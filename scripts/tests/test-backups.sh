#!/usr/bin/env bash
# Pruebas de los tres scripts del circuito de backups:
#   backup.sh           el volcado diario (se copia ajustando SOLO las variables de "Configuracion")
#   verificar-backup.sh alerta si no hay un backup reciente
#   avisar.sh           el canal de aviso
# docker y curl son falsos; las fechas viejas se fabrican con `touch -d`.
. "$(dirname "$0")/lib.sh"

BK="$T/backups"                 # carpeta de backups del proyecto de prueba
AVISOS="$T/avisos.log"          # lo que recibio el "avisar.sh" falso
DALL="$T/docker-all.log"
UP="/app/uploads"
export DOCKER_ALL_LOG="$DALL" FAKE_POSTGRES_USER=app_user FAKE_POSTGRES_DB=app_db

# Un avisar.sh falso: anota el mensaje que recibe. (El "$1" entre comillas simples es del script generado.)
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\necho "$1" >> "%s"\n' "$AVISOS" > "$T/avisar-ok.sh"; chmod +x "$T/avisar-ok.sh"
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\necho "$1" >> "%s"\nexit 1\n' "$AVISOS" > "$T/avisar-roto.sh"; chmod +x "$T/avisar-roto.sh"

# instalar [con-archivos]: copia backup.sh ajustando las variables, como lo haria un repo.
instalar() {
  local up=""
  [ "${1:-}" = con-archivos ] && up="$UP"
  sed -e 's|^REPO_NAME="CAMBIAR"|REPO_NAME="demo"|' \
      -e 's|^DB_CONTAINER="CAMBIAR-database"|DB_CONTAINER="demo-database"|' \
      -e 's|^API_CONTAINER="CAMBIAR-back-prod"|API_CONTAINER="demo-back-prod"|' \
      -e "s|^UPLOADS_DEST=\"\"|UPLOADS_DEST=\"$up\"|" "$REF/backup.sh" > "$T/backup.sh"
  grep -q 'REPO_NAME="demo"' "$T/backup.sh" || fail "no pude ajustar la configuracion de backup.sh"
}
estado_limpio() { rm -rf "$BK" "$AVISOS" "$DALL"; : > "$AVISOS"; : > "$DALL"; }
# backup [VAR=valor ...]  ->  OUT, ST
backup() {
  OUT=$(env PATH="$STUBS:$PATH" BACKUP_DIR="$BK" AVISAR="$T/avisar-ok.sh" DOCKER_PS="${DOCKER_PS-demo-database|}" "$@" bash "$T/backup.sh" 2>&1 < /dev/null)
  ST=$?
}
dbs() { find "$BK" -maxdepth 1 -name 'db_demo_*.sql.gz' 2>/dev/null; }
vieja() { mkdir -p "$(dirname "$1")"; : > "$1"; touch -d "$2 days ago" "$1"; }

# ================================== backup.sh ==================================
titulo "backup.sh: caso normal (solo base)"
estado_limpio; instalar; backup
igual "sale con 0" 0 "$ST"
igual "crea un solo volcado db_demo_*.sql.gz" 1 "$(dbs | wc -l | tr -d ' ')"
existe_archivo "el volcado no esta vacio" "$(dbs | head -1)"
igual "el volcado es un gzip valido" 0 "$(gzip -t "$(dbs | head -1)" 2>/dev/null; echo $?)"
contiene "el volcado trae el contenido de pg_dump" "$(gzip -dc "$(dbs | head -1)")" 'CREATE TABLE t'
igual "sin UPLOADS_DEST no hay archivo de archivos" 0 "$(find "$BK" -name 'files_*' | wc -l | tr -d ' ')"
contiene "dice que termino" "$OUT" 'Listo\.'
igual "no avisa nada si todo salio bien" "" "$(cat "$AVISOS")"
modo "la carpeta de backups queda 700" "$BK" 700
contiene "usuario y base salen del contenedor (no del .env)" "$(cat "$DALL")" 'pg_dump -U app_user -d app_db'
no_contiene "NUNCA docker exec -t (la TTY corrompe el volcado)" "$(grep 'docker exec' "$DALL")" 'exec (-[a-z]*t|-t)'
no_contiene "no para ni borra ningun contenedor" "$(cat "$DALL")" 'docker (stop|kill|rm|restart|compose|down)'

titulo "backup.sh: falla y avisa"
estado_limpio; instalar; backup DOCKER_PS=""
igual "contenedor de la base caido: sale con 1" 1 "$ST"
contiene "lo dice en el log" "$OUT" "El contenedor 'demo-database' no esta corriendo"
contiene "AVISA (un backup que falla en silencio no es un backup)" "$(cat "$AVISOS")" 'Backup de demo fallo \(codigo 1\)'
igual "no deja volcados" 0 "$(dbs | wc -l | tr -d ' ')"
estado_limpio; backup DOCKER_DUMP_FALLA=1
igual "pg_dump falla: sale con 1" 1 "$ST"
contiene "  lo dice" "$OUT" 'El volcado fallo o quedo vacio/corrupto'
igual "  no deja un volcado a medias" 0 "$(dbs | wc -l | tr -d ' ')"
contiene "  avisa" "$(cat "$AVISOS")" 'Backup de demo fallo'
for caso in 'vacio (pg_dump termina bien pero no imprime nada)|' 'sin la cabecera de pg_dump (texto cualquiera)|esto no es un volcado'; do
  nombre=${caso%%|*}; contenido=${caso#*|}
  estado_limpio; backup DOCKER_DUMP="$contenido"
  igual "volcado $nombre: sale con 1 (un gzip de 20 bytes NO es un backup)" 1 "$ST"
  contiene "  lo dice" "$OUT" 'El volcado fallo o quedo vacio/corrupto'
  igual "  no deja el archivo" 0 "$(dbs | wc -l | tr -d ' ')"
  contiene "  avisa" "$(cat "$AVISOS")" 'Backup de demo fallo'
done
estado_limpio; GRANDE="$T/dump-grande.sql"   # en archivo: Linux no acepta 400 KB en una variable de entorno
{ echo "-- PostgreSQL database dump"; head -c 400000 /dev/zero | tr '\0' 'x'; } > "$GRANDE"
backup DOCKER_DUMP_FILE="$GRANDE"
igual "volcado GRANDE (400 KB): sale con 0 (la verificacion no da falsos fallos por SIGPIPE)" 0 "$ST"
igual "  queda el volcado" 1 "$(dbs | wc -l | tr -d ' ')"
# Con SIGPIPE ignorado (como bajo sudo/cron en la Pi) gzip no muere callado: escribe
# "Broken pipe" en el log, que parece un error aunque el backup salio bien.
estado_limpio
OUT=$(trap '' PIPE; env PATH="$STUBS:$PATH" BACKUP_DIR="$BK" AVISAR="$T/avisar-ok.sh" DOCKER_PS="demo-database|" DOCKER_DUMP_FILE="$GRANDE" bash "$T/backup.sh" 2>&1 < /dev/null); ST=$?
igual "volcado GRANDE con SIGPIPE ignorado: sale con 0" 0 "$ST"
no_contiene "  el log no trae 'Broken pipe' de gzip" "$OUT" 'Broken pipe'
estado_limpio; instalar
OUT=$(env PATH="$STUBS:$PATH" BACKUP_DIR="$BK" AVISAR="$T/no-existe.sh" DOCKER_PS="" bash "$T/backup.sh" 2>&1 < /dev/null); ST=$?
igual "sin avisar.sh instalado: igual falla con el codigo original (1) y solo queda el log" 1 "$ST"
OUT=$(env PATH="$STUBS:$PATH" BACKUP_DIR="$BK" AVISAR="$T/avisar-roto.sh" DOCKER_PS="" bash "$T/backup.sh" 2>&1 < /dev/null); ST=$?
igual "avisar.sh que falla NO tapa el codigo de salida del backup" 1 "$ST"

titulo "backup.sh: archivos subidos"
estado_limpio; instalar con-archivos; backup
igual "sale con 0" 0 "$ST"
igual "crea el files_demo_*.tar.gz" 1 "$(find "$BK" -name 'files_demo_*.tar.gz' | wc -l | tr -d ' ')"
contiene "monta los volumenes del backend en SOLO LECTURA" "$(grep 'docker run' "$DALL")" '--volumes-from demo-back-prod:ro'
contiene "usa la imagen de la base (ya esta en disco)" "$(grep 'docker run' "$DALL")" 'postgres:16'
contiene "respalda la ruta indicada" "$(grep 'docker run' "$DALL")" "-C $UP"
estado_limpio; backup DOCKER_RUN_FALLA=1
igual "fallan los archivos: el backup de la base IGUAL termina bien (sale con 0)" 0 "$ST"
igual "  la base quedo respaldada" 1 "$(dbs | wc -l | tr -d ' ')"
igual "  no queda un files_ a medias" 0 "$(find "$BK" -name 'files_*' | wc -l | tr -d ' ')"
contiene "  pero AVISA que faltaron los archivos" "$(cat "$AVISOS")" 'NO los archivos de /app/uploads'

titulo "backup.sh: rotacion"
estado_limpio; instalar
vieja "$BK/db_demo_20200101_000000.sql.gz" 40
vieja "$BK/files_demo_20200101_000000.tar.gz" 40
vieja "$BK/db_demo_20260101_000000.sql.gz" 5
vieja "$BK/db_otro_20200101_000000.sql.gz" 90
vieja "$BK/pre-deploy/20200101-000000-abc1234.sql.gz" 90
vieja "$BK/notas.txt" 90
backup
igual "sale con 0" 0 "$ST"
no_existe_archivo "borra el db_ de este repo con mas de 30 dias" "$BK/db_demo_20200101_000000.sql.gz"
no_existe_archivo "borra el files_ de este repo con mas de 30 dias" "$BK/files_demo_20200101_000000.tar.gz"
existe_archivo "conserva el de 5 dias" "$BK/db_demo_20260101_000000.sql.gz"
existe_archivo "NO toca los backups de otro repo" "$BK/db_otro_20200101_000000.sql.gz"
existe_archivo "NO toca pre-deploy/ (tiene su propia rotacion)" "$BK/pre-deploy/20200101-000000-abc1234.sql.gz"
existe_archivo "NO toca archivos ajenos al patron" "$BK/notas.txt"
contiene "informa cuantos borro" "$OUT" 'Rotacion: 2 archivos de mas de 30 dias'
estado_limpio; vieja "$BK/db_demo_20200101_000000.sql.gz" 10; backup RETENTION_DAYS=7
no_existe_archivo "RETENTION_DAYS=7 borra uno de 10 dias" "$BK/db_demo_20200101_000000.sql.gz"
existe_archivo "el backup recien hecho nunca se rota" "$(dbs | head -1)"

# ============================ verificar-backup.sh ===============================
verifica() {
  OUT=$(env PATH="$STUBS:$PATH" BACKUP_DIR="$BK" AVISAR="$T/avisar-ok.sh" "$@" bash "$REF/verificar-backup.sh" 2>&1 < /dev/null)
  ST=$?
}
titulo "verificar-backup.sh"
estado_limpio; vieja "$BK/db_demo_x_reciente.sql.gz" 0
OUT=$(env PATH="$STUBS:$PATH" BACKUP_DIR="$BK" AVISAR="$T/avisar-ok.sh" bash "$REF/verificar-backup.sh" demo 2>&1 < /dev/null); ST=$?
igual "backup de hoy: sale con 0" 0 "$ST"
igual "  no avisa" "" "$(cat "$AVISOS")"
estado_limpio; vieja "$BK/db_demo_20200101_000000.sql.gz" 2
OUT=$(env PATH="$STUBS:$PATH" BACKUP_DIR="$BK" AVISAR="$T/avisar-ok.sh" bash "$REF/verificar-backup.sh" demo 2>&1 < /dev/null); ST=$?
igual "el ultimo tiene 2 dias (> 36 h): sale con 1" 1 "$ST"
contiene "  avisa con el nombre del ultimo" "$(cat "$AVISOS")" 'sin backup de menos de 36 h \(el ultimo es db_demo_20200101_000000.sql.gz\)'
OUT=$(env PATH="$STUBS:$PATH" BACKUP_DIR="$BK" AVISAR="$T/avisar-ok.sh" MAX_HORAS=72 bash "$REF/verificar-backup.sh" demo 2>&1 < /dev/null); ST=$?
igual "MAX_HORAS=72: el mismo backup de 2 dias ya sirve" 0 "$ST"
estado_limpio; mkdir -p "$BK"
OUT=$(env PATH="$STUBS:$PATH" BACKUP_DIR="$BK" AVISAR="$T/avisar-ok.sh" bash "$REF/verificar-backup.sh" demo 2>&1 < /dev/null); ST=$?
igual "carpeta sin ningun backup: sale con 1" 1 "$ST"
contiene "  lo dice" "$(cat "$AVISOS")" 'no hay ninguno en'
estado_limpio
OUT=$(env PATH="$STUBS:$PATH" BACKUP_DIR="$T/no-existe" AVISAR="$T/avisar-ok.sh" bash "$REF/verificar-backup.sh" demo 2>&1 < /dev/null); ST=$?
igual "la carpeta ni existe (cron roto): sale con 1 y avisa" 1 "$ST"
contiene "  avisa" "$(cat "$AVISOS")" 'sin backup'
estado_limpio; vieja "$BK/pre-deploy/db_demo_20260101_000000.sql.gz" 0; vieja "$BK/db_otro_20260101_000000.sql.gz" 0
OUT=$(env PATH="$STUBS:$PATH" BACKUP_DIR="$BK" AVISAR="$T/avisar-ok.sh" bash "$REF/verificar-backup.sh" demo 2>&1 < /dev/null); ST=$?
igual "un respaldo en pre-deploy/ o de OTRO repo no cuenta como el backup diario" 1 "$ST"
OUT=$(env PATH="$STUBS:$PATH" bash "$REF/verificar-backup.sh" 2>&1 < /dev/null); ST=$?
igual "sin argumentos: sale con 1" 1 "$ST"
contiene "  muestra el uso" "$OUT" 'Uso: verificar-backup.sh'

# ================================== avisar.sh ===================================
titulo "avisar.sh"
CLOG="$T/curl.log"
avisa() { : > "$CLOG"; OUT=$(env PATH="$STUBS:$PATH" CURL_LOG="$CLOG" "$@" 2>&1 < /dev/null); ST=$?; }
avisa bash "$REF/avisar.sh" "hola"
igual "sin AVISO_URL: sale con 0" 0 "$ST"
contiene "  deja solo el log" "$OUT" 'AVISO \(sin AVISO_URL, solo log\): hola'
igual "  no llama a curl" "" "$(cat "$CLOG")"
avisa env AVISO_URL=https://aviso.ejemplo.test/t bash "$REF/avisar.sh" "algo fallo"
igual "con AVISO_URL: sale con 0" 0 "$ST"
contiene "  hace POST del mensaje a la URL" "$(cat "$CLOG")" "curl -fsS --max-time 15 -d \[.*\] algo fallo https://aviso.ejemplo.test/t"
avisa env AVISO_URL=https://aviso.ejemplo.test/t CURL_FALLA=1 bash "$REF/avisar.sh" "algo fallo"
igual "curl falla: IGUAL sale con 0 (avisar nunca rompe a quien lo llama)" 0 "$ST"
contiene "  deja constancia en el log" "$OUT" 'no se pudo enviar el aviso: algo fallo'
avisa bash "$REF/avisar.sh"
contiene "sin mensaje: usa uno por defecto" "$OUT" 'aviso sin mensaje'

terminar
