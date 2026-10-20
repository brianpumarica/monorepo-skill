#!/bin/bash
# Rota secretos de produccion de un proyecto, en el servidor. Cada repo lo copia como
# scripts/rotar-secretos.sh. Uso (desde la carpeta del repo):
#   sudo bash scripts/rotar-secretos.sh jwt    # solo JWT_SECRET
#   sudo bash scripts/rotar-secretos.sh db     # solo la clave de la base
#   sudo bash scripts/rotar-secretos.sh all    # las dos (si el proyecto no tiene JWT_SECRET, solo la base)
#   sudo bash scripts/rotar-secretos.sh var NOMBRE   # otro secreto PROPIO (API_KEY, SESSION_SECRET...)
#
# No todo proyecto usa JWT: sin JWT_SECRET en el .env, `jwt` avisa y no toca nada, y `var` rota el
# secreto que el proyecto si tenga. `var` solo acepta *_SECRET, *_KEY y *_PASSWORD que ya esten en el
# .env, y NO la clave de la base (esa lleva `db`, que hace tambien el ALTER USER). Una credencial de
# un tercero (la API de un proveedor) se rota en el proveedor, no inventando otra aca.
#
# La base se busca en el contenedor DB_CONTAINER_NAME del .env o, si no esta, <PROJECT_PREFIX>-database.
#
# Orden, que es lo que evita quedarse afuera de la propia base:
#   1. se prepara el .env nuevo en un archivo temporal (nada cambia todavia);
#   2. ALTER USER en la base, con la clave vieja aun vigente;
#   3. recien si el ALTER funciono, el .env nuevo reemplaza al viejo (mv atomico).
# Si falla el paso 2, el .env sigue intacto y la base tambien. Si falla el paso 3 despues de un
# ALTER exitoso, la clave nueva queda en el archivo temporal (se avisa la ruta, no se borra).
#
# - Copia el .env viejo a .env.bak-<fecha> (600) en la misma carpeta, para poder volver.
# - NO imprime ningun secreto.
# - NO reinicia nada: el contenedor congela su entorno al crearse (database-lifecycle.md §0).
#   Al terminar indica el paso siguiente: volver a correr el deploy.
# - Con `db` o `all`, entre el ALTER USER y el deploy el backend corriendo sigue con la clave
#   vieja en su entorno: las conexiones ya abiertas siguen, pero no puede abrir nuevas. Correr
#   el deploy enseguida.
# - Rotar JWT_SECRET cierra todas las sesiones abiertas (los tokens firmados con la clave
#   vieja dejan de validar): avisar a los usuarios si hace falta.
set -euo pipefail

modo=${1:-}
variable=""
case "$modo" in
  jwt | db | all) repo_arg=${2:-} ;;
  var) variable=${2:-}; repo_arg=${3:-}
       printf '%s' "$variable" | grep -qE '^[A-Z][A-Z0-9_]*_(SECRET|KEY|PASSWORD)$' \
         || { echo "❌ var necesita el NOMBRE de un secreto propio (*_SECRET, *_KEY o *_PASSWORD): '$variable'"; exit 1; }
       [ "$variable" != POSTGRES_PASSWORD ] || { echo "❌ La clave de la base se rota con 'db' (tambien hace el ALTER USER)."; exit 1; } ;;
  *) echo "Uso: sudo bash scripts/rotar-secretos.sh {jwt|db|all} [repo]   |   var NOMBRE [repo]"; exit 1 ;;
esac

# El script vive en <repo>/scripts/: trabajar siempre desde la raiz del repo, se llame desde donde se
# llame (el log del deploy imprime la ruta completa para pegarla desde cualquier carpeta).
raiz=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd) || true
if [ -n "${raiz:-}" ] && [ -f "$raiz/.env.example" ]; then cd "$raiz"; fi
repo=${repo_arg:-$(basename "$PWD")}
base=${ENV_BASE:-/home/github-runner/env-backups}
owner=${ENV_OWNER-github-runner}   # vacio = no cambiar dueño (para probar sin root)
env_file="$base/$repo/.env"

[ -f "$env_file" ] || { echo "❌ No existe $env_file"; exit 1; }

# Lee VAR del .env sacando comillas y espacios sobrantes. Si la clave no esta devuelve vacio (sin el
# `|| true`, el grep sin resultado + `set -e` + `pipefail` mataba el script en silencio).
leer() { { grep -m1 "^$1=" "$env_file" || true; } | cut -d= -f2- | sed -e 's/^["'\'']//' -e 's/["'\'']$//'; }

# Reemplaza VAR=... en el archivo $1 por el valor $3, conservando las comillas si las tenia.
poner() {
  local archivo=$1 var=$2 valor=$3 q
  grep -q "^${var}=" "$archivo" || { echo "❌ ${var} no esta en $env_file"; exit 1; }
  q=$(grep -m1 "^${var}=" "$archivo" | cut -d= -f2- | cut -c1)
  case "$q" in '"' | "'") ;; *) q="" ;; esac
  # Los valores son hexadecimales: sin caracteres especiales para sed.
  sed -i "s|^${var}=.*|${var}=${q}${valor}${q}|" "$archivo"
}

tmp=$(mktemp "$env_file.nuevo.XXXXXX")
chmod 600 "$tmp"
cp "$env_file" "$tmp"
rotados=()

if [ "$modo" = jwt ] || [ "$modo" = all ]; then
  if grep -q "^JWT_SECRET=" "$tmp"; then
    poner "$tmp" JWT_SECRET "$(openssl rand -hex 32)"
    rotados+=(JWT_SECRET)
  elif [ "$modo" = jwt ]; then
    echo "❌ $env_file no tiene JWT_SECRET: este proyecto no firma tokens con esa variable. No se toco nada."
    echo "   Para otro secreto propio:  sudo bash scripts/rotar-secretos.sh var NOMBRE"
    rm -f "$tmp"; exit 1
  else
    echo "ℹ️  Sin JWT_SECRET en el .env: se rota solo la base."
  fi
fi

if [ "$modo" = var ]; then
  if ! grep -q "^${variable}=" "$tmp"; then
    echo "❌ $variable no esta en $env_file. No se toco nada."; rm -f "$tmp"; exit 1
  fi
  poner "$tmp" "$variable" "$(openssl rand -hex 32)"
  rotados+=("$variable")
fi

if [ "$modo" = db ] || [ "$modo" = all ]; then
  usuario=$(leer POSTGRES_USER); basedatos=$(leer POSTGRES_DB)
  vieja=$(leer POSTGRES_PASSWORD); prefijo=$(leer PROJECT_PREFIX)
  # El contenedor de la base: DB_CONTAINER_NAME del .env, o <PROJECT_PREFIX>-database. Sin ninguno
  # de los dos NO se adivina un nombre generico ("app-database" podria ser de otro proyecto).
  contenedor=$(leer DB_CONTAINER_NAME)
  [ -n "$contenedor" ] || { [ -n "$prefijo" ] && contenedor="$prefijo-database"; }
  [ -n "$contenedor" ] \
    || { echo "❌ $env_file no tiene DB_CONTAINER_NAME ni PROJECT_PREFIX: no se sabe en que contenedor hacer el ALTER USER."
         echo "   Agregar una de las dos (p. ej. PROJECT_PREFIX=<prefijo-del-proyecto>) y repetir. No se toco nada."
         rm -f "$tmp"; exit 1; }
  # shellcheck disable=SC2015  # A && B && C || { ... } a proposito: el bloque cubre el fallo de cualquiera
  [ -n "$usuario" ] && [ -n "$basedatos" ] && [ -n "$vieja" ] \
    || { echo "❌ Faltan POSTGRES_USER, POSTGRES_DB o POSTGRES_PASSWORD en $env_file"; rm -f "$tmp"; exit 1; }
  docker ps --format '{{.Names}}' | grep -qx "$contenedor" \
    || { echo "❌ El contenedor '$contenedor' no esta corriendo (no se puede hacer el ALTER USER)."; rm -f "$tmp"; exit 1; }

  nueva=$(openssl rand -hex 16)
  poner "$tmp" POSTGRES_PASSWORD "$nueva"
  # DATABASE_URL suele llevar la clave incrustada: se reemplaza solo ahi, sin tocar el resto.
  if grep -q "^DATABASE_URL=" "$tmp"; then
    linea=$(grep -m1 "^DATABASE_URL=" "$tmp")
    cuerpo=${linea#DATABASE_URL=}
    sed -i "s|^DATABASE_URL=.*|DATABASE_URL=${cuerpo//"$vieja"/"$nueva"}|" "$tmp"
  fi

  # Paso 2: la clave vieja sigue vigente hasta aqui. `psql` dentro del contenedor entra por
  # el socket local, sin clave. Sin `-t`: la TTY ensucia la salida.
  if ! echo "ALTER USER \"$usuario\" WITH PASSWORD '$nueva';" \
       | docker exec -i "$contenedor" psql -U "$usuario" -d "$basedatos" -v ON_ERROR_STOP=1 >/dev/null; then
    echo "❌ El ALTER USER fallo. No se toco el .env ni la base."
    rm -f "$tmp"; exit 1
  fi
  rotados+=(POSTGRES_PASSWORD)
fi

# Paso 3: copia de seguridad del viejo y reemplazo atomico.
bak="$env_file.bak-$(date +%Y%m%d-%H%M%S)"
cp -p "$env_file" "$bak"; chmod 600 "$bak"
[ -z "$owner" ] || chown "$owner:$owner" "$tmp" "$bak"
mv "$tmp" "$env_file" || { echo "❌ No se pudo reemplazar $env_file. El .env nuevo quedo en $tmp"; exit 1; }

echo "✅ Rotado: ${rotados[*]}  ($env_file, 600)"
echo "   Copia del .env anterior: $bak  (borrarla cuando el deploy confirme que todo anda)"
echo "   Falta: volver a correr el deploy para que los contenedores tomen el valor nuevo:"
echo "     gh workflow run deploy.yml --ref <rama>"
