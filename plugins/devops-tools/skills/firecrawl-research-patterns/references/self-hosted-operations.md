# Firecrawl Self-Hosted Operations

Deployment, health checks, recovery, and best practices for the self-hosted Firecrawl instance.

**Host**: littleblack (172.25.236.1) via ZeroTier
**Source**: <https://github.com/mendableai/firecrawl>

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

## Quick Reference

| Port | Service         | Type   | Purpose                    |
| ---- | --------------- | ------ | -------------------------- |
| 3002 | Firecrawl API   | Docker | Core scraping engine       |
| 3003 | Scraper Wrapper | Bun    | Saves to file, returns URL |
| 8080 | Caddy           | Binary | Serves saved markdown      |

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

## Related Guides

- [Self-Hosted Bootstrap Guide](./self-hosted-bootstrap-guide.md) — 7-step fresh installation
- [Self-Hosted Best Practices](./self-hosted-best-practices.md) — Docker restart policies, health monitoring
- [Self-Hosted Troubleshooting](./self-hosted-troubleshooting.md) — Symptom-based diagnosis and recovery

## External References

- [Firecrawl Official Docs](https://docs.firecrawl.dev/) - API reference
- [Docker Compose Restart](https://docs.docker.com/compose/compose-file/05-services/#restart) - Policy options
