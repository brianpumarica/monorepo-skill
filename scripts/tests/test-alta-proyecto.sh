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


titulo "paso 2: desconecta la integracion de Git de Vercel"
# Vercel falso: registra cada llamada. VERCEL_LINKED=1 simula un proyecto que ya desplegaba por Git
# (la API devuelve `link`); un DELETE a /link lo desconecta (borra el estado).
VC="$T/vercel-falso"; VLOG="$T/vercel.log"; VST="$T/vercel.estado"
cat > "$VC" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$VLOG"
[ "$1" = api ] || exit 0
case "$*" in
  *"-X DELETE"*) rm -f "$VST"; echo '{}' ;;
  *"-X PATCH"*) echo '{"rootDirectory":"frontend"}' ;;
  *) if [ -f "$VST" ]; then echo '{"id":"prj_1","link":{"type":"github"}}'; elif [ -n "${VERCEL_SIN_API:-}" ]; then :; else echo '{"id":"prj_1"}'; fi ;;
esac
SH
chmod +x "$VC"; mkdir -p "$P/frontend"
paso2() { : > "$VLOG"; OUT=$(cd "$P" && env PATH="$STUBS:$PATH" VLOG="$VLOG" VST="$VST" ALTA_CONFIG="$T/alta.env" VERCEL_CMD="$VC" "$@" bash "$REF/alta-proyecto.sh" --paso 2 2>&1 <<< "$SI"); ST=$?; }
echo conectado > "$VST"; paso2
igual "con integracion de Git: sale con 0" 0 "$ST"
contiene "  la detecta y la desconecta" "$OUT" 'Integracion de Git desconectada'
contiene "  llama a DELETE /v9/projects/<id>/link" "$(cat "$VLOG")" 'api /v9/projects/prj_1/link\?teamId=team_1 -X DELETE'
rm -f "$VST"; paso2
contiene "sin integracion: lo dice y no la toca" "$OUT" 'nada que desconectar'
no_contiene "  sin ningun DELETE" "$(cat "$VLOG")" 'DELETE'
paso2 VERCEL_SIN_API=1
contiene "si la API no responde: avisa en vez de afirmar que no hay integracion" "$OUT" 'No se pudo consultar el proyecto'
no_contiene "  y no dice 'nada que desconectar'" "$OUT" 'nada que desconectar'
echo conectado > "$VST"; OUT=$(cd "$P" && env PATH="$STUBS:$PATH" VLOG="$VLOG" VST="$VST" ALTA_CONFIG="$T/alta.env" VERCEL_CMD="$VC" bash "$REF/alta-proyecto.sh" --simular --paso 2 2>&1)
contiene "--simular anuncia el paso y no ejecuta nada" "$OUT" '\[simulacion\] crear y enlazar'
igual "  el estado de Vercel sigue igual" conectado "$(cat "$VST")"

terminar
