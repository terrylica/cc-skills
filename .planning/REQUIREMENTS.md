<!-- # SSoT-OK -->

# Requirements: claude-tts-companion v4.8.0

**Defined:** 2026-03-28
**Core Value:** See what Claude says, anywhere — real-time karaoke subtitles synced with TTS playback
**Milestone:** v4.8.0 Python MLX TTS Consolidation

## Decision Record

> These decisions were made after benchmarking 4 alternatives on 2026-03-28.
> Evidence files in `plugins/claude-tts-companion/.planning/debug/benchmark-*.md`

| Decision                          | Rationale                                                                                          | Evidence                                             |
| --------------------------------- | -------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| Python MLX over Swift MLX         | mlx-swift IOAccelerator leak +2.3GB/call by design (ml-explore/mlx #1086). Python MLX = +4MB/call. | vmmap measurements, benchmark-python-mlx-baseline.md |
| Python MLX over sherpa-onnx       | Kokoro ONNX `durations` field is NULL — no word timestamps without C++ patching                    | benchmark-sherpa-onnx.md                             |
| Python MLX over FluidAudio CoreML | No word-level timestamp API. CoreML compiled graphs are opaque.                                    | benchmark-fluidaudio.md                              |
| Python MLX over Rust/candle       | No Kokoro implementation exists. burn-mlx uses MLX = same leak.                                    | tts-runtime-alternatives-research.md                 |
| Word timing non-negotiable        | Karaoke subtitle highlighting requires per-word onset/duration data                                | User requirement                                     |

## v4.8.0 Requirements

### Python TTS Server

- [ ] **PTS-01**: Python MLX server exposes `/v1/audio/speech-with-timestamps` endpoint returning JSON with base64 WAV bytes and per-word onset/duration arrays
- [ ] **PTS-02**: Word timestamps derived from mlx-audio MToken.start_ts/end_ts (native duration model output, not character-weighted fallback)
- [ ] **PTS-03**: Python server launchd plist starts automatically before claude-tts-companion (service dependency ordering)

### Swift Integration

- [ ] **SWI-01**: TTSEngine parses word timestamps from Python server JSON response and passes native onsets to SubtitleSyncDriver
- [ ] **SWI-02**: Karaoke subtitle highlighting uses Python-derived word onsets with zero accumulated drift
- [ ] **SWI-03**: `tts_kokoro.sh` CLI script works end-to-end via Swift companion → Python server chain

### Dependency Cleanup

- [ ] **DEP-01**: kokoro-ios removed from Package.swift (no KokoroSwift import anywhere in CompanionCore)
- [ ] **DEP-02**: mlx-swift removed from Package.swift (no MLX import anywhere in CompanionCore)
- [ ] **DEP-03**: MLXUtilsLibrary removed from Package.swift
- [ ] **DEP-04**: `swift build` succeeds with zero MLX-related symbols or frameworks linked
- [ ] **DEP-05**: Binary size under 20 MB (down from current ~25+ MB with MLX dependencies)

### Memory Lifecycle Cleanup

- [ ] **MEM-01**: Synthesis-count restart removed from TTSEngine (no IOAccelerator leak in Swift process)
- [ ] **MEM-02**: MemoryLifecycle.swift removed or simplified (checkMemoryLifecycleRestart no longer needed)
- [ ] **MEM-03**: Swift companion RSS stays under 100 MB across 50+ consecutive TTS calls

## Future Requirements

### Deferred

- sherpa-onnx word timestamp C++ patch — if Python MLX server becomes unviable, patch sherpa-onnx Kokoro impl to populate durations field
- FluidAudio CoreML integration — if upstream adds word-level timestamp API

## Out of Scope

- Replacing Python with Rust/C++ TTS runtime — no Kokoro implementation with word timestamps exists (researched 2026-03-28)
- CJK karaoke word timing — tokenization is a separate problem (per v4.7.0 decision)
- Rewriting Python MLX server in Swift — mlx-swift IOAccelerator leak makes this impossible (by design, ml-explore/mlx #1086)
- CoreML Kokoro conversion — opaque compiled graphs prevent word timestamp extraction

## Traceability

| Requirement | Phase | Status  |
| ----------- | ----- | ------- |
| PTS-01      | 25    | Pending |
| PTS-02      | 25    | Pending |
| PTS-03      | 25    | Pending |
| SWI-01      | 26    | Pending |
| SWI-02      | 26    | Pending |
| SWI-03      | 26    | Pending |
| DEP-01      | 27    | Pending |
| DEP-02      | 27    | Pending |
| DEP-03      | 27    | Pending |
| DEP-04      | 27    | Pending |
| DEP-05      | 27    | Pending |
| MEM-01      | 28    | Pending |
| MEM-02      | 28    | Pending |
| MEM-03      | 28    | Pending |
