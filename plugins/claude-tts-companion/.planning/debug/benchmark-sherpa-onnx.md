# Benchmark: sherpa-onnx Kokoro TTS

Date: 2026-03-27
Machine: MacBook Pro Apple Silicon (arm64), macOS 14+
sherpa-onnx: v1.12.33 (static libs, CPU-only inference via ONNX Runtime)

## Model

- Path: `~/.local/share/kokoro/models/kokoro-int8-multi-lang-v1_0/`
- Model file: `model.int8.onnx` (109 MB)
- Total dir size: 351 MB (includes lexicons, espeak-ng-data, dict, FST files)
- Format: ONNX int8 quantized (kokoro-int8-multi-lang v1.0)
- Sample rate: 24000 Hz
- Speakers: 53
- Config: 2 threads, max_num_sentences=1

## Latency

| Text       | Chars | Audio Duration | Synthesis Time | RTF   |
| ---------- | ----- | -------------- | -------------- | ----- |
| Short EN   | 64    | 3.52s          | 2.12s          | 0.603 |
| Medium EN  | 186   | 10.64s         | 6.03s          | 0.566 |
| Long EN    | 347   | 17.67s         | 10.14s         | 0.574 |
| Short ZH   | 16    | 3.88s          | 2.92s          | 0.752 |
| Medium ZH  | 46    | 10.19s         | 6.45s          | 0.633 |
| Warm Short | 64    | 3.52s          | 2.06s          | 0.584 |

- Cold start (model load): 0.937s
- Warm vs cold RTF difference: negligible (0.584 vs 0.603)
- Chinese synthesis ~15-30% slower RTF than English

### vs Python MLX Baseline

| Metric          | Python MLX (bf16, GPU) | sherpa-onnx (int8, CPU) | Ratio       |
| --------------- | ---------------------- | ----------------------- | ----------- |
| Short text RTF  | 0.142                  | 0.603                   | 4.2x slower |
| Medium text RTF | 0.164                  | 0.566                   | 3.5x slower |
| Long text RTF   | 0.103                  | 0.574                   | 5.6x slower |

sherpa-onnx is 3.5-5.6x slower than Python MLX on GPU. Still real-time (RTF < 1.0) but with much less headroom.

## RAM

| Measurement                | Value                |
| -------------------------- | -------------------- |
| Before model load          | 30.0 MB              |
| After model load           | 570.1 MB             |
| After all synthesis        | 740.4 MB             |
| After model unload         | 740.8 MB             |
| Load delta                 | +540.1 MB            |
| Synthesis delta            | +170.3 MB            |
| Total delta                | +710.3 MB            |
| Memory reclaimed on unload | -0.4 MB (negligible) |

### vs Python MLX Baseline

| Metric          | Python MLX      | sherpa-onnx       |
| --------------- | --------------- | ----------------- |
| Idle RSS        | 552.5 MB        | 570.1 MB (loaded) |
| Synthesis delta | +10.1 MB        | +170.3 MB         |
| Peak            | 562.6 MB stable | 740.4 MB          |

**Critical finding**: sherpa-onnx does NOT reclaim memory on model unload. The C++ allocator retains freed pages. The 30-second idle timeout unload strategy (Config.sherpaOnnxIdleTimeoutSeconds) does not actually reduce RSS. Process restart is the only way to reclaim.

## Word Timing

- **durations field**: NULL for all Kokoro synthesis calls
- **Confirmed in source**: `offline-tts-kokoro-impl.h` only populates `sample_rate` and `samples` in `GeneratedAudio`. The `durations` field is never set.
- **C API struct** has `const float *durations` and `int32_t num_durations` fields, but Kokoro does not use them
- **Other models**: The durations field exists for potential use by other TTS backends (VITS, etc.), not Kokoro
- **Spike 16 approach** (referenced in CLAUDE.md): A ~50-line C++ patch to sherpa-onnx extracts word-level timestamps from the Kokoro duration model output. This is a custom fork modification, not upstream sherpa-onnx.
- **Alternative**: kokoro-ios (KokoroSwift) via MLX returns MToken objects with `start_ts`/`end_ts` for word timing

### Word timing options for karaoke

1. **Custom sherpa-onnx fork** (spike 16): Patch `offline-tts-kokoro-impl.h` to extract duration model intermediate output, accumulate per-phoneme durations, and map back to word boundaries. Populates the `durations` field.
2. **KokoroSwift/MLX path**: Use the MLX engine for English (which returns word timestamps natively), sherpa-onnx only for CJK fallback.
3. **Post-hoc alignment**: Run forced alignment (e.g., whisper) on the generated audio to recover word timestamps. Adds latency.

## Voice Quality

- Test WAV: `/tmp/sherpa-onnx-benchmark.wav` (Short EN, speaker ID 3, 24kHz mono)
- **English**: Natural prosody, clear pronunciation. Comparable to Python MLX baseline at speed=1.0. Slightly more robotic than MLX bf16 but acceptable for TTS consumption.
- **Chinese**: Good tone accuracy. Speaker ID 45 produces natural Mandarin.
- **int8 vs bf16**: Minor quality degradation from quantization, not perceptible in casual listening.

## Verdict

**Suitable for production CJK TTS? YES, with caveats.**

Strengths:

- Real-time synthesis (RTF 0.57-0.75, well under 1.0)
- Multi-language support (EN + ZH) in single model
- No GPU/Metal dependency (pure CPU via ONNX Runtime)
- Static linking, no dylib issues

Weaknesses:

- **No word timestamps** from upstream sherpa-onnx (blocks karaoke without custom fork or alternative approach)
- **3.5-5.6x slower** than Python MLX on GPU
- **740 MB peak RSS** with no reclaim on unload (vs 562 MB stable for MLX)
- Memory never returns to baseline without process restart

**Recommendation**: Use sherpa-onnx as the CJK-only fallback engine (current architecture). For English karaoke TTS with word timing, KokoroSwift/MLX is the better path since it provides native word timestamps and 3-5x faster synthesis via Metal GPU.
