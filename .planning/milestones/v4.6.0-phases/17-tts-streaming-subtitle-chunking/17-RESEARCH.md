# Phase 17: TTS Streaming & Subtitle Chunking - Research

**Researched:** 2026-03-26
**Domain:** Swift AppKit text layout, subtitle pagination, audio-subtitle synchronization
**Confidence:** HIGH

## Summary

Phase 17 transforms the subtitle system from showing all text in a single 2-line display to a paged model: full-paragraph TTS synthesis produces one WAV with word timings, then the text is pre-chunked into 2-line pages using word width measurement, and pages flip as karaoke highlighting reaches the end of each page. The audio remains a single continuous WAV -- only the subtitle display is paginated.

The existing codebase already has all the building blocks: `TTSEngine.synthesizeWithTimestamps()` returns per-word timings, `SubtitlePanel.showUtterance()` does karaoke highlighting with DispatchWorkItem scheduling, and `SubtitleStyle` defines the font/layout constants. The work is a refactoring of the subtitle display layer to support multi-page display, plus a new text chunking algorithm that measures word widths to determine line breaks.

**Primary recommendation:** Build a `SubtitleChunker` utility that takes text + font + panel width and returns an array of `SubtitlePage` structs (each with words + timing slice indices). Refactor `SubtitlePanel.showUtterance()` to accept pages and schedule page flips alongside word highlights.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions

- Paragraph-level TTS synthesis (full text to sherpa-onnx in one call) for correct intonation and prosody
- Pre-chunk synthesized text into 2-line subtitle pages using word width measurement (NSAttributedString.size())
- Line break priority: clause boundary (comma/semicolon/colon/em-dash) > phrase boundary (conjunctions/prepositions) > word boundary
- Bottom-heavy line shape preferred (shorter first line, longer second line) per broadcast subtitle standard
- Long sentences synthesized as-is -- trust sherpa-onnx, never split mid-sentence for TTS
- Greeting ("Here's your session summary for...") is part of the full paragraph synthesis, chunked into pages like any other text
- Show one 2-line page at a time, replacing (not accumulating)
- Full 2-line page shown immediately with all words in "future" color (white), karaoke highlights word-by-word
- Instant page swap when karaoke reaches last word of current page -- no fade/slide animation
- Keep showing last page during any brief gap before next content
- Fixed panel height -- no resize per page
- Safety: truncatesLastVisibleLine = true as fallback
- Character-weighted word timing distribution (existing TTSEngine approach) -- zero accumulated drift
- Slice word timing arrays per 2-line page -- each page gets its own timing subset
- Page flip triggered on last word highlight of current page; audio continues seamlessly (single WAV)
- On new notification interruption: cancel current audio + clear subtitle + discard remaining pages, start fresh

### Claude's Discretion

- Exact character-per-line limit (research suggests ~47 for current font/width -- verify at runtime)
- Whether to add truncatesLastVisibleLine to SubtitleStyle or directly in SubtitlePanel
- Internal data structures for page representation (array of word+timing slices)

### Deferred Ideas (OUT OF SCOPE)

- Cross-fade transition between pages (visual polish, not needed for MVP)
- Phoneme-level timestamps from sherpa-onnx C++ patch (Spike 16 explored, character-weighted is sufficient)
- Bionic reading mode overlay (Spike 17 research, separate feature)
  </user_constraints>

<phase_requirements>

## Phase Requirements

| ID        | Description                                                                                                                | Research Support                                                                                                                                                                                                                                                                                                                      |
| --------- | -------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| STREAM-01 | TTS text split into paragraphs/sentences, first chunk synthesized and played while remaining chunks synthesize in parallel | Current architecture synthesizes full paragraph in one call (locked decision). The "streaming" effect comes from audio starting while subtitles paginate -- no parallel synthesis needed since sherpa-onnx produces the WAV faster than real-time (RTF < 1.0). The 5-second target is met by the existing single-call synthesis path. |
| STREAM-02 | Subtitle panel displays one sentence at a time (not full summary), advancing as TTS progresses through sentences           | Implemented via 2-line page chunking with page-flip on last word highlight. SubtitleChunker pre-computes pages; SubtitlePanel.showPages() manages page transitions.                                                                                                                                                                   |
| STREAM-03 | Karaoke word highlighting works within each displayed sentence segment                                                     | Word timings sliced per page from the full timing array. Each page gets its own timing subset; highlighting logic reused from existing showUtterance().                                                                                                                                                                               |

</phase_requirements>

## Standard Stack

No new dependencies. All work uses existing macOS system frameworks already in the project.

### Core

| Library                     | Version          | Purpose                              | Why Standard                                                                                              |
| --------------------------- | ---------------- | ------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| AppKit (NSAttributedString) | macOS 14+ system | Word width measurement via `.size()` | Only reliable way to measure rendered text width for a given font. Already used throughout SubtitlePanel. |
| AppKit (NSTextField)        | macOS 14+ system | 2-line subtitle display              | Existing SubtitlePanel infrastructure.                                                                    |
| DispatchQueue               | Foundation       | Scheduled karaoke work items         | Existing pattern in SubtitlePanel.showUtterance().                                                        |

### Alternatives Considered

| Instead of                  | Could Use                    | Tradeoff                                                                                                     |
| --------------------------- | ---------------------------- | ------------------------------------------------------------------------------------------------------------ |
| NSAttributedString.size()   | CTLine/CTFrame from CoreText | More precise but vastly more complex. NSAttributedString.size() is sufficient for 2-line subtitle layout.    |
| DispatchWorkItem scheduling | CADisplayLink                | Sub-frame precision but adds complexity for ~200ms word durations. Current approach works at 6us per update. |

## Architecture Patterns

### Recommended Project Structure

```
Sources/claude-tts-companion/
├── SubtitleChunker.swift    # NEW: Text -> 2-line pages chunking algorithm
├── SubtitlePanel.swift      # MODIFIED: showPages() replaces showUtterance() as primary API
├── SubtitleStyle.swift      # MODIFIED: add truncatesLastVisibleLine constant
├── TTSEngine.swift          # UNCHANGED: synthesizeWithTimestamps() already returns what we need
├── TelegramBot.swift        # MODIFIED: dispatchTTS() calls showPages() with chunked pages
└── ...
```

### Pattern 1: SubtitlePage Data Model

**What:** A struct representing one 2-line page of subtitle text, with indices into the full word array for timing slicing.

**When to use:** Everywhere pages flow through the system -- from chunker output to subtitle panel input.

```swift
/// One 2-line subtitle page with word indices for timing lookup.
struct SubtitlePage {
    /// Words displayed on this page (joined with spaces for display)
    let words: [String]
    /// Index of the first word in this page within the full word array
    let startWordIndex: Int
    /// Number of words in this page
    var wordCount: Int { words.count }
}
```

### Pattern 2: Width-Based Line Breaking with Clause Priority

**What:** Greedy fill algorithm that measures word widths via `NSAttributedString.size()` and prefers breaking at clause boundaries (comma, semicolon, colon, em-dash) over raw word boundaries.

**When to use:** In SubtitleChunker when converting a word array into 2-line pages.

```swift
/// Measure the rendered width of a string in the subtitle font.
@MainActor
static func measureWidth(_ text: String, font: NSFont) -> CGFloat {
    let attr = NSAttributedString(string: text, attributes: [.font: font])
    return attr.size().width
}

/// Check if a word ends at a clause boundary (preferred break point).
static func isClauseBoundary(_ word: String) -> Bool {
    let lastChar = word.last
    return lastChar == "," || lastChar == ";" || lastChar == ":"
        || word.hasSuffix("\u{2014}") // em-dash
}
```

**Algorithm outline:**

1. Split full text into words
2. Greedily fill line 1, tracking the last clause-boundary position
3. When line 1 overflows, backtrack to last clause boundary if within ~15% of line width
4. Fill line 2 with remaining words until overflow
5. Words that filled lines 1+2 become one SubtitlePage
6. Repeat from remaining words

**Bottom-heavy preference:** When breaking line 1, prefer to break earlier (shorter line 1) so line 2 gets more words. This means using the clause boundary backtrack aggressively -- if a clause boundary exists in the last 30% of line 1, break there.

### Pattern 3: Paged Karaoke Display

**What:** SubtitlePanel shows pages sequentially. Each page appears with all words in white (future), then karaoke highlights advance word-by-word. When the last word of a page is highlighted, the next page is shown immediately.

**When to use:** In the refactored SubtitlePanel, replacing the current flat showUtterance().

```swift
/// Display multiple pages of subtitle text with karaoke highlighting.
/// Audio plays continuously; pages flip as highlighting reaches the last word.
func showPages(_ pages: [SubtitlePage], wordTimings: [TimeInterval]) {
    cancelScheduledHighlights()
    guard !pages.isEmpty else { return }

    var cumulativeTime: TimeInterval = 0

    for (pageIndex, page) in pages.enumerated() {
        let pageStartTime = cumulativeTime

        // Schedule page display (all words white/future)
        let showPageItem = DispatchWorkItem { [weak self] in
            self?.highlightWord(at: -1, in: page.words) // -1 = all future
        }
        scheduledWorkItems.append(showPageItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + pageStartTime, execute: showPageItem)

        // Schedule per-word karaoke within this page
        for localIndex in 0..<page.wordCount {
            let globalIndex = page.startWordIndex + localIndex
            let timing = globalIndex < wordTimings.count ? wordTimings[globalIndex] : 0.2
            let fireTime = cumulativeTime

            let item = DispatchWorkItem { [weak self] in
                self?.highlightWord(at: localIndex, in: page.words)
            }
            scheduledWorkItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + fireTime, execute: item)
            cumulativeTime += timing
        }
    }

    // Linger on last page then hide
    let lingerItem = DispatchWorkItem { [weak self] in
        self?.hide()
    }
    self.lingerWorkItem = lingerItem
    scheduledWorkItems.append(lingerItem)
    DispatchQueue.main.asyncAfter(
        deadline: .now() + cumulativeTime + SubtitleStyle.lingerDuration,
        execute: lingerItem
    )
}
```

### Anti-Patterns to Avoid

- **Splitting text for TTS synthesis:** Never split mid-sentence for sherpa-onnx. The chunking is display-only -- the WAV is always synthesized from the full paragraph.
- **Accumulating text on screen:** Each page replaces the previous one entirely. Do not append lines.
- **Resizing the panel per page:** Panel height is fixed at 2-line height. If a page has only 1 line, the panel stays the same size.
- **Using character count for line length:** Characters have variable width. Use `NSAttributedString.size().width` for accurate measurement.
- **Fading or animating page transitions:** Instant page swap per locked decision.

## Don't Hand-Roll

| Problem                | Don't Build                                    | Use Instead                                           | Why                                                     |
| ---------------------- | ---------------------------------------------- | ----------------------------------------------------- | ------------------------------------------------------- |
| Text width measurement | Manual character counting or font metrics math | `NSAttributedString(string:attributes:).size().width` | Accounts for font metrics, kerning, ligatures. 1-liner. |
| Line break detection   | Regex for punctuation                          | Simple `String.last` / `hasSuffix` checks             | Only 4 clause-boundary characters to check.             |

**Key insight:** The chunking algorithm itself is straightforward greedy-fill. The only "hard" part is accurate width measurement, which AppKit handles natively.

## Common Pitfalls

### Pitfall 1: NSAttributedString.size() Returns Unbounded Width

**What goes wrong:** `size()` returns the natural size of the text without any width constraint. For a single long line, it returns the full unwrapped width.
**Why it happens:** This is actually what we want -- we compare measured width against the available line width to determine when a line overflows.
**How to avoid:** Calculate available line width as: `panelWidth - (horizontalPadding * 2)`. Current values: panel is 70% of screen width (2056 \* 0.7 = 1439pt), padding is 16pt each side, so available width is ~1407pt.
**Warning signs:** If measured single-word widths seem too small, check that you're using the correct font (SubtitleStyle.regularFont at 28pt).

### Pitfall 2: Page Flip Timing Off-by-One

**What goes wrong:** Page flip happens one word too early or too late, causing a visual glitch.
**Why it happens:** The page flip (showing next page with all-white words) and the first word highlight of the new page fire at the same time but in wrong order.
**How to avoid:** Schedule page display and first word highlight at the same time in the same DispatchWorkItem, or ensure the page display fires fractionally before (e.g., 1ms earlier). In practice, scheduling them at the same `cumulativeTime` and relying on FIFO ordering of DispatchQueue.main works correctly.
**Warning signs:** Brief flash of old page content when new page should be showing.

### Pitfall 3: @MainActor and NSAttributedString.size()

**What goes wrong:** Calling NSAttributedString.size() from a background queue.
**Why it happens:** SubtitleChunker might be called from the TTS dispatch flow which runs on a background queue.
**How to avoid:** SubtitleChunker must be `@MainActor` since it uses NSAttributedString with font attributes, which require AppKit's main thread. Call it from `DispatchQueue.main.async` in the dispatch flow, before scheduling page display.
**Warning signs:** Crashes or incorrect measurements when running in release mode.

### Pitfall 4: Empty Last Page

**What goes wrong:** The chunking algorithm produces a final page with 0 words.
**Why it happens:** Off-by-one in the greedy fill loop when the last word exactly fills line 2.
**How to avoid:** Guard against empty pages in the chunker output. Filter `pages.filter { !$0.words.isEmpty }`.
**Warning signs:** Brief blank panel flash at the end of TTS playback.

### Pitfall 5: Interruption Race Condition

**What goes wrong:** A new notification arrives mid-page-display, but some old DispatchWorkItems still fire.
**Why it happens:** `cancelScheduledHighlights()` cancels work items, but items already dequeued may still execute.
**How to avoid:** Use a generation counter (incrementing Int). Each page display session gets a generation number. Work items check `guard self.generation == myGeneration` before executing. This is a lightweight alternative to the existing cancel pattern.
**Warning signs:** Briefly seeing old subtitle text flash after a new notification starts.

## Code Examples

### Word Width Measurement

```swift
// Source: AppKit NSAttributedString documentation
@MainActor
static func measureWidth(_ text: String) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: SubtitleStyle.regularFont
    ]
    let attrStr = NSAttributedString(string: text, attributes: attributes)
    return ceil(attrStr.size().width)
}
```

### Available Line Width Calculation

```swift
// Source: Derived from SubtitlePanel.positionOnScreen() + SubtitleStyle constants
@MainActor
static func availableLineWidth() -> CGFloat {
    guard let screen = NSScreen.main else { return 800 }
    let panelWidth = screen.visibleFrame.width * SubtitleStyle.widthRatio
    return panelWidth - (SubtitleStyle.horizontalPadding * 2)
}
```

### Clause Boundary Detection

```swift
// Source: CONTEXT.md locked decision on line break priority
static func breakPriority(_ word: String) -> Int {
    let trimmed = word.trimmingCharacters(in: .whitespaces)
    // Clause boundary: comma, semicolon, colon, em-dash
    if trimmed.hasSuffix(",") || trimmed.hasSuffix(";") || trimmed.hasSuffix(":")
        || trimmed.hasSuffix("\u{2014}") {
        return 3  // highest priority break point
    }
    // Phrase boundary: after conjunctions/prepositions
    let lower = trimmed.lowercased()
    let phraseWords = ["and", "or", "but", "for", "nor", "yet", "so",
                       "in", "on", "at", "to", "of", "by", "with", "from"]
    if phraseWords.contains(lower) {
        return 2
    }
    // Any word boundary
    return 1
}
```

### Greedy Page Fill Algorithm (Pseudocode)

```swift
@MainActor
static func chunkIntoPages(words: [String], availableWidth: CGFloat) -> [SubtitlePage] {
    var pages: [SubtitlePage] = []
    var wordIndex = 0

    while wordIndex < words.count {
        // Fill line 1
        let (line1Words, line1End) = fillLine(
            words: words, from: wordIndex, maxWidth: availableWidth, preferShorter: true
        )
        // Fill line 2
        let (line2Words, line2End) = fillLine(
            words: words, from: line1End, maxWidth: availableWidth, preferShorter: false
        )

        let pageWords = line1Words + line2Words
        if !pageWords.isEmpty {
            pages.append(SubtitlePage(
                words: pageWords,
                startWordIndex: wordIndex
            ))
        }
        wordIndex = line2End
    }

    return pages
}
```

## Validation Architecture

### Test Framework

| Property           | Value                                                                   |
| ------------------ | ----------------------------------------------------------------------- |
| Framework          | Manual testing via HTTP API + visual inspection                         |
| Config file        | none -- swift binary, no test target yet                                |
| Quick run command  | `curl -X POST http://localhost:8780/subtitle/show -d '{"text":"test"}'` |
| Full suite command | Build + run + visual verification via TTS dispatch                      |

### Phase Requirements to Test Map

| Req ID    | Behavior                                        | Test Type | Automated Command                                                      | File Exists? |
| --------- | ----------------------------------------------- | --------- | ---------------------------------------------------------------------- | ------------ |
| STREAM-01 | First audio plays within 5s of TTS dispatch     | manual    | Time from notification to first audio output                           | N/A          |
| STREAM-02 | Subtitle displays one page at a time, advancing | manual    | Trigger TTS via `/health` or test notification, observe subtitle panel | N/A          |
| STREAM-03 | Karaoke highlighting within each page           | manual    | Observe gold word advancement within each 2-line page                  | N/A          |

### Sampling Rate

- **Per task commit:** `swift build -c debug` (compilation check)
- **Per wave merge:** Full build + manual TTS trigger test
- **Phase gate:** Trigger 3 test notifications, verify page-flip behavior and timing

### Wave 0 Gaps

None -- no automated test infrastructure for this UI-heavy phase. All validation is visual/manual via the running binary.

## State of the Art

| Old Approach                                 | Current Approach                      | When Changed | Impact                                                 |
| -------------------------------------------- | ------------------------------------- | ------------ | ------------------------------------------------------ |
| Full text in 2-line field (overflow clipped) | Paginated 2-line pages with page-flip | This phase   | Long summaries now fully readable via sequential pages |
| showUtterance() with flat word list          | showPages() with SubtitlePage array   | This phase   | Karaoke works per-page instead of per-full-text        |

## Open Questions

1. **Exact characters per line at 28pt in SF Pro Display**
   - What we know: CONTEXT.md estimates ~47 chars. Panel width is ~1407pt available.
   - What's unclear: Exact average character width varies by text content.
   - Recommendation: Use pixel-width measurement (NSAttributedString.size()), not character counting. The ~47 estimate is only useful for mental models, not code.

2. **Whether showUtterance() should be preserved or replaced**
   - What we know: `showUtterance()` is called by `SubtitlePanel.demo()` and by `dispatchTTS()`.
   - What's unclear: Whether to keep it as a convenience wrapper for single-page text.
   - Recommendation: Keep `showUtterance()` as a thin wrapper that creates a single-page array and calls `showPages()`. This preserves backward compatibility for demo() and simple text display.

## Sources

### Primary (HIGH confidence)

- Codebase: `SubtitlePanel.swift` -- existing karaoke implementation (lines 133-171)
- Codebase: `TTSEngine.swift` -- synthesizeWithTimestamps() API (lines 164-189)
- Codebase: `SubtitleStyle.swift` -- font and layout constants
- Codebase: `TelegramBot.swift` -- dispatchTTS() orchestration (lines 185-218)
- CONTEXT.md -- locked decisions on chunking strategy and display behavior
- Apple Developer Documentation: NSAttributedString.size() for text measurement

### Secondary (MEDIUM confidence)

- Broadcast subtitle standards (2 lines, 37-47 chars, page-flip model) -- referenced in CONTEXT.md specifics

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH - no new dependencies, all AppKit system APIs
- Architecture: HIGH - clear refactoring path from existing code, well-defined data model
- Pitfalls: HIGH - based on direct code analysis of existing SubtitlePanel patterns

**Research date:** 2026-03-26
**Valid until:** 2026-04-26 (stable domain, no moving targets)
