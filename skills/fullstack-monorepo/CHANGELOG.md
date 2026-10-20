# Changelog de `fullstack-monorepo`

El número está en `metadata.version` de [`SKILL.md`](./SKILL.md) y se anota en el `AGENTS.md` de
cada repo que usa una copia. Una copia **sin número** es anterior a la `1.0.0`.

Convención: **mayor** si una regla nueva o cambiada puede dejar *rojo* a un repo que antes cumplía
(o cambia nombres que ya están en un servidor); **menor** si suma un perfil, una receta o un script
sin cambiar lo existente; **parche** si corrige texto o un script sin cambiar el contrato.

## 1.2.0 — 2026-10-20

### Qué tiene que revisar un repo que usa una copia

Nada: es opt-in. Un repo que no define `OFFSITE_REMOTE` se comporta exactamente igual.

### Nuevo

- **Copia de los backups fuera de la Pi** (CI/CD §2.5): `backup.sh` sube cada corrida con `rclone` si se define
  `OFFSITE_REMOTE` (remoto `crypt` recomendado), rota lo de afuera, y si falla avisa sin invalidar el backup local.

## 1.1.0 — 2026-10-20

Cierra los pendientes de la skill que dejó el feedback de `analiza`. Nada rompe un repo que ya cumplía.

### Qué tiene que revisar un repo que usa una copia

- **`crear-env.sh`** ahora asigna puerto solo a las `*_HOST_PORT` vacías que `docker-compose.prod.yml` usa.
  Un repo cuyo compose de prod lee `${DB_HOST_PORT:-…}` sigue igual; uno que dejaba la línea vacía de un
  servicio que prod no publica (el frontend en Vercel) ya no aparta un puerto.
- **El paso «Install project cron»** del `deploy.yml` ya no instala los comentarios de `scripts/crontab` (cada
  deploy sumaba otra copia) y limpia los que ya estaban repetidos en el crontab del runner.

### Nuevo

- **Variantes de perfil** ([`perfiles-de-despliegue.md`](./references/perfiles-de-despliegue.md) §6): sin base
  de datos, un solo entorno (solo `docker-compose.prod.yml`) y desplegado por el dueño de la carpeta sin el runner.
- **Un tercer servicio publicado**: `chequear-host.sh` revisa cualquier `*_HOST_PORT` del `.env` y `alta ADMIN_HOST_PORT`
  elige un puerto libre; `puerto asignar --con ADMIN,WORKER` los escribe en el bloque; el auditor acepta el par
  `<X>_HOST_PORT` + `<X>_PORT`.
- **`rotar-secretos.sh var NOMBRE`** rota cualquier secreto propio, y `jwt` / `all` toleran un proyecto sin `JWT_SECRET`.
- **`package.json` raíz para npm sin Turbo** ([`workspace-tooling.md`](./references/workspace-tooling.md) §1.1).
- Recetas de Node: `openssl` para Prisma en alpine, la verificación en el build de migraciones y seeder (no solo
  del servidor) y qué hacer si `npm ci` falla por el lockfile. Python: 3.12 es el mínimo, no el tope.
- Linters de documentación del repo y borrado de worktrees con junctions en Windows (SKILL §6).

### Corregido

- `puerto.sh` en Git Bash/Windows: una sola llamada a `netstat -ano` en vez de probar cada puerto (`listar` y
  `asignar` pasaron de decenas de segundos a ~2 s).
- `auditar-repos.sh` acepta cualquier job de validación (`lint`, `ci`, `check`…), no solo uno llamado `validate`.

## 1.0.0 — 2026-10-19

Primera versión numerada. Junta lo que salió de correr `analiza` en 13 repos reales.

### Qué tiene que revisar un repo que ya usa la skill

Sirve para decidir a quién le conviene actualizar (SKILL §6, «Mantener al día la copia»):

- **Compose de desarrollo con los nombres de producción** (`<prefijo>-database`, `<prefijo>_pgdata`):
  la plantilla ahora los separa con `-dev`. Al actualizar, la base de dev de un repo así **arranca
  vacía** salvo que se fije `VOLUME_PGDATA_DEV_NAME` con el nombre viejo (compose §0.3).
- **Paso del Tunnel del `deploy.yml`**: ahora corre solo si el `.env` del servidor define
  `TUNEL_HOST`. Un repo que dependía de que el paso creara `api-<repo>` tiene que definirlo.
- **`actions/checkout` y `setup-node` en `@v5`** (Node 24): un runner self-hosted necesita el agente
  `2.327.1` o posterior.
- **`crear-env.sh`** ya no inventa `*_SECRET` ni claves de API de terceros y sí genera las `*_KEY`
  propias; copiar la versión nueva solo afecta a los `.env` que se creen después.

### Nuevo

- **Perfiles de despliegue** ([`perfiles-de-despliegue.md`](./references/perfiles-de-despliegue.md)):
  A dual (el de siempre), B solo frontend en Vercel con `deploy-vercel.yml`, C app Next full-stack en
  la Pi y D backend hecho en Next. `analiza` elige el perfil y marca **n/a** lo que no aplica.
- **`validate.yml`** reutilizable (CI/CD §2.7): valida en cada PR y es el primer job del deploy; la
  `concurrency` pasó del workflow a los jobs que despliegan.
- **[`auditar-repos.sh`](./references/auditar-repos.sh)**: el chequeo estático (≈60 reglas) que corre
  `analiza`, con salida legible, `--plano` y código de salida.
- **Receta de npm con workspaces** (`dockerfile-recipes.md` §2b) y `HOSTNAME=0.0.0.0` en Next standalone.
- **`alta-proyecto.sh`** desconecta la integración de Git de Vercel de un repo que ya desplegaba por ahí.
- Anti-patrones: `ignoreBuildErrors` / `ignoreDuringBuilds`, restos de v0, integración de Git de Vercel
  conectada, `concurrency` de workflow, `@v4`, Tunnel sin `TUNEL_HOST`, compose de dev con nombres de prod.
- Pitfall 17 de CI/CD: Vercel Hobby bloquea por Git los commits con `Co-Authored-By`.
- La versión de la skill en la plantilla de `AGENTS.md` y en el chequeo de `analiza`.

### Corregido

- `crear-env.sh` no hacía nada con un `.env.example` en CRLF y salía con `1` cuando no quedaba nada por
  completar; ahora normaliza (avisando) y sale con `0`.
- `tunel-agregar.sh` solo leía el puerto de entradas `localhost:N`; con `127.0.0.1:N` fallaba pidiendo
  corregir a mano y, al cambiar el puerto, reescribía el host.
- `.gitattributes` figuraba como directiva de Docker; es de la Fase 1 y vale para cualquier repo.
- El `deploy.yml` dual ya no se exige a un repo solo de frontend que tiene `deploy-vercel.yml`.
- La regla de las dos carpetas distingue lo que hay en disco (junction/symlink) de lo que git versiona.
- El default anidado del volumen (`${VOLUME_PGDATA_NAME:-${VOLUME_DB:-…}}`) está documentado, con el aviso
  de que renombrar la variable sin él deja a prod con un volumen vacío.
