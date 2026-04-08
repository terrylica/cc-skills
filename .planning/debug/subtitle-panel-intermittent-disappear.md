---
status: diagnosed
trigger: "Subtitle panel (NSPanel overlay) disappears completely and intermittently while TTS audio continues playing without interruption."
created: 2026-04-07T17:30:00-0700
updated: 2026-04-07T17:30:00-0700
---

## Current Focus

hypothesis: The v12.42.x diff does NOT touch any subtitle panel, SubtitleSyncDriver, or TTSPipelineCoordinator code. The disappearance is either (A) a pre-existing vulnerability from uncancellable delayed hide() calls in fallback paths, or (B) a macOS AppKit panel ordering issue unrelated to code changes.
test: Reviewed full diff v12.41.0..v12.42.2, read all five core files, tailed stderr logs
expecting: If regression is real, the diff must contain a code path that triggers hide() or orderOut() on the subtitle panel during active playback
next_action: Return diagnosis

## Symptoms

expected: Subtitle panel stays visible on screen for the entire duration of TTS playback, with karaoke highlighting advancing word-by-word in sync with audio.
actual: Panel disappears completely at unpredictable moments during playback. Audio keeps playing fine. Panel may reappear later or may not return until the next TTS request.
errors: No error logs found in stderr.log correlating with disappearance events. Logs show normal tick telemetry, clean segment transitions, and proper finishPlayback flow.
reproduction: Trigger any TTS playback and watch the floating subtitle panel. It may disappear mid-sentence.
started: Reported after deploying v12.42.x changes.

## Eliminated

- hypothesis: v12.42.x code changes directly cause panel disappearance
  evidence: Full diff (git diff v12.41.0..v12.42.2) shows changes ONLY in AfplayPlayer.swift (WAV path fallback chain), HTTPControlServer.swift (async /health endpoint), SettingsStore.swift (do/catch), TTSEngine.swift (CodingKeys). Zero lines changed in SubtitlePanel.swift, SubtitleSyncDriver.swift, TTSPipelineCoordinator.swift, or any file that calls hide()/orderOut() on the subtitle panel.
  timestamp: 2026-04-07T17:30:00

- hypothesis: Safety-net in tickStreaming() fires prematurely during pipelined playback
  evidence: The safety-net check (line 523 of SubtitleSyncDriver) requires `!afplay.isPipelinedMode`. During pipelined playback, isPipelinedMode=true. It only becomes false in advanceQueue() when queueComplete=true AND queue is empty (final segment). At that point, the allCompleteCallback fires synchronously on the same main-thread dispatch, setting currentChunkComplete=true. The 60Hz tick cannot interleave because all of this runs on the main thread.
  timestamp: 2026-04-07T17:30:00

- hypothesis: Stale lingerThenHide from previous playback hides panel during new playback
  evidence: lingerThenHide uses pendingLingerHide which is cancelled by: show(text:), hide(), and updateAttributedText(). When a new pipeline starts, cancelCurrentPipeline() calls hide() (cancels pending), then activateChunk() calls highlightWord(isPageTransition:true) which calls updateAttributedText() which also cancels pending. The stale timer is properly cancelled.
  timestamp: 2026-04-07T17:30:00

## Evidence

- timestamp: 2026-04-07T17:30:00
  checked: Full git diff v12.41.0..v12.42.2 for CompanionCore/
  found: Only 4 files changed: AfplayPlayer.swift (+200 lines WAV fallback), HTTPControlServer.swift (+8 lines health), SettingsStore.swift (+6 lines error logging), TTSEngine.swift (+7 lines CodingKeys). No changes to subtitle panel, sync driver, or pipeline coordinator.
  implication: The regression claim cannot be explained by the diff.

- timestamp: 2026-04-07T17:30:00
  checked: Stderr logs from last TTS playback session
  found: Clean 4-segment pipelined playback (66.50s total). All chunk transitions show proper activateChunk telemetry. finishPlayback fires once at the very end. No unexpected hide/orderOut calls logged. No errors correlating with panel disappearance.
  implication: The playback pipeline itself works correctly. The disappearance is not caused by the sync driver or pipeline coordinator.

- timestamp: 2026-04-07T17:30:00
  checked: All code paths that call subtitlePanel.hide() or orderOut(nil)
  found: 8 call sites: (1) SubtitlePanel.hide() directly, (2) lingerThenHide DispatchWorkItem, (3) showPages linger item, (4) TelegramBotNotifications.showSubtitleOnlyFallback (7s fire-and-forget), (5) TTSQueue.showSubtitleFallback (8s fire-and-forget), (6) HTTPControlServer /subtitle/hide, (7) HTTPControlServer /subtitle/show with duration, (8) TTSPipelineCoordinator.cancelCurrentPipeline.
  implication: Items 4 and 5 use fire-and-forget asyncAfter without cancellation. If these fire and a new TTS starts within the delay, the stale hide() fires during active playback.

- timestamp: 2026-04-07T17:30:00
  checked: SubtitlePanel.highlightWord hot path (60Hz, isPageTransition:false)
  found: The 60Hz word-advancement path ONLY sets textField.attributedStringValue. It does NOT call orderFrontRegardless(), positionOnScreen(), or cancel pendingLingerHide. Only page-transition calls (isPageTransition:true) perform these operations.
  implication: If the panel loses front ordering (macOS Spaces transition, Mission Control, display wake), the 60Hz hot path will NOT bring it back. Only the next chunk transition (activateChunk) would restore visibility.

- timestamp: 2026-04-07T17:30:00
  checked: Stage Manager status
  found: GloballyEnabled = 0 (disabled)
  implication: Ruled out Stage Manager as cause.

- timestamp: 2026-04-07T17:30:00
  checked: NSPanel configuration
  found: level=.floating, collectionBehavior=[.canJoinAllSpaces, .fullScreenAuxiliary], sharingType=.readOnly, canBecomeKey=false, canBecomeMain=false
  implication: Standard floating panel config. Should remain visible but macOS has known edge cases with floating panels during Space transitions and fullscreen app focus changes.

## Resolution

root_cause: INCONCLUSIVE — the v12.42.x diff does NOT contain changes that could cause panel disappearance. Two candidate explanations remain: (1) Pre-existing vulnerability: fire-and-forget asyncAfter hide() calls in TelegramBotNotifications.showSubtitleOnlyFallback and TTSQueue.showSubtitleFallback can hide the panel during active playback if a synthesis failure precedes a successful TTS within the delay window. (2) macOS AppKit panel ordering: the 60Hz karaoke hot path does not call orderFrontRegardless(), so if macOS demotes the floating panel (Spaces transition, fullscreen app focus, display wake), the panel stays hidden until the next chunk/page transition.
fix:
verification:
files_changed: []
