# Docker Compose Templates (Dev & Prod)

> [!WARNING]
> **File Naming Standard**:
> - Development environment MUST be named **`docker-compose.yml`** (never `docker-compose.dev.yml` or `compose.dev.yml`).
> - Production environment MUST be named **`docker-compose.prod.yml`**.
> - If an existing repository contains `compose.dev.yml` or `docker-compose.dev.yml`, rename and migrate it to `docker-compose.yml` and delete the old `.dev` file.

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

> [!IMPORTANT]
> Esta plantilla es la base mínima. **Antes de desplegar hay que aplicarle los seis deltas
> obligatorios de §4**: rotación de logs, variables requeridas, nombre de imagen por entorno,
> hardening por servicio, sincronía de defaults y healthcheck nativo en servicios de aplicación.

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
    healthcheck:
      # /health y wget son placeholders — ver §4.6
      test: ["CMD-SHELL", "wget -qO- http://localhost:$$PORT/health || exit 1"]
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 15s
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

---

## 4. Endurecimiento Obligatorio del Compose de Producción

Seis deltas que se aplican **a todos los servicios** de la plantilla de §2. Ninguno es opcional
en un host compartido.

### 4.1 Rotación de logs

Sin esto, un solo proyecto llena el disco de todos los que conviven en el servidor.

```yaml
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

### 4.2 Variables obligatorias que fallan al levantar

En producción, una credencial ausente tiene que impedir el arranque — no degradarse a un default
de desarrollo:

```yaml
    environment:
      POSTGRES_PASSWORD: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
      JWT_SECRET: "${JWT_SECRET:?JWT_SECRET is required}"
```

### 4.3 Nombre de imagen distinto por entorno

Si dev y prod construyen al mismo nombre, levantar producción sin `--build` puede dejar corriendo
la imagen de desarrollo — con el servidor de desarrollo en lugar del servidor real.

```yaml
    build:
      context: .
      target: production
    image: ${PROJECT_NAME:-app}-backend-prod   # dev usa -backend-dev
```

### 4.4 Hardening por servicio — dónde sí y dónde no

```yaml
    security_opt:
      - no-new-privileges:true    # en TODOS los servicios
    cap_drop:
      - ALL                       # SÓLO en el servicio de aplicación
    deploy:
      resources:
        limits: { cpus: '2.0', memory: 512M }
        reservations: { memory: 256M }
```

| Servicio | `no-new-privileges` | `cap_drop: [ALL]` | Motivo |
| :--- | :---: | :---: | :--- |
| Aplicación / API | ✅ | ✅ | Corre como usuario sin privilegios, no bindea puertos <1024, no hace `setuid` |
| Base de datos | ✅ | ❌ | El entrypoint oficial necesita `SETUID`/`SETGID` para bajar privilegios |
| Servidor web (nginx) | ✅ | ❌ | Maneja sus propios `setuid` internos al arrancar como root |

> Verificar siempre con `docker compose -f docker-compose.prod.yml config` y con un
> `up -d --build --force-recreate` completo: el hardening rompe en el arranque, no en el `config`.

### 4.5 El default del compose anula el default de la aplicación

Cuando el compose define una variable —aunque sea con `${VAR:-valor}`—, **la variable siempre
existe dentro del contenedor**, así que el default que tenga la aplicación en su código nunca se
aplica. Los dos tienen que decir lo mismo, o el valor del compose es el único que manda.

### 4.6 Healthcheck nativo obligatorio en servicios de aplicación

Sin `healthcheck` propio, `Health` queda vacío y el deploy pipeline que espera "todo healthy"
(§2 del [runbook de CI/CD](./ci-cd-deployment-pipeline.md)) no espera nada — el smoke test puede
fallar por carrera, no por bug real.

```yaml
    healthcheck:
      test: ["CMD-SHELL", "<wget/curl/lo que traiga la imagen> http://localhost:$$PORT/<ruta-de-health> || exit 1"]
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 15s
```

Puerto, ruta y comando son placeholders: usar la variable de entorno, el endpoint y el binario
HTTP reales de ese proyecto (alpine trae `wget`; otras imágenes pueden necesitar `curl` u otra
alternativa). Usar `$$PORT` (doble `$`) para que lo resuelva el contenedor en runtime, no Compose
al parsear el YAML.
