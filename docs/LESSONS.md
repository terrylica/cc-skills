# Lessons Learned

Dated entries extracted from root [CLAUDE.md](../CLAUDE.md). Newest first.

**Hub**: [Root CLAUDE.md](../CLAUDE.md) | **Sibling**: [docs/CLAUDE.md](./CLAUDE.md)

---

**2026-02-23**: HTTP proxy migrated from Python FastAPI+httpx to Go compiled binary for macOS launchd deployment. Python proxy had 0 commits in 74 days (supply chain risk). Go optimal: stdlib httputil.ReverseProxy handles SSE with `FlushInterval:-1`, 15–30s builds vs Swift's 60–300s, exact-match routing prevents provider switching bugs. Deployed to `/usr/local/bin/claude-proxy` with per-provider weighted semaphores + exponential backoff retries + OAuth header forwarding. 9 independent audits converged on Go. [Implementation](../../.claude/tools/claude-code-proxy-go/CLAUDE.md)

**2026-02-23**: Cargo TTY suspension prevention hook added - prevents Claude Code suspension when running `cargo bench/test/build &`. Uses PUEUE daemon for process isolation (eliminates stdin inheritance). [Full Guide](./cargo-tty-suspension-prevention.md) | [Hook](../plugins/itp-hooks/hooks/pretooluse-cargo-tty-guard.ts) | [GitHub Issues #11898, #12507, #13598](https://github.com/anthropics/claude-code/issues)

**2026-02-20**: Swift launchd binaries that spawn `op` CLI trigger macOS TCC "access data from other apps" prompt — compiled Swift does NOT bypass TCC. Fix: cache static credentials (client_id/client_secret) locally on first run; subsequent runs read only local files, no TCC prompt. [itp-hooks CLAUDE.md](../plugins/itp-hooks/CLAUDE.md#native-binary-guard-macos-launchd)

**2026-02-05**: gh-issue-title-reminder hook added - maximizes 256-char GitHub issue titles. [gh-tools CLAUDE.md](../plugins/gh-tools/CLAUDE.md#github-issue-title-optimization-2026-02-05)

**2026-02-04**: gdrive-tools plugin absorbed into `productivity-tools/skills/gdrive-access`. Google Drive API access with 1Password OAuth.

**2026-01-24**: Code correctness hooks check silent failures only - NO unused imports (F401). [itp-hooks CLAUDE.md](../plugins/itp-hooks/CLAUDE.md#code-correctness-philosophy)

**2026-01-22**: posttooluse-reminder migrated from bash to TypeScript/Bun (33 tests). [Design Spec](/docs/design/2026-01-10-uv-reminder-hook/spec.md)

**2026-01-12**: gh CLI must use Homebrew, not mise (iTerm2 tab spawning). [ADR](/docs/adr/2026-01-12-mise-gh-cli-incompatibility.md)
