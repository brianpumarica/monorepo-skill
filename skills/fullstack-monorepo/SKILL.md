---
name: fullstack-monorepo
description: End-to-end framework-agnostic standard for creating, scaffolding, auditing, and maintaining production-grade Full-Stack Monorepos. Covers unified workspace setup (pnpm/npm/uv), dual Docker Compose orchestration (zero-flag dev-first + hybrid mode + Raspberry Pi production), bulletproof cross-platform hot-reloading (Vite, Next.js, Expo, NestJS, Express, FastAPI, Flask), multi-stage non-root Dockerfiles, safe database migration/seed lifecycle, Cloudflare Tunnels + Vercel deployment, and clean minimal-comment templates. Use whenever initializing a new monorepo, refactoring multi-package repositories, setting up Docker or compose for full-stack apps, fixing hot-reload in containers, or structuring frontend-backend-database architectures.
---

# Fullstack Monorepo Standard & Scaffold Runbook

This skill provides an opinionated, technology-agnostic standard for building and structuring production-grade Full-Stack Monorepos.

---

## 1. Golden Monorepo Directory Layout

Every repository following this standard MUST adhere to this directory hierarchy:

```
<project-root>/
├── .agents/
│   └── skills/                  # Local workspace skills
├── apps/
│   ├── api/                     # Backend service (NestJS / Express / FastAPI / etc.)
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh        # DB migration & startup runner
│   │   └── package.json         # (or requirements.txt / pyproject.toml)
│   └── web/                     # Frontend service (Next.js / Vite / Expo Web / etc.)
│       ├── Dockerfile
│       ├── nginx.conf           # Required for SPAs (Vite / React / Expo / Vue)
│       └── package.json
├── packages/
│   ├── types/                   # Shared TypeScript interfaces, DTOs & Zod schemas
│   │   ├── package.json
│   │   └── src/index.ts
│   └── tsconfig/                # Shared TypeScript base configs
│       ├── package.json
│       └── base.json
├── docs/
│   ├── architecture.md          # Architecture & data flow diagrams
│   ├── api-reference.md         # Endpoints & authentication
│   └── deployment.md            # Raspberry Pi + Cloudflare Tunnel + Vercel guide
├── docker/
│   └── init-db.sql              # Initial database extensions / schema (optional)
├── .dockerignore                # Centralized ignore rules
├── .env.example                 # Documented template without real secrets
├── .gitattributes               # Forces LF line endings for shell scripts (*.sh)
├── .gitignore                   # Comprehensive ignores for OS, Node, Python, Docker
├── AGENTS.md                    # Instructions & port matrix for AI assistants
├── docker-compose.yml           # DEV-FIRST compose (Default: DB + Back + Front hot-reload)
├── docker-compose.prod.yml      # PROD compose (Optimized runtime for Raspberry Pi / VPS)
├── package.json                 # Monorepo root workspace manifest
├── pnpm-workspace.yaml          # Workspace package registry
├── README.md                    # Human-facing setup and quickstart guide
└── turbo.json                   # Pipeline task runner config (optional but recommended)
```

---

## 2. Docker Compose Orchestration Architecture

### Principle 1: Dev-First by Default (`docker-compose.yml`)
Running `docker compose up -d` with **zero extra flags** MUST immediately start the full local development stack (Database + Backend Dev + Frontend Dev) with hot-reloading.

### Principle 2: Hybrid Mode (DB + Backend Only)
When developing the frontend outside Docker (or testing against Vercel/Netlify), start only the database and API:
```bash
docker compose up -d database backend
```

### Principle 3: Production on Raspberry Pi / VPS (`docker-compose.prod.yml`)
Production runs optimized built images with no source code mounts, non-root users, and minimal resource footprints:
```bash
docker compose -f docker-compose.prod.yml up -d --build
```

---

## 3. Technology-Specific Hot-Reload Matrix

To prevent file-watching failures on Windows/WSL/Docker mounts, apply these exact configurations:

| Framework / Tool | Key File | Configuration |
| :--- | :--- | :--- |
| **Vite** (React / Vue / Svelte) | `apps/web/vite.config.ts` | `server: { host: '0.0.0.0', port: 8084, watch: { usePolling: true, interval: 100 } }` |
| **Next.js** | `docker-compose.yml` | `environment: [WATCHPACK_POLLING=true]` + anonymous volume `/app/.next` |
| **Expo Web / React Native** | `apps/web/Dockerfile` | `CMD ["npx", "expo", "start", "--web", "--port", "8084", "--host", "0.0.0.0"]` |
| **NestJS / TypeScript** | `apps/api/nodemon.json` | `{"watch": ["src"], "ext": "ts", "legacyWatch": true, "exec": "nest start"}` |
| **Express / TypeScript** | `apps/api/package.json` | `"dev": "tsx watch --poll src/index.ts"` |
| **FastAPI / Python** | `docker-compose.yml` | `uvicorn main:app --host 0.0.0.0 --port 3004 --reload --reload-dir /app` |
| **Flask / Python** | `docker-compose.yml` | `environment: [FLASK_DEBUG=1]` + `python app.py` listening on `0.0.0.0` |

---

## 4. Dockerfile Production Standards

All Dockerfiles MUST follow these 5 rules:
1. **Multi-Stage Architecture**: `base` -> `development` -> `build` -> `production`.
2. **Non-Root Execution**: Use `USER node` for Node Alpine images or `USER appuser` for Python slim images.
3. **BuildKit Cache Mounts**: Use `RUN --mount=type=cache,target=/root/.local/share/pnpm/store pnpm install` to speed up builds.
4. **Static Frontend Hosting**: SPAs (Vite, Expo Web, React) MUST be served via `nginx:alpine` in production (RAM usage < 10MB). Next.js MUST use `output: 'standalone'`.
5. **Entrypoint Script**: Backend must use an idempotent `entrypoint.sh` that waits for Postgres readiness, runs migrations (`prisma migrate deploy` or `alembic upgrade head`), and executes the command with `exec "$@"`.

---

## 5. Deployment Architecture: Raspberry Pi + Cloudflare Tunnel + Vercel

```
  [User Browser]
       │
       ├── (1) HTTPS Web Traffic ──────> [Vercel / Netlify]
       │                                 (Static Frontend / SSR)
       │                                 Env: VITE_API_URL=https://api.domain.com
       │
       └── (2) HTTPS API Requests ────> [Cloudflare Edge / Tunnel]
                                               │ (Encrypted Zero-Trust Tunnel)
                                               ▼
                                     [Raspberry Pi / Home Server]
                                     ├── cloudflared (Tunnel Daemon)
                                     ├── backend-prod (Port 3004)
                                     └── database (PostgreSQL + pgvector)
```

1. **Raspberry Pi**: Runs `docker-compose.prod.yml` (Database + Backend).
2. **Cloudflare Tunnel (`cloudflared`)**: Exposes the local backend port to `https://api.tudominio.com` without opening router ports or exposing public IPs.
3. **Vercel**: Hosts `apps/web`. Environment variables (`NEXT_PUBLIC_API_URL` or `VITE_API_URL`) point to `https://api.tudominio.com`.
4. **CORS**: Backend allows `*.vercel.app` and your custom domain.

---

## 6. Detailed Reference Docs

For copy-paste ready, minimal-comment templates, refer to:
- [Workspace Tooling (pnpm + Turbo)](./references/workspace-tooling.md)
- [Docker Compose Recipes](./references/docker-compose-recipes.md)
- [Dockerfile Recipes](./references/dockerfile-recipes.md)
- [AGENTS.md Standard Template](./references/agents-md-template.md)
- [Database Lifecycle & Entrypoint](./references/database-lifecycle.md)

---

## 7. Companion Skills Ecosystem

This mother skill orchestrates a suite of specialized companion skills in `skills/` (or installable via `npx skills add <repository>@<skill>`):

### Core / Required Skills (Always Applied):
- [`cloudflare-tunnel`](../cloudflare-tunnel/SKILL.md): Exposing Raspberry Pi 5 backends & databases securely with Zero Trust and `cloudflared`.
- [`vercel-monorepo-deploy`](../vercel-monorepo-deploy/SKILL.md): Monorepo frontend deployment, `turbo-ignore`, and Cloudflare API wiring.
- [`docker-hardening`](../docker-hardening/SKILL.md): Non-root execution, `cap_drop: [ALL]`, BuildKit cache mounts, and container healthchecks.

### Optional / Stack-Specific Skills (Invoked on Demand):
- [`prisma-database`](../prisma-database/SKILL.md): Multi-file schemas (`prismaSchemaFolder`), connection pool adapters, and typed seeders.
- [`nestjs-backend`](../nestjs-backend/SKILL.md): Modular NestJS architecture, global response transform interceptor, and exception filters.
- [`fastapi-backend`](../fastapi-backend/SKILL.md): Modern async FastAPI with Pydantic v2, lifespan context, and SQLAlchemy 2.0.
- [`turborepo-orchestration`](../turborepo-orchestration/SKILL.md): Advanced `turbo.json` task pipelines, JIT shared packages, and `turbo watch dev`.


