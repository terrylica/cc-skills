# Spike Report: kokoro-ios (MLX Swift Kokoro TTS) on M3 Max

**Date**: 2026-03-27
**Platform**: macOS 15.7.5 (24G624), Apple M3 Max
**kokoro-ios version**: 1.0.11
**mlx-swift version**: 0.30.2
**Model**: kokoro-v1_0.safetensors (327 MB, bf16, from mlx-community/Kokoro-82M-bf16)

## Results Summary

| Metric                   | Value          | Notes                                   |
| ------------------------ | -------------- | --------------------------------------- |
| Model load time          | 0.078s         | safetensors to MLX array                |
| Voice load time          | 0.003s         | NPZ to MLXArray                         |
| Warmup synthesis time    | 4.381s         | First-ever inference (Metal shader JIT) |
| Synthesis time (cold)    | 1.492s         | Second inference                        |
| Synthesis time (warm)    | 1.097s         | Third inference                         |
| Audio duration           | 11.40s         | 163-char test sentence                  |
| **RTF (cold)**           | **0.1309**     | Well below 0.3 target                   |
| **RTF (warm)**           | **0.0963**     | ~10x faster than real-time              |
| Peak RSS                 | 524.4 MB       | During synthesis                        |
| RSS after model load     | 45.0 MB        | Before first synthesis                  |
| RSS after synthesis      | 436.5 MB       | Resident set after synthesis            |
| **Word timestamps?**     | **YES**        | Via `TimestampPredictor` + `MToken`     |
| Timestamp method         | Duration model | Per-phoneme durations mapped to words   |
| Sample rate              | 24000 Hz       | Same as sherpa-onnx                     |
| Binary size (unstripped) | 25 MB          | Executable only                         |
| Binary size (stripped)   | 15 MB          | Executable only                         |
| KokoroSwift.dylib        | 27 MB          | Required at runtime                     |
| MisakiSwift.dylib        | 27 MB          | Required at runtime (G2P)               |
| mlx.metallib             | 102 MB         | Required at runtime (Metal shaders)     |
| Model on disk            | 327 MB         | bf16 safetensors                        |
| Build time (first)       | 108s           | Full release build from scratch         |
| Build time (incremental) | 1.3s           | After touching main.swift               |

## Test Sentence

> "Hi Terry, you were working in claude tts companion. The subtitle system was refactored to use AVAudioPlayer with CADisplayLink polling for drift-free karaoke sync."

## Word Timestamps Output

All 29 tokens received timestamps with phoneme data:

```
[ 0.275s -  0.488s] "Hi"             phonemes=hˈI
[ 0.488s -  1.025s] "Terry"          phonemes=tˈɛɹi
[ 1.025s -  1.125s] ","              phonemes=,
[ 1.125s -  1.212s] "you"            phonemes=ju
[ 1.212s -  1.350s] "were"           phonemes=wɜɹ
[ 1.350s -  1.800s] "working"        phonemes=wˈɜɹkɪŋ
[ 1.800s -  1.962s] "in"             phonemes=ɪn
[ 1.962s -  2.362s] "claude"         phonemes=klˈɔd
[ 2.362s -  2.700s] "tts"            phonemes=tˈɪsts
[ 2.700s -  3.750s] "companion"      phonemes=kəmpˈænjən
[ 3.750s -  3.888s] "."              phonemes=.
[ 3.888s -  4.037s] "The"            phonemes=ðə
[ 4.037s -  4.550s] "subtitle"       phonemes=sˈʌbtˌITᵊl
[ 4.550s -  5.025s] "system"         phonemes=sˈɪstəm
[ 5.025s -  5.200s] "was"            phonemes=wʌz
[ 5.200s -  5.800s] "refactored"     phonemes=ɹifˈæktəɹd
[ 5.800s -  5.925s] "to"             phonemes=tə
[ 5.925s -  6.188s] "use"            phonemes=jˈuz
[ 6.188s -  7.225s] "AVAudioPlayer"  phonemes=ˌɑvjudˌIˈOplAəɹ
[ 7.225s -  7.412s] "with"           phonemes=wɪð
[ 7.412s -  8.238s] "CADisplayLink"  phonemes=kˌædəsplˈAlɪŋk
[ 8.238s -  8.700s] "polling"        phonemes=pˈOlɪŋ
[ 8.700s -  8.850s] "for"            phonemes=fɔɹ
[ 8.850s -  9.550s] "drift"          phonemes=dɹˈɪft
[ 9.550s -  9.700s] "-"              phonemes=—
[ 9.700s -  9.938s] "free"           phonemes=fɹˈi
[ 9.938s - 10.587s] "karaoke"        phonemes=kˌɛɹiˈOki
[10.587s - 11.150s] "sync"           phonemes=sˈɪŋk
[11.150s - 11.300s] "."              phonemes=.
```

## Comparison with sherpa-onnx

| Metric           | sherpa-onnx (int8)          | kokoro-ios (MLX bf16)                         | Winner                |
| ---------------- | --------------------------- | --------------------------------------------- | --------------------- |
| RTF              | ~0.15-0.20 (CPU)            | 0.096 (GPU, warm)                             | kokoro-ios            |
| Peak RSS         | ~561 MB                     | 524 MB                                        | kokoro-ios (marginal) |
| Model size       | 129 MB (int8)               | 327 MB (bf16)                                 | sherpa-onnx           |
| Word timestamps  | Custom C++ patch (50 lines) | Built-in `TimestampPredictor`                 | kokoro-ios            |
| Build complexity | Static C libs, C interop    | SwiftPM, but needs metallib workaround        | sherpa-onnx           |
| Dependency tree  | sherpa-onnx + ONNX Runtime  | mlx-swift + MisakiSwift + ZIPFoundation       | Similar               |
| Binary + runtime | ~19 MB binary               | 15 MB binary + 54 MB dylibs + 102 MB metallib | sherpa-onnx           |
| Sample rate      | 24000 Hz                    | 24000 Hz                                      | Tie                   |
| Languages        | Multi-lang (int8)           | English only (misaki G2P)                     | sherpa-onnx           |
| G2P              | External (espeak-ng)        | Built-in (MisakiSwift)                        | kokoro-ios            |

## Critical Issues Found

### 1. metallib Requirement (BLOCKER for CLI builds)

mlx-swift explicitly states: **"SwiftPM (command line) cannot build the Metal shaders so the ultimate build has to be done via Xcode."**

Without Xcode installed, the `mlx.metallib` (Metal shader library, 102 MB) cannot be compiled. The workaround used in this spike was to extract the pre-compiled metallib from the Python `mlx` pip package:

```
~/.cache/uv/.../site-packages/mlx/lib/mlx.metallib
```

This metallib must be placed next to the binary at runtime. This is fragile:

- Python mlx version must be kept in sync with Swift mlx version
- The metallib is 102 MB -- adds significant disk overhead
- No official distribution mechanism for standalone CLI apps

**For production**: Either install Xcode or use `xcodebuild` to compile the metallib.

### 2. Dynamic Library Duplication (WARNING)

kokoro-ios declares `type: .dynamic` for its library product. Both `libKokoroSwift.dylib` and `libMisakiSwift.dylib` statically link MLX, causing ~100 ObjC class duplication warnings at runtime. This works now but could cause "mysterious crashes" per Apple's warning. The fix would be to patch kokoro-ios to use static linking.

### 3. Warmup Latency

First inference takes 4.38s due to Metal shader JIT compilation. Subsequent calls are 1.1-1.5s. This is acceptable for TTS (first message has a delay, rest are fast), but worse than sherpa-onnx which has no JIT warmup.

### 4. Model Size (327 MB vs 129 MB)

The bf16 model is 2.5x larger than the sherpa-onnx int8 model. An int8 quantized MLX model would reduce this, but kokoro-ios doesn't appear to support int8 quantized safetensors yet.

### 5. English-Only G2P

MisakiSwift only supports English (US and GB). The sherpa-onnx multi-lang model supports additional languages. Not a concern for the current use case (English TTS sessions) but limits future expansion.

## Word Timestamp Architecture (Key Finding)

kokoro-ios provides word timestamps **natively** through `TimestampPredictor`, which maps the duration model's per-phoneme predictions to word boundaries via `MToken.start_ts` / `MToken.end_ts`. This is a significant advantage over sherpa-onnx, where we had to patch 50 lines of C++ code to extract duration tensors.

The `MToken` class also provides:

- `text`: Original word text
- `phonemes`: IPA phoneme representation
- `start_ts` / `end_ts`: Word timing in seconds
- `tag`: NLTag (part-of-speech)
- `whitespace`: Trailing whitespace

This is exactly what the karaoke subtitle system needs.

## Verdict

**kokoro-ios is a viable replacement for sherpa-onnx** with significant advantages for the karaoke subtitle use case:

**Advantages:**

- Native word timestamps (no C++ patching)
- Faster RTF on GPU (0.096 vs 0.15-0.20)
- Pure Swift stack (no C interop, no static lib management)
- Built-in G2P (MisakiSwift, no espeak-ng dependency)
- Slightly lower peak RSS

**Disadvantages:**

- Requires Xcode or metallib workaround for CLI builds
- 2.5x larger model file (327 MB vs 129 MB)
- 102 MB metallib required at runtime
- Dynamic library duplication warnings
- 4.4s first-inference warmup (Metal JIT)
- English only

**Recommendation: ADOPT with caveats.** The native word timestamps and pure Swift stack outweigh the disk size and build complexity issues. The metallib issue is solvable by adding Xcode to the build environment or using `xcodebuild`. The model size increase (198 MB) is acceptable for a launchd service on desktop.

## Reproduction

```bash
mkdir -p ~/tmp/kokoro-mlx-spike && cd ~/tmp/kokoro-mlx-spike
# Package.swift and Sources/ as committed in this spike
swift package resolve
swift build -c release
# Copy mlx.metallib next to binary
cp $(python3 -c "import mlx; print(mlx.__file__.replace('__init__.py','lib/mlx.metallib'))") .build/arm64-apple-macosx/release/
.build/release/kokoro-mlx-spike
```
