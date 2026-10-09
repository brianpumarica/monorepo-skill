#!/bin/bash
# Crea el .env de produccion de un proyecto en el servidor, UNA vez. Cada repo lo copia como
# scripts/crear-env.sh. Uso:  sudo bash scripts/crear-env.sh   (desde la carpeta del repo)
#
# - Parte de .env.example y completa con valores aleatorios las variables *_SECRET y
#   *_PASSWORD que estan VACIAS en la plantilla. Las que ya traen valor se copian tal cual;
#   por eso, para una base ya creada, dejar en .env.example el POSTGRES_PASSWORD real no
#   corresponde: se copia a mano del .env viejo antes de correr esto.
# - Las *_HOST_PORT que estan VACIAS en la plantilla se completan con puertos libres de este
#   servidor (los mismos que imprime `chequear-host.sh alta`): no hay que elegirlos ni escribirlos
#   a mano. Con valor en la plantilla, se respetan. El archivo queda con el dueño correcto: NO
#   editarlo despues con `sudo sed -i` (recrea el archivo como root y el runner deja de leerlo);
#   si hace falta cambiar algo, `sudo nano` y despues `sudo chown github-runner:github-runner`.
# - Las claves de terceros (API keys) no se inventan: quedan listadas para completar.
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
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
cp .env.example "$tmp"

generados=()
for var in $(grep -E '^[A-Z0-9_]*(_SECRET|_PASSWORD)=$' .env.example | cut -d= -f1); do
  case "$var" in JWT_SECRET) valor=$(openssl rand -hex 32) ;; *) valor=$(openssl rand -hex 16) ;; esac
  sed -i "s|^${var}=\$|${var}=${valor}|" "$tmp"
  generados+=("$var")
done

# Puertos libres para las *_HOST_PORT vacias de la plantilla.
asignados=()
if grep -qE '^[A-Z]*_HOST_PORT=$' .env.example && [ -f scripts/chequear-host.sh ]; then
  libres=$(ENV_BASE="$base" bash scripts/chequear-host.sh alta 2>/dev/null \
    | sed -n 's/^ *\([A-Z]*_HOST_PORT\)=\([0-9]*\).*/\1=\2/p')
  for par in $libres; do
    var=${par%%=*}; valor=${par#*=}
    if grep -qE "^${var}=\$" .env.example; then
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
for var in "${generados[@]}"; do
  case "$var" in ADMIN_*) echo "   $var = $(grep -m1 "^${var}=" "$dest" | cut -d= -f2-)   <- guardarla ahora, es la de acceso" ;; esac
done
pendientes=$(grep -E '^[A-Z0-9_]+=$' "$dest" | cut -d= -f1 | tr '\n' ' ')
[ -z "$pendientes" ] || echo "   Completar a mano (sudo nano $dest): $pendientes"
