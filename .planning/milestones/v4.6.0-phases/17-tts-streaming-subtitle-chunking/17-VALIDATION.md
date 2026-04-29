---
phase: 17
slug: tts-streaming-subtitle-chunking
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-26
---

# Phase 17 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property               | Value                                           |
| ---------------------- | ----------------------------------------------- |
| **Framework**          | Manual testing via HTTP API + visual inspection |
| **Config file**        | none — swift binary, no test target yet         |
| **Quick run command**  | `swift build -c debug`                          |
| **Full suite command** | Build + run + manual TTS trigger test           |
| **Estimated runtime**  | ~30 seconds (build)                             |

---

## Sampling Rate

- **After every task commit:** Run `swift build -c debug`
- **After every plan wave:** Full build + manual TTS trigger test
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID  | Plan | Wave | Requirement          | Test Type | Automated Command      | File Exists | Status     |
| -------- | ---- | ---- | -------------------- | --------- | ---------------------- | ----------- | ---------- |
| 17-01-01 | 01   | 1    | STREAM-02            | build     | `swift build -c debug` | ❌ W0       | ⬜ pending |
| 17-01-02 | 01   | 1    | STREAM-02            | build     | `swift build -c debug` | ❌ W0       | ⬜ pending |
| 17-02-01 | 02   | 1    | STREAM-01, STREAM-03 | manual    | TTS trigger + visual   | N/A         | ⬜ pending |

_Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky_

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No automated test infrastructure for this UI-heavy phase — all validation is visual/manual via the running binary.

---

## Manual-Only Verifications

| Behavior                      | Requirement | Why Manual                             | Test Instructions                                 |
| ----------------------------- | ----------- | -------------------------------------- | ------------------------------------------------- |
| First audio within 5s         | STREAM-01   | Timing is end-to-end from notification | Trigger TTS dispatch, measure time to first audio |
| Pages advance one at a time   | STREAM-02   | Visual UI behavior                     | Trigger TTS with long text, observe page flips    |
| Karaoke highlighting per page | STREAM-03   | Visual word-by-word highlighting       | Observe gold word advancement within 2-line pages |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
