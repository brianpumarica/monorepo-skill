# Docker Compose Templates (Dev & Prod)

> [!WARNING]
> **File Naming Standard**:
> - Development environment MUST be named **`docker-compose.yml`** (never `docker-compose.dev.yml` or `compose.dev.yml`).
> - Production environment MUST be named **`docker-compose.prod.yml`**.
> - If an existing repository contains `compose.dev.yml` or `docker-compose.dev.yml`, rename and migrate it to `docker-compose.yml` and delete the old `.dev` file.

---

## 0. Contrato de nombres (compose ↔ workflow ↔ `.env`)

**Estos nombres son obligatorios y no se renombran por proyecto.** El compose los publica, el
`.env` del servidor los define y el smoke test del
[workflow de deploy](./ci-cd-deployment-pipeline.md) §2 los consume. Que sean siempre los mismos
es lo que permite que el YAML del workflow sea **idéntico en todos los repositorios** y que un
`.env` se lea igual en cualquiera de ellos.

**Un sinónimo plausible no rompe de forma visible, y ese es el problema.** Si el compose publica
`BACKEND_HOST_PORT` y el workflow lee `HOST_PORT_BACKEND` —o `API_PORT`, o `PORT_BACKEND`—, la
expansión cae al valor por defecto y el smoke test prueba alegremente un puerto que no usa nadie.
El job sale verde. Por eso la ortografía exacta es parte del estándar, no una preferencia.

### Puertos

| Variable | Qué es | Dónde |
| :--- | :--- | :--- |
| `PORT` | Puerto **interno** del contenedor de la API | ambos compose + la app |
| `BACKEND_HOST_PORT` | Puerto del **host** hacia la API | ambos compose + smoke test del workflow |
| `FRONTEND_HOST_PORT` | Puerto del **host** hacia el front de desarrollo | compose dev |
| `DB_HOST_PORT` | Puerto del **host** hacia Postgres — **sólo desarrollo** | compose dev |

### Base de datos y credenciales

| Variable | Qué es |
| :--- | :--- |
| `POSTGRES_IMAGE` | Imagen de Postgres (permite fijar la versión) |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | Credenciales. **También las lee `entrypoint.sh`** para esperar a la base |
| `DATABASE_URL` | Cadena de conexión que consume la aplicación |
| `JWT_SECRET` / `JWT_EXPIRES_IN` | Firma de tokens |
| `ADMIN_USERNAME` / `ADMIN_PASSWORD` | Alta del administrador. `ADMIN_PASSWORD` es **obligatoria en producción** |
| `ADMIN_PASSWORD_RESET` | Vía de recuperación, `false` por defecto ([`database-lifecycle.md`](./database-lifecycle.md) §2) |

### Nombres de recursos de Docker

Un par por entorno: el sufijo separa desarrollo de producción, y el **valor** lleva el prefijo del
proyecto (§0.1).

| Variable | Ejemplo de valor |
| :--- | :--- |
| `DB_DEV_CONTAINER_NAME` / `DB_CONTAINER_NAME` | `acme-database-dev` / `acme-database` |
| `BACKEND_DEV_CONTAINER_NAME` / `BACKEND_PROD_CONTAINER_NAME` | `acme-back-dev` / `acme-back-prod` |
| `FRONTEND_DEV_CONTAINER_NAME` | `acme-front-dev` |
| `BACKEND_DEV_IMAGE` / `BACKEND_PROD_IMAGE` | `acme-backend-dev` / `acme-backend-prod` |
| `FRONTEND_DEV_IMAGE` | `acme-frontend-dev` |
| `VOLUME_PGDATA_DEV_NAME` / `VOLUME_PGDATA_NAME` | `acme_pgdata-dev` / `acme_pgdata` |

> **Los nombres de variable son fijos; los valores llevan el prefijo del proyecto.** Variables
> separadas para desarrollo y producción, nunca una sola: con una sola, el `.env` del servidor
> apunta los dos entornos al mismo contenedor y al mismo volumen — y levantar desarrollo ahí se
> lleva puesta la base productiva.

### Verificación

Antes de dar un deploy por bueno, los cuatro archivos tienen que coincidir:

```bash
for v in PORT BACKEND_HOST_PORT FRONTEND_HOST_PORT DB_HOST_PORT VOLUME_PGDATA_NAME; do
  printf '%-24s compose:%s prod:%s env:%s workflow:%s\n' "$v" \
    "$(grep -c "$v" docker-compose.yml)" "$(grep -c "$v" docker-compose.prod.yml)" \
    "$(grep -c "^$v=" .env.example)" "$(grep -rc "$v" .github/workflows/ | cut -d: -f2)"
done
```

Un `0` donde debería haber al menos `1` es exactamente el fallo silencioso de arriba.

### 0.1 En un host compartido, el prefijo por proyecto no es cosmético

Cuando el servidor hospeda varios proyectos, **todo nombre global de Docker es un espacio de
nombres compartido**: contenedores, imágenes, volúmenes y redes. Dos proyectos que elijan
`database` o `pgdata` se pisan, y el segundo en desplegar gana sin avisar.

| Recurso | Patrón |
| :--- | :--- |
| Contenedor | `<proyecto>-<servicio>-<entorno>` — `acme-database-dev`, `acme-back-prod` |
| Imagen | `<proyecto>-<servicio>-<entorno>` |
| Volumen | `<proyecto>_<datos>` — `acme_pgdata` |
| Red | propia del proyecto, declarada en el compose |

Son **dos ejes distintos y los dos hacen falta**: el prefijo separa un proyecto de sus vecinos, y
el sufijo de entorno separa desarrollo de producción **dentro** del mismo proyecto (§4.3). Faltar
el primero rompe a otro equipo; faltar el segundo se lleva puesta tu propia base productiva
cuando alguien levanta desarrollo en el servidor.

```bash
# Antes de elegir nombres y puertos para un proyecto nuevo, ver que hay tomado:
docker ps -a --format 'table {{.Names}}\t{{.Ports}}'
docker volume ls
```

El `context` y el `dockerfile` de cada servicio dependen del layout del repo, que es un eje
aparte: está en el §0 de [`dockerfile-recipes.md`](./dockerfile-recipes.md).

---

## 1. `docker-compose.yml` (Development & Hybrid by Default)

```yaml
services:
  database:
    image: ${POSTGRES_IMAGE:-postgres:16-alpine}
    container_name: ${PROJECT_NAME:-app}-database
    restart: unless-stopped
    ports:
      - "${DB_HOST_PORT:-5432}:5432"
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
      - "${BACKEND_HOST_PORT:-3004}:${PORT:-3004}"
    depends_on:
      database:
        condition: service_healthy
    environment:
      NODE_ENV: development
      PORT: ${PORT:-3004}
      # El entrypoint arma la espera de base con estas dos (database-lifecycle.md §1).
      POSTGRES_USER: ${POSTGRES_USER:-postgres}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-postgres}
      POSTGRES_DB: ${POSTGRES_DB:-app_db}
      DATABASE_URL: postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD:-postgres}@database:5432/${POSTGRES_DB:-app_db}?schema=public
      JWT_SECRET: ${JWT_SECRET:-dev-jwt-secret-key}
      CORS_ORIGIN: ${CORS_ORIGIN:-http://localhost:8084}
      # Obligatorio con volumenes montados desde Windows/WSL/macOS: sin polling, el watcher
      # no ve los eventos de archivo del host y el hot-reload no dispara (SKILL.md §8).
      CHOKIDAR_USEPOLLING: "true"
      WATCHPACK_POLLING: "true"
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
      - "${FRONTEND_HOST_PORT:-8084}:${FRONTEND_PORT:-8084}"
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
    # SIN `ports:` a proposito. El backend llega por la red interna `app-net`; publicar 5432
    # en un host compartido expone la base a todo lo que corra en la maquina y colisiona con
    # el Postgres de cualquier otro proyecto. Para depurar puntualmente, atarlo al loopback y
    # sacarlo despues:
    #   ports: ["127.0.0.1:${DB_HOST_PORT:-5432}:5432"]
    environment:
      POSTGRES_USER: ${POSTGRES_USER:?POSTGRES_USER is required}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}
      POSTGRES_DB: ${POSTGRES_DB:?POSTGRES_DB is required}
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
      - "${BACKEND_HOST_PORT:-3004}:${PORT:-3004}"
    depends_on:
      database:
        condition: service_healthy
    environment:
      NODE_ENV: production
      PORT: ${PORT:-3004}
      # El entrypoint necesita estas tres para esperar a la base y verificar con una consulta
      # real antes de migrar (database-lifecycle.md §1).
      POSTGRES_USER: ${POSTGRES_USER:?POSTGRES_USER is required}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}
      POSTGRES_DB: ${POSTGRES_DB:?POSTGRES_DB is required}
      DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@database:5432/${POSTGRES_DB}?schema=public
      JWT_SECRET: ${JWT_SECRET:?JWT_SECRET is required}
      CORS_ORIGIN: ${CORS_ORIGIN:?CORS_ORIGIN is required}
    healthcheck:
      # /health y wget son placeholders — ver §4.6. `127.0.0.1`, NO `localhost`: dentro del
      # contenedor `localhost` resuelve a ::1 y una app que escucha en 0.0.0.0 (IPv4) da
      # "connection refused" para siempre (§4.7).
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:$$PORT/health || exit 1"]
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
      test: ["CMD-SHELL", "<wget/curl/lo que traiga la imagen> http://127.0.0.1:$$PORT/<ruta-de-health> || exit 1"]
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 15s
```

Puerto, ruta y comando son placeholders: usar la variable de entorno, el endpoint y el binario
HTTP reales de ese proyecto (alpine trae `wget`; otras imágenes pueden necesitar `curl` u otra
alternativa). Usar `$$PORT` (doble `$`) para que lo resuelva el contenedor en runtime, no Compose
al parsear el YAML.

### 4.7 `127.0.0.1`, nunca `localhost`, dentro del contenedor

Verificado en `node:22-alpine`: `getent hosts localhost` devuelve **`::1`**. Una aplicación que
escucha en `0.0.0.0` está escuchando en **IPv4**, así que el healthcheck se conecta por IPv6 a un
puerto donde no hay nadie y recibe `connection refused` — indefinidamente.

```
docker inspect <contenedor> --format '{{json .State.Health}}'
→ "Output":"wget: can't connect to remote host: Connection refused"
```

Lo traicionero es que **la aplicación funciona perfecto**: `curl` desde el host contra el puerto
publicado devuelve 200, mientras el contenedor queda `unhealthy` para siempre. Y como el deploy
espera "todo healthy" (§4.6), el job falla siempre — por el healthcheck, no por la app.

- En el `healthcheck` del compose y en cualquier chequeo **dentro** del contenedor: `127.0.0.1`.
- En el smoke test del workflow, que corre **en el host** contra el puerto publicado, `localhost`
  es correcto.
- Alternativa si la app tiene que responder por las dos familias: escuchar en `::` con dual-stack.
  Cambiar el chequeo es más barato y no toca el código.
