#!/usr/bin/env bash
# Chequeos de convivencia en el host compartido. Cada repo lo copia como scripts/chequear-host.sh.
# Corre en el servidor, como el usuario del runner (github-runner), desde la carpeta del repo.
# No hay un registro escrito a mano de puertos ni de horarios: el registro es el servidor mismo
# (contenedores publicados, el .env de cada proyecto y el crontab), que no se desactualiza ni
# lleva nombres de proyectos a un repo publico.
#
#   chequear-host.sh alta       # ELEGIR: puertos y horario de backup libres para un proyecto nuevo
#   chequear-host.sh            # = puertos + horario; lo usa el deploy ANTES de tocar nada
#   chequear-host.sh puertos    # falla (exit 1) si un puerto del .env ya es de OTRO proyecto
#   chequear-host.sh horario    # avisa si el backup de este repo pisa el de otro
#   chequear-host.sh libre      # imprime solo el proximo horario de backup libre
#
# "alta" no necesita .env (es lo que se corre ANTES de crearlo). Los demas si: el deploy lo copia
# antes de este paso.
#
# Un puerto es de OTRO proyecto cuando lo cumple cualquiera de estas tres:
#   1. lo publica un contenedor cuyo nombre NO empieza con $PROJECT_PREFIX-;
#   2. figura en el .env de otro repo de env-backups/ (aunque ese proyecto este detenido: su
#      puerto sigue siendo suyo y volveria a chocar al levantarse);
#   3. lo esta escuchando un proceso que no es un contenedor de este proyecto.
# Un redeploy del mismo proyecto vuelve a tomar su mismo puerto y no cuenta como conflicto.
#
# Solo lectura: no para, no crea, no borra nada. Variables: ENV_BASE, PORT_VARS, y los rangos
# RANGO_BACKEND / RANGO_FRONTEND / RANGO_DB ("desde-hasta") que usa "alta".
set -uo pipefail

modo=${1:-todo}
ENV_BASE=${ENV_BASE:-/home/github-runner/env-backups}
PORT_VARS=${PORT_VARS:-"BACKEND_HOST_PORT DB_HOST_PORT FRONTEND_HOST_PORT"}
RANGO_BACKEND=${RANGO_BACKEND:-3000-3999}
RANGO_FRONTEND=${RANGO_FRONTEND:-8000-8999}
RANGO_DB=${RANGO_DB:-5400-5499}
SLOT_INICIO=${SLOT_INICIO:-180}    # 03:00, en minutos desde medianoche
SLOT_PASO=${SLOT_PASO:-10}         # un backup cada 10 minutos
SLOT_MAX=${SLOT_MAX:-360}          # hasta las 06:00

# El script vive en <repo>/scripts/: trabajar siempre desde la raiz del repo, se llame desde donde se
# llame (el log del deploy imprime la ruta completa para pegarla desde cualquier carpeta).
raiz=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd) || true
if [ -n "${raiz:-}" ] && [ -f "$raiz/.env.example" ]; then cd "$raiz"; fi
repo=${REPO_NAME:-$(basename "$PWD")}
prefijo=""
if [ "$modo" != alta ] && [ "$modo" != libre ]; then
  [ -f .env ] || { echo "❌ No hay .env en $PWD (el deploy lo copia antes de este paso)."; exit 1; }
  set -a; . ./.env; set +a
  prefijo=${PROJECT_PREFIX:-}
fi

# ¿Algo escucha en el puerto? ss si existe; si no, un intento de conexion (bash puro).
escuchando() {
  if command -v ss >/dev/null 2>&1; then [ -n "$(ss -ltnH "sport = :$1" 2>/dev/null)" ]
  else (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; fi
}

# Contenedores (todos los del host) que publican el puerto $1.
publicado_por() {
  docker ps --format '{{.Names}}|{{.Ports}}' 2>/dev/null | awk -F'|' -v p="$1" '
    { n = split($2, a, ", "); for (i = 1; i <= n; i++) if (a[i] ~ ("(^|:)" p "->")) { print $1; break } }'
}

# Repos (otros) cuyo .env guardado reserva el puerto $1 en alguna variable *_HOST_PORT.
reservado_por() {
  local d
  for d in "$ENV_BASE"/*/; do
    [ -f "${d}.env" ] || continue
    [ "$(basename "$d")" = "$repo" ] && continue
    grep -qE "^[A-Z_]*HOST_PORT=[\"']?$1[\"']?\$" "${d}.env" 2>/dev/null && basename "$d"
  done
}

puertos() {
  local mal=0 var p duenos ajeno res
  for var in $PORT_VARS; do
    p=${!var:-}
    [ -n "$p" ] || continue
    duenos=$(publicado_por "$p")
    ajeno=$(printf '%s\n' "$duenos" | grep -v "^${prefijo}-" | grep -v '^$' || true)
    res=$(reservado_por "$p" | tr '\n' ' ')
    if [ -n "$ajeno" ]; then
      echo "❌ $var=$p ya lo publica otro proyecto: $(echo "$ajeno" | tr '\n' ' ')"; mal=1
    elif [ -n "$res" ]; then
      echo "❌ $var=$p esta reservado en el .env de: $res(proyecto detenido o aun sin desplegar)"; mal=1
    elif [ -n "$duenos" ]; then
      echo "✅ $var=$p (lo tiene este mismo proyecto: redeploy)"
    elif escuchando "$p"; then
      echo "❌ $var=$p lo esta escuchando un proceso que no es un contenedor de este proyecto"; mal=1
    else
      echo "✅ $var=$p libre"
    fi
  done
  [ "$mal" -eq 0 ] || { echo "   Elegir otros: bash scripts/chequear-host.sh alta   (y cambiarlos en el .env del servidor)"; return 1; }
}

# Primer puerto del rango $1 ("desde-hasta") que nadie usa ni reservo. Los ya elegidos en esta
# misma corrida ($2...) se saltean, para no sugerir el mismo numero dos veces.
puerto_libre() {
  local desde=${1%-*} hasta=${1#*-} p x tomado
  shift
  for ((p = desde; p <= hasta; p++)); do
    tomado=0
    for x in "$@"; do [ "$x" = "$p" ] && tomado=1; done
    [ "$tomado" -eq 1 ] && continue
    [ -n "$(publicado_por "$p")" ] && continue
    [ -n "$(reservado_por "$p")" ] && continue
    escuchando "$p" && continue
    echo "$p"; return 0
  done
  return 1
}

# Minutos desde medianoche de cada linea de backup de OTROS proyectos en el crontab del usuario.
otros_horarios() {
  crontab -l 2>/dev/null | grep -v '^[[:space:]]*#' | grep 'backup\.sh' | grep -v "$repo" \
    | awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { print $2 * 60 + $1 }'
}
fmt() { printf '%02d:%02d' $(($1 / 60)) $(($1 % 60)); }
choca() {  # $1 = minuto del dia; imprime los horarios ajenos a menos de SLOT_PASO
  otros_horarios | awk -v t="$1" -v w="$SLOT_PASO" '{ d = $1 - t; if (d < 0) d = -d; if (d < w) print $1 }'
}

horario() {
  local propio t c
  # Horario de ESTE repo: la primera linea de backup.sh de scripts/crontab (formato: min hora ...).
  propio=$(grep -v '^[[:space:]]*#' scripts/crontab 2>/dev/null | grep 'backup\.sh' | head -1 \
    | awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { print $2 * 60 + $1 }')
  [ -n "$propio" ] || { echo "ℹ️  scripts/crontab no tiene una linea de backup.sh con hora fija: no se chequea el horario."; return 0; }
  c=$(choca "$propio")
  if [ -n "$c" ]; then
    echo "::warning::El backup de $repo ($(fmt "$propio")) cae a menos de ${SLOT_PASO} min del de otro proyecto ($(for t in $c; do printf '%s ' "$(fmt "$t")"; done | sed 's/ $//')). Dos pg_dump a la vez cargan la Pi; probar con: bash scripts/chequear-host.sh libre"
  else
    echo "✅ Backup de $repo a las $(fmt "$propio"): sin choque con otros proyectos"
  fi
}

libre() {
  local t=$SLOT_INICIO
  while [ "$t" -lt "$SLOT_MAX" ]; do
    [ -z "$(choca "$t")" ] && { echo "Proximo horario libre: $(fmt "$t")  ->  linea del crontab: $((t % 60)) $((t / 60)) * * *"; return 0; }
    t=$((t + SLOT_PASO))
  done
  echo "Sin horario libre entre $(fmt "$SLOT_INICIO") y $(fmt "$SLOT_MAX"); ampliar SLOT_MAX."; return 1
}

alta() {
  local b f d
  b=$(puerto_libre "$RANGO_BACKEND") || { echo "❌ Sin puerto libre en $RANGO_BACKEND"; return 1; }
  f=$(puerto_libre "$RANGO_FRONTEND" "$b") || { echo "❌ Sin puerto libre en $RANGO_FRONTEND"; return 1; }
  d=$(puerto_libre "$RANGO_DB" "$b" "$f") || { echo "❌ Sin puerto libre en $RANGO_DB"; return 1; }
  echo "Puertos libres en este servidor (para el .env de '$repo'):"
  echo "  BACKEND_HOST_PORT=$b"
  echo "  FRONTEND_HOST_PORT=$f   # solo si el frontend va en contenedor; con Vercel no se publica"
  echo "  DB_HOST_PORT=$d"
  libre
  echo "Es una foto de este momento: no reserva nada hasta que exista el .env. Si pasan dias, repetir 'alta'."
}

case "$modo" in
  alta)    alta ;;
  puertos) puertos ;;
  horario) horario ;;
  libre)   libre ;;
  todo)    rc=0; puertos || rc=1; horario; exit $rc ;;
  *) echo "Uso: chequear-host.sh [alta|puertos|horario|libre]"; exit 1 ;;
esac
