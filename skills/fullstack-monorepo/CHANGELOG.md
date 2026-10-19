# Changelog de `fullstack-monorepo`

El número está en `metadata.version` de [`SKILL.md`](./SKILL.md) y se anota en el `AGENTS.md` de
cada repo que usa una copia. Una copia **sin número** es anterior a la `1.0.0`.

Convención: **mayor** si una regla nueva o cambiada puede dejar *rojo* a un repo que antes cumplía
(o cambia nombres que ya están en un servidor); **menor** si suma un perfil, una receta o un script
sin cambiar lo existente; **parche** si corrige texto o un script sin cambiar el contrato.

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
