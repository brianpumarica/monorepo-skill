---
name: vercel-monorepo-deploy
description: Best practices, configurations, and automation runbook for deploying monorepo frontends (Next.js, Vite SPAs, React) to Vercel. Covers turbo-ignore build skipping, client-side routing rewrites in vercel.json, monorepo root directory setup, remote API environment wiring with Cloudflare Tunnels, and build performance optimization. Use whenever configuring or debugging Vercel deployments from a pnpm/npm monorepo.
---

# Vercel Monorepo Frontend Deployment Runbook

This skill establishes the production standard for deploying frontend applications (`apps/web`) from a pnpm/Turbo monorepo to Vercel, connected to remote backends exposed via Cloudflare Tunnels or custom domains.

---

## 1. Project Configuration in Vercel Dashboard

When importing the monorepo Git repository into Vercel, set these project settings:

| Setting | Value | Why |
| :--- | :--- | :--- |
| **Framework Preset** | *Auto-detected* (Next.js / Vite / Create React App) | Correct build presets |
| **Root Directory** | `apps/web` *(or leave empty if using root build)* | Scopes build context |
| **Include source files outside Root Directory** | **Checked (Enabled)** | Allows Vercel to access `packages/types`, `packages/tsconfig` and root `pnpm-lock.yaml` |
| **Build Command** | `cd ../.. && pnpm turbo run build --filter=web...` (if root is `apps/web`) or override with `pnpm --filter=web build` | Builds dependencies first |
| **Output Directory** | `dist` (for Vite/SPA) or `.next` (for Next.js) | Standard build output |
| **Install Command** | `pnpm install` | Uses workspace root lockfile |

---

## 2. Preventing Unnecessary Builds (`turbo-ignore`)

To avoid wasting Vercel build minutes and prevent frontend deployments when only `apps/api` or `docker/` changes:

### In Vercel Project Settings > Git > Ignored Build Step:
Select **Custom** and enter:
```bash
npx turbo-ignore web
```

### How it works:
- `turbo-ignore` checks the commit diff against the monorepo dependency graph.
- If changes only affected `apps/api` or unrelated files, the build exits with code `0` (canceled) with zero cost.
- If changes touched `apps/web`, `packages/types`, or `packages/tsconfig`, Vercel proceeds with the deployment.

---

## 3. SPA Client-Side Routing (`vercel.json`)

For Single Page Applications (**Vite**, React Router, Vue Router, Svelte) to prevent 404 errors on browser page refreshes:

Create `apps/web/vercel.json`:
```json
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "rewrites": [
    {
      "source": "/(.*)",
      "destination": "/index.html"
    }
  ],
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        { "key": "X-Content-Type-Options", "value": "nosniff" },
        { "key": "X-Frame-Options", "value": "DENY" },
        { "key": "X-XSS-Protection", "value": "1; mode=block" }
      ]
    }
  ]
}
```

> [!NOTE]
> For **Next.js** applications, `vercel.json` is not required as Next.js handles server-side and client-side routing natively.

---

## 4. Environment Variables Wiring

Connect the Vercel frontend to the backend running on Raspberry Pi / Cloudflare Tunnel:

### For Vite SPAs:
In Vercel **Environment Variables**:
- `VITE_API_URL`: `https://api.tudominio.com` (Production)
- `VITE_API_URL`: `https://dev-api.tudominio.com` (Preview / Staging)

In Frontend Code:
```typescript
const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:3004';
export const apiClient = axios.create({ baseURL: API_URL, withCredentials: true });
```

### For Next.js:
In Vercel **Environment Variables**:
- `NEXT_PUBLIC_API_URL`: `https://api.tudominio.com`

In Frontend Code:
```typescript
const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3004';
```

---

## 5. Just-In-Time (JIT) Monorepo Package Transpilation

To consume shared packages (`@repo/types`, `@repo/ui`) directly without needing a separate compilation step (`tsup`/`tsc`) during Vercel builds:

### In Next.js (`apps/web/next.config.js`):
```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  transpilePackages: ['@repo/types'],
  output: 'standalone', // Needed for Docker, ignored safely by Vercel
};

module.exports = nextConfig;
```

### In Vite (`apps/web/vite.config.ts`):
```typescript
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@repo/types': path.resolve(__dirname, '../../packages/types/src'),
    },
  },
});
```

---

## 6. Deployment Checklist

- [ ] Vercel Root Directory set to `apps/web` with "Include files outside Root" checked.
- [ ] Ignored Build Step configured with `npx turbo-ignore web`.
- [ ] `vercel.json` created in `apps/web` (for Vite/SPA apps).
- [ ] `VITE_API_URL` or `NEXT_PUBLIC_API_URL` set to Cloudflare Tunnel domain.
- [ ] Backend CORS configured to accept `https://*.vercel.app` and custom domain.
