---
status: awaiting_human_verify
trigger: "Two related issues: (1) TTS gets cut off right after greeting when agent dispatches a new session, (2) Subtitles show and advance but no audio plays"
created: 2026-03-27T11:20:00-0700
updated: 2026-03-27T11:35:00-0700
---

## Current Focus

hypothesis: CONFIRMED - Two root causes identified from log evidence:

1. MLX metal resource exhaustion ([metal::malloc] Resource limit 499000 exceeded) crashes the entire process mid-playback. The crash happens during synthesis of subsequent chunks while earlier chunks are still playing. This is the "TTS cutoff" issue.
2. When a NEW TTS dispatch arrives while the previous session's SyncDriver is still playing/waiting for chunks, the `isStreamingInProgress` guard does NOT block it (because the previous session may have already set it to false via onStreamingComplete). The new dispatch calls `dispatchStreamingTTS()` which queues synthesis on the TTS serial queue, but the OLD SyncDriver's timer is still running and waiting for chunks that will never arrive (the TTS queue now serves the new session). The old SyncDriver shows stale subtitles with no audio, and its "Waiting for chunk N" spam fills logs. Meanwhile the new session's chunks get synthesized but the isFirst logic in onChunkReady creates a NEW SyncDriver that replaces the old one only when the first chunk is ready.

The core design problem: dispatchStreamingTTS() does NOT cancel the previous streaming pipeline before starting a new one. It relies on the `isStreamingInProgress` boolean guard, but this guard is cleared by the PREVIOUS session's onStreamingComplete callback. Between that callback and the NEW session's first chunk arriving, there's a window where the OLD SyncDriver is orphaned but still running.

Fix plan:

1. Cancel previous SyncDriver and stop playback IMMEDIATELY in dispatchStreamingTTS() (not just when first chunk arrives)
2. Add MLX memory cleanup between synthesis sessions to prevent metal resource exhaustion

test: Apply fix, build, deploy, trigger two back-to-back notifications
expecting: Previous session cleanly cancelled, new session plays without crash or orphaned subtitles
next_action: Implement fix in TelegramBot.swift

OLD hypothesis below for record:

hypothesis: TTSEngine.play() overwrites self.audioPlayer and self.playbackDelegate on EVERY call, including streaming chunk playback via SubtitleSyncDriver. When the first streaming chunk calls engine.play(), it stores the player in engine.audioPlayer. When ttsEngine.stopPlayback() is called for a NEW session's first chunk (line 259), it stops the engine.audioPlayer -- but the streaming SyncDriver's streamPlayer is a DIFFERENT reference. The real bug: engine.play() sets self.playbackDelegate which REPLACES the previous delegate, meaning if chunk N's delegate gets replaced by chunk N+1's delegate before N finishes, the completion callback for N never fires and the WAV gets orphaned. BUT more critically: engine.play() stores a SINGLE audioPlayer reference, so when the SyncDriver calls play() for chunk 2, it overwrites audioPlayer with chunk 2's player, and chunk 1's PlaybackDelegate gets dealloced (since playbackDelegate is replaced), causing chunk 1's player to lose its delegate mid-playback.

WAIT -- re-reading more carefully. The SyncDriver for streaming uses engine.play() which sets engine.audioPlayer. But the SyncDriver also holds its OWN streamPlayer reference. The issue is about delegate lifecycle.

Actually, re-reading the flow: In streaming mode, `playStreamChunk()` calls `engine.play()` which:

1. Creates a new AVAudioPlayer
2. Sets `self.playbackDelegate = delegate` (REPLACING any previous delegate)
3. Sets `self.audioPlayer = player` (REPLACING previous player ref)
4. Calls player.play()
5. Returns the player

The SyncDriver stores the returned player in `self.streamPlayer`. BUT the PlaybackDelegate is only held by `engine.playbackDelegate`. When chunk 2 arrives and `playStreamChunk()` calls `engine.play()` again, the old delegate for chunk 1 gets deallocated because `engine.playbackDelegate` is overwritten. If chunk 1's player still has a weak reference to the delegate, the delegate callback never fires. BUT more importantly: chunk 1's player is STILL PLAYING when this happens (the SyncDriver's tick() detects `!currentPlayer.isPlaying` to know when to advance). So the delegate dealloc shouldn't break playback per se.

Let me re-focus on the ACTUAL reported issue: subtitles show but NO audio plays.

NEW HYPOTHESIS: The `ttsEngine.stopPlayback()` call on line 259 (first chunk handler) stops `engine.audioPlayer`. But at this point, `engine.audioPlayer` might be nil (no previous playback) or pointing to a PREVIOUS session's player. That's fine. The REAL issue is that `engine.play()` called from `playStreamChunk()` stores the new player in `engine.audioPlayer`. Then when the SECOND notification arrives, it hits the `isStreamingInProgress` guard (line 206) and gets DROPPED. So the second notification is never played. But the user says subtitles show for the SECOND notification too. How?

RE-READ THE TELEMETRY: "11:12:13 Dispatching TTS: 1590 chars" -- this is the second session. The isStreamingInProgress guard did NOT block it. So either: (a) the first session's streaming completed before the second arrived, or (b) isStreamingInProgress was never set to true for the first session, or (c) the first session used the non-streaming path.

Looking at the timeline again: 11:11:13 = first session subtitles showing. 11:12:13 = second dispatch. That's 60s apart. The first session's streaming could have completed by then (streaming complete callback fires onStreamingComplete which sets isStreamingInProgress = false).

So the REAL question: why does the second dispatch synthesize chunks but never play them?

Key observation from telemetry: "Streaming chunk 1/15 ready: 7.90s" at 11:12:17, then subtitles update but NO "Playing WAV" or "Playing stream chunk" log.

REFINED HYPOTHESIS: The `playStreamChunk()` method calls `engine.play()` which logs "Playing WAV via AVAudioPlayer". If that log is ABSENT, then either play() was never called, or play() failed (returned nil). Looking at playStreamChunk() line 301: it calls `engine.play(wavPath: chunk.wavPath, completion: {...})`. If this returns nil, line 305 logs an error and tries next chunk.

But there's a subtler issue: the `onChunkReady` callback dispatches to main thread (line 256). For the FIRST chunk (isFirst=true), it creates a new SyncDriver (line 264). Then calls `syncDriver?.addChunk()` (line 278). Inside addChunk(), when `streamChunks.count == 1`, it calls `playStreamChunk(at: 0)` which calls `engine.play()`.

BUT WAIT: line 259 calls `self.ttsEngine.stopPlayback()` BEFORE creating the SyncDriver. `stopPlayback()` sets `engine.audioPlayer = nil` and `engine.playbackDelegate = nil`. Then `playStreamChunk()` calls `engine.play()` which creates a NEW player and stores it in `engine.audioPlayer`. This should work.

UNLESS: there's a timing issue where `stopPlayback()` is called from the main thread, but the TTS queue's callback can also modify `engine.audioPlayer`. No -- `play()` is documented as "must be called on main thread" and the streaming code dispatches to main.

Let me check if the delegate getting replaced could cause the AVAudioPlayer to stop prematurely. When `engine.play()` is called for streaming chunk 1, it sets `engine.playbackDelegate` to a new PlaybackDelegate. When `engine.play()` is called for chunk 2 (via the tickStreaming -> advanceToPrebuilt or playStreamChunk path... but wait, the pre-buffered path uses `preparePlayer()` not `play()`). For pre-buffered chunks, `advanceToPrebuilt()` calls `player.play()` directly without going through `engine.play()`. So the engine.audioPlayer still points to chunk 1's player.

AH WAIT. For the FIRST chunk, `playStreamChunk()` calls `engine.play()`. For subsequent pre-buffered chunks, `advanceToPrebuilt()` just calls `player.play()`. But the engine.audioPlayer STILL HOLDS chunk 1's player reference. So when the streaming session ends and a NEW dispatch comes in, `ttsEngine.stopPlayback()` only stops chunk 1's player (which already finished). That's fine.

Let me re-examine more carefully. What if the WAV file gets cleaned up before the player can read it?

PlaybackDelegate.audioPlayerDidFinishPlaying() cleans up the WAV file at line 880. When streaming chunk 1 finishes playing, its delegate fires and deletes the WAV. But the delegate was created by `engine.play()` and stored in `engine.playbackDelegate`. When chunk 2 starts via `advanceToPrebuilt()`, the engine.playbackDelegate is NOT updated (advanceToPrebuilt doesn't call engine.play()). So engine.playbackDelegate still points to chunk 1's delegate. Chunk 1's delegate will fire and clean up chunk 1's WAV -- that's correct.

But chunk 2's delegate (nextPlaybackDelegate) is set in preparePlayer(). Looking at preparePlayer() -- it creates a PlaybackDelegate with the wavPath and completion. The advanceToPrebuilt() method promotes nextPlaybackDelegate to streamPlaybackDelegate. Good, the delegate is retained.

OK I'm going in circles. Let me focus on the SIMPLEST explanation for "chunks synthesized but never played": the `addChunk()` method is called but `playStreamChunk()` is never reached for the first chunk.

Look at addChunk() line 218: `if streamChunks.count == 1 { playStreamChunk(at: 0) }`. This should fire for the first chunk. UNLESS the SyncDriver was never created. Let me trace from the onChunkReady callback:

1. onChunkReady fires on TTS queue (line 247)
2. Dispatches to main thread (line 256)
3. On main: if isFirst, create SyncDriver (line 264), assign to self.syncDriver (line 272)
4. Call self.syncDriver?.addChunk() (line 278)

But self.syncDriver is `var syncDriver: SubtitleSyncDriver?` on TelegramBot. The SyncDriver is @MainActor. The assignment at line 272 is inside DispatchQueue.main.async, so it runs on main thread. The addChunk at line 278 is also in the same DispatchQueue.main.async block, so it runs AFTER the assignment. This should work.

UNLESS there's a second DispatchQueue.main.async block queued from a DIFFERENT chunk that runs between line 272 and 278. But they're in the same block, so they execute atomically on the main queue.

I think I need to check for ISSUE 1 (cutoff) separately. The cutoff happens when the second notification's dispatchTTS calls dispatchStreamingTTS which calls isStreamingInProgress guard. If the first session's streaming is still playing when the second notification arrives, isStreamingInProgress=true and the second is DROPPED. But the log shows "Dispatching TTS: 1590 chars" for the second session, which means it got past the guard. So isStreamingInProgress was false.

WAIT -- but the user says "First TTS plays greeting then gets cut immediately when second notification arrives." This implies the FIRST session IS still playing when the second arrives. But the guard would block the second. Unless the first session used the non-streaming (full) path?

Actually, re-reading the dispatchTTS flow: line 226 checks `Config.streamingTTS`. If streaming is on, it calls dispatchStreamingTTS which sets isStreamingInProgress=true. If the first session's greeting is still playing (via streaming), isStreamingInProgress=true, and the second session's dispatchTTS hits the guard at line 206 and is DROPPED with "Skipping TTS dispatch".

But the log shows the second session IS dispatched ("Dispatching TTS: 1590 chars"). This means either:
(a) isStreamingInProgress was already false (first session finished), or
(b) The log at line 224 runs BEFORE the guard at line 206

Looking at the code: line 206-209 is the guard, line 224 is the log. The guard is checked FIRST. So if we see "Dispatching TTS", the guard passed.

So for the second session, isStreamingInProgress=false. But then the streaming chunks are synthesized and never played. This is the puzzle.

NEW REALIZATION: Look at the sequence for the SECOND session:

1. dispatchTTS -> guard passes (isStreamingInProgress=false)
2. dispatchStreamingTTS -> sets isStreamingInProgress=true (line 236)
3. onChunkReady fires -> dispatches to main thread
4. On main: isFirst=true, so:
   - stopPlayback() (line 259)
   - syncDriver?.stop() (line 260) -- this stops the FIRST session's sync driver
   - syncDriver = nil (line 261)
   - Creates new SyncDriver (line 264) with streaming init
   - self.syncDriver = driver (line 272)
5. Then: self.syncDriver?.addChunk(...) (line 278)
6. addChunk: streamChunks.count == 1, so playStreamChunk(at: 0)
7. playStreamChunk calls engine.play() which should log "Playing WAV"

If "Playing WAV" is not logged, engine.play() either wasn't reached or returned nil.

HYPOTHESIS: The WAV file was already cleaned up. The PlaybackDelegate from `stopPlayback()` at line 259 -- wait, stopPlayback() just sets audioPlayer=nil and playbackDelegate=nil. It doesn't delete WAV files. The WAV is deleted by PlaybackDelegate.audioPlayerDidFinishPlaying(). So if stopPlayback() calls player.stop(), the delegate's didFinishPlaying should fire... but player.stop() does NOT trigger audioPlayerDidFinishPlaying per Apple docs. Only natural completion does.

Actually, let me check: stopPlayback() at line 508-512 calls audioPlayer?.stop(). The engine.audioPlayer at this point is the player from the FIRST session's last chunk. Stopping it is fine.

ANOTHER HYPOTHESIS: Maybe the WAV file from the second session's synthesis hasn't been written yet when play() tries to read it? No -- synthesis completes first, then onChunkReady fires.

Let me look more carefully at the SyncDriver.stop() call at line 260. The stop() method (line 238-252):

- Cancels timer
- Stops streamPlayer
- Stops nextStreamPlayer
- If !didFinish: calls onStreamingComplete?() and sets it to nil

The onStreamingComplete for the FIRST session's SyncDriver sets `isStreamingInProgress = false`. But we already established isStreamingInProgress is false when the second session starts. So this is fine.

BUT WAIT: When the SECOND session creates a new SyncDriver at line 264, it passes a NEW onStreamingComplete callback that sets isStreamingInProgress = false. But isStreamingInProgress was ALREADY set to true at line 236 for the second session. The second session's onStreamingComplete should fire when the second session's playback finishes.

I think the key insight is: what if playStreamChunk(at: 0) for the second session calls engine.play() and the play() call FAILS because of something?

Let me check play() error paths: line 210 creates AVAudioPlayer(contentsOf: url). This can fail if the file doesn't exist. The WAV was just written by the synthesis queue. It should exist. Unless... the file was cleaned up by a DIFFERENT PlaybackDelegate.

AH HA. Here's a potential race condition: The first session had a streaming pipeline. Each chunk's `engine.play()` sets `engine.playbackDelegate` to a new delegate. When the first session's last chunk finishes playing naturally, audioPlayerDidFinishPlaying fires on the delegate, which calls `try? FileManager.default.removeItem(atPath: wavPath)` -- this removes the FIRST session's last chunk WAV, not the second session's. So that's OK.

Actually, I think the issue might be simpler. Let me re-read engine.play():

```swift
func play(wavPath: String, completion: (() -> Void)? = nil) -> AVAudioPlayer? {
    ...
    let player = try AVAudioPlayer(contentsOf: url)
    let delegate = PlaybackDelegate(wavPath: wavPath, completion: completion, logger: logger)
    self.playbackDelegate = delegate  // REPLACES previous delegate
    player.delegate = delegate
    player.prepareToPlay()
    player.play()
    self.audioPlayer = player
    self.lastPlaybackTime = now
    logger.info("Playing WAV via AVAudioPlayer: ...")
    return player
}
```

When the first session's SyncDriver is playing chunk N via engine.play(), engine.playbackDelegate = chunk N's delegate. When chunk N+1 is prebuffered via preparePlayer(), a separate delegate is created but NOT stored in engine.playbackDelegate.

When the second session starts, stopPlayback() (line 259) sets engine.audioPlayer=nil and engine.playbackDelegate=nil. The first session's SyncDriver's streamPlayer (chunk N) still exists and may still be playing. When it finishes, its delegate fires -- but wait, the delegate was the one stored in engine.playbackDelegate which was just set to nil. Actually no -- the delegate is the player.delegate, which is set at creation time and never cleared. The player holds a strong reference to the delegate... actually, AVAudioPlayer.delegate is a WEAK reference per Apple docs!

THERE IT IS. AVAudioPlayer.delegate is WEAK. The only strong reference to the delegate is engine.playbackDelegate. When stopPlayback() sets engine.playbackDelegate = nil, the delegate gets deallocated, and the player's weak delegate becomes nil. So the audioPlayerDidFinishPlaying callback never fires. This means the WAV cleanup doesn't happen -- but that's a memory leak, not the reported bug.

Wait, but for streaming mode, the delegates are managed differently. The SyncDriver has `streamPlaybackDelegate` which holds the delegate. Let me check... actually it doesn't. Looking at preparePlayer() -- it returns `(player, delegate)` and the SyncDriver stores them. But for the FIRST chunk, engine.play() is used, not preparePlayer(). So the first chunk's delegate is ONLY held by engine.playbackDelegate.

OK this analysis is getting complex. Let me approach from a different angle: what specific condition would cause "Playing WAV" to NOT appear in logs?

The only way "Playing WAV" doesn't appear is if engine.play() is never called or throws. Let me check what calls engine.play() in streaming mode: playStreamChunk() at line 301. If that guard fails at line 296 (`guard let engine = ttsEngine`), we'd see the error log. If AVAudioPlayer creation fails at line 301, we'd see the error at line 305.

Unless... playStreamChunk() is never called at all. How? addChunk() at line 218 checks `streamChunks.count == 1` for first chunk. If addChunk isn't called... but we see the subtitles showing, which means highlightWord is being called, which means the SyncDriver IS running.

Wait -- the subtitles show but advance on the SAME PAGE for 12+ seconds. The SyncDriver's tick function needs a playing player to advance words. If streamPlayer is nil, tickStreaming() exits at line 465. But subtitles ARE updating. Unless... the first page is shown by addChunk() -> playStreamChunk() -> line 289 (`subtitlePanel.highlightWord(at: 0, in: firstPage.words)`), and then the timer tick keeps calling highlightWord with the same index because the player isn't playing?

Actually no -- if the player isn't playing, tickStreaming() would detect `!currentPlayer.isPlaying` and try to advance to the next chunk. But if there's no next chunk yet (waiting for synthesis), it would set waitingForNextChunk=true. When the next chunk arrives via addChunk(), it would call playStreamChunk(). But the same "Playing WAV" log would appear.

I think I need to read the logs for the ACTUAL incident more carefully. The available logs are from after a restart. The incident was before the restart. Let me search the full log file for the patterns described.

test: Search full log file for "Dispatching TTS" and "Skipping TTS dispatch" patterns near 11:11 timeframe
expecting: Will find the actual sequence of events
next_action: Search log file for incident evidence

## Symptoms

expected: Full TTS playback with synchronized audio and subtitles for each session notification
actual: |
Issue 1: First TTS plays greeting "Hi Terry, you were working in cc-skills:" then gets cut immediately when second notification arrives
Issue 2: Subtitles show and update (same page text for 12+ seconds) but no audio at all
errors: No errors in logs
reproduction: Two notifications arriving within ~60s of each other
started: After isStreamingInProgress guard and pre-buffering changes

## Eliminated

## Evidence

- timestamp: 2026-03-27T11:20:00
  checked: stderr.log last 200 lines
  found: Log starts at 11:13:43 (during a previous streaming session), then SIGTERM restart at 11:13:53, then fresh start. The actual incident (11:11-11:12) was before the log window.
  implication: Need to search earlier in the full 6.5MB log file for the incident

- timestamp: 2026-03-27T11:22:00
  checked: Code flow analysis of dispatchStreamingTTS + SubtitleSyncDriver.addChunk + playStreamChunk + TTSEngine.play
  found: AVAudioPlayer.delegate is a WEAK reference. engine.playbackDelegate is the only STRONG ref for delegates created via engine.play(). In streaming mode, only the FIRST chunk uses engine.play() -- subsequent prebuffered chunks use preparePlayer() and manage their own delegate lifecycle via SyncDriver.streamPlaybackDelegate/nextPlaybackDelegate. When a new session starts, stopPlayback() nils engine.playbackDelegate, potentially deallocating the first chunk's delegate mid-playback.
  implication: This could cause chunk 1 delegate callbacks to silently fail, but shouldn't prevent playback itself.

## Resolution

root_cause: |
Two interrelated issues:

1. MLX metal resource exhaustion: When a 17-chunk synthesis runs back-to-back with previous sessions, metal::malloc hits the 499000 resource limit and crashes the process. No MLX memory cleanup between sessions.
2. Orphaned SyncDriver: dispatchStreamingTTS() defers cancellation of the previous SyncDriver until the FIRST chunk of the NEW session is ready (inside the isFirst block in onChunkReady). During the ~4-18s synthesis delay for the first chunk, the OLD SyncDriver's 60Hz timer keeps polling an already-finished-or-missing player, spamming "Waiting for chunk N" logs and showing stale subtitles. The new session's audio doesn't play because the SyncDriver isn't created yet.
   fix: |
3. Move SyncDriver cancellation from onChunkReady first-chunk handler to the START of dispatchStreamingTTS() -- cancel previous playback immediately when new TTS is dispatched, not when first chunk arrives.
4. Add MLX.GPU.drain() / eval fence between streaming sessions to release metal resources before next synthesis.
5. Reduce "Waiting for chunk" log spam to one log per distinct chunk index.
   verification: |

- Build succeeds (debug + release)
- Binary installed to ~/.local/bin/, service restarted
- Awaiting user verification with real back-to-back notifications
  files_changed:
- plugins/claude-tts-companion/Sources/claude-tts-companion/TelegramBot.swift
- plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitleSyncDriver.swift
- plugins/claude-tts-companion/Sources/claude-tts-companion/TTSEngine.swift
