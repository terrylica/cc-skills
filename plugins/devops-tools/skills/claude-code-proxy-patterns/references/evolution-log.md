# Evolution Log

## 2026-02-22: Initial skill creation

Source: Empirical discovery during proxy implementation.
Key discoveries: OAuth Keychain storage (`"Claude Code-credentials"`), `anthropic-beta: oauth-2025-04-20` header requirement, `ANTHROPIC_API_KEY=proxy-managed` forcing pattern.
Reference implementation: `$HOME/.claude/tools/claude-code-proxy/proxy.py`
10 anti-patterns (CCP-01 through CCP-10) cataloged from real debugging sessions.
Provider compatibility tested: MiniMax M2.5-highspeed, Real Anthropic.
Binary reverse-engineering findings: `_d()` service name, `hW()` storage backend, `WL="oauth-2025-04-20"` constant.
