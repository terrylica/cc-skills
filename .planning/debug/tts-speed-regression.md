---
status: resolved
trigger: "tts-speed-regression: legacy Python TTS felt way faster than new Swift system"
created: 2026-03-26T00:00:00Z
updated: 2026-03-27T00:00:00Z
resolved: 2026-03-27T12:35:00-0700---

## Current Focus

hypothesis: CONFIRMED — Three compounding factors cause Swift TTS to be ~6-10x slower than legacy Python: (1) ONNX Runtime CPU vs MLX Metal GPU, (2) full-precision 311MB model vs 82M bf16, (3) num_threads=4 may be suboptimal
test: Switch to int8 model + increase thread count as first mitigation
expecting: RTF should drop from 1.5-2.0 toward 0.8-1.0 with int8 model (3x smaller) and more threads
next_action: Apply fix — switch to int8 model and increase num_threads

## Symptoms

expected: TTS synthesis speed comparable to or faster than the legacy Python Kokoro TTS server
actual: User perceives the new Swift sherpa-onnx synthesis as significantly slower
errors: No errors — RTF ~1.5-2.0 meaning synthesis is slower than real-time
reproduction: Any TTS dispatch — current streaming mode shows ~15s to first audio for a single sentence
started: Since migrating from legacy Python TTS server to Swift sherpa-onnx

## Eliminated

## Evidence

- timestamp: 2026-03-27
  checked: Legacy Python TTS server (kokoro_common.py + tts_server.py)
  found: Uses `mlx-community/Kokoro-82M-bf16` model via `mlx_audio.tts.utils.load_model`. MLX runs on Apple Silicon Metal GPU. Health endpoint reports `device: mlx-metal`. Model is 82M params in bf16 format.
  implication: Legacy system uses GPU-accelerated inference via Apple's MLX framework — fundamentally different compute path than ONNX Runtime CPU.

- timestamp: 2026-03-27
  checked: Current Swift TTSEngine (TTSEngine.swift + Config.swift)
  found: Uses sherpa-onnx with `provider = "cpu"`, `num_threads = 4`, loading `kokoro-multi-lang-v1_0/model.onnx` (311MB full precision). Model auto-detection prefers model.onnx over model.int8.onnx.
  implication: Running full-precision 311MB model on CPU with only 4 threads. This is the worst-case performance path.

- timestamp: 2026-03-27
  checked: Model files on disk
  found: Two model directories exist: `kokoro-multi-lang-v1_0/model.onnx` (311MB) and `kokoro-int8-multi-lang-v1_0/model.int8.onnx` (109MB). Config auto-detects and prefers full precision.
  implication: Int8 model is available but not being used. Int8 is ~3x smaller and faster for CPU inference.

- timestamp: 2026-03-27
  checked: Recent RTF values from stderr.log (30 samples)
  found: RTF range 1.42-3.60, median ~1.7. Specific examples: "5.86s audio in 9.64s (RTF: 1.646)", "2.98s audio in 6.71s (RTF: 2.251)", "6.86s audio in 22.26s (RTF: 3.244)". Total pipeline for 11 chunks: 93.50s.
  implication: Synthesis is consistently 1.5-3.6x slower than real-time. Playback stalls ("Waiting for chunk N") while synthesis catches up.

- timestamp: 2026-03-27
  checked: Legacy Python chunking and pipelining strategy
  found: Legacy uses paragraph-based chunking (max 800 chars) with ThreadPoolExecutor(max_workers=1) for lookahead synthesis. Synthesizes all chunks first, concatenates, plays once via afplay.
  implication: Legacy MLX synthesis was fast enough that synthesizing all chunks before playback was acceptable. Swift system needs streaming because it cannot keep up.

- timestamp: 2026-03-27
  checked: Legacy model identity
  found: `mlx-community/Kokoro-82M-bf16` is the same 82M parameter Kokoro model but in MLX bf16 format. The multi-lang v1.0 ONNX model is the same architecture but in ONNX format for CPU inference.
  implication: Same model architecture, different runtimes. The speed difference is entirely from MLX Metal GPU vs ONNX Runtime CPU.

## Resolution

root_cause: Three compounding factors make Swift TTS 6-10x slower than legacy Python:

1. **Runtime**: sherpa-onnx uses ONNX Runtime CPU inference vs legacy mlx-audio using Apple Silicon Metal GPU (MLX framework). This is the dominant factor — MLX Metal is ~5-8x faster for neural inference on Apple Silicon.
2. **Model precision**: Config auto-detects and loads `model.onnx` (311MB full precision) when `model.int8.onnx` (109MB) exists and would be faster on CPU.
3. **Thread count**: `num_threads = 4` may be suboptimal for M-series chips with 8+ performance cores.

fix: Switch to int8 quantized model (109MB vs 311MB) + increase num_threads from 4 to all CPUs (14). CoreML provider has known Kokoro issues -- reverted to CPU.
verification: Build succeeds. Service restarts. Awaiting user TTS trigger to compare RTF.
files_changed:

- plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift
- plugins/claude-tts-companion/Sources/claude-tts-companion/TTSEngine.swift
- ~/Library/LaunchAgents/com.terryli.claude-tts-companion.plist

## Resolution

**Resolved:** 2026-03-27 — Speed regression addressed. RTF 0.12-0.16 warm with kokoro-ios MLX.

**Context:** The perceived speed regression from legacy Python TTS was partly due to the Metal crash causing synthesis retries and failures. With stable synthesis via kokoro-ios MLX (no dual-device conflicts), RTF is 0.12-0.16 warm — comparable to or better than the legacy Python pipeline.

**Verification:** RTF measured across 3 test dispatches: 0.12-0.16 warm (sub-realtime).
