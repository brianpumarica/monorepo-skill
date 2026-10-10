#!/usr/bin/env bash
# Helpers compartidos por los test-*.sh. Se carga con:  . "$(dirname "$0")/lib.sh"
#
# Cada test corre en su propio proceso, con un directorio temporal propio, y termina con
# `terminar`, que sale con 1 si algo fallo. Los scripts de la skill se prueban SIN root, SIN
# servidor y SIN Docker real: `stubs/` pone un docker, cloudflared y systemctl falsos al frente del
# PATH, y cada script trae sus variables de prueba (TUNEL_SIN_ROOT, ENV_BASE, ENV_OWNER=, ...).
set -uo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$TESTS_DIR/../.." && pwd)
REF=${REF_OVERRIDE:-"$REPO_ROOT/skills/fullstack-monorepo/references"}   # REF_OVERRIDE: probar otra version de los scripts
CICD_MD="$REF/ci-cd-deployment-pipeline.md"
STUBS="$TESTS_DIR/stubs"

# En Windows (Git Bash) los permisos no existen y `install -m 700` falla: se usa un install falso
# y no se comprueban modos. En Linux/macOS se usa el real.
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) EN_WINDOWS=1; STUBS="$STUBS:$TESTS_DIR/stubs-windows" ;;
  *) EN_WINDOWS=0 ;;
esac
export STUBS EN_WINDOWS

PASS=0
FAIL=0
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

titulo() { echo; echo "== $1"; }
ok() { PASS=$((PASS + 1)); echo "  ✅ $1"; }
fail() {
  FAIL=$((FAIL + 1)); echo "  ❌ $1"
  [ -z "${2:-}" ] || printf '%s\n' "$2" | head -12 | sed 's/^/       /'
}

# igual "descripcion" esperado obtenido
igual() { if [ "$2" = "$3" ]; then ok "$1"; else fail "$1" "esperado: [$2]"$'\n'"obtenido: [$3]"; fi; }
# contiene "descripcion" "texto" "regex (grep -E)"
contiene() { if printf '%s\n' "$2" | grep -qE -- "$3"; then ok "$1"; else fail "$1" "no aparece /$3/ en:"$'\n'"$2"; fi; }
# no_contiene "descripcion" "texto" "regex"
no_contiene() { if printf '%s\n' "$2" | grep -qE -- "$3"; then fail "$1" "aparece /$3/ en:"$'\n'"$2"; else ok "$1"; fi; }
# existe_archivo / no_existe_archivo "descripcion" ruta
existe_archivo() { if [ -e "$2" ]; then ok "$1"; else fail "$1" "no existe $2"; fi; }
no_existe_archivo() { if [ -e "$2" ]; then fail "$1" "existe $2"; else ok "$1"; fi; }
# modo "descripcion" ruta 600   (se omite en Windows)
modo() {
  [ "$EN_WINDOWS" -eq 0 ] || { echo "  ⏭️  $1 (omitido: Windows no tiene modos)"; return 0; }
  igual "$1" "$3" "$(stat -c %a "$2")"
}

# Extrae del markdown de CI/CD un bloque de lineas [desde, hasta] (regex, la primera coincidencia
# de cada una) y le quita `$3` espacios de sangria. Los tests prueban el texto REAL de la doc.
extraer_md() {
  local sangria=${3:-0} a b
  a=$(grep -nE -- "$1" "$CICD_MD" | head -1 | cut -d: -f1)
  [ -n "$a" ] || { echo "extraer_md: no encuentro /$1/ en la doc" >&2; return 1; }
  b=$(awk -v a="$a" -v re="$2" 'NR >= a && $0 ~ re { print NR; exit }' "$CICD_MD")
  [ -n "$b" ] || { echo "extraer_md: no encuentro el fin /$2/" >&2; return 1; }
  sed -n "${a},${b}p" "$CICD_MD" | sed "s/^ \{0,$sangria\}//"
}

terminar() {
  echo
  echo "→ $(basename "$0"): $PASS ok, $FAIL fallaron"
  [ "$FAIL" -eq 0 ]
}
