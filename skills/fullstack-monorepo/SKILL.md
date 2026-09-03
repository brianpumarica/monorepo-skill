---
name: fullstack-monorepo
description: End-to-end framework-agnostic standard for auditing, scaffolding, refactoring, and maintaining production-grade Full-Stack Monorepos. Supports three official interaction modes (/analiza for stack-aware audit & gap analysis, /ejecuta for exhaustive implementation & legacy eradication, /inspecciona for read-only inspection of the live deployment). Covers conditional stack detection (Node/Python/Vite/Next/Docker), zero-flag dev-first Compose, bulletproof hot-reloading across host mounts, non-root multi-stage containers, SPA routing with Nginx/Vercel, dual CI/CD (Vercel CLI + Pi Runner), organization-level self-hosted runners, per-repository server env stores, post-deploy verification, and gh CLI operations.
---

# Fullstack Monorepo Standard & Scaffold Runbook

Este estándar proporciona un marco agnóstico, condicional y de grado de producción para crear, auditar y refactorizar monorrepos full-stack.

---

## 1. Modos de Invocación y Comandos Oficiales

Cualquier agente IA que ejecute esta skill DEBE responder de acuerdo al subcomando invocado:

| Comando / Sintaxis | Modo | Comportamiento Obligatorio del Agente |
| :--- | :--- | :--- |
| **`/fullstack-monorepo /analiza`**<br>*(o `@fullstack-monorepo /analiza`)* | **Fase 1: Auditoría & Diagnóstico** | 1. Ejecuta el **Motor de Detección de Stack**.<br>2. Genera la **Matriz de Conformidad (Gap Analysis)** clasificando ítems en: ✅ Cumple, ⚠️ Desviación, ❌ Faltante Crítico, 🗑️ Legacy a Eliminar.<br>3. Aplica la **Regla de Cero Preguntas Obvias** (solo consulta dilemas no estándar).<br>4. Presenta el plan de acción listo para aprobación. |
| **`/fullstack-monorepo /ejecuta`**<br>*(o `@fullstack-monorepo /ejecuta`)* | **Fase 2: Implementación & Erradicación** | 1. Aplica obligatoriamente el **Checklist de 6 Fases** para las tecnologías detectadas sin omitir entregables.<br>2. **Elimina proactivamente archivos legacy/anti-patrones**.<br>3. Ejecuta validaciones automáticas (`docker compose config`, lint, build).<br>4. Entrega el reporte de cambios completo. |
| **`/fullstack-monorepo /inspecciona`**<br>*(o `@fullstack-monorepo /inspecciona`)* | **Fase 0: Inspección del Entorno Desplegado** *(solo lectura)* | 1. Emite el **Catálogo de Diagnóstico** —comandos exclusivamente de lectura— para ejecutar en el servidor (ver [referencia de CI/CD §6](./references/ci-cd-deployment-pipeline.md)).<br>2. Interpreta la salida y reporta el **estado real**: inventario completo de contenedores del host, salud, recursos, versión desplegada y desvíos del entorno.<br>3. **No modifica absolutamente nada.** Lo que haya para corregir se lista y se espera aprobación explícita. |
| **`/fullstack-monorepo`** *(sin subcomando)* | **Modo Directo (All-in-One)** | Ejecuta el análisis y, si no existen dudas humanas ambiguas, **procede directamente a la ejecución exhaustiva** sin requerir confirmación intermedia. |

### Flujo recomendado

```
/inspecciona   →   /analiza   →   /ejecuta   →   /inspecciona
 (el servidor)      (el repo)      (el repo)       (verificar)
```

1. **`/inspecciona` antes de tocar el repo** — sólo si el proyecto se despliega en un servidor que
   ya hospeda otros. Devuelve puertos ocupados, disco disponible y contenedores vecinos: sin eso,
   los puertos se eligen a ciegas y la colisión aparece recién en el primer deploy.
2. **`/analiza`** — auditoría del repositorio y plan de acción.
3. **`/ejecuta`** — implementación del plan.
4. **`/inspecciona` después del primer deploy** — confirma que lo que corre es lo que se cree que
   corre. Complementa la sonda de versión: el job en verde prueba que el pipeline corrió; esto
   prueba que el código llegó.

`/analiza` y `/ejecuta` miran el **repositorio** y son las dos mitades del mismo trabajo.
`/inspecciona` mira el **servidor**: es otro eje, y por eso va antes y después, nunca en el medio.
El modo sin subcomando equivale a `/analiza` + `/ejecuta`, y **no** incluye inspección.

> **Dónde corre `/inspecciona`.** En la máquina de desarrollo, como cualquier otro modo. El
> servidor no tiene agente ni herramientas de IA: es sólo un host de contenedores. El agente
> trabaja por dos canales:
> - **Directo desde la máquina local:** `gh` para el estado del runner, las corridas y sus logs; y
>   `curl` contra los dominios públicos expuestos por el túnel.
> - **Copiar y pegar:** todo lo que sea `docker` en el servidor — el agente redacta el comando de
>   una línea, el operador lo pega en la terminal web y devuelve la salida.

---

## 2. Motor de Detección Condicional de Stack (*Stack-Aware Engine*)

La skill NO impone tecnologías que el proyecto no utiliza. En la fase de análisis, el agente detecta el stack activo y activa **únicamente** las directivas correspondientes de forma obligatoria:

| Tecnología Detectada | Indicador en el Proyecto | Directivas Obligatorias Activadas |
| :--- | :--- | :--- |
| **Docker / Compose** | Hay Dockerfiles o `docker-compose*.yml` | • `.gitattributes` con `eol=lf` para scripts Linux en Windows.<br>• `.dockerignore` raíz centralizado.<br>• `docker-compose.yml` (dev-first sin flags) y `docker-compose.prod.yml`. |
| **Node.js / TS (Backend)** | `package.json` en backend (Express / NestJS) | • Multi-stage con `node:22-alpine` y `USER node` non-root.<br>• BuildKit cache mounts (`/root/.npm`).<br>• `entrypoint.sh` idempotente con `pg_isready` y `exec "$@"`.<br>• Hot-reload con `tsx watch` + `CHOKIDAR_USEPOLLING=true`. |
| **Python (Backend)** | `requirements.txt` o `pyproject.toml` | • Multi-stage con `python:3.12-slim` y `USER appuser` non-root.<br>• Virtualenv aislado `/opt/venv`.<br>• Hot-reload con `uvicorn --reload --reload-dir /app`. |
| **Frontend SPA (Vite / React / Vue)** | `vite.config.ts` o index.html cliente | • `frontend/nginx.conf` con `try_files $uri $uri/ /index.html;` y Gzip.<br>• `frontend/vercel.json` con rewrites para SPA.<br>• Servidor final ultra-ligero `nginx:alpine` (<10MB RAM). |
| **Frontend SSR (Next.js)** | `next.config.js/ts` | • `output: 'standalone'` en producción.<br>• Volumen anónimo `/app/.next` y `WATCHPACK_POLLING=true`.<br>• Inyección de variables `NEXT_PUBLIC_*` en build-time. |
| **PostgreSQL / Base de Datos** | SQL scripts, Prisma o Alembic | • Healthchecks activos con `pg_isready`.<br>• Volumen de datos nombrado persistente.<br>• Seeders seguros (variables de entorno, sin contraseñas hardcodeadas). |

---

## 3. Regla de Cero Preguntas Obvias (*No-Trivial Questions Rule*)

Para maximizar la autonomía y la velocidad, el agente DEBE aplicar este filtro estricto:

* 🚫 **PROHIBIDO PREGUNTAR (Decisiones pre-aprobadas por el estándar):**
  - "¿Quieres que consolide `docker-compose.dev.yml` en `docker-compose.yml`?" $\rightarrow$ **SÍ, la skill lo exige.**
  - "¿Deseas agregar `nginx.conf` o `vercel.json` para las rutas SPA?" $\rightarrow$ **SÍ, la skill lo exige.**
  - "¿Quieres usar Node 22 en lugar de Node 20?" $\rightarrow$ **SÍ, la skill lo exige.**
  - "¿Quieres crear `.gitattributes` para evitar CRLF en Windows?" $\rightarrow$ **SÍ, la skill lo exige.**
  - "¿Deseas ejecutar el backend como non-root?" $\rightarrow$ **SÍ, la skill lo exige.**
  - "¿Agrego rotación de logs al compose de producción?" $\rightarrow$ **SÍ, la skill lo exige.**
  - "¿Uso `gh` en vez de la web para el PR y para seguir el deploy?" $\rightarrow$ **SÍ, la skill lo exige.**

* ✅ **ÚNICAS PREGUNTAS PERMITIDAS (Dilemas arquitectónicos reales):**
  - Existencia de múltiples servicios que colisionan en responsabilidades.
  - Elección de proveedor de base de datos externa no documentada.
  - Secretos de entorno faltantes que impiden la inicialización.
  - Conservar el volumen de datos existente vs. reconstruir producción desde cero (decisión destructiva: la toma el dueño, nunca el agente).

---

## 4. Entorno de Despliegue del Operador (*Deployment Environment Profile*)

Hechos del entorno real donde se despliega. **Los campos son fijos; los valores se reemplazan
por operador o proyecto.** El agente los da por ciertos y no vuelve a preguntarlos.

| Campo | Valor |
| :--- | :--- |
| **Alcance del runner** | Registrado a nivel **organización** (`brian-raspberry-5`), **no** en la cuenta personal. Un repositorio creado en la cuenta personal **no ve el runner** y su job queda encolado para siempre: hay que transferirlo a la organización antes del primer deploy. |
| **Etiquetas del runner** | `[self-hosted, linux, rpi5]` — servicio `actions.runner.<org>.<runner>.service` |
| **Canal de acceso al servidor** | Terminal web (ttyd) en `https://terminal.brianpumarica.online/` con Basic Auth. **No hay acceso por clave SSH, y es una decisión deliberada.** El agente redacta comandos de una sola línea; el operador los pega y devuelve la salida. **No hay transferencia de archivos**: para traer un volcado de la base, ver la referencia de base de datos §7. |
| **Verificación desde el repo** | `gh` CLI instalado y autenticado. Es el canal preferido para crear PRs, comprobar el runner y seguir los deploys — antes que la web y antes que la terminal del servidor. |
| **Host compartido** | Sí: el servidor hospeda varios proyectos a la vez. **Nunca** `docker system prune`, `docker container prune`, ni `docker compose down` sin `-f docker-compose.prod.yml` desde el directorio del proyecto. Antes de asignar los puertos de un proyecto nuevo, ver los que ya están tomados: `docker ps --format '{{.Names}}\t{{.Ports}}'`. |
| **Exposición pública** | Cloudflare Tunnel con el patrón `<proyecto>.brianpumarica.online`. Sin puertos abiertos en el router. |
| **Entorno de producción** | `/home/github-runner/env-backups/<nombre-del-repo>/.env` — permisos `600`, dueño `github-runner`. **Una carpeta por repositorio:** un archivo único se lo queda el primer proyecto y rompe a todos los demás. |
| **Ruta de los proyectos** | `/home/<usuario>/Documents/<nombre-del-repo>` |
| **Máquina de desarrollo** | Windows → los saltos de línea CRLF son un riesgo real y no teórico. |

---

## 5. Tabla de Erradicación de Anti-Patrones (*Legacy Eradication Matrix*)

Al ejecutar la refactorización, el agente DEBE eliminar activamente los siguientes anti-patrones:

| Anti-Patrón Heredado / Detectado | Acción Obligatoria de la Skill |
| :--- | :--- |
| **`docker-compose.dev.yml`** separado | **ELIMINAR / UNIFICAR DIRECTAMENTE en `docker-compose.yml`** para que `docker compose up -d` (cero flags) levante el entorno dev completo. |
| Scripts de CI/CD fragmentados (ej. `deploy-backend.yml` SSH aislado) | **REEMPLAZAR por `.github/workflows/deploy.yml`** con el pipeline dual completo (Vercel CLI + Pi Runner). |
| Dockerfile corriendo como `root` en producción | **MIGRAR OBLIGATORIAMENTE a `USER node` o `USER appuser`**. |
| Backend iniciando sin verificar disponibilidad de DB | **CREAR OBLIGATORIAMENTE `entrypoint.sh`** con bucle `pg_isready` y `exec "$@"`. |
| SPA sin configuración de servidor web | **CREAR OBLIGATORIAMENTE `nginx.conf` y `vercel.json`** para evitar errores 404 al recargar rutas. |
| Repositorio sin control de saltos de línea | **CREAR OBLIGATORIAMENTE `.gitattributes`** con `eol=lf`. |
| **Seeder que borra o sobrescribe datos** (`deleteMany`, `update` no vacío) | **REDUCIR a crear únicamente lo que falta.** El entrypoint corre en **cada** arranque del contenedor, producción incluida. |
| Cadena de fallback del entorno que termina en `.env.example` | **ELIMINAR ese último fallback.** Levantar producción con credenciales de desarrollo es peor que no levantarla: el deploy debe fallar ruidoso. |
| Comando de migraciones con `\|\| true` | **QUITAR el `\|\| true`**: abortar el arranque en lugar de servir la app contra un schema desactualizado. |
| Dev y prod generando el **mismo nombre de imagen** | **NOMBRAR distinto por entorno.** Levantar producción sin `--build` puede dejar corriendo la imagen de desarrollo. |
| Workflow de deploy que termina en `docker compose ps` | **AGREGAR verificación post-deploy** (contenedores `healthy` + smoke test al endpoint de salud) y hacer fallar el job si no pasa. |
| Job de CI que no despliega nada pero corre en cada push | **ELIMINARLO.** |
| Compose de producción sin rotación de logs | **AGREGAR `logging` con `max-size` / `max-file`** en todos los servicios: en un host compartido, un proyecto sin rotación llena el disco de todos. |

---

## 6. Golden Monorepo Directory Layout

```
<project-root>/
├── .github/
│   └── workflows/
│       └── deploy.yml           # Pipeline Dual: Vercel CLI (Frontend) + Pi Runner (Backend)
├── .agents/
│   └── skills/                  # Skills locales del workspace
├── apps/ (o backend / frontend)
│   ├── api/                     # Backend (NestJS / Express / FastAPI)
│   │   ├── Dockerfile           # Multi-stage, Node 22 / Python 3.12, non-root
│   │   └── entrypoint.sh        # DB readiness & startup runner
│   └── web/                     # Frontend (Next.js / Vite / React)
│       ├── Dockerfile           # Multi-stage, Nginx Alpine / Standalone
│       ├── nginx.conf           # Requerido para SPAs (Gzip + SPA Routing)
│       └── vercel.json          # Requerido para despliegues Vercel SPA
├── packages/ (opcional)
│   ├── types/                   # Interfaces TypeScript y esquemas Zod compartidos
│   └── tsconfig/                # Configuraciones base de TypeScript
├── docs/
│   ├── architecture.md          # Diagramas de flujo y topología de contenedores
│   ├── api-reference.md         # Endpoints, autenticación y payloads
│   └── deployment.md            # Guía Raspberry Pi + Cloudflare Tunnel + Vercel
├── docker/
│   └── init-db.sql              # Extensiones y esquema inicial de base de datos
├── .dockerignore                # Reglas centralizadas de exclusión
├── .env.example                 # Plantilla documentada sin secretos reales
├── .gitattributes               # Forzado de saltos LF para scripts Linux (*.sh, *.sql)
├── .gitignore                   # Ignorados exhaustivos (Node, Docker, Vercel, Turbo)
├── AGENTS.md                    # Matriz de puertos y directrices para agentes IA
├── docker-compose.yml           # DEV-FIRST por defecto (DB + Back Dev + Front Dev)
├── docker-compose.prod.yml      # PROD optimizado (Zero source mounts, non-root, restart)
├── package.json                 # Scripts raíz de orquestación (npm run docker:dev, etc.)
└── README.md                    # Guía de inicio rápido para desarrolladores
```

---

## 7. Checklist de Implementación Mandatoria (6 Fases)

Al recibir `/fullstack-monorepo /ejecuta` (o tras la aprobación de `/analiza`), el agente DEBE ejecutar ordenadamente:

### Fase 1: Normalización de Raíz
- [ ] Crear `.gitattributes` con `*.sh text eol=lf`, `*.sql text eol=lf`, `Dockerfile* text eol=lf`.
- [ ] Crear `.dockerignore` raíz y `.dockerignore` en backend.
- [ ] Actualizar `.gitignore` para monorrepos (Vercel, Turbo, logs, data).
- [ ] Crear `package.json` raíz con scripts de orquestación (`docker:dev`, `docker:prod`, `docker:down`, `docker:logs`).

### Fase 2: Orquestación Docker Compose
- [ ] Consolidar stack de desarrollo en `docker-compose.yml` (dev-first con cero flags).
- [ ] Eliminar cualquier archivo legacy redundante (`docker-compose.dev.yml`).
- [ ] Generar `docker-compose.prod.yml` con imágenes de producción, healthchecks y reinicio `unless-stopped`.

### Fase 3: Backend Hardening
- [ ] Crear `backend/entrypoint.sh` ejecutable con `pg_isready` y `exec "$@"`.
- [ ] Configurar `backend/Dockerfile` multi-stage (Node 22 / Python 3.12, `USER node` / `USER appuser`, BuildKit cache).
- [ ] Configurar hot-reload con polling (`CHOKIDAR_USEPOLLING=true` en Docker).

### Fase 4: Frontend Production Readiness
- [ ] Crear `frontend/nginx.conf` con `try_files $uri $uri/ /index.html;` y compresión gzip.
- [ ] Crear `frontend/vercel.json` con rewrites para Vercel.
- [ ] Configurar `frontend/Dockerfile` multi-stage con `nginx:alpine` para producción.

### Fase 5: CI/CD Pipeline Dual
- [ ] Crear/Unificar `.github/workflows/deploy.yml` (Job 1: Vercel CLI Frontend + Job 2: Raspberry Pi / Servidor Docker con `--force-recreate`).
- [ ] Eliminar workflows de despliegue fragmentados u obsoletos.
- [ ] Confirmar que el repositorio está **bajo la organización dueña del runner** y que el runner figura `Idle` antes de mergear (`gh api /orgs/<org>/actions/runners`).
- [ ] Crear el `.env` del servidor en su **carpeta por repositorio** (`/home/github-runner/env-backups/<repo>/.env`, `600`, dueño `github-runner`).
- [ ] Agregar el paso de **verificación post-deploy**: contenedores `healthy` + smoke test al endpoint de salud, con el job fallando si no pasa.

### Fase 6: Documentación y Agentes
- [ ] Generar `docs/architecture.md`, `docs/deployment.md` y `docs/api-reference.md`.
- [ ] Actualizar `AGENTS.md` con la matriz activa de puertos y registro de skills.
- [ ] Actualizar `README.md` con la guía de inicio rápido.
- [ ] Validar sintaxis con `docker compose config` y tests de compilación.

---

## 8. Matriz de Hot-Reloading Multiplataforma

Para evitar fallos de detección de archivos en montajes de volumen host (Windows / WSL / macOS):

| Framework / Tool | Archivo Clave | Configuración Mandatoria |
| :--- | :--- | :--- |
| **Vite** (React / Vue) | `vite.config.ts` | `server: { host: '0.0.0.0', watch: { usePolling: true, interval: 100 } }` |
| **Next.js** | `docker-compose.yml` | `environment: [WATCHPACK_POLLING=true]` + volumen anónimo `/app/.next` |
| **Express / TS** | `docker-compose.yml` | `environment: [CHOKIDAR_USEPOLLING=true]` + `"dev": "tsx watch src/index.ts"` |
| **NestJS / TS** | `nodemon.json` | `{"watch": ["src"], "ext": "ts", "legacyWatch": true, "exec": "nest start"}` |
| **FastAPI / Python** | `docker-compose.yml` | `uvicorn main:app --host 0.0.0.0 --reload --reload-dir /app` |

---

## 9. Referencias Detalladas y Companion Skills

Para plantillas de código listas para usar:
- [CI/CD Deployment Pipeline (GitHub Actions + Vercel CLI + Pi Runner)](./references/ci-cd-deployment-pipeline.md) — incluye el **Catálogo de Diagnóstico** del modo `/inspecciona` (§6), la operación con `gh` (§7) y la sonda de versión (§8)
- [Workspace Tooling (pnpm + Turbo)](./references/workspace-tooling.md)
- [Docker Compose Recipes](./references/docker-compose-recipes.md)
- [Dockerfile Recipes](./references/dockerfile-recipes.md)
- [AGENTS.md Standard Template](./references/agents-md-template.md)
- [Database Lifecycle & Entrypoint](./references/database-lifecycle.md) — incluye las **reglas innegociables del arranque** (§0) y cómo **traer un volcado desde un servidor sin SSH** (§7)

### Companion Skills Coordinadas:
- [`cloudflare-tunnel`](../cloudflare-tunnel/SKILL.md): Exposición segura con Zero Trust y SSL sin abrir puertos de router.
- [`vercel-monorepo-deploy`](../vercel-monorepo-deploy/SKILL.md): Despliegue de frontend monorrepo con Vercel CLI y `turbo-ignore`.
- [`docker-hardening`](../docker-hardening/SKILL.md): Seguridad de contenedores (`USER node`, `cap_drop: [ALL]`, healthchecks).
- [`prisma-database`](../prisma-database/SKILL.md) / [`fastapi-backend`](../fastapi-backend/SKILL.md) / [`nestjs-backend`](../nestjs-backend/SKILL.md): Especializaciones por tecnología.
