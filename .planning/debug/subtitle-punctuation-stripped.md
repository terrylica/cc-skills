---
status: awaiting_human_verify
trigger: "subtitle-punctuation-stripped"
created: 2026-03-28T00:00:00Z
updated: 2026-03-29T06:35:00Z
---

## Current Focus

hypothesis: The reattachPunctuation fix IS working correctly in the deployed binary. Production logs confirm punctuation reaches SubtitlePanel and is rendered.
test: Verified via production logs, binary MD5 match, process start time, and curl to Kokoro server
expecting: Visual overlay shows punctuation on next real TTS playback
next_action: Request human verification — trigger a real TTS playback and visually confirm punctuation appears

## Symptoms

expected: Subtitles display full text with punctuation (periods, commas, em dashes, apostrophes in contractions)
actual: All periods (`.`), commas (`,`), and seemingly all punctuation are stripped from subtitle display
errors: No errors — subtitles display but without punctuation
reproduction: Any TTS playback — e.g. `tts_kokoro.sh "We'd been running an autonomous workflow. It's over — the milestone's complete."`
started: Started immediately after the sync drift v2 fix was applied (this session). Punctuation was fine before that fix.

## Eliminated

- hypothesis: SubtitlePanel or SubtitleChunker has its own word-splitting logic that strips punctuation independently
  evidence: Exhaustive search of SubtitlePanel.highlightWord, SubtitleSyncDriver, SubtitleChunker, SubtitleStyle, BionicRenderer -- none strip punctuation from words. All render the words array as-is.
  timestamp: 2026-03-29T06:20:00Z

- hypothesis: A rendering-layer transformation strips punctuation between TTSPipelineCoordinator and visual display
  evidence: Traced full data flow: TTSPipelineCoordinator.words -> SubtitlePage -> SubtitleSyncDriver.addChunk -> activateChunk -> SubtitlePanel.highlightWord -> NSAttributedString. No transformation at any step.
  timestamp: 2026-03-29T06:25:00Z

- hypothesis: SubtitleSyncDriver re-splits words and strips punctuation
  evidence: SubtitleSyncDriver stores pages from addChunk() as-is and passes pages[x].words directly to SubtitlePanel.highlightWord(). No re-splitting or text processing.
  timestamp: 2026-03-29T06:30:00Z

- hypothesis: SubtitleChunker.chunkIntoPages strips punctuation
  evidence: chunkIntoPages splits on whitespace (line 39-41) and preserves all punctuation attached to words. "workflow." stays as "workflow."
  timestamp: 2026-03-29T06:30:00Z

- hypothesis: reattachPunctuation fix is not reaching the visual display path
  evidence: Production logs at 06:28:48 show "[PUNCT-FIX] Display words: We | had | been | running | an | autonomous | workflow. | It | is | over, | the | milestone | is | complete." AND subtitle-panel rendered text="We had been running an autonomous workflow. It is over, the milestone is complet" — punctuation IS present in the rendered output.
  timestamp: 2026-03-29T06:33:00Z

## Evidence

- timestamp: 2026-03-28T00:01:00Z
  checked: kokoro_common.py synthesize_with_timestamps() function
  found: Line 89-92 — MToken tokens are iterated, punctuation-only tokens are skipped, and `t.text` is used as the word text. MToken.text comes from Misaki/spaCy tokenization which produces linguistic tokens (no attached punctuation).
  implication: The wordTexts array sent from Python server contains words WITHOUT punctuation attached.

- timestamp: 2026-03-28T00:02:00Z
  checked: TTSPipelineCoordinator.swift lines 195-201
  found: When `chunk.wordTexts` is available and non-empty, it is used directly as display words instead of `splitWordsMatchingKokoro(chunk.text)`. The old path (`splitWordsMatchingKokoro`) splits on whitespace and keeps punctuation attached to words (e.g., "running," stays intact).
  implication: The sync drift v2 fix correctly uses Kokoro tokens for onset alignment but incorrectly uses them for display text too, stripping all punctuation.

- timestamp: 2026-03-28T00:03:00Z
  checked: PronunciationProcessor.splitWordsMatchingKokoro()
  found: Splits on whitespace and filters standalone punctuation only. Words like "running." keep the period. This was the pre-fix display path.
  implication: The solution should use wordTexts for COUNT/ALIGNMENT (1:1 with onsets) but derive display words from the original text with punctuation preserved.

- timestamp: 2026-03-29T06:30:00Z
  checked: Live Kokoro server response via curl
  found: Server returns 14 words ALL stripped of punctuation: [We, had, been, running, an, autonomous, workflow, It, is, over, the, milestone, is, complete]. splitWordsMatchingKokoro on same text produces 14 words WITH punctuation. Counts match (14 == 14), so reattachPunctuation fast path returns originalWords with punctuation.
  implication: reattachPunctuation works correctly for this test case.

- timestamp: 2026-03-29T06:32:00Z
  checked: Binary deployment and process timing
  found: Binary at ~/.local/bin/claude-tts-companion MD5=229af717e898563ebc06aa8944ca392a matches .build/release. Built at 06:26:44, source modified at 06:14/06:26. Process PID 9227 started at 06:26:57 (after build).
  implication: The fix is compiled into and running in the active binary.

- timestamp: 2026-03-29T06:33:00Z
  checked: Production logs after binary restart (06:26:57 onwards)
  found: Single TTS playback at 06:28:48. Full log chain: (1) "Using Kokoro-aligned words with punctuation for subtitle display (14 words)", (2) "[PUNCT-FIX] Display words: We | had | been | running | an | autonomous | workflow. | It | is | over, | the | milestone | is | complete.", (3) subtitle-panel text="We had been running an autonomous workflow. It is over, the milestone is complet" — ALL with punctuation preserved end-to-end.
  implication: Fix is confirmed working through entire pipeline: reattachPunctuation -> SubtitlePage -> SubtitleSyncDriver -> SubtitlePanel rendering.

## Resolution

root_cause: The sync drift v2 fix changed TTSPipelineCoordinator to use `chunk.wordTexts` (Kokoro MToken linguistic tokens) as both alignment keys AND display words. MToken.text strips punctuation from words (e.g., "running." -> "running", "workflow," -> "workflow"). The old path used `splitWordsMatchingKokoro(chunk.text)` which preserved punctuation.
fix: Added PronunciationProcessor.reattachPunctuation() that maps Kokoro linguistic tokens back to the original whitespace-split words (which preserve trailing punctuation). Updated TTSPipelineCoordinator to use this function for display words in both single-chunk and multi-chunk paragraph mode paths. Added [PUNCT-FIX] telemetry log.
verification: Binary deployed and running (PID 9227 since 06:26:57, MD5 confirmed). Production logs at 06:28:48 show punctuation in display words and rendered subtitle panel text. Awaiting visual confirmation from user.
files_changed: [PronunciationProcessor.swift, TTSPipelineCoordinator.swift]
