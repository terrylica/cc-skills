# Python TTS Server Delegation Summary

**One-liner:** TTSEngine delegates MLX synthesis to Python Kokoro server (localhost:8779) via HTTP, eliminating IOAccelerator memory leaks in the Swift binary.

## What Changed

TTSEngine was rewritten from a direct kokoro-ios MLX caller to an HTTP client that delegates synthesis to the existing Python Kokoro TTS server at `http://127.0.0.1:8779/v1/audio/speech`.

### Key Changes

| File                 | Change                                                                                                                                                                                                                                                                                                                                                      |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `TTSEngine.swift`    | Replaced kokoro-ios `KokoroTTS.generateAudio()` calls with `URLSession` HTTP POST to Python server. Removed `KokoroSwift`, `MLX`, `MLXUtilsLibrary` imports. Removed model loading (`ensureModelLoaded`, `voiceForName`, `ttsInstance`, `voicesDict`). Added `callPythonServer()`, `wavDuration()`, `extractSamplesFromWav()`, `checkPythonServerHealth()`. |
| `Config.swift`       | Added `pythonTTSServerURL` (env: `KOKORO_TTS_SERVER_URL`, default: `http://127.0.0.1:8779`), `pythonTTSRequestTimeout` (120s), `pythonTTSHealthCheckTimeout` (5s).                                                                                                                                                                                          |
| `TTSError.swift`     | Added `pythonServerUnavailable(url:)` and `pythonServerError(statusCode:message:)` cases.                                                                                                                                                                                                                                                                   |
| `CompanionApp.swift` | Updated startup log message. Added async health check for Python server on startup.                                                                                                                                                                                                                                                                         |
| `TelegramBot.swift`  | Removed `isDisabledDueToMissingModel` check (no longer applicable). Circuit breaker check remains.                                                                                                                                                                                                                                                          |

### What Was Kept Unchanged

- **Package.swift**: kokoro-ios, MLX, MLXUtilsLibrary dependencies remain (WordTimingAligner + tests still use MToken types)
- **WordTimingAligner.swift**: Untouched -- MToken alignment code stays for future use and existing tests
- **CJK synthesis**: Still uses sherpa-onnx directly (no Python server for CJK)
- **Public API surface**: All callers (TelegramBot, HTTPControlServer, SubtitleSyncDriver, CompanionApp) work without changes
- **Circuit breaker**: Same 3-failure / 5-min cooldown logic
- **Synthesis counter**: Still tracked for diagnostics; threshold raised to 500 (irrelevant since Swift binary no longer accumulates GPU memory)

## Decisions Made

1. **Int16 WAV handling**: Python server (soundfile) writes int16 PCM WAV by default. `extractSamplesFromWav()` reads `bitsPerSample` from WAV header and converts int16 to float32 (normalize by 32768.0). Also handles float32 WAV for forward compatibility.

2. **Character-weighted fallback only**: Python server doesn't return MToken timestamp data, so all word timings use the existing character-weighted fallback (`WordTimingAligner.extractWordTimings`). This means no native onset times (`wordOnsets` is always nil). Karaoke highlighting still works but without sub-word precision.

3. **Soft health check**: Python server health check on startup is non-blocking and logs a warning if unreachable. TTS is not disabled -- the server may come up later, and the circuit breaker handles repeated failures gracefully.

4. **Restart threshold raised to 500**: Since the Swift binary no longer runs MLX GPU work, there's no IOAccelerator memory leak in this process. The threshold is effectively a no-op but kept for API compatibility with MemoryLifecycle.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Int16 WAV format mismatch**

- **Found during:** Implementation
- **Issue:** Plan assumed Python server returns float32 WAV, but soundfile writes int16 PCM WAV by default
- **Fix:** `extractSamplesFromWav()` reads bitsPerSample from WAV header and handles both int16 and float32
- **Files modified:** TTSEngine.swift

**2. [Rule 1 - Bug] isDisabledDueToMissingModel reference in TelegramBot**

- **Found during:** Implementation
- **Issue:** TelegramBot.swift referenced `isDisabledDueToMissingModel` which was removed from TTSEngine
- **Fix:** Simplified to circuit breaker check only (Python server availability is transient, not permanent)
- **Files modified:** TelegramBot.swift

## Known Stubs

None -- all data paths are fully wired.

## Commit

| Hash       | Message                                                                    |
| ---------- | -------------------------------------------------------------------------- |
| `010cfe29` | feat(tts): delegate MLX synthesis to Python Kokoro server (localhost:8779) |
