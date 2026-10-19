#!/usr/bin/env bash
# Registra (o quita) la ruta del Cloudflare Tunnel de un proyecto. NO va dentro de un repo: se
# instala UNA vez por servidor como /usr/local/sbin/tunel-agregar (dueño root, 755), y el deploy lo
# llama con sudo. Ver ci-cd-deployment-pipeline.md §2.6 para la instalacion.
#
#   sudo tunel-agregar <repo>             # agrega api-<repo>.<dominio> -> http://localhost:<puerto>
#                                         #   (o <TUNEL_HOST> si el .env del proyecto lo define)
#   sudo tunel-agregar --quitar <repo>    # quita la ruta (solo si la creo este script)
#
# Por que es un script de root FUERA del repo y recibe solo el nombre del repo:
# - Si sudoers permitiera correr el scripts/tunel.sh del repo, quien pueda hacer push a ese repo
#   editaria el script y obtendria root. Este archivo lo instala una persona y no cambia con un push.
# - El llamador (github-runner) NO elige hostname, puerto ni dominio: el dominio sale de
#   /etc/tunel-agregar.conf (root), el puerto del .env del proyecto en env-backups/<repo>/ y se exige
#   que lo publique un contenedor <PROJECT_PREFIX>-* que este corriendo (no se enruta a un puerto
#   cualquiera). Es defensa en profundidad: github-runner ya esta en el grupo docker.
#
# Que hace, en orden, y por que:
#   1. Valida el nombre del repo y arma hostname y puerto (arriba).
#   2. Si la ruta ya esta con el mismo puerto: no hace NADA (ni DNS ni reinicio). El reinicio de
#      cloudflared corta unos segundos a TODOS los proyectos: solo se hace si el archivo cambio.
#   3. Copia de seguridad del config.yml, edicion en un temporal e `ingress validate` ANTES de
#      reemplazar nada. Inserta antes de la regla final (http_status:404); si no la encuentra, aborta.
#   4. `cloudflared tunnel route dns` (con el cert.pem de la configuracion: el runner no tiene el suyo).
#   5. Reinicia cloudflared; si no queda activo, restaura la copia y lo reinicia otra vez.
# Solo modifica entradas con su marcador "(tunel-agregar)": las que se escribieron a mano no se tocan.
#
# Nombre de la ruta: por defecto api-<repo>.<dominio>. Si el proyecto ya tenia otra ruta publica
# (p. ej. api-<otro-nombre>), se define TUNEL_HOST=<host completo> en su .env del servidor. Se valida
# igual que el resto: minusculas y UN solo nivel bajo el DOMINIO de /etc/tunel-agregar.conf. Un host
# que ya existe a mano en el config (sin marcador) no se toca: con el mismo puerto no hace nada.
#
# Pruebas (sin root, sin servidor): variables CONFIG, CONF_FILE, ENV_BASE y TUNEL_SIN_ROOT=1.
set -uo pipefail

# Reiniciar cloudflared corta la conexion de quien este conectado por el propio Tunnel (p. ej. una
# terminal web): ignorar el HUP evita que el script muera a mitad, despues del reinicio y antes de
# comprobar que cloudflared quedo activo.
trap '' HUP

CONFIG=${CONFIG:-/etc/cloudflared/config.yml}
CONF_FILE=${CONF_FILE:-/etc/tunel-agregar.conf}
ENV_BASE=${ENV_BASE:-/home/github-runner/env-backups}
MARCA="(tunel-agregar)"
CATCHALL='^[[:space:]]*-[[:space:]]*service:[[:space:]]*http_status:404[[:space:]]*$'

die() { echo "❌ tunel-agregar: $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || [ -n "${TUNEL_SIN_ROOT:-}" ] || die "hay que correrlo con sudo."

modo=agregar
if [ "${1:-}" = "--quitar" ]; then modo=quitar; shift; fi
repo_in=${1:-}
[ -n "$repo_in" ] || die "uso: tunel-agregar [--quitar] <repo>"

# 1. Nombre -> subdominio. Minusculas; '_' y '.' pasan a '-'; todo lo demas se rechaza.
repo=$(printf '%s' "$repo_in" | tr 'A-Z_.' 'a-z--')
printf '%s' "$repo" | grep -qE '^[a-z0-9]([a-z0-9-]{0,40}[a-z0-9])?$' || die "nombre de repo no valido: '$repo_in'"

# Configuracion del servidor (solo estas claves; el archivo no se ejecuta).
[ -f "$CONF_FILE" ] || die "falta $CONF_FILE (DOMINIO, TUNEL, ORIGINCERT): ver CI/CD §2.6."
leer_conf() { grep -m1 "^$1=" "$CONF_FILE" | cut -d= -f2- | tr -d '"\r'; }
DOMINIO=$(leer_conf DOMINIO); TUNEL=$(leer_conf TUNEL); ORIGINCERT=$(leer_conf ORIGINCERT)
[ -n "$DOMINIO" ] && [ -n "$TUNEL" ] || die "$CONF_FILE debe definir DOMINIO y TUNEL."
printf '%s' "$DOMINIO" | grep -qE '^[a-z0-9.-]+$' || die "DOMINIO no valido en $CONF_FILE"
host="api-$repo.$DOMINIO"
[ -f "$CONFIG" ] || die "no existe $CONFIG"

# .env del proyecto (puerto, prefijo y, opcional, TUNEL_HOST). Con --quitar puede no existir.
envf="$ENV_BASE/$repo_in/.env"
[ -f "$envf" ] || envf="$ENV_BASE/$repo/.env"
leer_env() { [ -f "$envf" ] && grep -m1 "^$1=" "$envf" | cut -d= -f2- | tr -d '"\r'; }
tunel_host=$(leer_env TUNEL_HOST || true)
if [ -n "$tunel_host" ]; then
  etiqueta=${tunel_host%".$DOMINIO"}
  [ "$etiqueta" != "$tunel_host" ] || die "TUNEL_HOST ('$tunel_host') debe terminar en .$DOMINIO"
  printf '%s' "$etiqueta" | grep -qE '^[a-z0-9]([a-z0-9-]{0,60}[a-z0-9])?$' \
    || die "TUNEL_HOST no valido: minusculas y un solo nivel bajo $DOMINIO (sin puntos extra)."
  host=$tunel_host
fi

# El 2>/dev/null va en el grupo { }: pegado al `exec` quedaria aplicado al resto del script y se
# perderian todos los mensajes de error posteriores (el script saldria con 1 sin decir por que).
{ exec 9>"${CONFIG}.lock"; } 2>/dev/null || exec 9>"/tmp/tunel-agregar.lock"
command -v flock >/dev/null 2>&1 && flock -w 60 9

# Puerto actual de la entrada de $host en el config ("" si no esta).
puerto_actual() {
  awk -v h="$host" '
    $0 ~ "^[[:space:]]*-[[:space:]]*hostname:[[:space:]]*" h "[[:space:]]*$" { f = 1; next }
    f && /service:/ { sub(/.*:/, ""); sub(/[^0-9].*/, ""); print; exit }
    f && /^[[:space:]]*-[[:space:]]/ { exit }' "$CONFIG"
}
# ¿La entrada de $host la creo este script? (el comentario con el marcador va justo arriba)
es_nuestra() { grep -B1 -E "hostname:[[:space:]]*${host}[[:space:]]*$" "$CONFIG" | head -1 | grep -qF "$MARCA"; }
existe() { grep -qE "^[[:space:]]*-[[:space:]]*hostname:[[:space:]]*${host}[[:space:]]*$" "$CONFIG"; }

# ---- --quitar ----------------------------------------------------------------
if [ "$modo" = quitar ]; then
  existe || { echo "✅ $host no esta en $CONFIG: nada que quitar."; exit 0; }
  es_nuestra || die "$host esta en el config pero NO lo creo tunel-agregar (sin marcador): se quita a mano."
  nuevo=$(mktemp)
  # La entrada son 3 lineas: comentario con el marcador, hostname y service (+ una linea en blanco).
  awk -v h="$host" '
    { l[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) if (l[i] ~ ("^[[:space:]]*-[[:space:]]*hostname:[[:space:]]*" h "[[:space:]]*$")) hi = i
      for (i = 1; i <= NR; i++) {
        if (hi && (i == hi - 1 || i == hi || i == hi + 1)) continue
        if (hi && i == hi + 2 && l[i] == "") continue
        print l[i]
      }
    }' "$CONFIG" > "$nuevo"
  accion="quitar"
else
  # 1b. Puerto y prefijo: del .env del proyecto, y deben estar publicados por un contenedor suyo.
  [ -f "$envf" ] || die "no encuentro el .env del proyecto en $ENV_BASE/$repo_in/"
  puerto=$(leer_env BACKEND_HOST_PORT); prefijo=$(leer_env PROJECT_PREFIX)
  printf '%s' "$puerto" | grep -qE '^[0-9]{4,5}$' || die "BACKEND_HOST_PORT no valido en $envf: '$puerto'"
  [ "$puerto" -ge 1024 ] && [ "$puerto" -le 65535 ] || die "puerto fuera de rango: $puerto"
  [ -n "$prefijo" ] || die "falta PROJECT_PREFIX en $envf"
  docker ps --format '{{.Names}}|{{.Ports}}' 2>/dev/null | awk -F'|' -v p="$puerto" -v pre="$prefijo-" '
      index($1, pre) == 1 { n = split($2, a, ", "); for (i = 1; i <= n; i++) if (a[i] ~ ("(^|:)" p "->")) found = 1 }
      END { exit !found }' \
    || die "ningun contenedor '$prefijo-*' en marcha publica el puerto $puerto: no se enruta a un puerto que el proyecto no esta sirviendo."

  # 2. Idempotencia.
  if existe; then
    actual=$(puerto_actual)
    if [ "$actual" = "$puerto" ]; then
      echo "✅ $host -> localhost:$puerto ya esta en el Tunnel: no se toca nada (sin reinicio)."
      exit 0
    fi
    es_nuestra || die "$host ya existe con otro puerto (${actual:-?}) y NO lo creo tunel-agregar: corregirlo a mano."
    nuevo=$(mktemp)
    awk -v h="$host" -v p="$puerto" '
      $0 ~ ("^[[:space:]]*-[[:space:]]*hostname:[[:space:]]*" h "[[:space:]]*$") { f = 1; print; next }
      f && /service:/ { sub(/:[0-9]+[[:space:]]*$/, ":" p); f = 0 }
      { print }' "$CONFIG" > "$nuevo"
    accion="actualizar"
  else
    grep -qE "$CATCHALL" "$CONFIG" || die "no encuentro la regla final 'service: http_status:404' en $CONFIG: no se adivina donde insertar."
    nuevo=$(mktemp)
    # Si la regla final tiene un comentario arriba ("# Catch-all..."), el bloque va antes de ese
    # comentario, para que no quede entre la regla y su comentario.
    awk -v h="$host" -v p="$puerto" -v r="$repo" -v m="$MARCA" -v c="$CATCHALL" '
      { l[NR] = $0 }
      END {
        for (i = 1; i <= NR; i++) if (!ci && l[i] ~ c) ci = i
        pos = ci; if (ci > 1 && l[ci - 1] ~ /^[[:space:]]*#/) pos = ci - 1
        for (i = 1; i <= NR; i++) {
          if (i == pos) { print "  # " r " " m; print "  - hostname: " h; print "    service: http://localhost:" p; print "" }
          print l[i]
        }
      }' "$CONFIG" > "$nuevo"
    accion="agregar"
  fi
fi

# 3. Validar el temporal ANTES de tocar el real.
if ! cloudflared tunnel --config "$nuevo" ingress validate >/dev/null 2>&1; then
  rm -f "$nuevo"; die "el config resultante no pasa 'ingress validate'; no se toco $CONFIG."
fi

bak="$CONFIG.bak-$(date +%Y%m%d-%H%M%S)"
cp -p "$CONFIG" "$bak"
cat "$nuevo" > "$CONFIG"; rm -f "$nuevo"
# Quedan las 10 copias mas nuevas. El nombre lleva la fecha (bak-AAAAMMDD-HHMMSS): el glob ya sale
# ordenado de la mas vieja a la mas nueva, sin parsear `ls` ni partir rutas con espacios.
copias=("$CONFIG".bak-*)
[ ${#copias[@]} -le 10 ] || rm -f -- "${copias[@]:0:${#copias[@]}-10}"
echo "✅ $accion: $host${puerto:+ -> localhost:$puerto}   (copia: $bak)"

# 4. DNS (solo al agregar: no existe `route dns` para borrar; el CNAME se quita en el panel).
if [ "$accion" = agregar ]; then
  if [ -n "$ORIGINCERT" ] && [ -f "$ORIGINCERT" ]; then
    if salida=$(cloudflared tunnel --origincert "$ORIGINCERT" route dns "$TUNEL" "$host" 2>&1); then
      echo "✅ DNS: $host -> tunel $TUNEL"
    else
      case "$salida" in
        *"already exists"*) echo "ℹ️  DNS: el registro ya existia." ;;
        *) echo "⚠️  route dns fallo: $salida"; echo "   La ruta quedo en el config; crear el CNAME a mano o repetir." ;;
      esac
    fi
  else
    echo "⚠️  Sin ORIGINCERT valido en $CONF_FILE: crear el CNAME a mano (cloudflared tunnel route dns $TUNEL $host)."
  fi
fi

# 5. Reiniciar (el archivo cambio) y comprobar; si no queda activo, volver atras.
systemctl restart cloudflared 2>/dev/null
if systemctl is-active --quiet cloudflared 2>/dev/null; then
  echo "✅ cloudflared reiniciado y activo."
else
  echo "❌ cloudflared no quedo activo: se restaura la copia anterior." >&2
  cat "$bak" > "$CONFIG"
  systemctl restart cloudflared 2>/dev/null
  systemctl is-active --quiet cloudflared 2>/dev/null && echo "↩️  Restaurado y activo." >&2 || echo "❌ Tampoco levanto con la copia: intervencion manual (journalctl -u cloudflared)." >&2
  exit 1
fi
