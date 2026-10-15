#!/usr/bin/env bash
# Pruebas de references/tunel-agregar.sh: sin root, sin cloudflared ni systemd reales.
. "$(dirname "$0")/lib.sh"

SCRIPT="$REF/tunel-agregar.sh"
CFG="$T/config.yml"; CONF="$T/tunel.conf"; ENVB="$T/env"; CF_LOG="$T/cf.log"
DOCKER_PS=$'app-backend|127.0.0.1:8101->8000/tcp\notro-backend|127.0.0.1:8102->8000/tcp\nmalo-backend|127.0.0.1:8103->8000/tcp'

# Config de partida: una ruta escrita a mano (sin marcador) + la regla final con su comentario.
reset() {
  printf 'DOMINIO=ejemplo.test\nTUNEL=t1\nORIGINCERT=/no/existe\n' > "$CONF"
  printf 'ingress:\n  - hostname: api-legacy.ejemplo.test\n    service: http://localhost:9000\n\n  # Catch-all\n  - service: http_status:404\n' > "$CFG"
  rm -rf "$ENVB" "$CFG".bak-* "$CFG.lock" "$CF_LOG"*; : > "$CF_LOG"
  mkdir -p "$ENVB"/{mi-repo,otro,malo,sinprefijo}
  printf 'PROJECT_PREFIX=app\nBACKEND_HOST_PORT=8101\n' > "$ENVB/mi-repo/.env"
  printf 'PROJECT_PREFIX=otro\nBACKEND_HOST_PORT=8102\nTUNEL_HOST=api-alias.ejemplo.test\n' > "$ENVB/otro/.env"
  printf 'PROJECT_PREFIX=malo\nBACKEND_HOST_PORT=8103\n' > "$ENVB/malo/.env"
  printf 'BACKEND_HOST_PORT=8101\n' > "$ENVB/sinprefijo/.env"
}
run() {
  OUT=$(env PATH="$STUBS:$PATH" CF_LOG="$CF_LOG" DOCKER_PS="$DOCKER_PS" TUNEL_SIN_ROOT=1 \
    CONFIG="$CFG" CONF_FILE="$CONF" ENV_BASE="$ENVB" "$@" bash "$SCRIPT" 2>&1)
  ST=$?
}
# runx VAR=valor... -- args   (variables extra para el caso)
runx() {
  local extra=()
  while [ "$1" != "--" ]; do extra+=("$1"); shift; done; shift
  OUT=$(env PATH="$STUBS:$PATH" CF_LOG="$CF_LOG" DOCKER_PS="$DOCKER_PS" TUNEL_SIN_ROOT=1 \
    CONFIG="$CFG" CONF_FILE="$CONF" ENV_BASE="$ENVB" "${extra[@]}" bash "$SCRIPT" "$@" 2>&1)
  ST=$?
}
reinicios() { grep -c 'systemctl restart' "$CF_LOG" || true; }

titulo "nombre por defecto: api-<repo>.<dominio>"
reset; runx -- mi-repo
igual "sale con 0" 0 "$ST"
contiene "agrega api-mi-repo.ejemplo.test -> localhost:8101" "$OUT" 'agregar: api-mi-repo.ejemplo.test -> localhost:8101'
contiene "queda en el config con su marcador" "$(cat "$CFG")" '# mi-repo \(tunel-agregar\)'
contiene "el bloque va ANTES del comentario del catch-all" "$(grep -n 'mi-repo\|Catch-all' "$CFG" | tr '\n' ' ')" 'mi-repo.*Catch-all'
contiene "la ruta escrita a mano sigue intacta" "$(cat "$CFG")" 'api-legacy.ejemplo.test'
igual "reinicio cloudflared una vez" 1 "$(reinicios)"
existe_archivo "dejo copia de seguridad" "$(primero "$CFG".bak-*)"

titulo "idempotencia: la segunda corrida no reinicia"
: > "$CF_LOG"; runx -- mi-repo
igual "sale con 0" 0 "$ST"
contiene "avisa que no toca nada" "$OUT" 'ya esta en el Tunnel: no se toca nada'
igual "no reinicia cloudflared" 0 "$(reinicios)"

titulo "TUNEL_HOST: un proyecto que ya tenia otra ruta"
reset; runx -- otro
igual "sale con 0" 0 "$ST"
contiene "usa el host del .env, no api-otro" "$OUT" 'agregar: api-alias.ejemplo.test -> localhost:8102'
no_contiene "no crea api-otro" "$(cat "$CFG")" 'api-otro'
printf 'PROJECT_PREFIX=otro\nBACKEND_HOST_PORT=8102\nTUNEL_HOST="api-alias.ejemplo.test"\n' > "$ENVB/otro/.env"
: > "$CF_LOG"; runx -- otro
contiene "acepta el valor entre comillas (ya existe: idempotente)" "$OUT" 'ya esta en el Tunnel'

titulo "TUNEL_HOST invalido"
for caso in 'a.b.ejemplo.test|un solo nivel' 'api-x.otro.com|debe terminar en' 'API-X.ejemplo.test|un solo nivel'; do
  host=${caso%%|*}; esperado=${caso#*|}
  reset; printf 'PROJECT_PREFIX=malo\nBACKEND_HOST_PORT=8103\nTUNEL_HOST=%s\n' "$host" > "$ENVB/malo/.env"
  cp "$CFG" "$T/antes.yml"; runx -- malo
  igual "$host: sale con 1" 1 "$ST"
  contiene "$host: explica el motivo" "$OUT" "$esperado"
  igual "$host: no toca el config" "$(cat "$T/antes.yml")" "$(cat "$CFG")"
done

titulo "--quitar"
reset; runx -- otro >/dev/null; : > "$CF_LOG"; runx -- --quitar otro
igual "sale con 0" 0 "$ST"
no_contiene "saca la ruta de TUNEL_HOST" "$(cat "$CFG")" 'api-alias'
contiene "no toca la ruta escrita a mano" "$(cat "$CFG")" 'api-legacy.ejemplo.test'
contiene "conserva el catch-all" "$(cat "$CFG")" 'http_status:404'
reset; printf 'PROJECT_PREFIX=x\nBACKEND_HOST_PORT=9000\nTUNEL_HOST=api-legacy.ejemplo.test\n' > "$ENVB/malo/.env"
runx -- --quitar malo
igual "una ruta a mano (sin marcador) NO se quita: sale con 1" 1 "$ST"
contiene "dice que se quita a mano" "$OUT" 'NO lo creo tunel-agregar'
contiene "la ruta sigue ahi" "$(cat "$CFG")" 'api-legacy.ejemplo.test'
reset; runx -- --quitar mi-repo
igual "quitar algo que no esta: sale con 0" 0 "$ST"
contiene "dice que no hay nada que quitar" "$OUT" 'nada que quitar'

titulo "rutas escritas a mano (sin marcador)"
reset; printf 'PROJECT_PREFIX=app\nBACKEND_HOST_PORT=8101\nTUNEL_HOST=api-legacy.ejemplo.test\n' > "$ENVB/mi-repo/.env"
runx -- mi-repo
igual "otro puerto: sale con 1" 1 "$ST"
contiene "otro puerto: el mensaje SE VE (antes se perdia en /dev/null)" "$OUT" 'ya existe con otro puerto \(9000\)'
sed -i 's/localhost:9000/localhost:8101/' "$CFG"; : > "$CF_LOG"; runx -- mi-repo
igual "mismo puerto: sale con 0" 0 "$ST"
igual "mismo puerto: no reinicia" 0 "$(reinicios)"

titulo "validaciones de entrada"
reset; runx -- 'Mi Repo!'
igual "nombre de repo no valido: sale con 1" 1 "$ST"
contiene "nombre de repo no valido: lo dice" "$OUT" 'nombre de repo no valido'
reset; runx --
igual "sin argumentos: sale con 1" 1 "$ST"
contiene "sin argumentos: muestra el uso" "$OUT" 'uso: tunel-agregar'
reset; runx -- sinprefijo
igual "sin PROJECT_PREFIX: sale con 1" 1 "$ST"
contiene "sin PROJECT_PREFIX: lo dice" "$OUT" 'falta PROJECT_PREFIX'
reset; runx DOCKER_PS=$'otro-backend|127.0.0.1:8102->8000/tcp' -- mi-repo
igual "puerto no publicado por un contenedor del proyecto: sale con 1" 1 "$ST"
contiene "puerto no publicado: lo dice" "$OUT" "ningun contenedor 'app-\*' en marcha"
reset; runx -- noexiste
igual "repo sin .env: sale con 1" 1 "$ST"

titulo "DNS: route dns solo con un ORIGINCERT valido"
CERT="$T/cert.pem"; : > "$CERT"
# dns [VAR=valor ...]  ->  agrega mi-repo con un cert que existe
dns() { reset; sed -i "s#^ORIGINCERT=.*#ORIGINCERT=$CERT#" "$CONF"; runx "$@" -- mi-repo; }
dns
igual "sale con 0" 0 "$ST"
contiene "crea el CNAME" "$OUT" '✅ DNS: api-mi-repo.ejemplo.test -> tunel t1'
contiene "  con el cert de la configuracion" "$(cat "$CF_LOG")" '--origincert .*cert\.pem route dns t1 api-mi-repo\.ejemplo\.test'
dns CF_DNS_FALLA=1 CF_DNS_SALIDA='Failed: record already exists'
igual "el CNAME ya existia: sale con 0" 0 "$ST"
contiene "  lo dice sin alarmar" "$OUT" 'el registro ya existia'
no_contiene "  ni lo da por fallado" "$OUT" 'route dns fallo'
dns CF_DNS_FALLA=1 CF_DNS_SALIDA='error de red'
igual "otra falla del DNS: sale con 0 (la ruta ya quedo en el config)" 0 "$ST"
contiene "  avisa con la salida de cloudflared" "$OUT" 'route dns fallo: error de red'
no_contiene "  sin el ✅" "$OUT" '✅ DNS'
reset; runx -- mi-repo
contiene "sin ORIGINCERT valido: pide el CNAME a mano" "$OUT" 'Sin ORIGINCERT valido'
no_contiene "  y no llama a route dns" "$(cat "$CF_LOG")" 'route dns'

titulo "copias del config: quedan las 10 mas nuevas"
# viejas <config>  ->  12 copias de 2020 (el nombre lleva la fecha)
viejas() { local i; for i in 01 02 03 04 05 06 07 08 09 10 11 12; do echo "vieja $i" > "$1.bak-20200101-0000$i"; done; }
reset; viejas "$CFG"; runx -- mi-repo
copias=("$CFG".bak-*)
igual "quedan 10" 10 "${#copias[@]}"
no_existe_archivo "borra la mas vieja" "$CFG.bak-20200101-000001"
no_existe_archivo "  y la tercera" "$CFG.bak-20200101-000003"
existe_archivo "conserva la cuarta" "$CFG.bak-20200101-000004"
existe_archivo "conserva la recien hecha" "$(printf '%s\n' "$OUT" | sed -n 's/.*(copia: \(.*\))$/\1/p')"
reset; D="$T/con espacio"; mkdir -p "$D"; cp "$CFG" "$D/config.yml"; rm -f "$D"/config.yml.bak-*
viejas "$D/config.yml"; runx CONFIG="$D/config.yml" -- mi-repo
copias=("$D"/config.yml.bak-*)
igual "con espacios en la ruta tambien rota" 10 "${#copias[@]}"

titulo "seguridad ante fallas de cloudflared"
reset; cp "$CFG" "$T/antes.yml"; runx CF_VALIDATE_FALLA=1 -- mi-repo
igual "ingress validate falla: sale con 1" 1 "$ST"
contiene "ingress validate falla: lo dice" "$OUT" "no pasa 'ingress validate'"
igual "ingress validate falla: el config real no se toca" "$(cat "$T/antes.yml")" "$(cat "$CFG")"
reset; cp "$CFG" "$T/antes.yml"; runx SYSTEMCTL_FALLA=1 -- mi-repo
igual "no queda activo ni con la copia: sale con 1" 1 "$ST"
contiene "pide intervencion manual" "$OUT" 'intervencion manual'
igual "restaura la copia anterior" "$(cat "$T/antes.yml")" "$(cat "$CFG")"
reset; cp "$CFG" "$T/antes.yml"; runx SYSTEMCTL_FALLA_UNA=1 -- mi-repo
igual "falla una vez: sale con 1" 1 "$ST"
contiene "falla una vez: restaura y queda activo" "$OUT" 'Restaurado y activo'
igual "falla una vez: el config vuelve al original" "$(cat "$T/antes.yml")" "$(cat "$CFG")"

terminar
