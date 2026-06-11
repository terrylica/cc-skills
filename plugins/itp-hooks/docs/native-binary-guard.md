# Native Binary Guard (macOS Launchd)

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — moved verbatim from the hub 2026-06-11 (CLAUDE.md size-guard refactor: hub was 112k chars, limit 40k).

## Native Binary Guard (macOS Launchd)

The `pretooluse-native-binary-guard.ts` hook enforces that all macOS launchd services use compiled native binaries (Swift preferred), never bash scripts.

### Why

Using `/bin/bash` in launchd plists shows a generic "bash" entry in System Settings > Login Items, which looks like unidentified malware. Compiled Swift binaries show their actual executable name (e.g., "calendar-announce").

### Detections

| Pattern                              | Example                               | Decision            |
| ------------------------------------ | ------------------------------------- | ------------------- |
| `.sh`/`.bash` file in automation dir | `~/.claude/automation/foo/run.sh`     | **DENY**            |
| `.plist` with `/bin/bash`            | `<string>/bin/bash</string>`          | **DENY**            |
| `.plist` with `.sh` script path      | `<string>/path/to/script.sh</string>` | **DENY**            |
| `.swift` file in automation dir      | `~/.claude/automation/foo/Main.swift` | ALLOW               |
| `.plist` with compiled binary        | `<string>/path/to/binary</string>`    | ALLOW               |
| Any file outside automation dirs     | `~/eon/project/script.sh`             | ALLOW (not checked) |

### Scope (Narrow)

Only triggers for files in these directories:

- `~/.claude/automation/`
- `~/Library/LaunchAgents/`
- `~/Library/LaunchDaemons/`

### Performance

Uses a **raw-stdin fast path**: checks for launchd-related keywords (`.plist`, `.sh`, `LaunchAgent`, `automation/`) in the raw stdin string BEFORE JSON parsing. For 99%+ of Write/Edit calls (normal code files), exits in <1ms without parsing JSON.

### Required Pattern

```bash
# 1. Write logic in Swift
vim ~/.claude/automation/my-tool/swift-cli/MyTool.swift

# 2. Compile to native binary
swiftc -O -framework EventKit -o my-tool MyTool.swift

# 3. Reference binary directly in plist (NOT /bin/bash)
# <string>$HOME/.claude/automation/my-tool/swift-cli/my-tool</string>
```

### TypeScript Services: Swift Runner + `bun --watch`

For TypeScript/Bun services (bots, sync daemons), the Swift binary acts as a thin launcher that delegates to `bun --watch run`. This gives you:

- **Launchd compliance**: Named binary in Login Items (not "bash")
- **Auto-restart on code changes**: `bun --watch` uses kqueue (macOS native, zero overhead) to restart the process when any `.ts` file changes — no manual kills needed
- **Clean process tree**: launchd → Swift runner → `bun --watch` → TypeScript service

```swift
// Runner binary (compile with: swiftc -O -o my-bot my-bot-runner.swift)
process.arguments = ["--watch", "run", scriptPath]
```

| Service type                       | Launchd binary      | Runtime                       |
| ---------------------------------- | ------------------- | ----------------------------- |
| System integration (EventKit, TCC) | Swift (full logic)  | Native                        |
| TypeScript bot/daemon              | Swift (thin runner) | `bun --watch run src/main.ts` |

**Anti-pattern**: `bun --hot` for long-running services (stale module state across reloads). Use `--watch` (full process restart).

Reference: `~/.claude/automation/claude-telegram-sync/telegram-bot-runner.swift`

### Escape Hatch

Add `# BASH-LAUNCHD-OK` (in scripts) or `<!-- BASH-LAUNCHD-OK -->` (in plists) to bypass.

### TCC Anti-Pattern: Duplicate EventKit Access

**Problem**: Each compiled Swift binary that imports EventKit triggers a separate macOS TCC prompt ("Would Like Full Access to Your Calendar"). Multiple binaries = multiple manual approval dialogs.

**Fix**: Designate ONE binary as the EventKit reader (e.g., `calendar-event-reader`). Other binaries call it as a subprocess and parse its JSON stdout. Only the reader needs the TCC grant.

| Pattern                                    | TCC Prompts | Approach     |
| ------------------------------------------ | ----------- | ------------ |
| 3 binaries each import EventKit            | 3 prompts   | Anti-pattern |
| 1 reader binary + 2 callers via subprocess | 1 prompt    | Correct      |

### TCC Anti-Pattern: Subprocess Credential Access

**Problem**: A launchd Swift binary that spawns `op` (1Password CLI) as a subprocess on every run triggers the macOS TCC prompt "would like to access data from other apps" — even though the binary is compiled Swift. **Compiled language does NOT bypass TCC. TCC is based on what the binary does at runtime, not what language it's written in.**

**Context**: The `gmail-oauth-token-hourly-refresher` runs hourly to refresh OAuth access tokens. It originally called `op item get` on every run to fetch OAuth app credentials (`client_id`/`client_secret`) from 1Password.

**Fix**: Cache static credentials locally on first run. Subsequent runs read from local cache files only — no subprocess spawning, no TCC prompt.

```swift
// Cache file: ~/.claude/tools/gmail-tokens/<uuid>.app-credentials.json
// Check cache first; fall back to `op` only when cache is missing

if cacheExists && cacheValid {
    clientId = cache["client_id"]       // Local file read — no TCC
    clientSecret = cache["client_secret"]
} else {
    // One-time 1Password fetch → TCC prompt appears ONCE
    fetchFromOP() → writeCache()        // All future runs skip this branch
}
```

**When to apply**: Any binary that fetches the same static credentials (OAuth app credentials, API keys, etc.) on every invocation. Dynamic credentials (tokens, session keys) cannot be cached and must be fetched fresh — but those typically live in local files already.

**To force re-fetch** (e.g., after rotating credentials in 1Password):

```bash
rm ~/.claude/tools/gmail-tokens/<uuid>.app-credentials.json
```

| Pattern                                    | TCC Prompts      | Approach     |
| ------------------------------------------ | ---------------- | ------------ |
| Call `op` on every hourly run              | Every run        | Anti-pattern |
| Cache static creds, call `op` only on miss | Once (first run) | Correct      |

### Reference

- Examples: `~/.claude/automation/calendar-alarm-sweep/swift-cli/` (CalendarAnnounce.swift, CalendarAlarmSweep.swift)
- Credential caching: `~/.claude/automation/gmail-token-refresher/main.swift`

