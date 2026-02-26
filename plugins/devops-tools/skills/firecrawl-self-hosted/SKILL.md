---
name: firecrawl-self-hosted
description: Self-hosted Firecrawl deployment, troubleshooting, and best practices. TRIGGERS - firecrawl, self-hosted scraping, web scrape, scraper wrapper, small-host, ZeroTier scraping.
allowed-tools: Bash, Read
---

# Firecrawl Self-Hosted Operations

Self-hosted Firecrawl deployment, troubleshooting, and best practices.

**Host**: small-host (172.25.236.1) via ZeroTier
**Source**: <https://github.com/mendableai/firecrawl>

## When to Use This Skill

Use this skill when:

- Scraping JavaScript-heavy web pages that WebFetch cannot handle
- Extracting content from Gemini/ChatGPT share links
- Operating the self-hosted Firecrawl instance on small-host
- Troubleshooting Docker container or ZeroTier connectivity issues
- Setting up new Firecrawl deployments with proper restart policies

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    small-host (172.25.236.1)                   │
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
ssh small-host 'docker ps --filter "name=firecrawl" --format "{{.Names}}: {{.Status}}"'

# API responding?
ssh small-host 'curl -s -o /dev/null -w "%{http_code}" http://localhost:3002/v1/scrape'
# Expected: 401 (no payload) or 200 (with payload)

# Wrapper responding?
curl -s -o /dev/null -w "%{http_code}" "http://172.25.236.1:3003/health"
```

### Detailed Status

```bash
# systemd services
ssh small-host "systemctl --user status firecrawl firecrawl-scraper caddy-firecrawl"

# Docker container details
ssh small-host 'docker ps -a --filter "name=firecrawl" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'

# Logs (live)
ssh small-host "journalctl --user -u firecrawl -u firecrawl-scraper -u caddy-firecrawl -f"
```

---

## Troubleshooting

For detailed symptom-based troubleshooting (API container stopped, wrapper unresponsive, Caddy down, ZeroTier unreachable), see [Troubleshooting Guide](./references/troubleshooting.md).

---

## Bootstrap: Fresh Installation

Complete 7-step installation guide (clone, Docker config, env vars, systemd services, Caddy file server) is in [Bootstrap Guide](./references/bootstrap-guide.md).

---

## Best Practices

Empirically verified patterns for Docker restart policies, YAML anchors, systemd services, and health monitoring are in [Best Practices](./references/best-practices.md).

---

## Files Reference

| Path on small-host               | Purpose                           |
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
ssh small-host 'cd ~/firecrawl && docker compose restart'
ssh small-host 'systemctl --user restart firecrawl-scraper caddy-firecrawl'

# Check everything
ssh small-host 'docker ps --filter "name=firecrawl" && systemctl --user status firecrawl-scraper caddy-firecrawl --no-pager'

# Logs (last 100 lines)
ssh small-host 'docker logs firecrawl-api-1 --tail 100'
ssh small-host 'journalctl --user -u firecrawl-scraper --no-pager -n 100'

# Force recreate with new config
ssh small-host 'cd ~/firecrawl && docker compose up -d --force-recreate'

# Verify restart policies
ssh small-host 'docker inspect --format "{{.Name}}: RestartPolicy={{.HostConfig.RestartPolicy.Name}}" $(docker ps -a --filter "name=firecrawl" -q)'
```

---

## Related Documentation

- [Firecrawl Official Docs](https://docs.firecrawl.dev/) - API reference
- [Docker Compose Restart](https://docs.docker.com/compose/compose-file/05-services/#restart) - Policy options
