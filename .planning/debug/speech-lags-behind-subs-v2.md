---
status: awaiting_human_verify
trigger: "Speech audio lags behind subtitle gold word highlighting. No magic number solutions allowed. Must use SOTA approach."
created: 2026-03-26T00:00:00Z
updated: 2026-03-26T00:00:00Z
---

## Current Focus

hypothesis: CONFIRMED — extractTimingsFromTokens returns per-word durations (end_ts - start_ts) but discards leading silence and inter-word gaps. SyncDriver cumulates from 0, so subtitles run ~275ms ahead of audio.
test: Spike data shows first word "Hi" starts at 0.275s but onset[0] = 0 in current code
expecting: Fix by passing onset times (start_ts) directly instead of durations
next_action: Implement fix — return onset times from extractTimingsFromTokens, add wordOnsets field to TTSResult/ChunkResult, update SyncDriver to use them

## Symptoms

expected: Gold word highlighting and spoken audio are perfectly synchronized
actual: Speech lags behind subtitles — gold word flashes before the audio speaks that word
errors: None — timing mismatch
reproduction: Every TTS playback
started: Persistent issue. Already replaced afplay with AVAudioPlayer + CADisplayLink polling (SOTA closed-loop approach).

## Eliminated

## Evidence

- timestamp: 2026-03-26T00:01:00Z
  checked: TTSEngine.extractTimingsFromTokens implementation
  found: Returns per-word DURATIONS (end_ts - start_ts), skipping punctuation tokens entirely. Leading silence before first word and inter-word gaps (from punctuation pauses) are lost.
  implication: When SyncDriver cumulates from 0, every word onset is early by at least the leading silence (~275ms from spike data)

- timestamp: 2026-03-26T00:02:00Z
  checked: Spike data for kokoro-ios word timestamps
  found: First word "Hi" starts at 0.275s, not 0.0s. Punctuation "," spans 1.025-1.125s. These gaps are lost when only durations are returned.
  implication: Root cause confirmed — subtitle highlight arrives ~275ms+ before audio for every word

- timestamp: 2026-03-26T00:03:00Z
  checked: SubtitleSyncDriver onset computation
  found: Builds onsets as cumulative sum of durations starting from 0. onset[0]=0, onset[1]=dur[0], etc.
  implication: If first word has 0.275s leading silence, onset[0] is wrong by 0.275s, and this error propagates to all subsequent words via missing inter-word gaps

## Resolution

root_cause: extractTimingsFromTokens returned per-word durations (end_ts - start_ts) but discarded leading silence (first word start_ts > 0) and inter-word gaps (from filtered punctuation tokens). SubtitleSyncDriver cumulated durations from 0, making every word onset ~275ms+ earlier than the actual audio timing.
fix: Changed extractTimingsFromTokens to return NativeTimings struct containing both durations AND onset times (start_ts values). Added wordOnsets field to TTSResult and ChunkResult. Updated SubtitleSyncDriver to use native onset times directly when available, falling back to duration-based cumulation for the character-weighted fallback path.
verification: Build succeeds, service running. Awaiting human verification of sync quality during real TTS playback.
files_changed:

- plugins/claude-tts-companion/Sources/claude-tts-companion/TTSEngine.swift
- plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitleSyncDriver.swift
- plugins/claude-tts-companion/Sources/claude-tts-companion/TelegramBot.swift
