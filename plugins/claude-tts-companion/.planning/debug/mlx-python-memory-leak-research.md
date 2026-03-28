# MLX Python Memory Leak Research: IOAccelerator / Metal GPU Memory

**Date**: 2026-03-27
**Context**: Python MLX (mlx-audio, Kokoro TTS) on macOS Apple Silicon — after many synthesis calls, IOAccelerator (Metal GPU) memory grows unbounded. Physical footprint reaches 25+ GB even though RSS stays at ~500MB. `mx.clear_cache()` does not prevent accumulation. The leak is in Metal driver-level IOAccelerator regions, not MLX's internal cache. Only process restart reclaims memory.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [MLX Core Issues](#mlx-core-issues)
3. [MLX-LM Server Issues](#mlx-lm-server-issues)
4. [Kokoro / mlx-audio Specific](#kokoro--mlx-audio-specific)
5. [Apple Developer Forums](#apple-developer-forums)
6. [MLX Memory Management API](#mlx-memory-management-api)
7. [Workarounds Analysis](#workarounds-analysis)
8. [Version History & Fixes](#version-history--fixes)
9. [Conclusions & Recommendations](#conclusions--recommendations)

---

## Executive Summary

**The problem is confirmed and well-documented across multiple MLX projects.** The root cause has two layers:

1. **MLX buffer cache** (controllable): MLX holds freed arrays in an internal buffer cache for reuse. This is tunable via `mx.set_cache_limit()` and `mx.clear_cache()`.

2. **Metal driver-level IOAccelerator memory** (NOT controllable): Metal allocates GPU heap blocks in large chunks (~1 GB). When buffers are released, memory becomes "unused" within the heap but **Metal does NOT release heap blocks back to macOS**, even when entirely unused. There is NO Metal API to force heap memory release. The only way to reclaim is to destroy the Metal device, which requires process exit.

**Bottom line**: `mx.clear_cache()` only addresses layer 1. Layer 2 (IOAccelerator/Metal driver memory) is an Apple framework limitation with no userspace workaround except process restart.

---

## MLX Core Issues

### Issue #755 — Memory leak in MLX / Metal / MPS

- **URL**: <https://github.com/ml-explore/mlx/issues/755>
- **Status**: Closed (consolidated under #742)
- **Finding**: Maintainer (awni) confirmed "This is not a leak, it's a combination of the MLX memory cache and the fact that we don't preallocate all used memory." Suggested `mx.disable_cache()` as workaround at the cost of generation speed.
- **Key quote**: David Koski recommended using the `footprint` CLI tool and filtering for `IOAccelerator` to see Metal driver allocations specifically — confirming these are separate from MLX's own tracking.

### Issue #742 — GPU Memory Management?

- **URL**: <https://github.com/ml-explore/mlx/issues/742>
- **Status**: Open (umbrella tracking issue)
- **Finding**: "MLX will not return 'freed' arrays to the system immediately. Rather they get held in the buffer cache and possibly reused." Unlike PyTorch's `torch.mps.empty_cache()`, MLX initially lacked a manual cache clear. Maintainer noted memory management was "starting to become a top priority."
- **Critical insight**: Benchmarking required **separate processes** to prevent memory bloat (25 GB observed vs 7 GB peak actual use). This confirms subprocess isolation is a known pattern.

### Issue #1086 — [Feature] Leak memory on exit

- **URL**: <https://github.com/ml-explore/mlx/issues/1086>
- **Status**: Closed/COMPLETED (PR #1142 merged)
- **Finding**: MLX's static `MetalAllocator` destructor took 30+ seconds to free GPU memory on exit. Fix: intentionally leak memory on exit (following Chromium's `base::NoDestructor` pattern). This is about exit speed, not runtime memory.

### Issue #1271 — Memory Leakage Issue in MLX 0.16

- **URL**: <https://github.com/ml-explore/mlx/issues/1271>
- **Status**: Fixed (PR #1274)
- **Finding**: Regression in MLX 0.16 (PR #1246) caused continuously growing memory during training. Fix: explicitly call `mx.eval(model, optimizer.state)` after each iteration. Version-specific bug, not the fundamental IOAccelerator issue.

### Issue #2668 — Memory seems to not get released

- **URL**: <https://github.com/ml-explore/mlx/issues/2668>
- **Status**: Closed
- **Finding**: 0.11 GiB input created 23.84 GiB usage. Maintainer confirmed this is the buffer cache and recommended:
  - `mx.clear_cache()` — empties entire cache
  - `mx.set_cache_limit(1024 * 1024 * 1024)` — restrict cache to 1 GB
- **Limitation**: These only affect MLX's internal cache, not Metal driver allocations.

### Issue #1481 — Memory release action in stream

- **URL**: <https://github.com/ml-explore/mlx/issues/1481>
- **Status**: Closed
- **Finding**: User requested explicit memory release during inference. Maintainer declined: "We don't plan to expose a way to explicitly interact the memory allocations behind arrays." Suggested `mx.metal.set_cache_limit()` to "effectively unload weights as soon as you are done with them."

### Issue #2254 — MLX using DOUBLE the memory required

- **URL**: <https://github.com/ml-explore/mlx/issues/2254>
- **Finding**: Reports of MLX consuming 2x expected memory for tensors.

### PR #390 — Disable Metal buffer cache

- **URL**: <https://github.com/ml-explore/mlx/pull/390>
- **Status**: Merged (January 2024)
- **Finding**: Added `mlx.core.metal.set_cache_enabled(False)` / `get_cache_enabled()`. Disabling cache reduced memory growth to "tens of MB" during 1000-token generation, with ~3-5% throughput decrease. Maintainer noted API may be deprecated once allocation strategies improve.

### Discussion #912 — Memory reuse / GC during eval

- **URL**: <https://github.com/ml-explore/mlx/discussions/912>
- **Status**: Informational
- **Finding**: Intermediate array memory is freed through reference counting + `arr.detach()`. Demonstrated that 10-layer network only held ~3.8 activation buffers simultaneously. However, this only governs MLX-level memory, not Metal driver heaps.

---

## MLX-LM Server Issues

### Issue #883 — Kernel panic (IOGPUMemory crash) from unbounded growth

- **URL**: <https://github.com/ml-explore/mlx-lm/issues/883>
- **Status**: Open
- **Finding**: Running mlx_lm.server with Qwen3-Coder-30B on 96GB system. KV cache grew unboundedly during agentic session (~58k+ tokens). `mx.set_wired_limit()` locked ~72GB as wired memory, bypassing macOS memory pressure monitoring. GPU driver hit "completeMemory() prepare count underflow" at IOGPUMemory.cpp:550, causing **kernel panic** (not just OOM).
- **Proposed fixes**: `--max-kv-size`, configurable `--memory-limit`, reduce default wired percentage to 50-60%, graceful 503 responses.

### LM Studio mlx-engine Issue #63 — Memory leak with MLX models

- **URL**: <https://github.com/lmstudio-ai/mlx-engine/issues/63>
- **Status**: Completed
- **Finding**: Each inference consumed ~10GB additional memory (roughly KV cache size). Memory balloon to 200+ GB on 192GB system. Fixed by "more aggressive Metal buffer cache clearing." Model reload reset memory to baseline, confirming the leak was in cached Metal buffers.

---

## Kokoro / mlx-audio Specific

### hexgrad/kokoro Issue #152 — Memory leak

- **URL**: <https://github.com/hexgrad/kokoro/issues/152>
- **Status**: Open
- **Finding**: PyTorch-based Kokoro memory leak during synthesis. Memory grows steadily, generation speed degrades. Affects CPU, MPS, and ROCm backends. On Mac Mini M4 with MPS: "memory usage goes up steadily, the generation speed goes down steadily" during 1h9m audio generation.
- **Workarounds**:
  - `UVICORN_LIMIT_MAX_REQUESTS=200` — graceful worker restart after N requests, bounds peak to ~2.8 GB
  - Switch to Kokoros (Rust re-implementation) to avoid PyTorch leak entirely
  - launchd `KeepAlive` / systemd `Restart=on-failure` for process recycling

### Blaizzy/mlx-audio — No specific memory leak issues filed

- **URL**: <https://github.com/Blaizzy/mlx-audio/issues>
- **Finding**: No open issues specifically about memory leaks with repeated synthesis calls. The mlx-audio port from PyTorch to MLX may mitigate some PyTorch-specific leaks but inherits the fundamental MLX/Metal memory behavior described above.

---

## Apple Developer Forums

### Thread 664763 — How to release memory leaked by CoreML

- **URL**: <https://developer.apple.com/forums/thread/664763>
- **Finding**: MLModel objects leak `MTLIOAccelResource` objects on initialization. Count increases even when parent object is released. Resources held by `AGXA10FamilyHeap`, `AGXA10FamilyBuffer`, `MTLIOMemoryInfo`, `MTLIOAccelPooledResource`.

### Thread 812368 — [CRITICAL] Metal RHI Memory Leak

- **URL**: <https://developer.apple.com/forums/thread/812368>
- **Finding**: Metal allocates GPU heap blocks in **large chunks (~1 GB)**. When buffers are released, memory becomes "unused" within the heap but **Metal does NOT release heap blocks back to macOS**, even when entirely unused. No Metal API to force release. Destroying Metal device = restarting the process.
- **Failed mitigations**:
  - Forcing individual buffer allocations (Metal still manages underlying allocations)
  - Minimizing buffer pool sizes (slightly slows leak rate, doesn't stop it)

### Thread 120931 — Memory leak in MTLCommandBuffer

- **URL**: <https://developer.apple.com/forums/thread/120931>

### Thread 662721 — Memory leak on releasing MTLCommandQueue

- **URL**: <https://developer.apple.com/forums/thread/662721>

### Thread 707477 — Bound Buffer Memory Leak

- **URL**: <https://developer.apple.com/forums/thread/707477>

### Thread 667545 — IOGPUCommandQueue memory leak

- **URL**: <https://developer.apple.com/forums/thread/667545>

**Pattern across all Apple forums threads**: Metal driver-level memory management is opaque, heap-based, and does not expose APIs for forced deallocation. Apple engineers have not provided workarounds beyond "file a Feedback Assistant report."

---

## MLX Memory Management API

### Complete API Reference (MLX 0.31.1)

Source: <https://ml-explore.github.io/mlx/build/html/python/metal.html>

```python
# Metal device info
mx.metal.is_available()       # Check Metal backend availability
mx.metal.device_info()        # Dict with max_buffer_size, max_recommended_working_set_size, memory_size, resource_limit

# Memory introspection
mx.get_active_memory()        # Currently allocated memory (bytes)
mx.get_peak_memory()          # Maximum memory used since last reset (bytes)
mx.reset_peak_memory()        # Clear peak memory tracking
mx.get_cache_memory()         # Cached (freed but held) memory (bytes)

# Memory control
mx.set_memory_limit(limit)    # Set max memory in bytes. Default: 1.5x max_recommended_working_set_size.
                               # Exceeding limit when no RAM available → exception.
                               # Returns previous limit.
mx.set_cache_limit(limit)     # Set free cache limit in bytes. Default: same as memory limit.
                               # Exceeding → free memory reclaimed from cache on next allocation.
                               # Set to 0 to disable caching entirely.
                               # Returns previous limit.
mx.set_wired_limit(limit)     # Lock memory as wired (non-swappable). macOS 15+ only.
                               # Speeds up large model inference by preventing paging.
mx.clear_cache()              # Empty the buffer cache. get_cache_memory() → 0 after call.

# Metal buffer cache control (from PR #390)
mx.metal.set_cache_enabled(False)  # Disable buffer cache entirely (~3-5% throughput cost)
mx.metal.get_cache_enabled()       # Check if cache is enabled

# Performance capture
mx.metal.start_capture(path)  # Start Metal GPU trace
mx.metal.stop_capture()       # Stop capture
```

### What These APIs Do NOT Control

- **IOAccelerator heap memory**: Metal's internal heap allocator operates below MLX's buffer cache. `clear_cache()` releases buffers back to Metal, but Metal does not release heaps back to the OS.
- **Metal driver memory pools**: The ~1 GB heap chunks allocated by the Metal driver for `MTLIOAccelResource`, `MTLIOAccelPooledResource` etc.
- **GPU command buffer memory**: Memory held by in-flight or completed command buffers until the Metal driver decides to reclaim them.

### Environment Variables

- **`MLX_METAL_MEMORY_BUDGET`**: NOT a real environment variable. Does not exist in MLX.
- **`MLX_BUILD_CPU`**, **`MLX_BUILD_CUDA`**: Build-time flags only.
- **System-level**: `sudo sysctl -w iogpu.wired_limit_mb=<value>` can adjust macOS GPU wired memory limits (use with caution).

---

## Workarounds Analysis

### 1. `mx.clear_cache()` after each synthesis

- **Effectiveness**: Partial. Releases MLX's internal buffer cache but NOT Metal driver heaps.
- **Result**: Slows the growth rate but does not prevent it. IOAccelerator regions still accumulate.

### 2. `mx.set_cache_limit(0)` — Disable caching

- **Effectiveness**: Better than clear_cache. Forces MLX to release buffers immediately rather than caching.
- **Cost**: ~3-5% throughput decrease.
- **Result**: Reduces MLX-level accumulation but Metal driver still retains heap memory.

### 3. `mx.metal.set_cache_enabled(False)`

- **Effectiveness**: Similar to set_cache_limit(0). Disables the entire buffer cache mechanism.
- **Cost**: Same throughput penalty.
- **Result**: Same limitation — Metal driver heaps persist.

### 4. `gc.collect()` after `mx.clear_cache()`

- **Effectiveness**: Minimal additional benefit. Python GC handles Python objects; MLX arrays are already ref-counted at the C++ level.
- **Result**: May help if Python-side references are keeping MLX arrays alive, but does not address Metal driver memory.

### 5. `del model; gc.collect(); mx.clear_cache()` then reload

- **Effectiveness**: Better than just clear_cache. Destroying the model releases all its array references, allowing MLX to free those buffers.
- **Result**: MLX cache memory drops to 0, but Metal driver heaps remain allocated. The heaps MAY be partially reused when the model is reloaded, but total IOAccelerator footprint does not decrease.

### 6. `mx.set_memory_limit()` — Hard cap

- **Effectiveness**: Prevents MLX from allocating beyond a limit. Throws exception if exceeded.
- **Result**: Prevents runaway growth at the MLX level. Does NOT prevent Metal driver heap growth since that operates at a lower level.

### 7. `multiprocessing.Process` per synthesis call (RECOMMENDED)

- **Effectiveness**: **HIGH**. Each subprocess gets its own Metal device. On process exit, the OS reclaims ALL memory including Metal driver heaps and IOAccelerator regions.
- **Cost**: Process startup + model load time per call (or per batch of N calls).
- **Pattern**:

  ```python
  import multiprocessing as mp

  def synthesize_in_subprocess(text, output_path):
      """Run synthesis in isolated subprocess to guarantee memory cleanup."""
      p = mp.Process(target=_do_synthesis, args=(text, output_path))
      p.start()
      p.join()
      # All Metal memory freed when subprocess exits

  def _do_synthesis(text, output_path):
      import mlx_audio  # Import inside subprocess
      # ... load model, synthesize, write WAV
  ```

- **Result**: Complete memory isolation. IOAccelerator memory never accumulates across calls.
- **Confirmed by**: mlx#742 discussion (benchmarking in separate processes to prevent bloat), kokoro#152 (UVICORN_LIMIT_MAX_REQUESTS for worker restart).

### 8. Periodic process restart (launchd/systemd)

- **Effectiveness**: **HIGH**. Same principle as subprocess isolation but at the service level.
- **Pattern**: Run N synthesis calls, then exit. launchd `KeepAlive` restarts automatically.
- **Confirmed by**: kokoro#152 (UVICORN_LIMIT_MAX_REQUESTS=200 bounds peak to ~2.8 GB).

### 9. Use `spawn` not `fork` for multiprocessing

- **Effectiveness**: Required for correctness on macOS with Metal/GPU libraries.
- **Reason**: `fork()` copies the parent's Metal state, which can cause deadlocks or corruption. `spawn` starts a fresh Python interpreter.
- **Pattern**: `mp.set_start_method('spawn')` or use `mp.get_context('spawn')`.

---

## Version History & Fixes

| MLX Version | Date       | Memory-Related Changes                                                                         |
| ----------- | ---------- | ---------------------------------------------------------------------------------------------- |
| 0.11.x      | Early 2024 | Memory release issues first widely reported                                                    |
| 0.15.x      | Mid 2024   | Stable memory during training                                                                  |
| 0.16        | Late 2024  | **Regression**: Memory leak in training (PR #1246). Fixed in PR #1274                          |
| 0.22.1      | ~Nov 2024  | Active memory still rising during training                                                     |
| 0.30.0      | Nov 2024   | "Reduce use of managed memory", "Fix memory count bug"                                         |
| 0.30.1      | Dec 2024   | "Make allocator::malloc throw on allocation failure", **"Detect cache thrashing in LRUCache"** |
| 0.30.4      | Jan 2025   | "Fallback to pinned host memory when managed memory not supported"                             |
| 0.31.0      | Feb 2025   | No memory-specific changes noted                                                               |
| 0.31.1      | Mar 2025   | Current latest. No IOAccelerator fix.                                                          |

**No MLX version (through 0.31.1) fixes the fundamental IOAccelerator/Metal driver memory issue.** This is an Apple framework limitation, not an MLX bug.

---

## Conclusions & Recommendations

### The Fundamental Problem

Metal's GPU memory allocator (IOAccelerator) uses a heap-based pool that **never returns memory to the OS** during the lifetime of a process. This is by design in Apple's Metal framework. MLX's `clear_cache()` and `set_cache_limit()` only control MLX's own buffer reuse layer on top of Metal. They cannot force Metal to release its underlying heaps.

### For claude-tts-companion (Kokoro TTS via mlx-audio)

**Recommended approach: Subprocess-based synthesis with periodic restart.**

1. **Short term**: Track synthesis count. After every N calls (e.g., 50-100), gracefully restart the TTS process. Use launchd `KeepAlive` for automatic restart.

2. **Optimal pattern**: Run synthesis in a subprocess pool:
   - Parent process: Telegram bot + HTTP API (lightweight, no MLX)
   - Child process: MLX/Kokoro model loaded, handles synthesis requests
   - After N syntheses (or when `mx.get_active_memory()` exceeds threshold), kill and respawn child

3. **Defensive MLX settings** (reduce accumulation rate within each process lifecycle):

   ```python
   import mlx.core as mx

   mx.set_cache_limit(0)              # Disable buffer caching
   # OR
   mx.metal.set_cache_enabled(False)  # Disable Metal buffer cache entirely

   # After each synthesis:
   mx.clear_cache()                   # Return buffers to Metal (won't help IOAccelerator but limits MLX layer)
   ```

4. **Monitor with `footprint`**:

   ```bash
   footprint -p <pid> --filter IOAccelerator
   ```

### What Will NOT Work

- `mx.clear_cache()` alone — only clears MLX layer, not Metal heaps
- `gc.collect()` — Python GC irrelevant to Metal driver memory
- `del model` + reload — Metal heaps persist across model lifecycle
- `mx.set_memory_limit()` — limits MLX allocations, not Metal driver pools
- `mx.reset_peak_memory()` — only resets a counter, doesn't free anything
- Any `MLX_METAL_MEMORY_BUDGET` env var — does not exist
- Waiting for an MLX fix — this is Apple's Metal framework behavior, not an MLX bug

### What WILL Work

- **Process restart** (the only guaranteed solution)
- **Subprocess isolation** via `multiprocessing.Process(start_method='spawn')`
- **Worker restart pattern** (UVICORN_LIMIT_MAX_REQUESTS or equivalent)
- **launchd KeepAlive + synthesis counter** (already planned in Phase 20.1)

---

## Sources

### MLX Core Repository

- [#755 — Memory leak in MLX / Metal / MPS](https://github.com/ml-explore/mlx/issues/755)
- [#742 — GPU Memory Management?](https://github.com/ml-explore/mlx/issues/742)
- [#1086 — Leak memory on exit](https://github.com/ml-explore/mlx/issues/1086)
- [#1271 — Memory Leakage Issue in MLX 0.16](https://github.com/ml-explore/mlx/issues/1271)
- [#2668 — Memory seems to not get released](https://github.com/ml-explore/mlx/issues/2668)
- [#1481 — Memory release action in stream](https://github.com/ml-explore/mlx/issues/1481)
- [#2254 — MLX using DOUBLE the memory required](https://github.com/ml-explore/mlx/issues/2254)
- [PR #390 — Disable Metal buffer cache](https://github.com/ml-explore/mlx/pull/390)
- [Discussion #912 — Memory reuse / GC during eval](https://github.com/ml-explore/mlx/discussions/912)
- [Releases page](https://github.com/ml-explore/mlx/releases)

### MLX-LM Repository

- [#883 — Kernel panic from unbounded memory growth](https://github.com/ml-explore/mlx-lm/issues/883)

### MLX-Swift Repository

- [mlx-swift-examples #66 — GPU Memory/Cache Limit](https://github.com/ml-explore/mlx-swift-examples/issues/66)
- [mlx-swift Memory.swift](https://github.com/ml-explore/mlx-swift/blob/main/Source/MLX/Memory.swift)

### Kokoro / mlx-audio

- [hexgrad/kokoro #152 — Memory leak](https://github.com/hexgrad/kokoro/issues/152)
- [Blaizzy/mlx-audio issues](https://github.com/Blaizzy/mlx-audio/issues)

### LM Studio

- [mlx-engine #63 — Memory leak with MLX models](https://github.com/lmstudio-ai/mlx-engine/issues/63)
- [mlx-engine #40 — Set wired limit before generation](https://github.com/lmstudio-ai/mlx-engine/issues/40)

### Apple Developer Forums

- [Thread 664763 — Release memory leaked by CoreML](https://developer.apple.com/forums/thread/664763)
- [Thread 812368 — CRITICAL Metal RHI Memory Leak](https://developer.apple.com/forums/thread/812368)
- [Thread 120931 — Memory leak in MTLCommandBuffer](https://developer.apple.com/forums/thread/120931)
- [Thread 662721 — Memory leak on releasing MTLCommandQueue](https://developer.apple.com/forums/thread/662721)
- [Thread 707477 — Bound Buffer Memory Leak](https://developer.apple.com/forums/thread/707477)
- [Thread 667545 — IOGPUCommandQueue memory leak](https://developer.apple.com/forums/thread/667545)

### MLX Documentation

- [Metal Python API](https://ml-explore.github.io/mlx/build/html/python/metal.html)
- [Unified Memory](https://ml-explore.github.io/mlx/build/html/usage/unified_memory.html)
- [set_memory_limit](https://ml-explore.github.io/mlx/build/html/python/_autosummary/mlx.core.set_memory_limit.html)
- [set_cache_limit](https://ml-explore.github.io/mlx/build/html/python/_autosummary/mlx.core.set_cache_limit.html)
- [clear_cache](https://ml-explore.github.io/mlx/build/html/python/_autosummary/mlx.core.clear_cache.html)

### Other

- [Awni's memory reduction gist](https://gist.github.com/awni/f9d14ed391853e8ab7c7ed1a14ed90a2)
- [sysctl GPU memory limits gist](https://gist.github.com/ivanfioravanti/44b4284be930b3c340cc1696d60c6143)
- [WWDC25 — Get started with MLX for Apple silicon](https://developer.apple.com/videos/play/wwdc2025/315/)
