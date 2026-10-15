#!/usr/bin/env bash
# Pruebas de references/rotar-secretos.sh: sin root y con un docker falso (ENV_BASE, ENV_OWNER=).
. "$(dirname "$0")/lib.sh"

SCRIPT="$REF/rotar-secretos.sh"
ENVB="$T/env"; DLOG="$T/docker.log"
DOCKER_PS=$'pf-database|\ndbx-custom|'

# mk <repo> <lineas extra del .env>
mk() {
  mkdir -p "$ENVB/$1"
  printf 'POSTGRES_USER=u\nPOSTGRES_DB=d\nPOSTGRES_PASSWORD=vieja123\nDATABASE_URL=postgres://u:vieja123@db/d\nJWT_SECRET=jwtviejo\n%b' "$2" > "$ENVB/$1/.env"
}
# corre [VAR=valor ...] -- args...
corre() {
  local extra=()
  while [ "$1" != "--" ]; do extra+=("$1"); shift; done; shift
  : > "$DLOG"
  OUT=$(env PATH="$STUBS:$PATH" DOCKER_PS="$DOCKER_PS" DOCKER_LOG="$DLOG" ENV_BASE="$ENVB" ENV_OWNER= "${extra[@]}" bash "$SCRIPT" "$@" 2>&1)
  ST=$?
}
valor() { grep -m1 "^$2=" "$ENVB/$1/.env" | cut -d= -f2-; }

titulo "uso"
rm -rf "$ENVB"; corre -- malo x
igual "modo desconocido: sale con 1" 1 "$ST"
contiene "muestra el uso" "$OUT" 'Uso:'
corre -- jwt noexiste
igual "repo sin .env: sale con 1" 1 "$ST"
contiene "dice que no existe el .env" "$OUT" 'No existe'

titulo "sin PROJECT_PREFIX ni DB_CONTAINER_NAME (antes salia mudo)"
rm -rf "$ENVB"; mk proj ''
corre -- db proj
igual "sale con 1" 1 "$ST"
contiene "avisa el motivo" "$OUT" 'no tiene DB_CONTAINER_NAME ni PROJECT_PREFIX'
contiene "dice que no toco nada" "$OUT" 'No se toco nada'
igual "no llamo a la base" "" "$(cat "$DLOG")"
igual "el .env conserva la clave vieja" vieja123 "$(valor proj POSTGRES_PASSWORD)"
igual "no quedo un archivo temporal" 0 "$(find "$ENVB/proj" -name "*nuevo*" | wc -l | tr -d " ")"

titulo "DB_CONTAINER_NAME"
rm -rf "$ENVB"; mk dbx 'DB_CONTAINER_NAME=dbx-custom\n'
corre -- db dbx
igual "sale con 0" 0 "$ST"
contiene "hizo el ALTER USER en el contenedor indicado" "$(cat "$DLOG")" 'exec -i dbx-custom psql -U u -d d'
contiene "el SQL cambia la clave" "$(cat "$DLOG")" "ALTER USER \"u\" WITH PASSWORD '"
no_contiene "la clave vieja ya no esta en el .env" "$(cat "$ENVB/dbx/.env")" 'vieja123'
igual "JWT_SECRET no se toco con 'db'" jwtviejo "$(valor dbx JWT_SECRET)"
nueva=$(valor dbx POSTGRES_PASSWORD)
contiene "DATABASE_URL lleva la clave nueva" "$(valor dbx DATABASE_URL)" "$nueva"
no_contiene "el resumen no imprime secretos" "$OUT" "$nueva"
existe_archivo "dejo el .env.bak" "$(primero "$ENVB"/dbx/.env.bak-*)"
contiene "el .env.bak guarda la clave vieja" "$(cat "$ENVB"/dbx/.env.bak-*)" 'vieja123'
modo "el .env queda 600" "$ENVB/dbx/.env" 600
modo "el .env.bak queda 600" "$(primero "$ENVB"/dbx/.env.bak-*)" 600

titulo "PROJECT_PREFIX y modo all"
rm -rf "$ENVB"; mk pf 'PROJECT_PREFIX=pf\n'
corre -- all pf
igual "sale con 0" 0 "$ST"
contiene "uso pf-database" "$(cat "$DLOG")" 'exec -i pf-database'
contiene "reporta las dos rotadas" "$OUT" 'Rotado: JWT_SECRET POSTGRES_PASSWORD'
no_contiene "JWT_SECRET cambio" "$(cat "$ENVB/pf/.env")" 'jwtviejo'
igual "JWT_SECRET nuevo = 64 hex" 64 "$(valor pf JWT_SECRET | tr -d '\n' | wc -c | tr -d ' ')"

titulo "solo jwt: no toca la base"
rm -rf "$ENVB"; mk proj ''
corre -- jwt proj
igual "sale con 0" 0 "$ST"
igual "no llamo a docker exec" "" "$(cat "$DLOG")"
igual "la clave de la base sigue igual" vieja123 "$(valor proj POSTGRES_PASSWORD)"
no_contiene "JWT_SECRET cambio" "$(cat "$ENVB/proj/.env")" 'jwtviejo'

titulo "fallas: el .env no se toca"
rm -rf "$ENVB"; mk pf 'PROJECT_PREFIX=pf\n'
corre DOCKER_FALLA=1 -- db pf
igual "el ALTER USER falla: sale con 1" 1 "$ST"
contiene "lo dice" "$OUT" 'ALTER USER fallo'
igual "el .env conserva la clave vieja" vieja123 "$(valor pf POSTGRES_PASSWORD)"
igual "no queda temporal ni .bak" 0 "$(find "$ENVB/pf" -type f ! -name .env | wc -l | tr -d ' ')"
rm -rf "$ENVB"; mk muerto 'PROJECT_PREFIX=zz\n'
corre -- db muerto
igual "contenedor que no corre: sale con 1" 1 "$ST"
contiene "dice cual contenedor" "$OUT" "'zz-database' no esta corriendo"
rm -rf "$ENVB"; mkdir -p "$ENVB/sinuser"; printf 'PROJECT_PREFIX=pf\nPOSTGRES_PASSWORD=x\n' > "$ENVB/sinuser/.env"
corre -- db sinuser
igual "faltan POSTGRES_USER/DB: sale con 1" 1 "$ST"
contiene "lo dice" "$OUT" 'Faltan POSTGRES_USER'

terminar
