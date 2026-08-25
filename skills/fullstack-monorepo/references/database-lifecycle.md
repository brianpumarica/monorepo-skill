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
if [ -f "./prisma/schema.prisma" ]; then
  npx prisma migrate deploy --schema=./prisma/schema.prisma
elif [ -f "./alembic.ini" ]; then
  alembic upgrade head
fi

echo "==> Running idempotent seed (if present)..."
if [ -f "./dist/prisma/seed.js" ]; then
  node dist/prisma/seed.js || true
elif [ -f "./prisma/seed.ts" ]; then
  npx tsx prisma/seed.ts || true
fi

echo "==> Starting main process..."
exec "$@"
```

---

## 2. Line Ending Safety (`.gitattributes`)

Always include `.gitattributes` at the monorepo root to prevent Windows CRLF issues in Linux containers:

```gitattributes
* text=auto
*.sh text eol=lf
*.sql text eol=lf
Dockerfile* text eol=lf
```
