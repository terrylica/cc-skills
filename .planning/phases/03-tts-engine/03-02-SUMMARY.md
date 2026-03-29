---
phase: 03-tts-engine
plan: 02
subsystem: tts
tags: [tts, karaoke, word-timing, sherpa-onnx]

requires:
  - phase: 03-tts-engine
    provides: TTSEngine with synthesis capability (plan 01)
provides:
  - Word-level timestamp extraction from duration tensor
  - TTS-driven karaoke replacing demo mode
affects: [all-downstream-phases]

tech-stack:
  added: []
  patterns: [word-timing-extraction, tts-karaoke-sync]

key-files:
  created: []
  modified:
    - plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift

key-decisions:
  - "Word timestamps extracted from sherpa-onnx duration tensor with accumulated onset tracking"
  - "Karaoke highlighting driven by real TTS word timings, replacing hardcoded 200ms demo"

requirements-completed: [TTS-06, TTS-07]

one-liner: "Word-level timestamp extraction from duration tensor with TTS-driven karaoke replacing demo mode"

self-check: PASSED
---

# Plan 03-02 Summary: Word Timestamps + TTS Karaoke

**Status:** Retroactive summary — plan executed during early v4.5.0 development, summary created during v4.9.0 milestone closure.

## What Was Built

Word-level timestamps extracted from the sherpa-onnx duration tensor, wired into SubtitlePanel for real-time karaoke highlighting synchronized with TTS audio playback. Replaced the hardcoded 200ms/word demo mode with actual speech-synchronized word timing.

The TTS word timing pipeline has since been significantly refactored through subsequent phases (Phase 17: Streaming, Phase 19: Actor Migration, Phase 25-26: Python TTS delegation with native MToken onsets).
