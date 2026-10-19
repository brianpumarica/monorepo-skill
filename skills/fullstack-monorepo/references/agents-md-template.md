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

| Service | Container Name | Host Port — desarrollo (`puerto asignar`) | Host Port — servidor (`chequear-host.sh alta`) | Internal Port |
| :--- | :--- | :--- | :--- | :--- |
| **Database** | `[PROJECT_PREFIX]-database-dev` (prod: `[PROJECT_PREFIX]-database`) | `[DB_HOST_PORT local]` | `[DB_HOST_PORT servidor]` | `5432` |
| **Backend** | `[PROJECT_PREFIX]-backend-dev` | `[BACKEND_HOST_PORT local]` | `[BACKEND_HOST_PORT servidor]` | igual al de desarrollo / `${PORT}` |
| **Frontend** | `[PROJECT_PREFIX]-frontend-dev` | `[FRONTEND_HOST_PORT local]` | `[FRONTEND_HOST_PORT servidor]` | `${FRONTEND_PORT}` |

> Completar con los números **reales**, no con los defaults del compose (3004 / 8084 / 5432): los
> defaults son los que chocan entre proyectos. Ver `puertos.md` de la skill.

---

## 4. Installed & Recommended Agent Skills
- `fullstack-monorepo` **v[X.Y.Z]** (copia instalada el [AAAA-MM-DD]): Main monorepo orchestrator and standards enforcer. La versión sale de `metadata.version` en `.agents/skills/fullstack-monorepo/SKILL.md`; cada vez que se actualiza la copia (SKILL §6), se cambia acá.
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
4. **La versión de la skill se anota y se mantiene.** La línea de `fullstack-monorepo` de la sección 4
   lleva el número de versión de la copia instalada: sin él, nadie sabe contra qué reglas se auditó el
   repo ni cuándo conviene actualizarla (`CHANGELOG.md` de la skill dice qué cambió).
5. **Un repo sin Docker (solo frontend en Vercel)** reemplaza las secciones 2 y 3 por los comandos
   del proyecto (`npm run dev`, `build`, `lint`), el puerto del servidor de desarrollo y una línea sobre
   el despliegue («push a `main` → Actions → Vercel; el PR solo compila»). Ver `perfiles-de-despliegue.md` §2.

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
