# External Integrations

**Analysis Date:** 2026-04-02

## APIs & External Services

**Telegram Bot API:**

- **Service:** Telegram (official Bot API, Telegram Cloud)
- **Purpose:** Session monitoring, command dispatch, session notifications, inline button callbacks, health status reporting
- **SDK/Client:** swift-telegram-sdk 4.5.0 (URLSession-based long polling)
- **Auth:** Token in `TELEGRAM_BOT_TOKEN` env var (plist `EnvironmentVariables` key)
- **Location:** `Sources/CompanionCore/TelegramBot.swift` (start/stop lifecycle)
- **Commands:** `/start`, `/stop`, `/status`, `/health`, `/sessions`, `/prompt`, `/done`, `/commands`
- **Callbacks:** Inline button handlers for interactive session control and summary exploration
- **See also:** `TelegramBotCommands.swift`, `TelegramBotCallbacks.swift`, `TelegramBotNotifications.swift`

**MiniMax API (Anthropic-compatible):**

- **Service:** MiniMax (LLM for session narratives)
- **Purpose:** Generate session summaries, single-turn brief, arc narratives, tail-weighted briefs for TTS playback
- **Endpoint:** `https://api.minimax.io/anthropic/v1/messages` (Anthropic-compatible protocol)
- **Auth:** API key in `MINIMAX_API_KEY` env var; header `x-api-key`
- **Client:** `MiniMaxClient` (URLSession, async/await, 30s request timeout + 60s resource timeout)
- **Model:** `MiniMax-M2.7-highspeed` (Config.swift line 100)
- **Max tokens:** 8192 (Config.summaryMaxTokens, line 94)
- **Request format:** Anthropic messages API (system prompt + user message)
- **Response headers:** `anthropic-version: 2024-10-22` (line 70 MiniMaxClient.swift)
- **Circuit breaker:** Stops retries after repeated failures (CircuitBreaker.swift)
- **Location:** `Sources/CompanionCore/MiniMaxClient.swift`, `Sources/CompanionCore/SummaryEngine.swift`
- **Error handling:** circuit-breaker open, missing API key, network errors, HTTP non-200, JSON decode failures
- **See also:** `CircuitBreaker.swift` for failure tracking

**Claude Code Notification Stream:**

- **Service:** Local file watch (Claude Code writes notification JSONs)
- **Purpose:** Real-time session tracking, session start/end detection, notification dedup
- **Polling method:** DispatchSource file system events (O_EVTONLY, .write mask) via FSEvents
- **Watch path:** `$CLAUDE_NOTIFICATION_DIR/*.json` (default: `~/.claude/notifications/`)
- **Latency target:** <100ms (Config.fileWatcherLatencyTarget, line 151 Config.swift)
- **File format:** JSON with session metadata (session_id, project_path, start_time, end_time)
- **Location:** `Sources/CompanionCore/NotificationWatcher.swift`, `Sources/CompanionCore/NotificationProcessor.swift`
- **Dedup:** 15-minute TTL (Config.notificationDedupTTL, line 157), 5-second min interval (line 161)
- **See also:** `JSONLTailer.swift` (offset-based JSONL tailing for transcripts)

**Claude Code Transcript Stream (JSONL):**

- **Service:** Local JSONL tailing (Claude Code writes conversation transcripts)
- **Purpose:** Extract conversation turns for session summary input
- **Watch path:** `$CLAUDE_PROJECTS_DIR/{project-hash}/sessions/{session-id}/transcript.jsonl`
- **File format:** Newline-delimited JSON (one turn per line: `{"role": "user"|"assistant", "content": "...", "tool_uses": [...]}`
- **Tailing method:** DispatchSource + offset-based reads from last known position
- **Latency:** P95 0.34ms (per spike 15 validation)
- **Location:** `Sources/CompanionCore/JSONLTailer.swift`, `Sources/CompanionCore/TranscriptParser.swift`
- **See also:** `ThinkingWatcher.swift` (extracting thinking content from extended transcripts)

## Data Storage

**Databases:**

- Not used. Stateless service.

**File Storage:**

- **Local filesystem only** (no cloud storage)
  - Kokoro models: `~/.local/share/kokoro/models/` (int8 quantized: ~260MB)
  - TTS audio cache: temporary WAV files in `/tmp` (cleaned up after playback)
  - Caption history: in-memory (CaptionHistory.swift) + optional JSON serialization
  - Logs: launchd stderr to `~/.local/state/launchd-logs/claude-tts-companion/stderr.log`

**Caching:**

- **In-memory only**
  - sherpa-onnx model instance (lazy-loaded on first TTS request, unloaded after 30s idle per line 175 Config.swift)
  - Caption history (CaptionHistory.swift, max entries bounded)
  - Circuit breaker state (MiniMaxClient failure tracking)

## Authentication & Identity

**Auth Provider:**

- **Custom** (no third-party OAuth)
  - Telegram: token-based (API key in env)
  - MiniMax: API key in env (x-api-key header)
  - Claude Code: file-system watching (no auth, local machine only)

**Secrets Management:**

- Secrets passed via launchd `EnvironmentVariables` (plist file in `~/Library/LaunchAgents/`)
- No `.env` file (plist is SSoT)
- Empty values in repo plist (line 37-41); populated at runtime via `launchctl setenv` or prior launchd load

## Monitoring & Observability

**Error Tracking:**

- None (no Sentry, Rollbar, or dedicated error service)
- Errors logged to stderr via swift-log (captured by launchd ASL)

**Logs:**

- **Destination:** launchd stderr to `~/.local/state/launchd-logs/claude-tts-companion/stderr.log` (plist StandardErrorPath line 49)
- **Framework:** swift-log with `StreamLogHandler.standardError`
- **Levels:** info, debug (logger.info, logger.error used throughout)
- **Subsystem loggers:** "telegram-bot", "http-server", "minimax-client", "tts-engine", "summary-engine", "jsonl-tailer", etc.
- **Access:** `make logs` (tail -f stderr.log) or Console.app

**Health Monitoring:**

- **HTTP health endpoint:** GET `/health` (port 8780, localhost only)
- **Response:** JSON with status, uptime_seconds, rss_mb, subsystem statuses, audio routing diagnostics
- **Check interval:** Makefile health check (make health), manual testing
- **Status fields:** bot (running/error), tts (idle/synthesis), subtitle (hidden/visible)

## CI/CD & Deployment

**Hosting:**

- **Platform:** launchd (macOS user agent service)
- **Service name:** `com.terryli.claude-tts-companion`
- **Binary path:** `~/.local/bin/claude-tts-companion`
- **Control:** launchctl (load/unload/restart)

**Deployment Pipeline:**

- **Build:** `make build` (swift build -c release)
- **Deploy:** `make deploy` (copy binary + bootout + bootstrap)
- **Restart:** `make restart` (launchctl kickstart)
- **All-in-one:** `make all` (build + deploy)
- **Restart behavior:** KeepAlive with NetworkState (respawn on crash, not on clean exit)
- **Process type:** Adaptive (auto-suspend when idle)
- **Startup:** RunAtLoad true (starts on login)

**CI/CD:**

- None (no GitHub Actions, Jenkins, or cloud CI)
- Local-only via Makefile

## Environment Configuration

**Required Environment Variables (plist):**

- `TELEGRAM_BOT_TOKEN` - Bot token (must be set before service starts)
- `TELEGRAM_CHAT_ID` - Notification chat ID
- `MINIMAX_API_KEY` - API key for summaries

**Optional Environment Variables (Config.swift defaults):**

- `KOKORO_MODEL_PATH` - Model directory (default: `~/.local/share/kokoro/models/kokoro-int8-multi-lang-v1_0`)
- `STREAMING_TTS` - true|false (default: true)
- `KOKORO_TTS_SERVER_URL` - Python server URL (default: `http://127.0.0.1:8779`)
- `CLAUDE_NOTIFICATION_DIR` - Notification JSON path (default: `~/.claude/notifications`)
- `CLAUDE_PROJECTS_DIR` - Transcript JSONL path (default: `~/.claude/projects`)
- `CLAUDE_CLI_PATH` - claude CLI binary (default: `/usr/local/bin/claude`)

**Secrets Location:**

- **Repository:** `launchd/com.terryli.claude-tts-companion.plist` (empty in repo, populated at deployment)
- **Runtime:** launchd EnvironmentVariables dict (read by process on start)
- **Persistence:** macOS Keychain (not used; tokens stored in launchd plist only)

## Webhooks & Callbacks

**Incoming:**

- **Telegram callbacks:** Inline button presses from `/sessions` command (BotDispatcher, line 68 TelegramBot.swift)
- **Format:** TGUpdate.callbackQuery (processed in TelegramBotCallbacks.swift)
- **Transport:** Long polling (not webhooks; no public endpoint needed)

**Outgoing:**

- **To Telegram:** sendMessage (text, HTML parse mode), sendPhoto, editMessageText, answerCallbackQuery
- **To MiniMax API:** POST /v1/messages (summary generation)
- **To Python TTS server:** POST to `$KOKORO_TTS_SERVER_URL` (synthesis via HTTP, not webhook)

---

_Integration audit: 2026-04-02_
