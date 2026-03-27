---
status: resolved
trigger: "MLX Metal resource limit (499000) crash persists DESPITE P0 fix"
created: 2026-03-27T12:10:00-0700
updated: 2026-03-27T12:25:00-0700
resolved: 2026-03-27T12:35:00-0700---

## Current Focus

hypothesis: Calling Memory.cacheLimit/clearCache/Stream.gpu.synchronize from the main binary initializes a SEPARATE MLX Metal device singleton (C++ static local in the main binary), while KokoroSwift uses its OWN copy (in libKokoroSwift.dylib). Multiple Metal devices from duplicate C++ singletons collectively exhaust the 499000 Metal resource limit.
test: Remove all direct MLX calls from TTSEngine (Memory.cacheLimit, Memory.clearCache, Stream.gpu.synchronize) so only the dylib's copy is used
expecting: Synthesis succeeds without crashing (like the spike which never calls MLX from main binary)
next_action: Edit TTSEngine.swift to remove all direct MLX API calls, rebuild, test

## Symptoms

expected: TTS synthesis works without crashing
actual: Every TTS dispatch triggers "Fatal error: [metal::malloc] Resource limit (499000) exceeded" and crashes
errors: MLX/ErrorHandler.swift:343: Fatal error: [metal::malloc] Resource limit (499000) exceeded. at .build/checkouts/mlx-swift/Source/Cmlx/mlx-c/mlx/c/array.cpp:323
reproduction: Any TTS synthesis, even "Hello world" via POST /tts/test
started: Since kokoro-ios MLX migration. Crash happens on FIRST synthesis after fresh process start.

## Eliminated

- hypothesis: Metal resources accumulating across syntheses (need periodic clearCache)
  evidence: Crash occurs on the VERY FIRST synthesis after fresh process start -- no accumulation
  timestamp: 2026-03-27T12:12:00-0700

- hypothesis: Missing mlx.metallib causing JIT compilation resource explosion
  evidence: When running from build dir, got "Failed to load the default metallib" but when running from install dir (/Users/terryli/.local/bin/), metallib is found (no error) yet crash still occurs
  timestamp: 2026-03-27T12:18:00-0700

- hypothesis: Duplicate ObjC classes between dylibs causing corruption
  evidence: Spike has the EXACT SAME duplicate class warnings between libMisakiSwift.dylib and libKokoroSwift.dylib, yet works perfectly (RTF 0.07, multiple syntheses)
  timestamp: 2026-03-27T12:15:00-0700

- hypothesis: Metal resource limit is system-wide (stale from previous crash)
  evidence: Fresh service start after clean bootout still crashes on first synthesis
  timestamp: 2026-03-27T12:16:00-0700

## Evidence

- timestamp: 2026-03-27T12:12:00-0700
  checked: stderr.log crash pattern
  found: Pattern is always "model loaded in 0.1s" -> immediate "Fatal error: Resource limit (499000)" on first generateAudio call. No successful synthesis before crash.
  implication: Not a cumulative issue -- something about the process state at startup is already near the limit

- timestamp: 2026-03-27T12:14:00-0700
  checked: Spike binary at ~/tmp/kokoro-mlx-spike/
  found: Spike runs perfectly -- warmup synthesis + 2 full syntheses, RTF 0.077, peak RSS 529MB. Same duplicate class warnings between dylibs.
  implication: The spike's approach of ONLY calling MLX through KokoroSwift (never directly from main binary) works

- timestamp: 2026-03-27T12:17:00-0700
  checked: Build dir run vs install dir run
  found: Build dir shows "MLX error: Failed to load the default metallib" then crash. Install dir finds metallib but STILL crashes.
  implication: Metallib loading is not the root cause

- timestamp: 2026-03-27T12:20:00-0700
  checked: C++ Metal device singleton pattern in device.cpp:798-801
  found: `static Device metal_device;` -- each dylib + the main binary gets its OWN copy of this singleton. Device constructor creates Metal device + command queue + allocator.
  implication: Main binary's Memory.cacheLimit call triggers creation of a SEPARATE Metal device instance

- timestamp: 2026-03-27T12:22:00-0700
  checked: Spike main.swift vs production TTSEngine.swift
  found: Spike NEVER calls Memory.cacheLimit, Memory.clearCache(), or Stream.gpu.synchronize(). It only calls KokoroSwift API. Production calls all three.
  implication: The production code's "fix" (adding cache management) actually CAUSES the crash by initializing a duplicate MLX Metal device in the main binary

- timestamp: 2026-03-27T12:23:00-0700
  checked: ObjC duplicate class warnings
  found: Production shows duplicates between libMisakiSwift AND claude-tts-companion (main binary). Spike only shows duplicates between the two dylibs. This confirms the main binary's MLX is being activated in production but not in the spike.
  implication: The main binary's direct MLX calls trigger class resolution in the binary's copy, proving a separate instance is being created

## Resolution

root_cause: The TTSEngine calls MLX Swift APIs directly (Memory.cacheLimit, Memory.clearCache(), Stream.gpu.synchronize()). These calls initialize a SEPARATE C++ MLX Metal device singleton in the main binary (static Device at device.cpp:799). KokoroSwift.dylib has its OWN Metal device singleton. Each singleton creates its own Metal allocator with independent num_resources_counters but they share the same GPU's 499000 resource limit. The two (or three, with MisakiSwift) Metal devices collectively exhaust the limit before any synthesis can complete. The spike works because it NEVER calls MLX APIs directly -- it only calls KokoroSwift's generateAudio(), which uses a single Metal device instance inside the dylib.
fix: Removed all direct MLX runtime API calls from TTSEngine.swift (Memory.cacheLimit, Memory.clearCache(), Stream.gpu.synchronize()). Kept `import MLX` for MLXArray type only. The cache management code was the "P0 fix" that ironically CAUSED the crash.
verification: 3 consecutive syntheses via launchd service, all succeeded (RTF 1.19/0.12/0.16). Service uptime stable at 33s, RSS 188MB. No "Fatal error" or "Resource limit" crashes.
files_changed: [plugins/claude-tts-companion/Sources/claude-tts-companion/TTSEngine.swift]


## Resolution

**Resolved:** 2026-03-27 — Service confirmed stable after kokoro-ios MLX migration.

**Root cause:** The dual-Metal-device crash (fe49c3f6) was the primary blocker. Direct MLX API calls from the main binary initialized a second Metal device singleton, conflicting with KokoroSwift dynamic library singleton. Removing direct MLX calls resolved the crash and cascading audio/subtitle issues.

**Verification:** 3 consecutive TTS test dispatches confirmed stable. RTF 0.12-0.16 warm. No Metal resource crashes, no audio choppiness, no subtitle desync.
