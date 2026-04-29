---
phase: 32
slug: audio-device-resilience
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-29
---

# Phase 32 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property               | Value                                                |
| ---------------------- | ---------------------------------------------------- | --------- |
| **Framework**          | swift test (XCTest via SwiftPM)                      |
| **Config file**        | `plugins/claude-tts-companion/Package.swift`         |
| **Quick run command**  | `cd plugins/claude-tts-companion && swift build 2>&1 | tail -5`  |
| **Full suite command** | `cd plugins/claude-tts-companion && swift build 2>&1 | tail -20` |
| **Estimated runtime**  | ~30 seconds                                          |

---

## Sampling Rate

- **After every task commit:** Run `cd plugins/claude-tts-companion && swift build 2>&1 | tail -5`
- **After every plan wave:** Run `cd plugins/claude-tts-companion && swift build 2>&1 | tail -20`
- **Before `/gsd:verify-work`:** Full build must succeed
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID  | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status     |
| -------- | ---- | ---- | ----------- | --------- | ----------------- | ----------- | ---------- |
| 32-01-01 | 01   | 1    | D-01        | build     | `swift build`     | N/A         | ⬜ pending |
| 32-01-02 | 01   | 1    | D-02        | build     | `swift build`     | N/A         | ⬜ pending |
| 32-01-03 | 01   | 1    | D-04        | build     | `swift build`     | N/A         | ⬜ pending |
| 32-01-04 | 01   | 1    | D-05        | build     | `swift build`     | N/A         | ⬜ pending |

_Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky_

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No new test framework needed — swift build is the primary validation.

---

## Manual-Only Verifications

| Behavior                            | Requirement | Why Manual                         | Test Instructions                                                                                                          |
| ----------------------------------- | ----------- | ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Audio continues after BT disconnect | D-01, D-02  | Requires physical Bluetooth device | 1. Play TTS audio 2. Disconnect BT headphones 3. Verify audio resumes on speakers within 5s                                |
| Health check detects stale device   | D-04        | Requires device mismatch state     | 1. Start companion 2. Switch audio output in System Settings 3. Wait 30s 4. Check logs for health check mismatch + rebuild |
| Debounce prevents rebuild storms    | D-05        | Requires rapid device switching    | 1. Rapidly toggle BT on/off 3 times 2. Check logs show max 1 rebuild per 5s cooldown                                       |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
