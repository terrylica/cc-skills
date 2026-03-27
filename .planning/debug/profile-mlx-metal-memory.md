---
status: awaiting_human_verify
trigger: "Profile MLX Metal GPU memory usage during sequential TTS synthesis to understand why chunk 5 stutters"
created: 2026-03-27T16:00:00Z
updated: 2026-03-27T16:45:00Z
---

<!-- SSoT-OK: kokoro-ios versions referenced as historical debug context, not dependency pins -->

## Current Focus

hypothesis: CONFIRMED. MLX synthesis creates ~1.7 GB of IOAccelerator (graphics) per call that is NEVER reclaimed. This is NOT from MLX's buffer cache (clearCache has no effect) but from Metal driver-level allocations (command buffers, pipeline states, compute pipeline objects). Setting Memory.cacheLimit to 32 MB and calling Memory.clearCache() inside the dylib both work correctly (verified via logs) but do NOT reduce IOAccelerator (graphics) regions. The 31 GB growth after 752 calls is from Metal resource objects that only the Metal runtime or process termination can reclaim.
test: Verified cache management works (32 MB limit set, clearCache returns success) but IOAccelerator (graphics) still grows linearly
expecting: N/A -- this is an MLX-Swift framework limitation on Apple Silicon
next_action: Present findings to user. The stutter is confirmed as memory pressure from IOAccelerator growth. Mitigation options: (1) periodic service restart, (2) upstream MLX-Swift fix for Metal resource cleanup, (3) accept ~600MB per synthesis session and size the service accordingly.

## Symptoms

expected: Smooth audio across all streaming TTS chunks, stable GPU memory
actual: IOAccelerator (graphics) grows ~1.7 GB per synthesis call, never released. 31 GB after 752 calls. RTF degrades 3x within a single streaming session.
errors: No crash from memory growth alone. But direct MLX API calls from main binary crash with "Resource limit (499000) exceeded"
reproduction: Every synthesis call accumulates IOAccelerator (graphics) memory permanently
started: Since kokoro-ios MLX migration

## Eliminated

- hypothesis: autoreleasepool drains Metal objects between chunks
  evidence: Fresh service: 16 KB IOAccelerator (graphics). After 1 synthesis: 1713 MB. After 2: 3337 MB. After 3: 6051 MB. Linear growth with autoreleasepool wrapping.
  timestamp: 2026-03-27T16:20:00Z

- hypothesis: MLX buffer cache is the source of IOAccelerator growth
  evidence: Forked kokoro-ios to add Memory.clearCache() and Memory.cacheLimit=32MB inside the dylib. Logs confirm cache is set ("32 MB was 35020 MB") and clearCache returns success. But IOAccelerator (graphics) still grows: 1675 MB -> 3193 MB -> 5022 MB after 3 calls. The cache is about MLX's INTERNAL buffer pool reuse, not Metal driver-level IOAccelerator allocations.
  timestamp: 2026-03-27T16:40:00Z

- hypothesis: dlsym can call clearCache through the dylib's Metal device singleton
  evidence: dlsym resolves mlx_clear_cache from libKokoroSwift.dylib handle, but diagnostic shows "0 MB -> 0 MB" cache -- it's actually clearing the main binary's empty cache, not the dylib's. Two-level namespace doesn't help with C function resolution.
  timestamp: 2026-03-27T16:30:00Z

- hypothesis: Calling KokoroTTS.setCacheLimit() from main binary is safe
  evidence: CRASHED with "Resource limit (499000) exceeded". Calling KokoroTTS methods that internally touch Memory.cacheLimit triggers the main binary's Metal device singleton initialization through Swift class dispatch.
  timestamp: 2026-03-27T16:35:00Z

- hypothesis: CPU contention or AVAudioEngine scheduling causes stutter
  evidence: RTF degrades within a single streaming session (0.211 -> 0.674 for 14-chunk session), directly correlating with IOAccelerator growth. Synthesis itself slows down.
  timestamp: 2026-03-27T16:25:00Z

## Evidence

- timestamp: 2026-03-27T16:05:00Z
  checked: Idle-state footprint after 752 synthesis calls
  found: 31 GB IOAccelerator (graphics) in 10,001 regions. phys_footprint: 31 GB. RSS: 110 MB.
  implication: Massive Metal resource leak

- timestamp: 2026-03-27T16:10:00Z
  checked: Fresh service baseline
  found: 16 KB IOAccelerator (graphics) in 2 regions, 17 MB total
  implication: All growth is from synthesis calls

- timestamp: 2026-03-27T16:15:00Z
  checked: Per-synthesis memory growth (fresh service, no fix)
  found: 0=16KB, 1=1713MB, 2=3337MB, 3=6051MB. ~1.7 GB per call.
  implication: Linear unbounded growth per generateAudio() call

- timestamp: 2026-03-27T16:18:00Z
  checked: RTF degradation pattern
  found: 14-chunk session: RTF 0.211 -> 0.336 -> 0.674. 3x slower by chunk 9.
  implication: Memory pressure directly degrades synthesis speed

- timestamp: 2026-03-27T16:30:00Z
  checked: dlsym approach to clear dylib cache
  found: dlsym resolves symbols from dylib handle but they execute with main binary's static Device singleton. Diagnostic shows "0 MB -> 0 MB" cache.
  implication: Cannot reach dylib's Metal device singleton from main binary via any mechanism

- timestamp: 2026-03-27T16:35:00Z
  checked: KokoroTTS.setCacheLimit() called from main binary
  found: CRASHES with "Resource limit (499000) exceeded". Even method calls on KokoroTTS that internally touch MLX APIs trigger the main binary's Metal device.
  implication: Swift class dispatch does not guarantee method body runs in dylib context for MLX C++ singletons

- timestamp: 2026-03-27T16:40:00Z
  checked: Memory.clearCache() + cacheLimit=32MB inside generateAudio() in forked kokoro-ios
  found: Logs confirm cache limit set and clearCache called successfully. But IOAccelerator (graphics) still grows: 1675 -> 3193 -> 5022 MB after 3 calls.
  implication: IOAccelerator (graphics) regions are Metal driver-level allocations (command buffers, pipeline states, compute pipelines), NOT MLX's buffer cache. MLX's cache management operates at a higher level and cannot reclaim these.

## Resolution

root_cause: MLX-Swift on Apple Silicon creates Metal driver-level IOAccelerator (graphics) allocations during model inference (~1.7 GB per generateAudio() call) that are never reclaimed. These are Metal command buffers, compiled pipeline states, and compute pipeline objects at the IOKit/IOAccelerator layer -- below MLX's buffer cache management. Memory.clearCache() only manages MLX's internal buffer reuse pool. autoreleasepool only drains ObjC objects. Neither can reclaim IOAccelerator resources.

Additionally, the dual Metal device singleton architecture (main binary vs dylib) makes it impossible to manage MLX's internal cache from the main binary. Calling any MLX API from the main binary initializes a separate C++ Metal device that competes for the GPU's 499000 resource limit.

The practical impact: after ~10 streaming sessions (50+ synthesis calls), IOAccelerator growth saturates physical RAM and forces swap, degrading synthesis RTF by 3x and causing audible audio stutter.

fix: Forked kokoro-ios (terrylica/kokoro-ios) to add Memory.clearCache() inside generateAudio() and set Memory.cacheLimit=32MB on init. This helps with MLX's internal buffer reuse but does NOT address the IOAccelerator driver-level leak. The only effective mitigation is periodic service restart (e.g., via launchd KeepAlive + scheduled restart every N hours) or upstream MLX-Swift fix for Metal resource lifecycle.
verification: Service runs, synthesis works, cache management logs confirm operation. But IOAccelerator still grows ~1.7 GB/call. Needs human verification on practical stutter improvement and discussion on restart strategy.
files_changed: [Package.swift, TTSEngine.swift, (fork) kokoro-ios KokoroTTS.swift]
