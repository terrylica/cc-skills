---
status: awaiting_human_verify
trigger: "Speech and subtitle gold words are slightly out of sync at times"
created: 2026-03-27T11:00:00-0700
updated: 2026-03-27T11:00:00-0700
---

## Current Focus

hypothesis: MToken.text tokens do not correspond 1:1 with subtitle words from whitespace-split, causing onset[i] to map to wrong word
test: Compare MToken token count (after punctuation filtering) with whitespace-split word count for the same sentence
expecting: If counts differ, the onset array is misaligned with the subtitle word array
next_action: Trace the data flow — MToken tokens vs SubtitleChunker words — to find the mismatch

## Symptoms

expected: Gold word highlighting perfectly matches the spoken word at all times
actual: Occasionally (~1-2 words per sentence) the highlight is slightly ahead or behind the speech
errors: No errors
reproduction: Intermittent during any TTS playback — some sentences are perfectly synced, others drift slightly
started: After native MToken timestamp integration

## Eliminated

## Evidence

- timestamp: 2026-03-27T11:00:00
  checked: MToken class definition (MLXUtilsLibrary/DataStructures/MToken.swift)
  found: MToken.text is a linguistic token from NaturalLanguage framework tokenizer. It is NOT a whitespace-split word — NLTokenizer can split "don't" into ["do", "n't"], keep hyphenated words together, etc.
  implication: MToken tokens are LINGUISTIC tokens, not whitespace-split words. The count of MTokens (after punct filter) likely differs from the count of whitespace-split words used by SubtitleChunker.

- timestamp: 2026-03-27T11:02:00
  checked: extractTimingsFromTokens() in TTSEngine.swift (lines 507-529)
  found: It iterates MTokens, skips punctuation, and produces one onset per non-punctuation MToken. The resulting onsets array has length = number of non-punct MTokens.
  implication: onsets[i] = start time of the i-th non-punctuation MToken (linguistic token)

- timestamp: 2026-03-27T11:03:00
  checked: SubtitleChunker.chunkIntoPages() (lines 30-33)
  found: Uses `text.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)` to split text into words. This is plain whitespace splitting — "don't" stays as one word, "well-known" stays as one word.
  implication: SubtitleChunker word count = whitespace-split count, while onset count = NLTokenizer token count (different!)

- timestamp: 2026-03-27T11:05:00
  checked: TimestampPredictor.swift (kokoro-ios)
  found: Timestamps are assigned per MToken (linguistic token), including tokens that NLTokenizer produces. Punctuation MTokens have phonemes==nil and get skipped by both TimestampPredictor AND extractTimingsFromTokens.
  implication: The onset array is aligned to MToken indices, not to whitespace-split word indices

- timestamp: 2026-03-27T11:07:00
  checked: Data flow in TelegramBot.swift
  found: chunk.wordOnsets (from extractTimingsFromTokens, aligned to MTokens) is passed directly to SubtitleSyncDriver.addChunk(nativeOnsets:), which uses it indexed by subtitle word position. SubtitleChunker splits by whitespace. If MToken count != word count, onset[i] maps to wrong word.
  implication: This is the root cause — onset array is indexed by MToken position but consumed by subtitle word position

## Resolution

root_cause: MToken linguistic tokens from NLTokenizer do NOT have a 1:1 correspondence with whitespace-split words used by SubtitleChunker. The NLTokenizer may split contractions (e.g., "don't" -> ["do", "n't"]), keep hyphenated words as one token, or split words differently than simple whitespace splitting. extractTimingsFromTokens() produces one onset per non-punctuation MToken, but SubtitleSyncDriver indexes into this array by whitespace-split word position. When counts differ, subsequent words get the wrong onset time, causing the intermittent ahead/behind drift.
fix: |

1. Added `texts` field to NativeTimings to carry MToken word texts alongside onsets
2. Added `alignOnsetsToWords()` that maps MToken onsets to whitespace-split subtitle words using character-offset tracking
3. Updated both `synthesizeWithTimestamps` and `synthesizeStreaming` to call alignOnsetsToWords before returning
4. Added count-mismatch guards in SubtitleSyncDriver (single-shot init + addChunk) that fall back to duration-derived onsets when alignment fails
5. Added diagnostic logging when MToken count != subtitle word count
   verification: Build succeeds, binary installed to ~/.local/bin, service restarted. Awaiting human verification of actual playback sync.
   files_changed:

- plugins/claude-tts-companion/Sources/claude-tts-companion/TTSEngine.swift
- plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitleSyncDriver.swift
