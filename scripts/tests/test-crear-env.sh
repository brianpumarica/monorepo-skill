#!/usr/bin/env bash
# Pruebas de references/crear-env.sh (+ chequear-host.sh alta): secretos al azar y puertos libres.
. "$(dirname "$0")/lib.sh"

R="$T/repo"; ENVB="$T/env"
mkdir -p "$R/scripts" "$ENVB"
cp "$REF/crear-env.sh" "$REF/chequear-host.sh" "$R/scripts/"

# crea <contenido de .env.example>  ->  OUT, ST   (el .env queda en $ENVB/repo/.env)
crea() {
  rm -rf "${ENVB:?}/repo"; printf '%b' "$1" > "$R/.env.example"
  OUT=$(cd "$R" && env PATH="$STUBS:$PATH" ENV_BASE="$ENVB" ENV_OWNER= bash scripts/crear-env.sh repo 2>&1); ST=$?
}
valor() { grep -m1 "^$1=" "$ENVB/repo/.env" | cut -d= -f2-; }
largo() { printf '%s' "$1" | wc -c | tr -d ' '; }

titulo "secretos y puertos"
crea 'JWT_SECRET=\nADMIN_PASSWORD=\nTHIRD_API_KEY=\nBACKEND_HOST_PORT=\nDB_HOST_PORT=\nPORT=3000\nFIJA_HOST_PORT=7777\n'
igual "sale con 0" 0 "$ST"
igual "JWT_SECRET: 64 hex" 64 "$(largo "$(valor JWT_SECRET)")"
igual "ADMIN_PASSWORD: 32 hex" 32 "$(largo "$(valor ADMIN_PASSWORD)")"
igual "una API key de terceros NO se inventa" "" "$(valor THIRD_API_KEY)"
contiene "BACKEND_HOST_PORT recibe un puerto" "$(valor BACKEND_HOST_PORT)" '^[0-9]{4,5}$'
contiene "DB_HOST_PORT recibe un puerto" "$(valor DB_HOST_PORT)" '^[0-9]{4,5}$'
igual "un puerto con valor en la plantilla se respeta" 7777 "$(valor FIJA_HOST_PORT)"
igual "PORT con valor se copia tal cual" 3000 "$(valor PORT)"
no_contiene "el resumen no imprime los secretos" "$OUT" "$(valor JWT_SECRET)"
modo "el .env queda 600" "$ENVB/repo/.env" 600

titulo "FRONTEND_HOST_PORT: solo se reserva si la plantilla lo trae vacio"
crea 'JWT_SECRET=\nBACKEND_HOST_PORT=\nFRONTEND_HOST_PORT=\nDB_HOST_PORT=\n'
contiene "con la linea vacia en la plantilla, se le asigna un puerto" "$(valor FRONTEND_HOST_PORT)" '^[0-9]{4,5}$'
crea 'JWT_SECRET=\nBACKEND_HOST_PORT=\nDB_HOST_PORT=\n'
no_contiene "frontend en Vercel: sin la linea en la plantilla, no aparece en el .env" "$(cat "$ENVB/repo/.env")" 'FRONTEND_HOST_PORT'

titulo "no pisa un .env existente"
mkdir -p "$ENVB/repo"; echo 'JWT_SECRET=original' > "$ENVB/repo/.env"
OUT=$(cd "$R" && env PATH="$STUBS:$PATH" ENV_BASE="$ENVB" ENV_OWNER= bash scripts/crear-env.sh repo 2>&1); ST=$?
igual "sale con 1" 1 "$ST"
contiene "lo dice" "$OUT" 'Ya existe'
igual "el .env sigue igual" "JWT_SECRET=original" "$(cat "$ENVB/repo/.env")"

terminar
