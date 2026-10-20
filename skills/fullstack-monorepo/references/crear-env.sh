#!/bin/bash
# Crea el .env de produccion de un proyecto en el servidor, UNA vez. Cada repo lo copia como
# scripts/crear-env.sh. Uso:  sudo bash scripts/crear-env.sh   (desde la carpeta del repo)
#
# - Parte de .env.example y completa con valores aleatorios las variables *_PASSWORD, *_SECRET y
#   las *_KEY propias (API_KEY, *_ENCRYPTION_KEY...) que estan VACIAS en la plantilla; las de un
#   tercero (GOOGLE_CLIENT_SECRET, OPENAI_API_KEY...) no, ver mas abajo. Las que ya traen valor se copian tal cual;
#   por eso, para una base ya creada, dejar en .env.example el POSTGRES_PASSWORD real no
#   corresponde: se copia a mano del .env viejo antes de correr esto.
# - Las *_HOST_PORT que estan VACIAS en la plantilla se completan con puertos libres de este
#   servidor (los mismos que imprime `chequear-host.sh alta`): no hay que elegirlos ni escribirlos
#   a mano. Con valor en la plantilla, se respetan. El archivo queda con el dueño correcto: NO
#   editarlo despues con `sudo sed -i` (recrea el archivo como root y el runner deja de leerlo);
#   si hace falta cambiar algo, `sudo nano` y despues `sudo chown github-runner:github-runner`.
# - Las credenciales de terceros no se inventan: quedan listadas para completar.
# - Nunca pisa un .env existente.
set -euo pipefail

# El script vive en <repo>/scripts/: trabajar siempre desde la raiz del repo, se llame desde donde se
# llame (el log del deploy imprime la ruta completa para pegarla desde cualquier carpeta).
raiz=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd) || true
if [ -n "${raiz:-}" ] && [ -f "$raiz/.env.example" ]; then cd "$raiz"; fi
repo=${1:-$(basename "$PWD")}
base=${ENV_BASE:-/home/github-runner/env-backups}
owner=${ENV_OWNER-github-runner}   # vacio = no cambiar dueño (para probar sin root)
dest="$base/$repo/.env"

[ -f .env.example ] || { echo "❌ Correr desde la carpeta del repo (no hay .env.example aqui)."; exit 1; }
[ ! -e "$dest" ] || { echo "❌ Ya existe $dest. No se pisa; editarlo con: sudo nano $dest"; exit 1; }

own=(); [ -n "$owner" ] && own=(-o "$owner" -g "$owner")
tmp=$(mktemp); ej=$(mktemp); trap 'rm -f "$tmp" "$ej"' EXIT
# Una plantilla guardada con CRLF (Windows sin .gitattributes) deja un \r al final de cada
# linea: ningun `VAR=$` coincide y el script no generaba NADA, sin decir por que. Se trabaja
# sobre una copia sin \r (y el .env sale con LF).
if [ "$(tr -cd '\r' < .env.example | wc -c)" -gt 0 ]; then
  echo "ℹ️  .env.example tiene saltos CRLF: se normalizan a LF (agregar .gitattributes con eol=lf al repo)."
fi
tr -d '\r' < .env.example > "$ej"
cp "$ej" "$tmp"

# Que se genera y que se deja para completar a mano:
#  - *_PASSWORD vacia: siempre (es una credencial propia).
#  - *_SECRET vacia: propia, salvo la de un tercero (<PROVEEDOR>_*, *_CLIENT_SECRET): ese valor
#    lo da el proveedor, y uno inventado hace fallar el login sin avisar.
#  - *_KEY vacia: solo las propias (API_KEY, SECRET_KEY, *_ENCRYPTION_KEY, *_SIGNING_KEY,
#    *_MASTER_KEY, *_INTERNAL_KEY). Una clave de API de un servicio (<PROVEEDOR>_API_KEY) la da
#    el servicio. Mas proveedores: CREAR_ENV_TERCEROS='ACME|OTRO' (prefijos, regex).
TERCEROS='GOOGLE|GITHUB|GITLAB|FACEBOOK|META|INSTAGRAM|TWITTER|X|LINKEDIN|APPLE|MICROSOFT|AZURE|AWS|STRIPE|PAYPAL|MERCADOPAGO|MP|TWILIO|SENDGRID|MAILGUN|RESEND|CLOUDFLARE|VERCEL|NETLIFY|NOTION|SLACK|DISCORD|TELEGRAM|WHATSAPP|EVOLUTION|N8N|OPENAI|ANTHROPIC|GEMINI|SUPABASE|FIREBASE|CLOUDINARY|SENTRY|AUTH0|OKTA|CLERK'
[ -z "${CREAR_ENV_TERCEROS:-}" ] || TERCEROS="$TERCEROS|$CREAR_ENV_TERCEROS"
es_tercero() { printf '%s' "$1" | grep -qE "^(${TERCEROS})_|_CLIENT_SECRET\$|^CLIENT_SECRET\$"; }
es_clave_propia() { printf '%s' "$1" | grep -qE '^(API_KEY|SECRET_KEY|[A-Z0-9_]*(ENCRYPTION|SIGNING|MASTER|INTERNAL)_KEY)$'; }

generados=()
while IFS= read -r var; do
  case "$var" in
    *_KEY) if ! es_clave_propia "$var" || es_tercero "$var"; then continue; fi ;;
    *_SECRET) ! es_tercero "$var" || continue ;;
  esac
  case "$var" in JWT_SECRET) valor=$(openssl rand -hex 32) ;; *) valor=$(openssl rand -hex 16) ;; esac
  sed -i "s|^${var}=\$|${var}=${valor}|" "$tmp"
  generados+=("$var")
done < <(grep -E '^[A-Z0-9_]*(_SECRET|_PASSWORD|_KEY)=$' "$ej" | cut -d= -f1)

# Puertos libres para las *_HOST_PORT vacias de la plantilla. Si el repo trae docker-compose.prod.yml,
# solo para las que ESE compose usa: una *_HOST_PORT vacia que prod no publica (el frontend que va a
# Vercel, la base que no sale al host) no aparta un puerto que nadie va a usar. Sin compose de prod
# en el repo, se asignan todas. Las que no son BACKEND/DB/FRONTEND se piden a chequear-host por nombre.
asignados=(); omitidos=(); pedir=()
if grep -qE '^[A-Z][A-Z0-9_]*_HOST_PORT=$' "$ej" && [ -f scripts/chequear-host.sh ]; then
  while IFS= read -r var; do
    if [ -f docker-compose.prod.yml ] && ! grep -q "\${$var" docker-compose.prod.yml; then
      omitidos+=("$var"); continue
    fi
    case "$var" in BACKEND_HOST_PORT | DB_HOST_PORT | FRONTEND_HOST_PORT) ;; *) pedir+=("$var") ;; esac
  done < <(grep -oE '^[A-Z][A-Z0-9_]*_HOST_PORT=$' "$ej" | tr -d '=')
  libres=$(ENV_BASE="$base" bash scripts/chequear-host.sh alta ${pedir[@]+"${pedir[@]}"} 2>/dev/null \
    | sed -n 's/^ *\([A-Z][A-Z0-9_]*_HOST_PORT\)=\([0-9]*\).*/\1=\2/p')
  for par in $libres; do
    var=${par%%=*}; valor=${par#*=}
    if grep -qE "^${var}=\$" "$ej" && ! printf '%s\n' "${omitidos[@]:-}" | grep -qx "$var"; then
      sed -i "s|^${var}=\$|${var}=${valor}|" "$tmp"
      asignados+=("$var=$valor")
    fi
  done
fi

install -d "${own[@]}" -m 700 "$(dirname "$dest")"
install "${own[@]}" -m 600 "$tmp" "$dest"

echo "✅ Creado $dest (600)."
[ ${#generados[@]} -gt 0 ] && echo "   Generados al azar: ${generados[*]}"
[ ${#asignados[@]} -gt 0 ] && echo "   Puertos libres asignados: ${asignados[*]}"
[ ${#omitidos[@]} -eq 0 ] || echo "   Sin puerto (docker-compose.prod.yml no las usa): ${omitidos[*]}"
for var in "${generados[@]}"; do
  case "$var" in ADMIN_*) echo "   $var = $(grep -m1 "^${var}=" "$dest" | cut -d= -f2-)   <- guardarla ahora, es la de acceso" ;; esac
done
# `|| true`: si no queda nada por completar, grep sale con 1 y con `set -e` el script moria aca,
# despues de crear el .env, con un codigo de error que el log del deploy mostraba como falla.
pendientes=$(grep -E '^[A-Z0-9_]+=$' "$dest" | cut -d= -f1 | grep -vxF -f <(printf '%s\n' "${omitidos[@]:-}") | tr '\n' ' ' || true)
[ -z "$pendientes" ] || echo "   Completar a mano (sudo nano $dest): $pendientes"
