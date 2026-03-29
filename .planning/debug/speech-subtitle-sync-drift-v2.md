---
status: awaiting_human_verify
trigger: "Speech and karaoke subtitles are out of sync. The gold word highlighting does not match the spoken word during TTS playback."
created: 2026-03-28T20:00:00-0700
updated: 2026-03-28T20:00:00-0700
---

## Current Focus

hypothesis: The silent lead-in buffer (480 samples / 10ms) scheduled in AudioStreamPlayer.reset() shifts the playerTime baseline, causing currentTime to be offset from the actual audio content start. SubtitleSyncDriver assumes time 0 = start of first real audio, but currentTime includes the silent lead-in.
test: Trace the exact data flow from reset() -> play() -> silent buffer -> real buffer scheduling -> currentTime computation to confirm the offset
expecting: If confirmed, currentTime will always be ~10ms+ ahead of the actual audio position, causing subtitles to highlight slightly early
next_action: Verify the offset and determine if it's significant enough to cause the reported sync drift

## Symptoms

expected: Gold word highlighting perfectly matches the spoken word at all times during TTS playback
actual: Speech and subtitle highlighting are out of sync — words highlight at wrong times relative to audio
errors: No error messages — this is a timing/sync issue
reproduction: Occurs during TTS playback of session summaries. The pasted text being read was a session debrief summary.
started: Reported after Phase 32 (audio device resilience) changes were merged. Prior sync drift was fixed 2026-03-27.

## Eliminated

## Evidence

- timestamp: 2026-03-28T20:00:00
  checked: AudioStreamPlayer.reset() flow (lines 205-235)
  found: reset() calls playerNode.stop(), then playerNode.play(), then scheduleBuffer(silentBuffer) with 480 samples (10ms at 48kHz). This means playerTime.sampleTime starts counting from the play() call, including the 480 silent samples.
  implication: currentTime will be offset by at least 480/48000 = 10ms from the actual audio content start

- timestamp: 2026-03-28T20:01:00
  checked: SubtitleSyncDriver.startBatchPlayback() (lines 269-337)
  found: Sets chunkStartTime = 0 for the first chunk. Uses asp.currentTime (which includes silent lead-in) as globalTime. chunkLocalTime = globalTime - 0 = globalTime.
  implication: Word onset lookup uses a time that is offset by the silent lead-in duration

- timestamp: 2026-03-28T20:02:00
  checked: TTSPipelineCoordinator.startBatchPipeline() flow (lines 143-236)
  found: cancelCurrentPipeline() -> reset() -> processing -> startBatchPlayback(). Between reset() and first real buffer scheduling, playerNode is running with only the silent lead-in.
  implication: The time offset is 10ms (silent buffer) plus any main-thread processing time between reset() and scheduling

- timestamp: 2026-03-28T20:03:00
  checked: Phase 32 changes (commits 4becbd35, ad9c319f)
  found: Phase 32 added HAL listener, engine rebuild, and health check. The health check skips during active playback. None of these changes affect the timing path during normal playback.
  implication: Phase 32 itself is unlikely the cause. The silent lead-in (172e39cb) and/or word count mismatch are more likely candidates.

- timestamp: 2026-03-28T20:04:00
  checked: Prior fix c81d6d19 (use preprocessed text in ChunkResult)
  found: Fixed ChunkResult.text to use preprocessed text so splitWordsMatchingKokoro matches Kokoro's tokenization. But the match depends on Kokoro's Python server word tokenization exactly matching splitWordsMatchingKokoro's whitespace-split + filter-punctuation logic.
  implication: If Kokoro returns words that don't match splitWordsMatchingKokoro (e.g., different handling of hyphenated words, contractions, numbers), the onset array will still be misaligned with the subtitle word array.

## Resolution

root_cause: |
Two issues causing subtitle/audio sync drift:

1. PRIMARY: Word count mismatch between Kokoro's MToken tokenization and splitWordsMatchingKokoro().
   The Python server returns word timings based on Misaki/spaCy linguistic tokens (MTokens), which
   may split or merge words differently from whitespace splitting. When counts differ,
   SubtitleSyncDriver.resolveOnsets() falls back to duration-derived onsets, causing significant drift.
   The prior fix (c81d6d19) used preprocessed text but this doesn't solve the fundamental tokenization
   mismatch -- Misaki tokenization != whitespace splitting.

2. SECONDARY: Silent lead-in buffer (480 samples = 10ms) in AudioStreamPlayer.reset() shifts the
   playerTime baseline. SubtitleSyncDriver assumes time 0 = start of first real audio, but
   currentTime includes the silent lead-in, causing a constant ~10ms forward offset.

fix: |

1. Add wordTexts field to ChunkResult to carry Kokoro's actual word texts through the pipeline.
2. In TTSPipelineCoordinator, use Kokoro's word texts as display words (when available) instead of
   re-splitting with splitWordsMatchingKokoro(). This guarantees 1:1 alignment between display
   words and onset times.
3. Account for silent lead-in offset: set chunkStartTime to the lead-in duration (480/48000) so
   the karaoke timer doesn't start ahead of the real audio.

verification: Build succeeds (swift build). Awaiting human verification of actual playback sync.
files_changed:

- plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift
- plugins/claude-tts-companion/Sources/CompanionCore/TTSPipelineCoordinator.swift
- plugins/claude-tts-companion/Sources/CompanionCore/SubtitleSyncDriver.swift
