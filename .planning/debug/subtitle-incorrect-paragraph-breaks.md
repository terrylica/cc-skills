---
status: awaiting_human_verify_v2
trigger: "subtitle-incorrect-paragraph-breaks"
created: 2026-03-28T00:00:00Z
updated: 2026-03-28T00:00:00Z
---

## Current Focus

hypothesis: paragraphBreakIndices computes indices against splitWordsMatchingKokoro word array, but display uses reattachPunctuation output which may have DIFFERENT count (it matches kokoroTokens count, not splitWordsMatchingKokoro count)
test: Compare word counts from paragraphBreakIndices vs reattachPunctuation for same text
expecting: If kokoroTokens count differs from splitWordsMatchingKokoro count, paragraph break indices are wrong
next_action: Trace the exact mismatch between the two word arrays

## Symptoms

expected: Text wraps naturally at panel width with paragraph breaks only between actual paragraphs
actual: Paragraph break inserted mid-sentence between "get stripped" and "during processing"
errors: No errors -- visual rendering issue
reproduction: Any multi-paragraph TTS playback -- the breaks appear at wrong word positions
started: After the sync drift + punctuation fixes in this session

## Eliminated

## Evidence

- timestamp: 2026-03-28T00:01:00Z
  checked: TTSPipelineCoordinator.startBatchPipeline single-chunk path (lines 188-215)
  found: Line 207 computes breaks via `PronunciationProcessor.paragraphBreakIndices(chunk.text)` which uses splitWordsMatchingKokoro internally. Line 195-206 computes display words via `reattachPunctuation(originalText: chunk.text, kokoroTokens: kokoroWords)` which returns array with count == kokoroTokens.count. These two word arrays can have DIFFERENT counts.
  implication: paragraphBreakIndices counts words using splitWordsMatchingKokoro, but the page is built with words from reattachPunctuation (count == kokoroTokens.count). If Kokoro produces fewer tokens than splitWordsMatchingKokoro (e.g., merges hyphenated words), the break index points to the wrong word.

- timestamp: 2026-03-28T00:02:00Z
  checked: PronunciationProcessor.paragraphBreakIndices (lines 155-169)
  found: Uses `paragraph.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace).filter { ... }` which is identical to splitWordsMatchingKokoro. This counts words in the ORIGINAL text. But the display array has kokoroTokens.count words.
  implication: ROOT CAUSE CONFIRMED. The break indices are computed against the original text word count, but applied to an array of kokoroTokens.count words. Any difference in count causes misaligned breaks.

## Resolution

root_cause: `paragraphBreakIndices` counts words using `splitWordsMatchingKokoro` logic (original text word count), but the display word array comes from `reattachPunctuation` which has `kokoroTokens.count` words. When Kokoro tokenizes differently (merges or splits), the indices point to wrong positions.
fix_v1: (FAILED) Greedy word-by-word matching — fragile, breaks when words don't match.
fix_v2: Character-offset anchoring — finds \n\n positions in the source text by character offset, maps each display word to the character range it covers in the source, then marks the display word whose range ends before each \n\n. Immune to tokenization differences because character positions are invariant. Based on industry standard approach (Azure TTS text_offset, spaCy tokenizations library).
verification: Build succeeds. Awaiting human verification of correct paragraph break rendering during TTS playback.
files_changed: [PronunciationProcessor.swift, TTSPipelineCoordinator.swift]
