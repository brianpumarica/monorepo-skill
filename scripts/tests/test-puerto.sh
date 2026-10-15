#!/usr/bin/env bash
# Pruebas de references/puerto.sh: bloque fijo por nombre, choques, el .env y el registro.
# Nada escucha de verdad: el ss falso de stubs/ dice que puertos estan ocupados (SS_PUERTOS).
. "$(dirname "$0")/lib.sh"

REG="$T/puertos"
# puerto [VAR=valor ...] -- args   (desde el proyecto $P; guarda OUT y ST)
puerto() {
  local extra=()
  while [ "$1" != "--" ]; do extra+=("$1"); shift; done; shift
  OUT=$(cd "$P" && env PATH="$STUBS:$PATH" PUERTOS_REGISTRO="$REG" PUERTOS_INICIO=4000 PUERTOS_FIN=4049 \
    SS_PUERTOS="${SS_PUERTOS:-}" "${extra[@]}" bash "$REF/puerto.sh" "$@" 2>&1)
  ST=$?
}
nuevo() { rm -rf "$P" "$REG"; mkdir -p "$P"; SS_PUERTOS=""; }
valor() { grep "^$1=" "$P/.env" | cut -d= -f2-; }
bloque() { awk -F'\t' -v n="$1" '$1 == n { print $2 }' "$REG"; }

titulo "asignar: un bloque propio, siempre el mismo"
P="$T/demo"; nuevo
puerto -- asignar
igual "sale con 0" 0 "$ST"
B=$(bloque demo)
contiene "sin nombre usa el de la carpeta y lo anota en el registro" "$B" '^40[0-4]0$'
contiene "lo anuncia" "$OUT" "'demo' recibio el bloque $B-$((B + 9))"
igual "frontend en bloque+0" "$B $B" "$(valor FRONTEND_HOST_PORT) $(valor FRONTEND_PORT)"
igual "backend en bloque+1" "$((B + 1)) $((B + 1))" "$(valor BACKEND_HOST_PORT) $(valor PORT)"
igual "base en bloque+2" "$((B + 2))" "$(valor DB_HOST_PORT)"
puerto -- asignar
contiene "la segunda vez dice que ya lo tenia" "$OUT" "ya tenia el bloque $B-"
igual "  y no lo duplica en el registro" 1 "$(grep -c '^demo' "$REG")"
puerto -- liberar
puerto -- asignar
igual "liberar y volver a asignar da el mismo bloque (sale del nombre)" "$B" "$(bloque demo)"
puerto -- asignar otro-nombre
contiene "con nombre usa ese, no el de la carpeta" "$(bloque otro-nombre)" '^40[0-4]0$'

titulo "asignar: el .env"
P="$T/demo"; nuevo
printf 'JWT_SECRET=x\nPORT=9999\nDB_HOST_PORT=1\n' > "$P/.env"
puerto -- asignar
B=$(bloque demo)
igual "conserva lo que no es de puertos" x "$(valor JWT_SECRET)"
igual "pisa el PORT viejo" "$((B + 1))" "$(valor PORT)"
igual "sin lineas repetidas" 1 "$(grep -c '^PORT=' "$P/.env")"
igual "agrega las que faltaban" "$B" "$(valor FRONTEND_HOST_PORT)"
printf 'node_modules\n' > "$P/.gitignore"; puerto -- asignar
contiene "avisa si .env no esta en .gitignore" "$OUT" '\.env no esta en \.gitignore'
printf '.env\n' > "$P/.gitignore"; puerto -- asignar
no_contiene "  y no avisa si esta" "$OUT" 'gitignore'

titulo "asignar: choques"
P="$T/demo"; nuevo
printf 'ajeno\t4000\n' > "$REG"
puerto PUERTOS_FIN=4019 -- asignar
igual "un bloque ya registrado por otro proyecto se saltea" 4010 "$(bloque demo)"
nuevo; SS_PUERTOS="4005"
puerto PUERTOS_FIN=4019 -- asignar
igual "un bloque con un puerto escuchando (algo sin registrar) se saltea" 4010 "$(bloque demo)"
nuevo; printf 'ajeno\t4000\n' > "$REG"; SS_PUERTOS="4019"
puerto PUERTOS_FIN=4019 -- asignar
igual "sin bloques libres: sale con 1" 1 "$ST"
contiene "  lo dice" "$OUT" 'No queda ningun bloque libre entre 4000 y 4019'
igual "  no anota nada" "" "$(bloque demo)"
no_existe_archivo "  ni crea el .env" "$P/.env"

titulo "listar"
P="$T/demo"; nuevo
puerto -- listar
contiene "sin proyectos lo dice" "$OUT" 'sin proyectos registrados'
printf 'zeta\t4020\nalfa\t4000\n' > "$REG"; SS_PUERTOS="4001"
puerto -- listar
igual "ordena por bloque" "alfa zeta" "$(printf '%s\n' "$OUT" | awk 'NR > 1 { printf "%s%s", s, $1; s = " " }')"
contiene "marca lo que esta corriendo" "$OUT" '^alfa +4000   libre +4001 ● corriendo'

titulo "quien"
P="$T/demo"; nuevo
printf 'demo\t4000\n' > "$REG"; SS_PUERTOS="4001 4033"
puerto -- quien 4001
contiene "un puerto de un proyecto registrado: dice cual y que corre" "$OUT" "es del proyecto 'demo' \(bloque 4000, \+1\)  ● corriendo"
puerto -- quien 4033
contiene "uno ocupado por algo sin registrar" "$OUT" 'no es un proyecto registrado'
puerto -- quien 4040
contiene "uno libre y sin dueño" "$OUT" 'esta libre y no pertenece a ningun proyecto'
puerto -- quien 3995
no_contiene "uno fuera del rango no se atribuye al primer bloque" "$OUT" "proyecto 'demo'"

titulo "liberar"
P="$T/demo"; nuevo
printf 'demo\t4000\notro\t4010\n' > "$REG"; printf 'PORT=4001\n' > "$P/.env"
puerto -- liberar
igual "saca solo ese proyecto del registro" "otro"$'\t'"4010" "$(cat "$REG")"
igual "el .env conserva los numeros viejos" "PORT=4001" "$(cat "$P/.env")"
puerto -- liberar nadie
igual "uno que no esta registrado: sale con 0" 0 "$ST"
contiene "  y lo dice" "$OUT" "'nadie' no esta registrado"

titulo "sin comando"
puerto --
igual "sale con 1" 1 "$ST"
contiene "muestra el uso" "$OUT" 'puerto asignar \[nombre\]'

terminar
