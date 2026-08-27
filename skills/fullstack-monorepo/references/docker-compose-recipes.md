# Docker Compose Templates (Dev & Prod)

---

## 1. `docker-compose.yml` (Development & Hybrid by Default)

```yaml
services:
  database:
    image: ${POSTGRES_IMAGE:-postgres:16-alpine}
    container_name: ${PROJECT_NAME:-app}-database
    restart: unless-stopped
    ports:
      - "${HOST_PORT_DB:-5432}:5432"
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-postgres}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-postgres}
      POSTGRES_DB: ${POSTGRES_DB:-app_db}
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./docker/init-db.sql:/docker-entrypoint-initdb.d/01-init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-app_db}"]
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 10s
    networks:
      - app-net

  backend:
    build:
      context: .
      dockerfile: ./apps/api/Dockerfile
      target: development
    container_name: ${PROJECT_NAME:-app}-backend-dev
    restart: unless-stopped
    ports:
      - "${HOST_PORT_BACKEND:-3004}:${PORT:-3004}"
    depends_on:
      database:
        condition: service_healthy
    environment:
      NODE_ENV: development
      PORT: ${PORT:-3004}
      DATABASE_URL: postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD:-postgres}@database:5432/${POSTGRES_DB:-app_db}?schema=public
      JWT_SECRET: ${JWT_SECRET:-dev-jwt-secret-key}
      CORS_ORIGIN: ${CORS_ORIGIN:-http://localhost:8084}
    volumes:
      - ./apps/api:/app/apps/api
      - ./packages:/app/packages
      - /app/node_modules
      - /app/apps/api/node_modules
    networks:
      - app-net

  frontend:
    build:
      context: .
      dockerfile: ./apps/web/Dockerfile
      target: development
    container_name: ${PROJECT_NAME:-app}-frontend-dev
    restart: unless-stopped
    ports:
      - "${HOST_PORT_FRONTEND:-8084}:${FRONTEND_PORT:-8084}"
    depends_on:
      - backend
    environment:
      NODE_ENV: development
      WATCHPACK_POLLING: "true"
      VITE_API_URL: ${VITE_API_URL:-http://localhost:3004}
      NEXT_PUBLIC_API_URL: ${NEXT_PUBLIC_API_URL:-http://localhost:3004}
      EXPO_PUBLIC_API_URL: ${EXPO_PUBLIC_API_URL:-http://localhost:3004}
    volumes:
      - ./apps/web:/app/apps/web
      - ./packages:/app/packages
      - /app/node_modules
      - /app/apps/web/node_modules
      - /app/apps/web/.next
    networks:
      - app-net

volumes:
  pgdata:
    name: ${PROJECT_NAME:-app}_pgdata

networks:
  app-net:
    driver: bridge
```

---

## 2. `docker-compose.prod.yml` (Production for Raspberry Pi / VPS)

```yaml
services:
  database:
    image: ${POSTGRES_IMAGE:-postgres:16-alpine}
    container_name: ${PROJECT_NAME:-app}-database
    restart: unless-stopped
    ports:
      - "${HOST_PORT_DB:-5432}:5432"
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./docker/init-db.sql:/docker-entrypoint-initdb.d/01-init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - app-net

  backend:
    build:
      context: .
      dockerfile: ./apps/api/Dockerfile
      target: production
    container_name: ${PROJECT_NAME:-app}-backend-prod
    restart: unless-stopped
    ports:
      - "${HOST_PORT_BACKEND:-3004}:${PORT:-3004}"
    depends_on:
      database:
        condition: service_healthy
    environment:
      NODE_ENV: production
      PORT: ${PORT:-3004}
      DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@database:5432/${POSTGRES_DB}?schema=public
      JWT_SECRET: ${JWT_SECRET}
      CORS_ORIGIN: ${CORS_ORIGIN}
    networks:
      - app-net

volumes:
  pgdata:
    name: ${PROJECT_NAME:-app}_pgdata

networks:
  app-net:
    driver: bridge
```

---

## 3. Production Deployment & Re-creation Command

When deploying updates on Raspberry Pi / Linux VPS (either via Self-Hosted Runner or CLI), ALWAYS use `--force-recreate --remove-orphans`:

```bash
# Build latest images and force recreation of running containers:
docker compose -f docker-compose.prod.yml up -d --build --force-recreate --remove-orphans

# Check status and health of all production services:
docker compose -f docker-compose.prod.yml ps

# View live backend logs:
docker logs -f ${PROJECT_NAME:-app}-backend-prod
```

