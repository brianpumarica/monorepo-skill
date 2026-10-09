#!/bin/bash
# Rota secretos de produccion de un proyecto, en el servidor. Cada repo lo copia como
# scripts/rotar-secretos.sh. Uso (desde la carpeta del repo):
#   sudo bash scripts/rotar-secretos.sh jwt    # solo JWT_SECRET
#   sudo bash scripts/rotar-secretos.sh db     # solo la clave de la base
#   sudo bash scripts/rotar-secretos.sh all    # las dos
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
case "$modo" in jwt | db | all) ;; *) echo "Uso: sudo bash scripts/rotar-secretos.sh {jwt|db|all} [repo]"; exit 1 ;; esac

# El script vive en <repo>/scripts/: trabajar siempre desde la raiz del repo, se llame desde donde se
# llame (el log del deploy imprime la ruta completa para pegarla desde cualquier carpeta).
raiz=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd) || true
if [ -n "${raiz:-}" ] && [ -f "$raiz/.env.example" ]; then cd "$raiz"; fi
repo=${2:-$(basename "$PWD")}
base=${ENV_BASE:-/home/github-runner/env-backups}
owner=${ENV_OWNER-github-runner}   # vacio = no cambiar dueño (para probar sin root)
env_file="$base/$repo/.env"

[ -f "$env_file" ] || { echo "❌ No existe $env_file"; exit 1; }

# Lee VAR del .env sacando comillas y espacios sobrantes.
leer() { grep -m1 "^$1=" "$env_file" | cut -d= -f2- | sed -e 's/^["'\'']//' -e 's/["'\'']$//'; }

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
  poner "$tmp" JWT_SECRET "$(openssl rand -hex 32)"
  rotados+=(JWT_SECRET)
fi

if [ "$modo" = db ] || [ "$modo" = all ]; then
  usuario=$(leer POSTGRES_USER); basedatos=$(leer POSTGRES_DB)
  vieja=$(leer POSTGRES_PASSWORD); prefijo=$(leer PROJECT_PREFIX)
  contenedor="${prefijo:-app}-database"
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
