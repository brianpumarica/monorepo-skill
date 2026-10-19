#!/usr/bin/env bash
# Pruebas de references/auditar-repos.sh: un repo de ejemplo que cumple todo (perfil A), uno solo de
# frontend (perfil B) y, sobre copias, un cambio a la vez que tiene que dar exactamente esa regla en FALTA.
. "$(dirname "$0")/lib.sh"
command -v git >/dev/null || { echo "sin git: se omite"; exit 0; }

AUDIT="$REF/auditar-repos.sh"
GIT=(git -c user.name=t -c user.email=t@t.test -c init.defaultBranch=main -c core.autocrlf=false -c core.safecrlf=false)

# escribe <ruta> <contenido con \n>
escribe() { mkdir -p "$(dirname "$1")"; printf '%b' "$2" > "$1"; }

# Repo de perfil A que cumple TODA la checklist estatica.
repo_a() {
  local d=$1
  mkdir -p "$d" && cd "$d" || return 1
  escribe .gitattributes '* text=auto\n*.sh text eol=lf\ncrontab text eol=lf\n'
  escribe .gitignore 'node_modules\n.env\n'
  escribe package.json '{"name":"demo","scripts":{"docker:dev":"docker compose up -d"}}\n'
  escribe README.md '# demo\n'
  escribe AGENTS.md '# AGENTS\n- `fullstack-monorepo` **v1.0.0**: orquestador\n'
  escribe backend/Dockerfile 'FROM node:22-alpine AS base\nRUN apk add --no-cache postgresql-client\nUSER node\nENTRYPOINT ["/app/entrypoint.sh"]\n'
  escribe backend/.dockerignore 'node_modules\n'
  escribe backend/entrypoint.sh '#!/bin/sh\nAPP_DIR=$(cd "$(dirname "$0")" && pwd)\nuntil pg_isready; do sleep 1; done\nexec "$@"\n'
  escribe docker-compose.yml 'services:
  database:
    image: postgres:16-alpine
    container_name: ${PROJECT_PREFIX:-app}-database-dev
    ports:
      - "127.0.0.1:${DB_HOST_PORT:-5432}:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
  backend:
    build:
      context: ./backend
    environment:
      CHOKIDAR_USEPOLLING: "true"
      PORT: ${PORT:-3004}
volumes:
  pgdata:
    name: ${PROJECT_PREFIX:-app}_pgdata-dev
'
  escribe docker-compose.prod.yml 'services:
  database:
    image: postgres:16-alpine
    container_name: ${PROJECT_PREFIX:-app}-database
    restart: unless-stopped
    logging:
      options:
        max-size: "10m"
    volumes:
      - pgdata:/var/lib/postgresql/data
  backend:
    build:
      context: ./backend
      labels:
        com.proyecto: ${PROJECT_PREFIX:-app}
    restart: unless-stopped
    logging:
      options:
        max-size: "10m"
    ports:
      - "127.0.0.1:${BACKEND_HOST_PORT:-3004}:${PORT:-3004}"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:$$PORT$${HEALTH_PATH:-/api/health} || exit 1"]
volumes:
  pgdata:
    name: ${VOLUME_PGDATA_NAME:-${PROJECT_PREFIX:-app}_pgdata}
'
  escribe .env.example 'PROJECT_PREFIX=app\nDB_HOST_PORT=\nBACKEND_HOST_PORT=\nPORT=3004\nHEALTH_PATH=/api/health\nVOLUME_PGDATA_NAME=\n'
  local s
  for s in crear-env rotar-secretos chequear-host backup verificar-backup; do escribe "scripts/$s.sh" '#!/bin/bash\n'; done
  escribe scripts/crontab '0 3 * * * __DIR__/scripts/backup.sh >> __DIR__/backup.log 2>&1\n'
  escribe .github/workflows/validate.yml 'name: Validate\non:\n  pull_request:\n  workflow_call:\npermissions:\n  contents: read\njobs:\n  validate:\n    runs-on: ubuntu-latest\n    timeout-minutes: 15\n    steps:\n      - uses: actions/checkout@v5\n'
  escribe .github/workflows/deploy.yml 'name: Deploy
on:
  push:
    branches: [main]
permissions:
  contents: read
env:
  IMAGE_TAG: ${{ github.sha }}
jobs:
  validate:
    uses: ./.github/workflows/validate.yml
  deploy-backend:
    needs: validate
    runs-on: [self-hosted, linux, rpi5]
    timeout-minutes: 30
    concurrency:
      group: production-deploy
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@v5
      - name: env
        env:
          ENV_STORE: /home/x/env-backups/r/.env
          REQUIRED_SECRETS: "JWT_SECRET"
        run: cp "$ENV_STORE" .env
      - run: bash scripts/chequear-host.sh
      - run: echo pre-deploy
      - run: docker compose -f docker-compose.prod.yml up -d --build --force-recreate
      - run: |
          rollback() { echo last-good; }
          curl -fsS "http://localhost:3004/api/health" # smoke
      - run: docker image prune -af --filter "label=com.proyecto=app"
      - name: Register Cloudflare Tunnel route
        run: |
          TUNEL_HOST=$(grep -m1 "^TUNEL_HOST=" .env | cut -d= -f2-)
          [ -z "$TUNEL_HOST" ] || sudo -n /usr/local/sbin/tunel-agregar repo
  deploy-frontend:
    needs: deploy-backend
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v5
      - run: vercel build
        env:
          NEXT_PUBLIC_API_URL: ${{ secrets.API_URL }}
'
  local sk
  for sk in .agents/skills .claude/skills; do escribe "$sk/fullstack-monorepo/SKILL.md" '---\nname: fullstack-monorepo\nmetadata:\n  version: "1.0.0"\n---\n'; done
  "${GIT[@]}" init -q . && git init -q --bare "$d.remote" 2>/dev/null
  "${GIT[@]}" remote add origin "$d.remote" && "${GIT[@]}" add -A && "${GIT[@]}" commit -q -m base \
    && "${GIT[@]}" push -q origin HEAD:develop 2>/dev/null
  cd "$T" || return 1
}

# Repo de perfil B: solo frontend en Vercel, sin Docker.
repo_b() {
  local d=$1
  mkdir -p "$d" && cd "$d" || return 1
  escribe .gitattributes '* text=auto\n*.sh text eol=lf\n'
  escribe .gitignore 'node_modules\n.vercel\n'
  escribe package.json '{"name":"sitio","scripts":{"build":"next build"}}\n'
  escribe README.md '# sitio\n'
  escribe AGENTS.md '# AGENTS\n- `fullstack-monorepo` v1.0.0\n'
  escribe next.config.mjs 'export default { reactStrictMode: true }\n'
  escribe .github/workflows/deploy-vercel.yml 'name: Deploy a Vercel
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
permissions:
  contents: read
jobs:
  validate:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v5
  deploy:
    needs: validate
    runs-on: ubuntu-latest
    timeout-minutes: 15
    concurrency:
      group: vercel-${{ github.ref }}
    steps:
      - uses: actions/checkout@v5
      - name: Deploy a produccion
        if: github.event_name != '"'"'pull_request'"'"'
        run: vercel deploy --prebuilt --prod
      - name: Smoke test
        if: github.event_name != '"'"'pull_request'"'"'
        run: curl -fsSL "$SITE_URL"
'
  cd "$T" || return 1
}

# audita <carpeta> [args]  ->  OUT, ST
audita() { local d=$1; shift; OUT=$(bash "$AUDIT" "$d" "$@" 2>&1); ST=$?; }
# Una regla concreta salio en FALTA / OK / n/a
falta() { contiene "$1" "$OUT" "❌ $2"; }
cumple() { contiene "$1" "$OUT" "✅ $2"; }
# cambio "descripcion" "regla que debe quedar en FALTA" 'comando a correr en una copia del repo A'
cambio() {
  local copia="$T/copia"; rm -rf "$copia" "$copia.remote"; cp -a "$A" "$copia"; cp -a "$A.remote" "$copia.remote"
  ( cd "$copia" && git remote set-url origin "$copia.remote" && eval "$3" ) >/dev/null 2>&1
  audita "$copia"
  igual "$1: sale con 1" 1 "$ST"
  falta "$1: la regla queda en FALTA" "$2"
}

A="$T/a"; B="$T/b"
repo_a "$A" || { fail "no pude armar el repo de ejemplo"; terminar; exit 1; }
repo_b "$B"

titulo "perfil A: un repo que cumple todo"
audita "$A"
igual "sale con 0" 0 "$ST"
contiene "dice el perfil" "$OUT" 'perfil: A'
contiene "resumen sin faltantes" "$OUT" '· 0 faltan ·'
no_contiene "ninguna regla en FALTA" "$OUT" '❌'
cumple "cuenta la version de la skill" '0 la copia de la skill tiene numero de version'
cumple "pide el job de validacion" '5 wf: validacion antes del deploy'
cumple "el Tunnel esta condicionado a TUNEL_HOST" '5 wf: tunel-agregar solo con TUNEL_HOST'
cumple "dev y prod no comparten el nombre de la base" '2 dev: la base no comparte nombre con prod'

titulo "salida --plano: una linea por regla"
audita "$A" --plano
igual "sale con 0" 0 "$ST"
contiene "formato repo|regla|estado" "$OUT" '^a\|1 \.gitattributes eol=lf\|OK$'
no_contiene "sin encabezados ni resumen" "$OUT" 'Resumen|Fase 1'

titulo "perfil A: un cambio a la vez"
cambio ".gitattributes borrado" '1 \.gitattributes eol=lf' 'rm .gitattributes'
cambio "puerto de prod en todas las interfaces" '2 prod: puertos en 127\.0\.0\.1' 'sed -i "s#127.0.0.1:\${BACKEND_HOST_PORT#\${BACKEND_HOST_PORT#" docker-compose.prod.yml'
cambio "healthcheck de prod con localhost" '2 prod: healthcheck sin localhost' 'sed -i "s#127.0.0.1:\$\$PORT#localhost:\$\$PORT#" docker-compose.prod.yml'
cambio "la base de dev con el nombre de la de prod" '2 dev: la base no comparte nombre con prod' 'sed -i "s#-database-dev#-database#" docker-compose.yml'
cambio "el volumen de dev con el nombre del de prod" '2 dev: el volumen de la base no comparte nombre con prod' 'sed -i "s#_pgdata-dev#_pgdata#" docker-compose.yml; sed -i "s#VOLUME_PGDATA_NAME:-\${PROJECT_PREFIX:-app}_pgdata#VOLUME_PGDATA_NAME:-x#; s#name: \${VOLUME_PGDATA_NAME:-x}#name: \${PROJECT_PREFIX:-app}_pgdata#" docker-compose.prod.yml'
cambio "variable del compose sin documentar" '2 vars del compose en \.env\.example' 'sed -i "/^HEALTH_PATH/d" .env.example'
cambio "IMAGE_TAG en .env.example" '2 \.env\.example sin IMAGE_TAG=' 'echo IMAGE_TAG= >> .env.example'
cambio "entrypoint sin exec" '3 entrypoint: exec' 'sed -i "/^exec/d" backend/entrypoint.sh'
cambio "workflow con checkout@v4 (aviso de Node 20)" '5 wf: acciones sin el aviso de Node 20' 'sed -i "0,/checkout@v5/s//checkout@v4/" .github/workflows/deploy.yml'
cambio "paso del Tunnel sin TUNEL_HOST" '5 wf: tunel-agregar solo con TUNEL_HOST' 'sed -i "s#^.*TUNEL_HOST=.*#          true#; s#\[ -z \"\$TUNEL_HOST\" \] || ##" .github/workflows/deploy.yml'
cambio "deploy sin el job de validacion" '5 wf: validacion antes del deploy' 'sed -i "/validate/d" .github/workflows/deploy.yml'
cambio "concurrency de deploy a nivel workflow con PR" '5 wf: concurrency de deploy a nivel job, no workflow' 'printf "concurrency:\n  group: production-deploy\n" >> .github/workflows/validate.yml'
cambio "secreto interpolado en run:" '5 wf: secretos solo por env:' 'echo "      - run: vercel --token=\${{ secrets.VERCEL_TOKEN }}" >> .github/workflows/deploy.yml'
cambio "AGENTS.md sin la version de la skill" '0 AGENTS\.md anota la version de la skill' 'echo "# AGENTS" > AGENTS.md'
cambio "copia de la skill sin numero de version" '0 la copia de la skill tiene numero de version' 'echo "---" > .agents/skills/fullstack-monorepo/SKILL.md'
cambio "next.config con ignoreBuildErrors" '5 next\.config: sin ignoreBuildErrors' 'mkdir frontend; echo "export default { typescript: { ignoreBuildErrors: true } }" > frontend/next.config.mjs'
cambio "layout con la marca de v0" '5 sin restos de v0' 'mkdir -p frontend/app; echo "export const metadata = { generator: '"'"'v0.app'"'"' }" > frontend/app/layout.tsx; echo "export default {}" > frontend/next.config.mjs'
cambio "sin la rama develop" '5 rama develop' 'git push -q origin :develop'

titulo "perfil B: solo frontend en Vercel"
audita "$B"
igual "sale con 0" 0 "$ST"
contiene "detecta el perfil B" "$OUT" 'perfil: B'
cumple "deploy-vercel.yml cuenta como workflow de despliegue" '5 deploy-vercel\.yml'
cumple "valida en los PR" '5 wf: valida en los PR'
cumple "solo publica desde main" '5 wf: solo publica desde main'
contiene "lo que es del servidor es n/a, no faltante" "$OUT" '➖ 5 scripts del servidor'
no_contiene "no le exige el deploy.yml dual" "$OUT" 'deploy\.yml  \('
no_contiene "ni compose, ni backend" "$OUT" '❌ [234] '
rm -rf "$T/b2"; cp -a "$B" "$T/b2"; rm -f "$T/b2/.github/workflows/deploy-vercel.yml"; mkdir -p "$T/b2/.github/workflows"; printf 'name: x\non: push\njobs: {}\n' > "$T/b2/.github/workflows/otro.yml"
audita "$T/b2"
igual "sin deploy-vercel.yml: sale con 1" 1 "$ST"
falta "  lo marca" '5 deploy-vercel\.yml'
rm -rf "$T/b3"; cp -a "$B" "$T/b3"; printf 'export default { typescript: { ignoreBuildErrors: true } }\n' > "$T/b3/next.config.mjs"
audita "$T/b3"
igual "ignoreBuildErrors: sale con 1" 1 "$ST"
falta "  lo marca" '5 next\.config: sin ignoreBuildErrors'

titulo "uso"
audita "$T/no-existe"
igual "carpeta inexistente: sale con 2" 2 "$ST"
contiene "  lo dice" "$OUT" 'no existe la carpeta'
OUT=$(cd "$A" && bash "$AUDIT" 2>&1); ST=$?
igual "sin argumentos audita la carpeta actual" 0 "$ST"

terminar
