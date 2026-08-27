# Cloudflare Zero Trust Access & Advanced Ingress Runbook

---

## 1. Zero Trust Access Protection for Admin / API Docs

To protect sensitive paths like Swagger UI (`/docs`, `/api/docs`) or Prisma Studio without opening them to the general public:

### A. Create an Access Application in Cloudflare One
1. Go to **Cloudflare Zero Trust Dashboard** > **Access** > **Applications**.
2. Click **Add an Application** > **Self-hosted**.
3. Application Name: `Backend API Documentation`.
4. Domain / Path: `api.tudominio.com/docs*` (or `/api/docs*`).
5. Policy:
   - Action: `Allow`
   - Rules: `Include Emails ending in @yourcompany.com` or `Specific Email List`.
   - Identity Providers: GitHub OAuth, Google Workspace, or One-Time PIN.

---

## 2. Machine-to-Machine Communication via Service Tokens

When GitHub Actions or external automated monitors need to bypass Zero Trust authentication:

### A. Generate Service Token
1. In Zero Trust Dashboard > **Access** > **Service Auth**.
2. Click **Create Service Token** (Name: `github-actions-ci`).
3. Save `CF-Access-Client-Id` and `CF-Access-Client-Secret` in GitHub Repository Secrets.

### B. Use in Automated API Health Checks / CI
```bash
curl -X GET https://api.tudominio.com/health \
  -H "CF-Access-Client-Id: ${{ secrets.CF_ACCESS_CLIENT_ID }}" \
  -H "CF-Access-Client-Secret: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}"
```

---

## 3. Advanced Ingress Multi-Service Routing (`config.yml`)

When running multiple containerized services on the same Raspberry Pi server behind a single Cloudflare Tunnel:

```yaml
tunnel: TU_TUNNEL_ID
credentials-file: /root/.cloudflared/TU_TUNNEL_ID.json

ingress:
  # Public REST API
  - hostname: api.tudominio.com
    service: http://backend:3004
    originRequest:
      connectTimeout: 30s
      noTLSVerify: true

  # Webhook Ingress (with custom path bypass)
  - hostname: webhooks.tudominio.com
    service: http://backend:3004
    originRequest:
      httpHostHeader: api.tudominio.com

  # Secure Remote PostgreSQL (TCP over WebSocket)
  - hostname: db.tudominio.com
    service: tcp://database:5432

  # Fallback rule (mandatory)
  - service: http_status:404
```

---

## 4. Secure Remote Database Connection via Tunnel

To connect to your PostgreSQL database running on Raspberry Pi from your local machine (e.g. pgAdmin, DBeaver, Prisma CLI) without exposing port 5432 to the internet:

### On your Local Machine:
```bash
# Run local proxy to route localhost:5433 to the remote tunnel
cloudflared access tcp --hostname db.tudominio.com --url 127.0.0.1:5433
```

### In your Local Database Client:
- **Host**: `127.0.0.1`
- **Port**: `5433`
- **User**: `postgres`
- **Password**: `tu_password_seguro`
- **Database**: `app`
