<!-- # SSoT-OK -->

# Requirements: claude-tts-companion v4.9.0

**Defined:** 2026-03-28
**Core Value:** See what Claude says, anywhere — real-time karaoke subtitles synced with TTS playback
**Milestone:** v4.9.0 SwiftBar UI & Telegram Bot Activation

## v4.9.0 Requirements

### SwiftBar UI

- [ ] **BAR-10**: SwiftBar shows Python TTS server health (green/red dot + PID + RSS) alongside Swift companion in Service section
- [ ] **BAR-11**: Voice and Speed settings propagate from SwiftBar through Swift companion to Python server
- [ ] **BAR-12**: Bot subsystem status shows "connected" (green) or "disabled" (grey) — never "unknown"

### Telegram Bot Activation

- [ ] **BOT-10**: TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID set in claude-tts-companion launchd plist (from ~/.claude/.secrets/ccterrybot-telegram)
- [ ] **BOT-11**: Bot connects via long polling and responds to /status within 5 seconds of service start
- [ ] **BOT-12**: Session-end notifications send Arc Summary + Tail Brief to Telegram with rich HTML formatting

### End-to-End Integration

- [ ] **E2E-01**: Full chain: session ends → notification → summary → TTS via Python → karaoke subtitles → Telegram message
- [ ] **E2E-02**: TTS audio plays with native word-level karaoke (Python MToken onsets) during E2E flow
- [ ] **E2E-03**: tts_kokoro.sh CLI works end-to-end (regression check)

## Future Requirements

- MiniMax API key refresh
- Telegram inline button E2E verification (already implemented)

## Out of Scope

- Rewriting SwiftBar plugin in Swift
- Multi-user Telegram bot
- Custom SwiftBar icon

## Traceability

| Requirement | Phase    | Status  |
| ----------- | -------- | ------- |
| BOT-10      | Phase 29 | Pending |
| BOT-11      | Phase 29 | Pending |
| BOT-12      | Phase 29 | Pending |
| BAR-10      | Phase 30 | Pending |
| BAR-11      | Phase 30 | Pending |
| BAR-12      | Phase 30 | Pending |
| E2E-01      | Phase 31 | Pending |
| E2E-02      | Phase 31 | Pending |
| E2E-03      | Phase 31 | Pending |
