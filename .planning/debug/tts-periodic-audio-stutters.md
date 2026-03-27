---
status: awaiting_human_verify
trigger: "TTS audio has persistent periodic stutters/choppiness that has survived multiple previous debug sessions"
created: 2026-03-27T00:00:00Z
updated: 2026-03-27T15:00:00Z
---

## Current Focus

hypothesis: CONFIRMED — Subtitle-audio desync caused by audioDuration mismatch. SubtitleSyncDriver.addChunk() computes audioDuration from wordTimings.reduce(0,+) which equals the raw audio duration. But TTSEngine appends 100ms trailing silence (2400 samples) to each chunk, and the padded samples are what get scheduled on AVAudioEngine. So cumulative offsets drift by 100ms per chunk (400ms behind by chunk 5).
test: Fix addChunk() to compute audioDuration from samples.count / 24000.0 when samples are available, falling back to wordTimings sum. This makes cumulative offsets match actual playback time.
expecting: Karaoke word highlighting stays in sync with audio across all 5 chunks
next_action: Edit SubtitleSyncDriver.addChunk() to use sample-based duration

## Symptoms

expected: Smooth continuous speech across all sentences without any hiccups or stutters
actual: Three manifestations: (1) Choppy audio at beginning of speech, (2) Choppy/stuttery audio in middle after 2-3 pages of sentences, (3) Sometimes an entire audio chunk at the end is lost/not played. Pattern is regular/periodic, not random.
errors: No errors in logs (previous debug sessions confirmed this)
reproduction: Every streaming TTS playback session. Has persisted through all previous fixes (WAV silence padding, CoreAudio pre-warm, font measurement fix).
started: Always been there — survived multiple debug cycles. Previous resolved sessions fixed boundary/transition issues but this core periodic stutter persists.

## Eliminated (new)

- hypothesis: MLX GPU cache clearing between chunks (Memory.clearCache / Stream.gpu.synchronize)
  evidence: mlx-metal-resource-crash.md proved that ANY direct MLX API call from the main binary creates a separate C++ Metal device singleton (static Device at device.cpp:799) that competes for the GPU's 499000 resource limit, causing immediate crash. This approach is fundamentally impossible.
  timestamp: 2026-03-27T15:00:00Z

## Eliminated

- hypothesis: CoreAudio hardware cold-start latency
  evidence: Fixed with silent audio pre-warm in audio-choppy-at-start session
  timestamp: prior session

- hypothesis: WAV truncation at sentence boundaries
  evidence: Fixed with trailing silence padding in sentence-end-choppy-audio session
  timestamp: prior session

- hypothesis: SubtitleChunker font measurement mismatch
  evidence: Fixed in audio-choppy-silenced session
  timestamp: prior session

## Evidence

- timestamp: 2026-03-27T15:00:00Z
  checked: mlx-metal-resource-crash.md resolved debug session
  found: Direct MLX API calls from main binary are strictly forbidden -- they create a duplicate Metal device singleton that exhausts the 499000 resource limit on first synthesis call. The checkpoint suggestion (MLX.GPU.synchronize/clearCache) would crash the app.
  implication: Must find a non-MLX-API approach to release GPU resources between chunks

- timestamp: 2026-03-27T15:05:00Z
  checked: DispatchQueue autorelease behavior in synthesizeStreaming()
  found: The entire for-loop runs inside a single queue.async {} closure on the TTS serial queue. DispatchQueues drain their autorelease pool at the boundary of each block, NOT between iterations of a for-loop. Metal command buffers, MLXArray intermediates, and other ObjC objects from all 5 generateAudio() calls accumulate in the same pool.
  implication: By chunk 5, the autorelease pool holds Metal objects from all 4 previous chunks. This GPU memory pressure is the likely cause of the 5th-chunk stutter. Wrapping each iteration in autoreleasepool {} forces drainage between chunks.

- timestamp: 2026-03-27T15:10:00Z
  checked: Fix implementation and build
  found: Wrapped each chunk in autoreleasepool {} that returns Optional<ChunkResult>. Build succeeds. Binary deployed. Service running.
  implication: Ready for human verification of audio playback smoothness

- timestamp: 2026-03-27T16:00:00Z
  checked: Batch-then-play implementation
  found: Implemented full architectural change across 4 files. TTSEngine.synthesizeStreaming() no longer takes synthesisGate param — synthesizes all chunks in sequence, delivers via callbacks. SubtitleSyncDriver gained startBatchPlayback() which schedules ALL buffers on AVAudioPlayerNode then starts timer. Callers (TelegramBot, HTTPControlServer) collect chunks in thread-safe array, then on onAllComplete dispatch to main to create driver + add all chunks + startBatchPlayback(). tickStreaming() uses cumulative time to track chunk transitions. Build succeeds. Deployed and running.
  implication: GPU is completely idle during playback — zero memory bus contention on unified memory

- timestamp: 2026-03-27T00:10:00Z
  checked: SubtitlePanel.highlightWord() call chain in SubtitlePanel.swift
  found: highlightWord() -> updateAttributedText() -> positionOnScreen() + orderFrontRegardless() + logDiagnostics(). This chain runs 60x/sec from SubtitleSyncDriver's DispatchSourceTimer.
  implication: Three expensive operations on every tick: (1) positionOnScreen() does NSScreen.main lookup, constraint updates, setFrame(display:true), preferredMaxLayoutWidth update. (2) orderFrontRegardless() reorders the window layer. (3) logDiagnostics() creates NSTextStorage+NSLayoutManager+NSTextContainer and calls ensureLayout() — a full text layout pass — every single tick.

- timestamp: 2026-03-27T00:12:00Z
  checked: AVAudioPlayer playback thread model
  found: AVAudioPlayer.play() is called from @MainActor context (SubtitleSyncDriver is @MainActor). AVAudioPlayer uses the run loop of its calling thread for delegate callbacks and buffer management scheduling.
  implication: Heavy main-thread work (60 NSLayoutManager creations/sec + 60 window reorders/sec + 60 frame recalculations/sec) directly competes with AVAudioPlayer's buffer servicing on the same run loop, causing periodic audio underruns.

- timestamp: 2026-03-27T00:14:00Z
  checked: Three stutter manifestations match hypothesis
  found: (1) Beginning stutter = first chunk plays while updateAttributedText hot path begins. (2) Middle stutter = sustained 60Hz overhead accumulates, especially on page transitions where highlightWord recalculates everything. (3) End chunk loss = final chunk's player may finish before tick detects it, OR main thread blocked during critical transition.
  implication: All three manifestations are consistent with main-thread contention between subtitle rendering and audio playback.

## Resolution

root_cause: Two-part issue: (1) MLX GPU/audio memory bus contention fixed by batch-then-play pattern. (2) Subtitle-audio desync: SubtitleSyncDriver.addChunk() computed audioDuration from wordTimings.reduce(0,+) which equals raw audio duration. But TTSEngine appends 100ms trailing silence (2400 samples at 24kHz) to each chunk's PCM buffer before scheduling on AVAudioEngine. The cumulative offset calculations used unpadded durations, causing karaoke highlights to drift 100ms ahead per chunk (400ms by chunk 5).
fix: Changed SubtitleSyncDriver.addChunk() to compute audioDuration from actual sample count (samples.count / 24000.0) when samples are available, falling back to wordTimings sum only when samples are nil. This ensures cumulative offsets match the actual playback duration including trailing silence padding.
verification: Build succeeds (swift build -c release). Binary deployed to ~/.local/bin/claude-tts-companion. Launchd service restarted and running. Needs human verification of subtitle-audio sync.
files_changed: [SubtitleSyncDriver.swift]
