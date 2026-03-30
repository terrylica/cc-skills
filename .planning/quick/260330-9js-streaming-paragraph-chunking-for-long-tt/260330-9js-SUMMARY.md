---
phase: quick
plan: 260330-9js
subsystem: claude-tts-companion
tags: [tts, streaming, paragraph-chunking, subtitle-sync]
dependency_graph:
  requires: []
  provides: [streaming-paragraph-pipeline, tts-stop-endpoint]
  affects:
    [TTSQueue, TTSPipelineCoordinator, SubtitleSyncDriver, HTTPControlServer]
tech_stack:
  added: []
  patterns: [PlaybackContinuationBox for cross-isolation async signaling]
key_files:
  created: []
  modified:
    - plugins/claude-tts-companion/Sources/CompanionCore/TTSQueue.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/TTSPipelineCoordinator.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/SubtitleSyncDriver.swift
    - plugins/claude-tts-companion/Sources/CompanionCore/HTTPControlServer.swift
decisions:
  - PlaybackContinuationBox (@unchecked Sendable with NSLock.withLock) for cross-isolation continuation passing between @MainActor onComplete and actor-isolated await
  - Audio buffers scheduled by coordinator (not SubtitleSyncDriver.startBatchPlayback) for true incremental streaming
  - SubtitleSyncDriver detects end-of-stream via allChunksDelivered + AudioStreamPlayer empty buffer check
metrics:
  duration: 5min
  completed: 2026-03-30
---

# Quick Plan 260330-9js: Streaming Paragraph Chunking for Long TTS Summary

Paragraph-chunked streaming TTS pipeline: long text with \n\n splits into paragraphs synthesized sequentially, playback starts after first paragraph, POST /tts/stop cancels mid-stream.

## Commits

| Task | Name                                                             | Commit   | Key Files                                                              |
| ---- | ---------------------------------------------------------------- | -------- | ---------------------------------------------------------------------- |
| 1    | Streaming paragraph pipeline (TTSPipelineCoordinator + TTSQueue) | aa3e950b | TTSQueue.swift, TTSPipelineCoordinator.swift, SubtitleSyncDriver.swift |
| 2    | POST /tts/stop endpoint                                          | 7007be88 | HTTPControlServer.swift, TTSQueue.swift                                |

## What Changed

### Task 1: Streaming Paragraph Pipeline

**TTSQueue.executeWorkItem** now checks for `\n\n` in the assembled text:

- Single paragraph (no `\n\n`): unchanged existing batch pipeline path
- Multiple paragraphs: splits by `\n\n`, starts streaming pipeline BEFORE synthesis, loops over paragraphs calling synthesizeStreamingAutoRoute per-paragraph with cancellation checks, feeds each to the pipeline coordinator incrementally

**PlaybackContinuationBox**: New `@unchecked Sendable` helper class that bridges async/await continuation across isolation domains. The `@MainActor` onComplete callback calls `resume()`, and the actor-isolated TTSQueue calls `await wait()`. Uses `NSLock.withLock` (Swift 6 safe).

**TTSPipelineCoordinator** gains three new methods:

- `startStreamingPipeline(onComplete:)` -- creates SubtitleSyncDriver upfront, stores completion callback
- `addStreamingChunk(_:)` -- processes chunks with same subtitle logic as startBatchPipeline (Kokoro word alignment, punctuation reattachment, paragraph breaks), schedules audio directly on AudioStreamPlayer, activates first chunk for karaoke on first call
- `finalizeStreamingPipeline()` -- marks all chunks delivered on the driver

**SubtitleSyncDriver** gains:

- `activateFirstChunkForStreaming()` -- activates chunk 0 and starts 60Hz karaoke timer without calling startBatchPlayback
- End-of-stream detection in `tickStreaming()` via `allChunksDelivered && !asp.isPlaying && !asp.hasScheduledBuffers`

### Task 2: POST /tts/stop

**TTSQueue.stopAll()** -- cancels token, cancels task, drains queue, resets userRequestActive, calls cancelCurrentPipeline. Unlike `preempt()`, does NOT set `userRequestActive = true` (stop is not a new request).

**HTTPControlServer** -- new `POST /tts/stop` route (API-10) that awaits `ttsQueue.stopAll()` and returns `{"ok": true}`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] SubtitleSyncDriver incompatible with incremental chunk scheduling**

- **Found during:** Task 1
- **Issue:** `startBatchPlayback()` sets `allChunksDelivered = true` and only schedules existing chunks. Calling it after the first paragraph would prevent subsequent paragraphs from being played.
- **Fix:** Coordinator schedules audio buffers directly on AudioStreamPlayer. New `activateFirstChunkForStreaming()` method on SubtitleSyncDriver starts karaoke without batch scheduling. End-of-stream detection added via AudioStreamPlayer empty buffer check.
- **Files modified:** TTSPipelineCoordinator.swift, SubtitleSyncDriver.swift

**2. [Rule 3 - Blocking] Swift 6 strict concurrency errors with NSLock in async context**

- **Found during:** Task 1
- **Issue:** `NSLock.lock()/unlock()` unavailable in async contexts in Swift 6. PlaybackContinuationBox initially used direct lock/unlock.
- **Fix:** Restructured to use `NSLock.withLock {}` and a non-async helper method `checkAndStoreContinuation()`.
- **Files modified:** TTSQueue.swift

**3. [Rule 3 - Blocking] Swift 6 Sendable data race errors with mutable vars captured in Task**

- **Found during:** Task 1
- **Issue:** Initial implementation used `withCheckedContinuation` + `DispatchQueue.main.async` + inner `Task {}` with mutable vars crossing isolation boundaries. Swift 6 flagged SendingRisksDataRace.
- **Fix:** Restructured to run synthesis loop in the actor context (not a detached Task), using PlaybackContinuationBox for the completion signal instead of wrapping everything in a continuation.
- **Files modified:** TTSQueue.swift

## Known Stubs

None. All paths are fully wired.

## Self-Check: PASSED

All 4 modified files exist. Both commits (aa3e950b, 7007be88) verified in git log. swift build succeeds.
