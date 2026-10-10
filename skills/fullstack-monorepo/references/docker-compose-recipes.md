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
| `FRONTEND_HOST_PORT` | Puerto del **host** hacia el front de desarrollo. **Opcional**: si el frontend de producción va a Vercel, no lleva línea en `.env.example` (ver la nota de abajo) | compose dev |
| `DB_HOST_PORT` | Puerto del **host** hacia Postgres. **Siempre atado a `127.0.0.1`** (§4.9); en producción es opcional y único por proyecto | ambos compose |
| `HEALTH_PATH` | Ruta del endpoint de salud (default del estándar: `/api/health`) | `healthcheck` del compose prod + smoke test del workflow ([CI/CD §9](./ci-cd-deployment-pipeline.md)) |

> [!NOTE]
> **Frontend en Vercel: sin `FRONTEND_HOST_PORT=` en `.env.example`.** `crear-env.sh` completa
> **toda** `*_HOST_PORT=` vacía de la plantilla con un puerto libre del servidor, y `chequear-host.sh`
> lo respeta como reservado: con el frontend fuera del servidor quedaría un puerto apartado que
> nadie publica. El compose de desarrollo ya trae un valor por defecto (`${FRONTEND_HOST_PORT:-8084}`),
> así que la línea no hace falta. Si el frontend sí corre en un contenedor del servidor, la línea
> va vacía, como las demás `*_HOST_PORT`.

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
| `PROJECT_PREFIX` | `acme`: el prefijo del proyecto. El workflow lo lee para el contenedor de la base, la imagen del rollback y la etiqueta `com.proyecto` de la poda |
| `IMAGE_TAG` | **No va en el `.env`**: lo fija el workflow al SHA del commit (`github.sha`). El compose lo usa con default `latest` |

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

### 0.2 Puertos en la máquina de desarrollo: uno fijo por proyecto

> Visión de conjunto —tu máquina y el servidor— en [`puertos.md`](./puertos.md).

En una máquina donde se crean muchos proyectos de prueba, el 3000 / 5173 / 8080 de los tutoriales
choca siempre, y lo peor no es el error: es que **Vite y Next se mueven solos al puerto
siguiente** sin avisar, y el proyecto "levanta" en un lugar que nadie esperaba. Hay que hablarle
a otra persona (o a un agente) para saber dónde quedó.

La solución es que cada proyecto tenga **siempre el mismo bloque de 10 puertos** y que ningún
servidor de desarrollo se mueva por su cuenta. [`puerto.sh`](./puerto.sh) lo asigna:

```bash
# Una sola vez por máquina (no por repo). En Git Bash, ~/bin ya suele estar en el PATH:
cp puerto.sh ~/bin/puerto && chmod +x ~/bin/puerto

# En la carpeta de cada proyecto nuevo, la primera vez:
puerto asignar            # escribe FRONTEND/BACKEND/DB en el .env, siempre los mismos
puerto listar             # todos tus proyectos, sus puertos y cuáles están corriendo AHORA
puerto quien 4661         # de quién es ese puerto
```

El bloque sale del nombre de la carpeta (rango 4000-4999, lejos de los puertos de los tutoriales)
y se anota en `~/.puertos`, **fuera de todo repositorio**. Si dos nombres caen en el mismo
bloque, el segundo recibe el siguiente libre y queda registrado: nunca se pisan.

| Puerto | Variables que escribe en el `.env` |
| :--- | :--- |
| bloque + 0 | `FRONTEND_HOST_PORT` y `FRONTEND_PORT` |
| bloque + 1 | `BACKEND_HOST_PORT` y `PORT` |
| bloque + 2 | `DB_HOST_PORT` |

**El mismo número por fuera y por dentro del contenedor** (`4661:4661`) es lo que permite usar
los dos modos con un solo `.env`: `docker compose up` publica `${BACKEND_HOST_PORT}:${PORT}`, y
`npm run dev` directo escucha en `PORT`. Para una base en Docker con la app corriendo fuera,
`DATABASE_URL` apunta a `localhost:${DB_HOST_PORT}`.

Para que un servidor **falle en vez de moverse**, el puerto tiene que ser explícito y estricto:

```ts
// vite.config.ts — loadEnv lee el .env de la carpeta que se le indica ('..' = raíz del monorepo)
import { defineConfig, loadEnv } from 'vite'
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, '..', '')
  return { server: { port: Number(env.FRONTEND_HOST_PORT) || 5173, strictPort: true } }
})
```

Un backend Node/Express/Nest que hace `listen(process.env.PORT)` ya falla con `EADDRINUSE` si
está ocupado, sin moverse. En frameworks que aceptan `--port`/`-p`, indicarlo explícitamente
produce el mismo efecto.

> `puerto.sh` es para **desarrollo local**. El servidor usa [`chequear-host.sh`](./chequear-host.sh)
> (CI/CD §2.4) y los puertos de su propio `.env`; el `.env` local está en `.gitignore` y nunca
> viaja, así que ambos mundos no se pisan.

El `context` y el `dockerfile` de cada servicio dependen del layout del repo, que es un eje
aparte: está en el §0 de [`dockerfile-recipes.md`](./dockerfile-recipes.md).

---

## 1. `docker-compose.yml` (Development & Hybrid by Default)

```yaml
services:
  database:
    image: ${POSTGRES_IMAGE:-postgres:16-alpine}
    container_name: ${PROJECT_PREFIX:-app}-database
    restart: unless-stopped
    ports:
      - "127.0.0.1:${DB_HOST_PORT:-5432}:5432"   # loopback: la base nunca sale de la máquina (§4.9)
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
    container_name: ${PROJECT_PREFIX:-app}-backend-dev
    restart: unless-stopped
    ports:
      # Desarrollo: sin `127.0.0.1:` a propósito, para probar desde el celular en la misma red.
      # En producción sí va atado al loopback (§4.9).
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
    container_name: ${PROJECT_PREFIX:-app}-frontend-dev
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
    name: ${PROJECT_PREFIX:-app}_pgdata

networks:
  app-net:
    driver: bridge
```

---

## 2. `docker-compose.prod.yml` (Production for Raspberry Pi / VPS)

> [!IMPORTANT]
> Esta plantilla es la base mínima. **Antes de desplegar hay que aplicarle los ocho deltas
> obligatorios de §4**: rotación de logs, variables requeridas, nombre de imagen por entorno (con
> tag por commit), hardening por servicio, sincronía de defaults, healthcheck nativo en servicios de
> aplicación, etiqueta de proyecto en las imágenes y puertos en loopback.

```yaml
services:
  database:
    image: ${POSTGRES_IMAGE:-postgres:16-alpine}
    container_name: ${PROJECT_PREFIX:-app}-database
    restart: unless-stopped
    # Solo en loopback (§4.9): el backend llega por la red interna `app-net`, y `127.0.0.1`
    # alcanza para un psql o un tunel SSH desde el propio servidor. Publicar 5432 en todas las
    # interfaces expone la base a la red local. DB_HOST_PORT tiene que ser unico por proyecto
    # en el host (dos proyectos con el mismo puerto: "port is already allocated" en el `up`).
    ports:
      - "127.0.0.1:${DB_HOST_PORT:-5432}:5432"
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
      labels:
        com.proyecto: ${PROJECT_PREFIX:-app}   # habilita la poda acotada (§4.8)
    # Tag por commit: lo fija IMAGE_TAG en el workflow; `latest` sólo para un `up` manual (§4.3).
    image: ${PROJECT_PREFIX:-app}-backend-prod:${IMAGE_TAG:-latest}
    container_name: ${PROJECT_PREFIX:-app}-backend-prod
    restart: unless-stopped
    ports:
      - "127.0.0.1:${BACKEND_HOST_PORT:-3004}:${PORT:-3004}"   # loopback: entra solo el Tunnel (§4.9)
    depends_on:
      database:
        condition: service_healthy
    environment:
      NODE_ENV: production
      PORT: ${PORT:-3004}
      HEALTH_PATH: ${HEALTH_PATH:-/api/health}   # la lee el healthcheck de abajo y el smoke test
      # El entrypoint necesita estas tres para esperar a la base y verificar con una consulta
      # real antes de migrar (database-lifecycle.md §1).
      POSTGRES_USER: ${POSTGRES_USER:?POSTGRES_USER is required}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}
      POSTGRES_DB: ${POSTGRES_DB:?POSTGRES_DB is required}
      DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@database:5432/${POSTGRES_DB}?schema=public
      JWT_SECRET: ${JWT_SECRET:?JWT_SECRET is required}
      CORS_ORIGIN: ${CORS_ORIGIN:?CORS_ORIGIN is required}
    healthcheck:
      # wget es placeholder — ver §4.6. La ruta es HEALTH_PATH, la misma que usa el smoke test
      # (CI/CD §9.3). `127.0.0.1`, NO `localhost`: dentro del contenedor `localhost` resuelve a
      # ::1 y una app que escucha en 0.0.0.0 (IPv4) da "connection refused" para siempre (§4.7).
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:$$PORT$${HEALTH_PATH:-/api/health} || exit 1"]
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 15s
    networks:
      - app-net

volumes:
  pgdata:
    name: ${PROJECT_PREFIX:-app}_pgdata

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
docker logs -f ${PROJECT_PREFIX:-app}-backend-prod
```

---

## 4. Endurecimiento Obligatorio del Compose de Producción

Ocho deltas que se aplican **a todos los servicios** de la plantilla de §2. Ninguno es opcional
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

### 4.3 Nombre de imagen distinto por entorno, y tag por commit

Dos problemas distintos que se resuelven en la misma línea:

1. **Nombre por entorno.** Si dev y prod construyen al mismo nombre, levantar producción sin
   `--build` puede dejar corriendo la imagen de desarrollo — con el servidor de desarrollo en
   lugar del servidor real.
2. **Tag por commit.** Con `:latest`, cuando la verificación post-deploy falla no existe imagen
   anterior a la que volver: el rollback es imposible por construcción.

```yaml
    build:
      context: .
      target: production
    # dev usa -backend-dev. El tag sale de IMAGE_TAG (el workflow lo fija al SHA del commit);
    # `latest` queda sólo como default para un `up` manual desde el servidor.
    image: ${PROJECT_PREFIX:-app}-backend-prod:${IMAGE_TAG:-latest}
```

> El rollback depende de esta línea. Ver [CI/CD §2.1](./ci-cd-deployment-pipeline.md) para las
> otras dos piezas (`IMAGE_TAG` en el workflow y el archivo `last-good-tag` en el servidor).

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
    # Para Node.js / Alpine (con wget nativo):
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:$$PORT$${HEALTH_PATH:-/api/health} || exit 1"]
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 15s

    # Para Python (ej. python:*-slim) sin instalar curl ni wget:
    healthcheck:
      test: ["CMD-SHELL", "python -c 'import urllib.request; urllib.request.urlopen(\"http://127.0.0.1:8000/api/health\")' || exit 1"]   # misma ruta que HEALTH_PATH
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 15s
```

Puerto y comando son adaptables por stack; la **ruta no**: es `HEALTH_PATH` y tiene que coincidir con el `.env` y el smoke test ([CI/CD §9](./ci-cd-deployment-pipeline.md)). En el ejemplo de Python, dentro de `python -c '...'` el shell no expande variables, así que la ruta se escribe literal. Para el resto: usar `127.0.0.1` (no `localhost`) y binarios nativos del runtime (como `urllib.request` en Python, para no instalar paquetes extras). Usar `$$PORT` (doble `$`) si se desea que lo resuelva el contenedor en runtime, no Compose al parsear el YAML.

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

### 4.8 Etiqueta de proyecto: la única poda segura en un host compartido

`docker system prune` está prohibido porque se lleva lo de los demás proyectos. Pero si nada se
poda nunca, cada despliegue deja una imagen huérfana y la SD del Pi se llena — que es la misma
caída, sólo que más lenta y para todos a la vez.

La salida es etiquetar las imágenes en el build, para poder podar **sólo las propias**:

```yaml
    build:
      context: .
      target: production
      labels:
        com.proyecto: ${PROJECT_PREFIX:-app}
```

Con eso, el paso de poda del workflow ([CI/CD §2](./ci-cd-deployment-pipeline.md)) queda acotado al
proyecto:

```bash
docker image prune -af --filter "label=com.proyecto=<proyecto>" --filter "until=720h"
```

Tres detalles que hacen que esto sea seguro:

- **`build.labels` etiqueta la imagen**, no el contenedor. `docker image prune --filter label=`
  lee la etiqueta de la imagen: ponerla en `services.<svc>.labels` no sirve para podar.
- **La imagen en uso nunca se poda**, así que la versión recién desplegada está a salvo.
- **La poda corre después de promover**, nunca antes de verificar: podar primero borraría
  justo la imagen anterior que el rollback necesita.

### 4.9 Puertos de producción en `127.0.0.1`, no en todas las interfaces

`"3004:3004"` publica en `0.0.0.0`: cualquiera en la red local llega al servicio **salteando**
Cloudflare Access (o lo que haya delante). Con `"127.0.0.1:3004:3004"` solo llega el propio
servidor, y eso es todo lo que necesita quien entra por el Tunnel.

| Servicio | Publicación en producción |
| :--- | :--- |
| Base de datos | `127.0.0.1:${DB_HOST_PORT}:5432` — solo para un `psql` desde el servidor. Los backups usan `docker exec`, no el puerto |
| Backend | `127.0.0.1:${BACKEND_HOST_PORT}:${PORT}` |
| Frontend servido por contenedor (nginx) | `127.0.0.1:${FRONTEND_HOST_PORT}:80`. Si el frontend va a Vercel, no hay nada que publicar |

**Verificar antes de aplicarlo** cómo apunta cada ruta del Tunnel (`ingress` en
`/etc/cloudflared/config.yml`, o el dashboard de Zero Trust):

- `service: http://localhost:<puerto>` → funciona con `127.0.0.1`.
- `service: http://<IP-de-la-LAN>:<puerto>` → deja de andar. Cambiarlo a `localhost` primero.
- `cloudflared` corriendo **como contenedor** no ve el loopback del host: ahí el servicio se
  alcanza por la red de Docker (`http://backend:3004`) y no hace falta publicar el puerto.

Probarlo: `ss -tlnp | grep <puerto>` tiene que mostrar `127.0.0.1:<puerto>`, no `0.0.0.0` ni
`*`. El smoke test del workflow corre en el host contra `localhost` y sigue funcionando.

**Probado en producción:** con el puerto atado a `127.0.0.1` y la ruta del Tunnel en
`service: http://localhost:<puerto>`, las siete rutas públicas siguieron respondiendo `200`.
`localhost` se resuelve primero a `::1`, donde el puerto no escucha: `cloudflared` no conecta ahí
y cae a IPv4, sin corte visible. No hace falta cambiar `localhost` por `127.0.0.1` en el `ingress`.

En desarrollo la base también va al loopback, pero backend y frontend quedan abiertos a
propósito, para probar desde otro dispositivo de la red.
