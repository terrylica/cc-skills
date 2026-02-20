---
name: firecrawl-self-hosted
description: Self-hosted Firecrawl deployment, troubleshooting, and best practices. TRIGGERS - firecrawl, self-hosted scraping, web scrape, scraper wrapper, littleblack, ZeroTier scraping.
allowed-tools: Bash, Read
---

# Firecrawl Self-Hosted Operations

Self-hosted Firecrawl deployment, troubleshooting, and best practices.

**Host**: littleblack (172.25.236.1) via ZeroTier
**Source**: <https://github.com/mendableai/firecrawl>

## When to Use This Skill

Use this skill when:

- Scraping JavaScript-heavy web pages that WebFetch cannot handle
- Extracting content from Gemini/ChatGPT share links
- Operating the self-hosted Firecrawl instance on littleblack
- Troubleshooting Docker container or ZeroTier connectivity issues
- Setting up new Firecrawl deployments with proper restart policies

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    LittleBlack (172.25.236.1)                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │   Client     │───▶│ Scraper      │───▶│ Firecrawl    │      │
│  │   (curl)     │    │ Wrapper :3003│    │ API :3002    │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│         │                   │                   │               │
│         │                   │                   ▼               │
│         │                   │            ┌──────────────┐       │
│         │                   │            │ Playwright   │       │
│         │                   │            │ Service      │       │
│         │                   │            └──────────────┘       │
│         │                   │                   │               │
│         │                   ▼                   ▼               │
│         │            ┌──────────────┐    ┌──────────────┐       │
│         │            │ Caddy :8080  │    │ Redis        │       │
│         │            │ (files)      │    │ RabbitMQ     │       │
│         ▼            └──────────────┘    └──────────────┘       │
│  ┌──────────────┐                                               │
│  │ Output URL   │◀── http://172.25.236.1:8080/NAME-TS.md       │
│  └──────────────┘                                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Quick Reference

| Port | Service         | Type   | Purpose                    |
| ---- | --------------- | ------ | -------------------------- |
| 3002 | Firecrawl API   | Docker | Core scraping engine       |
| 3003 | Scraper Wrapper | Bun    | Saves to file, returns URL |
| 8080 | Caddy           | Binary | Serves saved markdown      |

---

## Usage

### Recommended: Wrapper Endpoint

```bash
curl "http://172.25.236.1:3003/scrape?url=URL&name=NAME"
```

Returns:

```json
{
  "url": "http://172.25.236.1:8080/NAME-TIMESTAMP.md",
  "file": "NAME-TIMESTAMP.md"
}
```

### Direct API (Advanced)

```bash
curl -s -X POST http://172.25.236.1:3002/v1/scrape \
  -H "Content-Type: application/json" \
  -d '{"url":"URL","formats":["markdown"],"waitFor":5000}' \
  | jq -r '.data.markdown'
```

---

## Health Checks

### Quick Status

```bash
# All containers running?
ssh littleblack 'docker ps --filter "name=firecrawl" --format "{{.Names}}: {{.Status}}"'

# API responding?
ssh littleblack 'curl -s -o /dev/null -w "%{http_code}" http://localhost:3002/v1/scrape'
# Expected: 401 (no payload) or 200 (with payload)

# Wrapper responding?
curl -s -o /dev/null -w "%{http_code}" "http://172.25.236.1:3003/health"
```

### Detailed Status

```bash
# systemd services
ssh littleblack "systemctl --user status firecrawl firecrawl-scraper caddy-firecrawl"

# Docker container details
ssh littleblack 'docker ps -a --filter "name=firecrawl" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'

# Logs (live)
ssh littleblack "journalctl --user -u firecrawl -u firecrawl-scraper -u caddy-firecrawl -f"
```

---

## Troubleshooting

### Symptom: API Container Stopped

**Root Cause**: Docker restart policy was `no` (default). Container received SIGINT and didn't restart.

**Diagnosis**:

```bash
# Check container status
ssh littleblack 'docker ps -a --filter "name=firecrawl"'

# Check restart policy
ssh littleblack 'docker inspect --format "{{.Name}}: {{.HostConfig.RestartPolicy.Name}}" $(docker ps -a --filter "name=firecrawl" -q)'
```

**Fix**: Add `restart: unless-stopped` to ALL services in `docker-compose.yaml`:

```yaml
# ~/firecrawl/docker-compose.yaml
x-common-service: &common-service
  networks:
    - backend
  restart: unless-stopped # CRITICAL: Add this line
  logging:
    driver: "json-file"
    options:
      max-size: "1G"
      max-file: "4"

services:
  playwright-service:
    <<: *common-service
    # ... rest of config

  api:
    <<: *common-service
    # ... rest of config

  redis:
    <<: *common-service
    # ... rest of config

  rabbitmq:
    <<: *common-service
    # ... rest of config
```

**Apply Fix**:

```bash
ssh littleblack 'cd ~/firecrawl && docker compose up -d --force-recreate'
```

**Verify**:

```bash
ssh littleblack 'docker inspect --format "{{.Name}}: RestartPolicy={{.HostConfig.RestartPolicy.Name}}" $(docker ps -a --filter "name=firecrawl" -q)'
# All should show: RestartPolicy=unless-stopped
```

### Symptom: Scraper Wrapper Not Responding

**Diagnosis**:

```bash
ssh littleblack "systemctl --user status firecrawl-scraper"
```

**Fix**:

```bash
ssh littleblack "systemctl --user restart firecrawl-scraper"
```

### Symptom: Caddy File Server Down

**Diagnosis**:

```bash
ssh littleblack "systemctl --user status caddy-firecrawl"
curl -I http://172.25.236.1:8080/
```

**Fix**:

```bash
ssh littleblack "systemctl --user restart caddy-firecrawl"
```

### Symptom: ZeroTier Unreachable

**Diagnosis**:

```bash
# From local machine
ping 172.25.236.1

# Check ZeroTier status
zerotier-cli listnetworks
```

**Fix**: Re-authorize device in ZeroTier Central if needed.

---

## Bootstrap: Fresh Installation

### Prerequisites

- Debian/Ubuntu server with Docker
- ZeroTier network membership
- Domain or static IP (optional, for public access)

### Step 1: Clone Repository

```bash
cd ~
git clone https://github.com/mendableai/firecrawl.git
cd firecrawl
```

### Step 2: Configure docker-compose.yaml

**CRITICAL**: Add restart policy to prevent shutdown on signals:

```yaml
x-common-service: &common-service
  networks:
    - backend
  restart: unless-stopped # <-- ADD THIS
  logging:
    driver: "json-file"
    options:
      max-size: "1G"
      max-file: "4"
```

Apply to all services using the anchor:

```yaml
services:
  api:
    <<: *common-service
    # ...
  playwright-service:
    <<: *common-service
    # ...
  redis:
    <<: *common-service
    # ...
  rabbitmq:
    <<: *common-service
    # ...
```

### Step 3: Environment Variables

Create `.env` from template:

```bash
cp .env.example .env
```

Minimal required settings:

```bash
# .env
NUM_WORKERS_PER_QUEUE=2
PORT=3002
HOST=0.0.0.0
REDIS_URL=redis://redis:6379
REDIS_RATE_LIMIT_URL=redis://redis:6379
```

### Step 4: Start Services

```bash
docker compose up -d
```

### Step 5: Verify Restart Policies

```bash
docker inspect --format "{{.Name}}: RestartPolicy={{.HostConfig.RestartPolicy.Name}}" \
  $(docker ps -a --filter "name=firecrawl" -q)
```

All should show `unless-stopped`.

### Step 6: Optional - Scraper Wrapper

Create `~/firecrawl-scraper.ts`:

```typescript
import { serve } from "bun";
import { $ } from "bun";

const FIRECRAWL_API = "http://localhost:3002";
const OUTPUT_DIR = "/home/kab/firecrawl-output";

serve({
  port: 3003,
  async fetch(req) {
    const url = new URL(req.url);

    if (url.pathname === "/health") {
      return new Response("OK", { status: 200 });
    }

    if (url.pathname === "/scrape") {
      const targetUrl = url.searchParams.get("url");
      const name = url.searchParams.get("name") || "scraped";

      if (!targetUrl) {
        return Response.json(
          { error: "url parameter required" },
          { status: 400 },
        );
      }

      const response = await fetch(`${FIRECRAWL_API}/v1/scrape`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          url: targetUrl,
          formats: ["markdown"],
          waitFor: 5000,
        }),
      });

      const data = await response.json();
      const markdown = data?.data?.markdown;

      if (!markdown) {
        return Response.json(
          { error: "No markdown returned" },
          { status: 500 },
        );
      }

      const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
      const filename = `${name}-${timestamp}.md`;
      const filepath = `${OUTPUT_DIR}/${filename}`;

      await Bun.write(filepath, markdown);

      return Response.json({
        url: `http://172.25.236.1:8080/${filename}`,
        file: filename,
      });
    }

    return new Response("Not Found", { status: 404 });
  },
});
```

Create systemd user service `~/.config/systemd/user/firecrawl-scraper.service`:

```ini
[Unit]
Description=Firecrawl Scraper Wrapper
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/kab
ExecStart=/home/kab/.bun/bin/bun run firecrawl-scraper.ts
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

Enable:

```bash
systemctl --user daemon-reload
systemctl --user enable --now firecrawl-scraper
```

### Step 7: Optional - Caddy File Server

Download Caddy from [GitHub releases](https://github.com/caddyserver/caddy/releases) (latest version).

```bash
# Download and extract (check releases for current version)
wget https://github.com/caddyserver/caddy/releases/download/v<version>/caddy_<version>_linux_amd64.tar.gz  # SSoT-OK
tar xzf caddy_*.tar.gz
chmod +x caddy
```

Create systemd user service `~/.config/systemd/user/caddy-firecrawl.service`:

```ini
[Unit]
Description=Caddy Firecrawl File Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/kab
ExecStart=/home/kab/caddy file-server --root /home/kab/firecrawl-output --listen :8080 --browse
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

Enable:

```bash
systemctl --user daemon-reload
systemctl --user enable --now caddy-firecrawl
```

---

## Best Practices (Empirically Verified)

### 1. Always Use `restart: unless-stopped`

Docker default is `no` restart policy. Containers WILL stop on SIGINT/SIGTERM and not recover.

**Anti-pattern**:

```yaml
services:
  api:
    image: firecrawl/api
    # Missing restart policy = container dies and stays dead
```

**Correct**:

```yaml
services:
  api:
    image: firecrawl/api
    restart: unless-stopped # Auto-restart on crash or signal
```

### 2. Use YAML Anchors for Consistency

Don't repeat `restart: unless-stopped` for each service. Use anchors:

```yaml
x-common-service: &common-service
  restart: unless-stopped
  logging:
    driver: "json-file"
    options:
      max-size: "1G"
      max-file: "4"

services:
  api:
    <<: *common-service
    # ...
```

### 3. Verify After docker compose up

ALWAYS verify restart policies after `docker compose up -d`:

```bash
docker inspect --format "{{.Name}}: {{.HostConfig.RestartPolicy.Name}}" \
  $(docker ps -a --filter "name=firecrawl" -q)
```

### 4. Use systemd for Non-Docker Services

For Bun scripts and Caddy, use systemd with `Restart=always`:

```ini
[Service]
Restart=always
RestartSec=5
```

### 5. Monitor with Health Checks

Add periodic health check to catch silent failures:

```bash
# Add to crontab
*/5 * * * * curl -sf http://localhost:3002/health || systemctl --user restart firecrawl
```

---

## Files Reference

| Path on LittleBlack               | Purpose                           |
| --------------------------------- | --------------------------------- |
| `~/firecrawl/`                    | Firecrawl Docker deployment       |
| `~/firecrawl/docker-compose.yaml` | Docker orchestration (EDIT THIS)  |
| `~/firecrawl/.env`                | Environment configuration         |
| `~/firecrawl-scraper.ts`          | Bun wrapper script                |
| `~/firecrawl-output/`             | Saved markdown files (Caddy root) |
| `~/caddy`                         | Caddy binary                      |
| `~/.config/systemd/user/`         | User systemd services             |

---

## Recovery Commands Cheatsheet

```bash
# Full restart (all services)
ssh littleblack 'cd ~/firecrawl && docker compose restart'
ssh littleblack 'systemctl --user restart firecrawl-scraper caddy-firecrawl'

# Check everything
ssh littleblack 'docker ps --filter "name=firecrawl" && systemctl --user status firecrawl-scraper caddy-firecrawl --no-pager'

# Logs (last 100 lines)
ssh littleblack 'docker logs firecrawl-api-1 --tail 100'
ssh littleblack 'journalctl --user -u firecrawl-scraper --no-pager -n 100'

# Force recreate with new config
ssh littleblack 'cd ~/firecrawl && docker compose up -d --force-recreate'

# Verify restart policies
ssh littleblack 'docker inspect --format "{{.Name}}: RestartPolicy={{.HostConfig.RestartPolicy.Name}}" $(docker ps -a --filter "name=firecrawl" -q)'
```

---

## Related Documentation

- [Firecrawl Official Docs](https://docs.firecrawl.dev/) - API reference
- [Docker Compose Restart](https://docs.docker.com/compose/compose-file/05-services/#restart) - Policy options
