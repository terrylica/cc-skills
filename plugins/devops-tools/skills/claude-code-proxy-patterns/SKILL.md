---
name: claude-code-proxy-patterns
description: >-
  Claude Code OAuth proxy patterns and anti-patterns for multi-provider model routing.
  TRIGGERS - proxy Claude Code, OAuth token Keychain, route Haiku to MiniMax,
  ANTHROPIC_BASE_URL, model routing proxy, claude-code-proxy, proxy-toggle,
  multi-provider setup, anthropic-beta oauth, proxy auth failure, go proxy,
  failover proxy, launchd proxy, proxy failover
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

<!-- # SSoT-OK: version references are documentation of binary analysis findings, not package versions -->

# Claude Code Proxy Patterns

Multi-provider proxy that routes Claude Code model tiers to different backends. Haiku to MiniMax (cost/speed), Sonnet/Opus to Anthropic (native OAuth passthrough). Includes Go binary proxy with launchd auto-restart and failover wrapper for resilience.

**Scope**: Local reverse proxy for Claude Code with OAuth subscription (Max plan). Routes based on model name in request body.

**Reference implementations**: 
- Python proxy: `$HOME/.claude/tools/claude-code-proxy/proxy.py` (port 3000)
- Go proxy: `/usr/local/bin/claude-proxy` (port 8082)
- Failover wrapper: `$HOME/eon/cc-skills/tools/claude-code-failover/main.go` (port 8083)

---

## When to Use This Skill

- Building or debugging a Claude Code multi-provider proxy
- Setting up `ANTHROPIC_BASE_URL` with OAuth subscription mode
- Integrating Anthropic-compatible providers (MiniMax, etc.)
- Diagnosing "OAuth not supported" or auth failures through a proxy
- Understanding how Claude Code stores and transmits OAuth tokens

**Do NOT use for**: Claude API key-only setups (no proxy needed), MCP server development, Claude Code hooks (operate at tool level, not API level), or corporate HTTPS proxy traversal.

---

## Architecture

```
Claude Code (OAuth/Max subscription)
    |
    |  ANTHROPIC_BASE_URL=http://127.0.0.1:8083 (failover wrapper)
    |  ANTHROPIC_API_KEY=proxy-managed
    v
+------------------------------------------+
| failover-proxy (:8083)                   |
| Go + cenkalti/backoff retry (3x)        |
+------------------------------------------+
    |                              |
    | primary fail                  | fallback
    v                              v
+-----------+              +------------------+
| Go proxy  |              | Python proxy     |
| (:8082)   |              | (:3000)         |
| launchd   |              | manual          |
+-----------+              +------------------+
    |                              |
    | model =                      | model =
    | claude-haiku-               | anything else
    | 4-5-20251001               | (sonnet, opus)
    v                              v
+-----------+              +------------------+
| MiniMax   |              | api.anthropic.com|
| M2.5      |              | (OAuth headers   |
| highspeed |              |  forwarded)      |
+-----------+              +------------------+
```

**Port Configuration**:
- `:8083` - Failover wrapper (entry point, tries Go → Python)
- `:8082` - Go proxy (primary, launchd-managed, auto-restart)
- `:3000` - Python proxy (fallback, manual start)

The failover wrapper uses `cenkalti/backoff/v4` for exponential backoff retry (500ms → 1s → 2s) before falling back.

The proxy reads the `model` field from each `/v1/messages` request body. If it matches the configured Haiku model ID, the request goes to MiniMax. Everything else falls through to real Anthropic with OAuth passthrough.

---

## Working Patterns

### WP-01: Keychain OAuth Token Reading

Read OAuth tokens from macOS Keychain where Claude Code stores them.

**Service**: `"Claude Code-credentials"` (note the space before the hyphen)
**Account**: Current username via `getpass.getuser()`

```python
import subprocess, json, getpass

result = subprocess.run(
    ["security", "find-generic-password",
     "-s", "Claude Code-credentials",
     "-a", getpass.getuser(), "-w"],
    capture_output=True, text=True, timeout=5, check=False,
)
if result.returncode == 0:
    data = json.loads(result.stdout.strip())
    oauth = data.get("claudeAiOauth")
```

See [references/oauth-internals.md](./references/oauth-internals.md) for the full deep dive.

### WP-02: Token JSON Structure

The Keychain stores a JSON envelope with the `claudeAiOauth` key.

```json
{
  "claudeAiOauth": {
    "accessToken": "eyJhbG...",
    "refreshToken": "rt_...",
    "expiresAt": 1740268800000,
    "subscriptionType": "claude_pro_2025"
  }
}
```

**Note**: `expiresAt` is in **milliseconds** (Unix epoch _ 1000). Compare with `time.time() _ 1000` or divide by 1000 for seconds.

### WP-03: OAuth Beta Header

The `anthropic-beta: oauth-2025-04-20` header is **required** for OAuth token authentication. Without it, Anthropic rejects the Bearer token.

**Critical**: APPEND to existing beta headers, do not replace them.

```python
# proxy.py:304-308
existing_beta = original_headers.get("anthropic-beta", "")
beta_parts = [b.strip() for b in existing_beta.split(",") if b.strip()] if existing_beta else []
if "oauth-2025-04-20" not in beta_parts:
    beta_parts.append("oauth-2025-04-20")
target_headers["anthropic-beta"] = ",".join(beta_parts)
```

### WP-04: ANTHROPIC_API_KEY=proxy-managed

Setting `ANTHROPIC_BASE_URL` alone is insufficient in OAuth mode. Claude Code must also see `ANTHROPIC_API_KEY` set to switch from OAuth-only mode to API-key mode, which then honors `ANTHROPIC_BASE_URL`.

```bash
# In .zshenv (managed by proxy-toggle)
export ANTHROPIC_BASE_URL="http://127.0.0.1:3000"
export ANTHROPIC_API_KEY="proxy-managed"
```

The value `"proxy-managed"` is a dummy sentinel. The proxy intercepts it (line 324) and never forwards it to providers.

### WP-05: OAuth Token Cache with TTL

Avoid repeated Keychain subprocess calls by caching the token for 5 minutes.

```python
# proxy.py:117-118
_oauth_cache: dict = {"token": None, "expires_at": 0.0, "fetched_at": 0.0}
_OAUTH_CACHE_TTL = 300  # Re-read from Keychain every 5 minutes
```

Cache invalidation triggers:

- TTL expired (5 minutes since last fetch)
- Token's `expiresAt` has passed
- Proxy restart

### WP-06: Auth Priority Chain

The proxy tries multiple auth sources in order for Anthropic-bound requests.

```
1. REAL_ANTHROPIC_API_KEY env var   -> x-api-key header (explicit config)
2. Keychain OAuth token             -> Authorization: Bearer + anthropic-beta
3. ~/.claude/.credentials.json      -> Authorization: Bearer (plaintext fallback)
4. Forward client Authorization     -> Pass through whatever Claude Code sent
5. No auth                          -> Will 401 (expected)
```

See `proxy.py:293-314` for the implementation.

### WP-07: count_tokens Endpoint Auth

The `/v1/messages/count_tokens` endpoint needs the same auth as `/v1/messages`. Claude Code calls this for preflight token counting. Missing auth here causes silent failures.

```python
# proxy.py:460 - dedicated endpoint handler
@app.post("/v1/messages/count_tokens")
async def proxy_count_tokens(request: Request):
    # Same auth logic as proxy_messages
    # Returns 501 for non-Anthropic providers (MiniMax doesn't support it)
```

### WP-08: Anthropic-Compatible Provider URLs

Third-party providers that support the Anthropic `/v1/messages` API format.

| Provider               | Base URL                           | Notes                                             |
| ---------------------- | ---------------------------------- | ------------------------------------------------- |
| MiniMax M2.5-highspeed | `https://api.minimax.io/anthropic` | Returns `base_resp` field, extra `thinking` block |

See [references/provider-compatibility.md](./references/provider-compatibility.md) for the full matrix.

### WP-09: Concurrency Semaphore

Per-provider rate limiting prevents overwhelming third-party APIs. No semaphore for Anthropic (they handle their own rate limiting).

```python
# proxy.py:207-209
MAX_CONCURRENT_REQUESTS = int(os.getenv("MAX_CONCURRENT_REQUESTS", "5"))
haiku_semaphore = asyncio.Semaphore(MAX_CONCURRENT_REQUESTS)
opus_semaphore = asyncio.Semaphore(MAX_CONCURRENT_REQUESTS)
sonnet_semaphore = asyncio.Semaphore(MAX_CONCURRENT_REQUESTS)
```

### WP-10: proxy-toggle Enable/Disable

The `proxy-toggle` script manages `.zshenv` entries and a flag file atomically.

```bash
# Enable: adds env vars to .zshenv, creates flag file, checks proxy health
~/.claude/bin/proxy-toggle enable

# Disable: removes env vars from .zshenv, removes flag file
~/.claude/bin/proxy-toggle disable

# Status: shows routing flag, proxy process, .zshenv state
~/.claude/bin/proxy-toggle status
```

**Important**: Claude Code must be restarted after toggling because `ANTHROPIC_BASE_URL` is read at startup.

### WP-11: Health Endpoint

The `/health` endpoint returns provider configuration state for monitoring.

```bash
curl -s http://127.0.0.1:3000/health | python3 -m json.tool
```

```json
{
  "status": "healthy",
  "haiku": {
    "model": "claude-haiku-4-5-20251001",
    "provider_set": true,
    "api_key_set": true
  },
  "opus": {
    "model": "claude-3-opus",
    "provider_set": false,
    "api_key_set": false
  },
  "sonnet": {
    "model": "claude-sonnet",
    "provider_set": false,
    "api_key_set": false,
    "uses_oauth": true
  }
}
```

### WP-12: Failover Proxy with Retry

A wrapper proxy that tries primary first, retries on failure with exponential backoff, then falls back to secondary.

**Use case**: When primary Go proxy (8082) is down, automatically retry then route to Python fallback (3000).

**Architecture**:
```
Claude Code → :8083 (failover wrapper)
                   |
                   ├─→ :8082 (Go proxy) [PRIMARY, 3 retries, exponential backoff]
                   |   - 500ms → 1s → 2s
                   |
                   └─→ :3000 (Python) [FALLBACK]
```

**Go implementation** uses `cenkalti/backoff/v4` for exponential backoff:
```go
import "github.com/cenkalti/backoff/v4"

backoffConfig := backoff.NewExponentialBackOff(
    backoff.WithInitialInterval(500 * time.Millisecond),
    backoff.WithMultiplier(2),
    backoff.WithMaxInterval(2 * time.Second),
    backoff.WithMaxElapsedTime(5 * time.Second),
)
err := backoff.Retry(operation, backoffConfig)
```

**Location**: `$HOME/eon/cc-skills/tools/claude-code-failover/`

**Management**:
```bash
# Start
cd $HOME/eon/cc-skills/tools/claude-code-failover
go build -o proxy-failover .
nohup ./proxy-failover > ~/.claude/logs/proxy-failover.log 2>&1 &

# Status
curl -s http://127.0.0.1:8083/health | jq .

# Logs
tail -f ~/.claude/logs/proxy-failover.log
```

**Environment** (in `.zshenv`):
```bash
export ANTHROPIC_BASE_URL="http://127.0.0.1:8083"
export ANTHROPIC_API_KEY="proxy-managed"
```

**Telemetry**: `/health` returns failover stats:
```json
{
  "primary_attempts": 47,
  "primary_success": 46,
  "primary_failures": 1,
  "fallback_attempts": 1,
  "fallback_success": 1,
  "current_proxy": "go:8082"
}
```

### WP-13: Launchd Service for Go Proxy

The Go proxy runs as a launchd daemon for auto-restart on crash and boot.

**Location**: `/Library/LaunchDaemons/com.terryli.claude-proxy.plist`

**Configuration**:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.terryli.claude-proxy</string>
    <key>ProgramArguments</key>
    <array><string>/usr/local/bin/claude-proxy</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PORT</key><string>8082</string>
        <key>HAIKU_PROVIDER_API_KEY</key><string>sk-cp-...</string>
        <key>HAIKU_PROVIDER_BASE_URL</key><string>https://api.minimax.io/anthropic</string>
    </dict>
</dict>
</plist>
```

**Commands**:
```bash
# Load (start)
sudo launchctl load -w /Library/LaunchDaemons/com.terryli.claude-proxy.plist

# Unload (stop)
sudo launchctl unload -w /Library/LaunchDaemons/com.terryli.claude-proxy.plist

# Check status
sudo launchctl list | grep claude-proxy
```

---

## Anti-Patterns Summary

Full details with code examples: [references/anti-patterns.md](./references/anti-patterns.md)

| ID     | Severity | Gotcha                                                 | Fix                                                                    |
| ------ | -------- | ------------------------------------------------------ | ---------------------------------------------------------------------- |
| CCP-01 | HIGH     | ANTHROPIC_BASE_URL alone without ANTHROPIC_API_KEY     | Set `ANTHROPIC_API_KEY=proxy-managed`                                  |
| CCP-02 | HIGH     | Missing `anthropic-beta: oauth-2025-04-20` header      | Append to existing beta headers                                        |
| CCP-03 | MEDIUM   | Using `/api/oauth/claude_cli/create_api_key` endpoint  | Requires `org:create_api_key` scope (users only have `user:inference`) |
| CCP-04 | HIGH     | Lowercase keychain service `"claude-code-credentials"` | Actual name has space: `"Claude Code-credentials"`                     |
| CCP-05 | MEDIUM   | Reading `~/.claude/.credentials.json` as primary       | Keychain is SSoT; credential file is stale fallback                    |
| CCP-06 | HIGH     | Hardcoding OAuth tokens                                | Tokens expire; read dynamically with cache                             |
| CCP-07 | HIGH     | Using `gh auth token` in proxy/hooks                   | Causes process storms (recursive spawning)                             |
| CCP-08 | MEDIUM   | Setting ANTHROPIC_API_KEY to real key while proxy runs | Proxy forwards it to all providers, leaking key                        |
| CCP-09 | MEDIUM   | Not handling `/v1/messages/count_tokens`               | Causes auth failures on preflight requests                             |
| CCP-10 | LOW      | Running proxy on 0.0.0.0                               | Bind to 127.0.0.1 for security                                         |

---

## TodoWrite Task Templates

### Template A - Set Up New Multi-Provider Proxy

```
1. [Preflight] Verify Python 3.13, uv, and curl installed
2. [Preflight] Verify 1Password CLI for API key resolution
3. [Execute] Clone proxy repo to ~/.claude/tools/claude-code-proxy/
4. [Execute] Create virtualenv: uv venv --python 3.13 .venv
5. [Execute] Install deps: uv pip install --python .venv/bin/python -r requirements.txt
6. [Execute] Create .env file with provider config (chmod 600)
7. [Execute] Resolve API keys from 1Password into .env
8. [Execute] Start proxy: nohup .venv/bin/python proxy.py > /tmp/claude-code-proxy.log 2>&1 &
9. [Execute] Install proxy-toggle to ~/.claude/bin/
10. [Execute] Run proxy-toggle enable
11. [Verify] Health check: curl -s http://127.0.0.1:3000/health
12. [Verify] Restart Claude Code and verify Haiku routes to provider (check proxy logs)
```

### Template B - Add New Provider

```
1. [Preflight] Verify provider supports /v1/messages Anthropic-compatible endpoint
2. [Execute] Add provider env vars to .env (BASE_URL + API_KEY)
3. [Execute] Configure model tier mapping (HAIKU/SONNET/OPUS)
4. [Verify] Restart proxy and test with curl
5. [Verify] Update references/provider-compatibility.md
```

### Template C - Diagnose Proxy Auth Failure

```
1. Check proxy is running: curl -s http://127.0.0.1:3000/health
2. Check .zshenv has ANTHROPIC_BASE_URL and ANTHROPIC_API_KEY set
3. Check proxy logs: tail -50 /tmp/claude-code-proxy.log
4. Verify auth method in logs: look for "OAuth (Keychain)" vs "No auth"
5. Test Keychain read: security find-generic-password -s "Claude Code-credentials" -a $(whoami) -w | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('claudeAiOauth',{}).get('accessToken','NONE')[:20])"
6. Check anthropic-beta header in proxy logs (must contain oauth-2025-04-20)
7. If all else fails: proxy-toggle disable, restart Claude Code, verify native auth works
```

### Template D - Disable Proxy and Revert

```
1. [Execute] ~/.claude/bin/proxy-toggle disable
2. [Execute] Stop proxy: pkill -f "python proxy.py" (or mise run proxy_stop)
3. [Verify] grep ANTHROPIC_BASE_URL ~/.zshenv returns nothing
4. [Verify] Restart Claude Code and verify native auth works
```

---

## Reference Implementation

The working production deployment:

| File                                         | Purpose                                     |
| -------------------------------------------- | ------------------------------------------- |
| `~/.claude/tools/claude-code-proxy/proxy.py` | Main proxy server (~660 lines)              |
| `~/.claude/tools/claude-code-proxy/.env`     | Provider config (chmod 600)                 |
| `~/.claude/bin/proxy-toggle`                 | Enable/disable/status script                |
| `~/.claude/.proxy-enabled`                   | Empty flag file (present = routing enabled) |
| `~/.claude/docs/haiku-minimax-proxy.md`      | Operational documentation                   |

---

## Post-Change Checklist

After modifying this skill:

1. [ ] Anti-patterns table matches [references/anti-patterns.md](./references/anti-patterns.md)
2. [ ] Working patterns verified against proxy.py source
3. [ ] No hardcoded OAuth tokens in examples
4. [ ] Beta header version current (`oauth-2025-04-20`)
5. [ ] All internal links use relative paths (`./references/...`)
6. [ ] Link validator passes
7. [ ] Skill validator passes
8. [ ] Append changes to [references/evolution-log.md](./references/evolution-log.md)

---

## Troubleshooting

| Issue                                  | Cause                                      | Solution                                         |
| -------------------------------------- | ------------------------------------------ | ------------------------------------------------ |
| Claude Code ignores ANTHROPIC_BASE_URL | Missing ANTHROPIC_API_KEY (CCP-01)         | Set `ANTHROPIC_API_KEY=proxy-managed` in .zshenv |
| 401 Unauthorized from Anthropic        | Missing anthropic-beta header (CCP-02)     | Ensure proxy appends `oauth-2025-04-20`          |
| Keychain read returns empty            | Wrong service name (CCP-04)                | Use `"Claude Code-credentials"` (with space)     |
| Proxy forwards real API key            | ANTHROPIC_API_KEY set to real key (CCP-08) | Use `proxy-managed` sentinel value               |
| count_tokens auth failure              | Missing endpoint handler (CCP-09)          | Proxy must handle `/v1/messages/count_tokens`    |
| Proxy accessible from network          | Bound to 0.0.0.0 (CCP-10)                  | Bind to 127.0.0.1 only                           |
| Process storms on enable               | gh auth token in hooks (CCP-07)            | Never call gh CLI from hooks/credential helpers  |
| MiniMax returns wrong model name       | MiniMax quirk                              | Cosmetic only; Claude Code handles it            |
| Token expired after 5 min              | Cache TTL (WP-05)                          | Normal behavior; proxy re-reads from Keychain    |
