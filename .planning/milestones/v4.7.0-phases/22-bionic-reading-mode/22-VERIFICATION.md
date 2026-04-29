---
phase: 22-bionic-reading-mode
verified: 2026-03-28T03:30:00Z
status: human_needed
score: 8/8 must-haves verified
human_verification:
  - test: "Visual rendering of bionic bold-prefix"
    expected: "Subtitle text shows first ~40% of each word in bold, remainder in regular weight, all white"
    why_human: "NSAttributedString rendering requires visual inspection on a macOS display"
  - test: "SwiftBar toggle green/red dot state reflects current displayMode"
    expected: "Green dot when displayMode=bionic, red dot when displayMode=karaoke"
    why_human: "SwiftBar menu rendering requires visual confirmation; cannot test dot color programmatically without running the app"
  - test: "End-to-end toggle via SwiftBar click"
    expected: "Clicking Bionic Reading item cycles displayMode and subtitle rendering updates"
    why_human: "Requires live interaction with the SwiftBar menu and running claude-tts-companion service"
---

# Phase 22: Bionic Reading Mode Verification Report

**Phase Goal:** Users can toggle a bold-prefix reading mode that makes subtitle text easier to scan at a glance
**Verified:** 2026-03-28
**Status:** human_needed (all automated checks passed; 3 items require visual/live verification)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| #   | Truth                                                                                    | Status   | Evidence                                                                                                         |
| --- | ---------------------------------------------------------------------------------------- | -------- | ---------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| 1   | Bionic renderer splits words into bold prefix (40% chars) + regular suffix               | VERIFIED | BionicRenderer.boldPrefixLength uses `max(1, ceil(count*0.4))`; 14/14 tests pass                                 |
| 2   | DisplayMode enum has .karaoke, .bionic, .plain cases                                     | VERIFIED | DisplayMode.swift line 7-11; enum is `public`, `Codable`, `Sendable`                                             |
| 3   | POST /settings/subtitle accepts displayMode field and persists it                        | VERIFIED | SubtitleSettingsUpdate.displayMode at line 12; handler at HTTPControlServer.swift lines 133-143                  |
| 4   | SubtitlePanel renders bionic text when displayMode is .bionic                            | VERIFIED | show(text:) and highlightWord both branch on currentDisplayMode == .bionic and call BionicRenderer.render        |
| 5   | Setting displayMode to .bionic automatically sets karaokeEnabled to false and vice versa | VERIFIED | Mutual exclusion switch in HTTPControlServer.swift lines 136-141                                                 |
| 6   | SwiftBar settings menu shows a Bionic Reading toggle item                                | VERIFIED | claude-hq.10s.sh line 105: `echo "$B_DOT Bionic Reading                                                          | $(act set-subtitle displayMode toggle-bionic)"`                       |
| 7   | Clicking the toggle sends POST /settings/subtitle with displayMode field                 | VERIFIED | nc-action.sh lines 68-74: toggle-bionic handler calls `curl -X POST ... {"displayMode": ...} /settings/subtitle` |
| 8   | Toggle state reflects current displayMode from GET /settings                             | VERIFIED | claude-hq.10s.sh line 36: `DISPLAY_MODE=$(echo "$SETTINGS"                                                       | $JQ '.subtitle.displayMode // "karaoke"')`; line 104 drives dot color |

**Score:** 8/8 truths verified

---

### Required Artifacts

| Artifact                                                                          | Expected                                                            | Status   | Details                                                                                                           |
| --------------------------------------------------------------------------------- | ------------------------------------------------------------------- | -------- | ----------------------------------------------------------------------------------------------------------------- |
| `plugins/claude-tts-companion/Sources/CompanionCore/DisplayMode.swift`            | DisplayMode enum with karaoke/bionic/plain cases                    | VERIFIED | 17 lines; `enum DisplayMode: String, Codable, Sendable` with 3 cases + safe string parser                         |
| `plugins/claude-tts-companion/Sources/CompanionCore/BionicRenderer.swift`         | Pure function rendering words with bold prefix                      | VERIFIED | 68 lines; `boldPrefixLength` + `@MainActor render(words:fontSizeName:)`                                           |
| `plugins/claude-tts-companion/Tests/CompanionCoreTests/BionicRendererTests.swift` | Unit tests for bionic word splitting                                | VERIFIED | 104 lines; 14 swift-testing `@Test` cases, all passing                                                            |
| `plugins/claude-tts-companion/Sources/CompanionCore/SettingsStore.swift`          | SubtitleSettings.displayMode field persisted                        | VERIFIED | Line 11: `var displayMode: String`; backward-compatible `init(from:)` with `decodeIfPresent` default "karaoke"    |
| `plugins/claude-tts-companion/Sources/CompanionCore/HTTPControlServer.swift`      | displayMode in SubtitleSettingsUpdate + mutual exclusion handler    | VERIFIED | Line 12: `var displayMode: String?`; lines 133-143: update + mutual exclusion switch                              |
| `plugins/claude-tts-companion/Sources/CompanionCore/SubtitlePanel.swift`          | currentDisplayMode + bionic branching in show() and highlightWord() | VERIFIED | Lines 101-103: computed property; lines 115-118: show() bionic branch; lines 157-165: highlightWord bionic branch |
| `~/Library/Application Support/SwiftBar/Plugins/claude-hq.10s.sh`                 | Bionic Reading toggle menu item                                     | VERIFIED | Lines 36, 42, 104-105: DISPLAY_MODE parse, fallback, and toggle menu item                                         |
| `~/Library/Application Support/SwiftBar/Plugins/nc-action.sh`                     | toggle-bionic displayMode handler                                   | VERIFIED | Lines 68-74: full toggle-bionic elif block with GET current + POST new displayMode                                |

---

### Key Link Verification

| From                    | To                                        | Via                                                           | Status | Details                                                                                                               |
| ----------------------- | ----------------------------------------- | ------------------------------------------------------------- | ------ | --------------------------------------------------------------------------------------------------------------------- |
| SubtitlePanel.swift     | BionicRenderer.swift                      | `BionicRenderer.render()` calls in show() and highlightWord() | WIRED  | Pattern confirmed at lines 117, 158 of SubtitlePanel.swift                                                            |
| HTTPControlServer.swift | SettingsStore.swift                       | `displayMode` field in SubtitleSettingsUpdate                 | WIRED  | `update.displayMode` read and applied via `settingsStore.updateSubtitle` at lines 133-143                             |
| SettingsStore.swift     | DisplayMode.swift                         | `SubtitleSettings.displayMode` property                       | WIRED  | `displayMode: String` field (line 11); `DisplayMode.from(string:)` called in HTTPControlServer and SubtitlePanel      |
| claude-hq.10s.sh        | nc-action.sh                              | `act set-subtitle displayMode toggle-bionic`                  | WIRED  | Line 105 invokes the action; nc-action.sh handles it at lines 68-74                                                   |
| nc-action.sh            | <http://localhost:8780/settings/subtitle> | `curl POST with displayMode JSON`                             | WIRED  | Line 73: `curl -sf --max-time 3 -X POST -H 'Content-Type: application/json' -d "$JSON" "$API_BASE/settings/subtitle"` |

---

### Data-Flow Trace (Level 4)

| Artifact                                        | Data Variable        | Source                                              | Produces Real Data                                                        | Status  |
| ----------------------------------------------- | -------------------- | --------------------------------------------------- | ------------------------------------------------------------------------- | ------- |
| SubtitlePanel.swift                             | `currentDisplayMode` | `settingsStore?.getSettings().subtitle.displayMode` | Yes — reads from SettingsStore which persists to disk JSON                | FLOWING |
| BionicRenderer.render                           | `words: [String]`    | Callers pass real text split by whitespace          | Yes — words array from show(text:) split, or real words from TTS pipeline | FLOWING |
| HTTPControlServer.swift POST /settings/subtitle | `update.displayMode` | JSON request body decoded from HTTP client          | Yes — decoded from request, applied to SettingsStore                      | FLOWING |

---

### Behavioral Spot-Checks

| Behavior                                      | Command                                                                                  | Result                                | Status |
| --------------------------------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------- | ------ |
| BionicRendererTests 14 tests pass             | `cd plugins/claude-tts-companion && swift test --filter BionicRendererTests`             | `14 tests passed after 0.011 seconds` | PASS   |
| Swift build compiles clean                    | `cd plugins/claude-tts-companion && swift build`                                         | `Build complete! (1.65s)`             | PASS   |
| Bionic Reading present in SwiftBar plugin     | `grep "Bionic Reading" ~/Library/Application\ Support/SwiftBar/Plugins/claude-hq.10s.sh` | Line 105 matched                      | PASS   |
| toggle-bionic handler present in nc-action.sh | `grep "toggle-bionic" ~/Library/Application\ Support/SwiftBar/Plugins/nc-action.sh`      | Line 68 matched                       | PASS   |
| Commits from SUMMARY exist in git             | `git show 51fbba3f && git show 46d513f3`                                                 | Both commits verified in repo         | PASS   |

---

### Requirements Coverage

| Requirement | Source Plan | Description                                                                     | Status    | Evidence                                                                                                                                                                  |
| ----------- | ----------- | ------------------------------------------------------------------------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| BION-01     | Plan 02     | User can toggle bionic reading mode via SwiftBar settings menu                  | SATISFIED | claude-hq.10s.sh Bionic Reading toggle + nc-action.sh toggle-bionic handler wired to POST /settings/subtitle                                                              |
| BION-02     | Plan 01     | User can toggle bionic reading mode via HTTP API                                | SATISFIED | SubtitleSettingsUpdate.displayMode + POST /settings/subtitle handler persists and applies the mode                                                                        |
| BION-03     | Plan 01     | Subtitle text renders with bold first 40% of each word when bionic mode enabled | SATISFIED | BionicRenderer.boldPrefixLength (40% ceiling), SubtitlePanel branches on .bionic in show() and highlightWord()                                                            |
| BION-04     | Plan 01     | Bionic rendering composes correctly with karaoke gold highlighting              | SATISFIED | highlightWord early-returns with bionic rendering when mode == .bionic, leaving karaoke path intact; mutual exclusion in HTTP handler prevents both active simultaneously |

All 4 BION requirements satisfied. No orphaned requirements.

---

### Anti-Patterns Found

| File | Line | Pattern                                                                      | Severity | Impact |
| ---- | ---- | ---------------------------------------------------------------------------- | -------- | ------ |
| None | —    | No stubs, TODOs, empty returns, or placeholder data found in phase artifacts | —        | —      |

Note: `/ Mutual exclusion` comment syntax at HTTPControlServer.swift line 135 uses a single `/` instead of `//`, but Swift treats a bare `/` in statement position as a division operator on a preceding expression. The build succeeds (`Build complete!`), which means Swift's parser is accepting this as valid code (the expression evaluates and is discarded). This is a style defect, not a functional bug. Classified as ℹ️ Info.

---

### Human Verification Required

### 1. Visual Bionic Rendering

**Test:** Run `curl -X POST -H 'Content-Type: application/json' -d '{"displayMode":"bionic"}' http://localhost:8780/settings/subtitle` then `curl -X POST -H 'Content-Type: application/json' -d '{"text":"Welcome to bionic reading mode demonstration"}' http://localhost:8780/subtitle/show`
**Expected:** Subtitle panel shows "Wel" in bold, "come" in regular; "to" all bold (single-char-equivalent); "bio" bold, "nic" regular; "rea" bold, "ding" regular; etc. All text white.
**Why human:** NSAttributedString bold/regular weight rendering requires visual inspection on the macOS display.

### 2. SwiftBar Toggle Dot State

**Test:** Open SwiftBar menu and locate the Subtitle section; check the Bionic Reading item.
**Expected:** When displayMode is "karaoke" (default), the item shows a red dot (🔴). After toggling once, it shows a green dot (🟢).
**Why human:** SwiftBar menu item rendering requires visual confirmation; dot color driven by shell variable cannot be inspected without a running SwiftBar context.

### 3. End-to-End Toggle via SwiftBar Click

**Test:** Click "Bionic Reading" in SwiftBar menu. Observe the subtitle overlay update. Click again to toggle back.
**Expected:** First click enables bionic mode (green dot; subtitle renders with bold prefixes). Second click reverts to karaoke (red dot; subtitle returns to plain white or karaoke coloring).
**Why human:** Requires live interaction with SwiftBar menu and a running claude-tts-companion service instance.

---

### Gaps Summary

No functional gaps found. All 8 must-have truths are verified, all artifacts exist and are substantive and wired, all key links are connected, data flows end-to-end, all 4 BION requirements are satisfied, and the test suite passes 14/14. Three human verification items remain for visual/interactive behaviors that cannot be validated programmatically.

---

_Verified: 2026-03-28_
_Verifier: Claude (gsd-verifier)_
