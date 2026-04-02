# Domain Pitfalls

**Domain:** Notification intelligence for macOS companion app (Telegram edit-in-place, JSONL tailing, consumer consolidation, interactive Q&A)
**Researched:** 2026-04-02

## Critical Pitfalls

Mistakes that cause rewrites or major issues.

### Pitfall 1: Telegram editMessageText "message is not modified" (400) on re-check edits

**What goes wrong:** The parse-then-edit flow sends an initial notification, waits 3s, re-parses the transcript, and edits the message with updated content. If the transcript did not change during those 3 seconds (common for short sessions), the edit payload is identical to the original. Telegram returns `400 Bad Request: message is not modified: specified new message content and reply markup are exactly the same as a current content and reply markup of the message`. The current `editMessage()` in `TelegramBot.swift` (line 177) catches errors but does not distinguish this expected 400 from genuine failures -- it falls through to the plain-text retry, which also fails identically, producing a noisy warning log on every short session.

**Why it happens:** Telegram validates content equality server-side. Unlike most APIs that silently accept no-op updates, Telegram treats unchanged edits as an error. The swift-telegram-sdk surfaces this as a thrown error, not a no-op return.

**Consequences:** Log pollution (two warnings per no-op edit), potential confusion with real edit failures, and if error-counting feeds into any circuit breaker or alerting, false positives.

**Prevention:**

1. Before calling `editMessageText`, compare the new text against the previously sent text. Skip the edit if equal. Store the sent text alongside the message ID in the edit-in-place tracking struct.
2. Alternatively, catch the specific error description containing "message is not modified" and downgrade to `logger.debug` instead of `logger.warning`.
3. Never blindly retry on 400 -- parse the error body first.

**Detection:** Grep logs for `"Failed to edit message"` -- if the rate correlates with short sessions, this pitfall is active.

**Phase:** Transcript staleness fix (parse-then-edit implementation).

---

### Pitfall 2: Telegram editMessageText rate limiting (429) during rapid re-edits

**What goes wrong:** The edit-in-place pattern (send initial, then edit with corrected summary) fires two API calls within 3 seconds for the same message. If the companion also has a PromptExecutor streaming edits (`editThrottleSeconds = 1.5s`), or multiple sessions end simultaneously, the combined edit rate exceeds Telegram's per-chat limit (~1 message/second soft limit). Telegram responds with `429 Too Many Requests` and a `retry_after` value (up to 35+ seconds), during which the bot is blocked from ALL API calls in that chat -- not just edits.

**Why it happens:** Telegram's rate limit is per-chat, not per-method. `editMessageText` costs ~8 rate-limit units, same bucket as `sendMessage`. Two near-simultaneous session-end notifications with edits can exhaust the budget. The current code has no global rate limiter -- each caller (PromptExecutor, NotificationProcessor, TelegramBot) independently calls Telegram.

**Consequences:** Bot goes silent for up to 35 seconds. Subsequent notifications, button callbacks, and Q&A responses queue up and may arrive out of order or be dropped by the bot's internal timeout. Users perceive the bot as broken.

**Prevention:**

1. Implement a centralized Telegram API rate limiter (token bucket, 1 call/second/chat) in `TelegramBot.swift` that all callers go through. Queue outgoing messages and drain at safe rate.
2. Parse 429 responses and honor `retry_after` by sleeping that exact duration before retrying.
3. For the parse-then-edit flow specifically: if the initial send and the edit are the only two calls, 3s gap is safe. But guard against concurrent notifications with a serial queue.

**Detection:** Watch for `429` in Telegram API error logs or sudden message delivery gaps >10s.

**Phase:** Transcript staleness fix (parse-then-edit implementation).

---

### Pitfall 3: DispatchSource write events coalesce rapid appends into a single event

**What goes wrong:** When Claude Code writes multiple JSONL lines in rapid succession (e.g., tool call results), macOS coalesces multiple FSEvents write notifications into a single DispatchSource event. The `JSONLTailer` fires `readNewLines()` once and reads all accumulated bytes -- this works correctly for data. But if the consumer expects one callback per line (for real-time progress tracking), the batching behavior violates that assumption. More critically, if a single large write fills the FSEvents kernel buffer, subsequent events are dropped entirely with `kFSEventStreamEventFlagMustScanSubDirs`, and the tailer never fires again until the next write.

**Why it happens:** FSEvents coalescing is by design -- Apple docs describe it as an advisory system. The `O_EVTONLY` file descriptor with `.write` mask at the DispatchSource level inherits this coalescing. The current `JSONLTailer` implementation (line 48) does not handle the "must scan subdirs" case or detect dropped events.

**Consequences:** For the transcript staleness watcher: the 79s gap between stop hook and final write may produce no intermediate events, so the tailer only fires once when the final write arrives -- which is the desired behavior. But if someone later extends the tailer to expect granular per-line events (e.g., progress bars), they will get incorrect behavior. The real risk is silent event loss: if the kernel drops events, the tailer permanently stops receiving updates until `stop()` + `start()` reset.

**Prevention:**

1. Add a periodic safety poll (every 10-30s) that calls `readNewLines()` unconditionally, independent of DispatchSource events. This catches any dropped events.
2. In `readNewLines()`, check file size against current offset -- if file size > offset but no event fired, trigger a read anyway.
3. Do NOT assume one event = one write. The current implementation already handles this correctly by reading all new bytes on each event. Document this invariant.
4. Add a "stale file" detector: if no events fire for >60s but the file was expected to grow, log a warning and force a read.

**Detection:** Add telemetry: log the byte count read per event. If you see events reading >10KB at once, coalescing is happening. If events stop entirely but the file is still growing, event loss has occurred.

**Phase:** JSONL tail watcher implementation.

---

### Pitfall 4: JSONLTailer file descriptor leak on file deletion/recreation

**What goes wrong:** Claude Code creates a new JSONL transcript file for each session. If the tailer is watching a file that gets deleted (session ends) and a new file is created at the same path (new session), the `O_EVTONLY` file descriptor still references the old deleted inode. New writes to the new file at the same path produce NO events on the old descriptor. The tailer silently stops working. The `CONCERNS.md` already identifies the FD leak (line 47) but does not mention the file-replacement scenario, which is more operationally dangerous.

**Why it happens:** Unix file descriptors reference inodes, not paths. When a file is deleted and recreated, the new file has a different inode. The old descriptor is valid but points to an unlinked file -- reads return EOF, no new write events fire.

**Consequences:** After a session rotation, the tail watcher stops receiving updates. The transcript staleness fix relies on the tailer catching late writes -- if it is watching a stale descriptor, the edit-in-place correction never fires. This is a data correctness failure, not just a performance issue.

**Prevention:**

1. Monitor `.delete` and `.rename` events in addition to `.write`. When either fires, stop the current source, reopen the file descriptor for the new inode, and resume tailing from offset 0.
2. Alternatively, detect inode change by periodically `stat()`-ing the file and comparing `st_ino` against the original. If changed, restart the tailer.
3. Close the old FD explicitly in the delete handler -- do not rely solely on the cancel handler.

**Detection:** After a session rotation, check if the tailer logs any new data. If it goes silent while the file grows, the descriptor is stale.

**Phase:** JSONL tail watcher implementation.

---

### Pitfall 5: Consumer consolidation breaks the stop hook notification contract

**What goes wrong:** The stop hook currently writes notification JSON files to `~/.claude/notifications/`. The companion's `NotificationWatcher` picks these up. When consolidating to companion-only, if the stop hook is modified to stop writing to `~/.claude/notifications/` but the companion still watches that directory, no notifications arrive. Conversely, if the stop hook is modified to write to a new location that the companion does not yet watch, the same failure occurs. The Bun bot also reads from `state/notifications/` -- removing its watcher without verifying the companion handles all its responsibilities causes silent feature loss.

**Why it happens:** Dual-consumer systems have an implicit contract at the file boundary. Each consumer may have evolved unique behaviors (dedup logic, field parsing, error handling) that the other consumer does not replicate. The consolidation assumption "just remove one consumer" ignores these behavioral differences.

**Consequences:** Missed notifications for some or all sessions. The failure is silent -- no errors are thrown, the watcher simply never sees new files.

**Prevention:**

1. Enumerate every feature the Bun bot's notification watcher provides that the companion does not. Create a checklist and verify each is either ported or explicitly out of scope.
2. Do NOT modify the stop hook file output path during consolidation. Remove only the Bun bot's file watcher, not the file source.
3. Add a heartbeat/canary: after consolidation, have the stop hook write a test notification on first invocation and verify the companion processes it within 5 seconds.
4. Keep the Bun bot's notification watcher code (commented out) for 2 weeks after consolidation as a rollback path.

**Detection:** After consolidation, trigger a manual session stop and verify the companion logs `"Processing notification"` within 5s.

**Phase:** Notification dedup / companion-only consolidation.

## Moderate Pitfalls

### Pitfall 6: MiniMax Q&A context explosion on long sessions

**What goes wrong:** The `handleTextMessage` handler (TelegramBotCallbacks.swift, line 363) sends up to 50,000 characters of transcript text to MiniMax in the system prompt. For long sessions (100+ turns), the transcript easily exceeds this limit. Even at 50K chars, the MiniMax model receives a massive context where most content is irrelevant to the user's question. Research shows hallucinations increase with context length -- the model may confidently answer from an unrelated section of the transcript, mix up details from different turns, or fabricate details that sound plausible.

**Why it happens:** The `String(session.transcriptText.prefix(50000))` truncation is a blunt instrument -- it takes the first 50K chars, which are the OLDEST turns. For questions about recent work, the relevant content is at the END of the transcript, which gets truncated away. The model hallucinates because the answer is not in the provided context.

**Prevention:**

1. Reverse the truncation: send the LAST 50K chars, not the first. Recent turns are more relevant for Q&A.
2. Better: implement a two-stage approach -- first extract the last N turns (e.g., 20), then if the user's question references earlier work, expand the window.
3. Add the SummaryEngine's arc summary as a preamble before raw turns -- this gives the model a compressed overview of the full session, reducing hallucination from missing context.
4. Cap the system prompt at 30K chars (not 50K). Research indicates quality degrades beyond 30K even for large-context models.

**Detection:** When a Q&A answer references file paths, function names, or events that do not appear in the transcript's last 20 turns, hallucination is likely. Log the transcript length and answer for post-hoc audit.

**Phase:** MiniMax Q&A refinements.

---

### Pitfall 7: MiniMax hallucinates arc structure on 1-2 turn sessions

**What goes wrong:** The `SummaryEngine` (line 211) already guards against this: "Single or two turns -- delegate to single-turn (MiniMax hallucinates in arc mode)." But the Q&A handler does NOT apply this guard -- it sends the same system prompt regardless of session length. On 1-turn sessions, MiniMax may invent a multi-step narrative ("first the user set up the project, then configured the database, then...") when the actual session was a single prompt.

**Why it happens:** The Q&A system prompt says "analyzing a Claude Code session transcript" without indicating session length. The model assumes a rich multi-turn session and fills in gaps.

**Prevention:**

1. Prepend session metadata to the Q&A system prompt: `"This session had \(turns.count) turn(s) over \(duration) minutes."`.
2. For 1-2 turn sessions, add an explicit instruction: `"This was a very short session. Do NOT invent additional context."`.
3. Reuse the SummaryEngine's turn-count guard in the Q&A path.

**Detection:** Q&A answers that describe multi-step processes for sessions with turnCount <= 2.

**Phase:** MiniMax Q&A refinements.

---

### Pitfall 8: Edit-in-place loses inline keyboard on message update

**What goes wrong:** When `editMessageText` is called to update a notification with a corrected summary, it replaces the entire message content. If the original message was sent with `sendMessageWithKeyboard` (TelegramBot.swift, line 206), the edit must re-attach the `reply_markup` parameter with the same inline keyboard. If the edit call omits `replyMarkup`, Telegram silently removes all buttons. The user loses Focus Tab, Ask About This, and Transcript buttons.

**Why it happens:** Telegram's `editMessageText` replaces the reply markup only if explicitly provided. Omitting `replyMarkup` means "remove it." This is the opposite of what most developers expect (they expect "keep existing markup if not specified").

**Consequences:** Users lose interactive buttons after the 3s re-edit. They cannot focus the iTerm tab, ask Q&A questions, or view transcripts. The notification becomes a dead message.

**Prevention:**

1. Store the original `TGInlineKeyboardMarkup` alongside the message ID when tracking edit-in-place messages.
2. Always pass `replyMarkup` in the edit call, even if it has not changed.
3. Write a dedicated `editMessageWithKeyboard(messageId:text:keyboard:)` method that enforces this invariant.

**Detection:** After an edit-in-place fires, tap the buttons on the updated message. If they are gone, this pitfall is active.

**Phase:** Transcript staleness fix (parse-then-edit implementation).

---

### Pitfall 9: Telegram 48-hour edit window for non-bot messages

**What goes wrong:** Messages sent by the bot can be edited indefinitely. But if the edit-in-place pattern is ever extended to edit messages NOT originally sent by the bot (e.g., forwarded messages, or messages from the Bun bot era), the 48-hour limit applies. After 48 hours, `editMessageText` returns `400: message can't be edited`.

**Why it happens:** Telegram enforces different edit windows based on message ownership. Bot-sent messages have no time limit for editing by the same bot. But "business messages" or messages from other bots have a 48-hour window.

**Consequences:** Low risk for the current design (companion only edits its own messages), but if the notification metadata override from NASIM bot causes messages to be attributed differently, this could trigger unexpectedly.

**Prevention:**

1. Only edit messages where you have the message ID from your own `sendMessage` call. Never attempt to edit messages by ID from external sources.
2. Add a guard: if the message is older than 47 hours, skip the edit and send a new message instead.

**Detection:** `"message can't be edited"` in error logs.

**Phase:** Not currently at risk. Flag for future reference only.

---

### Pitfall 10: Consolidation removes Bun bot's /prompt and /sessions commands by mistake

**What goes wrong:** PROJECT.md states: "Bun bot retains /prompt, /sessions commands." During consolidation, if the developer removes the Bun bot's notification watcher file and accidentally also removes or breaks the command handlers (which may share initialization code or state), the /prompt and /sessions commands stop working without any error -- the bot simply stops responding to those commands.

**Why it happens:** In TypeScript codebases, command registration and notification watching are often interleaved in the same initialization function. Removing one may break the other due to shared state or import side effects.

**Consequences:** Loss of the /prompt command (remote Claude Code execution) and /sessions command (session listing). These are active-use features.

**Prevention:**

1. Before touching the Bun bot code, write down every command it handles and verify each still works after changes.
2. Remove ONLY the notification watcher code path. Do not refactor or "clean up" adjacent code during consolidation.
3. Test /prompt and /sessions after removing the notification watcher.

**Detection:** Send `/prompt test` and `/sessions` to the Bun bot after consolidation. If no response, the pitfall triggered.

**Phase:** Notification dedup / companion-only consolidation.

## Minor Pitfalls

### Pitfall 11: DispatchSource double-fire on file close after write

**What goes wrong:** Some write patterns (e.g., `FileHandle.synchronizeFile()` followed by `FileHandle.closeFile()`) cause the DispatchSource to fire twice for a single logical write. The `JSONLTailer.readNewLines()` handles this correctly (second read returns empty data, no callback fires), but it wastes a file open + seek + read cycle per spurious event.

**Prevention:** No action needed -- the current implementation is correct. Document this behavior so future developers do not add "dedup" logic that introduces bugs.

**Phase:** Not actionable.

---

### Pitfall 12: sendMessageDraft availability in swift-telegram-sdk

**What goes wrong:** Telegram Bot API 9.5 (March 2026) introduced `sendMessageDraft` for native streaming -- a replacement for the edit-in-place pattern. If the team considers switching to `sendMessageDraft` for the transcript staleness flow, they need to verify swift-telegram-sdk v4.5.0 supports it. The SDK may lag behind the Bot API by weeks or months.

**Prevention:** Check swift-telegram-sdk releases for Bot API 9.5 support before planning any migration. The edit-in-place pattern works today and should not be abandoned for an unverified API.

**Detection:** Check swift-telegram-sdk GitHub releases page for "9.5" or "sendMessageDraft" support.

**Phase:** Future consideration, not current milestone.

---

### Pitfall 13: Q&A free-text messages from other chats trigger responses

**What goes wrong:** The `handleTextMessage` guard (line 335) checks `message.chat.id == chatId`, which is correct. But if the bot is added to a group chat, ANY non-command text in that group will trigger a MiniMax Q&A call, consuming API quota.

**Prevention:** The current guard is sufficient for private chat. If the bot is ever added to groups, add a `message.chat.type == "private"` guard.

**Phase:** Not currently at risk. Flag for group chat expansion only.

## Phase-Specific Warnings

| Phase Topic                            | Likely Pitfall                                                 | Mitigation                                                          |
| -------------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------- |
| Parse-then-edit (transcript staleness) | "message is not modified" 400 on unchanged content (Pitfall 1) | Compare text before editing; catch and downgrade the specific error |
| Parse-then-edit (transcript staleness) | Inline keyboard lost on edit (Pitfall 8)                       | Always re-attach replyMarkup in edit calls                          |
| Parse-then-edit (transcript staleness) | Rate limiting from concurrent edits (Pitfall 2)                | Centralized rate limiter in TelegramBot.swift                       |
| JSONL tail watcher                     | Event coalescing hides intermediate writes (Pitfall 3)         | Periodic safety poll independent of DispatchSource                  |
| JSONL tail watcher                     | FD becomes stale after file deletion/recreation (Pitfall 4)    | Monitor .delete/.rename events; reopen on inode change              |
| Consumer consolidation                 | Breaks stop hook contract silently (Pitfall 5)                 | Feature checklist before removing Bun bot watcher                   |
| Consumer consolidation                 | Accidentally removes /prompt, /sessions (Pitfall 10)           | Touch ONLY watcher code, test commands post-change                  |
| MiniMax Q&A refinements                | Context explosion / truncation bias (Pitfall 6)                | Send last N turns, not first; cap at 30K chars                      |
| MiniMax Q&A refinements                | Hallucination on short sessions (Pitfall 7)                    | Prepend turn count; explicit "do not invent" instruction            |

## Sources

- [Telegram Bot FAQ - Rate Limits](https://core.telegram.org/bots/faq) -- official rate limit documentation
- [Telegram Bot API Changelog](https://core.telegram.org/bots/api-changelog) -- sendMessageDraft in API 9.3/9.5
- [tdlib/td Issue #3034](https://github.com/tdlib/td/issues/3034) -- editMessage rate limit discussion
- [GramIO Rate Limits Guide](https://gramio.dev/rate-limits) -- practical rate limit handling patterns
- [tdlib/telegram-bot-api Issue #400](https://github.com/tdlib/telegram-bot-api/issues/400) -- "message to edit not found" error analysis
- [Apple FSEvents Programming Guide](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html) -- event coalescing, MustScanSubDirs
- [Watchexec macOS FSEvents Limitations](https://watchexec.github.io/docs/macos-fsevents.html) -- practical FSEvents pitfalls
- [Apple DispatchSource Documentation](https://developer.apple.com/documentation/dispatch/dispatchsource) -- cancel handler requirements, FD lifecycle
- [Nature: Hallucination Detection in LLM Summarization](https://www.nature.com/articles/s41598-025-31075-1) -- Q-S-E framework for hallucination detection
- [Context Window Limits and Hallucination](https://pr-peri.github.io/llm/2026/02/13/why-hallucination-happens.html) -- why larger context increases hallucination
- [arxiv: Hallucinate at the Last in Long Response Generation](https://arxiv.org/html/2505.15291) -- positional hallucination bias in long documents
- Existing codebase: `TelegramBot.swift` (line 177), `JSONLTailer.swift`, `TelegramBotCallbacks.swift` (line 363), `SummaryEngine.swift` (line 211), `NotificationWatcher.swift`, `CONCERNS.md`

---

_Pitfalls audit: 2026-04-02_
