# Firecrawl Best Practices (Empirically Verified)

## 1. Always Use `restart: unless-stopped`

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

## 2. Use YAML Anchors for Consistency

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

## 3. Verify After docker compose up

ALWAYS verify restart policies after `docker compose up -d`:

```bash
docker inspect --format "{{.Name}}: {{.HostConfig.RestartPolicy.Name}}" \
  $(docker ps -a --filter "name=firecrawl" -q)
```

## 4. Use systemd for Non-Docker Services

For Bun scripts and Caddy, use systemd with `Restart=always`:

```ini
[Service]
Restart=always
RestartSec=5
```

## 5. Monitor with Health Checks

Add periodic health check to catch silent failures:

```bash
# Add to crontab
*/5 * * * * curl -sf http://localhost:3002/health || systemctl --user restart firecrawl
```
