# Multi-Stage Dockerfile Templates

> [!IMPORTANT]
> **Elegí la variante por gestor de paquetes y layout, no por gusto.** Las recetas §1 y §4 asumen
> **pnpm + workspaces + `apps/api` / `apps/web`** y contexto de build en la raíz del monorepo. Las
> §2 y §5 asumen **npm sin workspaces + `backend/` / `frontend/`** y contexto de build en la
> carpeta de cada app. Aplicar una receta pnpm sobre un repo con `package-lock.json` obliga a una
> migración que [`workspace-tooling.md`](./workspace-tooling.md) desaconseja explícitamente.

| Layout del repo | Lockfile | Backend | Frontend SPA | `context` del compose |
| :--- | :--- | :--- | :--- | :--- |
| `apps/api` + `apps/web` | `pnpm-lock.yaml` | §1 | §4 | `.` (raíz) |
| `backend/` + `frontend/` | `package-lock.json` | §2 | §5 | `./backend` / `./frontend` |
| Cualquiera | `requirements.txt` | §3 | — | según layout |

> [!WARNING]
> **Toda imagen cuyo `ENTRYPOINT` sea `entrypoint.sh` necesita `pg_isready` adentro.**
> Ni `node:22-alpine` ni `python:3.12-slim` lo traen: hay que instalar `postgresql-client` en la
> etapa `base`, para que lo hereden **desarrollo y producción**. Sin eso el entrypoint de
> [`database-lifecycle.md`](./database-lifecycle.md) §1 aborta el arranque y el contenedor nunca
> levanta (§7.3).

---

## 1. Backend: Node.js / NestJS / Express (pnpm + workspaces)

`apps/api/Dockerfile` — contexto de build: **raíz del monorepo**.

```dockerfile
FROM node:22-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
# postgresql-client: lo necesita entrypoint.sh (pg_isready + la consulta de verificacion).
RUN apk add --no-cache postgresql-client
RUN corepack enable && corepack prepare pnpm@latest --activate
WORKDIR /app

FROM base AS development
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/api/package.json ./apps/api/
COPY packages ./packages
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile
COPY . .
# Sin "|| true": si hay schema y `generate` falla, el build aborta aca en lugar de producir
# una imagen que arranca sin cliente generado.
RUN if [ -f apps/api/prisma/schema.prisma ]; then pnpm --filter api exec prisma generate; fi
RUN chmod +x apps/api/entrypoint.sh
EXPOSE 3004
ENTRYPOINT ["/app/apps/api/entrypoint.sh"]
CMD ["pnpm", "--filter", "api", "dev"]

FROM base AS build
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/api/package.json ./apps/api/
COPY packages ./packages
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile
COPY . .
RUN if [ -f apps/api/prisma/schema.prisma ]; then pnpm --filter api exec prisma generate; fi
RUN pnpm --filter api build
# El seeder se compila con su propia invocacion de tsc y su propio outDir: NO entra al build
# de la aplicacion (§7.1 explica por que eso moveria el rootDir de todo lo demas).
RUN if [ -f apps/api/prisma/seed.ts ]; then \
      pnpm --filter api exec tsc prisma/seed.ts --outDir dist/prisma --target ES2022 --module CommonJS; \
    fi
RUN pnpm --filter api --prod deploy /prod/api
# `pnpm deploy` no arrastra dist/. Sin "|| true": si falta, el build falla aca y no seis
# semanas despues, en un crash-loop de produccion.
RUN cp -r apps/api/dist /prod/api/dist
# El cliente de Prisma vive dentro de node_modules; `--prod deploy` rearma el arbol desde el
# store y puede dejarlo afuera. Se copia explicitamente si existe.
RUN if [ -d apps/api/node_modules/.prisma ]; then \
      cp -r apps/api/node_modules/.prisma /prod/api/node_modules/.prisma; \
    fi
# Red de seguridad: convierte un crash-loop silencioso en un build rojo.
RUN test -f /prod/api/dist/main.js || test -f /prod/api/dist/index.js \
    || (echo "ERROR: el build no dejo dist/main.js ni dist/index.js en /prod/api"; exit 1)

FROM base AS production
ENV NODE_ENV=production
WORKDIR /app
COPY --chown=node:node --from=build /prod/api ./
COPY --chown=node:node apps/api/entrypoint.sh ./
RUN chmod +x entrypoint.sh
USER node
EXPOSE 3004
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["node", "dist/main.js"]
```

> Verificá la imagen antes de confiar en ella — §7.2 trae los comandos exactos.

---

## 2. Backend: Node.js / NestJS / Express (npm, sin workspaces)

Para el layout `backend/` + `frontend/` en la raíz, cada uno con su `package-lock.json`.
`backend/Dockerfile` — contexto de build: **`./backend`**.

> **Requisito del proyecto:** `prisma` (o la herramienta de migraciones que uses) va en
> `dependencies`, **no** en `devDependencies` — ver
> [`database-lifecycle.md`](./database-lifecycle.md) §2.6. `npm ci --omit=dev` borra y rearma
> `node_modules` entero, así que el cliente se genera **después** de la poda, nunca antes.

```dockerfile
FROM node:22-alpine AS base
# postgresql-client: lo necesita entrypoint.sh. Se instala en `base` para que lo hereden
# tanto development como production.
RUN apk add --no-cache postgresql-client
WORKDIR /app

FROM base AS development
ENV NODE_ENV=development
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci
COPY . .
RUN if [ -f prisma/schema.prisma ]; then npx --no-install prisma generate; fi
RUN chmod +x entrypoint.sh
EXPOSE 3004
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["npm", "run", "dev"]

FROM base AS build
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci
COPY . .
RUN if [ -f prisma/schema.prisma ]; then npx --no-install prisma generate; fi
RUN npm run build
RUN if [ -f prisma/seed.ts ]; then \
      npx --no-install tsc prisma/seed.ts --outDir dist/prisma --target ES2022 --module CommonJS; \
    fi
RUN test -f dist/main.js || test -f dist/index.js \
    || (echo "ERROR: el build no genero dist/main.js ni dist/index.js"; exit 1)
# Poda primero, genera despues: al reves, `npm ci` se lleva puesto el cliente generado.
RUN --mount=type=cache,target=/root/.npm npm ci --omit=dev
RUN if [ -f prisma/schema.prisma ]; then npx --no-install prisma generate; fi

FROM base AS production
ENV NODE_ENV=production
COPY --chown=node:node --from=build /app/node_modules ./node_modules
COPY --chown=node:node --from=build /app/dist ./dist
COPY --chown=node:node --from=build /app/package.json ./package.json
# Quitar la linea siguiente si el proyecto no usa Prisma.
COPY --chown=node:node --from=build /app/prisma ./prisma
COPY --chown=node:node entrypoint.sh ./entrypoint.sh
RUN chmod +x entrypoint.sh
USER node
EXPOSE 3004
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["node", "dist/main.js"]
```

---

## 3. Backend: Python / FastAPI

`apps/api/Dockerfile` (ajustar rutas si el layout es `backend/`).

```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /build
RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev && rm -rf /var/lib/apt/lists/*
COPY apps/api/requirements.txt .
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir --upgrade pip && pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim AS base
WORKDIR /app
RUN groupadd -g 1000 appgroup && useradd -u 1000 -g appgroup -s /bin/bash appuser
# postgresql-client trae pg_isready y psql, que usa entrypoint.sh.
RUN apt-get update && apt-get install -y --no-install-recommends \
      libpq5 curl postgresql-client \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

FROM base AS development
COPY --chown=appuser:appgroup apps/api ./apps/api
RUN chmod +x apps/api/entrypoint.sh
USER appuser
EXPOSE 3004
# ENTRYPOINT obligatorio tambien en Python: sin el, las migraciones nunca corren (Fase 3).
ENTRYPOINT ["/app/apps/api/entrypoint.sh"]
# --reload-dir acota el watcher al codigo de la app; sin el, uvicorn vigila el venv entero.
CMD ["uvicorn", "apps.api.main:app", "--host", "0.0.0.0", "--port", "3004", "--reload", "--reload-dir", "/app/apps/api"]

FROM base AS production
COPY --chown=appuser:appgroup apps/api ./apps/api
RUN chmod +x apps/api/entrypoint.sh
USER appuser
EXPOSE 3004
ENTRYPOINT ["/app/apps/api/entrypoint.sh"]
CMD ["uvicorn", "apps.api.main:app", "--host", "0.0.0.0", "--port", "3004", "--workers", "4"]
```

---

## 4. Frontend SPA: Vite / React / Expo Web (pnpm + workspaces)

`apps/web/Dockerfile` — contexto de build: **raíz del monorepo**.

```dockerfile
FROM node:22-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable && corepack prepare pnpm@latest --activate
WORKDIR /app

FROM base AS development
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/web/package.json ./apps/web/
COPY packages ./packages
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile
COPY . .
EXPOSE 8084
CMD ["pnpm", "--filter", "web", "dev", "--host", "0.0.0.0", "--port", "8084"]

FROM base AS build
ARG VITE_API_URL
ARG EXPO_PUBLIC_API_URL
ENV VITE_API_URL=$VITE_API_URL EXPO_PUBLIC_API_URL=$EXPO_PUBLIC_API_URL
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/web/package.json ./apps/web/
COPY packages ./packages
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile
COPY . .
RUN pnpm --filter web build
RUN test -d apps/web/dist || (echo "ERROR: el build no genero apps/web/dist"; exit 1)

FROM nginx:alpine AS production
COPY --from=build /app/apps/web/dist /usr/share/nginx/html
COPY apps/web/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

---

## 5. Frontend SPA: Vite / React (npm, sin workspaces)

`frontend/Dockerfile` — contexto de build: **`./frontend`**.

```dockerfile
FROM node:22-alpine AS base
WORKDIR /app

FROM base AS development
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci
COPY . .
EXPOSE 8084
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0", "--port", "8084"]

FROM base AS build
# Las variables VITE_*/EXPO_PUBLIC_* se hornean en el bundle en build-time: si no llegan como
# ARG aca, el cliente sale apuntando a rutas relativas (ci-cd §4.1).
ARG VITE_API_URL
ARG EXPO_PUBLIC_API_URL
ENV VITE_API_URL=$VITE_API_URL EXPO_PUBLIC_API_URL=$EXPO_PUBLIC_API_URL
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci
COPY . .
RUN npm run build
RUN test -d dist || (echo "ERROR: el build no genero dist/"; exit 1)

FROM nginx:alpine AS production
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

### `nginx.conf` (vale para §4 y §5)

```nginx
server {
    listen 80;
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location ~* \.(?:ico|css|js|gif|jpe?g|png|woff2?|eot|ttf|svg|webp)$ {
        expires 6M;
        access_log off;
        add_header Cache-Control "public, max-age=15552000, immutable";
    }
}
```

---

## 6. Frontend SSR: Next.js Standalone

`apps/web/Dockerfile`:
```dockerfile
FROM node:22-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable && corepack prepare pnpm@latest --activate
WORKDIR /app

FROM base AS development
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/web/package.json ./apps/web/
COPY packages ./packages
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile
COPY . .
EXPOSE 8084
CMD ["pnpm", "--filter", "web", "dev", "--port", "8084"]

FROM base AS build
ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/web/package.json ./apps/web/
COPY packages ./packages
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile
COPY . .
RUN pnpm --filter web build
# `output: 'standalone'` es obligatorio en next.config: sin el, esta carpeta no existe.
RUN test -d apps/web/.next/standalone \
    || (echo "ERROR: falta .next/standalone — configurar output: standalone"; exit 1)

FROM node:22-alpine AS production
WORKDIR /app
ENV NODE_ENV=production PORT=8084
COPY --chown=node:node --from=build /app/apps/web/.next/standalone ./
COPY --chown=node:node --from=build /app/apps/web/.next/static ./apps/web/.next/static
COPY --chown=node:node --from=build /app/apps/web/public ./apps/web/public
USER node
EXPOSE 8084
CMD ["node", "apps/web/server.js"]
```

---

## 7. Trampas de Build Verificadas en Producción

### 7.1 Los scripts de mantenimiento no van en el build

**Regla genérica:** el build de producción compila **sólo** el directorio fuente de la aplicación.
Los scripts de mantenimiento (seeders, exportadores, generadores) viven fuera y se excluyen en
bloque —por directorio, nunca archivo por archivo—, porque el próximo que se agregue no va a estar
en la lista.

> **No contradice la compilación del seeder de §1 y §2.** Ahí el seeder se compila con una
> invocación `tsc` **propia**, con su propio `outDir`: eso es correcto y deliberado. La regla habla
> del build de la aplicación (`tsconfig.build.json` / `nest build`), donde un archivo de más mueve
> la raíz de salida de todo lo demás.

**Cómo se manifiesta en TypeScript:** basta un `.ts` incluido fuera de `src/` para que el
compilador suba el `rootDir` un nivel. La salida deja de ser `dist/main.js` y pasa a
`dist/src/main.js`, mientras el `CMD` de la imagen sigue apuntando a la ruta vieja:

```
Error: Cannot find module '/app/dist/main'
```

El contenedor entra en crash-loop. En `tsconfig.build.json`, excluir el directorio entero:

```json
{ "exclude": ["node_modules", "test", "dist", "prisma/**"] }
```

> Los `RUN test -f dist/main.js || ... exit 1` de §1 y §2 existen exactamente para esto: convierten
> un crash-loop que puede pasar semanas inadvertido en un build rojo, en el momento.

### 7.2 La imagen final debe traer todo lo que el entrypoint necesita

Si el entrypoint corre migraciones o un seeder, sus binarios tienen que estar **dentro** de la
imagen. Si no, se descargan en cada arranque y el contenedor depende de la red para levantar —y
falla en silencio cuando no hay.

```bash
# Verificacion tras construir la imagen de produccion — los tres chequeos, no uno:
docker run --rm --entrypoint sh <imagen> -c "command -v pg_isready; command -v psql"
docker run --rm --entrypoint sh <imagen> -c "ls node_modules/.bin | grep -E 'prisma|tsx|alembic'"
docker run --rm --entrypoint sh <imagen> -c "ls -d node_modules/.prisma || echo 'sin cliente Prisma generado'"
```

### 7.3 `pg_isready` no viene en las imágenes base

`node:22-alpine` y `python:3.12-slim` **no incluyen** `pg_isready`. Un `entrypoint.sh` que lo
invoca en una imagen sin `postgresql-client` no falla de forma obvia: agota el ciclo de reintentos
—medio minuto de nada— y recién ahí aborta, con un mensaje que parece de base de datos caída
cuando en realidad falta un paquete.

```dockerfile
RUN apk add --no-cache postgresql-client                  # alpine
RUN apt-get update && apt-get install -y --no-install-recommends postgresql-client \
    && rm -rf /var/lib/apt/lists/*                        # debian/slim
```

Va en la etapa `base` —la que heredan desarrollo **y** producción—, nunca en una sola. El
entrypoint de [`database-lifecycle.md`](./database-lifecycle.md) §1 además chequea que el binario
exista y aborta con un mensaje explícito si falta, en vez de esperar los 30 reintentos.
