---
phase: quick
plan: 260327-d2e
subsystem: tts
tags: [kokoro-ios, mlx-swift, metal-gpu, tts, karaoke-timestamps]

provides:
  - kokoro-ios MLX Metal GPU TTS backend replacing sherpa-onnx CPU backend
  - Native word timestamps via MToken.start_ts/end_ts for karaoke highlighting
  - Pure Swift TTS stack (no C interop, no static libs)
affects: [claude-tts-companion, deployment]

tech-stack:
  added:
    [
      kokoro-ios 1.0.11,
      mlx-swift 0.30.2,
      MLXUtilsLibrary 0.0.6,
      MisakiSwift 1.0.6,
    ]
  removed: [sherpa-onnx static libs, ONNX Runtime, CSherpaOnnx C module]
  patterns:
    [
      AVAudioFile WAV writing,
      MToken timestamp extraction,
      voice name string IDs,
    ]

key-files:
  modified:
    - plugins/claude-tts-companion/Package.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/TTSEngine.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/LanguageDetector.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/TelegramBot.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift
  deleted:
    - plugins/claude-tts-companion/Sources/CSherpaOnnx/ (entire directory)

decisions:
  - Pin kokoro-ios 1.0.11, mlx-swift 0.30.2, MLXUtilsLibrary 0.0.6 exact versions for compatibility (1.0.11 requires exact 0.30.2)
  - Voice names (string) replace speaker IDs (Int32) as the voice selection interface
  - Character-weighted timing fallback preserved when MToken timestamps are unavailable
  - Chinese text gracefully degrades to English voice with warning (kokoro-ios is English-only)

metrics:
  duration: 12min
  completed: 2026-03-27
  tasks: 3
  files_modified: 6
  files_deleted: 4
---

# Quick Task 260327-d2e: Replace sherpa-onnx with kokoro-ios MLX Summary

Kokoro-ios MLX Metal GPU TTS backend replacing sherpa-onnx CPU ONNX Runtime, with native word timestamps and pure Swift stack.

## What Changed

### Task 1: Package.swift + Config.swift (e6f331e9)

- Removed CSherpaOnnx target and all linker settings (-lsherpa-onnx, -lonnxruntime, -lc++)
- Added kokoro-ios, MLXUtilsLibrary, mlx-swift SPM dependencies (pinned exact versions)
- Bumped platform from macOS 14 to macOS 15 (required by kokoro-ios)
- Replaced sherpa-onnx model paths with MLX safetensors + voices.npz paths
- Added metallib path config, voice name config (af_heart default)

### Task 2: TTSEngine rewrite + caller updates (bbe10fa0)

- Replaced sherpa-onnx C API with KokoroTTS.generateAudio() for synthesis
- Native MToken.start_ts/end_ts timestamps replace character-weighted approximation
- WAV output via AVAudioFile (replaces SherpaOnnxWriteWave C function)
- Added voiceName parameter throughout: TTSEngine, LanguageDetector, TelegramBot
- Updated /health to report "Kokoro MLX (bf16)"
- Removed CSherpaOnnx import from main.swift

### Task 3: CSherpaOnnx cleanup (cfa3d898)

- Deleted Sources/CSherpaOnnx/ directory (empty.c, c-api.h, module.modulemap, shim.h)
- Verified no remaining sherpa-onnx code references (only comments mentioning legacy speaker IDs)
- Release build: 40MB binary, 102s build time

## Deployment

Installed to ~/.local/bin/ with required runtime files:

- `claude-tts-companion` (40MB binary)
- `libKokoroSwift.dylib` (27MB)
- `libMisakiSwift.dylib` (27MB)
- `mlx.metallib` (102MB, copied from Python mlx pip package)
- Model: ~/.local/share/kokoro/models/mlx/kokoro-v1_0.safetensors (312MB, symlinked)
- Voices: ~/.local/share/kokoro/models/mlx/voices.npz (510KB, symlinked)

Service restarted and confirmed running with "TTS backend: kokoro-ios MLX (bf16)" in logs.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Version pinning for kokoro-ios compatibility**

- **Found during:** Task 1 (package resolution) and Task 2 (build)
- **Issue:** kokoro-ios 1.0.10 (resolved with `from: "1.0.0"`) had missing MLXFast dependency. kokoro-ios 1.0.11 requires exact mlx-swift 0.30.2, conflicting with `from: "0.30.0"` which resolved to 0.31.1.
- **Fix:** Pinned all three packages to exact versions matching spike: kokoro-ios 1.0.11, mlx-swift 0.30.2, MLXUtilsLibrary 0.0.6
- **Files modified:** Package.swift
- **Commit:** bbe10fa0

**2. [Rule 3 - Blocking] main.swift CSherpaOnnx import removal**

- **Found during:** Task 2 (build)
- **Issue:** main.swift imported CSherpaOnnx and called SherpaOnnxGetVersionStr() for startup verification
- **Fix:** Removed import and replaced with kokoro-ios MLX backend log message
- **Files modified:** main.swift
- **Commit:** bbe10fa0

## Known Issues

1. **ObjC class duplication warnings** -- kokoro-ios declares `type: .dynamic` for KokoroSwift and MisakiSwift, both statically link MLX/MLXUtilsLibrary/ZIPFoundation, causing ~40 class duplication warnings at runtime. Functional but could cause "mysterious crashes" per Apple. Fix requires patching kokoro-ios upstream to use static linking.

2. **metallib sourcing** -- The mlx.metallib (102MB) was copied from the spike's build, which sourced it from the Python mlx pip package. For production, either install Xcode or maintain a pinned Python mlx version to keep the metallib in sync with mlx-swift 0.30.2.

3. **First-inference warmup** -- Metal shader JIT compilation adds ~4.4s to the first synthesis call. Subsequent calls are 1.1-1.5s. Acceptable for a background launchd service.

## Known Stubs

None -- all synthesis paths are wired to kokoro-ios with character-weighted fallback.

## Self-Check: PASSED
