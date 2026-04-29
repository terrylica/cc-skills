# Phase 32: Audio Device Resilience - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-29
**Phase:** 32-audio-device-resilience
**Areas discussed:** Recovery strategy, Health check design, Dependency choice, Debounce & timing

---

## Approach Selection

| Option                       | Description                                                                                  | Selected |
| ---------------------------- | -------------------------------------------------------------------------------------------- | -------- |
| Accept all (Recommended)     | Full engine teardown+rebuild, raw CoreAudio HAL, 30s health check, 200ms debounce, telemetry | ✓        |
| Discuss individual decisions | Walk through each decision one at a time                                                     |          |
| Add constraints              | Additional requirements beyond research                                                      |          |

**User's choice:** Accept all recommended decisions from web research
**Notes:** User specifically requested "anti-fragile" approach backed by web research rather than interactive discussion. All 4 gray areas were selected with "not discuss but search web for best practices that are anti-fragile" annotation.

---

## Web Research Conducted

### Sources Consulted

1. Chris Liscio blog posts on AVAudioEngine aggregate device problems
2. AudioKit source code (AudioEngine.swift) — device change & rebuildGraph() patterns
3. AudioKit Issues #2130, #2384 — community experience with device switching
4. SimplyCoreAudio GitHub — found to be archived (March 2024)
5. Nonstrict.eu — audio capture gap handling on macOS
6. Apple Developer Forums — AVAudioEngine device handling threads

### Key Finding: SimplyCoreAudio Archived

SimplyCoreAudio (the dependency suggested in the issue) is read-only since March 2024. Decision: use raw CoreAudio HAL API instead (zero new dependencies, ~30 lines).

### Key Finding: Light Restart Insufficient

Current code only stops player node and calls engine.start(). AudioKit's rebuildGraph() pattern and community consensus confirm full teardown+rebuild is the only reliable recovery.

---

## Claude's Discretion

- Internal code organization (helper methods, extensions)
- NSLock usage patterns for thread safety during rebuild
- Whether CoreAudio HAL listener goes in separate file or inline
- DispatchSourceTimer scheduling details for health check

## Deferred Ideas

None — discussion stayed within phase scope
