---
phase: 23-caption-history-panel
verified: 2026-03-28T04:00:00Z
status: human_needed
score: 5/5 must-haves verified
re_verification: false
human_verification:
  - test: "Panel opens from SwiftBar and shows captions with HH:MM timestamps"
    expected: "Floating titled NSPanel appears with two-column table (time + caption text) in dark appearance"
    why_human: "Visual UI rendering cannot be verified programmatically; requires running service with active captions"
  - test: "Auto-scroll with manual override"
    expected: "Panel scrolls to newest entry on refresh; scrolling up pauses auto-scroll; returning to bottom resumes it"
    why_human: "Scroll behavior is runtime interaction requiring manual testing"
  - test: "Click-to-copy"
    expected: "Clicking a caption row copies its text to clipboard (verifiable via Cmd+V)"
    why_human: "NSTableView selection and NSPasteboard write requires live app interaction"
  - test: "Service running: curl -X POST http://localhost:8780/captions/panel/show"
    expected: '{"ok":true} and panel appears on screen'
    why_human: "Requires claude-tts-companion service running with launchd; cannot test without live service"
---

# Phase 23: Caption History Panel Verification Report

**Phase Goal:** Users can review and copy past subtitle captions from a scrollable panel
**Verified:** 2026-03-28T04:00:00Z
**Status:** human_needed (all automated checks passed; 4 items need live service testing)
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth                                                                      | Status   | Evidence                                                                                                                                                                  |
| --- | -------------------------------------------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | A scrollable NSPanel shows past captions with HH:MM timestamps             | VERIFIED | CaptionHistoryPanel.swift:10 — NSPanel subclass with NSTableView; timeFormatter uses `dateFormat = "HH:mm"` at line 40; two-column table at lines 64-74                   |
| 2   | Panel auto-scrolls to latest entry when new captions arrive                | VERIFIED | `refresh()` calls `scrollToBottom()` when `!isUserScrolling` (lines 157-163); `scrollToBottom()` uses `tableView.scrollRowToVisible(entries.count - 1)` (lines 255-258)   |
| 3   | Manual scroll up pauses auto-scroll; returning to bottom resumes it        | VERIFIED | `scrollViewDidScroll(_:)` observer (lines 232-244) sets `isUserScrolling = !atBottom` with 20pt tolerance; wired via `NSScrollView.didLiveScrollNotification` at line 137 |
| 4   | Clicking a caption copies its text to the macOS clipboard                  | VERIFIED | `tableViewSelectionDidChange(_:)` (lines 211-228) calls `NSPasteboard.general.setString(entry.text, forType: .string)` with deselect-after-delay visual feedback          |
| 5   | POST /captions/panel/show opens panel; POST /captions/panel/hide closes it | VERIFIED | HTTPControlServer.swift lines 272-280; both endpoints call `MainActor.run { captionHistoryPanel.show()/hide() }`                                                          |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact                                                                       | Expected                                                    | Status   | Details                                                                                                            |
| ------------------------------------------------------------------------------ | ----------------------------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------------ |
| `plugins/claude-tts-companion/Sources/CompanionCore/CaptionHistoryPanel.swift` | Scrollable caption history NSPanel with NSTableView         | VERIFIED | 265 lines (exceeds 80-line minimum); @MainActor NSPanel subclass with NSTableViewDataSource + Delegate conformance |
| `plugins/claude-tts-companion/Sources/CompanionCore/HTTPControlServer.swift`   | Panel show/hide HTTP endpoints containing `/captions/panel` | VERIFIED | Lines 272-280 contain both `POST /captions/panel/show` and `POST /captions/panel/hide` endpoints                   |
| `~/Library/Application Support/SwiftBar/Plugins/claude-hq.10s.sh`              | Caption History menu item                                   | VERIFIED | Line 107: `echo ":text.bubble: Caption History                                                                     | $(act toggle-captions "" "")"` |
| `~/Library/Application Support/SwiftBar/Plugins/nc-action.sh`                  | toggle-captions action handler containing `/captions/panel` | VERIFIED | Lines 114-119: `toggle-captions` case with `curl -sf ... -X POST "$API_BASE/captions/panel/show"`                  |

### Key Link Verification

| From                | To                  | Via                                     | Status   | Details                                                                                                                                                                                                                      |
| ------------------- | ------------------- | --------------------------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CaptionHistoryPanel | CaptionHistory      | reads entries via `getAll()`            | VERIFIED | `reloadEntries()` at line 250 calls `captionHistory.getAll()`; called from `show()` and `refresh()`                                                                                                                          |
| HTTPControlServer   | CaptionHistoryPanel | MainActor.run show/hide calls           | VERIFIED | Lines 272-280: `captionHistoryPanel.show()` and `captionHistoryPanel.hide()` called inside `MainActor.run`                                                                                                                   |
| CompanionApp        | CaptionHistoryPanel | creates and passes to HTTPControlServer | VERIFIED | Line 39: `captionHistoryPanel = CaptionHistoryPanel(captionHistory: captionHistory)`; line 47: passed to HTTPControlServer init; line 68: `captionHistory.onChange = { [weak self] in self?.captionHistoryPanel.refresh() }` |
| nc-action.sh        | HTTPControlServer   | curl POST /captions/panel/show          | VERIFIED | nc-action.sh line 116: `curl -sf --max-time 3 -X POST "$API_BASE/captions/panel/show"`                                                                                                                                       |

### Data-Flow Trace (Level 4)

| Artifact                     | Data Variable             | Source                                                                                                         | Produces Real Data                                                                         | Status  |
| ---------------------------- | ------------------------- | -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ | ------- |
| CaptionHistoryPanel          | `entries: [CaptionEntry]` | `CaptionHistory.getAll()` via `reloadEntries()`                                                                | Yes — ring buffer reads from `buffer` array populated by `record()` calls in SubtitlePanel | FLOWING |
| CaptionHistoryPanel.onChange | refresh trigger           | `CaptionHistory.record()` dispatches to main thread via `DispatchQueue.main.async { callback() }` (line 73-75) | Yes — real-time push on each new caption                                                   | FLOWING |

### Behavioral Spot-Checks

| Behavior                                   | Command                                                  | Result                                                                          | Status |
| ------------------------------------------ | -------------------------------------------------------- | ------------------------------------------------------------------------------- | ------ |
| Swift build compiles without errors        | `cd plugins/claude-tts-companion && swift build`         | `Build complete! (1.47s)`                                                       | PASS   |
| CaptionHistoryPanel class exists           | `grep -q "class CaptionHistoryPanel" ...`                | Match at line 10                                                                | PASS   |
| HTTP endpoints present in source           | `grep -c "/captions/panel" HTTPControlServer.swift`      | 2 matches (show + hide)                                                         | PASS   |
| CaptionHistoryPanel referenced in 3+ files | grep across Sources/                                     | Found in CaptionHistoryPanel.swift, HTTPControlServer.swift, CompanionApp.swift | PASS   |
| Panel show endpoint (live)                 | `curl -X POST http://localhost:8780/captions/panel/show` | SKIP — requires running service                                                 | SKIP   |

### Requirements Coverage

| Requirement | Source Plan            | Description                                                                          | Status    | Evidence                                                                                                                                                             |
| ----------- | ---------------------- | ------------------------------------------------------------------------------------ | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CAPT-01     | 23-01-PLAN             | User can open scrollable caption history panel showing past captions with timestamps | SATISFIED | CaptionHistoryPanel NSPanel with NSTableView, HH:mm formatter, `show()` method calls `orderFrontRegardless()`                                                        |
| CAPT-02     | 23-01-PLAN             | Caption history auto-scrolls to latest, with manual scroll override                  | SATISFIED | `isUserScrolling` flag + `NSScrollView.didLiveScrollNotification` observer + `scrollToBottom()` in `refresh()`                                                       |
| CAPT-03     | 23-01-PLAN             | User can copy individual caption text to clipboard                                   | SATISFIED | `tableViewSelectionDidChange` writes `entry.text` to `NSPasteboard.general`                                                                                          |
| CAPT-04     | 23-01-PLAN, 23-02-PLAN | Caption history accessible via SwiftBar button and HTTP API                          | SATISFIED | HTTP: `POST /captions/panel/show` + `/hide` in HTTPControlServer; SwiftBar: `Caption History` button in claude-hq.10s.sh + `toggle-captions` handler in nc-action.sh |

All 4 requirement IDs from plan frontmatter are accounted for. No orphaned requirements detected (REQUIREMENTS.md confirms all 4 mapped to Phase 23 with status Complete).

### Anti-Patterns Found

| File | Line | Pattern    | Severity | Impact |
| ---- | ---- | ---------- | -------- | ------ |
| —    | —    | None found | —        | —      |

No TODO/FIXME/PLACEHOLDER comments. No stub implementations (return null/empty). No hardcoded empty data arrays passed to rendering. No console-log-only handlers.

### Human Verification Required

#### 1. Visual Panel Appearance

**Test:** With claude-tts-companion service running, send a TTS request then call `curl -X POST http://localhost:8780/captions/panel/show`
**Expected:** Floating dark panel titled "Caption History" appears with HH:MM timestamps in left column and caption text in right column
**Why human:** Visual rendering and AppKit window presentation cannot be verified programmatically

#### 2. Auto-scroll Behavior

**Test:** Populate enough captions to overflow the panel, then scroll up manually; wait for a new caption to arrive
**Expected:** Auto-scroll stops while scrolled up; returns to auto-scroll when user scrolls back to bottom
**Why human:** Requires live interaction with a running NSScrollView and real-time caption delivery

#### 3. Click-to-Copy

**Test:** Open the caption history panel with entries; click any row; press Cmd+V in a text field
**Expected:** The caption text for that row is pasted
**Why human:** NSTableView selection and NSPasteboard content require live app interaction to verify

#### 4. SwiftBar Integration End-to-End

**Test:** Click SwiftBar menu bar icon; locate "Caption History" button; click it
**Expected:** Panel opens immediately with past captions
**Why human:** SwiftBar menu rendering and inter-process HTTP call require running service and GUI interaction

### Gaps Summary

No gaps found. All 5 automated truths verified, all 4 artifacts confirmed substantive and wired, all 3 key links traced end-to-end, all 4 requirement IDs satisfied.

Four items are routed to human verification because they require a running `claude-tts-companion` launchd service and live GUI interaction — standard for AppKit panel behavior verification.

---

_Verified: 2026-03-28T04:00:00Z_
_Verifier: Claude (gsd-verifier)_
