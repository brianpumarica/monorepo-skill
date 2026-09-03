# Standard `AGENTS.md` Template

---

```markdown
# AGENTS.md — [PROJECT_NAME]

## 1. Monorepo Overview
- **Backend (`apps/api`)**: [NestJS / FastAPI / Express], Port: `[3004]`
- **Frontend (`apps/web`)**: [Next.js / Vite / Expo Web], Port: `[8084]`
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
| **Backend** | `[PROJECT_NAME]-backend-dev` | `${HOST_PORT_BACKEND:-3004}` | `${PORT:-3004}` |
| **Frontend** | `[PROJECT_NAME]-frontend-dev` | `${HOST_PORT_FRONTEND:-8084}` | `${FRONTEND_PORT:-8084}` |

---

## 4. Installed & Recommended Agent Skills
- `fullstack-monorepo`: Main monorepo orchestrator and standards enforcer.
- `docker-hardening`: Deep Docker security, non-root execution, and debugging operations.
- `prisma-database` / `fastapi-backend` / `nestjs-backend`: Database & backend architecture.
- `vercel-monorepo-deploy`: Frontend cloud deployment configuration.
- `cloudflare-tunnel`: Zero Trust remote exposure without opening router ports.

---

## 5. Coding & Safety Rules
1. **Never commit `.env`**: Always keep `.env.example` updated with default dummy values.
2. **Migrations over `db push`**: In production, never run `db push`. Use `prisma migrate deploy` or `alembic upgrade head`.
3. **Shared Types**: Always export API response and request types from `packages/types` to avoid frontend-backend type drift.
4. **Validation**: Run `pnpm build` or `docker compose exec backend npm run build` before completing major tasks.
```
---

## Reglas de Mantenimiento de `AGENTS.md`

1. **Auditar el drift en cada release.** Los comandos que documenta este archivo envejecen y
   algunos se vuelven destructivos con el tiempo: un `down -v` documentado como "resetear la base"
   es inofensivo en local y borra el volumen productivo en el servidor. `AGENTS.md` no es
   documentación histórica, es una **instrucción activa** para el próximo agente.
2. **Verificar contra la realidad**: credenciales de ejemplo que ya no existen, conteos de
   entidades hardcodeados, valores de enum incompletos y versiones de runtime desactualizadas son
   los desvíos más frecuentes.
3. **La matriz de puertos incluye los del host**, no sólo los del proyecto, cuando el servidor es
   compartido.

### Secciones obligatorias adicionales de la plantilla

```markdown
## 6. Comandos Prohibidos

| No ejecutar | Por qué |
| :--- | :--- |
| `docker system prune` / `docker container prune` | El host es compartido: se lleva contenedores de otros proyectos |
| `docker compose down -v` | Borra el volumen de datos productivo |
| `docker compose down` sin `-f docker-compose.prod.yml` | Actúa sobre lo que Compose cree que es el proyecto actual |
| Parar la aplicación para hacer un volcado | Al arrancar se reejecuta el entrypoint; el volcado en caliente ya es consistente |
| `docker exec -t` con redirección a archivo | La TTY convierte LF en CRLF y corrompe el archivo |
```
