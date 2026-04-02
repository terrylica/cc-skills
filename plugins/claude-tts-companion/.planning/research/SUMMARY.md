# Project Research Summary

**Project:** claude-tts-companion — Notification Intelligence Milestone
**Domain:** Brownfield enhancement — macOS companion app with self-correcting Telegram notifications
**Researched:** 2026-04-02
**Confidence:** HIGH

## Executive Summary

This milestone adds notification intelligence to a production Swift companion app (~7,500 LOC). The core problem is a 79-second staleness gap: the stop hook fires before Claude Code finishes writing JSONL transcripts, so the companion sends a notification summarizing incomplete session data. Research confirms the solution is a three-stage Fire-Improve-Finalize pipeline: send immediately (T+0.2s), re-check at 3 seconds, then run a tail watcher that debounces writes for up to 87 seconds until the transcript stabilizes. All required APIs (DispatchSourceTimer, DispatchSource file watching, Telegram editMessageText) are already present in the codebase — no new dependencies are needed.

The recommended implementation sequence is strictly ordered by dependency: first consolidate to a single notification consumer (remove the legacy Bun bot watcher), then implement parse-then-edit with the 3-second re-check (requires sendSessionNotification to return a message ID), then add the JSONL tail watcher as the final accuracy correction stage. The architecture research establishes this is a restructuring task, not greenfield — every component being added either modifies an existing class or wraps an already-validated building block (JSONLTailer, NSLock pattern, editMessage).

The two critical risks are Telegram API behavior and DispatchSource reliability. Telegram returns HTTP 400 "message is not modified" when editing unchanged content — the companion must compare text before calling editMessageText, and must always re-attach the inline keyboard or buttons will silently disappear. DispatchSource write events coalesce on macOS, meaning rapid writes produce a single event; a periodic safety poll every 10-30 seconds guards against dropped events. Both risks have clear, tested mitigations that can be implemented at the point of use.

## Key Findings

### Recommended Stack

No new dependencies are required for this milestone. The existing stack — DispatchSource.makeTimerSource for polling, DispatchSource.makeFileSystemObjectSource(.write) via JSONLTailer for event-driven file watching, TGEditMessageTextParams via swift-telegram-sdk 4.5.0, and NSLock + @unchecked Sendable for thread safety — covers every technical domain. The pattern of NSLock over Swift actors is established throughout the codebase (JSONLTailer, NotificationProcessor, ThinkingWatcher, CircuitBreaker) and must be continued to avoid re-entrancy issues with existing GCD/DispatchSource patterns.

**Core technologies:**

- `DispatchSource.makeTimerSource` + `FileManager.attributesOfItem`: file-size stabilization polling — identical pattern to NotificationWatcher.swift, zero new API surface
- `TGEditMessageTextParams` (swift-telegram-sdk 4.5.0): edit-in-place Telegram messages — already used in TelegramBotCallbacks.swift for prompt execution progress
- `JSONLTailer.swift`: offset-based JSONL tail watching — battle-tested (spike 15, 0.34ms P95), reuse unchanged
- `shlock(1)`: cross-process locking during Bun bot transition if needed — already used in tts_kokoro.sh, macOS built-in
- `NSLock` + `@unchecked Sendable`: thread safety — codebase convention, maintain for consistency

### Expected Features

**Must have (table stakes):**

- Edit-in-place on data improvement — Telegram's standard for self-correcting messages; stale summaries followed by a second message destroy trust
- Single-consumer consolidation — dual consumers (companion + Bun bot) cause architectural confusion; only companion owns message_id lifecycle
- Transcript-size-growth dedup — prevents re-notification for unchanged sessions; already implemented, preserve as-is
- Self-explanatory notification messages — "Session completed." fallbacks already eliminated (28 fixed 2026-04-02); no regression
- Callback query acknowledgment — Telegram UX requirement; already implemented

**Should have (differentiators):**

- Parse-then-edit with JSONL tail watcher — the core milestone deliverable; Fast delivery + silent self-correction for the 79s staleness gap
- Material change detection before editing — prevents meaningless edits when summary is unchanged
- Notification provenance metadata — small footer ("Updated: transcript grew from 45KB to 57KB") for transparency
- Chained follow-up Q&A conversations — multi-turn conversation history, builds on existing single-turn Q&A

**Defer (v2+):**

- Multi-session Q&A selector — single-session covers 90% of use cases; add "Ask" button to /sessions list later
- TTS re-synthesis on edit — niche use case, jarring; add feature gate now, implement when requested
- Session activity indicators in SwiftBar — independent work stream, not notification intelligence core
- Real-time streaming summaries — mid-session summaries are inaccurate by design; out of scope per PROJECT.md

### Architecture Approach

The notification pipeline transitions from linear/fire-once to a three-stage lifecycle pattern (Fire-Improve-Finalize). CompanionApp.handleNotification becomes the orchestration hub: it stores the returned message ID from the initial send, schedules a 3-second re-check via DispatchQueue.asyncAfter, and spawns a TranscriptTailWatcher that self-terminates after debounced stabilization (5s no-writes) or 5-minute safety valve. All three stages are idempotent — if the transcript did not grow, no edit fires. A crash between stages leaves users with the initial notification (degraded accuracy, not lost data).

**Major components:**

1. `TranscriptTailWatcher` (new) — wraps JSONLTailer with debounce logic + self-termination; one instance per notification lifecycle; no global registry needed
2. `TelegramBot.editSessionNotification` (new method) — wraps editMessageText with mandatory keyboard re-attachment; enforces the invariant that edits always preserve buttons
3. `TelegramBot.sendSessionNotification` (modified) — return type changes from Void to Int? to propagate message ID for subsequent edits
4. `CompanionApp.handleNotification` (modified) — orchestrates the three-stage flow; stores (messageId, initialSize, transcriptPath) in local closure scope, not a persistent registry
5. Bun bot notification watcher (deleted) — pure deletion of confirmed-dead code; /prompt and /sessions commands retained

### Critical Pitfalls

1. **"message is not modified" 400 on no-op edits** — Compare new summary text against initially sent text before calling editMessageText; catch the specific error string and downgrade to debug log to prevent log pollution and false circuit-breaker triggers
2. **Inline keyboard silently lost on edit** — Telegram removes buttons when replyMarkup is omitted from editMessageText; always store the TGInlineKeyboardMarkup alongside message ID and pass it on every edit call; write a dedicated editMessageWithKeyboard() method to enforce this invariant
3. **DispatchSource write events coalesce / drop** — macOS coalesces rapid writes into a single event and can drop events under buffer pressure; add a periodic safety poll (every 10-30s) calling readNewLines() unconditionally to catch dropped events; do not assume 1 event = 1 write
4. **FD becomes stale after file deletion/recreation** — O_EVTONLY FD references the old inode when file is replaced; monitor .delete and .rename events in addition to .write, and reopen + restart the tailer on inode change (lower risk for per-notification-scoped watchers but critical if JSONLTailer is used long-lived)
5. **Consumer consolidation breaks the stop hook contract silently** — removing the Bun bot watcher without a feature checklist causes silent notification loss; enumerate every Bun bot watcher behavior, verify each is handled by companion or explicitly out of scope, and test with a manual session stop before removing the code

## Implications for Roadmap

Based on research, the build order is strictly determined by component dependencies. Three phases with clean handoffs.

### Phase 1: Single-Consumer Consolidation

**Rationale:** Zero-dependency phase — no API changes required. The Bun bot's watcher is confirmed dead in production (gets synthetic tests only). Removing it establishes companion as the sole owner of the message_id lifecycle, which is a prerequisite for parse-then-edit correctness. The companion cannot reliably track which Telegram message to edit if another process might also send notifications.
**Delivers:** Clean single-process ownership of all notifications; Bun bot becomes a stateless command handler; foundation for reliable message ID tracking
**Addresses:** Notification dedup (single consumer) table-stakes feature; prerequisite from FEATURES.md dependency graph
**Avoids:** Pitfall 5 (silent notification contract breakage) — use feature checklist, test /prompt and /sessions post-removal
**Risk:** LOW — pure code deletion; Pitfall 10 (accidental command breakage) mitigated by touching only watcher code path

### Phase 2: Parse-Then-Edit (3-Second Re-check)

**Rationale:** Core mechanism for edit-in-place. Requires Phase 1 because only one process should own message IDs. The 3-second re-check catches the majority of growth cases and is simpler to validate than the full tail watcher. Establishes the editSessionNotification method and message ID tracking that Phase 3 will extend.
**Delivers:** Notifications that self-correct within 3 seconds of initial send; message ID propagation from send to edit; inline keyboard preservation on edit
**Uses:** TGEditMessageTextParams (swift-telegram-sdk 4.5.0, already in codebase); DispatchQueue.asyncAfter for 3s delay
**Implements:** sendSessionNotification return type change, new editSessionNotification method, PendingEdit tracking in closure scope
**Avoids:** Pitfall 1 (no-op edit 400) — compare text before editing; Pitfall 2 (rate limiting) — 3s gap is safe, add serial queue guard; Pitfall 8 (lost keyboard) — mandatory replyMarkup re-attachment
**Risk:** MEDIUM — Telegram API editMessageText with HTML parse mode + inline keyboard needs integration testing

### Phase 3: JSONL Tail Watcher (Full Staleness Correction)

**Rationale:** The 3-second re-check in Phase 2 catches early growth but the full 79-second gap requires an event-driven watcher that fires on actual writes. Phase 2's editSessionNotification method is a prerequisite. The tail watcher is the highest-complexity component because it involves debounce timer lifecycle, self-termination, and careful DispatchSource management.
**Delivers:** Fully accurate final notifications within ~87 seconds of stop hook; transcript stabilization detection; MiniMax re-summarization only when content materially changed
**Uses:** JSONLTailer.swift (existing, unchanged); DispatchSourceTimer for debounce; 5-minute safety valve
**Implements:** New TranscriptTailWatcher class; wiring into CompanionApp.handleNotification; dedup entry update with final transcript size
**Avoids:** Pitfall 3 (event coalescing) — periodic safety poll independent of DispatchSource; Pitfall 4 (stale FD) — scoped to single notification lifecycle so file recreation is low risk; TTS re-dispatch only on FINALIZE stage and only if tail brief changed >20%
**Risk:** MEDIUM — debounce timer lifecycle and DispatchSource cancellation need careful testing

### Phase 4: Q&A Enhancements (MiniMax Refinements)

**Rationale:** Independent from the staleness pipeline. Builds on existing single-turn Q&A infrastructure. Low dependency on Phases 1-3. Groups Q&A improvements together to minimize context-switching.
**Delivers:** Multi-turn conversation threading; hallucination reduction for short sessions; improved context window management (last N turns vs. first N)
**Addresses:** Chained follow-up Q&A differentiator feature; material change detection can be added alongside
**Avoids:** Pitfall 6 (context explosion) — send last 50K chars not first, cap at 30K; Pitfall 7 (hallucination on short sessions) — prepend turn count metadata, explicit "do not invent" instruction
**Risk:** LOW — additive changes to existing Q&A handler; no Telegram API changes

### Phase Ordering Rationale

- Phase 1 before Phase 2: message_id ownership requires single consumer; dual-consumer would race on which process tracks the ID
- Phase 2 before Phase 3: tail watcher needs editSessionNotification method that Phase 2 creates; Phase 3 is meaningless without the edit infrastructure
- Phases 1-3 before Phase 4: Q&A enhancements are independent and can be deferred; the staleness fix is the milestone's core value
- Each phase is independently deployable: Phase 1 reduces noise, Phase 2 adds self-correction, Phase 3 adds final accuracy, Phase 4 improves Q&A quality

### Research Flags

Phases likely needing deeper research during planning:

- **Phase 3 (JSONL Tail Watcher):** DispatchSource cancellation semantics during self-termination need verification against the existing JSONLTailer cancel() implementation; debounce timer + tailer interaction has subtle ordering requirements
- **Phase 2 (Parse-Then-Edit):** Confirm swift-telegram-sdk v4.5.0 TGEditMessageTextParams correctly preserves inline keyboard when replyMarkup is passed — one integration test before wiring into production path

Phases with standard patterns (skip research-phase):

- **Phase 1 (Consolidation):** Pure TypeScript code deletion; no research needed — grep the Bun bot source for notification watcher initialization, remove it, test
- **Phase 4 (Q&A Enhancements):** Well-understood prompt engineering; pitfalls 6 and 7 have prescriptive fixes; no novel API surface

## Confidence Assessment

| Area         | Confidence | Notes                                                                                                                                                                   |
| ------------ | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Stack        | HIGH       | All APIs are in-use in the production codebase; no new dependencies; spikes 03, 04, 08, 09, 10, 15 validate the building blocks                                         |
| Features     | HIGH       | Feature set derived from existing codebase analysis + official Telegram Bot API docs; no speculation about user preferences needed (single-user system)                 |
| Architecture | HIGH       | Direct codebase analysis of CompanionApp.swift, JSONLTailer.swift, TelegramBotNotifications.swift; component boundaries are clear; no third-party integration ambiguity |
| Pitfalls     | HIGH       | Pitfalls 1, 2, 8 documented from Telegram official API docs + existing codebase error handling; Pitfalls 3, 4 from Apple FSEvents docs + watchexec practical analysis   |

**Overall confidence:** HIGH

### Gaps to Address

- **editMessageText keyboard preservation:** Confirmed conceptually from Telegram API docs but needs one integration test in the actual swift-telegram-sdk v4.5.0 path before treating as verified. The existing TelegramBotCallbacks.swift already passes replyMarkup in some edit calls — check line 177 to confirm the pattern holds for HTML parse mode.
- **79-second gap variance:** The 79s figure is observed empirically on the developer's machine. Different session sizes, different hardware, or different Claude Code versions may produce different gaps. The 90-second maxWait safety cap in FileSizeStabilizer handles upward variance; document the assumption for future tuning.
- **Bun bot initialization coupling:** The Bun bot's TypeScript source needs inspection to confirm notification watcher and command handlers are not co-initialized in a single function. If they share state, Phase 1 deletion scope expands. Inspect before estimating Phase 1 effort.

## Sources

### Primary (HIGH confidence)

- `Sources/CompanionCore/JSONLTailer.swift` — offset-based JSONL tailing implementation
- `Sources/CompanionCore/TelegramBotNotifications.swift` — current sendSessionNotification (returns Void)
- `Sources/CompanionCore/CompanionApp.swift` lines 248-384 — handleNotification orchestration
- `Sources/CompanionCore/NotificationProcessor.swift` — dedup + rate-limit gate
- `Sources/CompanionCore/ThinkingWatcher.swift` — JSONLTailer + debounce pattern reference
- `Sources/CompanionCore/TelegramBot.swift` — editMessage implementation (line 177)
- [Telegram Bot API — editMessageText](https://core.telegram.org/bots/api#editmessagetext) — official edit constraints and rate limits
- [Apple DispatchSource Documentation](https://developer.apple.com/documentation/dispatch/dispatchsource) — cancel handler requirements, FD lifecycle
- [Apple FSEvents Programming Guide](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide) — event coalescing, MustScanSubDirs

### Secondary (MEDIUM confidence)

- [GramIO Rate Limits Guide](https://gramio.dev/rate-limits) — practical Telegram rate limit handling patterns (community consensus)
- [Watchexec macOS FSEvents Limitations](https://watchexec.github.io/docs/macos-fsevents.html) — practical FSEvents coalescing behavior in production tools
- [tdlib/td Issue #3034](https://github.com/tdlib/td/issues/3034) — editMessage rate limit discussion

### Tertiary (LOW confidence — needs validation)

- [arxiv: Hallucinate at the Last in Long Response Generation](https://arxiv.org/html/2505.15291) — positional hallucination bias in long documents (informs Pitfall 6 mitigation)
- [Context Window Limits and Hallucination](https://pr-peri.github.io/llm/2026/02/13/why-hallucination-happens.html) — 30K char quality degradation claim (needs validation against MiniMax specifically)

---

_Research completed: 2026-04-02_
_Ready for roadmap: yes_
