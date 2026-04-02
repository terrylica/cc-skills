# Technology Stack: Notification Intelligence

**Project:** claude-tts-companion (notification intelligence milestone)
**Researched:** 2026-04-02
**Overall Confidence:** HIGH

This research covers four specific technical domains needed for the notification intelligence milestone: file-size polling/stabilization, Telegram message editing, JSONL tailing, and cross-process notification dedup.

---

## 1. File-Size Polling & Stabilization Detection

**Problem:** Stop hook fires ~79 seconds before Claude Code finishes writing the JSONL transcript. The companion reads immediately and gets stale content.

**Solution:** Parse-then-edit with DispatchSource timer polling for file size stabilization.

### Recommended Pattern: DispatchSourceTimer + FileManager.attributesOfItem

Use `DispatchSource.makeTimerSource` (already used in `NotificationWatcher.swift`) with `FileManager.attributesOfItem(atPath:)` to poll file size until stable.

```swift
/// Polls a file until its size stops growing for `stableDuration` seconds.
/// Calls `onStable` once with the final file size.
final class FileSizeStabilizer: @unchecked Sendable {
    private let filePath: String
    private let stableDuration: TimeInterval  // e.g. 3.0 seconds
    private let pollInterval: TimeInterval     // e.g. 0.5 seconds
    private let maxWait: TimeInterval          // e.g. 90.0 seconds (safety cap)
    private var timer: DispatchSourceTimer?
    private var lastSize: UInt64 = 0
    private var lastChangeTime: Date = Date()
    private var startTime: Date = Date()
    private let lock = NSLock()

    init(filePath: String, stableDuration: TimeInterval = 3.0,
         pollInterval: TimeInterval = 0.5, maxWait: TimeInterval = 90.0) {
        self.filePath = filePath
        self.stableDuration = stableDuration
        self.pollInterval = pollInterval
        self.maxWait = maxWait
    }

    func waitForStable(onStable: @escaping (UInt64) -> Void) {
        startTime = Date()
        lastSize = currentFileSize()
        lastChangeTime = Date()

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let now = Date()
            let size = self.currentFileSize()

            self.lock.lock()
            if size != self.lastSize {
                self.lastSize = size
                self.lastChangeTime = now
            }
            let elapsed = now.timeIntervalSince(self.lastChangeTime)
            let totalElapsed = now.timeIntervalSince(self.startTime)
            self.lock.unlock()

            if elapsed >= self.stableDuration || totalElapsed >= self.maxWait {
                self.timer?.cancel()
                self.timer = nil
                onStable(size)
            }
        }
        self.timer = timer
        timer.resume()
    }

    func cancel() {
        timer?.cancel()
        timer = nil
    }

    private func currentFileSize() -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
              let size = attrs[.size] as? UInt64 else { return 0 }
        return size
    }
}
```

**Why this pattern:**

| Criterion                 | DispatchSourceTimer                        | DispatchSource.write                       | FSEvents                            |
| ------------------------- | ------------------------------------------ | ------------------------------------------ | ----------------------------------- |
| Reliable for size checks  | YES -- poll guarantees read                | Fires on write but NOT guaranteed per-byte | Fires on metadata change, coalesced |
| Already in codebase       | YES (NotificationWatcher)                  | YES (JSONLTailer)                          | No                                  |
| CPU cost at 0.5s interval | Negligible (<0.01% CPU)                    | Event-driven (lower)                       | Event-driven (lower)                |
| Correct for stabilization | YES -- explicit polling is the right model | Would need secondary timer anyway          | Would need secondary timer anyway   |

**Key design decisions:**

- **3-second stable duration** because the 79s gap means Claude Code is writing intermittently. 3s of no growth = high confidence it finished.
- **0.5s poll interval** because `attributesOfItem` is a single `stat()` syscall -- essentially free.
- **90s maxWait safety cap** because the observed gap is ~79s; 90s prevents infinite waiting if the file is being written by a long-running session.
- **NSLock** because this matches the existing thread-safety pattern in the codebase (JSONLTailer, NotificationProcessor, ThinkingWatcher all use NSLock).

### What NOT to Use

| Approach                                                              | Why Not                                                                                                              |
| --------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `DispatchSource.makeFileSystemObjectSource(.write)` for stabilization | `.write` events coalesce -- you might get one event for multiple writes, making "no more events = stable" unreliable |
| `kqueue` / `kevent` directly                                          | DispatchSource wraps kqueue with proper GCD integration. Raw kqueue adds complexity for zero benefit.                |
| `FileHandle.readabilityHandler`                                       | Designed for streaming reads, not size monitoring. Fires on every byte -- wrong abstraction.                         |
| Foundation `NSFilePresenter`                                          | Designed for document coordination between apps. Heavy, requires `NSFileCoordinator`. Overkill for stat-polling.     |
| `Process.waitUntilExit` on Claude Code                                | Cannot track Claude Code process -- companion has no process handle. Notifications arrive via file drop, not IPC.    |

---

## 2. Telegram Message Editing (editMessageText) via swift-telegram-sdk

**Problem:** Parse-then-edit pattern requires sending a message immediately, then editing it 3-79 seconds later with updated content.

**Status:** Already working in the codebase. `TelegramBot.editMessage(messageId:text:)` wraps `TGEditMessageTextParams`.

### Existing API (swift-telegram-sdk 4.5.0)

The codebase already has the correct pattern. The edit-in-place flow is:

```swift
// Step 1: Send initial message, capture message ID
let messageId = await bot.sendMessageReturningId(initialHtml)

// Step 2: Later, edit with updated content
if let msgId = messageId {
    await bot.editMessage(messageId: msgId, text: updatedHtml)
}
```

### Pattern for Staleness Fix: Parse-Then-Edit

```swift
/// Orchestrates the parse-then-edit flow for transcript staleness.
/// 1. Immediately parse transcript and send notification (may be stale)
/// 2. Start stabilization watcher on transcript file
/// 3. When stable, re-parse and edit the message if content changed
func sendWithStalenessCorrection(
    sessionId: String,
    transcriptPath: String,
    bot: TelegramBot,
    /* ... other params ... */
) async {
    // Phase 1: Immediate parse + send
    let initialTurns = TranscriptParser.parse(filePath: transcriptPath)
    let initialSize = fileSize(atPath: transcriptPath)
    let messageId = await bot.sendMessageReturningId(renderNotification(initialTurns))

    guard let msgId = messageId else { return }

    // Phase 2: Wait for transcript stabilization (3s stable window)
    let stabilizer = FileSizeStabilizer(filePath: transcriptPath, stableDuration: 3.0)
    stabilizer.waitForStable { [weak self] finalSize in
        guard finalSize > initialSize else { return }  // No growth = initial was accurate

        // Phase 3: Re-parse and edit
        let updatedTurns = TranscriptParser.parse(filePath: transcriptPath)
        let updatedHtml = self?.renderNotification(updatedTurns) ?? ""

        Task {
            await bot.editMessage(messageId: msgId, text: updatedHtml)
        }
    }
}
```

### Edit-with-Inline-Keyboard

When editing a message that has inline buttons, include the `replyMarkup` parameter to preserve the keyboard:

```swift
// Editing WITH keyboard preservation (already used in TelegramBotCallbacks.swift)
try await bot.editMessageText(params: TGEditMessageTextParams(
    chatId: .chat(chatId),
    messageId: messageId,
    text: updatedHtml,
    parseMode: .html,
    linkPreviewOptions: TGLinkPreviewOptions(isDisabled: true),
    replyMarkup: existingKeyboard  // Pass keyboard to preserve it
))
```

**Telegram API constraint:** `editMessageText` silently fails (HTTP 400 "message is not modified") if the new text is identical to the old text. The staleness fix should compare content before editing.

### What NOT to Do

| Anti-Pattern                     | Why                                                                                                   |
| -------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Delete + re-send instead of edit | User loses message position in chat; creates notification spam                                        |
| Edit without HTML fallback       | Telegram rejects malformed HTML with 400 -- always have a plain-text retry (already in `editMessage`) |
| Edit too frequently              | Telegram rate-limits edits to ~30/min per chat. The 3s stabilization window naturally prevents this.  |
| Skip the `replyMarkup` on edit   | Omitting `replyMarkup` removes the inline keyboard. Always pass the keyboard if the message has one.  |

---

## 3. JSONL Tailing with DispatchSource

**Problem:** The JSONL tail watcher must catch late transcript writes (up to 79s after stop hook) to supplement the stabilization approach.

**Status:** Already implemented in `JSONLTailer.swift`. Well-designed with offset tracking, partial-line handling, and NSLock.

### Current Implementation Assessment

The existing `JSONLTailer` is correct and production-validated. Key strengths:

- **O_EVTONLY file descriptor** -- read-only monitoring, does not prevent file deletion
- **Offset-based reads** -- only reads new bytes, never re-reads the entire file
- **Partial-line buffering** -- incomplete lines (no trailing newline) are re-read next event
- **Strong DispatchSource reference** -- prevents ARC deallocation mid-monitoring

### Enhancement for Staleness Fix: Callback with Parsed Entries

The staleness fix needs the JSONL tailer to feed parsed entries back to trigger re-summarization. The current callback signature `([String]) -> Void` is correct -- the consumer parses JSON lines.

```swift
// Wire JSONL tailer to trigger re-edit when new content arrives
let tailer = JSONLTailer(filePath: transcriptPath) { [weak self] newLines in
    guard let self = self else { return }

    // Parse new JSONL lines into transcript entries
    let newEntries = newLines.compactMap { line -> TranscriptEntry? in
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return TranscriptParser.parseEntry(json)
    }

    guard !newEntries.isEmpty else { return }

    // Trigger re-summarization and message edit
    self.handleNewTranscriptEntries(newEntries, messageId: messageId)
}
tailer.start()

// Stop after stabilization completes (avoid tailing forever)
// Use the FileSizeStabilizer's onStable callback to stop the tailer
```

### DispatchSource Lifecycle Warning

**The existing pattern has one subtle issue:** If the JSONL file is deleted and recreated (e.g., Claude Code starts a new session with the same path), the `O_EVTONLY` file descriptor points to the old inode. The `DispatchSource` will never fire again.

For the staleness fix this is a non-issue because:

1. Transcript files are never deleted during a session
2. The tailer is scoped to one notification lifecycle, not long-lived

But if reusing `JSONLTailer` for long-lived watching, add `.delete` and `.rename` to the event mask:

```swift
// For long-lived watchers (NOT needed for staleness fix)
let src = DispatchSource.makeFileSystemObjectSource(
    fileDescriptor: fd,
    eventMask: [.write, .delete, .rename],  // Detect file replacement
    queue: .global(qos: .userInitiated)
)
```

### What NOT to Use for JSONL Tailing

| Approach                                | Why Not                                                                                                  |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `FSEvents` API                          | Designed for directory-level bulk changes (Spotlight, Time Machine). Too coarse for single-file tailing. |
| `FileHandle.readabilityHandler`         | Fires synchronously on every available byte. No event coalescing, higher CPU for large writes.           |
| `Process("/usr/bin/tail", ["-f", ...])` | Subprocess for what is 50 lines of Swift. Harder to control lifecycle and parse output.                  |
| Polling with `Timer.scheduledTimer`     | Works but wastes CPU between writes. DispatchSource is event-driven and only fires on actual writes.     |
| `swift-nio` file watching               | Pulls in SwiftNIO dependency. Against the project constraint (no NIO).                                   |

---

## 4. Cross-Process Notification Dedup

**Problem:** Two processes consume notifications -- the companion (Swift, production) and the Bun bot (TypeScript, legacy). Consolidating to companion-only.

**Solution:** File-based locking + process elimination. No IPC library needed.

### Recommended Approach: Consolidate, Don't Coordinate

The PROJECT.md states the goal clearly: "consolidate to companion-only consumer (remove Bun bot notification watcher)." This is a code-deletion task, not a distributed-systems problem.

**Steps:**

1. Remove the notification watcher from the Bun bot (it only gets synthetic tests anyway)
2. Companion remains the sole consumer of `~/.claude/notifications/*.json`
3. No cross-process coordination needed because there is only one process

### If Temporary Coexistence Is Needed: shlock(1)

During the transition, if both processes must run but only one should process each notification, use `shlock(1)` -- a macOS system utility already used in the TTS pipeline (`tts_kokoro.sh`).

```swift
/// Acquire a file-based lock using shlock(1).
/// Returns true if lock acquired, false if another process holds it.
func acquireShlock(lockFile: String) -> Bool {
    let pid = ProcessInfo.processInfo.processIdentifier
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/shlock")
    process.arguments = ["-f", lockFile, "-p", "\(pid)"]
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

func releaseShlock(lockFile: String) {
    try? FileManager.default.removeItem(atPath: lockFile)
}

// Usage in notification handler:
let lockFile = "/tmp/claude-notification-\(filename).lock"
guard acquireShlock(lockFile: lockFile) else {
    logger.info("Skipping \(filename) -- another process holds lock")
    return
}
defer { releaseShlock(lockFile: lockFile) }
// ... process notification ...
```

**Why shlock over alternatives:**

| Mechanism                     | Pro                                                                      | Con                                                                                                 | Verdict                |
| ----------------------------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------- | ---------------------- |
| `shlock(1)`                   | Already used in project, macOS built-in, PID-based (stale lock recovery) | Subprocess call per lock                                                                            | USE during transition  |
| `flock(2)` / `fcntl(F_SETLK)` | Kernel-level, fast                                                       | Released on process exit (good), but Bun bot is Node.js -- cross-language advisory locks are tricky | Avoid                  |
| Named pipe / Unix socket IPC  | Real-time coordination                                                   | Requires both processes to implement a protocol. Massive overengineering for a transition period.   | No                     |
| Redis / SQLite                | Proper distributed lock                                                  | Adding a database dependency for 2-process coordination is absurd                                   | No                     |
| Delete-after-read             | First reader wins                                                        | Race condition: both processes stat the file simultaneously                                         | No                     |
| Rename-to-claim               | `rename()` is atomic                                                     | Bun bot would need to understand the same convention                                                | Acceptable alternative |

### In-Process Dedup (Already Implemented)

The existing `NotificationProcessor` handles in-process dedup correctly:

- **Session ID + transcript size** dedup prevents re-notifying for unchanged transcripts
- **Rate limiting** (5s minimum interval) prevents burst processing
- **Mutex gate** (isProcessing flag) prevents concurrent processing
- **TTL-based pruning** prevents unbounded memory growth

No changes needed to the in-process dedup for this milestone.

### What NOT to Do

| Anti-Pattern                          | Why                                                                                                                                                 |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Add a SQLite database for dedup state | In-memory `[String: DedupEntry]` with TTL pruning is correct for a single-process consumer. SQLite adds crash recovery complexity for zero benefit. |
| Use `NSDistributedNotificationCenter` | Cross-process but unreliable for coordination. Notifications can be dropped under load. Not a lock.                                                 |
| Implement a custom IPC protocol       | The goal is to REMOVE the second consumer, not build infrastructure to coordinate with it.                                                          |
| Keep both consumers permanently       | Architectural confusion. One SSoT consumer.                                                                                                         |

---

## Stack Summary for Roadmap

### No New Dependencies Required

All four domains use APIs already in the project:

| Domain                   | API                                                               | New Dependency? |
| ------------------------ | ----------------------------------------------------------------- | --------------- |
| File-size stabilization  | `DispatchSource.makeTimerSource` + `FileManager.attributesOfItem` | No              |
| Telegram message editing | `TGEditMessageTextParams` via swift-telegram-sdk 4.5.0            | No              |
| JSONL tailing            | `DispatchSource.makeFileSystemObjectSource(.write)`               | No              |
| Cross-process dedup      | Consolidation (code deletion) + optional `shlock(1)`              | No              |

### Thread Safety Pattern

All new code should follow the established codebase pattern:

```swift
// Codebase convention: NSLock + @unchecked Sendable for shared mutable state
final class MyComponent: @unchecked Sendable {
    private let lock = NSLock()
    private var mutableState: SomeType = ...

    func read() -> SomeType {
        lock.lock()
        defer { lock.unlock() }
        return mutableState
    }

    func write(_ value: SomeType) {
        lock.lock()
        mutableState = value
        lock.unlock()
    }
}
```

**Why NSLock, not Swift actors:** The codebase uses `@unchecked Sendable` + NSLock throughout (JSONLTailer, NotificationProcessor, ThinkingWatcher, CircuitBreaker). Mixing actors with the existing DispatchSource/GCD patterns would create re-entrancy issues and actor-hopping overhead. Stay consistent.

### Existing Patterns to Reuse

| Pattern                     | Source File                                                  | Reuse For                            |
| --------------------------- | ------------------------------------------------------------ | ------------------------------------ |
| Timer-based polling         | `NotificationWatcher.swift`                                  | File-size stabilization polling      |
| Event-driven file tailing   | `JSONLTailer.swift`                                          | Transcript tail watching             |
| Send-then-edit message flow | `TelegramBot.swift` `sendMessageReturningId` + `editMessage` | Parse-then-edit staleness correction |
| NSLock thread safety        | All `@unchecked Sendable` classes                            | New stabilizer component             |
| Dedup with TTL pruning      | `NotificationProcessor.swift`                                | Keep as-is, no changes               |

---

## Sources

- Codebase analysis: `JSONLTailer.swift`, `NotificationWatcher.swift`, `TelegramBot.swift`, `TelegramBotCallbacks.swift`, `NotificationProcessor.swift`, `ThinkingWatcher.swift`, `CompanionApp.swift`, `Config.swift` -- HIGH confidence (direct source code)
- swift-telegram-sdk 4.5.0 API: `TGEditMessageTextParams`, `TGSendMessageParams` -- HIGH confidence (used in production code)
- DispatchSource APIs: Apple Developer Documentation, macOS system frameworks -- HIGH confidence
- shlock(1): macOS man page, already used in `tts_kokoro.sh` -- HIGH confidence
- Telegram Bot API edit constraints: [Telegram Bot API docs](https://core.telegram.org/bots/api#editmessagetext) -- HIGH confidence

---

_Stack analysis: 2026-04-02_
