# Architecture: Notification Intelligence Pipeline

**Domain:** Notification pipeline restructuring (single-consumer, parse-then-edit, JSONL tail watcher)
**Researched:** 2026-04-02
**Confidence:** HIGH (all components exist in codebase; this is restructuring, not greenfield)

## Current State

The notification pipeline today is linear and fire-once:

```
Stop Hook writes JSON → NotificationWatcher polls (2s) → NotificationProcessor (dedup + rate limit)
  → CompanionApp.handleNotification → TranscriptParser.parse(filePath) → SummaryEngine (MiniMax)
  → TelegramBot.sendSessionNotification → TTS/Subtitles
```

**Problems being solved:**

1. **Dual consumer confusion**: Stop hook writes to `~/.claude/notifications/` (companion) AND Bun bot watches `state/notifications/` (legacy). Only companion is production; Bun bot gets synthetic tests only.
2. **Transcript staleness**: Stop hook fires ~79s before Claude Code finishes writing JSONL. Companion reads immediately, misses tail content. Summaries describe intermediate state, not final work.
3. **No self-correction**: Once a Telegram message is sent, it is never updated even if better data becomes available.

## Recommended Architecture

### Component Boundaries

| Component                               | Responsibility                                                  | Communicates With                                                   | Change Type                              |
| --------------------------------------- | --------------------------------------------------------------- | ------------------------------------------------------------------- | ---------------------------------------- |
| **NotificationWatcher**                 | Polls `~/.claude/notifications/` for new JSON files             | CompanionApp (callback)                                             | Unchanged                                |
| **NotificationProcessor**               | Dedup + rate-limit gate                                         | CompanionApp (called by)                                            | Unchanged                                |
| **CompanionApp.handleNotification**     | Orchestrates notification flow, schedules re-check              | TranscriptParser, SummaryEngine, TelegramBot, TranscriptTailWatcher | **Modified** -- adds re-check scheduling |
| **TranscriptParser**                    | Parses JSONL into entries/turns                                 | CompanionApp (called by)                                            | Unchanged                                |
| **SummaryEngine**                       | Generates Arc/Tail summaries via MiniMax                        | CompanionApp, TelegramBot (called by)                               | Unchanged                                |
| **TelegramBot.sendSessionNotification** | Sends Telegram message, returns message ID                      | CompanionApp (called by)                                            | **Modified** -- must return message ID   |
| **TelegramBot.editSessionNotification** | Edits existing Telegram message with updated summary            | CompanionApp (called by)                                            | **New**                                  |
| **TranscriptTailWatcher**               | Monitors transcript JSONL for growth after initial notification | CompanionApp (callback)                                             | **New**                                  |
| **Bun bot notification watcher**        | Watches `state/notifications/`                                  | N/A                                                                 | **Removed**                              |
| **Bun bot /prompt, /sessions**          | Telegram commands for ad-hoc queries                            | Telegram API directly                                               | **Retained** (separate process)          |

### Data Flow: Single-Consumer Consolidation

**What changes:**

The Bun bot's notification watching code is deleted. The companion is the sole consumer of `~/.claude/notifications/`. The Bun bot continues running for `/prompt` and `/sessions` commands only -- it becomes a stateless command handler, not a notification consumer.

```
BEFORE:
  Stop Hook → ~/.claude/notifications/*.json → Companion (production)
  Stop Hook → state/notifications/*.json     → Bun Bot (vestigial)

AFTER:
  Stop Hook → ~/.claude/notifications/*.json → Companion (sole consumer)
  Bun Bot   → /prompt, /sessions commands only (no file watching)
```

**Implementation:**

1. Remove the notification-watching code path from the Bun bot's TypeScript source
2. Remove `state/notifications/` directory creation and watching
3. Keep the Bun bot's Telegram command registration (`/prompt`, `/sessions`) intact
4. No changes to the companion's NotificationWatcher -- it already watches the correct directory

**Risk:** Low. The Bun bot's watcher is confirmed unused in production. Removing it is a deletion, not a refactor.

### Data Flow: Parse-Then-Edit Pattern

**Core idea:** Send the notification immediately with whatever transcript data is available (fast delivery), then re-read the transcript after a delay and edit the Telegram message if the summary changed (accuracy correction).

```
T=0s    Stop hook fires, writes notification JSON
T=0.2s  NotificationWatcher detects JSON, CompanionApp.handleNotification fires
T=0.5s  TranscriptParser reads JSONL (may be incomplete -- 79s gap)
T=1.0s  SummaryEngine generates Arc + Tail from available data
T=1.5s  TelegramBot.sendSessionNotification → Telegram message sent
        └─ Returns (chatId, messageId) tuple → stored in PendingEdit

T=3.5s  DispatchQueue.asyncAfter(3.0s) fires re-check
        └─ TranscriptParser re-reads JSONL
        └─ Compare transcript size: if unchanged, skip (no edit needed)
        └─ If grown: re-summarize, TelegramBot.editSessionNotification(messageId, newText)
        └─ TTS: if TBR changed, enqueue updated TTS (or skip if already played)

T=3.5s  TranscriptTailWatcher starts watching the JSONL file (see next section)
```

**Component changes:**

1. **TelegramBot.sendSessionNotification** must return `(chatId: Int64, messageId: Int)` instead of `Void`. The current `sendMessageWithKeyboard` already returns `messageId` -- just propagate it.

2. **TelegramBot.editSessionNotification** (new method):
   - Takes `messageId`, new `SessionNotificationData`, and the existing keyboard
   - Calls `bot.editMessageText(chatId:messageId:text:parseMode:replyMarkup:)`
   - swift-telegram-sdk exposes `editMessageText` via `TGBot` -- no new dependency needed

3. **CompanionApp.handleNotification** orchestration change:

   ```
   // After initial send:
   let sentMessageId = await bot.sendSessionNotification(...)

   // Schedule re-check after 3 seconds
   if let msgId = sentMessageId, let tp = transcriptPath {
       let initialSize = fileSize(tp)
       DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 3.0) {
           let currentSize = fileSize(tp)
           guard currentSize > initialSize else { return }  // No growth, skip

           // Re-parse, re-summarize, edit message
           let entries = TranscriptParser.parse(filePath: tp)
           let turns = TranscriptParser.entriesToTurns(entries)
           Task {
               let arc = await summaryEngine.arcSummary(turns: turns, cwd: cwd)
               let tail = await summaryEngine.tailBrief(turns: turns, cwd: cwd)
               await bot.editSessionNotification(messageId: msgId, ...)
               // Optionally re-TTS if tail changed significantly
           }
       }
   }
   ```

4. **PendingEdit tracking** (lightweight, no new file needed):
   - Store `(messageId, initialTranscriptSize, transcriptPath, sessionId)` in a local variable within the `handleNotification` closure scope
   - No persistent storage needed -- edits are fire-and-forget within the same notification lifecycle

**Confidence:** HIGH. `editMessageText` is a standard Telegram Bot API method. swift-telegram-sdk v4.5.0 supports it.

### Data Flow: JSONL Tail Watcher

**Core idea:** The 3s re-check catches most staleness, but the full 79s gap means some transcripts are still being written well after the initial notification. A JSONL tail watcher detects continued transcript growth and triggers re-summarization when the transcript stabilizes.

```
T=0s     Stop hook fires
T=0.2s   Notification detected, initial parse + send
T=3.5s   Re-check fires (catches partial growth)
T=3.5s   TranscriptTailWatcher.start(transcriptPath, messageId)
         └─ JSONLTailer monitors transcript for .write events
         └─ On each write: reset a 5s debounce timer
         └─ When debounce expires (no writes for 5s = transcript stable):
             └─ Compare final transcript size to last-summarized size
             └─ If grown: re-parse, re-summarize, edit Telegram message
             └─ Stop watching this transcript
T=~82s   Claude Code finishes writing → last .write event
T=~87s   Debounce timer expires → final re-summarization + edit
         └─ TranscriptTailWatcher self-terminates for this session
```

**New component: TranscriptTailWatcher**

```swift
/// Watches a specific transcript JSONL for post-notification growth.
/// Self-terminates after transcript stabilizes (no writes for debounce period).
/// Maximum lifetime: 5 minutes (safety valve against leaked watchers).
public final class TranscriptTailWatcher: @unchecked Sendable {
    let transcriptPath: String
    let messageId: Int           // Telegram message to edit
    let chatId: Int64
    let lastSummarizedSize: UInt64
    var tailer: JSONLTailer?
    var debounceTimer: DispatchSourceTimer?
    let debouncePeriod: TimeInterval = 5.0
    let maxLifetime: TimeInterval = 300.0  // 5 min safety valve
    let onStabilized: (String, UInt64) -> Void  // (transcriptPath, finalSize)
}
```

**Key design decisions:**

1. **Reuse JSONLTailer** -- already validated (spike 15, 0.34ms P95). Do NOT poll; use `DispatchSource.makeFileSystemObjectSource(.write)` via the existing `JSONLTailer` class. The ThinkingWatcher already uses this pattern successfully.

2. **Debounce, not immediate** -- Claude Code writes JSONL incrementally. Reacting to every write would spam MiniMax. Wait until writes stop for 5s (transcript stable) before re-summarizing.

3. **One watcher per notification** -- Each notification spawns one TranscriptTailWatcher. The watcher self-terminates after stabilization or after 5 minutes (safety valve). No global registry needed -- companion processes ~1-3 notifications concurrently.

4. **Edit, not re-send** -- Always edit the existing Telegram message. Users see one message that improves over time, not duplicate messages.

5. **TTS re-dispatch** -- Only re-dispatch TTS if the Tail Brief text changed by more than 20% (Levenshtein or simple length comparison). Avoid re-playing nearly-identical audio.

**Interaction with existing components:**

- `JSONLTailer` is reused unchanged (it already handles offset-based reading and partial line buffering)
- `NotificationProcessor.recordProcessed` updates the dedup entry with the final transcript size after tail watcher completes
- `ThinkingWatcher` operates on a different file and lifecycle (active during session, not after) -- no conflict

## Patterns to Follow

### Pattern: Fire-Improve-Finalize

The notification lifecycle becomes three stages, not one:

```
FIRE     (T+0.2s)  → Send immediately with available data
IMPROVE  (T+3.5s)  → Re-check, edit if transcript grew
FINALIZE (T+~87s)  → Tail watcher detects stability, final edit
```

Each stage is idempotent: if the transcript hasn't grown since the last stage, nothing happens. If the companion crashes between stages, users still have the initial notification (degraded accuracy, but not lost).

### Pattern: Return-and-Track Message IDs

Current `sendSessionNotification` returns `Void`. This must change to return the Telegram message ID for subsequent edits.

```swift
// BEFORE
func sendSessionNotification(...) async { ... }

// AFTER
func sendSessionNotification(...) async -> Int? {
    // ... existing logic ...
    let messageId = await sendMessageWithKeyboard(message, keyboard: keyboard)
    return messageId
}
```

The `sendMessageWithKeyboard` already returns `Int?` (message ID). Just propagate it.

### Pattern: Debounced File Watcher with Safety Valve

```swift
// On each JSONLTailer callback:
debounceTimer?.cancel()
debounceTimer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
debounceTimer.schedule(deadline: .now() + debouncePeriod)
debounceTimer.setEventHandler { [weak self] in self?.onStabilized() }
debounceTimer.resume()
```

The safety valve (5 min max lifetime) prevents leaked watchers if Claude Code writes indefinitely.

## Anti-Patterns to Avoid

### Anti-Pattern: Polling for Transcript Growth

**What:** Using a DispatchSourceTimer to poll file size every N seconds to detect transcript growth.
**Why bad:** NotificationWatcher already uses polling (2s interval). Adding more polling timers increases CPU wake-ups. The JSONLTailer's DispatchSource-based approach is event-driven and more efficient.
**Instead:** Use JSONLTailer (DispatchSource + O_EVTONLY) which fires only on actual writes.

### Anti-Pattern: Re-sending Instead of Editing

**What:** Sending a new Telegram message with the updated summary.
**Why bad:** Users see duplicate messages. The chat becomes noisy. Inline button state (Focus Tab dedup) breaks.
**Instead:** Always use `editMessageText` to update the existing message in-place.

### Anti-Pattern: Global Watcher Registry

**What:** Maintaining a dictionary of active TranscriptTailWatchers keyed by session ID.
**Why bad:** Adds complexity for cleanup, lifecycle management, and concurrency. The companion processes 1-3 notifications concurrently.
**Instead:** Each handleNotification closure owns its own TranscriptTailWatcher as a local variable. The watcher self-terminates. No registry needed.

### Anti-Pattern: Immediate TTS Re-dispatch on Every Edit

**What:** Re-playing TTS audio every time the transcript grows.
**Why bad:** User hears nearly-identical audio multiple times. Disruptive.
**Instead:** Only re-dispatch TTS on the FINALIZE stage if the Tail Brief changed significantly (>20% length delta). Skip re-TTS on the IMPROVE stage entirely.

## Build Order (Dependencies Between Changes)

The three features have clear dependency ordering:

### Phase 1: Single-Consumer Consolidation

**Prerequisite for:** Nothing (independent, can be done first)
**Changes:**

1. Remove Bun bot notification-watching code (TypeScript deletion)
2. Remove `state/notifications/` directory creation
3. Verify Bun bot `/prompt` and `/sessions` still work without watcher

**Risk:** LOW -- pure deletion of confirmed-dead code.

### Phase 2: Parse-Then-Edit (3s Re-check)

**Prerequisite for:** Phase 3 (tail watcher needs edit infrastructure)
**Changes:**

1. Modify `sendSessionNotification` to return `Int?` (message ID)
2. Add `editSessionNotification` method to TelegramBot
3. Add 3s re-check scheduling in `CompanionApp.handleNotification`
4. Update `NotificationProcessor.recordProcessed` to accept updated transcript size

**Risk:** MEDIUM -- requires Telegram API `editMessageText` integration. The method exists in swift-telegram-sdk but needs testing with HTML parse mode + inline keyboard preservation.

**Key verification needed:** Confirm that `editMessageText` preserves the inline keyboard (reply_markup) when editing. If not, the keyboard must be re-attached on each edit.

### Phase 3: JSONL Tail Watcher

**Prerequisite:** Phase 2 (needs editSessionNotification method)
**Changes:**

1. Create `TranscriptTailWatcher` class (new file)
2. Wire into `CompanionApp.handleNotification` after initial send
3. On stabilization callback: re-parse, re-summarize, call `editSessionNotification`
4. Update dedup entry with final transcript size
5. Add safety valve (5 min max lifetime, self-termination)

**Risk:** MEDIUM -- the debounce timer lifecycle and self-termination need careful testing to avoid leaked DispatchSources. The JSONLTailer itself is battle-tested.

## Scalability Considerations

| Concern           | Current (1-3 sessions)          | At 10 concurrent sessions                                    | Mitigation                                                                   |
| ----------------- | ------------------------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------------- |
| MiniMax API calls | 2 per notification (arc + tail) | 6 per notification (initial + re-check + finalize) x 10 = 60 | Circuit breaker already handles overload; debounce reduces unnecessary calls |
| File descriptors  | 1 per JSONLTailer               | 10 concurrent tail watchers = 10 FDs                         | O_EVTONLY FDs are cheap; 5 min safety valve prevents leaks                   |
| Telegram edits    | 0 edits today                   | 2 edits per notification x 10 = 20                           | Telegram rate limit is 30 msg/sec; editing is even less restricted           |
| Memory            | Negligible                      | TranscriptTailWatcher is ~200 bytes each                     | Not a concern                                                                |

## Sources

- `Sources/CompanionCore/JSONLTailer.swift` -- existing battle-tested offset-based JSONL tailing (spike 15)
- `Sources/CompanionCore/ThinkingWatcher.swift` -- existing pattern for JSONLTailer + MiniMax summarization
- `Sources/CompanionCore/TelegramBotNotifications.swift` -- current sendSessionNotification (returns Void)
- `Sources/CompanionCore/CompanionApp.swift` lines 248-384 -- current handleNotification flow
- `Sources/CompanionCore/NotificationProcessor.swift` -- dedup + rate-limit gate
- Telegram Bot API `editMessageText` -- [official docs](https://core.telegram.org/bots/api#editmessagetext)
- swift-telegram-sdk v4.5.0 -- exposes `editMessageText` via `TGBot` protocol

---

_Architecture analysis: 2026-04-02_
