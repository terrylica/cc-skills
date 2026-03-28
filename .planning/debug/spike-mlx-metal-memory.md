---
status: awaiting_human_verify
trigger: "Spike: Profile exact MLX Metal GPU memory behavior to answer critical questions about IOAccelerator leak"
created: 2026-03-27T17:00:00Z
updated: 2026-03-27T17:25:00Z
---

## Current Focus

hypothesis: CONFIRMED. IOAccelerator (graphics) grows ~1.5 GB per generateAudio() call (not per curl request -- each request produces 2 chunks = 2 generateAudio() calls). This is Metal driver-level allocation, not MLX buffer cache. Memory.clearCache() and cacheLimit=32MB are already in the kokoro-ios fork and working correctly, but they only manage MLX's internal buffer pool, not the IOAccelerator regions.
test: Measured fresh service baseline -> 3 TTS test calls -> final state
expecting: N/A -- confirmed with data
next_action: Present findings to user with exact numbers and mitigation options

## Symptoms

expected: Stable GPU memory across synthesis calls, or memory freed after each call
actual: IOAccelerator (graphics) grows unboundedly per generateAudio() call (~1.5 GB/call)
errors: After ~20 generateAudio() calls, service reaches 30+ GB physical footprint, CoreAudio reports "skipping cycle due to overload", service eventually restarts via launchd
reproduction: Any TTS synthesis call via HTTP API
started: Since kokoro-ios MLX migration

## Eliminated

- hypothesis: MLX buffer cache is the source of growth
  evidence: kokoro-ios fork already has Memory.clearCache() at end of generateAudio() and cacheLimit=32MB on init. vmmap still shows linear IOAccelerator growth. These are Metal driver-level allocations below MLX's buffer cache layer. <!-- SSoT-OK: version ref is debug context -->
  timestamp: 2026-03-27T17:15:00Z

- hypothesis: Service was freshly started with no prior calls at initial measurement
  evidence: PID 21263 showed 9676 IOAccelerator regions and 31.6G despite appearing to have only 2m18s uptime -- it was the OLD service from prior debug session with 752+ accumulated calls. Service restarted to PID 34028 for clean measurements.
  timestamp: 2026-03-27T17:05:00Z

## Evidence

- timestamp: 2026-03-27T17:00:00Z
  checked: Initial PID 21263 state
  found: 9676 IOAccelerator regions, 31.6G physical footprint (peak 31.8G), RSS 130MB. This is ACCUMULATED from prior debug session.
  implication: The prior session's 752+ calls accumulated ~31G of IOAccelerator

- timestamp: 2026-03-27T17:05:00Z
  checked: Fresh service PID 34028 baseline (uptime ~30s, no synthesis calls)
  found: 6 IOAccelerator regions, 18.1M physical footprint, RSS 46MB
  implication: Clean baseline confirmed

- timestamp: 2026-03-27T17:10:00Z
  checked: After TTS call 1 (73 chars, 2 chunks = 2 generateAudio() calls)
  found: 1645 IOAccelerator regions, 2.5G physical footprint (peak 2.6G), RSS 526MB
  implication: First synthesis adds ~2.5G (includes model load + 2 inference passes)

- timestamp: 2026-03-27T17:12:00Z
  checked: After TTS call 2 (71 chars, 2 chunks = 2 generateAudio() calls)
  found: 2784 IOAccelerator regions, 4.5G physical footprint (peak 4.6G), RSS 531MB
  implication: +2.0G from 2 more generateAudio() calls = ~1.0G per call after warmup

- timestamp: 2026-03-27T17:14:00Z
  checked: After TTS call 3 (71 chars, 2 chunks = 2 generateAudio() calls)
  found: 3644 IOAccelerator regions, 5.5G physical footprint (peak 5.6G), RSS 536MB
  implication: +1.0G from 2 more generateAudio() calls = ~0.5G per call (lower growth? may be measurement timing)

- timestamp: 2026-03-27T17:18:00Z
  checked: After Telegram bot triggered 14-chunk synthesis (14 generateAudio() calls)
  found: 12338 IOAccelerator regions, 30.9G physical footprint (peak 31.0G), RSS 121MB
  implication: 20 total generateAudio() calls -> 30.9G. Average ~1.5G per call.

- timestamp: 2026-03-27T17:20:00Z
  checked: IOAccelerator region type breakdown (after 20 calls)
  found: 3313 PURGE=N (non-purgeable), 250 PURGE=V (volatile), 79 SM=SHM. Large regions: 124x7392K, 120x4096K, 94x4384K, 98x2464K.
  implication: Majority are non-purgeable Metal GPU buffers that system CANNOT reclaim. These are compiled compute pipelines, command buffer residuals, and intermediate buffers.

- timestamp: 2026-03-27T17:22:00Z
  checked: CoreAudio logs during heavy memory pressure
  found: "HALC_ProxyIOContext::IOWorkLoop: skipping cycle due to overload" and "received an out of order message" errors in system log
  implication: Memory pressure from IOAccelerator growth directly causes audio playback issues

- timestamp: 2026-03-27T17:23:00Z
  checked: Known MLX issues on GitHub
  found: Multiple reports: ml-explore/mlx#755, #1271, #2254, ml-explore/mlx-examples#724, #1124, #1262. Also hexgrad/kokoro#152 (exact same symptom). MLX PR #390 added set_cache_enabled(False) / cacheLimit=0. Python mlx.core.metal docs say "To disable the cache, set the limit to 0."
  implication: This is a KNOWN MLX ecosystem issue. Python users also report it. The community workaround is set_cache_enabled(False) or periodic process restart.

- timestamp: 2026-03-27T17:24:00Z
  checked: mlx-swift Memory.swift API (in SPM cache)
  found: Line 237: "To disable the cache, set the limit to 0." Current fork uses cacheLimit=32MB. Setting to 0 would disable caching entirely.
  implication: cacheLimit=0 is worth testing as a mitigation -- but may not help if IOAccelerator growth is from compiled Metal pipelines, not cached buffers.

## Resolution

root_cause: MLX-Swift creates Metal driver-level IOAccelerator (graphics) allocations during each generateAudio() call that are never reclaimed. Average growth is ~1.5 GB per call. After 20 calls, service reaches 30+ GB physical footprint. These are non-purgeable (PURGE=N) Metal GPU buffers: compiled compute pipelines (7.4MB each, 124 instances), intermediate buffers (4MB each, 120 instances), and various smaller allocations. Memory.clearCache() only manages MLX's internal buffer reuse pool, not these driver-level allocations. This is a known issue across the MLX ecosystem (ml-explore/mlx#755, #1271, hexgrad/kokoro#152).

fix: Two mitigation paths to test:

1. **cacheLimit=0** -- mlx-swift docs say "To disable the cache, set the limit to 0." Test whether this prevents IOAccelerator growth or only MLX buffer growth.
2. **Periodic service restart** -- launchd KeepAlive already restarts the service. Add a scheduled restart (e.g., every 30 min or after N synthesis calls) to cap memory accumulation.
3. **Upstream fix** -- File issue on ml-explore/mlx-swift with vmmap data showing IOAccelerator growth pattern.

verification: Needs human verification on which mitigation to pursue.
files_changed: []
