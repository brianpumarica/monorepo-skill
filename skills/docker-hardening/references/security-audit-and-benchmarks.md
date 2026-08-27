# Docker Security Audit & Production Hardening Benchmarks

---

## 1. CIS Benchmark Compliance Checklist for Linux & Raspberry Pi

Ensure your container runtime meets key CIS Docker Benchmark standards:

| Benchmark | Rule | Implementation in `docker-compose.prod.yml` |
| :--- | :--- | :--- |
| **CIS 4.1** | Non-root container user | `USER node` / `USER appuser` in Dockerfile |
| **CIS 5.1** | Disable AppArmor / Seccomp unconfined | Keep default Docker Seccomp profile enabled |
| **CIS 5.2** | Drop default kernel capabilities | `cap_drop: [ALL]`, only add back required (e.g. `NET_BIND_SERVICE`) |
| **CIS 5.3** | Prevent privilege escalation | `security_opt: [no-new-privileges:true]` |
| **CIS 5.10** | Limit container memory | `deploy.resources.limits.memory: 512M` |
| **CIS 5.11** | Limit CPU usage | `deploy.resources.limits.cpus: '2.0'` |
| **CIS 5.12** | Read-only root filesystem (where possible) | `read_only: true` with tmpfs for `/tmp` |
| **CIS 5.25** | Limit container restart attempts | `restart: on-failure:5` or `unless-stopped` |

---

## 2. Kernel Limits & Sysctls Tuning (Host Level)

On Linux/Raspberry Pi host (`/etc/sysctl.d/99-docker-security.conf`):

```ini
# Prevent SYN flood DoS
net.ipv4.tcp_syncookies = 1

# Disable IP source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Disable ICMP redirect acceptance
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# Enable file descriptor capacity for Node/Python servers
fs.file-max = 2097152
```

Apply with:
```bash
sudo sysctl --system
```

---

## 3. Automated Docker Security Scan Commands

### Scan Running Containers for Vulnerabilities:
```bash
# Check running container capabilities
docker inspect --format '{{json .HostConfig.CapDrop}}' <container-name>

# Verify non-root user ID
docker inspect --format '{{.Config.User}}' <container-name>

# Inspect memory limits
docker stats --no-stream
```

### Build-Time Image Vulnerability Scanning with Trivy:
```bash
# Scan production image
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy image --severity HIGH,CRITICAL <image-name>:production
```
