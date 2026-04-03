# Roadmap: claude-tts-companion — Notification Intelligence

## Overview

This milestone transforms the companion's notification pipeline from fire-once to a self-correcting three-stage lifecycle (Fire-Improve-Finalize) that eliminates the 79-second transcript staleness gap. The build order follows strict dependency chains: consolidate to a single consumer, build edit infrastructure, wire the re-check and tail watcher, then deliver independent improvements to Q&A, SwiftBar UX, and message quality.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Single-Consumer Consolidation** - Remove Bun bot notification watcher, establish companion as sole consumer
- [ ] **Phase 2: Message ID & Edit Infrastructure** - sendSessionNotification returns message ID, editSessionNotification preserves inline keyboard
- [ ] **Phase 3: Parse-Then-Edit Re-check** - 3-second re-check with material change detection prevents stale initial notifications
- [ ] **Phase 4: Three-Stage Lifecycle Orchestration** - Wire Fire-Improve-Finalize pipeline end-to-end in handleNotification
- [ ] **Phase 5: JSONL Tail Watcher & TTS Re-dispatch** - Event-driven transcript growth detection with debounced re-summarization
- [ ] **Phase 6: Q&A Enhancements** - Tail-based context, turn-count metadata, chained follow-ups, better errors
- [ ] **Phase 7: SwiftBar UX Polish** - SSH tunnel health, device name display, service PID visibility
- [ ] **Phase 8: Message Quality Hardening** - Eliminate all vague fallback messages across auto-continue and summarizer

## Phase Details

### Phase 1: Single-Consumer Consolidation

**Goal**: Companion owns the entire notification lifecycle with no competing consumers
**Depends on**: Nothing (first phase)
**Requirements**: NOTIF-01
**Success Criteria** (what must be TRUE):

1. Bun bot no longer watches the notification directory or sends session-end Telegram messages
2. Bun bot /prompt and /sessions commands still work after watcher removal
3. Companion receives and processes every session-end notification without duplicates

**Plans**: 1 plan

Plans:

- [ ] 01-01-PLAN.md — Remove Bun bot notification watcher, deprecate notification-watcher.ts

### Phase 2: Message ID & Edit Infrastructure

**Goal**: Session notifications can be edited in-place after initial send
**Depends on**: Phase 1
**Requirements**: NOTIF-02, NOTIF-04
**Success Criteria** (what must be TRUE):

1. sendSessionNotification returns the Telegram message ID (Int) after sending
2. editSessionNotification edits the message text while preserving all inline keyboard buttons
3. Editing a message with identical text is handled gracefully (no error log, no circuit breaker trigger)
   **Plans**: TBD

### Phase 3: Parse-Then-Edit Re-check

**Goal**: Notifications self-correct within 3 seconds when transcript has grown since initial send
**Depends on**: Phase 2
**Requirements**: NOTIF-03, NOTIF-05
**Success Criteria** (what must be TRUE):

1. 3 seconds after initial notification, the companion re-reads the transcript and compares against the initial state
2. If the last turn changed, the companion re-summarizes and edits the Telegram message in-place
3. No edit fires when transcript content has not materially changed (structured field comparison)
   **Plans**: TBD

### Phase 4: Three-Stage Lifecycle Orchestration

**Goal**: handleNotification orchestrates Fire-Improve-Finalize as a single coherent pipeline
**Depends on**: Phase 3
**Requirements**: NOTIF-09
**Success Criteria** (what must be TRUE):

1. Session notification follows the three-stage lifecycle: Fire at T+0.2s, Improve at T+3.5s, Finalize at T+87s
2. Each stage is idempotent -- a crash between stages leaves the user with the best notification available so far
3. The pipeline state (message ID, initial transcript size, keyboard) flows cleanly between stages without global mutable state
   **Plans**: TBD

### Phase 5: JSONL Tail Watcher & TTS Re-dispatch

**Goal**: Transcript growth after initial notification triggers accurate final summary with optional TTS
**Depends on**: Phase 4
**Requirements**: NOTIF-06, NOTIF-07, NOTIF-08, NOTIF-10
**Success Criteria** (what must be TRUE):

1. TranscriptTailWatcher detects JSONL file growth via DispatchSource and debounces rapid writes
2. When transcript stabilizes, the watcher triggers re-summarization and edits the Telegram message
3. Tail watcher self-terminates after 5 minutes or when JSONL stops growing for 10 seconds
4. TTS is re-dispatched at Finalize stage only when the tail brief changed by more than 20% in length
   **Plans**: TBD

### Phase 6: Q&A Enhancements

**Goal**: Ask About This delivers accurate, contextual answers with multi-turn conversation support
**Depends on**: Phase 1
**Requirements**: QA-01, QA-02, QA-03, QA-04
**Success Criteria** (what must be TRUE):

1. Q&A context window uses the last N turns of the transcript (tail), not the first N turns (head)
2. MiniMax system prompt includes turn-count metadata to prevent hallucination on short sessions
3. Replying to a bot Q&A answer continues the conversation with full history context
4. Q&A errors display the MiniMax model name and truncated error details to the user
   **Plans**: TBD

### Phase 7: SwiftBar UX Polish

**Goal**: SwiftBar control center shows accurate, real-time service health without legacy artifacts
**Depends on**: Nothing (independent)
**Requirements**: UX-01, UX-02, UX-03
**Success Criteria** (what must be TRUE):

1. SSH tunnel status shows green/orange/red based on actual ClickHouse connectivity (lsof + curl check)
2. No "kokoro-tts-mlx" ghost references appear; TTS section shows actual device name from health endpoint
3. Service section shows PID for all running services (companion, kokoro-tts-server, ssh-tunnel)
   **Plans**: TBD
   **UI hint**: yes

### Phase 8: Message Quality Hardening

**Goal**: Every notification and auto-continue message is self-explanatory with no vague fallbacks
**Depends on**: Nothing (independent)
**Requirements**: MSG-01, MSG-02, MSG-03
**Success Criteria** (what must be TRUE):

1. All auto-continue messages include iteration count, elapsed time, and turn count
2. All summarizer fallbacks explain why summary is unavailable (circuit breaker state, empty result, API error details)
3. grep across Swift and TypeScript sources returns zero matches for "No reason provided", "Session completed.", or "Continue as planned"
   **Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8
Note: Phases 6, 7, 8 are independent of each other and only depend on Phase 1 (6) or nothing (7, 8).

| Phase                                   | Plans Complete | Status      | Completed |
| --------------------------------------- | -------------- | ----------- | --------- |
| 1. Single-Consumer Consolidation        | 0/1            | Not started | -         |
| 2. Message ID & Edit Infrastructure     | 0/0            | Not started | -         |
| 3. Parse-Then-Edit Re-check             | 0/0            | Not started | -         |
| 4. Three-Stage Lifecycle Orchestration  | 0/0            | Not started | -         |
| 5. JSONL Tail Watcher & TTS Re-dispatch | 0/0            | Not started | -         |
| 6. Q&A Enhancements                     | 0/0            | Not started | -         |
| 7. SwiftBar UX Polish                   | 0/0            | Not started | -         |
| 8. Message Quality Hardening            | 0/0            | Not started | -         |
