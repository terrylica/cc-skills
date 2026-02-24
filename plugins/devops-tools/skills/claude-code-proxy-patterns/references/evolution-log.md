# Evolution Log

## 2026-02-23: Go Migration + Failover

Source: Migration from Python FastAPI to Go binary for launchd deployment.

Key changes:
- Go binary proxy deployed to `/usr/local/bin/claude-proxy` (port 8082)
- launchd plist for auto-restart: `/Library/LaunchDaemons/com.terryli.claude-proxy.plist`
- Failover wrapper added (port 8083) with `cenkalti/backoff/v4` retry
- Primary: Go proxy (8082), Fallback: Python proxy (3000)

Reference implementations:
- Go proxy: `/usr/local/bin/claude-proxy`
- Failover: `$HOME/eon/cc-skills/tools/claude-code-failover/main.go`
- Python proxy: `$HOME/.claude/tools/claude-code-proxy/proxy.py`

Port configuration:
- `:8083` - Failover wrapper (entry point)
- `:8082` - Go proxy (primary, launchd-managed)
- `:3000` - Python proxy (fallback)

MiniMax credentials added to Go proxy via launchd EnvironmentVariables.

## 2026-02-22: Initial skill creation

Source: Empirical discovery during proxy implementation.
Key discoveries: OAuth Keychain storage (`"Claude Code-credentials"`), `anthropic-beta: oauth-2025-04-20` header requirement, `ANTHROPIC_API_KEY=proxy-managed` forcing pattern.
Reference implementation: `$HOME/.claude/tools/claude-code-proxy/proxy.py`
10 anti-patterns (CCP-01 through CCP-10) cataloged from real debugging sessions.
Provider compatibility tested: MiniMax M2.5-highspeed, Real Anthropic.
Binary reverse-engineering findings: `_d()` service name, `hW()` storage backend, `WL="oauth-2025-04-20"` constant.
