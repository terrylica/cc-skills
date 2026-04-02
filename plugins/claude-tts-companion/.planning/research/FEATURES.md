# Feature Landscape: Notification Intelligence

**Domain:** Developer session monitoring with self-correcting notifications, interactive Q&A, dedup consolidation
**Researched:** 2026-04-02
**Context:** Brownfield Swift companion app (~7,500 LOC) monitoring Claude Code sessions via Telegram, TTS, and karaoke subtitles

## Table Stakes

Features users expect. Missing = notifications feel unreliable or noisy.

| Feature                                            | Why Expected                                                                                                                                                     | Complexity | Notes                                                                                                                                                                                                                                                                                          |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Edit-in-place on data improvement**              | Stale initial summaries destroy trust. Users see wrong info, then a correction arrives as a _second_ message -- confusing. Industry standard: edit the original. | Medium     | Telegram `editMessageText` API is well-supported. The companion already uses `editMessage(messageId:text:)` for prompt execution progress. Extend to session notifications: send initial summary, store `message_id`, re-summarize after 3s tail re-check, edit if content changed materially. |
| **Notification dedup (single consumer)**           | Dual consumers (companion + Bun bot) cause architectural confusion and potential double-notifications. Single consumer = single source of truth.                 | Low        | Already partially implemented in `NotificationProcessor.swift` (session ID + transcript size fingerprinting, 15-min TTL). Complete by removing Bun bot's `state/notifications/` watcher entirely.                                                                                              |
| **Transcript-size-growth dedup**                   | Prevents re-notification on the same session unless new work was done. Without this, stop-hook re-fires produce noise.                                           | Low        | Already implemented (`shouldSkipDedup` checks `currentSize <= entry.transcriptSize`). Table stakes because it is the foundation of reliable dedup.                                                                                                                                             |
| **Rate limiting between notifications**            | Rapid stop-hook fires (e.g., session crash/restart loop) should not flood the chat.                                                                              | Low        | Already implemented (5-second minimum interval in `NotificationProcessor`). Keep as-is.                                                                                                                                                                                                        |
| **Self-explanatory messages (no vague fallbacks)** | "Session completed." tells the user nothing. Every notification must contain evidence of what was done (files changed, tools used, outcome).                     | Medium     | 28 vague messages already fixed (2026-04-02). Table stakes going forward: never ship a fallback that says only "completed" or "no reason provided." Add assertion/lint to catch regressions.                                                                                                   |
| **Callback query acknowledgment**                  | After pressing an inline button, Telegram shows a spinner until `answerCallbackQuery` is called. Not answering = broken UX.                                      | Low        | Already implemented. Industry best practice per Telegram Bot API docs.                                                                                                                                                                                                                         |
| **Circuit breaker on LLM calls**                   | MiniMax downtime must not block notification delivery. Degrade gracefully to raw transcript excerpts.                                                            | Low        | Already implemented (`CircuitBreaker.swift`). Table stakes for any LLM-dependent notification system.                                                                                                                                                                                          |
| **Context-rich error messages**                    | When circuit breaker opens or API fails, tell the user _why_ ("MiniMax API returned 429, circuit breaker open for 60s") not just "unavailable."                  | Low        | Partially implemented. Ensure every error path includes the specific failure reason in the Telegram message.                                                                                                                                                                                   |

## Differentiators

Features that set this system apart from generic monitoring bots. Not expected, but highly valued.

| Feature                                     | Value Proposition                                                                                                                                                                                                               | Complexity | Notes                                                                                                                                                                                                                                                                                                                                                                  |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Parse-then-edit with JSONL tail watcher** | The 79-second transcript staleness gap is a unique problem. Sending an initial summary fast, then silently editing it when the full transcript arrives, gives both speed and accuracy. No open-source monitoring bot does this. | High       | Two-phase approach: (1) On stop-hook, parse available JSONL, send initial summary with `message_id` stored. (2) Start a `DispatchSource` tail watcher on the transcript. When new lines arrive within a configurable window (e.g., 90s), re-parse, re-summarize, `editMessageText` the original. Stop watching after the window expires or no growth detected for 10s. |
| **Interactive Q&A over session context**    | "Ask About This" button + free-text follow-up lets the user interrogate a session without opening Claude Code. Turns Telegram from a notification channel into a read-only investigation tool.                                  | Medium     | Already ported from NASIM bot. `lastSessionContext` stores transcript text for the most recent session. MiniMax answers questions against that context. Enhancement: support Q&A on _any_ recent session (not just last), via a session selector.                                                                                                                      |
| **Chained follow-up conversations**         | After the first Q&A answer, the user should be able to ask follow-ups without re-selecting the session. Conversation threading in Telegram.                                                                                     | Medium     | Store Q&A history per session (bounded, e.g., last 5 exchanges). Prepend previous Q&A turns to the MiniMax prompt. Use Telegram reply-to-message threading to keep the visual chain.                                                                                                                                                                                   |
| **Material change detection for edits**     | Only edit the notification if the re-summarized content is _materially different_ from the initial. Prevents meaningless edits (e.g., same summary with slightly different wording).                                            | Medium     | Hash or semantic comparison: if the new summary's key facts (files changed, outcome, tool counts) match the original, skip the edit. Simple approach: compare extracted structured fields rather than free-text similarity.                                                                                                                                            |
| **Multi-session Q&A selector**              | Let the user pick which recent session to ask about, not just the last one. `/sessions` already lists recent sessions -- add an "Ask" button to each.                                                                           | Medium     | Extend `InlineButtonManager` to store context for N recent sessions (already bounded at 200 entries). Add "Ask" callback to the `/sessions` list.                                                                                                                                                                                                                      |
| **TTS re-synthesis on edit**                | When the notification is edited with improved content, optionally re-speak the corrected summary via TTS. Most users will NOT want this (double audio is jarring). Gate behind a feature flag, default OFF.                     | Low        | Simple: if `FeatureGates.ttsResynthOnEdit` is true and the message was edited, queue a new TTS job. Default off.                                                                                                                                                                                                                                                       |
| **Notification provenance metadata**        | Show whether a notification is "initial" or "updated" and the reason ("transcript grew 12KB after initial send"). Transparency builds trust.                                                                                    | Low        | Add a small footer to edited messages: "Updated: transcript grew from 45KB to 57KB." Use HTML `<i>` tag for subtle presentation.                                                                                                                                                                                                                                       |
| **Session activity indicators in SwiftBar** | SwiftBar menu bar shows real-time session state: idle, active (with turn count), synthesizing, sending. Replaces polling `/status` command.                                                                                     | Medium     | SwiftBar already exists (`claude-hq.10s.sh`). Enhance with session-aware state: read companion's `/health` endpoint (already returns subsystem statuses). Add session count, last notification time, current activity.                                                                                                                                                 |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature                                | Why Avoid                                                                                                                                                      | What to Do Instead                                                                                                           |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| **Real-time streaming summaries**           | Summarizing mid-session produces inaccurate, incomplete narratives that train the user to ignore notifications. Out of scope per PROJECT.md.                   | Summarize on session-end only. The parse-then-edit pattern handles the "fast but might be stale" case.                       |
| **Delete-and-resend instead of edit**       | Sending a new message for corrections fragments the conversation. User loses context of which notification maps to which session. Telegram chat becomes noisy. | Always use `editMessageText` on the original `message_id`. Never delete + re-send.                                           |
| **LLM-powered dedup (semantic similarity)** | Using MiniMax to determine if two notifications are "similar enough" to dedup is over-engineered. Transcript size + session ID is deterministic and free.      | Keep the current fingerprinting approach (session ID + transcript byte size). It is correct, fast, and costs zero API calls. |
| **Multi-user support**                      | This is Terry's personal infrastructure, not a SaaS. Multi-user adds auth, tenant isolation, and state management complexity for zero benefit.                 | Single-user, single-chat design. `TELEGRAM_CHAT_ID` is the only consumer.                                                    |
| **Push notifications to iOS/mobile**        | macOS-only binary. iOS companion would require a separate app, Apple Developer account, push notification infrastructure. Massive scope creep.                 | Telegram mobile app already receives notifications cross-platform. This is the mobile delivery mechanism.                    |
| **Webhook mode for Telegram**               | Long polling works. Webhook requires a public endpoint, TLS termination, and port forwarding. For a local launchd service, this is unnecessary complexity.     | Keep long polling via `TGClientPrtcl` (validated in spike 04, 8.6MB RSS).                                                    |
| **Full conversation replay in Telegram**    | Dumping entire transcripts into Telegram messages hits the 4096-char limit and is unreadable.                                                                  | Keep the paginated transcript viewer (already implemented with `txp:` callbacks, bounded chunks).                            |
| **Automatic session resume from Telegram**  | Letting the bot resume Claude Code sessions remotely introduces security concerns and state management complexity.                                             | Keep "Ask About This" as read-only. Session control stays in the terminal.                                                   |
| **Complex dedup rule engine**               | OpsGenie/PagerDuty-style rule engines with match conditions, fingerprint templates, and suppression windows are enterprise-grade overkill.                     | Session ID + transcript size growth is the only dedup dimension needed. Two fields, one comparison.                          |

## Feature Dependencies

```
Notification Dedup (single consumer) ─── prerequisite for ──→ Parse-then-edit
    (must remove Bun bot watcher first so only companion owns message_id lifecycle)

Parse-then-edit ─── prerequisite for ──→ Material Change Detection
    (need both initial and updated summaries to compare)

Parse-then-edit ─── prerequisite for ──→ TTS Re-synthesis on Edit
    (need the edit event to trigger re-synthesis)

Parse-then-edit ─── prerequisite for ──→ Notification Provenance Metadata
    (need to know "this was edited" to add the footer)

Interactive Q&A (existing) ─── prerequisite for ──→ Chained Follow-ups
    (need single-turn Q&A working before adding multi-turn)

Interactive Q&A (existing) ─── prerequisite for ──→ Multi-session Q&A Selector
    (need Q&A plumbing before adding session selection UI)
```

## MVP Recommendation

Prioritize in this order:

1. **Notification dedup consolidation** (table stakes, Low complexity) -- Remove Bun bot notification watcher. Companion becomes sole consumer. This unblocks everything else.
2. **Parse-then-edit with JSONL tail watcher** (differentiator, High complexity) -- The core value of this milestone. Solves the 79-second staleness gap with fast initial delivery + silent self-correction.
3. **Material change detection** (differentiator, Medium complexity) -- Prevents meaningless edits. Without this, every session will get an edit even if the summary is identical.
4. **Notification provenance metadata** (differentiator, Low complexity) -- Small footer on edited messages. Cheap to add once parse-then-edit is working.
5. **Chained follow-up Q&A** (differentiator, Medium complexity) -- Multi-turn Q&A with conversation history. Builds on existing single-turn Q&A.

Defer:

- **Multi-session Q&A selector**: Nice-to-have but single-session Q&A covers 90% of use cases. The last session is almost always the one you want to ask about.
- **TTS re-synthesis on edit**: Default off, niche use case. Add the feature gate now, implement later if needed.
- **Session activity indicators in SwiftBar**: Independent work stream, not part of notification intelligence core.

## Sources

- [Telegram Bot API -- editMessageText](https://core.telegram.org/bots/api) -- official docs, HIGH confidence
- [Telegram Bot API changelog](https://core.telegram.org/bots/api-changelog) -- recent API additions
- [OpsGenie Alert Deduplication](https://support.atlassian.com/opsgenie/docs/what-is-alert-de-duplication/) -- alias-based dedup pattern
- [PagerDuty Intelligent Alert Grouping](https://support.pagerduty.com/main/docs/intelligent-alert-grouping) -- ML-based grouping (rejected as over-engineered for this use case)
- [OneUptime Alert Deduplication](https://oneuptime.com/blog/post/2026-01-30-alert-deduplication/view) -- fingerprinting strategies
- [Smashing Magazine -- UX Strategies for Real-Time Dashboards](https://www.smashingmagazine.com/2025/09/ux-strategies-real-time-dashboards/) -- dashboard UX patterns
- [End Point Dev -- Telegram Bot RAG Pipeline](https://www.endpointdev.com/blog/2025/12/telegram-bot-rag-pipeline/) -- RAG Q&A integration pattern
- Existing codebase: `NotificationProcessor.swift`, `TelegramBotCallbacks.swift`, `InlineButtonManager.swift`, `SummaryEngine.swift` -- validated current implementation
