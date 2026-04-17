# Firecrawl Troubleshooting

## Symptom: API Container Stopped

**Root Cause**: Docker restart policy was `no` (default). Container received SIGINT and didn't restart.

**Diagnosis**:

```bash
# Check container status
ssh small-host 'docker ps -a --filter "name=firecrawl"'

# Check restart policy
ssh small-host 'docker inspect --format "{{.Name}}: {{.HostConfig.RestartPolicy.Name}}" $(docker ps -a --filter "name=firecrawl" -q)'
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
ssh small-host 'cd ~/firecrawl && docker compose up -d --force-recreate'
```

**Verify**:

```bash
ssh small-host 'docker inspect --format "{{.Name}}: RestartPolicy={{.HostConfig.RestartPolicy.Name}}" $(docker ps -a --filter "name=firecrawl" -q)'
# All should show: RestartPolicy=unless-stopped
```

## Symptom: Scraper Wrapper Not Responding

**Diagnosis**:

```bash
ssh small-host "systemctl --user status firecrawl-scraper"
```

**Fix**:

```bash
ssh small-host "systemctl --user restart firecrawl-scraper"
```

## Symptom: Caddy File Server Down

**Diagnosis**:

```bash
ssh small-host "systemctl --user status caddy-firecrawl"
curl -I http://small-host:8080/
```

**Fix**:

```bash
ssh small-host "systemctl --user restart caddy-firecrawl"
```

## Symptom: Tailscale Unreachable

**Diagnosis**:

```bash
# From local machine
tailscale ping small-host

# Check Tailscale status
tailscale status
```

**Fix**: Re-authorize device in Tailscale admin console if needed.
