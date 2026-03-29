<!-- # SSoT-OK -->

# Requirements: claude-tts-companion v4.9.0

**Defined:** 2026-03-28
**Core Value:** See what Claude says, anywhere -- real-time karaoke subtitles synced with TTS playback
**Milestone:** v4.9.0 SwiftBar UI & Telegram Bot Activation

## v4.9.0 Requirements

### SwiftBar UI

- [x] **BAR-10**: SwiftBar shows Python TTS server health (green/red dot + PID + RSS) alongside Swift companion in Service section
- [x] **BAR-11**: Voice and Speed settings propagate from SwiftBar through Swift companion to Python server
- [x] **BAR-12**: Bot subsystem status shows "connected" (green) or "disabled" (grey) -- never "unknown"

### Telegram Bot Activation

- [ ] **BOT-10**: TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID set in claude-tts-companion launchd plist (from ~/.claude/.secrets/ccterrybot-telegram)
- [ ] **BOT-11**: Bot connects via long polling and responds to /status within 5 seconds of service start
- [ ] **BOT-12**: Session-end notifications send Arc Summary + Tail Brief to Telegram with rich HTML formatting

### End-to-End Integration

- [ ] **E2E-01**: Full chain: session ends -> notification -> summary -> TTS via Python -> karaoke subtitles -> Telegram message
- [ ] **E2E-02**: TTS audio plays with native word-level karaoke (Python MToken onsets) during E2E flow
- [ ] **E2E-03**: tts_kokoro.sh CLI works end-to-end (regression check)

### Audio Device Resilience

- [x] **AUDIO-01**: CoreAudio HAL listener fires immediately when default output device changes (Bluetooth, HDMI, speaker switch)
- [x] **AUDIO-02**: Full AVAudioEngine teardown + rebuild (detach/reset/re-attach/connect/prepare/start) on device change
- [x] **AUDIO-03**: 200ms debounce + 5s cooldown prevents rebuild storms during rapid device flapping
- [x] **AUDIO-04**: AVAudioEngineConfigurationChange notification feeds into same debounced rebuild path as HAL listener
- [ ] **AUDIO-05**: 30-second periodic health check detects device mismatch when HAL/notification both miss a change
- [ ] **AUDIO-06**: Device ID + name logged on every engine start, rebuild, and health check mismatch

## Future Requirements

- MiniMax API key refresh
- Telegram inline button E2E verification (already implemented)

## Out of Scope

- Rewriting SwiftBar plugin in Swift
- Multi-user Telegram bot
- Custom SwiftBar icon

## Traceability

| Requirement | Phase    | Status   |
| ----------- | -------- | -------- |
| BOT-10      | Phase 29 | Pending  |
| BOT-11      | Phase 29 | Pending  |
| BOT-12      | Phase 29 | Pending  |
| BAR-10      | Phase 30 | Complete |
| BAR-11      | Phase 30 | Complete |
| BAR-12      | Phase 30 | Complete |
| E2E-01      | Phase 31 | Pending  |
| E2E-02      | Phase 31 | Pending  |
| E2E-03      | Phase 31 | Pending  |
| AUDIO-01    | Phase 32 | Complete |
| AUDIO-02    | Phase 32 | Complete |
| AUDIO-03    | Phase 32 | Complete |
| AUDIO-04    | Phase 32 | Complete |
| AUDIO-05    | Phase 32 | Pending  |
| AUDIO-06    | Phase 32 | Pending  |
