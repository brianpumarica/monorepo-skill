#!/usr/bin/env bash
# Puertos fijos por proyecto en TU MAQUINA de desarrollo (Windows con Git Bash, Linux o macOS).
# NO va dentro de un repo: se instala UNA vez en el PATH (por ejemplo ~/bin/puerto) y sirve para
# todos tus proyectos, con Docker o sin Docker.
#
#   puerto asignar [nombre]   # le da al proyecto un bloque de puertos propio y lo escribe en .env
#   puerto listar             # tus proyectos, sus puertos y cuales estan corriendo AHORA
#   puerto quien <puerto>     # que proyecto (o proceso) usa un puerto
#   puerto liberar [nombre]   # devuelve el bloque del proyecto
#
# Idea: cada proyecto recibe SIEMPRE el mismo bloque de 10 puertos dentro de 4000-4999 (lejos del
# 3000, 5173, 8080, 5432 que usan todos los tutoriales), derivado de su nombre. El mismo numero
# sirve por fuera y por dentro del contenedor, asi `npm run dev` y `docker compose up` usan el
# mismo .env y el mismo puerto: no hay que pedirselo a nadie ni acordarse.
#
#   bloque+0  FRONTEND_HOST_PORT / FRONTEND_PORT      bloque+2  DB_HOST_PORT
#   bloque+1  BACKEND_HOST_PORT  / PORT               bloque+3..9  libres para lo que haga falta
#
# El registro vive en ~/.puertos (nombre<TAB>bloque), fuera de cualquier repo: ahi estan los
# nombres de tus proyectos y no tienen que ir a un repositorio publico.
# Variables: PUERTOS_REGISTRO (archivo), PUERTOS_INICIO (default 4000), PUERTOS_FIN (default 4999).
set -uo pipefail

REGISTRO=${PUERTOS_REGISTRO:-$HOME/.puertos}
INICIO=${PUERTOS_INICIO:-4000}
FIN=${PUERTOS_FIN:-4999}
ANCHO=10
touch "$REGISTRO"

# ¿Hay algo escuchando en el puerto? ss si existe (Linux); si no, un intento de conexion en bash puro
# (Git Bash y macOS no traen ss). El mismo criterio que chequear-host.sh.
escuchando() {
  if command -v ss >/dev/null 2>&1; then [ -n "$(ss -ltnH "sport = :$1" 2>/dev/null)" ]
  else (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; fi
}

bloque_de() { awk -F'\t' -v n="$1" '$1 == n { print $2 }' "$REGISTRO"; }
dueno_de() { awk -F'\t' -v b="$1" '$2 == b { print $1 }' "$REGISTRO"; }

# Algun puerto del bloque ocupado por un proceso que NO es de un proyecto registrado y corriendo.
bloque_ocupado() {
  local b=$1 i
  for i in 0 1 2 3 4 5 6 7 8 9; do escuchando $((b + i)) && return 0; done
  return 1
}

nombre_proyecto() { echo "${1:-$(basename "$PWD")}"; }

asignar() {
  local nombre; nombre=$(nombre_proyecto "${1:-}")
  local b; b=$(bloque_de "$nombre")
  if [ -z "$b" ]; then
    local total=$(((FIN - INICIO + 1) / ANCHO))
    local hash; hash=$(printf '%s' "$nombre" | cksum | cut -d' ' -f1)
    local i=0 cand
    while [ "$i" -lt "$total" ]; do
      cand=$((INICIO + ((hash + i) % total) * ANCHO))
      # Libre = nadie lo tiene registrado y nada lo esta escuchando.
      if [ -z "$(dueno_de "$cand")" ] && ! bloque_ocupado "$cand"; then b=$cand; break; fi
      i=$((i + 1))
    done
    [ -n "$b" ] || { echo "❌ No queda ningun bloque libre entre $INICIO y $FIN."; return 1; }
    printf '%s\t%s\n' "$nombre" "$b" >> "$REGISTRO"
    echo "✅ '$nombre' recibio el bloque $b-$((b + ANCHO - 1))"
  else
    echo "ℹ️  '$nombre' ya tenia el bloque $b-$((b + ANCHO - 1)) (siempre es el mismo)"
  fi
  escribir_env "$b"
}

# Escribe/actualiza SOLO las variables de puertos en .env; no toca nada mas.
escribir_env() {
  local b=$1 f=.env
  [ -f "$f" ] || : > "$f"
  poner() {
    if grep -q "^$1=" "$f"; then sed "s|^$1=.*|$1=$2|" "$f" > "$f.tmp" && mv "$f.tmp" "$f"; else printf '%s=%s\n' "$1" "$2" >> "$f"; fi
  }
  poner FRONTEND_HOST_PORT $((b))
  poner FRONTEND_PORT $((b))
  poner BACKEND_HOST_PORT $((b + 1))
  poner PORT $((b + 1))
  poner DB_HOST_PORT $((b + 2))
  echo "   .env  ->  frontend $b | backend $((b + 1)) | base $((b + 2))"
  echo "   http://localhost:$b (frontend)   http://localhost:$((b + 1)) (backend)"
  if [ -f .gitignore ] && ! grep -qE '^\.env$' .gitignore; then
    echo "   ⚠️  .env no esta en .gitignore: agregarlo antes de commitear."
  fi
}

estado() { if escuchando "$1"; then echo "● corriendo"; else echo "  libre"; fi; }

listar() {
  if [ ! -s "$REGISTRO" ]; then echo "(sin proyectos registrados; usar: puerto asignar)"; return 0; fi
  printf '%-28s %-22s %-22s %s\n' PROYECTO FRONTEND BACKEND BASE
  sort -t$'\t' -k2n "$REGISTRO" | while IFS=$'\t' read -r n b; do
    [ -n "$n" ] || continue
    printf '%-28s %-22s %-22s %s\n' "$n" "$b $(estado "$b")" "$((b + 1)) $(estado $((b + 1)))" "$((b + 2)) $(estado $((b + 2)))"
  done
}

quien() {
  local p=${1:?Uso: puerto quien <puerto>}
  local b=$(((p - INICIO) / ANCHO * ANCHO + INICIO)) d
  d=$(dueno_de "$b")
  if [ "$p" -ge "$INICIO" ] && [ "$p" -le "$FIN" ] && [ -n "$d" ]; then
    echo "El puerto $p es del proyecto '$d' (bloque $b, +$((p - b)))  $(estado "$p")"
  elif escuchando "$p"; then
    echo "El puerto $p esta en uso por algo que no es un proyecto registrado."
    command -v netstat >/dev/null 2>&1 && netstat -ano 2>/dev/null | grep -E "[:.]${p}[[:space:]].*LISTEN" | head -3
    echo "   (en Windows: tasklist //FI \"PID eq <PID>\"; en Linux/macOS: lsof -i :$p)"
  else
    echo "El puerto $p esta libre y no pertenece a ningun proyecto."
  fi
}

liberar() {
  local nombre; nombre=$(nombre_proyecto "${1:-}")
  [ -n "$(bloque_de "$nombre")" ] || { echo "'$nombre' no esta registrado."; return 0; }
  awk -F'\t' -v n="$nombre" '$1 != n' "$REGISTRO" > "$REGISTRO.tmp" && mv "$REGISTRO.tmp" "$REGISTRO"
  echo "✅ Bloque de '$nombre' devuelto. (El .env del proyecto conserva los numeros viejos.)"
}

case "${1:-}" in
  asignar) asignar "${2:-}" ;;
  listar) listar ;;
  quien) quien "${2:-}" ;;
  liberar) liberar "${2:-}" ;;
  *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
