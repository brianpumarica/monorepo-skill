---
name: fullstack-monorepo
description: End-to-end framework-agnostic standard for auditing, scaffolding, refactoring, and maintaining production-grade Full-Stack Monorepos. Supports two official interaction modes (/analiza for stack-aware audit & gap analysis, /ejecuta for exhaustive implementation & legacy eradication). Covers conditional stack detection (Node/Python/Vite/Next/Docker), zero-flag dev-first Compose, bulletproof hot-reloading across host mounts, non-root multi-stage containers, SPA routing with Nginx/Vercel, and dual CI/CD (Vercel CLI + Pi Runner).
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
| **`/fullstack-monorepo`** *(sin subcomando)* | **Modo Directo (All-in-One)** | Ejecuta el análisis y, si no existen dudas humanas ambiguas, **procede directamente a la ejecución exhaustiva** sin requerir confirmación intermedia. |

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

* ✅ **ÚNICAS PREGUNTAS PERMITIDAS (Dilemas arquitectónicos reales):**
  - Existencia de múltiples servicios que colisionan en responsabilidades.
  - Elección de proveedor de base de datos externa no documentada.
  - Secretos de entorno faltantes que impiden la inicialización.

---

## 4. Tabla de Erradicación de Anti-Patrones (*Legacy Eradication Matrix*)

Al ejecutar la refactorización, el agente DEBE eliminar activamente los siguientes anti-patrones:

| Anti-Patrón Heredado / Detectado | Acción Obligatoria de la Skill |
| :--- | :--- |
| **`docker-compose.dev.yml`** separado | **ELIMINAR / UNIFICAR DIRECTAMENTE en `docker-compose.yml`** para que `docker compose up -d` (cero flags) levante el entorno dev completo. |
| Scripts de CI/CD fragmentados (ej. `deploy-backend.yml` SSH aislado) | **REEMPLAZAR por `.github/workflows/deploy.yml`** con el pipeline dual completo (Vercel CLI + Pi Runner). |
| Dockerfile corriendo como `root` en producción | **MIGRAR OBLIGATORIAMENTE a `USER node` o `USER appuser`**. |
| Backend iniciando sin verificar disponibilidad de DB | **CREAR OBLIGATORIAMENTE `entrypoint.sh`** con bucle `pg_isready` y `exec "$@"`. |
| SPA sin configuración de servidor web | **CREAR OBLIGATORIAMENTE `nginx.conf` y `vercel.json`** para evitar errores 404 al recargar rutas. |
| Repositorio sin control de saltos de línea | **CREAR OBLIGATORIAMENTE `.gitattributes`** con `eol=lf`. |

---

## 5. Golden Monorepo Directory Layout

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

## 6. Checklist de Implementación Mandatoria (6 Fases)

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

### Fase 6: Documentación y Agentes
- [ ] Generar `docs/architecture.md`, `docs/deployment.md` y `docs/api-reference.md`.
- [ ] Actualizar `AGENTS.md` con la matriz activa de puertos y registro de skills.
- [ ] Actualizar `README.md` con la guía de inicio rápido.
- [ ] Validar sintaxis con `docker compose config` y tests de compilación.

---

## 7. Matriz de Hot-Reloading Multiplataforma

Para evitar fallos de detección de archivos en montajes de volumen host (Windows / WSL / macOS):

| Framework / Tool | Archivo Clave | Configuración Mandatoria |
| :--- | :--- | :--- |
| **Vite** (React / Vue) | `vite.config.ts` | `server: { host: '0.0.0.0', watch: { usePolling: true, interval: 100 } }` |
| **Next.js** | `docker-compose.yml` | `environment: [WATCHPACK_POLLING=true]` + volumen anónimo `/app/.next` |
| **Express / TS** | `docker-compose.yml` | `environment: [CHOKIDAR_USEPOLLING=true]` + `"dev": "tsx watch src/index.ts"` |
| **NestJS / TS** | `nodemon.json` | `{"watch": ["src"], "ext": "ts", "legacyWatch": true, "exec": "nest start"}` |
| **FastAPI / Python** | `docker-compose.yml` | `uvicorn main:app --host 0.0.0.0 --reload --reload-dir /app` |

---

## 8. Referencias Detalladas y Companion Skills

Para plantillas de código listas para usar:
- [CI/CD Deployment Pipeline (GitHub Actions + Vercel CLI + Pi Runner)](./references/ci-cd-deployment-pipeline.md)
- [Workspace Tooling (pnpm + Turbo)](./references/workspace-tooling.md)
- [Docker Compose Recipes](./references/docker-compose-recipes.md)
- [Dockerfile Recipes](./references/dockerfile-recipes.md)
- [AGENTS.md Standard Template](./references/agents-md-template.md)
- [Database Lifecycle & Entrypoint](./references/database-lifecycle.md)

### Companion Skills Coordinadas:
- [`cloudflare-tunnel`](../cloudflare-tunnel/SKILL.md): Exposición segura con Zero Trust y SSL sin abrir puertos de router.
- [`vercel-monorepo-deploy`](../vercel-monorepo-deploy/SKILL.md): Despliegue de frontend monorrepo con Vercel CLI y `turbo-ignore`.
- [`docker-hardening`](../docker-hardening/SKILL.md): Seguridad de contenedores (`USER node`, `cap_drop: [ALL]`, healthchecks).
- [`prisma-database`](../prisma-database/SKILL.md) / [`fastapi-backend`](../fastapi-backend/SKILL.md) / [`nestjs-backend`](../nestjs-backend/SKILL.md): Especializaciones por tecnología.
