# Phase 17: TTS Streaming & Subtitle Chunking - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

TTS audio starts playing within 5 seconds of session end using paragraph-level synthesis for natural intonation. Subtitles display as 2-line pages with word-level karaoke gold highlighting, flipping pages as speech progresses through the text.

</domain>

<decisions>
## Implementation Decisions

### Text Chunking Strategy

- Paragraph-level TTS synthesis (full text to sherpa-onnx in one call) for correct intonation and prosody
- Pre-chunk synthesized text into 2-line subtitle pages using word width measurement (NSAttributedString.size())
- Line break priority: clause boundary (comma/semicolon/colon/em-dash) > phrase boundary (conjunctions/prepositions) > word boundary
- Bottom-heavy line shape preferred (shorter first line, longer second line) per broadcast subtitle standard
- Long sentences synthesized as-is — trust sherpa-onnx, never split mid-sentence for TTS
- Greeting ("Here's your session summary for...") is part of the full paragraph synthesis, chunked into pages like any other text

### Subtitle Display Behavior

- Show one 2-line page at a time, replacing (not accumulating)
- Full 2-line page shown immediately with all words in "future" color (white), karaoke highlights word-by-word
- Instant page swap when karaoke reaches last word of current page — no fade/slide animation
- Keep showing last page during any brief gap before next content
- Fixed panel height — no resize per page
- Safety: truncatesLastVisibleLine = true as fallback

### Audio-Subtitle Synchronization

- Character-weighted word timing distribution (existing TTSEngine approach) — zero accumulated drift
- Slice word timing arrays per 2-line page — each page gets its own timing subset
- Page flip triggered on last word highlight of current page; audio continues seamlessly (single WAV)
- On new notification interruption: cancel current audio + clear subtitle + discard remaining pages, start fresh

### Claude's Discretion

- Exact character-per-line limit (research suggests ~47 for current font/width — verify at runtime)
- Whether to add truncatesLastVisibleLine to SubtitleStyle or directly in SubtitlePanel
- Internal data structures for page representation (array of word+timing slices)

</decisions>

<code_context>

## Existing Code Insights

### Reusable Assets

- `TTSEngine.swift` — synthesizeWithTimestamps() already does full-text synthesis + character-weighted word timing extraction
- `SubtitlePanel.swift` — showUtterance(text, wordTimings) with DispatchQueue-scheduled karaoke highlighting
- `SubtitleStyle.swift` — karaoke colors (gold current, silver past, white future), maxLines = 2, lingerDuration
- `TelegramBot.dispatchTTS()` — current entry point for TTS dispatch

### Established Patterns

- TTSEngine uses dedicated serial DispatchQueue (.userInitiated QoS)
- SubtitlePanel is @MainActor, all UI updates on main thread
- Word timings use character-weighted distribution with zero accumulated drift
- Audio playback via afplay subprocess (process.waitUntilExit())

### Integration Points

- TTSEngine.synthesizeWithTimestamps() — needs to return full word timing array for paragraph
- SubtitlePanel.showUtterance() — needs refactor to accept pages instead of flat word list
- TelegramBot.dispatchTTS() — orchestrates synthesis → subtitle → playback flow
- cancelCurrentPlayback() — existing pattern for interruption handling

</code_context>

<specifics>
## Specific Ideas

- Research validated: broadcast subtitle standard is max 2 lines, 37-47 chars/line, page-flip (not scroll)
- ASS/SSA karaoke uses per-event model with full text visible — matches recommended approach
- NSAttributedString.size() for word width measurement to determine line breaks
- Pre-chunking algorithm: greedily fill line 1 then line 2, prefer breaking at clause boundaries within ~15% of line edge

</specifics>

<deferred>
## Deferred Ideas

- Cross-fade transition between pages (visual polish, not needed for MVP)
- Phoneme-level timestamps from sherpa-onnx C++ patch (Spike 16 explored, character-weighted is sufficient)
- Bionic reading mode overlay (Spike 17 research, separate feature)

</deferred>
