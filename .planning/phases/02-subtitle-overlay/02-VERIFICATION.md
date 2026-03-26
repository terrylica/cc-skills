---
phase: 02-subtitle-overlay
verified: 2026-03-26T09:00:00Z
status: human_needed
score: 11/11 must-haves verified
human_verification:
  - test: "Visual inspection of karaoke overlay"
    expected: "Floating dark semi-transparent panel bottom-center, words cycle gold/grey/white at 200ms/word, panel click-through, no dock icon"
    why_human: "AppKit NSPanel rendering and real-time karaoke timing cannot be verified without running the binary and observing the screen"
  - test: "Screen-sharing invisibility"
    expected: "Panel does NOT appear in a screen share or screen capture session (sharingType = .none)"
    why_human: "NSWindow.sharingType = .none correctness can only be confirmed by sharing your screen in Zoom/FaceTime/Screenshot and observing the panel is absent"
---

# Phase 2: Subtitle Overlay Verification Report

**Phase Goal:** Users see floating karaoke subtitles on their macOS screen with all visual and privacy properties
**Verified:** 2026-03-26T09:00:00Z
**Status:** human_needed
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| #   | Truth                                                                      | Status                                  | Evidence                                                                                                                                           |
| --- | -------------------------------------------------------------------------- | --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | A floating NSPanel appears on the MacBook built-in display                 | VERIFIED                                | `level = .floating`, `NSScreen.main` in `positionOnScreen()`                                                                                       |
| 2   | Panel has dark 30% opacity background with 10px corner radius              | VERIFIED                                | `backgroundColor = NSColor(... alpha: 0.3)`, `cornerRadius: CGFloat = 10` in SubtitleStyle.swift                                                   |
| 3   | Panel is positioned bottom center, 80px from bottom edge, 70% screen width | VERIFIED                                | `bottomOffset: CGFloat = 80`, `widthRatio: CGFloat = 0.7`, centering math in `positionOnScreen()`                                                  |
| 4   | Panel is invisible to screen sharing                                       | VERIFIED (code) / NEEDS HUMAN (runtime) | `sharingType = .none` at SubtitlePanel.swift:217                                                                                                   |
| 5   | Panel does not steal focus and is click-through                            | VERIFIED                                | `ignoresMouseEvents = true` (SUB-10), `canBecomeKey: Bool { false }`, `canBecomeMain: Bool { false }` (SUB-09), `.nonactivatingPanel` in styleMask |
| 6   | Panel appears on all Spaces and fullscreen apps                            | VERIFIED                                | `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` at SubtitlePanel.swift:214                                                        |
| 7   | Text wraps to 2 lines without shrinking                                    | VERIFIED                                | `maximumNumberOfLines = SubtitleStyle.maxLines` (= 2), `lineBreakMode = .byWordWrapping`, no font scaling                                          |
| 8   | Current word highlights in gold bold as words advance                      | VERIFIED                                | `highlightWord(at:in:)` applies `SubtitleStyle.currentWordColor` + `currentWordFont` at the active index                                           |
| 9   | Past words dim to silver-grey, future words remain white                   | VERIFIED                                | `pastWordColor` for `i < index`, `futureWordColor` for `i > index` in `highlightWord`                                                              |
| 10  | NSAttributedString updates complete under 1ms per word                     | VERIFIED (structural)                   | Hot path uses cached static lets (`SubtitleStyle.currentWordFont`, `regularFont`) — no font construction per word                                  |
| 11  | Demo mode cycles sample text at 200ms per word with 2s linger              | VERIFIED                                | `demo()` uses `Array(repeating: 0.2, count: words.count)`, `SubtitleStyle.lingerDuration` (= 2.0)                                                  |

**Score:** 11/11 truths verified (9 fully automated, 2 need human runtime confirmation)

### Required Artifacts

| Artifact                                                                        | Expected                           | Status   | Details                                                                                             |
| ------------------------------------------------------------------------------- | ---------------------------------- | -------- | --------------------------------------------------------------------------------------------------- |
| `plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitleStyle.swift` | Color, font, layout constants      | VERIFIED | 71 lines; `enum SubtitleStyle` with all CONTEXT.md values                                           |
| `plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitlePanel.swift` | NSPanel subclass + karaoke engine  | VERIFIED | 287 lines; full implementation including `highlightWord`, `showUtterance`, `demo`                   |
| `plugins/claude-tts-companion/Sources/claude-tts-companion/main.swift`          | Panel creation and demo activation | VERIFIED | Creates `SubtitlePanel()`, calls `positionOnScreen()`, launches `demo()` at +0.5s, hides on SIGTERM |

### Key Link Verification

| From                | To                  | Via                               | Status | Details                                                  |
| ------------------- | ------------------- | --------------------------------- | ------ | -------------------------------------------------------- |
| SubtitlePanel.swift | SubtitleStyle.swift | SubtitleStyle.\* constants        | WIRED  | 23 references to `SubtitleStyle.` in SubtitlePanel.swift |
| SubtitlePanel.swift | SubtitleStyle.swift | `SubtitleStyle.currentWordColor`  | WIRED  | SubtitlePanel.swift:112                                  |
| main.swift          | SubtitlePanel.swift | `SubtitlePanel()` constructor     | WIRED  | main.swift:23                                            |
| main.swift          | SubtitlePanel.swift | `.demo()` call                    | WIRED  | main.swift:50 inside asyncAfter                          |
| main.swift          | SubtitlePanel.swift | `subtitlePanel.hide()` in SIGTERM | WIRED  | main.swift:31                                            |

### Data-Flow Trace (Level 4)

Subtitle rendering uses locally generated NSAttributedString (no external data source). The data pipeline is:

1. `demo()` generates hardcoded sentences + 200ms timing arrays
2. `showUtterance(_:wordTimings:)` schedules `highlightWord(at:in:)` calls
3. `highlightWord` builds `NSMutableAttributedString` from cached color/font statics
4. `updateAttributedText(_:)` sets `textField.attributedStringValue` — directly rendered

| Artifact            | Data Variable                     | Source                            | Produces Real Data                                       | Status  |
| ------------------- | --------------------------------- | --------------------------------- | -------------------------------------------------------- | ------- |
| SubtitlePanel.swift | `textField.attributedStringValue` | `highlightWord` / `showUtterance` | Yes — computed per word from real text and timing arrays | FLOWING |
| main.swift          | `subtitlePanel`                   | `SubtitlePanel()` init + `demo()` | Yes — demo sentences hardcoded intentionally for Phase 2 | FLOWING |

Note: Demo data is intentionally hardcoded (200ms/word). This is the designed Phase 2 behavior; Phase 3 (TTS engine) replaces demo timings with real sherpa-onnx word timestamps. Not a stub.

### Behavioral Spot-Checks

| Behavior                                 | Command                                                                           | Result                           | Status |
| ---------------------------------------- | --------------------------------------------------------------------------------- | -------------------------------- | ------ |
| `swift build` compiles with zero errors  | `cd plugins/claude-tts-companion && swift build`                                  | `Build complete! (0.12s)`        | PASS   |
| All 4 phase commits exist in git history | `git show --stat e91d0a71 e16bdc98 bdeba498 9c503883`                             | All 4 found, authored 2026-03-25 | PASS   |
| SubtitleStyle exports correct gold color | grep `red: 1.0, green: 0.843, blue: 0.0`                                          | Found at SubtitleStyle.swift:13  | PASS   |
| SubtitleStyle exports correct grey color | grep `0.627, 0.627, 0.627`                                                        | Found at SubtitleStyle.swift:16  | PASS   |
| Background at 30% opacity                | grep `alpha: 0.3`                                                                 | Found at SubtitleStyle.swift:22  | PASS   |
| Corner radius = 10                       | grep `cornerRadius: CGFloat = 10`                                                 | Found at SubtitleStyle.swift:51  | PASS   |
| All privacy flags set                    | grep `sharingType = .none`, `ignoresMouseEvents = true`, `canBecomeKey { false }` | All found in SubtitlePanel.swift | PASS   |
| main.swift wiring complete               | grep `SubtitlePanel()`, `.demo()`, `subtitlePanel.hide()`                         | All found at main.swift:23,50,31 | PASS   |

### Requirements Coverage

| Requirement | Source Plan | Description                                   | Status                                   | Evidence                                                                   |
| ----------- | ----------- | --------------------------------------------- | ---------------------------------------- | -------------------------------------------------------------------------- |
| SUB-01      | 02-01       | User sees floating subtitle text via NSPanel  | SATISFIED                                | `level = .floating` + `NSScreen.main`                                      |
| SUB-02      | 02-01       | Panel on MacBook built-in display by default  | SATISFIED                                | `NSScreen.main` in `positionOnScreen()`                                    |
| SUB-03      | 02-02       | Current word highlighted in warm gold (bold)  | SATISFIED                                | `SubtitleStyle.currentWordColor` + `currentWordFont` in `highlightWord`    |
| SUB-04      | 02-02       | Past words silver-grey, future words white    | SATISFIED                                | `pastWordColor` / `futureWordColor` branches in `highlightWord`            |
| SUB-05      | 02-02       | NSAttributedString updates under 1ms per word | SATISFIED (structural)                   | No font loading in hot path; static lets used                              |
| SUB-06      | 02-01       | Dark 30% background with 10px corners         | SATISFIED                                | `alpha: 0.3`, `cornerRadius = 10` in SubtitleStyle                         |
| SUB-07      | 02-01       | Text wraps to 2 lines without shrinking       | SATISFIED                                | `maximumNumberOfLines = 2`, `byWordWrapping`, no font scaling              |
| SUB-08      | 02-01       | Panel invisible to screen sharing             | SATISFIED (code) / NEEDS HUMAN (runtime) | `sharingType = .none` set                                                  |
| SUB-09      | 02-01       | Panel does not steal focus                    | SATISFIED                                | `.nonactivatingPanel`, `canBecomeKey { false }`, `canBecomeMain { false }` |
| SUB-10      | 02-01       | Panel is click-through                        | SATISFIED                                | `ignoresMouseEvents = true`                                                |
| SUB-11      | 02-01       | Visible on all Spaces and fullscreen apps     | SATISFIED                                | `[.canJoinAllSpaces, .fullScreenAuxiliary]`                                |

All 11 SUB requirements claimed by this phase are accounted for. No orphaned requirements.

### Anti-Patterns Found

| File                | Line | Pattern                              | Severity | Impact                                                                            |
| ------------------- | ---- | ------------------------------------ | -------- | --------------------------------------------------------------------------------- |
| SubtitlePanel.swift | 56   | `// Use a placeholder frame` comment | Info     | Benign comment; `positionOnScreen()` called immediately in `init()` overwrites it |

No functional stubs, no TODOs, no empty implementations, no hardcoded empty data. The one "placeholder" mention is a code comment explaining a necessary two-step init pattern (placeholder frame for super.init, then real frame set by positionOnScreen). Not a stub.

### Human Verification Required

#### 1. Karaoke Overlay Visual Inspection

**Test:** Run `swift run claude-tts-companion` from `plugins/claude-tts-companion/`. Within 0.5 seconds a dark semi-transparent panel should appear bottom-center of your MacBook screen.

**Expected:**

- Panel at bottom center, ~80px from bottom, ~70% of screen width
- Dark background with visible transparency (30% opacity — you see through it to the content below)
- Rounded corners (~10px radius)
- First sentence "Welcome to claude TTS companion, your real-time subtitle overlay" appears
- Words light up in GOLD one at a time at ~200ms intervals
- Previously highlighted words dim to SILVER-GREY
- Upcoming words are WHITE
- First sentence wraps to 2 lines (not truncated, not shrunk)
- After 3 sentences complete, panel clears after ~2 second linger
- No dock icon or app switcher entry appears
- Clicking through the panel — mouse events pass to windows behind it

**Why human:** AppKit NSPanel rendering, timing perception, and visual appearance cannot be verified programmatically.

#### 2. Screen-Sharing Invisibility (SUB-08)

**Test:** While the binary is running and the subtitle panel is visible on screen, start a screen share (Zoom, FaceTime, macOS Screenshot, or QuickTime screen recording) and observe the shared/recorded output.

**Expected:** The subtitle panel is NOT visible in the screen share or recording. The `sharingType = .none` API excludes the window from capture.

**Why human:** NSWindow.sharingType = .none is a macOS security feature that can only be confirmed by observing a capture session — not by inspecting code.

### Gaps Summary

No gaps found. All 11 requirements are implemented with substantive, wired, and data-flowing code. The build compiles clean. Two items require human runtime confirmation (visual karaoke appearance and screen-sharing invisibility) but these are inherently non-automatable — the code implementing them is correct and complete.

---

_Verified: 2026-03-26T09:00:00Z_
_Verifier: Claude (gsd-verifier)_
