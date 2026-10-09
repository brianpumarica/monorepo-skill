#!/usr/bin/env bash
# Alerta si el ultimo backup de un proyecto es mas viejo que MAX_HORAS (o no existe). Cada repo lo
# copia como scripts/verificar-backup.sh y lo corre el cron versionado una vez al dia, DESPUES
# del horario del backup. Uso:  verificar-backup.sh <repo>
#
# Existe porque backup.sh solo puede avisar de lo que le pasa mientras corre: si el cron
# apunta a una ruta muerta, el usuario no existe o el crontab nunca se instalo, backup.sh ni
# arranca y nadie se entera. Este script mira el resultado, no el proceso.
set -uo pipefail

REPO_NAME="${1:?Uso: verificar-backup.sh <repo>}"
MAX_HORAS="${MAX_HORAS:-36}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups/$REPO_NAME}"
AVISAR="${AVISAR:-/home/github-runner/avisar.sh}"

avisar() { [ -x "$AVISAR" ] && "$AVISAR" "$1" || true; }

# Solo el nivel raiz: pre-deploy/ tiene su propia rotacion y no cuenta como backup diario.
reciente=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "db_${REPO_NAME}_*.sql.gz" -mmin -$((MAX_HORAS * 60)) 2>/dev/null | head -1)

if [ -n "$reciente" ]; then
  echo "[$(date +'%F %T')] ✅ $REPO_NAME: hay backup de menos de ${MAX_HORAS} h ($(basename "$reciente"))"
  exit 0
fi

ultimo=$(ls -1t "$BACKUP_DIR"/db_"${REPO_NAME}"_*.sql.gz 2>/dev/null | head -1)
if [ -n "$ultimo" ]; then detalle="el ultimo es $(basename "$ultimo")"; else detalle="no hay ninguno en $BACKUP_DIR"; fi
msg="❌ $REPO_NAME: sin backup de menos de ${MAX_HORAS} h ($detalle). Revisar el cron y backup.log"
echo "[$(date +'%F %T')] $msg"
avisar "$msg"
exit 1
