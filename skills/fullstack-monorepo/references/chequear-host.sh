#!/usr/bin/env bash
# Chequeos de convivencia en el host compartido. Cada repo lo copia como scripts/chequear-host.sh.
# Corre en el servidor, como el usuario del runner, desde la carpeta del repo y con el .env ya
# cargado en el workspace (el deploy lo copia antes). No hay un registro escrito a mano de
# puertos ni de horarios: el registro es el servidor mismo (contenedores publicados y crontab),
# que no se desactualiza ni lleva nombres de proyectos en un repo publico.
#
#   chequear-host.sh            # = puertos + horario; lo usa el deploy ANTES de tocar nada
#   chequear-host.sh puertos    # falla (exit 1) si un puerto del .env ya lo usa OTRO proyecto
#   chequear-host.sh horario    # avisa si el backup de este repo pisa el de otro
#   chequear-host.sh libre      # imprime el proximo horario de backup libre (para el alta)
#
# Reglas:
# - Solo lectura. No para, no crea, no borra nada.
# - "Otro proyecto" = un contenedor cuyo nombre NO empieza con $PROJECT_PREFIX-. Los
#   contenedores propios no cuentan: un redeploy vuelve a tomar su mismo puerto.
# - Un puerto ocupado por algo que no es un contenedor (ss) tambien es conflicto, salvo que lo
#   tenga un contenedor propio.
set -uo pipefail

modo=${1:-todo}
PORT_VARS=${PORT_VARS:-"BACKEND_HOST_PORT DB_HOST_PORT FRONTEND_HOST_PORT"}
SLOT_INICIO=${SLOT_INICIO:-180}    # 03:00, en minutos desde medianoche
SLOT_PASO=${SLOT_PASO:-10}         # un backup cada 10 minutos
SLOT_MAX=${SLOT_MAX:-360}          # hasta las 06:00

[ -f .env ] || { echo "❌ No hay .env en $PWD (el deploy lo copia antes de este paso)."; exit 1; }
set -a; . ./.env; set +a
prefijo=${PROJECT_PREFIX:-}
repo=${REPO_NAME:-$(basename "$PWD")}

puertos() {
  local mal=0 var p duenos
  local tabla; tabla=$(docker ps --format '{{.Names}}|{{.Ports}}' 2>/dev/null)
  for var in $PORT_VARS; do
    p=${!var:-}
    [ -n "$p" ] || continue
    # Contenedores que publican ese puerto del host: "0.0.0.0:3004->3004/tcp" o "127.0.0.1:5434->5432/tcp".
    duenos=$(printf '%s\n' "$tabla" | awk -F'|' -v p="$p" '
      { n = split($2, a, ", "); for (i = 1; i <= n; i++) if (a[i] ~ ("(^|:)" p "->")) { print $1; break } }')
    if [ -n "$duenos" ]; then
      ajeno=$(printf '%s\n' "$duenos" | grep -v "^${prefijo}-" || true)
      if [ -n "$ajeno" ]; then
        echo "❌ $var=$p ya lo publica otro proyecto: $(echo "$ajeno" | tr '\n' ' ')"
        mal=1
      else
        echo "✅ $var=$p (lo tiene este mismo proyecto: redeploy)"
      fi
    elif command -v ss >/dev/null 2>&1 && [ -n "$(ss -ltnH "sport = :$p" 2>/dev/null)" ]; then
      echo "❌ $var=$p lo esta escuchando un proceso que no es un contenedor de este proyecto"
      mal=1
    else
      echo "✅ $var=$p libre"
    fi
  done
  [ "$mal" -eq 0 ] || { echo "   Elegir otro puerto en el .env del servidor: docker ps --format 'table {{.Names}}\t{{.Ports}}'"; return 1; }
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

case "$modo" in
  puertos) puertos ;;
  horario) horario ;;
  libre)   libre ;;
  todo)    rc=0; puertos || rc=1; horario; exit $rc ;;
  *) echo "Uso: chequear-host.sh [puertos|horario|libre]"; exit 1 ;;
esac
