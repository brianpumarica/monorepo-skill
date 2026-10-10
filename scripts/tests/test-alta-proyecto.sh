#!/usr/bin/env bash
# Pruebas de references/alta-proyecto.sh con un gh falso: que secrets carga el paso 3.
. "$(dirname "$0")/lib.sh"
command -v node >/dev/null || { echo "sin node: se omite"; exit 0; }

P="$T/proy"; mkdir -p "$P/.vercel"; git -C "$P" init -q .
echo '{"projectId":"prj_1","orgId":"team_1"}' > "$P/.vercel/project.json"
printf 'ORG_RUNNER=mi-org\nDOMINIO=ejemplo.test\n' > "$T/alta.env"
URL='https://api-demo.ejemplo.test'

titulo "paso 3: secrets de GitHub"
OUT=$(cd "$P" && env PATH="$STUBS:$PATH" ALTA_CONFIG="$T/alta.env" bash "$REF/alta-proyecto.sh" --simular --paso 3 2>&1)
contiene "--simular anuncia API_URL y no ejecuta nada" "$OUT" '\[simulacion\] cargar VERCEL_PROJECT_ID, VERCEL_ORG_ID, API_URL y SITE_URL en mi-org/demo'
: > "$T/gh.log"
SI=$(printf 's\n%.0s' 1 2 3 4 5 6)   # contesta "s" a cada confirmacion (sin `yes |`: con pipefail daria SIGPIPE)
OUT=$(cd "$P" && env PATH="$STUBS:$PATH" GH_LOG="$T/gh.log" ALTA_CONFIG="$T/alta.env" VERCEL_TOKEN=tok-secreto bash "$REF/alta-proyecto.sh" --paso 3 2>&1 <<< "$SI"); ST=$?
igual "ejecucion confirmando todo: sale con 0" 0 "$ST"
LOG=$(cat "$T/gh.log")
contiene "carga API_URL" "$LOG" '^secret set API_URL '
no_contiene "ya no carga VITE_API_URL" "$LOG" 'VITE_API_URL'
igual "API_URL vale $URL (por su largo)" "secret set API_URL ($(printf '%s' "$URL" | wc -c | tr -d ' ') bytes)" "$(grep '^secret set API_URL' "$T/gh.log")"
contiene "carga los 5 secrets, en orden" "$(grep -o 'secret set [A-Z_]*' "$T/gh.log" | tr '\n' ' ')" 'VERCEL_PROJECT_ID.*VERCEL_ORG_ID.*API_URL.*SITE_URL.*VERCEL_TOKEN'
no_contiene "el token no aparece en la salida" "$OUT" 'tok-secreto'

terminar
