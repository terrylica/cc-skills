# TTS Runtime Alternatives Research

**Date:** 2026-03-27
**Goal:** Find a TTS inference runtime for Kokoro-82M on Apple Silicon with stable memory (no IOAccelerator leak)
**Context:** Current mlx-swift + kokoro-ios leaks ~1.5 GB per `generateAudio()` call via IOAccelerator (Metal driver-level). See `spike-mlx-metal-memory.md` for profiling data.

---

## Option A: Rust + Candle or Burn Frameworks

### Candle (huggingface/candle)

**Feasibility: LOW for Kokoro specifically**

Candle has a Metal backend (`metal-candle` crate) that works on Apple Silicon. It supports audio models (Whisper, Parler-TTS, MetaVoice) but there is **no existing Kokoro model implementation** in Candle. You would need to port the entire Kokoro architecture (ISTFT decoder, duration model, transformer backbone) to Candle ops manually.

- **Metal support:** Yes, via `candle-metal` backend. Claims 25.9x faster than MLX for embeddings.
- **Memory management:** Candle uses Rust's ownership model for tensor lifecycle. Metal buffers are tied to Rust `Drop` semantics, so they should be freed deterministically. However, no one has tested whether the Metal backend exhibits the same IOAccelerator accumulation pattern as MLX.
- **Kokoro support:** None. Would require full model reimplementation (~2000+ lines).
- **Safetensors loading:** Yes, native support.
- **C FFI from Swift:** Possible via `cbindgen` or manual `extern "C"` wrappers, but adds significant build complexity (Cargo + SwiftPM cross-linking).

**Crane** (lucasjinreal/Crane) is a Candle-based inference engine that lists Spark-TTS but not Kokoro.

### Burn (tracel-ai/burn)

**Feasibility: LOW**

Burn has a `burn-mlx` backend that uses Apple MLX underneath -- so it would have the **same IOAccelerator leak**. The `burn-candle` backend delegates to Candle's Metal. No Kokoro model implementation exists for Burn either.

- **Metal support:** Via burn-mlx (MLX underneath) or burn-candle.
- **Memory:** burn-mlx inherits MLX's memory behavior. burn-candle inherits Candle's.
- **Kokoro support:** None.

### Verdict (Option A)

Not viable today. Building Kokoro from scratch in Candle/Burn is weeks of work with uncertain memory benefits. The `metal-candle` backend _might_ have better memory behavior than MLX, but this is unproven.

| Criterion                | Rating                                             |
| ------------------------ | -------------------------------------------------- |
| Feasibility              | LOW -- no Kokoro model, major porting effort       |
| Expected RAM             | Unknown (Metal backend unproven for this workload) |
| Integration complexity   | HIGH -- Cargo/Rust build + C FFI to Swift          |
| Existing implementations | None for Kokoro                                    |

---

## Option B: ONNX Runtime (Kokoro v1.0 ONNX Model)

### Feasibility: HIGH -- this is the strongest option

**Kokoro-82M is already converted to ONNX format** and published on HuggingFace:

- `onnx-community/Kokoro-82M-v1.0-ONNX` -- standard model (f32: 310MB, fp16: 169MB, int8: 88MB)
- `onnx-community/Kokoro-82M-v1.0-ONNX-timestamped` -- variant with **word-level timestamp outputs** (critical for karaoke)

sherpa-onnx already supports the Kokoro v1.0 multi-lang model (`kokoro-multi-lang-v1_0.tar.bz2`) with both English and Chinese. **The project already has sherpa-onnx integrated** for CJK synthesis via `SherpaOnnxEngine.swift`.

### Architecture: Use sherpa-onnx for BOTH English and Chinese

The existing `SherpaOnnxEngine` handles CJK. The proposal is to use the same sherpa-onnx path for English Kokoro v1.0, replacing the MLX path entirely.

**Model:** `kokoro-multi-lang-v1_0` -- single model handles English + Chinese + other languages.

### Memory Behavior

ONNX Runtime on CPU uses standard `malloc`/`free`. No Metal GPU memory involved at all (CPU execution provider). The current sherpa-onnx CJK engine shows stable memory:

- Load: ~300-500MB RSS
- Per-call: No growth (measured across existing CJK synthesis calls)
- Idle unload: Already implemented with 30-second timer

With the CoreML execution provider, ONNX Runtime can optionally offload to ANE, but there are known issues with Kokoro + CoreML (sherpa-onnx issue #1792). **CPU execution is safer and still fast enough** -- Kokoro ONNX achieves near-real-time on Apple Silicon CPU.

### Word Timestamps

The `Kokoro-82M-v1.0-ONNX-timestamped` model variant outputs word-level timestamps directly. sherpa-onnx may or may not expose these through its C API -- needs verification. Alternative: use the existing `WordTimingAligner` with character-weighted fallback (already works for CJK path).

### Memory Leak in kokoro-onnx

Note: `thewh1teagle/kokoro-onnx` (Python) has a reported memory leak issue (#148) for long sentences. This appears to be in the Python wrapper, not ONNX Runtime itself. The C API used by sherpa-onnx manages memory explicitly and does not exhibit this pattern based on the existing CJK usage.

### Verdict (Option B)

**Recommended path.** Eliminates MLX entirely. Reuses existing sherpa-onnx infrastructure. The `kokoro-multi-lang-v1_0` model handles both English and Chinese in a single model, simplifying the architecture.

| Criterion                | Rating                                                  |
| ------------------------ | ------------------------------------------------------- |
| Feasibility              | HIGH -- model exists, sherpa-onnx already integrated    |
| Expected RAM             | ~300-500MB loaded, stable across calls, 0 when unloaded |
| Integration complexity   | LOW -- extend existing SherpaOnnxEngine                 |
| Existing implementations | sherpa-onnx supports kokoro-multi-lang-v1_0             |

### Key Risk

**Voice quality regression.** The current MLX kokoro-ios path uses the original PyTorch-derived MLX weights. The ONNX int8 quantized model may sound slightly different. Need A/B listening comparison.

**Word timestamp fidelity.** The kokoro-ios `MToken.start_ts/end_ts` provides native duration-model timestamps. sherpa-onnx may only provide phoneme-level timing, requiring the `WordTimingAligner` fallback. The `ONNX-timestamped` variant on HuggingFace may solve this if sherpa-onnx integrates it.

---

## Option C: mlx-swift Version Upgrade

### Feasibility: NONE -- the leak is architectural

**Current version:** mlx-swift 0.30.2 (pinned in Package.swift)
**Latest:** mlx-swift 0.31.x

The IOAccelerator leak is **not a bug in mlx-swift** -- it is a fundamental behavior of MLX's Metal allocator design. The `MetalAllocator` pools buffers by design and only frees on process exit. This is documented in:

- ml-explore/mlx issue #1086 ("Leak memory on exit" -- **intentional by design**)
- ml-explore/mlx issue #755 (Memory leak in MLX/Metal/MPS)
- ml-explore/mlx-lm issue #883 (kernel panic from unbounded memory growth -- reported Feb 2026)

The MLX 0.31.x release notes show fixes for Metal fused attention and CUDA, but **no changes to the Metal allocator's buffer pooling strategy**. The `Memory.clearCache()` and `Memory.cacheLimit` APIs only control MLX's internal buffer reuse pool, not the underlying IOAccelerator (graphics) regions that the Metal driver allocates.

**No alternative Swift MLX binding exists.** `mlx-swift` is the only official binding.

### Verdict (Option C)

Dead end. Upgrading mlx-swift will not fix the IOAccelerator leak. The only MLX-based mitigation is periodic process restart (already implemented in Phase 20.1).

| Criterion                | Rating                                           |
| ------------------------ | ------------------------------------------------ |
| Feasibility              | NONE -- leak is by design in MLX Metal allocator |
| Expected RAM             | Same ~1.5 GB/call growth                         |
| Integration complexity   | N/A                                              |
| Existing implementations | N/A                                              |

---

## Option D: Python MLX as Subprocess

### Feasibility: MEDIUM

Run `python3 -c "from mlx_audio.tts..."` (or a small script) per synthesis call instead of a persistent HTTP server. Each invocation is a fresh process; all Metal/IOAccelerator memory is reclaimed on `exit()`.

### Latency Analysis

- **Cold start:** ~2-5 seconds (Python startup + model load from disk)
- **Synthesis:** ~0.5-2 seconds per sentence (depending on length)
- **Total per call:** ~3-7 seconds (vs ~0.5-2s current warm path)

The cold-start penalty is severe for interactive TTS. Could be mitigated by:

1. Pre-loading model into shared memory (complex, fragile)
2. Keeping a "warm" subprocess alive for N calls, then killing it (basically reimplements the current restart-after-N-calls strategy)
3. Using `mlx.core.metal.set_cache_enabled(False)` to reduce (but not eliminate) growth

### Memory

Memory is fully reclaimed per invocation. Peak during synthesis: ~400-600MB. Returns to 0 after process exits.

### Integration

- Subprocess call from Swift via `Process()` (simple)
- Pass text as CLI arg, receive WAV path on stdout
- Word timestamps: would need a JSON output format from the Python script
- Requires Python 3.13 + mlx-audio installed (adds runtime dependency)

### Verdict (Option D)

Workable but slow. The 3-7 second latency per call makes it unsuitable for streaming sentence-by-sentence synthesis. Better as a fallback strategy than a primary engine.

| Criterion                | Rating                                   |
| ------------------------ | ---------------------------------------- |
| Feasibility              | MEDIUM -- works but high latency         |
| Expected RAM             | 0 between calls, ~500MB during synthesis |
| Integration complexity   | LOW -- subprocess with stdout protocol   |
| Existing implementations | mlx-audio CLI exists                     |

---

## Option E: CoreML Conversion

### Feasibility: HIGH -- multiple production implementations exist

Two production-quality CoreML conversions of Kokoro-82M are available:

### 1. FluidAudio (FluidInference/FluidAudio)

**The most polished option.**

- Swift SDK for on-device audio AI, available via SwiftPM and CocoaPods
- Kokoro-82M runs on **Apple Neural Engine** (ANE), not GPU/Metal
- Claims **55% less peak RAM** than MLX with equivalent speed
- Supports 9 languages including English
- **Word-level timestamps** supported
- macOS 14+ and iOS 17+ compatible
- Pre-converted model: `FluidInference/kokoro-82m-coreml` on HuggingFace

**Key advantage:** ANE inference means **zero Metal/GPU memory usage**. The IOAccelerator leak is specific to Metal compute pipelines. CoreML on ANE uses a completely different memory path.

### 2. kokoro-coreml (mattmireles/kokoro-coreml)

- PyTorch-to-CoreML conversion pipeline
- Two-stage architecture: Duration model + Decoder-only Synth
- Fixed input/output shapes (avoids CoreML dynamic-shape issues)
- 30-50% speedup via ANE optimization
- Swift-side alignment computation (avoids dynamic MIL graphs)

### 3. speech-swift (soniqo/speech-swift)

- Broader AI speech toolkit (ASR, TTS, VAD, diarization)
- Kokoro-82M via CoreML on Neural Engine
- Claims ~45ms per forward pass regardless of output length
- macOS 14+ compatible

### Memory Behavior

CoreML with `computeUnits = .cpuAndNeuralEngine` routes neural ops to ANE, which:

- Does NOT use Metal GPU buffers (no IOAccelerator regions)
- Has its own memory management that is well-behaved (Apple controls the entire stack)
- Peak RAM typically ~200-400MB for Kokoro-82M

### Caveats

- **sherpa-onnx CoreML provider has known issues** with Kokoro (issue #1792 -- shape errors)
- Using FluidAudio or kokoro-coreml directly bypasses sherpa-onnx entirely
- FluidAudio adds a dependency (~5-10MB) but is well-maintained
- CoreML model compilation happens on first load (can take 10-30 seconds, then cached)

### Verdict (Option E)

**Strong second choice after Option B.** FluidAudio is production-ready, runs on ANE (no Metal), and claims 55% less RAM than MLX. The word-level timestamp support addresses the karaoke requirement. Main risk is adding a new dependency and potential voice quality differences.

| Criterion                | Rating                                                 |
| ------------------------ | ------------------------------------------------------ |
| Feasibility              | HIGH -- FluidAudio is production-ready SwiftPM package |
| Expected RAM             | ~200-400MB (ANE, no Metal GPU memory)                  |
| Integration complexity   | MEDIUM -- new dependency, replaces MLX path            |
| Existing implementations | FluidAudio, kokoro-coreml, speech-swift                |

---

## Comparison Matrix

| Option                     | Feasibility | RAM (peak) | RAM (idle) | Memory Leak?        | Latency | Word Timestamps | Integration Effort        |
| -------------------------- | ----------- | ---------- | ---------- | ------------------- | ------- | --------------- | ------------------------- |
| **A: Rust/Candle**         | LOW         | Unknown    | Unknown    | Unknown             | Unknown | No              | HIGH (weeks)              |
| **B: ONNX Runtime**        | **HIGH**    | ~500MB     | 0 (unload) | **No**              | ~1-2s   | Partial         | **LOW** (extend existing) |
| **C: mlx-swift upgrade**   | NONE        | 1.5GB/call | N/A        | **Yes (by design)** | N/A     | N/A             | N/A                       |
| **D: Python subprocess**   | MEDIUM      | ~500MB     | 0          | **No**              | 3-7s    | Yes (mlx-audio) | LOW                       |
| **E: CoreML (FluidAudio)** | **HIGH**    | ~300MB     | ~100MB     | **No**              | ~1s     | Yes             | MEDIUM                    |

---

## Recommendation

### Primary: Option B -- sherpa-onnx with Kokoro v1.0 ONNX Model

**Why:**

1. **Zero new dependencies.** sherpa-onnx is already linked and working for CJK.
2. **Proven memory stability.** The existing `SherpaOnnxEngine` shows no memory growth across calls.
3. **Unified model.** `kokoro-multi-lang-v1_0` handles English + Chinese, eliminating the dual-engine architecture (MLX for English, sherpa-onnx for CJK).
4. **Simplifies the codebase.** Remove mlx-swift, KokoroSwift, MLXUtilsLibrary dependencies entirely. Binary size drops significantly.
5. **Idle unload already implemented.** The 30-second timer pattern in `SherpaOnnxEngine` works.

**Action items:**

1. Download `kokoro-multi-lang-v1_0` model to `~/.local/share/kokoro/models/`
2. Extend `SherpaOnnxEngine` to handle English text (currently only CJK)
3. A/B test voice quality: sherpa-onnx Kokoro v1.0 vs current kokoro-ios MLX
4. Verify word-level timestamp availability in sherpa-onnx Kokoro output
5. If timestamps unavailable, use existing `WordTimingAligner` character-weighted fallback
6. Remove mlx-swift, kokoro-ios, MLXUtilsLibrary from Package.swift

### Fallback: Option E -- FluidAudio CoreML

**If** sherpa-onnx voice quality is unacceptable or word timestamps are insufficient, FluidAudio provides:

- ANE inference (zero Metal memory)
- Native Swift integration via SwiftPM
- Word-level timestamps
- 55% less RAM than MLX

**Tradeoff:** Adds ~5-10MB dependency, requires CoreML model download (~300MB), first-load compilation delay.

### Do NOT Pursue

- **Option A (Rust):** Too much effort, no Kokoro implementation exists
- **Option C (mlx-swift upgrade):** The leak is by design, no fix coming
- **Option D (Python subprocess):** Latency too high for streaming TTS

---

## Sources

- [huggingface/candle -- Minimalist ML framework for Rust](https://github.com/huggingface/candle)
- [metal-candle -- Production-quality Rust ML for Apple Silicon](https://github.com/GarthDB/metal-candle)
- [tracel-ai/burn -- Next-gen tensor library for Rust](https://github.com/tracel-ai/burn)
- [onnx-community/Kokoro-82M-v1.0-ONNX](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX)
- [onnx-community/Kokoro-82M-v1.0-ONNX-timestamped](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX-timestamped)
- [thewh1teagle/kokoro-onnx -- TTS with kokoro and ONNX runtime](https://github.com/thewh1teagle/kokoro-onnx)
- [kokoro-onnx memory leak issue #148](https://github.com/thewh1teagle/kokoro-onnx/issues/148)
- [rishiskhare/tts-rs -- Kokoro TTS in Rust + ONNX](https://github.com/rishiskhare/tts-rs)
- [sherpa-onnx Kokoro pretrained models](https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html)
- [sherpa-onnx CoreML provider issue #1792](https://github.com/k2-fsa/sherpa-onnx/issues/1792)
- [ml-explore/mlx issue #1086 -- Leak memory on exit (by design)](https://github.com/ml-explore/mlx/issues/1086)
- [ml-explore/mlx issue #755 -- Memory leak in MLX/Metal/MPS](https://github.com/ml-explore/mlx/issues/755)
- [ml-explore/mlx-lm issue #883 -- kernel panic from unbounded memory growth](https://github.com/ml-explore/mlx-lm/issues/883)
- [ml-explore/mlx-swift releases](https://github.com/ml-explore/mlx-swift/releases)
- [FluidInference/FluidAudio -- CoreML audio models in Swift](https://github.com/FluidInference/FluidAudio)
- [FluidInference/kokoro-82m-coreml on HuggingFace](https://huggingface.co/FluidInference/kokoro-82m-coreml)
- [FluidAudio documentation -- Kokoro TTS](https://docs.fluidinference.com/tts/kokoro)
- [mattmireles/kokoro-coreml -- PyTorch to CoreML pipeline](https://github.com/mattmireles/kokoro-coreml)
- [soniqo/speech-swift -- AI speech toolkit for Apple Silicon](https://github.com/soniqo/speech-swift)
- [Blaizzy/mlx-audio -- MLX-based TTS/STT](https://github.com/Blaizzy/mlx-audio)
