# Whole-clock hide toggle (⌃⌥⇧⌘H)

Added 2026-10-10. One switch hides the clock **and every rail welded to it** (audio, network, brightness, TTS speed, mic-mute and VPN banners), and the same switch brings them all back exactly where they were. The stack can take a lot of screen space, while the toggle is rarely used, so it sits on a chord nobody presses by accident.

## How to use it

| Entry point    | How                                                                                                                                                                                                         |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Global hotkey  | **⌃⌥⇧⌘H** (Control-Option-Shift-Command-H), from any app. Press again to show.                                                                                                                              |
| Context menu   | Right-click the clock → **Hide Clock ⌃⌥⇧⌘H** (first item of the full menu, last item of each segment menu). A hidden clock has no menu, so showing it again is only via the hotkey, the CLI, or a relaunch. |
| CLI / scripts  | `/Applications/FloatingClock.app/Contents/MacOS/floating-clock --toggle` (or `--show`, `--hide`). Posts to the running clock and exits; never starts a second one.                                          |
| Any other tool | Post the distributed notification `<bundle id>.visibility.toggle` (or `.show`, `.hide`), where `<bundle id>` is the app's `CFBundleIdentifier`, e.g. from BetterTouchTool, a Karabiner `shell_command`, or Shortcuts.                               |

Hidden is **not persisted**: a relaunch (login, crash, reinstall) always shows the clock, so it can never stay lost.

## Configuration

`ToggleVisibilityHotKey` (string, default `ctrl+opt+shift+cmd+H`) — read once at launch, so relaunch after changing it.

```bash
BID=$(defaults read /Applications/FloatingClock.app/Contents/Info CFBundleIdentifier)
defaults write "$BID" ToggleVisibilityHotKey 'ctrl+opt+shift+cmd+J'  # re-bind
defaults write "$BID" ToggleVisibilityHotKey none                    # no hotkey
defaults delete "$BID" ToggleVisibilityHotKey                        # back to default
```

Grammar (`Sources/core/HotKeySpec.{h,m}`): modifiers `ctrl|control`, `opt|option|alt`, `shift`, `cmd|command` in any order, joined by `+`, then one key — `A`–`Z`, `0`–`9`, `F1`–`F20`, US-ANSI punctuation, or `Space`, `Return`, `Tab`, `Escape`, `Delete`, `Home`, `End`, `PageUp`, `PageDown`, arrows. Case-insensitive. A malformed value registers **no** hotkey (never a wrong one) and is logged. The active chord is logged at launch (log subsystem = the bundle identifier):

```bash
/usr/bin/log show --last 5m --predicate "subsystem == \"$BID\" AND category == \"visibility\"" --style compact
```

Every flip is logged with its source (`hotkey`, `menu`, `notification`).

## Mechanism

- `Sources/core/ClockVisibilityToggle.{h,m}` owns the state. Hiding runs one tick first, so each rail does its normal detach-then-`orderOut` ceremony, then orders the panel out. Showing orders the panel front (`orderFrontRegardless`, since an accessory app is never active), then runs one tick so the rails re-attach. Hide latency measured at about 60 ms after the keypress, show about 55 ms.
- Each rail's `refresh` and `syncPosition` treat `FCClockUserHidden()` exactly like their own disabled state. That covers the window-move and screen-change paths, which call `syncPosition` directly and would otherwise re-show a rail behind a hidden clock.
- The hotkey is a **Carbon `RegisterEventHotKey`**, not an event tap: it needs no Accessibility or Input Monitoring grant, and the app still sees no other keystrokes. A 250 ms debounce stops a held or bouncing chord from flipping twice.
- Distributed-notification observers use `NSNotificationSuspensionBehaviorDeliverImmediately`: AppKit holds notifications back from inactive apps, and an `LSUIElement` app is never active.
- The brightness boost is left alone while hidden. Hiding is transient, and dimming the screen as a side effect of hiding a clock would read as a bug. Hiding the brightness bar itself, a persistent choice, still releases the boost.

## How ⌃⌥⇧⌘H was chosen (method, reusable for any new global shortcut)

1. **Configuration survey** of every place a shortcut can be claimed: macOS symbolic hotkeys (`com.apple.symbolichotkeys`), per-app `NSUserKeyEquivalents`, the trigger lists of any installed keyboard remapper or automation tool, each running app's own hotkey preferences, browser extension commands, Services and Shortcuts. On the test machine nothing claimed **⌃⌥⇧ + anything** or **⌃⌥⇧⌘ + letter**. ⌃⌥⇧⌘ with `.` `,` `/` is Apple's sysdiagnose chord, so it was excluded. F16–F20 were excluded because no MacBook key produces them.
2. **Registration probing does not detect conflicts.** `RegisterEventHotKey` refuses only a duplicate inside the same process. Across processes it succeeds, and the hotkey is then delivered to **every** registrant: verified against a hotkey another running app had registered, where both handlers fired. A conflict therefore does not fail loudly; it double-fires silently. Config survey plus behavioural observation is the only reliable check.
3. **Behavioural check** with `scripts/hotkey-check/`:
   - `sidefx` snapshots every on-screen window, the frontmost app and the pasteboard, presses the chord with nothing of ours registered, and diffs. Background noise was zero; a positive control (another app's registered hotkey) was caught; ⌃⌥⇧⌘H made nothing react with several different apps frontmost. The one benign diff is the pointer hiding on the first keypress in a text field, which any chord causes.
   - `firetest` confirms the chord reaches the Carbon dispatcher, i.e. no event tap swallows it.
   - `functest.sh` is the end-to-end suite against the installed app. 22/22 passed: hotkey hide, staying hidden across ticks, show, frames identical after a round trip, CLI `--hide`/`--show`/`--toggle` and their idempotence, no second instance, double-press debounce, 20 stress cycles (40/40 transitions), several frontmost apps, and relaunch while hidden. The VPN banner rail and the menu item were also checked live.

```bash
make hotkey-tools                                  # build wins / sidefx / firetest
build/hotkey-check/sidefx null ctrl+opt+shift+cmd+H
FRONT_APPS="Finder,Safari" scripts/hotkey-check/functest.sh   # invasive: toggles, activates apps, relaunches the clock
```

The press-based tools drive System Events, so the terminal running them needs Accessibility. A direct `CGEventPost` from a terminal child process is dropped silently, which is why they do not use it.

## Tests

`tests/test_hotkey_spec.m` covers the default chord, modifier order and aliases, rejection of malformed specs (with outputs untouched), and glyph display. A deliberately broken duplicate-modifier check was confirmed to fail two of these tests before the fix was restored.
