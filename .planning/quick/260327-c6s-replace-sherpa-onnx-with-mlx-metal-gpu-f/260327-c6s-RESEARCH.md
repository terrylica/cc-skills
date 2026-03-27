# Replace sherpa-onnx with MLX Metal GPU - Research

**Researched:** 2026-03-27
**Domain:** TTS inference backend migration (sherpa-onnx CPU -> MLX/CoreML Metal GPU)
**Confidence:** HIGH
**Hardware:** Apple M3 Max, 36GB unified memory

## Summary

Replacing sherpa-onnx ONNX Runtime CPU backend with an MLX or CoreML Metal GPU path for Kokoro TTS synthesis is feasible, with multiple viable options at different tradeoff points. The current sherpa-onnx int8 implementation achieves RTF 0.25-0.58 (depending on text length and thread count), which is already faster than real-time but leaves significant GPU headroom untapped.

The strongest options are: (1) **kokoro-ios (mlalma)** -- a pure MLX Swift Kokoro port with 3.3x faster-than-realtime on iPhone 13 Pro (M3 Max would be significantly faster), and (2) **FluidAudio CoreML** -- which achieves 23x RTFx on M4 Pro but lacks word-level timestamps critical for karaoke. The Python mlx-audio subprocess approach is the lowest-risk fallback since it is the already-proven legacy system.

**Primary recommendation:** Use **kokoro-ios (mlalma)** as an SPM dependency, replacing sherpa-onnx entirely. This gives MLX Metal GPU acceleration, eliminates the 62MB libonnxruntime.a static lib, and the MLX weights format is more memory-efficient. The main risk is phonemization differences (eSpeak NG vs Kokoro's native phonemizer) and maturity of the library.

## Current State (Baseline)

### sherpa-onnx int8 CPU Performance (M3 Max)

| Metric                          | Full-Precision (330MB model) | Int8 (109MB model)      |
| ------------------------------- | ---------------------------- | ----------------------- |
| Model size on disk              | 330MB                        | 109MB                   |
| Peak RSS                        | 1,237MB                      | ~561MB                  |
| RTF (short sentence, 4 threads) | 0.28                         | ~0.58 (spike 10)        |
| RTF (paragraph, 4 threads)      | 0.25                         | Not separately measured |
| Model load time                 | 0.56s                        | ~0.56s                  |
| Binary size (stripped)          | 19MB                         | ~38MB (with all libs)   |

**Note:** The spike 03 RTF of 0.25 was with the **full precision** model on 4 threads. The int8 model was introduced later for memory savings (561MB vs 1,237MB RSS) but appears to be slower on CPU (spike 10 measured RTF 0.58 for int8). This is counterintuitive -- int8 should be faster on CPU. The discrepancy may be due to different text lengths or thread counts between spikes.

### Legacy Python mlx-audio Performance

The legacy `~/.local/share/kokoro/tts_server.py` uses `mlx-community/Kokoro-82M-bf16` via mlx-audio Python. No recorded RTF benchmarks were found on disk, but spike 03 recorded the Python server at:

- RSS: 163MB (7.6x lower than full-precision sherpa-onnx)
- Synthesis time: ~2s per chunk (comparable per-word to sherpa-onnx)
- Model: bf16 MLX weights on Metal GPU

### Static Library Sizes (Current)

| Library                           | Size      |
| --------------------------------- | --------- |
| libonnxruntime.a                  | 62.3MB    |
| libsherpa-onnx.a (all components) | 17.1MB    |
| libsherpa-onnx-core.a             | 10.4MB    |
| Other sherpa libs                 | ~6.6MB    |
| **Total sherpa-onnx static libs** | **~96MB** |

## Option Analysis

### Option 1: kokoro-ios (mlalma) -- MLX Swift Native

**What:** Pure Swift Kokoro TTS built on mlx-swift. Ports MLX Python Kokoro to MLX Swift.

| Property        | Value                                                                      |
| --------------- | -------------------------------------------------------------------------- |
| Repository      | <https://github.com/mlalma/kokoro-ios>                                     |
| SPM             | `.package(url: "https://github.com/mlalma/kokoro-ios.git", from: "1.0.0")` |
| Dependencies    | mlx-swift, MisakiSwift (G2P), MLXUtilsLibrary                              |
| Platforms       | macOS 15.0+, iOS 18.0+                                                     |
| Model format    | MLX safetensors weights (from HuggingFace)                                 |
| Performance     | ~3.3x faster than real-time (iPhone 13 Pro); M3 Max expected much faster   |
| Phonemizer      | MisakiSwift (different from Kokoro native -- audio output will differ)     |
| Word timestamps | Not built-in; would need custom extraction from duration model             |

**Pros:**

- Pure Swift, native SPM integration
- MLX Metal GPU acceleration (uses Apple Silicon GPU natively)
- Eliminates 96MB of ONNX Runtime static libraries
- Lower memory than ONNX (MLX uses unified memory efficiently)
- Active development (v1.0.5+)

**Cons:**

- Requires macOS 15.0+ (current target is macOS 14+; would need to bump)
- MisakiSwift phonemizer produces different audio than sherpa-onnx eSpeak-NG
- No word-level timestamp support out of the box
- Library maturity: relatively new, fewer users than sherpa-onnx
- mlx-swift pulls in Metal shaders compiled at build time (build time impact)
- Model format change: need MLX safetensors instead of ONNX int8

**Confidence:** MEDIUM -- library works but word-timestamp integration is unproven

### Option 2: FluidAudio CoreML

**What:** CoreML-based Kokoro TTS running on Apple Neural Engine.

| Property        | Value                                                                              |
| --------------- | ---------------------------------------------------------------------------------- |
| Repository      | <https://github.com/FluidInference/FluidAudio>                                     |
| SPM             | `.package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.7")` |
| Product         | FluidAudioWithTTS                                                                  |
| Performance     | 23.2x RTFx on M4 Pro; CoreML matches MLX speed with 55% less peak RAM              |
| Peak RAM        | 1.5GB                                                                              |
| Dependencies    | **28 transitive dependencies**                                                     |
| Word timestamps | **NOT SUPPORTED** -- only chunk-level metadata via synthesizeDetailed()            |
| Streaming       | **NOT SUPPORTED** -- generates all frames at once                                  |

**Pros:**

- Fastest option (23x RTFx) -- runs on Neural Engine
- Professional SDK with documentation
- 55% less RAM than MLX path
- CoreML model auto-compiled and cached by macOS

**Cons:**

- **CRITICAL: No word-level timestamps** -- breaks karaoke highlighting entirely
- **28 transitive dependencies** -- massive footprint increase vs current 3 deps
- 15s initial CoreML compilation on first run
- CoreML targets CPU+ANE explicitly (avoids GPU for iOS background compat)
- Would need to reimplement word timing externally
- Overkill dependency for TTS-only use case (SDK includes ASR, VAD, diarization)

**Confidence:** HIGH for performance, but **DISQUALIFIED** for this project due to missing word timestamps and dependency bloat

### Option 3: Python mlx-audio Subprocess (HTTP)

**What:** Keep the legacy `tts_server.py` running as a separate process, call via HTTP from Swift.

| Property         | Value                                                                   |
| ---------------- | ----------------------------------------------------------------------- |
| Binary overhead  | 0 (Python runs separately)                                              |
| Performance      | MLX Metal GPU, RTF likely < 0.3 based on comparable benchmarks          |
| Latency overhead | ~5-10ms HTTP localhost round-trip per request                           |
| Dependencies     | Python 3.13, mlx-audio pip package, venv at ~/.local/share/kokoro/.venv |
| Word timestamps  | Not natively -- would need post-hoc extraction same as current          |

**Pros:**

- **KNOWN WORKING** -- this is the legacy system that was replaced
- Zero binary size impact
- MLX Metal GPU acceleration (proven)
- No code changes to TTSEngine beyond HTTP client
- Model already downloaded (mlx-community/Kokoro-82M-bf16)

**Cons:**

- **Contradicts project goal** of "one binary, one service" (reintroduces Python process)
- Requires Python runtime + pip packages managed separately
- HTTP overhead per synthesis call
- Two processes to manage via launchd
- Memory: separate Python process (~163MB) not shared with Swift binary

**Confidence:** HIGH for feasibility, but contradicts architectural goals

### Option 4: sherpa-onnx with CoreML Execution Provider

**What:** Keep sherpa-onnx but switch provider from "cpu" to "coreml".

| Property    | Value                                      |
| ----------- | ------------------------------------------ |
| Code change | Single line: `provider = strdup("coreml")` |
| Performance | **LIKELY WORSE than CPU**                  |

**Evidence against this option:**

- GitHub issue #2910: CoreML RTF 0.470 vs CPU RTF 0.427 on M2 Max (CoreML was **slower**)
- GitHub issue #152: CoreML crashes on TTS models; partial operator mapping only
- sherpa-onnx maintainer acknowledged CoreML is unpredictable for Transformer models
- Maintainer mentioned plans to merge "sherpa-mlx" into sherpa-onnx for proper Metal support, but no evidence this exists yet
- Int8 quantized models are even less likely to benefit from CoreML (ANE prefers float16)

**Confidence:** HIGH that this will NOT work well -- evidence strongly against

### Option 5: mlx-audio-swift (Blaizzy)

**What:** Official mlx-audio Swift SDK -- modular audio processing framework.

| Property       | Value                                                                                                      |
| -------------- | ---------------------------------------------------------------------------------------------------------- |
| Repository     | <https://github.com/Blaizzy/mlx-audio-swift>                                                               |
| Platforms      | macOS 14+, iOS 17+                                                                                         |
| Products       | MLXAudioTTS, MLXAudioCore (modular imports)                                                                |
| Dependencies   | mlx-swift, swift-transformers                                                                              |
| Kokoro support | **NOT LISTED** -- supports Qwen3-TTS, Fish Audio S2 Pro, Soprano, VyvoTTS, Orpheus, Marvis TTS, Pocket TTS |

**Cons:**

- **Does not support Kokoro model** -- different model architecture
- Would require switching TTS model entirely
- Unproven for this use case

**Confidence:** LOW -- not applicable for Kokoro

### Option 6: Handrolled Metal Compute Shaders

**What:** Write Metal compute shaders directly for Kokoro's architecture.

**Verdict:** Completely unrealistic for an 82M parameter model with conv1d, LSTM, attention, and duration prediction layers. Would take months of work. Not a viable option.

**Confidence:** HIGH that this is not viable

### Option 7: kokoro-swift-mlx (mattmireles)

**What:** Another MLX Swift Kokoro port, experimental.

| Property    | Value                                               |
| ----------- | --------------------------------------------------- |
| Repository  | <https://github.com/mattmireles/kokoro-swift-mlx>   |
| Performance | Same ~3.3x RTFx claim (iPhone 13 Pro)               |
| Phonemizer  | eSpeak NG (compiled separately as xcframework)      |
| Status      | Experimental, requires manual eSpeak NG compilation |

**Verdict:** Less mature than mlalma/kokoro-ios. Same fundamental approach but with more manual setup. Not recommended over Option 1.

## Ranked Recommendations

| Rank | Option                          | RTF Estimate             | Binary Impact                  | Effort  | Risk   | Word Timestamps   |
| ---- | ------------------------------- | ------------------------ | ------------------------------ | ------- | ------ | ----------------- |
| 1    | **kokoro-ios (mlalma)**         | ~0.10-0.15 (est. M3 Max) | -60MB (remove ONNX) +?MB (MLX) | MEDIUM  | MEDIUM | Needs custom work |
| 2    | **Python mlx-audio subprocess** | ~0.15-0.25               | 0                              | LOW     | LOW    | Same as current   |
| 3    | **FluidAudio CoreML**           | ~0.04 (23x RTFx)         | +large (28 deps)               | LOW     | HIGH   | **MISSING**       |
| 4    | **sherpa-onnx CoreML EP**       | ~0.47+ (slower)          | 0                              | TRIVIAL | HIGH   | Same as current   |

## Implementation Effort Estimates

### Option 1: kokoro-ios (mlalma) -- Recommended

**Estimated effort: 2-3 days**

1. Add kokoro-ios SPM dependency, remove CSherpaOnnx target (0.5 day)
2. Rewrite TTSEngine.swift to use kokoro-ios API instead of sherpa-onnx C API (1 day)
3. Handle model download/path configuration for MLX safetensors (0.5 day)
4. Implement word timing extraction from MLX model output (0.5-1 day)
5. Bump macOS deployment target from 14 to 15 (trivial)
6. Test and benchmark (0.5 day)

**Key unknowns:**

- Does kokoro-ios expose raw duration tensors for word timing?
- What is the actual binary size delta (remove ONNX libs, add MLX framework)?
- Does the MisakiSwift phonemizer produce acceptable audio quality?
- Build time impact of MLX Metal shader compilation

### Option 2: Python subprocess -- Fallback

**Estimated effort: 0.5 day**

1. Add HTTP client to TTSEngine.swift calling localhost:8779 (0.25 day)
2. Ensure tts_server.py launchd service is running alongside companion (0.25 day)

### Spike Recommendation

Before committing to Option 1, run a **validation spike** (2-4 hours):

1. Create a minimal Swift CLI that imports kokoro-ios
2. Synthesize the same test sentences used in spike 03
3. Measure RTF, RSS, binary size, and model load time on M3 Max
4. Verify audio quality with MisakiSwift phonemizer
5. Check if duration tensor data is accessible for word timing

## Common Pitfalls

### Pitfall 1: macOS Version Bump

**What goes wrong:** kokoro-ios requires macOS 15.0+; current deployment target is macOS 14
**How to avoid:** Verify user's macOS version first. M3 Max machines ship with macOS 14+ and can upgrade to 15. Check `sw_vers` before committing.

### Pitfall 2: Phonemizer Differences

**What goes wrong:** MisakiSwift produces different phonemes than sherpa-onnx's eSpeak-NG, changing voice quality
**How to avoid:** A/B test audio output quality before switching. Users may notice voice changes.

### Pitfall 3: Word Timestamp Regression

**What goes wrong:** Losing word-level timestamps that drive karaoke highlighting
**How to avoid:** Verify kokoro-ios exposes duration model output. If not, character-weighted fallback (current implementation) still works with actual audio duration.

### Pitfall 4: Model Format Migration

**What goes wrong:** Current model is ONNX int8 at ~/.local/share/kokoro/models/kokoro-int8-multi-lang-v1_0/
**How to avoid:** MLX models are different format. Need to download MLX safetensors weights from HuggingFace (mlx-community/Kokoro-82M-bf16 or similar). Both can coexist on disk.

### Pitfall 5: Build Time Explosion

**What goes wrong:** mlx-swift compiles Metal shaders at build time, potentially adding minutes to `swift build`
**How to avoid:** Measure build time in spike. Consider using pre-compiled MLX if available.

## Footprint Analysis

| Component              | Current (sherpa-onnx)        | Option 1 (kokoro-ios/MLX)             | Option 2 (Python subprocess) |
| ---------------------- | ---------------------------- | ------------------------------------- | ---------------------------- |
| Binary size (stripped) | ~38MB                        | ~25-35MB (est.)                       | ~20MB (remove ONNX libs)     |
| Static lib overhead    | 96MB source                  | ~15-25MB (MLX, est.)                  | 0                            |
| Model on disk          | 109MB (int8 ONNX)            | ~165MB (bf16 safetensors)             | ~165MB (already present)     |
| Peak RSS               | ~561MB                       | ~300-500MB (est.)                     | ~163MB Python + ~30MB Swift  |
| SPM dependencies       | 3 (telegram, log, flyingfox) | 4+ (add mlx, kokoro-ios, misakiswift) | 3 (unchanged)                |
| External dependencies  | None                         | None                                  | Python 3.13 + venv           |
| macOS minimum          | 14                           | 15                                    | 14                           |

## Project Constraints (from CLAUDE.md)

- **Platform:** macOS Apple Silicon only
- **Build:** `swift build` via SwiftPM (not Xcode)
- **Python:** "Not used -- pure Swift + C (sherpa-onnx static libs)" -- Option 2 (subprocess) contradicts this
- **Model:** Kokoro at `~/.local/share/kokoro/models/` -- new MLX model would need similar path
- **Key decision:** "sherpa-onnx over CoreML/FluidAudio" was made based on spike 05 data; this research provides updated evidence

## Open Questions

1. **kokoro-ios actual RTF on M3 Max** -- the 3.3x RTFx claim is on iPhone 13 Pro. M3 Max GPU is significantly more powerful; actual RTF could be 0.05-0.15 (estimated, needs validation)

2. **MLX model availability for multi-lang v1.0** -- current model is kokoro-int8-multi-lang-v1_0 with 53 voices. Does an MLX safetensors version exist for this specific model, or only the 82M English-only?

3. **Word timing from kokoro-ios** -- does the library expose the duration model tensor? If not, can we fork and add it? (This is the single biggest risk)

4. **Build time impact** -- how long does `swift build` take with mlx-swift? Current build is ~30s.

5. **Chinese voice support** -- current system uses speaker ID 45 (zf_xiaobei) for CJK text. Does kokoro-ios support multi-lang voices?

## Sources

### Primary (HIGH confidence)

- [Spike 03 Report](~/tmp/subtitle-spikes-7aqa/03-textream/SPIKE-03-REPORT.md) -- sherpa-onnx baseline benchmarks
- [Spike 10 Report](~/tmp/subtitle-spikes-7aqa/10-e2e-flow/SPIKE-10-E2E-REPORT.md) -- int8 RTF 0.58
- [sherpa-onnx issue #2910](https://github.com/k2-fsa/sherpa-onnx/issues/2910) -- CoreML slower than CPU
- [sherpa-onnx issue #152](https://github.com/k2-fsa/sherpa-onnx/issues/152) -- CoreML support incomplete
- [FluidInference/kokoro-82m-coreml](https://huggingface.co/FluidInference/kokoro-82m-coreml) -- 23x RTFx benchmark
- [FluidAudio docs](https://docs.fluidinference.com/tts/kokoro) -- no word timestamps, 28 deps

### Secondary (MEDIUM confidence)

- [mlalma/kokoro-ios](https://github.com/mlalma/kokoro-ios) -- 3.3x RTFx on iPhone 13 Pro
- [mattmireles/kokoro-swift-mlx](https://github.com/mattmireles/kokoro-swift-mlx) -- alternative MLX Swift port
- [Blaizzy/mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) -- no Kokoro support
- [ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift) -- v0.31.1, depends on mlx-c

### Tertiary (LOW confidence)

- RTF estimates for M3 Max are extrapolated from iPhone 13 Pro benchmarks -- needs validation
- Binary size estimates for MLX are based on general SPM knowledge -- needs build measurement

## Metadata

**Confidence breakdown:**

- Current baseline performance: HIGH -- measured in spikes 03 and 10
- Option ranking: MEDIUM -- kokoro-ios M3 Max performance is extrapolated
- Footprint estimates: LOW -- need actual build measurements
- Word timestamp risk: HIGH -- this is the critical unknown

**Research date:** 2026-03-27
**Valid until:** 2026-04-10 (MLX ecosystem evolving rapidly)
