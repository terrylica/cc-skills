# Benchmark: FluidAudio CoreML Kokoro TTS

**Date**: 2026-03-27
**Researcher**: Claude (automated web research)
**Purpose**: Evaluate FluidAudio as a potential replacement for sherpa-onnx Kokoro TTS in claude-tts-companion

## Availability

| Item           | Status                                                                           | Details                                                                                                                             |
| -------------- | -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| GitHub         | **Active**                                                                       | [FluidInference/FluidAudio](https://github.com/FluidInference/FluidAudio) -- 1,757 stars, 240 forks, Apache-2.0, created 2025-06-21 |
| SwiftPM        | **Available**                                                                    | `.package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4")`                                                 |
| CocoaPods      | Available                                                                        | Also listed on CocoaPods                                                                                                            |
| Model          | **Available**                                                                    | [FluidInference/kokoro-82m-coreml](https://huggingface.co/FluidInference/kokoro-82m-coreml) on HuggingFace, Apache-2.0              |
| Documentation  | [docs.fluidinference.com/tts/kokoro](https://docs.fluidinference.com/tts/kokoro) | Moderate quality, covers basics but TTS API docs are thin                                                                           |
| Latest version | v0.13.3 (2026-03-28)                                                             | Active development, 38 releases in 9 months                                                                                         |

## Word Timing (NON-NEGOTIABLE) -- BLOCKER

| Aspect             | Finding                                                                                                                                                                                                     |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Supported**      | **NO**                                                                                                                                                                                                      |
| **API**            | `synthesize(text:)` returns raw audio data only. `synthesizeDetailed(text:, variantPreference:)` returns chunk metadata (chunk index, variant used, token count, text segment) but **no word-level timing** |
| **Duration model** | Kokoro internally uses a 6-LSTM duration predictor that runs on CPU, but this output is **not exposed** through any public API                                                                              |
| **SSML timing**    | Only `<phoneme>`, `<sub>`, `<say-as>` supported. No `<break>` or `<prosody duration>`. No temporal control                                                                                                  |
| **Documentation**  | Zero mentions of "word timing", "timestamp", "onset", "duration" in TTS docs                                                                                                                                |
| **GitHub issues**  | Zero issues requesting or discussing word-level timestamps for TTS                                                                                                                                          |
| **Source code**    | Duration predictor output is consumed internally by the synthesis pipeline; no hook point to extract it                                                                                                     |

**Evidence**: Searched docs.fluidinference.com/tts/kokoro, Documentation/TTS/Kokoro.md, Documentation/TTS/SSML.md, Documentation/API.md, all GitHub issues, DeepWiki analysis. None mention word-level timing output.

**Comparison with sherpa-onnx**: Our current sherpa-onnx setup has a ~50-line C++ patch (spike 16) that extracts word-level timestamps from the duration model at zero cost. FluidAudio's CoreML pipeline has no equivalent hook point -- the duration model output is consumed inside the CoreML graph with no intermediate extraction.

## Performance (M4 Pro, 48GB -- from HuggingFace benchmarks)

| Implementation     | Total Inference (s)     | RTFx       | Peak RAM (GB) | Warm-up (s) |
| ------------------ | ----------------------- | ---------- | ------------- | ----------- |
| PyTorch CPU        | 27.177                  | 16.99x     | 4.85          | 0.175       |
| PyTorch MPS        | crashed on long strings | 9.96x      | 1.54          | 0.568       |
| **MLX Pipeline**   | 19.401                  | **23.80x** | 3.37          | 2.155       |
| **Swift + CoreML** | 17.408                  | **23.23x** | **1.503**     | ~2.348      |

Test: 461.65s of output audio on M4 Pro.

### V2 ANE-optimized models (from Kokoro.md docs)

| Metric                   | V1       | V2 (ANE)     |
| ------------------------ | -------- | ------------ |
| Median latency (5s text) | 417 ms   | **250 ms**   |
| RTFx                     | 12.0x    | **20.0x**    |
| Speedup                  | baseline | 1.67x faster |

### Key performance claims

- "CoreML matches MLX speed with 55% less peak RAM" -- **verified**: 1.503 GB vs 3.37 GB = 55.4% less
- Runs on **ANE (Neural Engine)** with fp16, except 6 LSTM ops (duration predictor) on CPU
- Does NOT use GPU/MPS -- pure ANE + CPU
- First-run CoreML compilation: **~15 seconds** (cached after, ~2s subsequent loads)
- Generation is parallel (all frames at once) -- must wait for complete audio before playback (no streaming)

## Integration Assessment

### SwiftPM dependencies

FluidAudio pulls in:

- `swift-transformers` v1.3.0+ (HuggingFace) -- provides `Tokenizers` product
- Internal C++ wrappers: `FastClusterWrapper`, `MachTaskSelfWrapper` (CXX17)

### Conflict analysis with existing stack

| Dependency                      | Conflict?              | Notes                                                           |
| ------------------------------- | ---------------------- | --------------------------------------------------------------- |
| sherpa-onnx (static libs)       | **No direct conflict** | Different C++ libs, no symbol overlap                           |
| swift-telegram-sdk              | No                     | Unrelated                                                       |
| FlyingFox                       | No                     | Unrelated                                                       |
| swift-log                       | No                     | Not pulled in by FluidAudio                                     |
| swift-argument-parser           | No                     | Not pulled in by FluidAudio                                     |
| swift-transformers (Tokenizers) | **NEW dependency**     | Adds HuggingFace tokenizer runtime; moderate binary size impact |

### Model specifics

| Item                    | Value                                                                               |
| ----------------------- | ----------------------------------------------------------------------------------- |
| Base model              | hexgrad/Kokoro-82M (82M params)                                                     |
| CoreML format           | fp16 for ANE, duration predictor on CPU                                             |
| PyTorch model size      | ~327 MB (kokoro-v1_0.pth)                                                           |
| CoreML model size       | Not published; estimate ~200-350 MB (CoreML fp16 is typically smaller than PyTorch) |
| ONNX int8 (our current) | **129 MB** -- significantly smaller                                                 |
| First-load compilation  | ~15 seconds (CoreML compiles to device-specific binary)                             |
| Subsequent loads        | ~2 seconds                                                                          |

### Integration with TTSEngine actor pattern

FluidAudio provides `TtSManager` (or `KokoroTtsManager`) with async/await API:

```swift
let manager = TtSManager()
let audioData = try await manager.synthesize(text: "Hello")
```

This would integrate cleanly with our actor pattern, BUT the lack of word timing means we cannot drive karaoke subtitles from it.

## Known Issues

1. **Sibilance in female voices** -- af_heart (A grade) and af_bella (A-) both have harsh sibilant sounds. A de-esser was added (enabled by default) but the underlying issue persists
2. **English-only** -- no multilingual support (same as our current setup, not a blocker)
3. **G2P phoneme mismatches** -- certain common words ("hello", "day") have pronunciation errors
4. **No streaming** -- must wait for full generation (Kokoro generates all frames at once)
5. **15-second cold start** -- first CoreML compilation is slow (mitigated by caching)
6. **PyTorch CPU memory leak** -- documented in upstream Kokoro, but CoreML path appears clean
7. **PyTorch MPS crashes on long strings** -- CoreML path not affected
8. **Voice quality variance** -- only bf_emma rated "quite good"; many voices have noise or distortion artifacts

## Voice Quality Assessment (from FluidAudio's own evaluation)

| Voice      | Grade | Quality Notes                |
| ---------- | ----- | ---------------------------- |
| bf_emma    | B-    | "Quite good" -- best overall |
| af_heart   | A     | Strong sibilance issues      |
| af_bella   | A-    | Sibilance issues             |
| am_adam    | F+    | "Usable" despite low grade   |
| af_jessica | --    | "Noticeably low quality"     |
| bf_alice   | --    | "Quality quite bad"          |

## Verdict

**Suitable for production karaoke TTS? NO.**

### Disqualifying factor: No word-level timestamps

The claude-tts-companion project requires word-for-word timing for karaoke subtitle highlighting. This is non-negotiable. FluidAudio's CoreML Kokoro implementation:

1. **Does not expose word-level timestamps** through any public API
2. **Cannot be patched** to extract them -- unlike sherpa-onnx where we added a ~50-line C++ patch to the duration model, CoreML models are opaque compiled graphs with no intermediate value extraction
3. **The duration predictor runs on CPU** (6 LSTM ops), but its output feeds directly into the CoreML synthesis pipeline with no interception point

### What FluidAudio does well

- **55% less RAM** than MLX (1.5 GB vs 3.37 GB peak) -- genuinely impressive
- **ANE offloading** -- frees GPU entirely, good for concurrent workloads
- **Clean SwiftPM integration** -- minimal dependencies, no ONNX Runtime needed
- **Active development** -- 38 releases in 9 months, responsive maintainers

### When FluidAudio would make sense

- Audio-only TTS (no subtitle sync needed)
- Memory-constrained environments (iOS apps)
- Apps that need ANE to keep GPU free for other work
- If FluidAudio adds word timing API in the future (worth watching)

### Recommendation

**Stay with sherpa-onnx.** The custom C++ duration-model patch giving us zero-cost word timestamps is the critical differentiator. No other Kokoro implementation (CoreML, MLX, PyTorch) exposes this data without similar source-level patching, and CoreML's compiled-graph architecture makes such patching impossible.

If RAM pressure from sherpa-onnx becomes critical (our current peak is 561 MB with int8), the correct mitigation is the synthesis counter + graceful restart pattern already implemented in phase 20.1, not switching to a fundamentally incompatible TTS backend.

## Sources

- [FluidAudio GitHub](https://github.com/FluidInference/FluidAudio)
- [FluidAudio Kokoro Docs](https://docs.fluidinference.com/tts/kokoro)
- [kokoro-82m-coreml on HuggingFace](https://huggingface.co/FluidInference/kokoro-82m-coreml)
- [FluidAudio Benchmarks.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)
- [FluidAudio TTS/Kokoro.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/TTS/Kokoro.md)
- [FluidAudio TTS/voice-quality.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/TTS/voice-quality.md)
- [FluidAudio Package.swift](https://github.com/FluidInference/FluidAudio/blob/main/Package.swift)
- [FluidAudio Releases](https://github.com/FluidInference/FluidAudio/releases)
- [DeepWiki FluidAudio Analysis](https://deepwiki.com/FluidInference/FluidAudio)
