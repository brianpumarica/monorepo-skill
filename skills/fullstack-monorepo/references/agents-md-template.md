# Standard `AGENTS.md` Template

---

```markdown
# AGENTS.md — [PROJECT_NAME]

## 1. Monorepo Overview
- **Backend (`apps/api`)**: [NestJS / FastAPI / Express], Port: `[3000]`
- **Frontend (`apps/web`)**: [Next.js / Vite / Expo Web], Port: `[8080]`
- **Database**: PostgreSQL 16 (Port: `[5432]`)
- **Shared Packages (`packages/`)**: `@repo/types`, `@repo/tsconfig`

---

## 2. Docker Workflows (Primary)

### Development (Hot-Reloading)
```bash
# Start full dev stack (DB + Backend + Frontend):
docker compose up -d

# Hybrid mode (Start ONLY DB + Backend, run frontend locally or on Vercel):
docker compose up -d database backend

# View logs:
docker compose logs -f backend
```

### Production (Raspberry Pi / VPS)
```bash
docker compose -f docker-compose.prod.yml up -d --build
```

---

## 3. Active Port Mapping

| Service | Container Name | Host Port | Internal Port |
| :--- | :--- | :--- | :--- |
| **Database** | `[PROJECT_NAME]-database` | `${HOST_PORT_DB:-5432}` | `5432` |
| **Backend** | `[PROJECT_NAME]-backend-dev` | `${HOST_PORT_BACKEND:-3000}` | `${PORT:-3000}` |
| **Frontend** | `[PROJECT_NAME]-frontend-dev` | `${HOST_PORT_FRONTEND:-8080}` | `${FRONTEND_PORT:-8080}` |

---

## 4. Installed & Recommended Agent Skills
- `fullstack-monorepo`: Main monorepo orchestrator and standards enforcer.
- `docker-expert`: Deep Docker command and debugging operations.
- `prisma-cli` / `postgres`: Database schema alterations and migrations.
- `vercel-deploy`: Frontend cloud deployment configuration.

---

## 5. Coding & Safety Rules
1. **Never commit `.env`**: Always keep `.env.example` updated with default dummy values.
2. **Migrations over `db push`**: In production, never run `db push`. Use `prisma migrate deploy` or `alembic upgrade head`.
3. **Shared Types**: Always export API response and request types from `packages/types` to avoid frontend-backend type drift.
4. **Validation**: Run `pnpm build` or `docker compose exec backend npm run build` before completing major tasks.
```
