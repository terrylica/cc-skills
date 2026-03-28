---
status: awaiting_human_verify
trigger: "TTS audio playback has periodic stutters - choppy at beginning, middle after 2-3 sentences, sometimes loses end chunk"
created: 2026-03-27T00:00:00Z
updated: 2026-03-27T02:00:00Z
---

## Current Focus

hypothesis: Play-end gating fixed chunks 1-4. Last chunk stutters because CoreAudio hardware goes cold during synthesis gap. When chunk 4 ends, gate signals, synthesis starts (~1-2s), then playback begins on cold hardware. The warmUpAudioHardware() 30s threshold doesn't catch this 1-2s gap. Fix: play a looping silent buffer between chunks to keep CoreAudio warm.
test: Add a keepAlive silent player that loops during inter-chunk synthesis gaps
expecting: All 5 chunks play cleanly including the last one
next_action: Implement silent keepAlive player in TTSEngine + wire it into SubtitleSyncDriver chunk transitions

## Symptoms

expected: Smooth continuous TTS audio playback without interruptions
actual: Periodic stutters - first 3 sentences clean, stutter starts at sentence 4 (2nd page). Back-pressure partially works.
errors: No crash, no error logs - just audible stuttering/choppiness
reproduction: Trigger TTS with multi-sentence text (5+ sentences), observe playback
started: Ongoing pattern

## Eliminated

- hypothesis: SubtitlePanel main-thread highlightWord work causing audio stutters
  evidence: Applied lightweight highlightWord fix, rebuilt release, deployed, restarted launchd - stutters persist unchanged
  timestamp: 2026-03-27

- hypothesis: MLX Metal GPU synthesis saturating memory bus (simple back-pressure / DispatchSemaphore with signal-on-start)
  evidence: Added DispatchSemaphore back-pressure so synthesis pauses after each chunk until previous chunk starts playing. PARTIALLY helped - first 3 clean, stutter at sentence 4+. Analysis shows signal-on-start still allows concurrent synthesis+playback.
  timestamp: 2026-03-27

## Evidence

- timestamp: 2026-03-27
  checked: SubtitlePanel highlightWord optimization
  found: Fix applied but stutters persist - same pattern (beginning, middle, end)
  implication: Root cause is NOT (solely) SubtitlePanel main-thread work.

- timestamp: 2026-03-27
  checked: Full streaming pipeline architecture (TTSEngine.swift, SubtitleSyncDriver.swift, TelegramBot.swift)
  found: MLX Metal GPU synthesis runs concurrently with AVAudioPlayer playback via shared Apple Silicon unified memory.
  implication: GPU contention hypothesis confirmed as direction, but signal-on-start back-pressure insufficient.

- timestamp: 2026-03-27
  checked: User testing with back-pressure (DispatchSemaphore, signal-on-play-start)
  found: |
  PARTIALLY FIXED. Short 3-sentence test: NO STUTTER. Longer 5-sentence test: sentences 1-3 clean,
  stutter starts at sentence 4. This correlates perfectly with the back-pressure gate timing:
  - Gate initial value = 1, so chunks 0 and 1 synthesize without blocking (before any playback starts)
  - Chunk 2 blocks, then synthesizes while chunk 0 finishes (minimal overlap)
  - Chunk 3+ synthesize while previous chunk plays (FULL overlap = GPU contention = stutter)
    implication: Root cause confirmed as concurrent MLX synthesis + Core Audio playback on shared GPU.

- timestamp: 2026-03-27
  checked: Back-pressure gate signal timing analysis (code trace)
  found: |
  synthesisGate.signal() is called in playStreamChunk() and advanceToPrebuilt() when a chunk
  STARTS playing. This immediately unblocks the TTS queue to synthesize the next chunk.
  Result: synthesis and playback always run concurrently (for chunks 3+).

  Fix: Move signal to when chunk FINISHES playing (in tickStreaming's !isPlaying detection).
  This ensures synthesis only runs when GPU is free from audio playback.

  Tradeoff: small inter-chunk gap (~1-2s synthesis time) vs zero stutter.
  Mitigation: pre-synthesis doesn't help if it causes stutter, so clean gaps are better.
  implication: Signal timing is the root cause. Fix by signaling on playback END, not START.

- timestamp: 2026-03-27
  checked: User testing with play-end gating (5-sentence text)
  found: |
  Chunks 1-4 play cleanly (play-end gating works). Chunk 5 (last) stutters at "Fifth and final"
  (first words). Root cause: when chunk 4 ends, gate signals, synthesis of chunk 5 starts (~1-2s),
  then playback begins. During that 1-2s synthesis gap, no audio is playing and CoreAudio hardware
  goes cold. When chunk 5's player starts, hardware re-init causes stutter.

  Code path analysis:
  1. tickStreaming() detects !isPlaying -> signals gate -> tries advance to chunk 5
  2. Chunk 5 not synthesized yet -> waitingForNextChunk = true
  3. Gate signal unblocks TTS queue -> synthesizes chunk 5 (~1-2s)
  4. addChunk() delivers chunk 5 -> sees waitingForNextChunk -> calls playStreamChunk()
  5. playStreamChunk() -> engine.play() -> creates NEW AVAudioPlayer on cold hardware -> stutter

  warmUpAudioHardware() in play() only triggers after 30s idle, missing this 1-2s gap.
  implication: Need to keep CoreAudio hardware warm between chunks during synthesis gaps.

## Resolution

root_cause: Two-part stutter mechanism on Apple Silicon unified memory:

1. (Fixed) GPU bus contention: MLX synthesis concurrent with audio playback causes stutters on chunks 3+.
2. (Remaining) CoreAudio cold-start: Play-end gating creates a 1-2s synthesis gap between chunks where no audio plays. CoreAudio hardware goes idle during this gap. When the next chunk starts playing, hardware re-init causes stutter at the first words. Only affects the last chunk because pre-buffered chunks for earlier transitions mask the issue.

fix: |
Two-part fix:

1. (Already applied) Signal gate on play-END not play-START to prevent GPU contention.
2. (Applying now) Add a looping silent keepAlive player in TTSEngine that runs during inter-chunk
   gaps, keeping CoreAudio hardware warm. Start it when a chunk finishes, stop it when the next
   chunk starts playing. This prevents hardware cold-start for ALL chunk transitions, not just the last.

verification: Build succeeded. Binary deployed to /usr/local/bin/. Service restarted (state=running). Awaiting user test with 5+ sentence text to confirm last-chunk stutter is resolved.

files_changed:

- Sources/claude-tts-companion/TTSEngine.swift
- Sources/claude-tts-companion/SubtitleSyncDriver.swift
