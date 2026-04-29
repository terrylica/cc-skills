---
phase: 17-tts-streaming-subtitle-chunking
verified: 2026-03-26T10:30:00Z
status: human_needed
score: 9/9 automated must-haves verified
re_verification: false
human_verification:
  - test: "Trigger a TTS dispatch via Telegram session end and measure elapsed time from dispatch to first audio output"
    expected: "First audio begins playing within 5 seconds of TTS dispatch"
    why_human: "End-to-end timing (notification arrival to audio playback) requires running the full binary with a real Telegram session and a stopwatch — cannot measure synthesis RTF programmatically without a live binary"
  - test: "Trigger TTS with a long paragraph (3+ sentences, ~60+ words). Observe the subtitle panel."
    expected: "Subtitle panel shows one 2-line page at a time; as karaoke highlighting reaches the last word of a page, the next page appears instantly (no fade), resetting all words to white and beginning per-word karaoke again"
    why_human: "Page-flip timing and visual behavior requires live binary observation with a running NSPanel on screen"
  - test: "Observe karaoke gold highlighting within each subtitle page"
    expected: "Words light up gold one at a time in left-to-right order within each 2-line page; past words turn silver-grey; current word is bold gold; future words remain white"
    why_human: "Word-level color transitions are visual UI behavior that cannot be verified from source code alone"
---

# Phase 17: TTS Streaming & Subtitle Chunking Verification Report

**Phase Goal:** TTS audio starts playing within 5 seconds of session end; subtitles display one sentence at a time with karaoke word highlighting
**Verified:** 2026-03-26T10:30:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (from ROADMAP.md Success Criteria)

| #   | Truth                                                                                   | Status  | Evidence                                                                                                                                                                |
| --- | --------------------------------------------------------------------------------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | First audio starts playing within 5 seconds of TTS dispatch (paragraph-level synthesis) | ? HUMAN | Code path: synthesis → single WAV → `ttsEngine.play()` concurrent with subtitle. RTF < 1.0 documented in design. Cannot time end-to-end without live binary.            |
| 2   | Subtitle panel shows one sentence at a time, advancing as each sentence completes       | ? HUMAN | `showPages()` schedules page flips at word timing boundaries. Page flip logic is in code (verified). Visual behavior requires live observation.                         |
| 3   | Karaoke gold word highlighting advances within each displayed sentence                  | ? HUMAN | `highlightWord(at:in:)` produces gold/silver/white attributed strings per page's local word array. Logic verified in code. Visual confirmation requires running binary. |

**Automated sub-truths (backing the three success criteria above):**

| #   | Sub-truth                                                                                 | Status     | Evidence                                                                                                                                                                                      |
| --- | ----------------------------------------------------------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A   | SubtitleChunker splits text into 2-line pages using pixel-width measurement               | ✓ VERIFIED | `SubtitleChunker.swift` exists, substantive (162 lines), `chunkIntoPages()`, `measureWidth()`, `availableLineWidth()`, `fillLine()` all present                                               |
| B   | Each SubtitlePage tracks `startWordIndex` for timing array slicing                        | ✓ VERIFIED | `struct SubtitlePage` with `words`, `startWordIndex`, `wordCount` present in `SubtitleChunker.swift:4-8`                                                                                      |
| C   | SubtitlePanel.showPages() schedules page display + per-word karaoke with generation guard | ✓ VERIFIED | `showPages()` at line 140, `generation == myGeneration` guard in all work items, page-level `showPageItem` + per-word items scheduled via `DispatchQueue.main.asyncAfter`                     |
| D   | Page flip is instant (triggered on last word of page, next page resets to white)          | ✓ VERIFIED | `showPageItem` fires at `pageStartTime = cumulativeTime` immediately when the previous page's last word is being highlighted; uses `highlightWord(at: -1, in: pageWords)` for all-white reset |
| E   | Generation counter prevents stale work items after interruption                           | ✓ VERIFIED | `cancelScheduledHighlights()` increments `generation` before cancelling items; all work items guard `self.generation == myGeneration`                                                         |
| F   | `showUtterance()` wraps `showPages()` for backward compatibility                          | ✓ VERIFIED | `SubtitlePanel.swift:195-199` — `showUtterance()` creates `SubtitlePage(words:startWordIndex:0)` and calls `showPages([singlePage], wordTimings:)`                                            |
| G   | `SubtitleChunker.chunkIntoPages()` is called in `dispatchTTS()` (TelegramBot)             | ✓ VERIFIED | `TelegramBot.swift:206` — `let pages = SubtitleChunker.chunkIntoPages(text: ttsResult.text)`                                                                                                  |
| H   | `subtitlePanel.showPages()` replaces `showUtterance()` in production TTS dispatch         | ✓ VERIFIED | `TelegramBot.swift:207` — `self.subtitlePanel.showPages(pages, wordTimings: ttsResult.wordTimings)`. No `showUtterance` call remains in `dispatchTTS()`.                                      |
| I   | Project compiles with `swift build -c debug`                                              | ✓ VERIFIED | Build output: `Build complete! (1.11s)` — zero errors                                                                                                                                         |

**Score (automated):** 9/9 automated sub-truths verified

---

### Required Artifacts

| Artifact                                                                          | Expected                            | Status     | Details                                                                                                                    |
| --------------------------------------------------------------------------------- | ----------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------------------------- |
| `plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitleChunker.swift` | Text-to-pages chunking algorithm    | ✓ VERIFIED | 162 lines, `@MainActor enum SubtitleChunker`, `struct SubtitlePage`, all 5 required functions present                      |
| `plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitlePanel.swift`   | Paged karaoke display               | ✓ VERIFIED | 317 lines, `showPages()` at line 140, generation counter at line 20, `showUtterance()` wrapper at line 195                 |
| `plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitleStyle.swift`   | `truncatesLastVisibleLine` constant | ✓ VERIFIED | Line 72: `static let truncatesLastVisibleLine = true` with doc comment                                                     |
| `plugins/claude-tts-companion/Sources/claude-tts-companion/TelegramBot.swift`     | Paged TTS dispatch flow             | ✓ VERIFIED | Lines 205-208: `SubtitleChunker.chunkIntoPages()` + `showPages()` replace former `showUtterance()` call in `dispatchTTS()` |

---

### Key Link Verification

| From                    | To                      | Via                                                             | Status  | Details                                                                                                           |
| ----------------------- | ----------------------- | --------------------------------------------------------------- | ------- | ----------------------------------------------------------------------------------------------------------------- |
| `SubtitleChunker.swift` | `SubtitleStyle.swift`   | `SubtitleStyle.regularFont` used in `measureWidth()`            | ✓ WIRED | `SubtitleChunker.swift:40` — `[.font: SubtitleStyle.regularFont]`; also uses `widthRatio` and `horizontalPadding` |
| `SubtitlePanel.swift`   | `SubtitleChunker.swift` | `SubtitlePage` struct consumed by `showPages()`                 | ✓ WIRED | `SubtitlePanel.swift:140` accepts `[SubtitlePage]`; `showUtterance()` creates `SubtitlePage` at line 197          |
| `TelegramBot.swift`     | `SubtitleChunker.swift` | `SubtitleChunker.chunkIntoPages()` called in `dispatchTTS()`    | ✓ WIRED | `TelegramBot.swift:206` — call confirmed, receives `ttsResult.text` from synthesis callback                       |
| `TelegramBot.swift`     | `SubtitlePanel.swift`   | `subtitlePanel.showPages()` called instead of `showUtterance()` | ✓ WIRED | `TelegramBot.swift:207` — confirmed; no `showUtterance` call in `dispatchTTS()`                                   |

---

### Data-Flow Trace (Level 4)

| Artifact                  | Data Variable | Source                                                    | Produces Real Data                                            | Status    |
| ------------------------- | ------------- | --------------------------------------------------------- | ------------------------------------------------------------- | --------- |
| `SubtitlePanel.showPages` | `pages`       | `SubtitleChunker.chunkIntoPages(text:)`                   | Yes — derived from `ttsResult.text` (real synthesis output)   | ✓ FLOWING |
| `SubtitlePanel.showPages` | `wordTimings` | `ttsResult.wordTimings` from `synthesizeWithTimestamps()` | Yes — character-weighted durations from sherpa-onnx synthesis | ✓ FLOWING |
| `SubtitleChunker`         | `text`        | `ttsResult.text` (echoed from synthesis input)            | Yes — real text fed to sherpa-onnx                            | ✓ FLOWING |

Note: `main.swift:256` uses `showUtterance()` directly in the dev-mode demo path (when `telegramBot == nil`). Since `showUtterance()` now delegates to `showPages()`, this path also flows through paged karaoke. The dev-mode path is not a stub — it's an intentional single-page fallback for development without a Telegram token.

---

### Behavioral Spot-Checks

| Behavior                                        | Command                                                                   | Result                    | Status |
| ----------------------------------------------- | ------------------------------------------------------------------------- | ------------------------- | ------ |
| Project compiles clean                          | `cd plugins/claude-tts-companion && swift build -c debug 2>&1 \| tail -3` | `Build complete! (1.11s)` | ✓ PASS |
| `SubtitleChunker.chunkIntoPages` exported       | `grep "SubtitleChunker.chunkIntoPages" TelegramBot.swift`                 | Line 206 found            | ✓ PASS |
| `showPages` wired in `dispatchTTS`              | `grep "showPages" TelegramBot.swift`                                      | Line 207 found            | ✓ PASS |
| No `showUtterance` remaining in `dispatchTTS()` | `grep "showUtterance.*ttsResult" TelegramBot.swift`                       | No match                  | ✓ PASS |
| Commits in git log                              | `git log --oneline \| grep -E "92e0f560\|c25ca6fc\|309dc665"`             | All 3 found               | ✓ PASS |
| Visual page-flip behavior                       | Requires live binary                                                      | N/A                       | ? SKIP |
| 5-second latency to first audio                 | Requires live binary + Telegram session                                   | N/A                       | ? SKIP |

---

### Requirements Coverage

| Requirement | Source Plan(s) | Description (from REQUIREMENTS.md)                                                                                         | Status         | Evidence                                                                                                                                                                                                                                                                                                                              |
| ----------- | -------------- | -------------------------------------------------------------------------------------------------------------------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| STREAM-01   | 17-01, 17-02   | TTS text split into paragraphs/sentences, first chunk synthesized and played while remaining chunks synthesize in parallel | ? HUMAN + NOTE | Implementation uses single-WAV paragraph synthesis (intentional per 17-CONTEXT.md). The 5-second latency goal from the ROADMAP success criterion is achievable via RTF < 1.0 — no parallel chunked synthesis needed. REQUIREMENTS.md wording predates the design decision to use single-WAV synthesis. Latency must be verified live. |
| STREAM-02   | 17-01, 17-02   | Subtitle panel displays one sentence at a time (not full summary), advancing as TTS progresses through sentences           | ? HUMAN        | `showPages()` schedules page-sequential display. One 2-line page at a time confirmed in code. Visual confirmation required.                                                                                                                                                                                                           |
| STREAM-03   | 17-01, 17-02   | Karaoke word highlighting works within each displayed sentence segment                                                     | ? HUMAN        | Per-word `highlightWord(at:in:)` called within each page's word scope. Confirmed in code. Visual confirmation required.                                                                                                                                                                                                               |

**Note on STREAM-01 wording:** The REQUIREMENTS.md description says "parallel chunk synthesis" — this conflicts with the explicit design decision in 17-CONTEXT.md to use single-paragraph synthesis for correct prosody. The ROADMAP success criterion ("First audio starts playing within 5 seconds of TTS dispatch") is the authoritative contract. The implementation meets the latency goal by keeping synthesis fast (RTF < 1.0), not by parallelizing. This is a REQUIREMENTS.md documentation issue, not an implementation gap.

**Orphaned requirements check:** No requirements in REQUIREMENTS.md map to Phase 17 that are not claimed by 17-01 or 17-02.

---

### Anti-Patterns Found

| File                  | Line | Pattern                            | Severity | Impact                                                                                                              |
| --------------------- | ---- | ---------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------- |
| `SubtitlePanel.swift` | 60   | Comment: "Use a placeholder frame" | ℹ️ Info  | Not a stub — NSPanel requires an initial content rect before Auto Layout; comment accurately describes init pattern |

No blocking anti-patterns found. The `main.swift:256` `showUtterance()` call in the dev-mode demo path is intentional and backward-compatible (delegates to `showPages()` internally).

---

### Human Verification Required

#### 1. First Audio Within 5 Seconds (STREAM-01)

**Test:** Start the binary with a valid Telegram bot token. Send a Claude session notification via the file watcher. Start a stopwatch when the notification file is written. Stop when audio begins playing.
**Expected:** Audio starts within 5 seconds of session end.
**Why human:** End-to-end timing requires a live running binary, real Telegram credentials, and a session notification trigger. Cannot measure synthesis RTF programmatically without execution.

#### 2. Paged Subtitle Display with Page Flips (STREAM-02)

**Test:** With the binary running, trigger a TTS dispatch with a long paragraph (at least 60 words). Observe the subtitle panel at the bottom of the screen.
**Expected:** The panel shows exactly one 2-line page at a time. When the last word of the current page is highlighted gold, the next page appears instantly (no animation) with all words shown white. Karaoke highlighting begins from the first word of the new page.
**Why human:** Page-flip timing and visual rendering are UI behaviors that cannot be verified from source code static analysis.

#### 3. Karaoke Gold Highlighting Per Page (STREAM-03)

**Test:** With the binary running, observe any TTS playback on a subtitle page.
**Expected:** Words advance gold one at a time, left to right. Current word is bold gold, past words are silver-grey, future words are white. Timing matches audio playback cadence.
**Why human:** Word-level color transitions at audio-synchronized timing require visual observation of the live NSPanel.

---

### Gaps Summary

No gaps found in the automated checks. All three artifacts exist, are substantive (not stubs), are fully wired, and have real data flowing through them. The project compiles cleanly. All three documented commits (92e0f560, c25ca6fc, 309dc665) are confirmed in git history.

The only open items are the three human verification tests, which were explicitly flagged as manual-only in the 17-VALIDATION.md (UI behavior, real-time audio timing). These are not gaps — they are the expected verification modality for this phase.

**REQUIREMENTS.md note:** STREAM-01's description ("parallel chunk synthesis") does not match the implemented approach (single-WAV synthesis). This is a documentation inconsistency, not an implementation gap. The ROADMAP success criterion is the contract, and the implementation satisfies it by design.

---

_Verified: 2026-03-26T10:30:00Z_
_Verifier: Claude (gsd-verifier)_
