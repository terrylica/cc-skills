# Requirements: claude-tts-companion — Notification Intelligence

**Defined:** 2026-04-02
**Core Value:** Every session end produces an accurate, self-explanatory notification

## v1 Requirements

### Notification Pipeline

- [ ] **NOTIF-01**: Companion is the sole notification consumer (Bun bot notification watcher removed)
- [ ] **NOTIF-02**: Session summary Telegram message is editable (sendSessionNotification returns message ID)
- [ ] **NOTIF-03**: 3-second re-check compares transcript state and edits Telegram message if last turn changed
- [ ] **NOTIF-04**: Inline keyboard is preserved on all editMessageText calls (re-attached explicitly)
- [ ] **NOTIF-05**: Material change detection prevents unnecessary edits (structured field comparison)
- [ ] **NOTIF-06**: JSONL tail watcher detects transcript growth after notification sent (DispatchSource + debounce)
- [ ] **NOTIF-07**: Tail watcher triggers re-summarization and edits Telegram message when transcript stabilizes
- [ ] **NOTIF-08**: Tail watcher self-terminates after 5 minutes or when JSONL stops growing for 10 seconds
- [ ] **NOTIF-09**: Three-stage lifecycle: Fire (T+0.2s initial send), Improve (T+3.5s re-check), Finalize (T+87s tail watcher)
- [ ] **NOTIF-10**: TTS re-dispatched on material change at Finalize stage (>20% length delta)

### Interactive Q&A

- [ ] **QA-01**: MiniMax Q&A context uses tail N turns (most recent), not head N turns
- [ ] **QA-02**: Turn-count metadata included in MiniMax system prompt to prevent hallucination on short sessions
- [ ] **QA-03**: Chained follow-ups with conversation history (replies to bot's answer continue the context)
- [ ] **QA-04**: Q&A error messages include MiniMax model name and truncated error details

### SwiftBar UX

- [ ] **UX-01**: SSH tunnel status shows green/orange/red based on actual ClickHouse connectivity via lsof + curl
- [ ] **UX-02**: No "kokoro-tts-mlx" ghost references in SwiftBar (show device name from health endpoint)
- [ ] **UX-03**: Service section shows PID for all running services (companion, kokoro-tts-server, ssh-tunnel)

### Message Quality

- [ ] **MSG-01**: All auto-continue messages include context (iteration count, elapsed time, turn count)
- [ ] **MSG-02**: All summarizer fallbacks explain WHY summary is unavailable (circuit breaker, empty result, API error)
- [ ] **MSG-03**: No "No reason provided", "Session completed.", or "Continue as planned" fallback messages remain

## v2 Requirements

### Advanced Q&A

- **QA-05**: Multi-session selection (ask about a specific past session, not just the latest)
- **QA-06**: Session search by keyword across recent transcripts

### Notification Enrichment

- **NOTIF-11**: Session-aware SwiftBar indicators (show active session count in menu bar)
- **NOTIF-12**: Real-time notification streaming (draft message updated as session progresses, not batch on end)

## Out of Scope

| Feature                          | Reason                                                                 |
| -------------------------------- | ---------------------------------------------------------------------- |
| Bun bot as notification consumer | Consolidating to companion-only; Bun bot retains /prompt and /sessions |
| Multi-user monitoring            | Personal infrastructure, not SaaS                                      |
| iOS/mobile companion             | macOS only                                                             |
| Real-time streaming summaries    | Batch on session-end; v2 candidate                                     |
| sendMessageDraft (Bot API 9.5)   | swift-telegram-sdk v4.5.0 doesn't support it yet                       |

## Traceability

| REQ-ID                    | Phase |
| ------------------------- | ----- |
| (Populated by roadmapper) |       |

---

_Requirements defined: 2026-04-02_
