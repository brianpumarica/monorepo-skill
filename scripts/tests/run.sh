#!/usr/bin/env bash
# Corre todos los test-*.sh y resume. Uso:  bash scripts/tests/run.sh [fragmento-del-nombre]
# Otra version de los scripts:  REF_OVERRIDE=/ruta/a/references bash scripts/tests/run.sh
cd "$(dirname "$0")" || exit 1
fallidos=()
for t in test-*"${1:-}"*.sh; do
  echo "━━━ $t"
  bash "$t" || fallidos+=("$t")
done
echo
if [ ${#fallidos[@]} -gt 0 ]; then echo "❌ Fallaron: ${fallidos[*]}"; exit 1; fi
echo "✅ Todos los tests de scripts pasaron."
