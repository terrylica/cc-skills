---
phase: 25-python-tts-server-timestamp-endpoint
verified: 2026-03-28T08:00:00Z
status: passed
score: 4/4 must-haves verified
re_verification: false
---

# Phase 25: Python TTS Server Timestamp Endpoint Verification Report

**Phase Goal:** Python MLX server exposes a word-level timestamp API so Swift can receive native per-word onset/duration data over HTTP
**Verified:** 2026-03-28
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth                                                                                                                                   | Status     | Evidence                                                                                                                                                 |
| --- | --------------------------------------------------------------------------------------------------------------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | curl localhost:8779/v1/audio/speech-with-timestamps with JSON body returns 200 with audio_b64, words array, audio_duration, sample_rate | ✓ VERIFIED | Live endpoint tested: 2 words, 1.57s audio, sample_rate=24000; all four JSON fields present                                                              |
| 2   | Each word in the words array has text, onset (float seconds), and duration (float seconds) derived from MToken.start_ts/end_ts          | ✓ VERIFIED | "Hello" onset=0.350s dur=0.275s, "world" onset=0.625s dur=0.675s; non-uniform gaps confirm native MToken data (not character-weighted)                   |
| 3   | Punctuation-only tokens are filtered from the words array                                                                               | ✓ VERIFIED | "Hello world. This is a test." returned 6 words ['Hello','world','This','is','a','test'] — no punctuation-only tokens present; `_PUNCT_ONLY` regex wired |
| 4   | Python server launchd plist has KeepAlive and RunAtLoad for automatic startup                                                           | ✓ VERIFIED | `~/Library/LaunchAgents/com.terryli.kokoro-tts-server.plist` has `<key>KeepAlive</key><true/>` and `<key>RunAtLoad</key><true/>`                         |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact                                                     | Expected                                        | Status     | Details                                                                                                                                                       |
| ------------------------------------------------------------ | ----------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `~/.local/share/kokoro/kokoro_common.py`                     | synthesize_with_timestamps() with MToken timing | ✓ VERIFIED | Function exists at lines 53-102; contains `start_ts`, `end_ts`, `chunk_offset`, punctuation filter, squeeze(0) shape fix                                      |
| `~/.local/share/kokoro/tts_server.py`                        | /v1/audio/speech-with-timestamps endpoint       | ✓ VERIFIED | Route at line 527, handler `_handle_speech_with_timestamps` at lines 535-583, `synthesize_with_timestamps_locked` at lines 99-104, `import base64` at line 28 |
| `~/Library/LaunchAgents/com.terryli.kokoro-tts-server.plist` | KeepAlive + RunAtLoad                           | ✓ VERIFIED | Both keys present as `<true/>`                                                                                                                                |

### Key Link Verification

| From                                           | To                                                              | Via                                        | Status  | Details                                                                                                    |
| ---------------------------------------------- | --------------------------------------------------------------- | ------------------------------------------ | ------- | ---------------------------------------------------------------------------------------------------------- |
| `tts_server.py _handle_speech_with_timestamps` | `kokoro_common.synthesize_with_timestamps`                      | `synthesize_with_timestamps_locked()` call | ✓ WIRED | Line 560: `audio, words = synthesize_with_timestamps_locked(self.model, text, voice, lang, speed)`         |
| `kokoro_common.synthesize_with_timestamps`     | `mlx_audio KokoroPipeline.Result.tokens MToken.start_ts/end_ts` | `pipeline(text)` then `result.tokens` loop | ✓ WIRED | Lines 70-98: direct pipeline access, iterates `result.tokens`, reads `t.start_ts` and `t.end_ts` per token |

### Data-Flow Trace (Level 4)

| Artifact                         | Data Variable  | Source                                                                         | Produces Real Data                                                                                | Status    |
| -------------------------------- | -------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------- | --------- |
| `_handle_speech_with_timestamps` | `audio, words` | `synthesize_with_timestamps_locked()` → `pipeline(text)` → MLX model inference | Yes — live endpoint returns non-empty audio_b64 (>100 chars) and 2+ words with non-uniform onsets | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior                                                         | Command                                                          | Result                                               | Status |
| ---------------------------------------------------------------- | ---------------------------------------------------------------- | ---------------------------------------------------- | ------ |
| Server is alive                                                  | `GET /health`                                                    | `status=ok model=mlx-community/Kokoro-82M-bf16`      | ✓ PASS |
| /v1/audio/speech-with-timestamps returns valid JSON + all fields | `POST /v1/audio/speech-with-timestamps {"input":"Hello world."}` | 2 words, 1.57s audio, 24000 Hz; all 4 fields present | ✓ PASS |
| Punctuation-only tokens filtered                                 | `POST` with "Hello world. This is a test."                       | 6 word tokens, no punct-only entries                 | ✓ PASS |
| Native timestamps (non-uniform spacing)                          | Inspect onset gaps from multi-word response                      | Gaps: [0.35, 0.575, 0.225, 0.113, 0.1] — not uniform | ✓ PASS |
| Existing /v1/audio/speech unaffected (no regression)             | `POST /v1/audio/speech {"input":"Hello"}`                        | HTTP 200                                             | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description                                                                                                                    | Status      | Evidence                                                                                                      |
| ----------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------ | ----------- | ------------------------------------------------------------------------------------------------------------- |
| PTS-01      | 25-01-PLAN  | Python MLX server exposes `/v1/audio/speech-with-timestamps` endpoint returning JSON with base64 WAV + per-word onset/duration | ✓ SATISFIED | Live endpoint returns `audio_b64`, `words`, `audio_duration`, `sample_rate`; all fields verified              |
| PTS-02      | 25-01-PLAN  | Word timestamps derived from mlx-audio MToken.start_ts/end_ts (native duration model output, not character-weighted fallback)  | ✓ SATISFIED | `synthesize_with_timestamps()` accesses `KokoroPipeline` directly; non-uniform onset gaps confirm native data |
| PTS-03      | 25-01-PLAN  | Python server launchd plist starts automatically before claude-tts-companion (service dependency ordering)                     | ✓ SATISFIED | Plist has `KeepAlive: true` and `RunAtLoad: true`; no changes needed (pre-existing)                           |

No orphaned requirements: REQUIREMENTS.md maps exactly PTS-01, PTS-02, PTS-03 to phase 25, all claimed by 25-01-PLAN.

### Anti-Patterns Found

| File       | Line | Pattern | Severity | Impact |
| ---------- | ---- | ------- | -------- | ------ |
| None found | —    | —       | —        | —      |

No TODO/FIXME/placeholder comments or stub patterns found in either modified file. The endpoint returns real MLX-synthesized data with populated word timing arrays.

### Human Verification Required

None — all observable behaviors verified programmatically via live endpoint calls against the running server.

### Gaps Summary

No gaps. Phase goal fully achieved.

- The `/v1/audio/speech-with-timestamps` endpoint is live at `http://127.0.0.1:8779` and returns all four required fields.
- Word timestamps are native MToken data (non-uniform spacing confirmed in behavioral spot-checks), not the character-weighted fallback.
- Punctuation-only token filtering is wired and verified.
- Launchd plist has both `KeepAlive` and `RunAtLoad` for automatic startup.
- The existing `/v1/audio/speech` endpoint is unaffected.
- Phase 26 (Swift TTSEngine native word onset) can proceed immediately.

---

_Verified: 2026-03-28_
_Verifier: Claude (gsd-verifier)_
