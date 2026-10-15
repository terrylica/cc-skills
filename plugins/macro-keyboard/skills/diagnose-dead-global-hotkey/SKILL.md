---
name: diagnose-dead-global-hotkey
description: Find out why a macOS global hotkey (screenshot tool, launcher, clipboard manager) stops working only while a particular app is frontmost or running, typically a remote-desktop or VNC viewer, a VM or a game. Traces a REAL key press through the four event-tap positions to separate the causes - a Karabiner per-app modifier remap that rewrites the chord, an app's active keyboard grab (CGEventTap) that swallows it, Secure Event Input, or the hotkey owner itself - then applies the matching fix. TRIGGERS - global hotkey not working, shortcut does not work in VNC, hotkey dead when app focused, screenshot shortcut goes to remote desktop, keyboard grab, CGEventTap, RegisterEventHotKey, Karabiner per-app remap, frontmost_application_if, Cmd becomes Ctrl, TigerVNC FullscreenSystemKeys, secure input.
allowed-tools: Read, Edit, Write, Bash
---

# Diagnose a Dead Global Hotkey

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, an API or app option changed, or a workaround was needed: fix this file and the scripts immediately, don't defer. Only update for real, reproducible issues.

A global hotkey works everywhere except while one app is in front (or full screen, or merely running). The press either does nothing or does something inside that app instead. This skill finds **where** on the input path the chord is lost or changed, then fixes that layer only.

## The input path (bottom to top)

```
keyboard ─► DriverKit remapper (Karabiner-Elements) ─► HID tap point ─► Session tap point ─► hotkey dispatch ─► frontmost app
              rewrites keys BELOW every tap            active taps here can swallow or rewrite     (Carbon RegisterEventHotKey)
```

`tap-census.swift` can also report taps at a third point, AnnotatedSession. The window server handles some shortcuts before events reach it (TigerVNC's source gives this as the reason it cannot grab the keyboard there), so a tap at that point is an unlikely culprit, and the logger does not watch it. If the four positions are all clean and the census shows an ACTIVE AnnotatedSession tap from the problem app, suspect it next.

Two facts drive the whole method:

1. **A remapper works below the tap layer.** Karabiner's rules (for example a `frontmost_application_if` rule that turns Command into Control for a remote-desktop viewer) change the chord before any event tap, logger or hotkey sees it.
2. **A synthetic test key enters above the remapper.** A `CGEventPost` probe can report "hotkey fires" while the physical key still fails. Never conclude from a synthetic probe alone; confirm with a real key press in the logger.

## Tools (in `scripts/`, run with `swift <file>`, no build step)

Resolve the directory first: `S="$(cc-plugin-root macro-keyboard)/skills/diagnose-dead-global-hotkey/scripts"`.

| Script                  | What it does                                                                                                                                                                            |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tap-census.swift`      | Lists every keyboard event tap: owner, HID or Session point, ACTIVE (can swallow) or listen-only. Read-only.                                                                            |
| `key-path-logger.swift` | Four listen-only taps (HID head/tail, Session head/tail). Logs only key-downs with Cmd, Ctrl or Opt held: modifiers, keycode, frontmost app, and whether a watched app opened a window. |
| `hotkey-probe.swift`    | Posts a synthetic chord at the HID tap and reports whether the watched app reacted (`FIRED` / `DID NOT FIRE`). Good for tap and window-state tests, blind to remappers.                 |

The logger needs Input Monitoring for the terminal that runs it. It never logs plain typing.

## Workflow

### 1. Establish the baseline and the failing state

```bash
swift "$S/tap-census.swift"                         # with the problem app closed
# open the problem app, reproduce the failing state (windowed? full screen? focused?)
swift "$S/tap-census.swift"                         # diff: a new ACTIVE tap owned by the problem app is suspect #1
ioreg -l -w 0 | grep -o '"kCGSSessionSecureInputPID"=[0-9]*' | sort -u   # non-empty = Secure Event Input is on (that pid)
```

Record the exact state the user is in. Full screen versus windowed matters: some viewers grab the keyboard only in full screen.

### 2. Watch a real key press

```bash
swift "$S/key-path-logger.swift" 600 "<hotkey owner process name>"
```

Ask the user to press the hotkey (a) in a neutral app such as Finder, then (b) with the problem app frontmost. Read the log:

| Log shows                                                                                        | Cause                                                                                           | Fix                                                                                                     |
| ------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Different modifiers than pressed (e.g. `Ctrl+Shift+X` for Cmd+Shift+X), `front=` the problem app | A remapper rule scoped to that app rewrote the chord                                            | Add an exception to the rule, [Fix A](#fix-a-karabiner-per-app-modifier-remap)                          |
| Seen at `HID-head`, missing at a later position                                                  | An ACTIVE tap between those positions swallowed it                                              | Find the owner with `tap-census.swift`; if it is the problem app, [Fix B](#fix-b-an-apps-keyboard-grab) |
| Seen everywhere, unchanged, but the hotkey owner opens nothing                                   | The owner registered a different chord, or its registration failed                              | Check the owner's shortcut setting; re-register it                                                      |
| Not seen anywhere while the problem app is frontmost, but seen from the neutral app              | Secure Event Input: it hides key events from other processes' taps as well as from hotkeys      | Find the Secure Input pid (step 1); the owning app must turn it off (usually a focused password field)  |
| Not seen anywhere, even from the neutral app                                                     | Lost before the window server: hardware, KVM or sharing software, a remapper rule that drops it | Check Karabiner-EventViewer and the remapper's rules for the key                                        |

### 3. Fix the layer that failed, then re-verify with a real press

Re-run the logger and have the user press again. Done when the log shows the original chord at all four positions and the watched app's window count rises.

## Fix A: Karabiner per-app modifier remap

A rule such as "Command → Control while a remote-desktop viewer is frontmost" (so Cmd+C/V act as Ctrl+C/V on the remote machine) also turns the hotkey chord into a Control chord, which the remote machine receives. Add exception manipulators **inside that rule, before its modifier manipulators**, that re-emit the chord with Command:

```json
{ "type": "basic",
  "conditions": [{ "type": "frontmost_application_if", "bundle_identifiers": ["^<viewer bundle id regex>$"] }],
  "from": { "key_code": "x", "modifiers": { "mandatory": ["command", "shift"], "optional": ["caps_lock"] } },
  "to":   [{ "key_code": "x", "modifiers": ["left_command", "left_shift"] }] },
{ "type": "basic",
  "conditions": [{ "type": "frontmost_application_if", "bundle_identifiers": ["^<viewer bundle id regex>$"] }],
  "from": { "key_code": "x", "modifiers": { "mandatory": ["control", "shift"], "optional": ["caps_lock"] } },
  "to":   [{ "key_code": "x", "modifiers": ["left_command", "left_shift"] }] }
```

Ship both variants. The pair was verified together, but it was not measured which one matches: that depends on whether `from.modifiers` sees the physical Command or the already-rewritten Control, and keeping both makes the rule correct either way. Side effect to tell the user: a physical Ctrl+Shift+X in that app now also becomes the hotkey. Karabiner reloads `karabiner.json` on save; confirm with `Load .../karabiner.json` followed by `core_configuration is updated` in `~/.local/share/karabiner/log/console_user_server.log`. If the file is managed by a dotfile manager (chezmoi and so on), update its source too.

**Why "click another app first" does not help:** a floating, non-activating window (clock, HUD, palette) never becomes the frontmost application, so `frontmost_application_if` still matches the viewer. Check `front=` in the logger, not what the user clicked.

## Fix B: an app's keyboard grab

Remote-desktop viewers, VMs and games often install an **ACTIVE Session-level `CGEventTap`** that takes every key event and re-posts it to themselves, so system shortcuts reach the remote side. Hotkey dispatch never sees the key. Look for an option that disables the grab:

| App             | Grab trigger                                                                      | Option that disables it                                                                                |
| --------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| TigerVNC viewer | Full screen with `FullscreenSystemKeys` on (the default), or a manual grab toggle | `-FullscreenSystemKeys=0` on the command line, or `FullscreenSystemKeys=0` in the viewer's config file |

Verify with `tap-census.swift` that the app's ACTIVE tap is gone in the failing state, and with `hotkey-probe.swift` that the chord fires (taps are above the remapper, so the probe is valid for this fix). The trade-off: system shortcuts such as Cmd+Tab then act on the Mac instead of the remote machine.

## Pitfalls

- **Logging only Command chords hides a remap to Control.** The logger records Cmd, Ctrl and Opt chords for this reason.
- **A synthetic probe proves nothing about remappers** (fact 2 above). Run it, but do not stop at it.
- **One fix may not be enough.** A viewer can hit both causes: a remapper rule (any window state) and a keyboard grab (full screen only). Re-test in every state the user uses.
- **The probe's chord goes somewhere when the hotkey does not fire**: to the frontmost app, or through a viewer to a remote machine. Run it with a harmless app in front.

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the diagnosis match a row of the table?** If the log showed a pattern not listed, add the row and its fix.
2. **Did an app option or API change?** If a viewer renamed its grab option or a script stopped compiling on a new macOS, update the table or script.
3. **Was a workaround needed?** If you had to improvise, fold it into the workflow or pitfalls so the next run does not need it.

Only update if the issue is real and reproducible, not speculative.
