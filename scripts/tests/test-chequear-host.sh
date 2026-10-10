#!/usr/bin/env bash
# Pruebas de references/chequear-host.sh: puertos ajenos, reservas, procesos que escuchan, horarios.
. "$(dirname "$0")/lib.sh"

R="$T/mi-repo"; ENVB="$T/env"; CRON="$T/crontab"
mkdir -p "$R/scripts" "$ENVB/otro"
cp "$REF/chequear-host.sh" "$R/scripts/"

# nuevo_estado: .env de este proyecto (prefijo app), otro proyecto con 4001 reservado, nada escuchando
nuevo_estado() {
  printf 'PROJECT_PREFIX=app\nBACKEND_HOST_PORT=4100\nDB_HOST_PORT=4200\nFRONTEND_HOST_PORT=\n' > "$R/.env"
  printf 'BACKEND_HOST_PORT=4001\n' > "$ENVB/otro/.env"
  printf 'HOLA=1\n' > "$R/.env.example"
  : > "$CRON"; rm -f "$R/scripts/crontab"
  DOCKER_PS=""; SS_PUERTOS=""
}
# chequea [VAR=valor ...] -- args   (usa el estado actual; guarda OUT y ST)
chequea() {
  local extra=()
  while [ "$1" != "--" ]; do extra+=("$1"); shift; done; shift
  OUT=$(cd "$R" && env PATH="$STUBS:$PATH" DOCKER_PS="$DOCKER_PS" SS_PUERTOS="$SS_PUERTOS" CRONTAB_FILE="$CRON" \
    ENV_BASE="$ENVB" "${extra[@]}" bash scripts/chequear-host.sh "$@" 2>&1)
  ST=$?
}

titulo "puertos"
nuevo_estado; chequea -- puertos
igual "puertos libres: sale con 0" 0 "$ST"
contiene "dice que BACKEND_HOST_PORT esta libre" "$OUT" 'BACKEND_HOST_PORT=4100 libre'
no_contiene "una variable vacia (FRONTEND_HOST_PORT=) se saltea" "$OUT" 'FRONTEND_HOST_PORT'

nuevo_estado; DOCKER_PS='otro-backend|127.0.0.1:4100->8000/tcp'; chequea -- puertos
igual "lo publica un contenedor de OTRO proyecto: sale con 1" 1 "$ST"
contiene "  nombra al contenedor ajeno" "$OUT" 'BACKEND_HOST_PORT=4100 ya lo publica otro proyecto: otro-backend'
contiene "  sugiere elegir otros con 'alta'" "$OUT" 'chequear-host.sh alta'

nuevo_estado; DOCKER_PS='app-backend|127.0.0.1:4100->8000/tcp'; chequea -- puertos
igual "lo publica un contenedor de ESTE proyecto (redeploy): sale con 0" 0 "$ST"
contiene "  lo reconoce como redeploy" "$OUT" 'lo tiene este mismo proyecto: redeploy'

nuevo_estado; printf 'PROJECT_PREFIX=app\nBACKEND_HOST_PORT=4001\n' > "$R/.env"; chequea -- puertos
igual "reservado en el .env de otro repo (aunque este detenido): sale con 1" 1 "$ST"
contiene "  dice de quien es" "$OUT" 'reservado en el .env de: otro'

nuevo_estado; SS_PUERTOS="4100"; chequea -- puertos
igual "lo escucha un proceso que no es un contenedor: sale con 1" 1 "$ST"
contiene "  lo dice" "$OUT" 'lo esta escuchando un proceso'

nuevo_estado; printf 'PROJECT_PREFIX=app\nBACKEND_PORT=4001\n' > "$R/.env"; chequea PORT_VARS="BACKEND_PORT" -- puertos
igual "PORT_VARS permite revisar nombres viejos de variables: sale con 1" 1 "$ST"
contiene "  usa el nombre de la variable vieja" "$OUT" 'BACKEND_PORT=4001 esta reservado'

nuevo_estado; rm "$R/.env"; chequea -- puertos
igual "sin .env: sale con 1" 1 "$ST"
contiene "  lo dice" "$OUT" 'No hay .env'

nuevo_estado; chequea -- nada
igual "modo desconocido: sale con 1" 1 "$ST"
contiene "  muestra el uso" "$OUT" 'Uso: chequear-host.sh'

titulo "alta: elegir puertos libres"
nuevo_estado; SS_PUERTOS="4000 4001"
chequea RANGO_BACKEND="4000-4009" RANGO_FRONTEND="5000-5009" RANGO_DB="6000-6009" -- alta
igual "sale con 0" 0 "$ST"
contiene "saltea el puerto que escucha un proceso (4000) y el reservado por otro repo (4001)" "$OUT" 'BACKEND_HOST_PORT=4002'
contiene "frontend: primero libre de su rango" "$OUT" 'FRONTEND_HOST_PORT=5000'
contiene "db: primero libre de su rango" "$OUT" 'DB_HOST_PORT=6000'
chequea RANGO_BACKEND="4000-4001" -- alta
nuevo_estado; SS_PUERTOS="4000 4001"; chequea RANGO_BACKEND="4000-4001" -- alta
igual "rango agotado: sale con 1" 1 "$ST"
contiene "  lo dice" "$OUT" 'Sin puerto libre en 4000-4001'
nuevo_estado; rm "$R/.env"; chequea -- alta
igual "alta no necesita .env (se corre ANTES de crearlo): sale con 0" 0 "$ST"

titulo "horario del backup"
nuevo_estado; chequea -- horario
contiene "sin scripts/crontab no se chequea" "$OUT" 'no tiene una linea de backup.sh con hora fija'
nuevo_estado
printf '0 3 * * * cd __DIR__ && bash scripts/backup.sh\n' > "$R/scripts/crontab"
printf '5 3 * * * cd /x/otro && bash scripts/backup.sh\n' > "$CRON"; chequea -- horario
contiene "otro backup a menos de 10 min: avisa con ::warning::" "$OUT" '::warning::El backup de mi-repo \(03:00\) cae a menos de'
contiene "  nombra el horario ajeno" "$OUT" '03:05'
printf '30 3 * * * cd /x/otro && bash scripts/backup.sh\n' > "$CRON"; chequea -- horario
contiene "sin choque: lo confirma" "$OUT" 'Backup de mi-repo a las 03:00: sin choque'
printf '# 0 3 * * * comentado backup.sh\n5 3 * * * cd /x/mi-repo && bash scripts/backup.sh\n' > "$CRON"; chequea -- horario
contiene "las lineas del propio repo no cuentan como choque" "$OUT" 'sin choque'

titulo "todo = puertos + horario (lo que corre el deploy)"
nuevo_estado; printf '0 3 * * * bash scripts/backup.sh\n' > "$R/scripts/crontab"; chequea --
igual "todo en orden: sale con 0" 0 "$ST"
contiene "  hace los dos chequeos" "$OUT" 'BACKEND_HOST_PORT=4100 libre'
SS_PUERTOS="4100"; chequea --
igual "un puerto ajeno falla el deploy aunque el horario este bien: sale con 1" 1 "$ST"
printf '5 3 * * * bash scripts/backup.sh\n' > "$CRON"; SS_PUERTOS=""; chequea --
igual "un choque de horario SOLO avisa: sale con 0" 0 "$ST"

titulo "libre: proximo horario sin choque"
nuevo_estado; printf '0 3 * * * bash scripts/backup.sh\n10 3 * * * bash scripts/backup.sh\n' > "$CRON"; chequea -- libre
contiene "propone un horario y la linea de crontab lista" "$OUT" 'Proximo horario libre: [0-9]{2}:[0-9]{2}  ->  linea del crontab: [0-9]+ [0-9]+ \* \* \*'
no_contiene "no propone uno que choque con 03:00 ni 03:10" "$OUT" 'libre: 03:0[0-9]'

terminar
