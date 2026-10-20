# Workspace Tooling & Package Orchestration (pnpm + Turborepo)

> [!NOTE]
> **No impongas la herramienta.** Un monorepo con npm y scripts de orquestación en el
> `package.json` raíz cumple el estándar igual que uno con pnpm + Turborepo. Migrar a pnpm/Turbo
> sin que nadie lo haya pedido es ruido, no cumplimiento: aplicá esta referencia sólo si el
> proyecto ya usa esas herramientas o si el volumen de paquetes lo justifica.

---

## 1. Root `package.json`

```json
{
  "name": "fullstack-monorepo",
  "private": true,
  "packageManager": "pnpm@9.15.4",
  "scripts": {
    "dev": "turbo run dev",
    "build": "turbo run build",
    "lint": "turbo run lint",
    "test": "turbo run test",
    "clean": "turbo run clean && rm -rf node_modules"
  },
  "devDependencies": {
    "turbo": "^2.3.3",
    "typescript": "^5.7.3",
    "prettier": "^3.4.2"
  }
}
```

---

### 1.1 Sin Turbo, con npm: el `package.json` raíz mínimo

Un repo con npm (con o sin `workspaces`) y sin Turborepo cumple el estándar con scripts de orquestación
de Docker en el `package.json` raíz; no hace falta migrar nada (Fase 1 de la skill):

```json
{
  "name": "mi-proyecto",
  "private": true,
  "scripts": {
    "docker:dev": "docker compose up -d",
    "docker:prod": "docker compose -f docker-compose.prod.yml up -d --build --force-recreate --remove-orphans",
    "docker:down": "docker compose down",
    "docker:logs": "docker compose logs -f backend"
  }
}
```

Si el repo ya tiene `package.json` en la raíz, solo se suman los cuatro `docker:*`. Con `workspaces` se
agrega `"workspaces": ["apps/*", "packages/*"]` y, si hay un solo `package-lock.json`, ese es el que manda
([`dockerfile-recipes.md`](./dockerfile-recipes.md) §2b). `docker:down` es **solo para desarrollo**:
en el servidor, `down` sin `-f docker-compose.prod.yml` actúa sobre lo que Compose cree que es el proyecto.
Sin Docker (perfil B) estos scripts no van.

---

## 2. `pnpm-workspace.yaml`

```yaml
packages:
  - "apps/*"
  - "packages/*"
```

---

## 3. `turbo.json`

```json
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**", ".next/**", "!.next/cache/**"]
    },
    "lint": {
      "dependsOn": ["^build"]
    },
    "test": {
      "dependsOn": ["^build"],
      "outputs": ["coverage/**"]
    },
    "dev": {
      "cache": false,
      "persistent": true
    }
  }
}
```

---

## 4. Shared Packages

### `packages/types/package.json`
```json
{
  "name": "@repo/types",
  "version": "0.0.0",
  "private": true,
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "scripts": {
    "type-check": "tsc --noEmit"
  }
}
```

### Consuming Shared Packages in `apps/api` or `apps/web`
In `apps/api/package.json` or `apps/web/package.json`:
```json
{
  "dependencies": {
    "@repo/types": "workspace:*"
  }
}
```
