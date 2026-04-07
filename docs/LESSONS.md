# Lessons Learned

Dated entries extracted from root [CLAUDE.md](../CLAUDE.md). Newest first.

**Hub**: [Root CLAUDE.md](../CLAUDE.md) | **Sibling**: [docs/CLAUDE.md](./CLAUDE.md)

---

**2026-04-07**: Antifragile filesystem side-effects in `claude-tts-companion`. TTS audio silently failed for 50+ minutes because `~/.local/share/tts-debug-wav/` disappeared and `AfplayPlayer.swift` used `try? FileManager.createDirectory(...)` at init time with no per-write recheck. Subtitles rendered (in-memory samples) but `afplay` was never spawned — every request hit `NSPOSIXErrorDomain Code=2` and logged an identical error 25+ times. Fix: three-tier self-healing fallback chain (primary → `NSTemporaryDirectory()/claude-tts-wav/` → `mkstemp(3)`) invoked on every write, structured collapsed failure telemetry (≤1 log per failure-class per 60s with `consecutive_failure_count` + `primary_recovered` recovery event), `/health.afplay` snapshot for dashboards, chaos test that compiles-fails against the buggy code (strictly stronger than runtime failure). **Rule**: no `try? FileManager.default.createDirectory` anywhere in `claude-tts-companion/Sources/` — grep must return zero. Incident: `.planning/debug/tts-no-audio-260406.md`. Pattern: `.planning/quick/260407-h07-antifragile-fix-for-afplayplayer-wav-wri/` (research, plan, summary, verification). Code: `Sources/CompanionCore/AfplayPlayer.swift` `ensureWritableWavDirectory()`, `recordFailure()`.

**2026-04-07**: Do NOT replace `afplay` subprocess with `AVAudioPlayer` in `claude-tts-companion`. `AVAudioPlayer`/`AVAudioEngine` was the _previous_ audio implementation and was abandoned because even _initializing_ `AVAudioEngine` in the same process polluted CoreAudio hardware state enough to cause audio jitter under CPU contention (concurrent Swift compilation, MLX/Metal spikes). Subprocess isolation via `posix_spawn(afplay)` keeps the audio path unaffected by in-process GPU/CPU pressure. Git commits `e2e80e1e`, `2be60672`, `c3525c2e`, `815844e2` document the retreat. When a future bug suggests "just use AVAudioPlayer.init(data:) to skip the WAV write", the correct response is to fix the WAV-write side-effect (Antifragile pattern above), not to touch the audio path. Full research: `.planning/quick/260407-h07-antifragile-fix-for-afplayplayer-wav-wri/260407-h07-RESEARCH.md`.

**2026-04-07**: Root `CLAUDE.md` should NOT duplicate project-level content. Pre-2026-04-07, the root had a full ~120-line copy of `claude-tts-companion`'s project/stack/conventions/architecture — and it drifted (wrong Kokoro model path `kokoro-int8-en-v0_19` vs actual `kokoro-int8-multi-lang-v1_0`, stale "AVAudioPlayer for WAV playback" description). Hub-and-spoke rule: the root is a navigation hub; each plugin's CLAUDE.md is the SSoT for that plugin's project details. Active project gets a single pointer link in root's Navigation table.

**2026-03-31**: Terminal text unwrapping for TTS — use `awk`, not FOSS parsers. Spike-tested `par`, `fmt`, `fold`, `pandoc`, `textwrap`, `pysbd` — all fail at joining soft-wrapped continuation lines while preserving bullet boundaries. `par` and `fmt` merge everything into one paragraph (F). `fold` and `pandoc` are passthrough (D). `textwrap` strips indent but doesn't join continuations (D+). `pysbd` splits continuations as separate sentences (D). Only custom `awk` (or equivalent regex) handles the combination of: (1) bullet detection (`·•*-`, numbered, headings), (2) continuation line joining, (3) marker stripping, (4) progressive batching. Zero dependencies, single-pass, built-in on every Unix. Anti-pattern: reaching for Python `textwrap`/`pysbd` or `par` for terminal-copied text — they don't understand bullet-prefixed paragraphs with soft-wrapped continuations.

**2026-03-05**: MCP `mcp-shell-server` causes TTY suspension via hardcoded `-i` (interactive) shell flag + `pwd.getpwuid()` ignoring `$SHELL` env var. Hook-based fix impossible (MCP command allowlist rejects `bash`). Fix: monkeypatch entrypoint replacing `-i` with `-l` (login) + `stdin=DEVNULL`. [Full Guide](./cargo-tty-suspension-prevention.md#mcp-shell-server-tty-suspension-2026-03-05) | Patch: `~/.claude/bin/mcp-shell-server-patched.py`

**2026-03-05**: `bun add -g` fails for packages with native deps (kuzu in gitnexus). Use `npm install -g` instead — mise reshims automatically. Bun-First Policy exception for native modules.

**2026-02-23**: HTTP proxy migrated from Python FastAPI+httpx to Go compiled binary for macOS launchd deployment. Python proxy had 0 commits in 74 days (supply chain risk). Go optimal: stdlib httputil.ReverseProxy handles SSE with `FlushInterval:-1`, 15–30s builds vs Swift's 60–300s, exact-match routing prevents provider switching bugs. Deployed to `/usr/local/bin/claude-proxy` with per-provider weighted semaphores + exponential backoff retries + OAuth header forwarding. 9 independent audits converged on Go. [Implementation](../../.claude/tools/claude-code-proxy-go/CLAUDE.md)

**2026-02-23**: Cargo TTY suspension prevention hook added - prevents Claude Code suspension when running `cargo bench/test/build &`. Uses PUEUE daemon for process isolation (eliminates stdin inheritance). [Full Guide](./cargo-tty-suspension-prevention.md) | [Hook](../plugins/itp-hooks/hooks/pretooluse-cargo-tty-guard.ts) | [GitHub Issues #11898, #12507, #13598](https://github.com/anthropics/claude-code/issues)

**2026-02-20**: Swift launchd binaries that spawn `op` CLI trigger macOS TCC "access data from other apps" prompt — compiled Swift does NOT bypass TCC. Fix: cache static credentials (client_id/client_secret) locally on first run; subsequent runs read only local files, no TCC prompt. [itp-hooks CLAUDE.md](../plugins/itp-hooks/CLAUDE.md#native-binary-guard-macos-launchd)

**2026-02-05**: gh-issue-title-reminder hook added - maximizes 256-char GitHub issue titles. [gh-tools CLAUDE.md](../plugins/gh-tools/CLAUDE.md#github-issue-title-optimization-2026-02-05)

**2026-02-04**: gdrive-tools plugin absorbed into `productivity-tools/skills/gdrive-access`. Google Drive API access with 1Password OAuth.

**2026-01-24**: Code correctness hooks check silent failures only - NO unused imports (F401). [itp-hooks CLAUDE.md](../plugins/itp-hooks/CLAUDE.md#code-correctness-philosophy)

**2026-01-22**: posttooluse-reminder migrated from bash to TypeScript/Bun (33 tests). [Design Spec](/docs/design/2026-01-10-uv-reminder-hook/spec.md)

**2026-01-12**: gh CLI must use Homebrew, not mise (iTerm2 tab spawning). [ADR](/docs/adr/2026-01-12-mise-gh-cli-incompatibility.md)
