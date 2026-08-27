---
name: prisma-database
description: Complete database management, schema architecture, and migration lifecycle standard for Prisma ORM with PostgreSQL in full-stack monorepos. Covers multi-file schemas (prismaSchemaFolder), connection pooling with pg adapter, typed seeders, safe migration deployment inside container entrypoints, and exporting Prisma types to shared workspace packages. Use whenever setting up, refactoring, or running migrations with Prisma in a monorepo.
---

# Prisma ORM & Database Lifecycle Runbook

This skill establishes the production standard for managing PostgreSQL databases with **Prisma ORM** inside modern full-stack monorepos.

---

## 1. Directory & Multi-File Schema Layout (`prismaSchemaFolder`)

Prisma supports modular schema files, splitting models into logical domains:

```
apps/api/prisma/
├── schema/
│   ├── base.prisma       # Generator, datasource, and enums
│   ├── user.prisma       # User, Account, Session models
│   └── post.prisma       # Business domain models
├── migrations/           # Version-controlled SQL migrations
├── seed.ts               # Typed seeding script executed via tsx
└── entrypoint.sh         # Startup runner for migrations
```

### `apps/api/prisma/schema/base.prisma`:
```prisma
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

generator client {
  provider        = "prisma-client-js"
  previewFeatures = ["prismaSchemaFolder"]
}
```

### `apps/api/prisma/schema/user.prisma`:
```prisma
enum Role {
  USER
  ADMIN
}

model User {
  id        String   @id @default(uuid())
  email     String   @unique
  name      String?
  role      Role     @default(USER)
  createdAt DateTime @default(now()) @map("created_at")
  updatedAt DateTime @updatedAt @map("updated_at")

  @@map("users")
}
```

---

## 2. Shared Types Integration (`@repo/types`)

To make database models accessible to both frontend (`apps/web`) and backend (`apps/api`) without circular dependencies:

In `packages/types/package.json`:
```json
{
  "name": "@repo/types",
  "version": "0.0.1",
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "dependencies": {
    "@prisma/client": "^5.14.0"
  }
}
```

In `packages/types/src/index.ts`:
```typescript
export type { User, Role } from '@prisma/client';

export interface UserResponseDto {
  id: string;
  email: string;
  name: string | null;
  role: string;
}
```

---

## 3. Production Connection Pooling (`@prisma/adapter-pg`)

For maximum connection efficiency on PostgreSQL (preventing connection exhaustion under load):

```typescript
// apps/api/src/db.ts
import { Pool } from 'pg';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@prisma/client';

const connectionString = process.env.DATABASE_URL;

const pool = new Pool({
  connectionString,
  max: 10,                 // Limit connections on Raspberry Pi
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

const adapter = new PrismaPg(pool);

export const prisma = new PrismaClient({
  adapter,
  log: process.env.NODE_ENV === 'development' ? ['query', 'error', 'warn'] : ['error'],
});
```

---

## 4. Development vs Production Workflow

| Task | Command (Development) | Command (Production / CI) |
| :--- | :--- | :--- |
| **New Schema Change** | `npx prisma migrate dev --name <change_name>` | **Never run `migrate dev` in prod** |
| **Quick Prototyping** | `npx prisma db push` | *Forbidden in production* |
| **Apply Migrations** | `npx prisma migrate dev` | `npx prisma migrate deploy` |
| **Generate Client** | `npx prisma generate` | `npx prisma generate` (during build) |
| **Seed Database** | `npx tsx prisma/seed.ts` | `npx tsx prisma/seed.ts` (controlled) |
| **Inspect Data GUI** | `npx prisma studio --port 5555` | Use Cloudflare TCP tunnel if needed |

---

## 5. Production Entrypoint (`apps/api/entrypoint.sh`)

Ensure migrations and compiled seeders run automatically before the API process launches:

```bash
#!/bin/sh
set -e

echo "⏳ Waiting for PostgreSQL database to be ready..."
until pg_isready -h "${DATABASE_HOST:-database}" -p "${DATABASE_PORT:-5432}" -U "${POSTGRES_USER:-postgres}"; do
  sleep 1
done
echo "✅ Database connection established."

echo "🚀 Applying database migrations..."
npx prisma migrate deploy

echo "🌱 Running production database seed (if present)..."
if [ -f "./dist/prisma/seed.js" ]; then
  node dist/prisma/seed.js || true
elif [ -f "./dist/seed.js" ]; then
  node dist/seed.js || true
elif [ -f "./prisma/seed.ts" ]; then
  npx tsx prisma/seed.ts 2>/dev/null || true
fi

echo "🌟 Starting application server..."
exec "$@"
```

---

## 6. Production Seeder Compilation & Security Standard

### Compilation in Dockerfile (Build Stage):
Because production Docker containers prune `devDependencies` (omitting `ts-node` and `tsx`), compile the seed script into JavaScript during the build stage:

```dockerfile
# In apps/api/Dockerfile (build stage)
RUN if [ -f apps/api/prisma/seed.ts ]; then npx tsc apps/api/prisma/seed.ts --outDir apps/api/dist/prisma --target ES2022 --module CommonJS 2>/dev/null || true; fi
```

### Seeder Security Rules (`apps/api/prisma/seed.ts`):
1. **No Hardcoded Passwords**: Never write fallback default passwords (e.g. `'admin123'`) in the code.
2. **Environment Variable Enforcement**: Read `ADMIN_EMAIL` and `ADMIN_PASSWORD` from `process.env`. If absent in production, skip or abort gracefully with a security warning rather than provisioning a vulnerable account.
3. **Idempotency**: Use `upsert` so re-deployments with `--force-recreate` never duplicate or corrupt existing records.

---

## 7. Deep-Dive Reference Guides

- [Prisma ORM, pgvector & PostgreSQL Extension Standard](./references/pgvector-and-extensions.md) (pgvector embeddings, RAG similarity search queries, and connection pool tuning).

