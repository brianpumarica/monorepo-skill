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
crea 'JWT_SECRET=\nADMIN_PASSWORD=\nOPENAI_API_KEY=\nBACKEND_HOST_PORT=\nDB_HOST_PORT=\nPORT=3000\nFIJA_HOST_PORT=7777\n'
igual "sale con 0" 0 "$ST"
igual "JWT_SECRET: 64 hex" 64 "$(largo "$(valor JWT_SECRET)")"
igual "ADMIN_PASSWORD: 32 hex" 32 "$(largo "$(valor ADMIN_PASSWORD)")"
igual "una API key de terceros NO se inventa" "" "$(valor OPENAI_API_KEY)"
contiene "BACKEND_HOST_PORT recibe un puerto" "$(valor BACKEND_HOST_PORT)" '^[0-9]{4,5}$'
contiene "DB_HOST_PORT recibe un puerto" "$(valor DB_HOST_PORT)" '^[0-9]{4,5}$'
igual "un puerto con valor en la plantilla se respeta" 7777 "$(valor FIJA_HOST_PORT)"
igual "PORT con valor se copia tal cual" 3000 "$(valor PORT)"
no_contiene "el resumen no imprime los secretos" "$OUT" "$(valor JWT_SECRET)"
modo "el .env queda 600" "$ENVB/repo/.env" 600

titulo "que se genera: propias si, de terceros no"
crea 'SESSION_SECRET=\nGOOGLE_CLIENT_SECRET=\nSTRIPE_SECRET=\nAPI_KEY=\nAPP_ENCRYPTION_KEY=\nGEMINI_API_KEY=\nSTRIPE_SIGNING_KEY=\nACME_API_KEY=\nACME_CLIENT_SECRET=\n'
igual "SESSION_SECRET propia: 32 hex" 32 "$(largo "$(valor SESSION_SECRET)")"
igual "API_KEY propia (sin proveedor): se genera" 32 "$(largo "$(valor API_KEY)")"
igual "*_ENCRYPTION_KEY propia: se genera" 32 "$(largo "$(valor APP_ENCRYPTION_KEY)")"
igual "GOOGLE_CLIENT_SECRET de un tercero: NO se inventa" "" "$(valor GOOGLE_CLIENT_SECRET)"
igual "STRIPE_SECRET de un tercero: NO se inventa" "" "$(valor STRIPE_SECRET)"
igual "STRIPE_SIGNING_KEY de un tercero: NO se inventa" "" "$(valor STRIPE_SIGNING_KEY)"
igual "GEMINI_API_KEY de un tercero: NO se inventa" "" "$(valor GEMINI_API_KEY)"
igual "<PROVEEDOR>_API_KEY desconocido: NO se inventa (una clave de mas es peor que una de menos)" "" "$(valor ACME_API_KEY)"
igual "*_CLIENT_SECRET de cualquier proveedor: NO se inventa" "" "$(valor ACME_CLIENT_SECRET)"
contiene "las de terceros quedan en 'Completar a mano'" "$OUT" 'Completar a mano.*GOOGLE_CLIENT_SECRET'
crea 'ACME_SECRET=\nOTRO_SECRET=\n'
igual "sin CREAR_ENV_TERCEROS, ACME_SECRET se genera" 32 "$(largo "$(valor ACME_SECRET)")"
rm -rf "${ENVB:?}/repo"; printf 'ACME_SECRET=\nOTRO_SECRET=\n' > "$R/.env.example"
OUT=$(cd "$R" && env PATH="$STUBS:$PATH" ENV_BASE="$ENVB" ENV_OWNER= CREAR_ENV_TERCEROS='ACME' bash scripts/crear-env.sh repo 2>&1)
igual "CREAR_ENV_TERCEROS=ACME: ACME_SECRET no se inventa" "" "$(valor ACME_SECRET)"
igual "  y las demas siguen generandose" 32 "$(largo "$(valor OTRO_SECRET)")"

titulo ".env.example con CRLF: se genera igual y el .env sale con LF"
crea 'JWT_SECRET=\r\nADMIN_PASSWORD=\r\nBACKEND_HOST_PORT=\r\nPORT=3000\r\n'
igual "sale con 0 (aunque no quede nada por completar)" 0 "$ST"
igual "JWT_SECRET: 64 hex (antes quedaba vacio sin avisar)" 64 "$(largo "$(valor JWT_SECRET)")"
igual "ADMIN_PASSWORD: 32 hex" 32 "$(largo "$(valor ADMIN_PASSWORD)")"
contiene "BACKEND_HOST_PORT recibe un puerto" "$(valor BACKEND_HOST_PORT)" '^[0-9]{4,5}$'
contiene "avisa que normalizo los CRLF" "$OUT" 'CRLF'
igual "el .env no trae ningun CR" 0 "$(tr -cd '\r' < "$ENVB/repo/.env" | wc -c | tr -d ' ')"

titulo "FRONTEND_HOST_PORT: solo se reserva si la plantilla lo trae vacio"
crea 'JWT_SECRET=\nBACKEND_HOST_PORT=\nFRONTEND_HOST_PORT=\nDB_HOST_PORT=\n'
contiene "con la linea vacia en la plantilla, se le asigna un puerto" "$(valor FRONTEND_HOST_PORT)" '^[0-9]{4,5}$'
crea 'JWT_SECRET=\nBACKEND_HOST_PORT=\nDB_HOST_PORT=\n'
no_contiene "frontend en Vercel: sin la linea en la plantilla, no aparece en el .env" "$(cat "$ENVB/repo/.env")" 'FRONTEND_HOST_PORT'

titulo "docker-compose.prod.yml manda: solo se asigna lo que prod publica"
cat > "$R/docker-compose.prod.yml" <<'YML'
services:
  backend:
    ports:
      - "127.0.0.1:${BACKEND_HOST_PORT:-3004}:3004"
  panel:
    ports:
      - "127.0.0.1:${ADMIN_HOST_PORT:-8090}:8090"
YML
crea 'JWT_SECRET=\nBACKEND_HOST_PORT=\nFRONTEND_HOST_PORT=\nDB_HOST_PORT=\nADMIN_HOST_PORT=\n'
contiene "BACKEND_HOST_PORT (la usa prod) recibe un puerto" "$(valor BACKEND_HOST_PORT)" '^[0-9]{4,5}$'
contiene "ADMIN_HOST_PORT (un tercer servicio que prod publica) tambien" "$(valor ADMIN_HOST_PORT)" '^[0-9]{4,5}$'
igual "FRONTEND_HOST_PORT (prod no la usa: va a Vercel) queda vacia" "" "$(valor FRONTEND_HOST_PORT)"
igual "DB_HOST_PORT (prod no la publica) queda vacia" "" "$(valor DB_HOST_PORT)"
contiene "lo dice" "$OUT" 'Sin puerto \(docker-compose.prod.yml no las usa\): FRONTEND_HOST_PORT DB_HOST_PORT'
no_contiene "y no las pide en 'Completar a mano'" "$OUT" 'Completar a mano'
igual "los puertos asignados son distintos entre si" 2 "$(printf '%s\n%s\n' "$(valor BACKEND_HOST_PORT)" "$(valor ADMIN_HOST_PORT)" | sort -u | wc -l | tr -d ' ')"
rm -f "$R/docker-compose.prod.yml"

titulo "no pisa un .env existente"
mkdir -p "$ENVB/repo"; echo 'JWT_SECRET=original' > "$ENVB/repo/.env"
OUT=$(cd "$R" && env PATH="$STUBS:$PATH" ENV_BASE="$ENVB" ENV_OWNER= bash scripts/crear-env.sh repo 2>&1); ST=$?
igual "sale con 1" 1 "$ST"
contiene "lo dice" "$OUT" 'Ya existe'
igual "el .env sigue igual" "JWT_SECRET=original" "$(cat "$ENVB/repo/.env")"

terminar
