#!/usr/bin/env bash
# Plantilla del aviso de los backups. NO va dentro de un repo: es una sola copia por servidor,
# en /home/github-runner/avisar.sh (dueño github-runner, 700), y la usan backup.sh y
# verificar-backup.sh de todos los proyectos. Uso: avisar.sh "mensaje".
#
# Esta version manda el mensaje por POST a un webhook generico (ntfy, un bot, una automatizacion
# propia...). La URL va en /home/github-runner/avisar.env (600), nunca en un repo:
#   AVISO_URL=https://...
# Cambiar el `curl` por lo que use cada operador; lo unico que importa es el contrato:
# $1 = mensaje, y salir siempre en silencio si no se puede avisar.
set -uo pipefail

msg="${1:-aviso sin mensaje}"
host=$(hostname)
[ -f /home/github-runner/avisar.env ] && . /home/github-runner/avisar.env

if [ -n "${AVISO_URL:-}" ]; then
  curl -fsS --max-time 15 -d "[$host] $msg" "$AVISO_URL" >/dev/null \
    || echo "[$(date +'%F %T')] no se pudo enviar el aviso: $msg" >&2
else
  echo "[$(date +'%F %T')] AVISO (sin AVISO_URL, solo log): $msg" >&2
fi
exit 0
