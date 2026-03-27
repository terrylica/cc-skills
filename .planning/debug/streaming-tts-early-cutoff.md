---
status: awaiting_human_verify
trigger: "streaming-tts-early-cutoff: Speech and subtitles stop short frequently"
created: 2026-03-27T10:30:00-0700
updated: 2026-03-27T10:35:00-0700
---

## Current Focus

hypothesis: CONFIRMED — No streaming-in-progress guard in dispatchTTS
test: Fix applied and deployed
expecting: New notifications during active streaming TTS are skipped with a warning log
next_action: User verification — wait for two back-to-back notifications and confirm first plays to completion

## Symptoms

expected: TTS plays all chunks to completion before new notification's TTS starts
actual: New notification interrupts mid-stream — only 3 of 12 chunks play, then new TTS starts
errors: No errors — the interruption is "by design" but premature
reproduction: Any two notifications arriving ~90s apart (first still synthesizing when second arrives)
started: Since streaming TTS pipeline implementation

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-03-27T10:30:00
  checked: Log pattern at 10:04:24 — 12-chunk dispatch, only chunks 1-9 visible before new dispatch at 10:05:23
  found: New dispatch interrupts before all chunks play. Synthesis continues on serial queue but playback gets replaced.
  implication: Confirms the race between synthesis completion and new dispatch

- timestamp: 2026-03-27T10:30:00
  checked: Log pattern at 10:09:00 — 12-chunk dispatch, only chunks 1-3 visible before new dispatch at 10:10:39
  found: Only 3 of 12 chunks played before interruption. ~90s gap between dispatches.
  implication: The problem is severe — most of the audio is lost

- timestamp: 2026-03-27T10:30:00
  checked: Code path in dispatchStreamingTTS (TelegramBot.swift lines 225-276)
  found: No guard for "streaming in progress". The onChunkReady callback with isFirst=true stops previous playback and replaces syncDriver.
  implication: Root cause confirmed — need a streaming-in-progress guard

- timestamp: 2026-03-27T10:30:00
  checked: TTSEngine.synthesizeStreaming (lines 284-358) serial queue behavior
  found: queue.async enqueues ALL synthesis work. Two calls to synthesizeStreaming queue interleaved blocks. Old chunks complete synthesis but their callbacks fire into a replaced SyncDriver.
  implication: The serial queue doesn't prevent interleaving — it just serializes the actual synthesis. Callbacks still fire and create conflicting state.

## Resolution

root_cause: dispatchStreamingTTS has no guard against concurrent streaming sessions. When a new notification dispatches TTS while a previous streaming pipeline is still playing, the new pipeline's first chunk callback (isFirst=true) stops the old playback and replaces the syncDriver. The old synthesis chunks continue synthesizing on the serial queue but their callbacks feed into the now-replaced syncDriver (dropped silently) or create additional conflicts.
fix: Added isStreamingInProgress flag to TelegramBot. Set true at start of dispatchStreamingTTS, cleared via SubtitleSyncDriver.onStreamingComplete callback when last chunk finishes playing. dispatchTTS skips new dispatch if flag is set (logs warning with dropped char count). Edge cases handled: zero-chunk synthesis failure clears flag in onAllComplete; external stop() also fires callback.
verification: Build succeeds. Release binary installed and service restarted. Awaiting user confirmation with real notification traffic.
files_changed:

- plugins/claude-tts-companion/Sources/claude-tts-companion/TelegramBot.swift
- plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitleSyncDriver.swift
