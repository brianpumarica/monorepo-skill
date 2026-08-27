# Database Lifecycle & Entrypoint Runner

---

## 1. Idempotent `apps/api/entrypoint.sh`

```bash
#!/bin/sh
set -e

echo "==> Checking database readiness..."
MAX_TRIES=30
COUNT=0

until pg_isready -h "${DB_HOST:-database}" -p "${DB_PORT:-5432}" -U "${POSTGRES_USER:-postgres}" 2>/dev/null || [ $COUNT -eq $MAX_TRIES ]; do
  COUNT=$((COUNT + 1))
  echo "    Database not ready yet ($COUNT/$MAX_TRIES). Retrying in 1s..."
  sleep 1
done

if [ $COUNT -eq $MAX_TRIES ]; then
  echo "Error: Database timeout reached. Exiting."
  exit 1
fi

echo "==> Running database migrations..."
if [ -d "./prisma" ] || [ -f "./prisma/schema.prisma" ]; then
  if command -v pnpm >/dev/null 2>&1; then
    pnpm exec prisma migrate deploy
  elif [ -x "./node_modules/.bin/prisma" ]; then
    ./node_modules/.bin/prisma migrate deploy
  else
    npx --no-install prisma migrate deploy
  fi
elif [ -f "./alembic.ini" ]; then
  alembic upgrade head
fi

echo "==> Running idempotent seed (if present)..."
if [ -f "./dist/prisma/seed.js" ]; then
  node dist/prisma/seed.js
elif [ -f "./dist/seed.js" ]; then
  node dist/seed.js
elif [ -f "./prisma/seed.ts" ] && [ "$NODE_ENV" != "production" ]; then
  if [ -x "./node_modules/.bin/tsx" ]; then
    ./node_modules/.bin/tsx prisma/seed.ts
  else
    npx --no-install tsx prisma/seed.ts
  fi
fi

echo "==> Starting main process..."
exec "$@"
```

---

## 2. Secure Production Seeder Standard (`seed.ts`)

### Security Rules for Database Seeders:
1. **Never hardcode default admin passwords in source code**: Avoid `admin / admin123` defaults that can be leaked to git or deployed unconfigured.
2. **Mandatory Environment Variables**: Read initial administrative credentials strictly from `process.env`. Throw an error if missing.
3. **Idempotency**: Use `upsert` or check existence before creating records.

```typescript
// apps/api/prisma/seed.ts
import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcrypt';

const prisma = new PrismaClient();

async function main() {
  const adminEmail = process.env.ADMIN_EMAIL || process.env.ADMIN_USERNAME;
  const adminPassword = process.env.ADMIN_PASSWORD;

  if (!adminEmail || !adminPassword) {
    console.warn('⚠️ ADMIN_EMAIL / ADMIN_PASSWORD not set. Skipping default admin seed.');
    return;
  }

  const hashedPassword = await bcrypt.hash(adminPassword, 10);

  await prisma.user.upsert({
    where: { email: adminEmail },
    update: {},
    create: {
      email: adminEmail,
      name: 'System Admin',
      password: hashedPassword,
      role: 'ADMIN',
    },
  });

  console.log('✅ Admin user verified/seeded successfully.');
}

main()
  .catch((e) => {
    console.error('❌ Seeding error:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
```

---

## 3. Line Ending Safety (`.gitattributes`)

Always include `.gitattributes` at the monorepo root to prevent Windows CRLF issues in Linux containers:

```gitattributes
* text=auto
*.sh text eol=lf
*.sql text eol=lf
Dockerfile* text eol=lf
```
