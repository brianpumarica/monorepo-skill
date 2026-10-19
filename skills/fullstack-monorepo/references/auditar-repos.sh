#!/usr/bin/env bash
# Chequeo ESTATICO de un repo contra la checklist de fullstack-monorepo (SKILL.md §7). Es lo que
# corre `analiza` como primer paso, y se puede correr suelto en cualquier repo. No cambia nada, no
# necesita Docker ni red (salvo `git ls-remote` para saber si existe la rama develop).
#
#   bash auditar-repos.sh [carpeta-del-repo]        # por defecto, la carpeta actual
#   bash auditar-repos.sh [carpeta] --plano         # una linea por regla:  repo|regla|OK|FALTA ...|n/a
#
# Desde un repo que tiene la skill instalada:
#   bash .agents/skills/fullstack-monorepo/references/auditar-repos.sh
#
# Sale con 0 si no hay ninguna regla en FALTA, con 1 si hay alguna, con 2 si la carpeta no existe.
# Cada linea es una regla de la skill; «n/a» es lo que el perfil del repo no exige (SKILL §2,
# perfiles-de-despliegue.md): un repo solo de frontend no tiene docker-compose y no le falta nada.
#
# Que NO mira: lo que hay en el servidor (eso es el modo `inspecciona`), el contenido de docs/ (lo
# arma una skill de documentacion aparte) y si la integracion de Git de Vercel sigue conectada (eso
# vive en la API de Vercel; `alta-proyecto.sh --paso 2` la desconecta).
set -uo pipefail

PLANO=0; r=.
for a in "$@"; do
  case "$a" in
    --plano) PLANO=1 ;;
    -h | --help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) r=$a ;;
  esac
done
cd "$r" 2>/dev/null || { echo "auditar-repos: no existe la carpeta '$r'" >&2; exit 2; }
repo=$(basename "$PWD")

OKS=0; MALS=0; NAS=0; FASE=""
# La fase es el primer caracter del nombre de la regla ("1 .gitattributes..." -> fase 1).
titulo_fase() {
  [ "$PLANO" -eq 0 ] && [ "${1%% *}" != "$FASE" ] || return 0
  FASE=${1%% *}
  case "$FASE" in
    0) echo; echo "Skill y perfil" ;; 1) echo; echo "Fase 1 · Normalizacion de raiz" ;;
    2) echo; echo "Fase 2 · Docker Compose" ;; 3) echo; echo "Fase 3 · Backend" ;;
    4) echo; echo "Fase 4 · Frontend" ;; 5) echo; echo "Fase 5 · CI/CD" ;; 6) echo; echo "Fase 6 · Documentacion y agentes" ;;
    *) echo ;;
  esac
}
emitir() { # estado-plano simbolo regla [detalle]
  if [ "$PLANO" -eq 1 ]; then printf '%s|%s|%s\n' "$repo" "$3" "$1${4:+ $4}"
  else titulo_fase "$3"; printf '  %s %s%s\n' "$2" "$3" "${4:+  $4}"; fi
}
ok()  { OKS=$((OKS + 1));   emitir OK   "✅" "$1"; }
mal() { MALS=$((MALS + 1)); emitir FALTA "❌" "$1" "${2:-}"; }
na()  { NAS=$((NAS + 1));   emitir n/a  "➖" "$1"; }
# chk "regla" "comando": OK si el comando sale con 0. El comando es codigo de este script, no del repo.
chk() { local n=$1; shift; if eval "$*" >/dev/null 2>&1; then ok "$n"; else mal "$n"; fi; }
# Sin las lineas de comentario: un `${VAR}`, `localhost` o `|| true` escrito en un comentario no cuenta.
sincom() { cat "$@" 2>/dev/null | grep -v '^[[:space:]]*#'; }

# Restos de v0: la metadata `generator: 'v0.app'` del layout y un paquete llamado v0-* / my-v0-*.
restos_v0() {
  ! grep -rqE "generator: *['\"]v0" --include='layout.*' --exclude-dir=node_modules --exclude-dir=.next . 2>/dev/null \
    && ! grep -qsE '"name": *"(my-)?v0-' package.json ./*/package.json
}

# --- Que tiene el repo ----------------------------------------------------------
BACK=""; for d in backend apps/api api server; do [ -f "$d/Dockerfile" ] && { BACK=$d; break; }; done
FRONT=""; for d in frontend apps/web web mobile; do [ -d "$d" ] && { FRONT=$d; break; }; done
WF=.github/workflows/deploy.yml
WFV=.github/workflows/deploy-vercel.yml
PROD=docker-compose.prod.yml
DEV=docker-compose.yml
HAYDOCKER=0
# (find y no ls: `ls` sale con error si UN solo comodin no coincide, aunque otros si.)
if find . -maxdepth 3 \( -name 'Dockerfile*' -o -name 'docker-compose*.yml' \) -not -path '*/node_modules/*' | grep -q .; then HAYDOCKER=1; fi
HAYDB=0; grep -qi postgres $DEV $PROD 2>/dev/null && HAYDB=1
NEXTCFG=$(find . -maxdepth 3 -name 'next.config.*' -not -path '*/node_modules/*' | head -20 | tr '\n' ' ')

# Perfil: sin Docker es el B (solo frontend); con Docker, A/C/D comparten la checklist.
if [ "$HAYDOCKER" -eq 0 ]; then PERFIL=B; else PERFIL=A; fi
[ "$PLANO" -eq 1 ] || echo "Repo: $repo   perfil: $PERFIL$([ "$PERFIL" = B ] && echo ' (solo frontend: Docker, .env del servidor, backups y Tunnel son n/a)')"

# --- Skill instalada y su version -------------------------------------------------
SK=""; for d in .agents/skills/fullstack-monorepo .claude/skills/fullstack-monorepo; do [ -f "$d/SKILL.md" ] && { SK=$d; break; }; done
if [ -n "$SK" ]; then
  chk "0 la copia de la skill tiene numero de version" "grep -qE '^[[:space:]]+version: *\"?[0-9]+\.[0-9]+\.[0-9]+' $SK/SKILL.md"
  chk "0 AGENTS.md anota la version de la skill"       "grep -qE 'fullstack-monorepo.*v?[0-9]+\.[0-9]+\.[0-9]+' AGENTS.md"
else na "0 copia de la skill (no esta instalada en este repo)"; fi

# --- Fase 1 -----------------------------------------------------------------------
chk "1 .gitattributes eol=lf"            "grep -q 'eol=lf' .gitattributes"
chk "1 .gitignore"                       "[ -f .gitignore ]"
if [ "$HAYDOCKER" -eq 1 ]; then
  chk "1 .gitattributes cubre crontab"   "grep -q '^crontab\|scripts/crontab\|/crontab\|^\* .*eol=lf' .gitattributes"
  # El .dockerignore va junto a cada contexto de build: el de la raiz solo sirve si hay `context: .`.
  if grep -qE 'context: *\.?/?$' $DEV $PROD 2>/dev/null; then
    chk "1 .dockerignore raiz"           "[ -f .dockerignore ]"
  else na "1 .dockerignore raiz (ningun build usa la raiz)"; fi
  [ -n "$BACK" ] && chk "1 .dockerignore backend" "[ -f $BACK/.dockerignore ]"
  chk "1 package.json raiz docker:dev"   "grep -q '\"docker:dev\"' package.json"
else
  na "1 .dockerignore y package.json docker:* (sin Docker)"
fi

# --- Fase 2: compose --------------------------------------------------------------
if [ "$HAYDOCKER" -eq 1 ]; then
  chk "2 docker-compose.yml (dev)"          "[ -f $DEV ]"
  chk "2 sin docker-compose.dev.yml"        "[ ! -f docker-compose.dev.yml ]"
  chk "2 prod: restart unless-stopped"      "grep -q 'unless-stopped' $PROD"
  chk "2 prod: healthcheck"                 "grep -q 'healthcheck' $PROD"
  chk "2 prod: healthcheck sin localhost"   "! sincom $PROD | grep -A4 healthcheck | grep -q 'localhost'"
  chk "2 prod: rotacion de logs"            "grep -q 'max-size' $PROD"
  chk "2 prod: labels com.proyecto"         "grep -q 'com.proyecto' $PROD"
  # Solo las entradas bajo `ports:`: la linea del volumen (`- ${VOL}:/ruta`) no es un puerto.
  puertos() { awk '/^[[:space:]]*ports:/{p=1;next} p&&/^[[:space:]]*-/{print;next} {p=0}' "$1"; }
  chk "2 prod: puertos en 127.0.0.1"        "! puertos $PROD | grep -v '127.0.0.1' | grep -q ':'"
  chk "2 .env.example con HEALTH_PATH"      "grep -q '^HEALTH_PATH' .env.example"
  miss=$(sincom $DEV $PROD | grep -oE '\$\{[A-Z_][A-Z0-9_]*' | cut -c3- | sort -u | grep -vx IMAGE_TAG \
    | while read -r v; do grep -q "^$v=" .env.example 2>/dev/null || echo "$v"; done | tr '\n' ' ')
  if [ -z "$miss" ]; then ok "2 vars del compose en .env.example"; else mal "2 vars del compose en .env.example" "($miss)"; fi
  raras=$(cat $DEV $PROD .env.example 2>/dev/null | grep -oE '\b[A-Z_]*_PORT\b' | sort -u \
    | grep -vE '^(BACKEND_HOST_PORT|DB_HOST_PORT|FRONTEND_HOST_PORT|PORT|DB_PORT|POSTGRES_PORT_INTERNAL)$' | tr '\n' ' ')
  if [ -z "$raras" ]; then ok "2 nombres de puertos del contrato"; else mal "2 nombres de puertos del contrato" "($raras)"; fi
  # IMAGE_TAG la define el deploy (SHA). Definida en .env.example, crear-env la copia al .env del
  # servidor y el `. ./.env` del paso de promocion pisa el SHA con ese valor: last-good-tag vacio.
  chk "2 .env.example sin IMAGE_TAG="       "! grep -q '^IMAGE_TAG=' .env.example"
  # Dev y prod no comparten nombre de contenedor de la base ni de volumen (compose-recipes §0.3).
  if [ "$HAYDB" -eq 1 ]; then
    dbdev=$(sincom $DEV | grep -m1 -A12 '^  database:' | grep -m1 container_name | sed 's/.*container_name: *//')
    dbprod=$(sincom $PROD | grep -m1 -A12 '^  database:' | grep -m1 container_name | sed 's/.*container_name: *//')
    if [ -n "$dbdev" ] && [ "$dbdev" = "$dbprod" ]; then mal "2 dev: la base no comparte nombre con prod" "($dbdev)"; else ok "2 dev: la base no comparte nombre con prod"; fi
    voldev=$(sincom $DEV | awk '/^volumes:/{v=1;next} v&&/name:/{print;exit}' | sed 's/.*name: *//')
    volprod=$(sincom $PROD | awk '/^volumes:/{v=1;next} v&&/name:/{print;exit}' | sed 's/.*name: *//')
    if [ -n "$voldev" ] && [ "$voldev" = "$volprod" ]; then mal "2 dev: el volumen de la base no comparte nombre con prod" "($voldev)"; else ok "2 dev: el volumen de la base no comparte nombre con prod"; fi
  fi
  # Recarga en dev: CHOKIDAR_USEPOLLING (tsx/vite), legacyWatch de nodemon, WATCHPACK_POLLING (Next),
  # `uvicorn --reload` (watchfiles ve los cambios del bind mount de Docker Desktop sin polling: probado).
  if [ -n "$BACK" ]; then
    chk "2 dev: recarga del backend"        "grep -q 'CHOKIDAR_USEPOLLING' $DEV || grep -q '\"legacyWatch\": *true' $BACK/nodemon.json 2>/dev/null || grep -q -- '--reload' $BACK/Dockerfile $DEV"
  fi
  if [ -n "$FRONT" ] && ls $FRONT/next.config.* >/dev/null 2>&1 && grep -q 'context: \./*'"$FRONT" $DEV; then
    chk "2 dev: WATCHPACK_POLLING (Next)"   "grep -q 'WATCHPACK_POLLING' $DEV"
  fi
else
  na "2 docker-compose (sin Docker)"
fi

# --- Fase 3: backend --------------------------------------------------------------
if [ -n "$BACK" ]; then
  E=$BACK/entrypoint.sh
  if [ -f "$E" ]; then
    chk "3 entrypoint: pg_isready"        "grep -q pg_isready $E"
    chk "3 entrypoint: exec \"\$@\""       "grep -q 'exec \"\$@\"' $E"
    chk "3 entrypoint: APP_DIR anclado"   "grep -q 'APP_DIR' $E"
    chk "3 entrypoint: sin || true"       "! sincom $E | grep -q '|| true'"
    chk "3 Dockerfile: postgresql-client" "grep -q 'postgresql-client' $BACK/Dockerfile"
  elif [ "$HAYDB" -eq 1 ]; then mal "3 entrypoint.sh"
  else na "3 entrypoint.sh (sin base)"; fi
  chk "3 Dockerfile: USER no root"        "grep -qE '^USER +(node|appuser|[a-z]+)' $BACK/Dockerfile"
  chk "3 Dockerfile: sin || true"         "! sincom $BACK/Dockerfile | grep -q '|| true'"
else
  na "3 backend (no hay un Dockerfile de backend)"
fi

# --- Fase 4: frontend -------------------------------------------------------------
if [ -n "$FRONT" ] && ls $FRONT/next.config.* >/dev/null 2>&1; then
  na "4 nginx.conf / vercel.json (Next.js: no es SPA)"
elif [ -n "$FRONT" ] && [ "$PERFIL" = A ]; then
  # nginx solo si el compose de prod sirve el frontend; si va solo a Vercel, no hay nginx.
  if grep -q "context: *\./*$FRONT" $PROD 2>/dev/null; then
    chk "4 nginx.conf try_files"          "grep -q 'try_files' $FRONT/nginx.conf"
    chk "4 nginx.conf gzip"               "grep -q 'gzip on' $FRONT/nginx.conf"
    chk "4 Dockerfile nginx:alpine"       "grep -q 'nginx:.*alpine' $FRONT/Dockerfile"
  else na "4 nginx.conf (el frontend no va en el compose de prod)"; fi
  chk "4 vercel.json rewrites"            "grep -q 'rewrites' $FRONT/vercel.json"
else na "4 frontend con servidor propio (no tiene)"; fi

# --- Fase 5: workflows (todos los perfiles) ----------------------------------------
if ! ls .github/workflows/*.yml >/dev/null 2>&1; then
  mal "5 workflow de despliegue" "(no hay .github/workflows/*.yml)"
else
  ALLWF=$(ls .github/workflows/*.yml | tr '\n' ' ')
  # Node 20 en las acciones: checkout/setup-node @v4 dan el aviso de deprecacion en cada corrida.
  chk "5 wf: acciones sin el aviso de Node 20" "! grep -hE 'uses: *actions/(checkout|setup-node)@v[1-4]\b' $ALLWF"
  chk "5 wf: secretos solo por env:"           "! grep -nE 'run:.*secrets\.|--[a-z-]+=.*secrets\.' $ALLWF"
  # `concurrency` a nivel workflow en uno que corre en PR: el PR cancela el deploy en cola.
  for w in $ALLWF; do
    if grep -q '^concurrency:' "$w" && grep -q 'pull_request' "$w" && grep -q 'production-deploy' "$w"; then
      mal "5 wf: concurrency de deploy a nivel job, no workflow" "($w)"; CONC=1
    fi
  done
  [ -n "${CONC:-}" ] || ok "5 wf: concurrency de deploy a nivel job, no workflow"
fi

if [ "$PERFIL" = B ]; then
  # Solo frontend: deploy-vercel.yml es EL workflow de despliegue (no se exige el deploy.yml dual).
  if [ -f "$WFV" ]; then
    ok "5 deploy-vercel.yml (perfil solo frontend)"
    chk "5 wf: permissions contents: read"   "grep -A1 '^permissions:' $WFV | grep -q 'contents: read'"
    nr=$(grep -c 'runs-on:' $WFV); nt=$(grep -c 'timeout-minutes' $WFV)
    if [ "$nt" -ge "$nr" ]; then ok "5 wf: timeout-minutes en todos los jobs"; else mal "5 wf: timeout-minutes en todos los jobs" "($nt de $nr)"; fi
    chk "5 wf: valida en los PR"             "grep -q 'pull_request' $WFV"
    chk "5 wf: solo publica desde main"      "grep -q \"github.event_name != 'pull_request'\" $WFV"
    chk "5 wf: job de validacion antes del deploy" "grep -qE '^ +(validate|lint|test|typecheck|ci|check)[a-z-]*:' $WFV && grep -q 'needs:' $WFV"
    chk "5 wf: smoke test despues del deploy" "grep -qiE 'smoke|curl' $WFV"
  else
    mal "5 deploy-vercel.yml" "(repo sin Docker: falta el workflow que publica en Vercel)"
  fi
  na "5 scripts del servidor, backups, Tunnel y .env del servidor (sin servidor)"
else
  if [ -f "$WF" ]; then
    chk "5 wf: permissions contents: read"    "grep -A1 '^permissions:' $WF | grep -q 'contents: read'"
    nr=$(grep -c 'runs-on:' $WF); nt=$(grep -c 'timeout-minutes' $WF)
    if [ "$nt" -ge "$nr" ]; then ok "5 wf: timeout-minutes en todos los jobs"; else mal "5 wf: timeout-minutes en todos los jobs" "($nt de $nr)"; fi
    chk "5 wf: tag por commit (IMAGE_TAG)"    "grep -q 'IMAGE_TAG' $WF"
    chk "5 wf: rollback"                      "grep -qi 'rollback\|last-good' $WF"
    if [ "$HAYDB" -eq 1 ]; then chk "5 wf: backup pre-deploy" "grep -q 'pre-deploy' $WF"; else na "5 wf: backup pre-deploy (sin base)"; fi
    chk "5 wf: chequear-host"                 "grep -q 'chequear-host' $WF"
    chk "5 wf: .env de env-backups"           "grep -q 'env-backups' $WF"
    chk "5 wf: REQUIRED_SECRETS"              "grep -q 'REQUIRED_SECRETS' $WF"
    chk "5 wf: sin cp .env.example"           "! grep -q 'cp .env.example' $WF"
    chk "5 wf: verificacion post-deploy"      "grep -qiE 'smoke|healthy|curl' $WF"
    chk "5 wf: poda acotada al proyecto"      "grep -q 'label=com.proyecto' $WF && ! grep -v '^[[:space:]]*#' $WF | grep -q 'system prune'"
    chk "5 wf: --force-recreate"              "grep -q 'force-recreate' $WF"
    if grep -qi vercel $WF; then
      chk "5 wf: frontend con needs:"         "grep -q 'needs:' $WF"
      chk "5 wf: secret API_URL"              "grep -q 'secrets.API_URL' $WF"
    fi
    chk "5 wf: tunel-agregar"                 "grep -q 'tunel-agregar' $WF"
    # El paso del Tunnel solo corre con TUNEL_HOST: si no, un proyecto con otra ruta crea una nueva.
    if grep -q 'tunel-agregar' $WF; then chk "5 wf: tunel-agregar solo con TUNEL_HOST" "grep -B8 'tunel-agregar' $WF | grep -q TUNEL_HOST"; fi
    # Un job de validacion (validate / lint / test / ci / check) o el workflow reutilizable validate.yml.
    chk "5 wf: validacion antes del deploy" "grep -qE '^ +(validate|lint|test|typecheck|ci|check)[a-z-]*:|uses: *./.github/workflows/' $WF"
  else
    mal "5 deploy.yml" "(el repo usa Docker y no tiene .github/workflows/deploy.yml)"
  fi
  for s in crear-env rotar-secretos chequear-host; do chk "5 scripts/$s.sh" "[ -f scripts/$s.sh ]"; done
  if [ "$HAYDB" -eq 1 ]; then
    for s in backup verificar-backup; do chk "5 scripts/$s.sh" "[ -f scripts/$s.sh ]"; done
    chk "5 scripts/crontab"                   "[ -f scripts/crontab ]"
  else na "5 backup.sh / verificar-backup.sh / crontab (sin base)"; fi
  chk "5 rama develop"                        "git ls-remote --exit-code --heads origin develop"
fi

# --- Codigo del frontend: anti-patrones de v0 y de builds que callan errores ----------
if [ -n "$NEXTCFG" ]; then
  # shellcheck disable=SC2086  # NEXTCFG es una lista de archivos sin espacios
  chk "5 next.config: sin ignoreBuildErrors"  "! sincom $NEXTCFG | grep -qE 'ignoreBuildErrors: *true'"
  # shellcheck disable=SC2086
  chk "5 next.config: sin ignoreDuringBuilds" "! sincom $NEXTCFG | grep -qE 'ignoreDuringBuilds: *true'"
  chk "5 sin restos de v0 (metadata y nombre)" restos_v0
else
  na "5 next.config (no hay Next.js)"
fi

# --- Fase 6 -----------------------------------------------------------------------
# docs/ (architecture, deployment, api-reference) los arma una skill aparte, no esta auditoria.
na "6 docs/*.md (otra skill)"
chk "6 AGENTS.md"                         "[ -f AGENTS.md ]"
chk "6 README.md"                         "[ -f README.md ]"
if [ -d .agents/skills ] || [ -d .claude/skills ]; then
  d=$(diff <(ls .agents/skills 2>/dev/null) <(ls .claude/skills 2>/dev/null) | grep -c '^[<>]')
  if [ "$d" -eq 0 ]; then ok "6 skills: .agents y .claude iguales"; else mal "6 skills: .agents y .claude iguales" "($d distintas)"; fi
fi

# --- Resumen ----------------------------------------------------------------------
if [ "$PLANO" -eq 0 ]; then
  echo
  echo "Resumen: $OKS cumplen · $MALS faltan · $NAS no aplican"
  [ "$MALS" -eq 0 ] || echo "(esto es solo el chequeo estatico: el plan completo lo arma \`analiza\`)"
fi
[ "$MALS" -eq 0 ]
