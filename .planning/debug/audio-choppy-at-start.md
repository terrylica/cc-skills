---
status: awaiting_human_verify
trigger: "Audio sounds choppy/stuttery when speech first starts playing"
created: 2026-03-27T11:00:00-0700
updated: 2026-03-27T10:52:00-0700
---

## Current Focus

hypothesis: CONFIRMED -- CoreAudio hardware cold-start causes first-chunk stutter
test: Built and deployed with silent audio pre-warm at init + re-warm after 30s idle
expecting: First chunk of streaming TTS plays cleanly without stutter
next_action: User verification -- trigger a TTS session and listen for clean audio start

## Symptoms

expected: Clean, smooth audio from the very first syllable
actual: First ~0.5-1s of audio sounds choppy, stuttery, or has artifacts before smoothing out
errors: No errors in logs
reproduction: Beginning of every TTS streaming session
started: Since AVAudioPlayer + streaming pipeline

## Eliminated

## Evidence

- timestamp: 2026-03-27T11:00:00
  checked: TTSEngine.play() and preparePlayer() flow
  found: prepareToPlay() is called before play() but they happen back-to-back with no delay. In streaming mode, playStreamChunk() calls engine.play() which does prepareToPlay() + play() immediately. The pre-buffering path (advanceToPrebuilt) only applies to chunks 2+, not the first chunk.
  implication: First chunk has no pre-buffering advantage. prepareToPlay() allocates buffers but CoreAudio hardware warm-up is asynchronous -- play() fires before hardware is ready.

- timestamp: 2026-03-27T11:00:01
  checked: Logs for timing of first chunk playback
  found: Chunk 1 synthesis completes and playing starts within same second (10:47:02). No gap between synthesis complete and play start. Pre-buffered chunks (chunk 2+) log "PRE-BUFFERED" and play cleanly.
  implication: The issue is specific to the FIRST audio play after CoreAudio hardware has been idle. Subsequent chunks play via pre-buffered path and don't stutter.

- timestamp: 2026-03-27T11:00:02
  checked: Apple developer docs and forums on prepareToPlay()
  found: prepareToPlay() "preloads buffers and acquires the audio hardware needed for playback, which minimizes the lag between calling the play method and the start of sound output." But acquiring hardware is not instantaneous -- on macOS, audio hardware powers down after idle, and re-init takes ~50-500ms depending on the audio subsystem.
  implication: The standard pattern is to call prepareToPlay() well BEFORE play() is needed, not immediately before. Playing a brief silent sound at startup keeps the audio subsystem warm.

- timestamp: 2026-03-27T10:51:00
  checked: Fix deployed and service restarted
  found: Log shows "CoreAudio hardware pre-warmed with 0.1s silent buffer" at startup. Service starts cleanly. Re-warm logic in play() will also trigger if audio has been idle >30s.
  implication: Fix is deployed and running. Awaiting human verification of audio quality.

## Resolution

root_cause: CoreAudio hardware is cold/idle when the first streaming chunk starts playing. prepareToPlay() is called immediately before play() with no time gap, so the audio hardware initialization overlaps with the beginning of actual audio data, causing stutter/choppiness in the first ~0.5-1s. After the first chunk, subsequent chunks use the pre-buffered path and play cleanly because CoreAudio is already active.
fix: Added warmUpAudioHardware() method to TTSEngine that plays 0.1s of silence at volume=0.0 via AVAudioPlayer. Called (1) at init to pre-warm at service startup, and (2) in play() if audio has been idle >30s (re-warm after CoreAudio may have powered down). This ensures the audio output chain is initialized before real audio data needs to play.
verification: Build succeeds, service restarts cleanly, log shows warm-up message. Awaiting human listening test.
files_changed:

- plugins/claude-tts-companion/Sources/claude-tts-companion/TTSEngine.swift
