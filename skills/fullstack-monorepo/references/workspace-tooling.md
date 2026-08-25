# Workspace Tooling & Package Orchestration (pnpm + Turborepo)

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
