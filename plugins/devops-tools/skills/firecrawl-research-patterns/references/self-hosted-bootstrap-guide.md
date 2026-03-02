# Firecrawl Bootstrap: Fresh Installation

## Prerequisites

- Debian/Ubuntu server with Docker
- ZeroTier network membership
- Domain or static IP (optional, for public access)

## Step 1: Clone Repository

```bash
cd ~
git clone https://github.com/mendableai/firecrawl.git
cd firecrawl
```

## Step 2: Configure docker-compose.yaml

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

## Step 3: Environment Variables

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

## Step 4: Start Services

```bash
docker compose up -d
```

## Step 5: Verify Restart Policies

```bash
docker inspect --format "{{.Name}}: RestartPolicy={{.HostConfig.RestartPolicy.Name}}" \
  $(docker ps -a --filter "name=firecrawl" -q)
```

All should show `unless-stopped`.

## Step 6: Optional - Scraper Wrapper

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

## Step 7: Optional - Caddy File Server

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
