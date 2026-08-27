# Vercel Preview Deployments, Environment Matrix & Troubleshooting

---

## 1. Automated Branch Preview Deployments with Vercel CLI

To create unique preview URLs for Pull Requests from private organization monorepos without upgrading to Vercel Pro:

### GitHub Actions Workflow Step (`.github/workflows/preview.yml`):
```yaml
name: Preview Deployment
on:
  pull_request:
    branches:
      - main

jobs:
  deploy-preview:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup Node.js 22
        uses: actions/setup-node@v4
        with:
          node-version: 22

      - name: Install pnpm & Vercel CLI
        run: npm install --global pnpm@latest vercel@latest

      - name: Pull Vercel Environment (Preview)
        run: vercel pull --yes --environment=preview --token=${{ secrets.VERCEL_TOKEN }}
        env:
          VERCEL_ORG_ID: ${{ secrets.VERCEL_ORG_ID }}
          VERCEL_PROJECT_ID: ${{ secrets.VERCEL_PROJECT_ID }}

      - name: Build Project (Preview)
        run: vercel build --token=${{ secrets.VERCEL_TOKEN }}
        env:
          VERCEL_ORG_ID: ${{ secrets.VERCEL_ORG_ID }}
          VERCEL_PROJECT_ID: ${{ secrets.VERCEL_PROJECT_ID }}
          NEXT_PUBLIC_API_URL: ${{ secrets.PREVIEW_API_URL || secrets.NEXT_PUBLIC_API_URL }}

      - name: Deploy Preview to Vercel
        id: deploy
        run: |
          PREVIEW_URL=$(vercel deploy --prebuilt --token=${{ secrets.VERCEL_TOKEN }})
          echo "url=$PREVIEW_URL" >> $GITHUB_OUTPUT
        env:
          VERCEL_ORG_ID: ${{ secrets.VERCEL_ORG_ID }}
          VERCEL_PROJECT_ID: ${{ secrets.VERCEL_PROJECT_ID }}

      - name: Comment PR with Preview Link
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `🚀 **Vercel Preview Deployment Ready!**\n\n🔗 URL: ${process.env.PREVIEW_URL}`
            });
        env:
          PREVIEW_URL: ${{ steps.deploy.outputs.url }}
```

---

## 2. Monorepo Troubleshooting Matrix

| Symptom | Root Cause | Fix |
| :--- | :--- | :--- |
| **`404 Not Found` on API requests** | `NEXT_PUBLIC_API_URL` missing at build time | Pass `NEXT_PUBLIC_API_URL` in `vercel build` env block |
| **`404 Not Found` on SPA route refresh** | Missing SPA rewrite rule | Add `vercel.json` with `{"source": "/(.*)", "destination": "/index.html"}` |
| **`ENOENT apps/web/apps/web`** | `working-directory` duplicate | Run Vercel CLI from monorepo root |
| **`node:sqlite missing`** | Node.js < 22 used with pnpm 10 | Use `actions/setup-node@v4` with `node-version: 22` |
| **CORS errors in browser** | Backend origin header mismatch | Add `*.vercel.app` to backend `CORS_ALLOWED_ORIGINS` |
| **Build timeout on monorepo** | Cache miss on shared packages | Configure `turbo-ignore` and link Vercel Remote Cache |
