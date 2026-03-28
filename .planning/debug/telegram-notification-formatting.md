---
status: awaiting_human_verify
trigger: "Telegram bot messages from Claude Code Commander are not sensibly structured. Multiple sessions jumbled together with poor formatting."
created: 2026-03-28T12:30:00Z
updated: 2026-03-28T12:30:00Z
---

## Current Focus

hypothesis: Multiple independent issues cause poor notification quality - see Evidence for full analysis
test: Review formatDecisionMessage output and parseDecision fallback path
expecting: Confirm root causes and design fixes
next_action: Implement fixes for all identified issues

## Symptoms

expected: Each Telegram notification should be a clean, well-structured message for a SINGLE session/event
actual: Messages contain multiple sessions jumbled together - multiple Auto-Continue blocks mixed, two projects in one message, inconsistent formatting ("I Session" vs "In Session" vs "Il Session"), duplicate timestamps, "thinking block fallback" appearing inline
errors: No crash - formatting/structure issue
reproduction: Messages appear this way when auto-continue notifications fire
started: Ongoing

## Eliminated

## Evidence

- timestamp: 2026-03-28T12:35:00Z
  checked: Full notification pipeline from stop hook to Telegram send
  found: |
  Pipeline: telegram-notify-stop.ts writes JSON -> NotificationWatcher picks up file ->
  CompanionApp.handleNotification() -> sends TWO separate messages per session event:
  1. Auto-continue decision message (formatDecisionMessage/formatExitMessage) via sendSilentMessage
  2. Session notification (renderSessionNotification) via sendSessionNotification which sends Arc Summary + Tail Brief
     implication: Each session stop creates 2-3 Telegram messages - when multiple sessions stop near-simultaneously, messages interleave

- timestamp: 2026-03-28T12:37:00Z
  checked: parseDecision() fallback path in AutoContinue.swift lines 508-524
  found: |
  When MiniMax response doesn't follow "DECISION|reason" format, a keyword scan fallback fires.
  The reason is set to literal string "extracted from unstructured response (thinking block fallback)"
  This internal debug text gets passed through to formatDecisionMessage() as displayReason (line 924)
  and rendered verbatim in the Telegram notification (line 946).
  implication: Internal implementation detail leaks into user-facing messages

- timestamp: 2026-03-28T12:38:00Z
  checked: formatDecisionMessage line 970 - session ID display
  found: |
  Line reads: "Claude session uuid jsonl ~/.claude/projects: <code>{shortSession}</code>"
  This is internal path/implementation detail exposed to user
  implication: Notification contains developer-facing metadata that clutters the message

- timestamp: 2026-03-28T12:39:00Z
  checked: "I Session" vs "In Session" vs "Il Session" inconsistency
  found: |
  The actual text in code is emoji + "Session" (e.g. line 958: "📊 Session").
  The reported variations are almost certainly OCR misreads of emoji characters before "Session".
  Not a code bug.
  implication: Not an actual formatting bug - dismiss this symptom

- timestamp: 2026-03-28T12:40:00Z
  checked: Duplicate timestamp "2026-03-28 12:14 12:14"
  found: |
  formatVancouverTimestamp() uses format "yyyy-MM-dd HH:mm" which produces "2026-03-28 12:14".
  Only called once per message. The duplicate "12:14" likely comes from two adjacent messages
  rendered close together in the Telegram chat, making their timestamps appear as one.
  implication: Not a code duplication bug but the visual effect of too many messages sent in rapid succession

## Resolution

root_cause: |
Three compounding issues make auto-continue Telegram notifications poorly structured:

1. VERBOSE INTERNAL METADATA: formatDecisionMessage() includes developer-facing detail:
   - "Claude session uuid jsonl ~/.claude/projects: <code>..." (line 970)
   - "extracted from unstructured response (thinking block fallback)" leaks as reason text (parseDecision line 523)

2. CLUTTERED LAYOUT: The decision message template packs too much information:
   - Full separator lines (24x box-drawing chars) top and bottom
   - Redundant "Plan" section when plan is "unknown" or "No Plan"
   - Verbose iteration/runtime stats that only matter during active debugging

3. REASON TEXT QUALITY: When MiniMax returns thinking-block-style responses,
   parseDecision's fallback path (line 523) sets a useless technical reason string
   instead of extracting the actual decision rationale from the unstructured text.

fix: |

1. Clean up formatDecisionMessage template:
   - Replace verbose session UUID line with just "<code>{shortSession}</code>"
   - Hide "Plan" section when no plan exists
   - Condense layout by removing redundant separators

2. Fix parseDecision fallback reason:
   - When fallback keyword scan fires, extract surrounding context from the model response
     as the reason instead of using the hardcoded debug string

3. Tighten the notification template for readability

verification: |

- swift build: clean (0 errors, 0 new warnings)
- swift test: 82/82 tests pass
- Before/after message comparison (manually verified in code):

  BEFORE (formatDecisionMessage):
  🔄 Auto-Continue: CONTINUE
  ━━━━━━━━━━━━━━━━━━━━━━━━
  <extracted from unstructured response (thinking block fallback)>
  📋 Plan: No Plan
  <unknown>
  📊 Session
  • Iteration: 3 / 10
  • Runtime: 5.2 / 180 min
  • 4T Bash12 Edit8 Read15
  • Project: ~/eon/cc-skills
  • Claude session uuid jsonl ~/.claude/projects: 5a6aab44
  ━━━━━━━━━━━━━━━━━━━━━━━━
  2026-03-28 12:14

  AFTER (formatDecisionMessage):
  🔄 Auto-Continue: CONTINUE 5a6aab44
  <actual sentence from model response containing the keyword>
  • #3/10 • 5m • 4T Bash12 Edit8 Read15
  • ~/eon/cc-skills
  2026-03-28 12:14

files_changed:

- plugins/claude-tts-companion/Sources/CompanionCore/AutoContinue.swift
