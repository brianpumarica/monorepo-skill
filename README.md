# Full-Stack Monorepo Agent Skills Suite 🚀

[![skills.sh](https://img.shields.io/badge/skills.sh-indexed-blue)](https://skills.sh)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Compatibility](https://img.shields.io/badge/Compatibility-Antigravity%20%7C%20Cursor%20%7C%20Claude%20Code%20%7C%20Copilot-orange)](#compatibility)

A comprehensive, production-grade suite of **Agent Skills** for scaffolding, orchestrating, hardening, and deploying full-stack monorepos with **Docker**, **Raspberry Pi 5**, **Cloudflare Tunnels**, and **Vercel**.

Designed for **Progressive Disclosure**: only the relevant skills are activated depending on your tech stack, avoiding context bloat and maximizing AI precision.

---

## 📦 Quick Installation via `skills.sh`

### Install the Complete Suite (All Skills):
```bash
npx skills add <github-username>/monorepo-skill
```

### Or Install Individual Skills a la Carte:
```bash
# Mother Skill (Layout, Orchestration, Hot-Reload Matrix)
npx skills add <github-username>/monorepo-skill@fullstack-monorepo

# Core Infrastructure Skills
npx skills add <github-username>/monorepo-skill@cloudflare-tunnel
npx skills add <github-username>/monorepo-skill@vercel-monorepo-deploy
npx skills add <github-username>/monorepo-skill@docker-hardening

# Tech-Specific Skills
npx skills add <github-username>/monorepo-skill@prisma-database
npx skills add <github-username>/monorepo-skill@nestjs-backend
npx skills add <github-username>/monorepo-skill@fastapi-backend
npx skills add <github-username>/monorepo-skill@turborepo-orchestration
```

---

## 🏛️ Architecture Overview

```
 [User Browser]
      │
      ├── (1) HTTPS Web Traffic ──────> [Vercel / Netlify]
      │                                 (Static Frontend / SSR)
      │                                 Env: VITE_API_URL=https://api.domain.com
      │
      └── (2) HTTPS API Requests ────> [Cloudflare Edge / Tunnel]
                                              │ (Encrypted Zero-Trust QUIC)
                                              ▼
                                    [Raspberry Pi 5 / Home Server]
                                    ┌────────────────────────────────┐
                                    │ Docker Network: `app-net`      │
                                    │                                │
                                    │ ├── cloudflared (Tunnel Daemon)│
                                    │ ├── backend-prod (Port 3004)   │
                                    │ └── database (PostgreSQL 16)   │
                                    └────────────────────────────────┘
```

---

## 📚 Skills Catalog

### 🌟 Mother Skill (Orchestrator)
| Skill | Path | Description |
| :--- | :--- | :--- |
| **`fullstack-monorepo`** | [`skills/fullstack-monorepo/`](./skills/fullstack-monorepo/SKILL.md) | Framework-agnostic Golden Layout, dev-first zero-flag Docker Compose, cross-platform hot-reload matrix (Vite, Next.js, Expo, NestJS, FastAPI). |

### 🛡️ Core Skills (Essential Infrastructure)
| Skill | Path | Description |
| :--- | :--- | :--- |
| **`cloudflare-tunnel`** | [`skills/cloudflare-tunnel/`](./skills/cloudflare-tunnel/SKILL.md) | Auto-configured `cloudflared` service in Docker Compose, Zero Trust Access protection (`/docs`), remote TCP database tunneling, and CORS. |
| **`vercel-monorepo-deploy`** | [`skills/vercel-monorepo-deploy/`](./skills/vercel-monorepo-deploy/SKILL.md) | Monorepo frontend deployment, `turbo-ignore` build skipping, SPA client-side routing in `vercel.json`, and API wiring. |
| **`docker-hardening`** | [`skills/docker-hardening/`](./skills/docker-hardening/SKILL.md) | Linux security hardening (`cap_drop: [ALL]`, `no-new-privileges: true`), non-root execution, RAM/CPU limits for Raspberry Pi 5, BuildKit caching. |

### ⚙️ Optional Skills (Tech-Stack Dependent)
| Skill | Path | Description |
| :--- | :--- | :--- |
| **`prisma-database`** | [`skills/prisma-database/`](./skills/prisma-database/SKILL.md) | Multi-file schemas (`prismaSchemaFolder`), connection pooling (`@prisma/adapter-pg`), idempotent migration entrypoints, and `@repo/types` sync. |
| **`nestjs-backend`** | [`skills/nestjs-backend/`](./skills/nestjs-backend/SKILL.md) | Modular monolith architecture, `{ success, data, error }` response interceptor, global exception filters, and Docker polling hot-reload. |
| **`fastapi-backend`** | [`skills/fastapi-backend/`](./skills/fastapi-backend/SKILL.md) | Python 3.11+, Pydantic v2, `@asynccontextmanager` Lifespan handlers, SQLAlchemy 2.0 async + `asyncpg`, and Uvicorn hot-reloading. |
| **`turborepo-orchestration`** | [`skills/turborepo-orchestration/`](./skills/turborepo-orchestration/SKILL.md) | Advanced `turbo.json` task graph, Just-In-Time (JIT) shared TypeScript packages without intermediate compilation, and `turbo watch dev`. |

---

## 📂 Repository Directory Layout

```
.
├── skills/                      # Canonical skills directory (skills.sh compatible)
│   ├── fullstack-monorepo/      # Mother orchestrator skill
│   │   ├── SKILL.md
│   │   └── references/
│   ├── cloudflare-tunnel/       # Core infrastructure skill
│   │   └── SKILL.md
│   ├── vercel-monorepo-deploy/  # Core deployment skill
│   │   └── SKILL.md
│   ├── docker-hardening/        # Core security skill
│   │   └── SKILL.md
│   ├── prisma-database/         # Optional database skill
│   │   └── SKILL.md
│   ├── nestjs-backend/          # Optional backend skill
│   │   └── SKILL.md
│   ├── fastapi-backend/         # Optional backend skill
│   │   └── SKILL.md
│   └── turborepo-orchestration/ # Optional tooling skill
│       └── SKILL.md
├── .gitattributes               # Git LF normalization
├── .gitignore                   # Standard ignore rules
├── LICENSE                      # MIT License
├── package.json                 # Repository metadata
└── README.md                    # Project documentation
```

---

## 🤖 Compatibility

These skills are 100% compliant with the standard **Agent Skills Specification** and work across:
- **Google Antigravity IDE** (`.agents/skills/`)
- **skills.sh CLI** (`npx skills add`)
- **Claude Code** (`skills/`)
- **Cursor IDE**
- **GitHub Copilot Workspace & CLI**
- **Roo Code & Cline**

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
