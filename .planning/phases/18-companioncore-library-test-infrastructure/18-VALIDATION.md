---
phase: 18
slug: companioncore-library-test-infrastructure
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-28
---

# Phase 18 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property               | Value                                                         |
| ---------------------- | ------------------------------------------------------------- |
| **Framework**          | Swift Testing (swift-testing, shipped with Swift 6 toolchain) |
| **Config file**        | none — Wave 0 creates test target in Package.swift            |
| **Quick run command**  | `cd plugins/claude-tts-companion && swift test`               |
| **Full suite command** | `cd plugins/claude-tts-companion && swift test`               |
| **Estimated runtime**  | ~15 seconds (compilation-dominated)                           |

---

## Sampling Rate

- **After every task commit:** Run `cd plugins/claude-tts-companion && swift build`
- **After every plan wave:** Run `cd plugins/claude-tts-companion && swift test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID  | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status     |
| -------- | ---- | ---- | ----------- | --------- | ----------------- | ----------- | ---------- |
| 18-01-01 | 01   | 1    | ARCH-01     | build     | `swift build`     | ❌ W0       | ⬜ pending |
| 18-01-02 | 01   | 1    | ARCH-01     | build     | `swift build`     | ❌ W0       | ⬜ pending |
| 18-02-01 | 02   | 1    | TEST-01     | unit      | `swift test`      | ❌ W0       | ⬜ pending |

_Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky_

---

## Wave 0 Requirements

- [ ] `Tests/CompanionCoreTests/` — test target directory
- [ ] `Package.swift` — CompanionCore library target + CompanionCoreTests test target
- [ ] Swift Testing framework — built into Swift 6 toolchain, no install needed

_Existing infrastructure: SwiftPM already configured. Wave 0 adds library + test targets._

---

## Manual-Only Verifications

| Behavior                                  | Requirement | Why Manual      | Test Instructions                        |
| ----------------------------------------- | ----------- | --------------- | ---------------------------------------- |
| `@testable import CompanionCore` compiles | TEST-01     | Build-time only | `swift test` must compile without errors |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
