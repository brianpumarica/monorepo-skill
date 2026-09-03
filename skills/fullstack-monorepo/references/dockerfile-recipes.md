# Multi-Stage Dockerfile Templates

---

## 1. Backend: Node.js / NestJS / Express (pnpm)

`apps/api/Dockerfile`:
```dockerfile
FROM node:22-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable && corepack prepare pnpm@latest --activate
WORKDIR /app

FROM base AS development
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/api/package.json ./apps/api/
COPY packages ./packages
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile
COPY . .
RUN pnpm --filter api exec prisma generate 2>/dev/null || true
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
RUN pnpm --filter api exec prisma generate 2>/dev/null || true
RUN pnpm --filter api build
# Compile TypeScript seeder so it can run in production without devDependencies/ts-node
RUN if [ -f apps/api/prisma/seed.ts ]; then pnpm --filter api exec tsc prisma/seed.ts --outDir dist/prisma --target ES2022 --module CommonJS 2>/dev/null || true; fi
RUN pnpm --filter api --prod deploy /prod/api
# Ensure compiled dist folder is included in deployed bundle
RUN cp -r apps/api/dist /prod/api/dist 2>/dev/null || true

FROM node:22-alpine AS production
WORKDIR /app
USER node
COPY --chown=node:node --from=build /prod/api ./
COPY --chown=node:node apps/api/entrypoint.sh ./
RUN chmod +x entrypoint.sh
EXPOSE 3004
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["node", "dist/main.js"]
```

---

## 2. Backend: Python / FastAPI

`apps/api/Dockerfile`:
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
RUN apt-get update && apt-get install -y --no-install-recommends libpq5 curl && rm -rf /var/lib/apt/lists/*
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

FROM base AS development
COPY --chown=appuser:appgroup apps/api ./apps/api
USER appuser
EXPOSE 3004
CMD ["uvicorn", "apps.api.main:app", "--host", "0.0.0.0", "--port", "3004", "--reload"]

FROM base AS production
COPY --chown=appuser:appgroup apps/api ./apps/api
USER appuser
EXPOSE 3004
CMD ["uvicorn", "apps.api.main:app", "--host", "0.0.0.0", "--port", "3004", "--workers", "4"]
```

---

## 3. Frontend: SPA (Vite / React / Expo Web)

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

FROM nginx:alpine AS production
COPY --from=build /app/apps/web/dist /usr/share/nginx/html
COPY apps/web/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

`apps/web/nginx.conf`:
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

## 4. Frontend: SSR (Next.js Standalone)

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

FROM node:22-alpine AS production
WORKDIR /app
ENV NODE_ENV=production PORT=8084
USER node
COPY --chown=node:node --from=build /app/apps/web/.next/standalone ./
COPY --chown=node:node --from=build /app/apps/web/.next/static ./apps/web/.next/static
COPY --chown=node:node --from=build /app/apps/web/public ./apps/web/public
EXPOSE 8084
CMD ["node", "apps/web/server.js"]
```
---

## 5. Trampas de Build Verificadas en Producción

### 5.1 Los scripts de mantenimiento no van en el build

**Regla genérica:** el build de producción compila **sólo** el directorio fuente de la aplicación.
Los scripts de mantenimiento (seeders, exportadores, generadores) viven fuera y se excluyen en
bloque —por directorio, nunca archivo por archivo—, porque el próximo que se agregue no va a estar
en la lista.

> **No contradice la compilación del seeder de §1.** Ahí el seeder se compila con una invocación
> `tsc` **propia**, con su propio `outDir`: eso es correcto y deliberado. La regla habla del build
> de la aplicación (`tsconfig.build.json` / `nest build`), donde un archivo de más mueve la raíz de
> salida de todo lo demás.

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

> Se detecta sólo levantando la imagen de producción. Ni el type-check ni los tests lo ven, y el
> despliegue conserva el contenedor anterior hasta que el nuevo levanta — así que puede pasar
> semanas sin notarse.

### 5.2 La imagen final debe traer todo lo que el entrypoint necesita

Si el entrypoint corre migraciones o un seeder, sus binarios tienen que estar **dentro** de la
imagen. Si no, se descargan en cada arranque y el contenedor depende de la red para levantar —y
falla en silencio cuando no hay.

```bash
# Verificación tras construir la imagen de producción:
docker run --rm --entrypoint sh <imagen> -c 'ls node_modules/.bin | grep -E "prisma|tsx|alembic"'
```
