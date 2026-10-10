#!/usr/bin/env bash
# Backup diario de un proyecto en la Pi. Cada repo lo copia como scripts/backup.sh y ajusta
# SOLO las variables de "Configuracion". Lo corre el cron versionado (scripts/crontab) como el
# usuario del runner; cualquier usuario del grupo docker sirve.
#
# Reglas:
# 1. NUNCA `docker exec -t`: la TTY convierte LF en CRLF y corrompe el dump.
# 2. No para ningun contenedor: pg_dump es consistente en caliente.
# 3. No lee el .env del servidor (es 600 del usuario del runner y el cron de otro usuario no
#    puede abrirlo, que es como un backup fallo en silencio): usuario y base salen del
#    contenedor de la base, y los archivos subidos de los montajes del backend.
# 4. Rotacion para no llenar el disco del host compartido.
# 5. Si falla, AVISA: llama a $AVISAR (por defecto /home/github-runner/avisar.sh, plantilla en
#    avisar.sh) con el mensaje. Un backup que falla en silencio no es un backup. Si ese script
#    no existe, solo queda el log. verificar-backup.sh cubre el otro caso: que este script ni
#    siquiera corra.
set -eo pipefail

# --- Configuracion (lo unico que cambia por proyecto) -------------------------
REPO_NAME="CAMBIAR"                 # nombre del repo; define la carpeta y los archivos
DB_CONTAINER="CAMBIAR-database"     # contenedor de PostgreSQL
API_CONTAINER="CAMBIAR-back-prod"   # contenedor del backend que monta los archivos subidos
UPLOADS_DEST=""                     # ruta DENTRO del backend (ej. /app/uploads); vacio = sin archivos
RETENTION_DAYS="${RETENTION_DAYS:-30}"
AVISAR="${AVISAR:-/home/github-runner/avisar.sh}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups/$REPO_NAME}"
# -----------------------------------------------------------------------------

DATE=$(date +"%Y%m%d_%H%M%S")
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
# Avisar nunca debe romper el backup ni taparle su codigo de salida.
avisar() { [ -x "$AVISAR" ] && "$AVISAR" "$1" || true; }
# EXIT cubre tanto los `exit 1` explicitos como cualquier comando que `set -e` aborte.
# shellcheck disable=SC2154  # rc se asigna dentro del propio trap
trap 'rc=$?; [ "$rc" -eq 0 ] || avisar "❌ Backup de $REPO_NAME fallo (codigo $rc). Ver backup.log"' EXIT

log "==> Backup de $REPO_NAME"
docker ps --format '{{.Names}}' | grep -qx "$DB_CONTAINER" \
  || { log "❌ El contenedor '$DB_CONTAINER' no esta corriendo."; exit 1; }

DB_USER=$(docker exec "$DB_CONTAINER" printenv POSTGRES_USER)
DB_NAME=$(docker exec "$DB_CONTAINER" printenv POSTGRES_DB)

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# --- 1. Base de datos ---------------------------------------------------------
DB_FILE="$BACKUP_DIR/db_${REPO_NAME}_${DATE}.sql.gz"
log "Respaldando '$DB_NAME' desde '$DB_CONTAINER'..."
# Tres comprobaciones sobre el resultado: que no este vacio, que sea un gzip valido y que traiga la
# cabecera que pg_dump siempre escribe. Un pg_dump que termina "bien" sin imprimir nada comprime a
# 20 bytes: pasa las dos primeras y seria un backup vacio que parece sano. La cabecera se busca con
# sustitucion de procesos (no con un pipe): con `pipefail`, un `grep -q` que corta la lectura le
# daria SIGPIPE a gzip y marcaria como fallido un volcado grande y bueno.
if ! docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" -d "$DB_NAME" | gzip -9 > "$DB_FILE" \
   || [ ! -s "$DB_FILE" ] || ! gzip -t "$DB_FILE" \
   || ! grep -q 'PostgreSQL database dump' < <(gzip -dc "$DB_FILE"); then
  log "❌ El volcado fallo o quedo vacio/corrupto."
  rm -f "$DB_FILE"
  exit 1
fi
log "✅ Base: $DB_FILE ($(du -h "$DB_FILE" | cut -f1))"

# --- 2. Archivos subidos ------------------------------------------------------
# --volumes-from reutiliza los montajes del backend tal como estan (volumen con nombre o
# carpeta del host), sin tener que saber cual es cual. La imagen de la base ya esta en disco
# y trae tar y gzip.
if [ -n "$UPLOADS_DEST" ]; then
  FILES_FILE="$BACKUP_DIR/files_${REPO_NAME}_${DATE}.tar.gz"
  IMAGE=$(docker inspect --format '{{.Config.Image}}' "$DB_CONTAINER")
  if docker run --rm --volumes-from "$API_CONTAINER:ro" "$IMAGE" \
       tar -czf - -C "$UPLOADS_DEST" . > "$FILES_FILE" && gzip -t "$FILES_FILE"; then
    log "✅ Archivos: $FILES_FILE ($(du -h "$FILES_FILE" | cut -f1))"
  else
    log "⚠️ No se pudieron respaldar los archivos de $UPLOADS_DEST en '$API_CONTAINER'."
    avisar "⚠️ Backup de $REPO_NAME: la base se respaldo pero NO los archivos de $UPLOADS_DEST"
    rm -f "$FILES_FILE"
  fi
fi

# --- 3. Rotacion --------------------------------------------------------------
BORRADOS=$(find "$BACKUP_DIR" -type f \( -name "db_${REPO_NAME}_*.sql.gz" -o -name "files_${REPO_NAME}_*.tar.gz" \) \
  -mtime +"$RETENTION_DAYS" -print -delete | wc -l)
log "Rotacion: $BORRADOS archivos de mas de $RETENTION_DAYS dias eliminados."
log "==> Listo. $(find "$BACKUP_DIR" -type f | wc -l) archivos, $(du -sh "$BACKUP_DIR" | cut -f1) en $BACKUP_DIR"
