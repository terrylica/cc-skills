---
status: awaiting_human_verify
trigger: "MiniMax TTS for Telegram summaries is no longer working. Instead, macOS say command produces a bad robotic voice."
created: 2026-03-26T18:40:00-0700
updated: 2026-03-26T18:40:00-0700
---

## Current Focus

hypothesis: Two independent issues cause the broken TTS: (1) notification directory mismatch between stop hook writer and new service watcher, and (2) CNS notification hook unconditionally uses macOS `say` for folder announcement
test: Verify the stop hook writes to a different path than the new service watches
expecting: Mismatch confirmed = root cause of MiniMax/Kokoro not triggering
next_action: Fix the stop hook to write to the correct directory OR fix the new service to watch the correct directory

## Symptoms

expected: When a Claude Code session ends, the system should generate a MiniMax summary, then speak it using Kokoro TTS (af_heart voice) with karaoke subtitles
actual: macOS `say` command is being used instead -- produces bad robotic voice. MiniMax summaries may not be generating either.
errors: New service Telegram bot logs continuous "BotError - No description provided" errors. No notification files ever reach the new service.
reproduction: End a Claude Code session and observe what happens
started: Started after deploying claude-tts-companion unified service (2026-03-26)

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-03-26T18:40:00-0700
  checked: Stop hook telegram-notify-stop.ts notification output path
  found: Writes to ~/.claude/automation/claude-telegram-sync/state/notifications/{sessionId}.json
  implication: This is the OLD path used by the old TypeScript Telegram bot

- timestamp: 2026-03-26T18:40:00-0700
  checked: New claude-tts-companion Config.swift notification watch directory
  found: Watches ~/.claude/notifications/ (Config.swift line 90)
  implication: DIRECTORY MISMATCH - new service never sees notification files written by stop hook

- timestamp: 2026-03-26T18:40:00-0700
  checked: CNS cns_notification_hook.sh
  found: Lines 54-56 unconditionally use macOS `say` command for folder announcement after jingle
  implication: This is the "bad robotic voice" the user hears - it's a separate system from TTS/Telegram

- timestamp: 2026-03-26T18:40:00-0700
  checked: Old services (telegram-bot, kokoro-tts-server)
  found: Not running in launchctl. Only claude-tts-companion (PID 86695) is active.
  implication: Old consumer of notification files is gone; new consumer watches wrong directory

- timestamp: 2026-03-26T18:40:00-0700
  checked: claude-tts-companion stderr logs
  found: Telegram bot has continuous BotError errors every ~30s since startup. Notification watcher started on ~/.claude/notifications/ but directory is empty.
  implication: Even if notifications arrived, the Telegram bot has its own issues (likely separate bug)

- timestamp: 2026-03-26T18:45:00-0700
  checked: JSON key names in notification files vs main.swift parsing
  found: Stop hook writes camelCase (sessionId, transcriptPath) but main.swift reads snake_case (session_id, transcript_path)
  implication: Session ID resolves to "unknown", transcript path is nil -- MiniMax summary never generates

- timestamp: 2026-03-26T18:50:00-0700
  checked: Telegram getUpdates API directly
  found: HTTP 409 "Conflict: terminated by other getUpdates request; make sure that only one bot instance is running"
  implication: Old TypeScript bot (PID 82476, bun --watch) still running and polling same token

- timestamp: 2026-03-26T18:50:00-0700
  checked: ps aux for old telegram bot
  found: PID 82476: bun --watch run ~/.claude/automation/claude-telegram-sync/src/main.ts (parent PID 1, orphaned process)
  implication: Old bot must be killed for new service's Telegram bot to work

- timestamp: 2026-03-26T18:40:00-0700
  checked: /tmp/telegram-stop-hook.log (recent entries)
  found: Stop hook IS firing and writing notification files successfully to the old path
  implication: The hook works; the problem is purely a directory mismatch

## Resolution

root_cause: Three bugs prevent MiniMax/Kokoro TTS from triggering: (1) Directory mismatch -- stop hook wrote to ~/.claude/automation/claude-telegram-sync/state/notifications/ but new service watches ~/.claude/notifications/. (2) JSON key mismatch -- stop hook writes camelCase (sessionId, transcriptPath) but main.swift read snake_case (session_id, transcript_path). (3) Old TypeScript bot (PID 82476) still running and polling same Telegram token, causing HTTP 409 conflicts for the new service. Additionally, the CNS cns_notification_hook.sh uses macOS `say` for folder announcement (the "bad robotic voice"), but this is a separate notification system.
fix: (1) Updated telegram-notify-stop.ts to write to ~/.claude/notifications/. (2) Updated main.swift to read both camelCase and snake_case JSON keys. (3) Need to kill old bot process and remove/disable old launchd plist.
verification: Pending -- kill old bot, then test with a real session end
files_changed: [plugins/tts-tg-sync/hooks/telegram-notify-stop.ts, plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift]
