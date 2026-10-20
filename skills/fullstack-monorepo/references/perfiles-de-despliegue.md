# Perfiles de despliegue

La skill nació para un solo caso: backend en Docker en la Pi más frontend en Vercel. Casi todo lo
demás (`deploy.yml` dual, `crear-env`, backups, Tunnel) presupone ese caso. Este documento dice
**qué cambia cuando el repo es otra cosa**, y qué directivas del estándar dejan de aplicar. Se
elige el perfil en `analiza`, antes de armar la matriz de conformidad.

## 0. Cómo elegir el perfil

| Perfil | Cómo se reconoce | Dónde corre | Workflow |
| :--- | :--- | :--- | :--- |
| **A. Dual** *(el estándar)* | Backend con `Dockerfile`/compose **y** un frontend aparte | Pi + Vercel | `deploy.yml` dual ([CI/CD §2](./ci-cd-deployment-pipeline.md)) |
| **B. Solo frontend** | Sin `Dockerfile` ni `docker-compose*.yml`; `vercel.json`, `.vercel/`, `netlify.toml`, o solo `next`/`vite` en el `package.json` | Vercel (o Netlify) | `deploy-vercel.yml` (§2) |
| **C. App Next full-stack en la Pi** | Un solo proyecto Next con route handlers / Server Actions / Prisma, sin backend ni frontend separados | Pi (un contenedor) | `deploy.yml` **sin** el job de Vercel (§3) |
| **D. Backend hecho en Next** | Un proyecto Next que solo sirve `app/api/*` (o `pages/api`) a otro frontend | Pi + el frontend en Vercel | `deploy.yml` dual, con Next como backend (§4) |

**Si el repo cae entre dos, manda dónde corre cada pieza**, no el framework: una app Next que se
publica en Vercel es **B**; la misma app en un contenedor de la Pi es **C**. Un monorepo con un
Next para la web y otro Next para la API es **A** con las recetas de Next en ambos lados.

Lo que **no depende del perfil** y se exige siempre: `.gitattributes` con `eol=lf` y `.gitignore`
(Fase 1 de la skill, no una directiva de Docker), `AGENTS.md`, `permissions: contents: read` y
`timeout-minutes` en todos los workflows, secretos por `env:`, y los anti-patrones de código de
[SKILL §5](../SKILL.md) (`ignoreBuildErrors`, restos de v0).

## 1. Qué directivas dejan de aplicar

| Directiva | A | B | C | D |
| :--- | :---: | :---: | :---: | :---: |
| `docker-compose*.yml`, `Dockerfile`, `.dockerignore`, `entrypoint.sh` | ✅ | n/a | ✅ | ✅ |
| `nginx.conf` | si el front va a un contenedor | n/a | n/a (Next no es SPA) | n/a |
| `vercel.json` con rewrites | si el front es SPA | si es SPA | n/a | n/a |
| `crear-env.sh`, `rotar-secretos.sh`, `chequear-host.sh`, `.env` del servidor | ✅ | n/a | ✅ | ✅ |
| `backup.sh`, `verificar-backup.sh`, `crontab` | con base | n/a | con base | con base |
| `tunel-agregar` / `TUNEL_HOST` | ✅ | n/a | ✅ (host de usuario) | ✅ (`api-<repo>`) |
| Secrets de Vercel (`VERCEL_*`, `API_URL`, `SITE_URL`) | ✅ | ✅ | n/a | ✅ |
| Detector de puertos `puerto asignar` | ✅ | ✅ (puerto del dev server) | ✅ | ✅ |

`analiza` marca como **n/a** lo que no aplica, no como «faltante»: un repo de perfil B sin
`docker-compose.prod.yml` cumple el estándar.

## 2. Perfil B — solo frontend en Vercel (o Netlify)

No hay Pi, ni `.env` de servidor, ni backups: el estándar se reduce a **cuatro cosas**.

1. **Un workflow que valida en cada PR y publica solo desde `main`** (abajo).
2. **La integración de Git de Vercel desconectada** (`alta-proyecto.sh --paso 2` la desconecta).
   Si queda conectada, Vercel compila cada push por su cuenta: checks rojos en cada PR y, en Hobby,
   bloqueo de los commits con `Co-Authored-By` ([CI/CD §4, pitfall 17](./ci-cd-deployment-pipeline.md)).
3. **Secrets de GitHub**: `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID` (y `SITE_URL` para el
   smoke test). `alta-proyecto.sh` los carga.
4. **Una verificación después del deploy**: sin contenedores `healthy` que mirar, es una petición a
   la URL pública.

`.github/workflows/deploy-vercel.yml` — *probada en tres repos reales; la validación previa y el
smoke test son los que se sumaron después*:

```yaml
name: Deploy a Vercel

# El repo es privado o de una organizacion: en el plan Hobby, Vercel no se conecta por Git
# (ci-cd §3). Se construye y publica con la CLI. En un PR solo se valida y se construye (como
# check antes del merge); en main se publica en produccion.
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

# Menor privilegio: el pipeline solo necesita leer el repositorio.
permissions:
  contents: read

jobs:
  validate:
    name: Lint, types y build
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v5
        with:
          node-version: 22
          cache: npm   # o pnpm (con pnpm/action-setup antes)
      - run: npm ci
      # Sin linter o sin type-check, el paso se OMITE: no se agrega uno por cumplir (abajo).
      - run: npm run lint --if-present
      - run: npm run typecheck --if-present

  deploy:
    name: Build y deploy en Vercel
    needs: validate
    runs-on: ubuntu-latest
    timeout-minutes: 15
    # La serializacion va en el job: los PR no esperan a un deploy de main ni lo cancelan.
    concurrency:
      group: vercel-${{ github.ref }}
      cancel-in-progress: ${{ github.event_name == 'pull_request' }}
    env:
      # La CLI lee estas tres del entorno: no hace falta --token (secretos siempre por env:).
      VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}
      VERCEL_ORG_ID: ${{ secrets.VERCEL_ORG_ID }}
      VERCEL_PROJECT_ID: ${{ secrets.VERCEL_PROJECT_ID }}
      # Produccion solo desde main; un PR trae el entorno de preview y no publica nada.
      DEPLOY_ENV: ${{ github.event_name == 'pull_request' && 'preview' || 'production' }}
      SITE_URL: ${{ secrets.SITE_URL }}
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v5
        with:
          node-version: 22
      # Con pnpm: `npm install --global pnpm@10 vercel@latest`. La CLI usa el gestor del lockfile.
      - name: CLI de Vercel
        run: npm install --global vercel@latest

      - name: Traer la configuracion del proyecto
        run: vercel pull --yes --environment="$DEPLOY_ENV"

      - name: Build
        run: |
          if [ "$DEPLOY_ENV" = production ]; then vercel build --prod; else vercel build; fi

      - name: Deploy a produccion
        if: github.event_name != 'pull_request'
        run: vercel deploy --prebuilt --prod

      # La URL de produccion (alias del dominio), no la del deploy: esa puede estar detras de la
      # proteccion de Vercel y dar 401 con el sitio sano.
      - name: Smoke test
        if: github.event_name != 'pull_request'
        run: |
          if [ -z "$SITE_URL" ]; then echo "ℹ️ Sin SITE_URL: no se hace el smoke test."; exit 0; fi
          curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors -o /dev/null "$SITE_URL"
          echo "✅ $SITE_URL responde."
```

**Qué cambia respecto de la plantilla dual**

- **No hay `deploy.yml` dual.** `deploy-vercel.yml` *es* el workflow de despliegue del repo: exigir
  además el `deploy.yml` con el job de la Pi es un falso faltante. Si un repo tiene las dos
  cosas (un backend en la Pi y un frontend), vale el perfil A.
- **Sin linter.** Un repo generado por una herramienta puede no tener ESLint. No se agrega uno solo
  para que el job exista: se omite el paso y se anota como pendiente en `docs/pendientes.md`. Con
  TypeScript, `npx tsc --noEmit` sí es un type-check y va en lugar del `typecheck` (si el script no
  existe).
- **Type-check de verdad.** Si `next.config` trae `typescript: { ignoreBuildErrors: true }`, el build
  no valida tipos: se quita, se corrigen los errores que aparezcan (en un PR aparte) y no se
  vuelve a esconderlos (SKILL §5).
- **`AGENTS.md` de este perfil**: sin la sección de Docker, sin matriz de contenedores, sin
  «Comandos prohibidos» de host. Lleva: comandos (`npm run dev`, `build`, `lint`), el puerto del
  servidor de desarrollo (de `puerto asignar`), el flujo de despliegue («push a `main` → Actions →
  Vercel; el PR solo compila»), la URL de producción y la línea de versión de la skill.
- **Netlify** *(sin probar en producción)*: mismo esqueleto, con `NETLIFY_AUTH_TOKEN` y
  `NETLIFY_SITE_ID` como secrets y `netlify deploy --build --prod` (en un PR, sin `--prod`). Si el
  sitio sigue conectado por Git de Netlify, desconectarlo por el mismo motivo.
- **Restos de v0** (proyectos generados con v0): ver SKILL §5. Se limpian en el mismo PR que
  agrega el workflow, o en uno aparte, pero se **listan** siempre.

## 3. Perfil C — app Next full-stack sola en la Pi

Una app Next con su lógica de servidor, un solo contenedor y (casi siempre) Postgres. No hay
frontend aparte: **el usuario entra directo a la Pi**, por el Tunnel.

| Pieza | Cómo queda |
| :--- | :--- |
| Imagen | La receta de Next standalone ([`dockerfile-recipes.md`](./dockerfile-recipes.md) §6), con `ENV HOSTNAME=0.0.0.0` y `output: 'standalone'` |
| Servicio en el compose | Se llama `backend` aunque sirva la web: el **contrato de nombres no cambia** ([compose §0](./docker-compose-recipes.md)). Publica con `BACKEND_HOST_PORT`, atado a `127.0.0.1` |
| Healthcheck | Un route handler propio (`app/api/health/route.ts`) que responde 200 y consulta la base; `HEALTH_PATH` apunta ahí |
| `deploy.yml` | El de [CI/CD §2](./ci-cd-deployment-pipeline.md) **sin** `deploy-frontend` ni los secrets de Vercel. Se conserva `validate`, el backup previo, el rollback y la poda |
| Ruta del Tunnel | **`TUNEL_HOST=<repo>.<dominio>`** en el `.env` del servidor: el nombre `api-<repo>` es para APIs y no sirve para algo que abre un usuario. Un solo nivel bajo el dominio, con guion. `tunel-agregar` lo registra igual (§2.6) |
| `entrypoint.sh` | Igual que en el backend ([`database-lifecycle.md`](./database-lifecycle.md) §1). Ojo: `standalone` copia solo lo que la app importa; el CLI de Prisma (`migrate deploy`) **no viene** salvo que se instale en la imagen final. Se verifica con §8.2 de las recetas |

Tres trampas propias de este perfil:

1. **`rewrites()` y `NEXT_PUBLIC_*` se fijan en el build.** Un `rewrites()` que apunta a otro servicio
   (`API_ORIGIN`) se evalúa al construir, no al arrancar: cambiar la variable en el `.env` del
   servidor no cambia nada. Va como `ARG` + `ENV` **antes** de `next build`, y como `build.args` en
   el compose ([CI/CD §4, pitfall 1](./ci-cd-deployment-pipeline.md)).
2. **Las subidas de archivos viven en un volumen nombrado, escribible por el usuario no root.** Sin
   volumen se pierden en cada deploy (`--force-recreate`); con el volumen pero sin `chown`, la app
   corre como `node` y no puede escribir. En el Dockerfile: `RUN mkdir -p /app/uploads && chown node:node /app/uploads`
   **antes** de `USER node`, y `volumes: - <prefijo>_uploads:/app/uploads` en el compose de prod.
   Los backups ([`backup.sh`](./backup.sh)) copian esa carpeta si se completa `UPLOADS_DEST`.
3. **El seeder corre en cada arranque** (`entrypoint.sh`): solo crea lo que falta, nunca pisa lo que
   cargó un usuario (SKILL §5, «Seeder que borra o sobrescribe»).

Y en **desarrollo**: `puerto asignar` escribe `PORT`, pero `next dev` solo lo toma si el script no
trae `-p`. Si el `package.json` fija `next dev -p 3000`, el compose pasa el puerto explícito
(`command: npm run dev -- -p ${PORT}`) o se quita el `-p` del script.

## 4. Perfil D — backend hecho en Next

Es el perfil A con Next en el lugar de Express/Nest. Todo lo del backend aplica (compose,
`entrypoint.sh`, backups, `crear-env`), con estas diferencias respecto del C:

- La ruta del Tunnel **sí** es `api-<repo>.<dominio>` (es una API) y el frontend sigue en Vercel
  con `deploy-frontend` y `needs: deploy-backend`.
- `CORS_ORIGIN` es obligatorio (otro origen lo llama); en el perfil C no existe.
- El healthcheck y el smoke test usan la misma ruta que en cualquier backend ([CI/CD §9](./ci-cd-deployment-pipeline.md)).
- Las trampas 1 a 3 del perfil C aplican igual (subidas, `standalone`, seeder).

## 5. Dónde queda cada cosa en el repo

| Archivo | A | B | C | D |
| :--- | :---: | :---: | :---: | :---: |
| `.github/workflows/deploy.yml` | ✅ | — | ✅ (sin front) | ✅ |
| `.github/workflows/validate.yml` | ✅ | — (va dentro del `deploy-vercel.yml`) | ✅ | ✅ |
| `.github/workflows/deploy-vercel.yml` | — | ✅ | — | — |
| `docker-compose.yml` / `.prod.yml` | ✅ | — | ✅ | ✅ |
| `scripts/` (crear-env, chequear-host, backup, …) | ✅ | — | ✅ | ✅ |

## 6. Variantes (se combinan con los perfiles A, C y D)

Tres situaciones que no son un perfil nuevo sino un recorte de uno existente. Las tres salen de
repos reales; ninguna se probó todavía con un deploy completo.

### 6.1 Sin base de datos

Un servicio sin Postgres (un proxy, un bot, un worker que solo llama a APIs).

| Se va | Se queda |
| :--- | :--- |
| `postgresql-client` en el Dockerfile y el `pg_isready` del `entrypoint.sh` (queda el ancla `APP_DIR` y el `exec "$@"`) | Healthcheck nativo y smoke test (`HEALTH_PATH`) |
| `POSTGRES_*`, `DATABASE_URL`, `DB_HOST_PORT` y el volumen de datos del compose y de `.env.example` | Tag por commit, rollback y poda acotada |
| El paso «Backup database before migrations» del `deploy.yml` | `crear-env.sh` (secretos propios y puertos) y `chequear-host.sh` |
| `backup.sh`, `verificar-backup.sh` y su línea del `scripts/crontab` | `rotar-secretos.sh var NOMBRE` para los secretos propios |

- El endpoint de salud sigue el contrato de [CI/CD §9](./ci-cd-deployment-pipeline.md) **sin** el campo
  `database`: responde lo que el servicio necesita para servir, o solo `OK` si no depende de nada.
- `chequear-host.sh` dice «no tiene una línea de backup.sh» y sigue: no falla.
- Si el servicio guarda estado en archivos o SQLite, **`backup.sh` no lo cubre** (hace `pg_dump`): el
  volumen nombrado hay que respaldarlo aparte. Está anotado como pendiente de la skill.
- `auditar-repos.sh` ya marca como n/a lo que depende de la base cuando el compose no menciona Postgres.

### 6.2 Un solo entorno

Un proyecto que solo corre en el servidor (no se desarrolla levantándolo en contenedores) lleva
**solo `docker-compose.prod.yml`**. No se crea un `docker-compose.yml` de desarrollo vacío por cumplir
la regla de «dev-first»: sin entorno de desarrollo no hay hot-reload, ni `-dev`, ni `puerto asignar` que
configurar. Todo lo de producción se exige igual. `auditar-repos.sh` lo marca n/a. Si más adelante alguien
quiere desarrollarlo en contenedores, ahí sí nace el compose de dev con nombres `-dev` (compose §0.3).

### 6.3 Desplegado por el dueño de la carpeta, sin el runner

El código y los volúmenes son de un usuario normal y el despliegue lo hace un script
(`sudo -u <dueño> desplegar.sh`), no `github-runner`. Lo que cambia, porque asume el home del runner:

| Pieza | Con el runner | Por el dueño |
| :--- | :--- | :--- |
| `.env` del servidor | `/home/github-runner/env-backups/<repo>/.env` | El que diga el script, `600` y del dueño. `crear-env.sh` lo crea con `sudo ENV_BASE=<carpeta> ENV_OWNER=<dueño> bash scripts/crear-env.sh` |
| `chequear-host.sh` | Lee `env-backups/` de todos los repos | Con `ENV_BASE=<carpeta>` ve solo lo que esté ahí; los **contenedores** de los demás proyectos los ve igual (`docker ps`), así que un puerto ajeno en uso se detecta. Lo que no ve son las reservas de proyectos detenidos |
| `avisar.sh` | `/home/github-runner/avisar.sh` (modo `700`) | El dueño **no puede leerlo**: copia propia (`~/avisar.sh` con su `avisar.env`) y `AVISAR=$HOME/avisar.sh` en el cron. `backup.sh` y `verificar-backup.sh` ya toman la variable |
| Backups | `~github-runner/backups/<repo>/` | `BACKUP_DIR` (por defecto `$HOME/backups/<repo>` del dueño) |

Siguen valiendo íntegras las reglas del compose de producción, el tag por commit con rollback, el
healthcheck y el smoke test, la poda acotada por `com.proyecto` y los puertos en `127.0.0.1`. Lo que
se pierde es la parte del `deploy.yml` que solo existe con el runner (`.env` canónico, `REQUIRED_SECRETS`):
el script de deploy tiene que hacer su equivalente, y `analiza` lo anota como desvío aceptado, no como
faltante.
