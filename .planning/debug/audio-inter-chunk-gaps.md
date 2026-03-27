---
status: awaiting_human_verify
trigger: "Audio has ~1 second silence between streaming chunks. User hears choppy audio with gaps, and audio sometimes goes silent while subtitles keep playing."
created: 2026-03-26T20:40:00-0700
updated: 2026-03-26T20:40:00-0700
---

## Current Focus

hypothesis: Gap caused by synchronous AVAudioPlayer creation in playStreamChunk -- tick() detects !isPlaying, then playStreamChunk creates new player + prepareToPlay() + play() taking ~500ms-1s
test: Read the chunk transition code path in tickStreaming() -> playStreamChunk()
expecting: No pre-buffering of next chunk; player created on-demand after current finishes
next_action: Confirm root cause in code, then implement pre-buffering fix

## Symptoms

expected: Seamless audio across streaming chunks -- no audible gaps
actual: ~1 second silence between every chunk transition. Audio sometimes stops entirely while subtitles continue.
errors: No errors -- all AVAudioPlayer instances finish with success: true
reproduction: Every streaming TTS playback with multiple chunks
started: Since streaming pipeline implementation

## Eliminated

## Evidence

- timestamp: 2026-03-26T20:40:00
  checked: SubtitleSyncDriver.swift tickStreaming() and playStreamChunk()
  found: tickStreaming() line 372 checks !currentPlayer.isPlaying, then calls playStreamChunk(at: currentChunkIndex + 1). playStreamChunk() at line 277 creates a brand new AVAudioPlayer via engine.play(wavPath:), which internally does AVAudioPlayer(contentsOf:) + prepareToPlay() + play(). No pre-buffering exists.
  implication: Confirms the gap mechanism: detection -> creation -> prepare -> play is sequential and takes ~500ms-1s

- timestamp: 2026-03-26T20:40:00
  checked: TTSEngine.play() method (line 187-204)
  found: play() creates AVAudioPlayer, calls prepareToPlay(), then play() synchronously. Also creates a new PlaybackDelegate each time. The delegate cleans up the WAV file on completion.
  implication: WAV cleanup on completion could delete the file before the next chunk even starts if chunks share naming patterns, but each has UUID so this is not the gap cause

## Resolution

root_cause: tickStreaming() detects !isPlaying then calls playStreamChunk() which synchronously creates AVAudioPlayer + prepareToPlay() + play(). The prepareToPlay() call fills audio hardware buffers from disk, taking ~500ms-1s, creating audible gaps between every chunk transition.
fix: Pre-buffer the next chunk's AVAudioPlayer while the current one is still playing. Added prebufferNextChunk() which calls TTSEngine.preparePlayer() (new method) to create+prepare without playing. advanceToPrebuilt() uses the pre-buffered player on transition -- just calls play() which is near-instant. Pre-buffering is triggered (a) after each chunk starts playing, and (b) when addChunk() delivers the chunk right after the currently playing one.
verification: Build succeeds, service restarts cleanly. Awaiting real streaming TTS playback test from user.
files_changed: [SubtitleSyncDriver.swift, TTSEngine.swift]
