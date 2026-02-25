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

- Go proxy binary: `/usr/local/bin/claude-proxy` (port 8082)

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
    |  ANTHROPIC_BASE_URL=http://127.0.0.1:8082 (Go proxy)
    |  (unset ANTHROPIC_API_KEY to avoid auth conflict)
    v
+----------------------------------+
| Go proxy (:8082)                 |
| launchd managed, auto-restart   |
+----------------------------------+
    |
    | model =
    | claude-haiku-
    | 4-5-20251001
    v
+-----------+
| MiniMax   |
| M2.5      |
| highspeed |
+-----------+
```

**Port Configuration**:

- `:8082` - Go proxy (entry point, launchd-managed, auto-restart)

The Go proxy uses `cenkalti/backoff/v4` for built-in retry logic.

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
export ANTHROPIC_BASE_URL="http://127.0.0.1:8082"
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
curl -s http://127.0.0.1:8082/health | jq .
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

### WP-12: Go Proxy with Retry

A Go proxy with built-in retry using `cenkalti/backoff/v4` for resilience.

**Use case**: Primary Go proxy with exponential backoff retry (500ms → 1s → 2s).

**Architecture**:

```
Claude Code → :8082 (Go proxy with retry)
                   |
                   └─→ MiniMax or Anthropic
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

**Location**: `/usr/local/bin/claude-proxy`

**Environment** (in `.zshenv`):

```bash
export ANTHROPIC_BASE_URL="http://127.0.0.1:8082"
export ANTHROPIC_API_KEY="proxy-managed"
```

**Test**:

```bash
curl -s http://127.0.0.1:8082/health | jq .
```

### WP-13: Launchd Service Configuration

The Go proxy runs as a macOS launchd daemon for auto-restart on crash and boot persistence.

**Why launchd?**:

- Auto-restarts if proxy crashes
- Starts on system boot (RunAtLoad)
- Runs as root (needed for port 80/443 if ever needed)
- Resource limits can be enforced

**Plist Location**: `/Library/LaunchDaemons/com.example.claude-proxy.plist`

**Full Configuration**:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Unique identifier -->
    <key>Label</key><string>com.example.claude-proxy</string>

    <!-- Program to run -->
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/claude-proxy</string>
    </array>

    <!-- Start on boot -->
    <key>RunAtLoad</key><true/>

    <!-- Auto-restart on crash (any non-zero exit) -->
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key><false/>
    </dict>

    <!-- Environment variables passed to the proxy -->
    <key>EnvironmentVariables</key>
    <dict>
        <key>PORT</key><string>8082</string>
        <key>HAIKU_PROVIDER_API_KEY</key><string>sk-cp-49GSmHBfC0c65pvYrFoZZy8xEjOVxXrUiTIJn65ynTvgzoiGEvM7q9V5dYYe6PwjMfZaGelKoE2oTq1hKnttv8ODm36O8gklUIi1eaTVOKbPILlIPfNcM0E</string>
        <key>HAIKU_PROVIDER_BASE_URL</key><string>https://api.minimax.io/anthropic</string>
        <key>ANTHROPIC_DEFAULT_HAIKU_MODEL</key><string>claude-haiku-4-5-20251001</string>
    </dict>

    <!-- Resource limits -->
    <key>SoftResourceLimits</key>
    <dict>
        <key>NumberOfFiles</key><integer>65536</integer>
    </dict>

    <!-- Log output -->
    <key>StandardOutPath</key><string>/Users/<you>/.claude/logs/proxy-stdout.log</string>
    <key>StandardErrorPath</key><string>/Users/<you>/.claude/logs/proxy-stderr.log</string>
</dict>
</plist>
```

**Key launchd Properties Explained**:

| Key                                | Purpose            | Value for Proxy                                |
| ---------------------------------- | ------------------ | ---------------------------------------------- |
| `Label`                            | Unique identifier  | `com.example.claude-proxy`                     |
| `ProgramArguments`                 | Command + args     | `["/usr/local/bin/claude-proxy"]`              |
| `RunAtLoad`                        | Start at boot      | `true`                                         |
| `KeepAlive/SuccessfulExit`         | Restart on crash   | `false` (always restart)                       |
| `EnvironmentVariables`             | Env vars for proxy | PORT, API keys, etc.                           |
| `SoftResourceLimits/NumberOfFiles` | FD limit           | `65536`                                        |
| `StandardOutPath`                  | stdout log         | `/Users/<you>/.claude/logs/proxy-stdout.log` |
| `StandardErrorPath`                | stderr log         | `/Users/<you>/.claude/logs/proxy-stderr.log` |

**Commands**:

```bash
# Install plist (one-time)
sudo cp /path/to/com.example.claude-proxy.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.example.claude-proxy.plist
sudo chmod 644 /Library/LaunchDaemons/com.example.claude-proxy.plist

# Start (load)
sudo launchctl load -w /Library/LaunchDaemons/com.example.claude-proxy.plist

# Stop (unload)
sudo launchctl unload -w /Library/LaunchDaemons/com.example.claude-proxy.plist

# Restart
sudo launchctl unload -w /Library/LaunchDaemons/com.example.claude-proxy.plist
sudo launchctl load -w /Library/LaunchDaemons/com.example.claude-proxy.plist

# Check status
sudo launchctl list | grep claude-proxy

# View running PID info
ps aux | grep claude-proxy

# View logs
tail -f /Users/<you>/.claude/logs/proxy-stdout.log
tail -f /Users/<you>/.claude/logs/proxy-stderr.log

# Test health
curl -s http://127.0.0.1:8082/health | jq .
```

**Verification Checklist**:

```bash
# 1. Plist exists
ls -la /Library/LaunchDaemons/com.example.claude-proxy.plist

# 2. Loaded in launchd
sudo launchctl list | grep claude-proxy

# 3. Process running
ps aux | grep claude-proxy | grep -v grep

# 4. Port listening
lsof -i :8082

# 5. Health endpoint responds
curl -s http://127.0.0.1:8082/health | jq .
```

**Debugging launchd Issues**:

```bash
# Check if plist is valid
plutil -lint /Library/LaunchDaemons/com.example.claude-proxy.plist

# View full launchd logs
log show --predicate 'process == "claude-proxy"' --last 5m

# Check stderr for errors
tail -50 /Users/<you>/.claude/logs/proxy-stderr.log
```

### WP-14: OAuth Token Auto-Refresh

The Go proxy automatically refreshes OAuth tokens before they expire.

**Use case**: Prevent auth failures when tokens expire during long-running Claude Code sessions.

**Implementation**: Background goroutine runs every 30 minutes, checks if token expires within 5 minutes, and refreshes using the refresh token.

```go
// oauth_refresh.go
func startTokenRefreshLoop() {
    ticker := time.NewTicker(30 * time.Minute)
    defer ticker.Stop()
    refreshTokenIfNeeded() // Run immediately on startup
    for {
        select {
        case <-ticker.C:
            refreshTokenIfNeeded()
        }
    }
}

func refreshTokenIfNeeded() {
    // Check if token expires within 5 minutes
    needsRefresh := oauthCache.token == "" ||
        (!oauthCache.expiresAt.IsZero() && time.Now().Add(5*time.Minute).After(oauthCache.expiresAt))

    if !needsRefresh {
        return // Token still valid
    }

    // Try API refresh first
    newToken, newRefreshToken, newExpiresAt, err := refreshOAuthToken(refreshToken)
    if err != nil {
        // Fallback: get fresh token from Keychain
        tryKeychainRefresh()
        return
    }

    // Update cache and persist
    oauthCache.token = newToken
    oauthCache.refreshToken = newRefreshToken
    oauthCache.expiresAt = newExpiresAt
    saveOAuthToFile(newToken, newRefreshToken, newExpiresAt)
}
```

**Refresh Logic**:

1. Runs every 30 minutes in background goroutine
2. Checks if token expires within 5 minutes
3. If refresh token available → calls Anthropic OAuth refresh endpoint
4. If API fails → falls back to Keychain retrieval
5. Saves new tokens to `.oauth.json` for persistence

**Key files**:

- `oauth_refresh.go` - Auto-refresh logic (~80 lines)
- `main.go` - Token cache + refreshOAuthToken function

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
| CCP-08 | HIGH     | ANTHROPIC_API_KEY set in env while having OAuth token  | Auth conflict warning in Claude Code; unset it                         |
| CCP-09 | MEDIUM   | cache_control param sent to MiniMax                    | MiniMax doesn't support it; remove from allowedParams                  |
| CCP-10 | MEDIUM   | Setting ANTHROPIC_API_KEY to real key while proxy runs | Proxy forwards it to all providers, leaking key                        |
| CCP-11 | MEDIUM   | Not handling `/v1/messages/count_tokens`               | Causes auth failures on preflight requests                             |
| CCP-12 | LOW      | Running proxy on 0.0.0.0                               | Bind to 127.0.0.1 for security                                         |

---

## TodoWrite Task Templates

### Template A - Set Up Go Proxy

```
1. [Preflight] Verify Go 1.21+ installed: go version
2. [Execute] Build Go proxy to /usr/local/bin/claude-proxy
3. [Execute] Create launchd plist at /Library/LaunchDaemons/com.example.claude-proxy.plist
4. [Execute] Load launchd: sudo launchctl load -w /Library/LaunchDaemons/com.example.claude-proxy.plist
5. [Execute] Add to ~/.zshenv: export ANTHROPIC_BASE_URL="http://127.0.0.1:8082"
6. [Execute] Add to ~/.zshenv: export ANTHROPIC_API_KEY="proxy-managed"
7. [Verify] Health: curl -s http://127.0.0.1:8082/health
8. [Verify] Restart Claude Code
```

### Template B - Add New Provider

```
1. [Preflight] Verify provider supports /v1/messages
2. [Execute] Edit launchd plist, add to EnvironmentVariables:
   - PROVIDER_API_KEY
   - PROVIDER_BASE_URL
3. [Execute] Reload: sudo launchctl unload -w ... && sudo launchctl load -w ...
4. [Verify] Test: curl http://127.0.0.1:8082/health
```

### Template C - Diagnose Proxy Auth Failure

```
1. Check running: sudo launchctl list | grep claude-proxy
2. Check port: lsof -i :8082
3. Check .zshenv: grep ANTHROPIC ~/.zshenv
4. Check logs: tail -50 /Users/<you>/.claude/logs/proxy-stdout.log
5. Health check: curl http://127.0.0.1:8082/health
```

### Template D - Disable Proxy

```
1. Comment out ANTHROPIC_BASE_URL in ~/.zshenv
2. Unload: sudo launchctl unload -w /Library/LaunchDaemons/com.example.claude-proxy.plist
3. Restart Claude Code
```

---

## Reference Implementation

The working production deployment (Go proxy is primary):

| File                                                    | Purpose                          |
| ------------------------------------------------------- | -------------------------------- |
| `/usr/local/bin/claude-proxy`                           | Go proxy binary (~960 lines)     |
| `~/.claude/tools/claude-code-proxy-go/main.go`          | Go proxy source                  |
| `~/.claude/tools/claude-code-proxy-go/oauth_refresh.go` | OAuth auto-refresh (80 lines)    |
| `~/.claude/tools/claude-code-proxy-go/.env`             | Provider config (chmod 600)      |
| `/Library/LaunchDaemons/com.example.claude-proxy.plist` | launchd config                   |
| `~/.zshenv`                                             | Environment (ANTHROPIC_BASE_URL) |

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

| Issue                                  | Cause                                          | Solution                                         |
| -------------------------------------- | ---------------------------------------------- | ------------------------------------------------ |
| Claude Code ignores ANTHROPIC_BASE_URL | Missing ANTHROPIC_API_KEY (CCP-01)             | Set `ANTHROPIC_API_KEY=proxy-managed` in .zshenv |
| 401 Unauthorized from Anthropic        | Missing anthropic-beta header (CCP-02)         | Ensure proxy appends `oauth-2025-04-20`          |
| Keychain read returns empty            | Wrong service name (CCP-04)                    | Use `"Claude Code-credentials"` (with space)     |
| Proxy forwards real API key            | ANTHROPIC_API_KEY set to real key (CCP-10)     | Use `proxy-managed` sentinel value               |
| count_tokens auth failure              | Missing endpoint handler (CCP-11)              | Proxy must handle `/v1/messages/count_tokens`    |
| Proxy accessible from network          | Bound to 0.0.0.0 (CCP-12)                      | Bind to 127.0.0.1 only                           |
| Process storms on enable               | gh auth token in hooks (CCP-07)                | Never call gh CLI from hooks/credential helpers  |
| MiniMax returns wrong model name       | MiniMax quirk                                  | Cosmetic only; Claude Code handles it            |
| Token expired after 5 min              | Cache TTL (WP-05)                              | Normal behavior; proxy re-reads from Keychain    |
| Auth conflict warning in Claude Code   | ANTHROPIC_API_KEY set (CCP-08)                 | Unset ANTHROPIC_API_KEY in .zshenv               |
| cache_control.ephemeral.scope error    | MiniMax doesn't support cache_control (CCP-09) | Remove cache_control from allowedParams          |
