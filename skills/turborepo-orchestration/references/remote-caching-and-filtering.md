# Turborepo Remote Caching & Advanced Task Filtering

---

## 1. Remote Caching with Vercel in GitHub Actions

Turborepo can share build caches across your team and CI/CD pipelines to dramatically cut deployment times:

### A. Link Turborepo to Vercel Remote Cache
```bash
# Authenticate and link locally:
npx turbo login
npx turbo link
```

### B. Configure in GitHub Actions (`.github/workflows/deploy.yml`)
Add `TURBO_TOKEN` and `TURBO_TEAM` secrets:

```yaml
- name: Run Cached Build
  run: pnpm turbo run build
  env:
    TURBO_TOKEN: ${{ secrets.TURBO_TOKEN }}
    TURBO_TEAM: ${{ secrets.TURBO_TEAM }}
```

---

## 2. Advanced Task Filtering Cheat Sheet

| Goal | Command |
| :--- | :--- |
| **Build app and all internal dependencies** | `pnpm turbo run build --filter=web...` |
| **Build only packages changed in current branch against main** | `pnpm turbo run build --filter=...[origin/main]` |
| **Run tests only in packages that changed** | `pnpm turbo run test --filter=...[HEAD~1]` |
| **Exclude specific package from task** | `pnpm turbo run lint --filter=!@repo/docs` |
| **Run command directly in specific workspace package** | `pnpm --filter @repo/types typecheck` |

---

## 3. Optimizing `turbo.json` Task Dependency Graphs

```json
{
  "$schema": "https://turbo.build/schema.json",
  "globalDependencies": [".env", ".env.local"],
  "globalEnv": ["NODE_ENV", "PORT", "DATABASE_URL", "NEXT_PUBLIC_API_URL"],
  "tasks": {
    "topo": {
      "dependsOn": ["^topo"]
    },
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**", ".next/**", "!.next/cache/**"]
    },
    "typecheck": {
      "dependsOn": ["^typecheck"],
      "outputs": []
    },
    "lint": {
      "dependsOn": ["^build"],
      "outputs": []
    },
    "dev": {
      "cache": false,
      "persistent": true
    }
  }
}
```
