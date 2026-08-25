---
name: turborepo-orchestration
description: Advanced pipeline orchestration, caching strategies, and package management for Turborepo and pnpm workspaces. Covers turbo.json pipeline configuration, Just-In-Time (JIT) shared TypeScript packages without compile steps, turbo watch dev persistence, task filtering, and remote caching. Use whenever setting up, optimizing, or diagnosing monorepo build pipelines.
---

# Turborepo & Workspace Orchestration Runbook

This skill establishes the standard for high-speed builds, intelligent task caching, and internal package consumption using **Turborepo** and **pnpm workspaces**.

---

## 1. Golden `turbo.json` Configuration

Place this file at the monorepo root:

```json
{
  "$schema": "https://turbo.build/schema.json",
  "globalDependencies": [".env", ".env.local"],
  "globalEnv": ["NODE_ENV", "PORT", "DATABASE_URL"],
  "tasks": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**", ".next/**", "!.next/cache/**"]
    },
    "typecheck": {
      "dependsOn": ["^typecheck"],
      "outputs": []
    },
    "lint": {
      "dependsOn": ["^lint"],
      "outputs": []
    },
    "dev": {
      "cache": false,
      "persistent": true
    },
    "clean": {
      "cache": false
    }
  }
}
```

---

## 2. Just-In-Time (JIT) vs Compiled Packages

Avoid maintaining slow, intermediate compilation steps (`tsup` / `tsc -b`) for internal packages like `@repo/types` or `@repo/ui`.

### JIT Pattern (Recommended):
1. Write pure TypeScript in `packages/types/src/index.ts`.
2. Set package manifest without a build script:
   ```json
   // packages/types/package.json
   {
     "name": "@repo/types",
     "version": "0.0.1",
     "main": "./src/index.ts",
     "types": "./src/index.ts"
   }
   ```
3. In consuming apps:
   - **Next.js**: Add `transpilePackages: ['@repo/types']` in `next.config.js`.
   - **Vite**: Add alias `'@repo/types': path.resolve(__dirname, '../../packages/types/src')` in `vite.config.ts`.
   - **NestJS/Node**: Use `tsconfig.json` paths:
     ```json
     "paths": {
       "@repo/types": ["../../packages/types/src/index.ts"]
     }
     ```

---

## 3. Essential Turborepo Commands

| Goal | Command | Description |
| :--- | :--- | :--- |
| **Build all apps & packages** | `pnpm turbo run build` | Cached automatically |
| **Build only frontend & its dependencies** | `pnpm turbo run build --filter=web...` | Builds `@repo/types` then `web` |
| **Typecheck entire monorepo** | `pnpm turbo run typecheck` | Validates all TS files |
| **Run persistent dev mode** | `pnpm turbo run dev` | Runs web & api concurrently |
| **Clean all build artifacts** | `pnpm turbo run clean` | Removes `dist/`, `.next/`, `node_modules/.cache` |

---

## 4. Root `package.json` Standard Scripts

```json
{
  "name": "monorepo-root",
  "private": true,
  "scripts": {
    "build": "turbo run build",
    "dev": "docker compose up -d && turbo run dev",
    "dev:docker": "docker compose up -d",
    "lint": "turbo run lint",
    "typecheck": "turbo run typecheck",
    "format": "prettier --write \"**/*.{ts,tsx,md,json}\"",
    "clean": "turbo run clean && rm -rf node_modules"
  },
  "devDependencies": {
    "prettier": "^3.2.5",
    "turbo": "^2.0.0"
  },
  "packageManager": "pnpm@9.1.0"
}
```
