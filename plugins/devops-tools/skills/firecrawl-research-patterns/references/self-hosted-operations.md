# Firecrawl Self-Hosted Operations

Deployment, health checks, recovery, and best practices for the self-hosted Firecrawl instance.

**Host**: small-host (Tailscale: `<host>`, legacy ZeroTier: `172.25.236.1`). All 5 containers up 5+ weeks, stable.
**Source**: <https://github.com/mendableai/firecrawl>

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    small-host (Tailscale)                   │
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
│  │ Output URL   │◀── http://small-host:8080/NAME-TS.md       │
│  └──────────────┘                                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Reference

| Port | Service           | Type   | Purpose                                            |
| ---- | ----------------- | ------ | -------------------------------------------------- |
| 3002 | Firecrawl API     | Docker | Core scraping engine (direct API)                  |
| 3003 | Scraper Wrapper   | Bun    | JS-rendered SPAs, saves to file, returns Caddy URL |
| 3004 | Cloudflare Bypass | Bun    | curl-impersonate for Cloudflare-protected sites    |
| 8080 | Caddy             | Binary | Serves saved markdown from firecrawl-output/       |

### When to Use Which Port

| Target                 | Port | Reason                                        |
| ---------------------- | ---- | --------------------------------------------- |
| arXiv / standard pages | 3003 | Playwright JS rendering, preserves image URLs |
| Claude artifacts       | 3004 | Cloudflare blocks Playwright                  |
| Gemini/ChatGPT shares  | 3003 | Needs JS rendering (SPA)                      |
| Other Cloudflare sites | 3004 | If 3003 gets a Cloudflare challenge           |

## Usage

### Recommended: Wrapper Endpoint (port 3003)

```bash
curl "http://small-host:3003/scrape?url=URL&name=NAME"
```

Returns:

```json
{
  "url": "http://small-host:8080/NAME-TIMESTAMP.md",
  "file": "NAME-TIMESTAMP.md"
}
```

### Direct API (Advanced)

```bash
curl -s -X POST http://small-host:3002/v1/scrape \
  -H "Content-Type: application/json" \
  -d '{"url":"URL","formats":["markdown"],"waitFor":5000}' \
  | jq -r '.data.markdown'
```

## Health Checks

### Quick Status

```bash
# All containers running?
ssh small-host 'docker ps --filter "name=firecrawl" --format "{{.Names}}: {{.Status}}"'

# API responding?
ssh small-host 'curl -s -o /dev/null -w "%{http_code}" http://localhost:3002/v1/scrape'
# Expected: 401 (no payload) or 200 (with payload)

# Wrapper responding?
curl -s -o /dev/null -w "%{http_code}" "http://small-host:3003/health"
```

### Detailed Status

```bash
# systemd services (services run under kab user, not yca SSH user)
ssh small-host "sudo systemctl --user -M kab@ status firecrawl-scraper caddy-firecrawl"

# Docker container details
ssh small-host 'docker ps -a --filter "name=firecrawl" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'

# Logs (live)
ssh small-host "sudo journalctl --user -M kab@ -u firecrawl-scraper -u caddy-firecrawl -f"
```

**Note**: Firecrawl services run under the `kab` user on small-host. The SSH user is `yca`. Always use `sudo systemctl --user -M kab@` — plain `systemctl --user` targets the SSH user and sees no services.

## Recovery Commands Cheatsheet

```bash
# Full restart (all services)
ssh small-host 'cd ~/firecrawl && docker compose restart'
ssh small-host 'sudo systemctl --user -M kab@ restart firecrawl-scraper caddy-firecrawl'

# Check everything
ssh small-host 'docker ps --filter "name=firecrawl" && sudo systemctl --user -M kab@ status firecrawl-scraper caddy-firecrawl --no-pager'

# Logs (last 100 lines)
ssh small-host 'docker logs firecrawl-api-1 --tail 100'
ssh small-host 'sudo journalctl --user -M kab@ -u firecrawl-scraper --no-pager -n 100'

# Force recreate with new config
ssh small-host 'cd ~/firecrawl && docker compose up -d --force-recreate'

# Verify restart policies
ssh small-host 'docker inspect --format "{{.Name}}: RestartPolicy={{.HostConfig.RestartPolicy.Name}}" $(docker ps -a --filter "name=firecrawl" -q)'
```

## Cloudflare Bypass (Port 3004)

For sites that block Playwright-based scraping (Cloudflare challenge pages), use the curl-impersonate bypass service:

```bash
curl "http://small-host:3004/scrape-cf?url=URL&name=NAME"
```

This uses `curl-impersonate` to mimic a real browser TLS fingerprint, bypassing Cloudflare's bot detection. Use when port 3003 returns a Cloudflare challenge instead of page content.

## Files Reference

| Path on gpu-host                  | Purpose                           |
| --------------------------------- | --------------------------------- |
| `~/firecrawl/`                    | Firecrawl Docker deployment       |
| `~/firecrawl/docker-compose.yaml` | Docker orchestration (EDIT THIS)  |
| `~/firecrawl/.env`                | Environment configuration         |
| `~/firecrawl-scraper.ts`          | Bun wrapper script                |
| `~/firecrawl-output/`             | Saved markdown files (Caddy root) |
| `~/caddy`                         | Caddy binary                      |
| `~/.config/systemd/user/`         | User systemd services             |

## Related Guides

- [Self-Hosted Bootstrap Guide](./self-hosted-bootstrap-guide.md) — 7-step fresh installation
- [Self-Hosted Best Practices](./self-hosted-best-practices.md) — Docker restart policies, health monitoring
- [Self-Hosted Troubleshooting](./self-hosted-troubleshooting.md) — Symptom-based diagnosis and recovery

## External References

- [Firecrawl Official Docs](https://docs.firecrawl.dev/) - API reference
- [Docker Compose Restart](https://docs.docker.com/compose/compose-file/05-services/#restart) - Policy options
