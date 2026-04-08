---
phase: quick
plan: 260407-odg
type: execute
wave: 1
depends_on: []
files_modified:
  - plugins/claude-tts-companion/Sources/CompanionCore/TelegramBotNotifications.swift
  - plugins/claude-tts-companion/Sources/CompanionCore/TTSQueue.swift
  - plugins/claude-tts-companion/Sources/CompanionCore/SubtitleSyncDriver.swift
autonomous: true
requirements: []
must_haves:
  truths:
    - "Fire-and-forget hide() calls in fallback paths are cancellable via stored DispatchWorkItem"
    - "New TTS playback cancels any pending fallback hide before it fires"
    - "60Hz karaoke tick re-asserts panel visibility every ~0.5s via orderFrontRegardless()"
  artifacts:
    - path: "plugins/claude-tts-companion/Sources/CompanionCore/TelegramBotNotifications.swift"
      provides: "Cancellable pendingFallbackHide work item in showSubtitleOnlyFallback"
      contains: "pendingFallbackHide"
    - path: "plugins/claude-tts-companion/Sources/CompanionCore/TTSQueue.swift"
      provides: "Cancellable pendingFallbackHide work item in showSubtitleFallback"
      contains: "pendingFallbackHide"
    - path: "plugins/claude-tts-companion/Sources/CompanionCore/SubtitleSyncDriver.swift"
      provides: "Periodic orderFrontRegardless in tickStreaming"
      contains: "orderFrontRegardless"
  key_links:
    - from: "TTSPipelineCoordinator.cancelCurrentPipeline()"
      to: "subtitlePanel.hide()"
      via: "already cancels pendingLingerHide in SubtitlePanel.hide()"
      pattern: "subtitlePanel\\.hide\\(\\)"
    - from: "SubtitleSyncDriver.tickStreaming()"
      to: "subtitlePanel.orderFrontRegardless()"
      via: "periodic call every ~30 ticks"
      pattern: "orderFrontRegardless"
---

<objective>
Fix two independent causes of intermittent subtitle panel disappearance during TTS playback.

Purpose: The subtitle panel vanishes mid-playback due to (1) uncancellable delayed hide() calls in fallback paths that fire during subsequent active playback, and (2) macOS silently demoting the floating NSPanel during Spaces/Mission Control/display wake transitions with no periodic re-assertion of front ordering.

Output: Patched TelegramBotNotifications.swift, TTSQueue.swift, SubtitleSyncDriver.swift
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@plugins/claude-tts-companion/CLAUDE.md
@.planning/debug/subtitle-panel-intermittent-disappear.md

<interfaces>
<!-- Key APIs the executor needs -->

From SubtitlePanel.swift (lines 124-148):

```swift
/// Hide the subtitle panel.
func hide() {
    pendingLingerHide?.cancel()
    pendingLingerHide = nil
    clearEdgeHint()
    orderOut(nil)
}

/// Pending linger-hide work item.
private var pendingLingerHide: DispatchWorkItem?

/// Schedule a hide after the linger duration.
func lingerThenHide() {
    pendingLingerHide?.cancel()
    let item = DispatchWorkItem { [weak self] in
        self?.pendingLingerHide = nil
        self?.clearEdgeHint()
        self?.orderOut(nil)
    }
    pendingLingerHide = item
    DispatchQueue.main.asyncAfter(deadline: .now() + SubtitleStyle.lingerDuration, execute: item)
}
```

From SubtitlePanel.swift (line 119):

```swift
orderFrontRegardless()  // NSWindow method, already used in show(text:) and updateAttributedText()
```

From TelegramBotNotifications.swift (line 5):

```swift
extension TelegramBot {  // This is an extension on TelegramBot class
```

From TTSQueue.swift (line 79):

```swift
public actor TTSQueue {  // This is an actor, not a class
```

From SubtitleSyncDriver.swift (lines 107-108):

```swift
/// Tick counter for periodic telemetry logging (every 30 ticks = ~0.5s).
private var tickCount: Int = 0
```

From TTSPipelineCoordinator.swift (lines 113-127, 135-141):

```swift
func cancelCurrentPipeline() {
    activeSyncDriver?.stop()
    activeSyncDriver = nil
    playbackManager.afplayPlayer.reset()
    playbackManager.stopPlayback()
    subtitlePanel.clearEdgeHint()
    subtitlePanel.hide()  // Already cancels pendingLingerHide via SubtitlePanel.hide()
    isActive = false
    // ...
}

func startBatchPipeline(chunks:onComplete:) {
    cancelCurrentPipeline()  // Cancels previous pipeline before starting new one
    isActive = true
    // ...
}
```

</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Make fallback hide() calls cancellable in TelegramBotNotifications and TTSQueue</name>
  <files>
    plugins/claude-tts-companion/Sources/CompanionCore/TelegramBotNotifications.swift
    plugins/claude-tts-companion/Sources/CompanionCore/TTSQueue.swift
  </files>
  <action>
**TelegramBotNotifications.swift** — `showSubtitleOnlyFallback` (line 140-148):

The current code uses fire-and-forget `asyncAfter` to hide after `SubtitleStyle.lingerDuration + 5.0`:

```swift
func showSubtitleOnlyFallback(text: String) {
    DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.subtitlePanel.show(text: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + SubtitleStyle.lingerDuration + 5.0) { [weak self] in
            self?.subtitlePanel.hide()
        }
    }
}
```

This is an `extension TelegramBot` so the stored property must go on TelegramBot itself. However, since we cannot add stored properties to extensions, and this is a class extension in the same module, add the property directly in TelegramBot's main declaration. But first check: the `subtitlePanel` property is already accessible here. The simplest approach that avoids modifying TelegramBot's main file is to use `SubtitlePanel.lingerThenHide()` pattern — BUT the delay here is `lingerDuration + 5.0`, not just `lingerDuration`.

**Better approach**: Replace the fire-and-forget `asyncAfter` with a `DispatchWorkItem` stored on the `SubtitlePanel` itself. Since `SubtitlePanel` already has the `pendingLingerHide` pattern, the cleanest fix is to call `subtitlePanel.show(text:)` (which already cancels `pendingLingerHide`) then schedule the hide via a new `SubtitlePanel` method or reuse `lingerThenHide()`.

**Actually simplest and correct**: The `SubtitlePanel.show(text:)` method already cancels `pendingLingerHide` and calls `orderFrontRegardless()`. And when a NEW TTS pipeline starts, `TTSPipelineCoordinator.cancelCurrentPipeline()` calls `subtitlePanel.hide()` which cancels `pendingLingerHide`. So all we need is to replace the raw `asyncAfter` with `subtitlePanel.lingerThenHide()` or a custom-duration variant.

Since the fallback delay is `lingerDuration + 5.0` (not just `lingerDuration`), add a `lingerThenHide(after:)` overload to SubtitlePanel OR simply use the existing `pendingLingerHide` mechanism with a custom delay. The cleanest: change `showSubtitleOnlyFallback` to:

```swift
func showSubtitleOnlyFallback(text: String) {
    DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.subtitlePanel.show(text: text)
        // Schedule cancellable hide — cancelled automatically if SubtitlePanel.show(),
        // hide(), or updateAttributedText() is called before timer fires.
        self.subtitlePanel.lingerThenHide(after: SubtitleStyle.lingerDuration + 5.0)
    }
}
```

**TTSQueue.swift** — `showSubtitleFallback` (line 474-482):

Same pattern. Current code:

```swift
private func showSubtitleFallback(_ item: WorkItem) {
    let text = item.greeting.map { "\($0) \(item.text)" } ?? item.text
    DispatchQueue.main.async { [subtitlePanel] in
        subtitlePanel.show(text: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            subtitlePanel.hide()
        }
    }
}
```

Replace with:

```swift
private func showSubtitleFallback(_ item: WorkItem) {
    let text = item.greeting.map { "\($0) \(item.text)" } ?? item.text
    DispatchQueue.main.async { [subtitlePanel] in
        subtitlePanel.show(text: text)
        subtitlePanel.lingerThenHide(after: 8.0)
    }
}
```

**SubtitlePanel.swift** — Add `lingerThenHide(after:)` overload:

Near the existing `lingerThenHide()` (line 139-148), add a parameterized version:

```swift
/// Schedule a hide after a custom delay. Uses the same pendingLingerHide
/// mechanism as lingerThenHide() — automatically cancelled if new content
/// is shown (show/updateAttributedText cancel pendingLingerHide).
func lingerThenHide(after delay: TimeInterval) {
    pendingLingerHide?.cancel()
    let item = DispatchWorkItem { [weak self] in
        self?.pendingLingerHide = nil
        self?.clearEdgeHint()
        self?.orderOut(nil)
    }
    pendingLingerHide = item
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
}
```

Then refactor the existing `lingerThenHide()` to call the parameterized version:

```swift
func lingerThenHide() {
    lingerThenHide(after: SubtitleStyle.lingerDuration)
}
```

This ensures all delayed hide() calls go through the single cancellable `pendingLingerHide` work item. Any new `show()`, `hide()`, `updateAttributedText()`, or `lingerThenHide()` call cancels any pending hide.
</action>
<verify>
<automated>cd plugins/claude-tts-companion && swift build 2>&1 | tail -5</automated>
</verify>
<done> - showSubtitleOnlyFallback uses subtitlePanel.lingerThenHide(after:) instead of raw asyncAfter - showSubtitleFallback uses subtitlePanel.lingerThenHide(after:) instead of raw asyncAfter - SubtitlePanel has lingerThenHide(after:) method that reuses pendingLingerHide cancellation - No raw DispatchQueue.main.asyncAfter hide() calls remain in fallback paths - swift build succeeds
</done>
</task>

<task type="auto">
  <name>Task 2: Add periodic orderFrontRegardless() in tickStreaming 60Hz path</name>
  <files>plugins/claude-tts-companion/Sources/CompanionCore/SubtitleSyncDriver.swift</files>
  <action>
In `tickStreaming()` (line 509), the existing `tickCount` is already incremented every tick and used for telemetry logging every 30 ticks. Add a periodic `orderFrontRegardless()` call piggy-backing on this counter.

After the telemetry log block (line 565-567), add a panel visibility re-assertion:

```swift
// Re-assert panel front ordering every ~0.5s (30 ticks at 60Hz).
// macOS can silently demote floating NSPanels during Spaces transitions,
// Mission Control, display wake, or fullscreen app focus changes.
// This is cheap (one ObjC message send) and ensures the panel stays visible.
if tickCount % 30 == 0 {
    subtitlePanel.orderFrontRegardless()
}
```

Place this AFTER the telemetry log block (which also fires on `tickCount % 30 == 0`) and BEFORE the `updateHighlight(for: chunkLocalTime)` call at line 569. This way the panel is guaranteed visible before the highlight update paints new content.

Note: `subtitlePanel` is already a `@MainActor` property accessible from `tickStreaming()` since `SubtitleSyncDriver` is `@MainActor`. The `orderFrontRegardless()` method is inherited from NSWindow (parent of NSPanel) and is already used in `SubtitlePanel.show(text:)` and `updateAttributedText()`.
</action>
<verify>
<automated>cd plugins/claude-tts-companion && swift build 2>&1 | tail -5</automated>
</verify>
<done> - tickStreaming() calls subtitlePanel.orderFrontRegardless() every 30 ticks (~0.5s) - The call is placed after telemetry logging and before updateHighlight - swift build succeeds
</done>
</task>

</tasks>

<threat_model>

## Trust Boundaries

No new trust boundaries introduced. Both fixes are internal to the main-thread UI coordination layer.

## STRIDE Threat Register

| Threat ID  | Category              | Component                  | Disposition | Mitigation Plan                                                                                                  |
| ---------- | --------------------- | -------------------------- | ----------- | ---------------------------------------------------------------------------------------------------------------- |
| T-quick-01 | D (Denial of Service) | orderFrontRegardless 30x/s | accept      | One ObjC message send per 0.5s is negligible; already called on every page transition. No measurable CPU impact. |

</threat_model>

<verification>
```bash
cd plugins/claude-tts-companion && swift build 2>&1 | tail -5
```
Build must succeed with zero errors. No tests needed (visual-only fixes verified by user observation).
</verification>

<success_criteria>

- swift build passes cleanly
- No fire-and-forget asyncAfter hide() calls remain in fallback code paths
- All delayed hide() calls route through SubtitlePanel.pendingLingerHide cancellation mechanism
- tickStreaming re-asserts panel visibility every ~0.5s
  </success_criteria>

<output>
After completion, create `.planning/quick/260407-odg-fix-subtitle-panel-intermittent-disappea/260407-odg-SUMMARY.md`
</output>
