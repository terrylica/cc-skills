# Failed Approaches to Emitting Fn on macOS (2026)

Condensed catalog of everything that was tried before landing on `apple_vendor_top_case_key_code: keyboard_fn` via Karabiner-Elements. Every entry here was empirically tested against Typeless (`pushToTalk: "Fn"`) on macOS 15 Sequoia, and macOS's native dictation double-tap-Fn.

## BetterTouchTool (BTT)

**Tried**: BTT 4.x custom gesture → action `Trigger Key Sequence` with Fn as the key; also `Send Shortcut` with Fn as a modifier.

**Result**: BTT reports "action fired" in its log. Typeless mic does not open. macOS dictation does not activate.

**Root cause**: BTT internally calls `CGEventCreateKeyboardEvent` + `CGEventSetFlags(..., kCGEventFlagMaskSecondaryFn)` then `CGEventPost`. The `kCGEventFlagMaskSecondaryFn` flag is **silently dropped** by `CGEventPost` before the event reaches the input event manager. This is consistent across macOS 13/14/15 and undocumented.

**Evidence**: ran a CGEventTap that observed events at `kCGHIDEventTap` — BTT's Fn events showed up with the flag _missing_. A real hardware Fn press showed the flag _present_.

## hidutil

**Tried**:

```bash
hidutil property --set '{"UserKeyMapping":[
  {"HIDKeyboardModifierMappingSrc":0x70000003A,
   "HIDKeyboardModifierMappingDst":0x700000065}
]}'
```

(various source/dest combos attempting to remap a pad button to the Apple Top Case Fn usage)

**Result**: `hidutil` accepts the mapping, but the Fn flag is never synthesized by the OS for the remapped key.

**Root cause**: `hidutil` operates at the HID keycode level (swap keycode X for keycode Y in the device's report stream). The Fn _flag_ (`NX_DEVICE_CAPABILITY_INPUTKEYBOARD_FUNCTION`) is not a keycode — it's a per-event capability set by the keyboard driver based on which HID Usage Page / Usage fired. `hidutil` can't reach that layer.

## QMK / VIA / Vial on Jieli-class Pads

**Tried**: connect the Jieli pad, run `qmk list-keyboards` + `vial` GUI to detect + flash.

**Result**: Neither tool sees the pad. Attempts to force it with `--keymap` fail at bootloader detection.

**Root cause**: Jieli AC69xx / similar cheap chipsets use a proprietary bootloader that only accepts vendor firmware. They are not QMK-compatible. No amount of `dfu-util` incantation will let you flash.

For pads that **are** flashable (ZMK-friendly, QMK-friendly), `APPLE_FN_ENABLE=yes` in the keymap's `rules.mk` + using `KC_APPLE_FN` emits real Fn. But you need a flashable board.

## Python `pynput` / `pyobjc` CGEvent

**Tried**:

```python
from Quartz import CGEventCreateKeyboardEvent, CGEventSetFlags, CGEventPost
# kCGEventFlagMaskSecondaryFn = 0x800000
ev = CGEventCreateKeyboardEvent(None, 63, True)  # 63 = Fn virtual keycode
CGEventSetFlags(ev, 0x800000)
CGEventPost(0, ev)
```

**Result**: Same as BTT — event posts, flag is dropped, Typeless does not fire.

**Root cause**: same mechanism as BTT. `CGEventPost` is the chokepoint.

## AppleScript `key code`

**Tried**:

```applescript
tell application "System Events" to key code 63
```

**Result**: AppleScript errors — `key code 63` is not a recognized virtual keycode in the AS bridge. Even if it worked, it would route through `CGEventPost` internally.

## Hammerspoon `hs.eventtap.keyStroke`

**Tried**: `hs.eventtap.keyStroke({"fn"}, nil)` and variations.

**Result**: No effect — Hammerspoon uses the same `CGEventPost` path under the hood.

## The One That Worked

Karabiner-Elements → remap rule with `"to": [{"apple_vendor_top_case_key_code": "keyboard_fn"}]`.

Karabiner's **DriverKit VirtualHIDDevice** (`org.pqrs.driverkit.VirtualHIDDevice-Manager`) registers itself with the kernel as a real HID keyboard. Its emitted events carry `NX_DEVICE_CAPABILITY_INPUTKEYBOARD_FUNCTION` the same way an Apple internal keyboard does. Fn-flag survives. Typeless and macOS dictation accept it.

This is the only path in 2026. Monitor <https://github.com/pqrs-org/Karabiner-Elements> for changes, but the architectural constraint (flag set at driver level, not postable from userland) is unlikely to change.

## Summary Table

| Tool / Approach             | Why It Fails                                                 |
| --------------------------- | ------------------------------------------------------------ |
| BTT                         | `CGEventPost` drops `kCGEventFlagMaskSecondaryFn`            |
| `hidutil`                   | HID keycode layer can't synthesize the Fn capability flag    |
| QMK/VIA/Vial on Jieli       | Proprietary bootloader rejects non-vendor firmware           |
| Python pyobjc `CGEventPost` | Same as BTT — `CGEventPost` path                             |
| AppleScript `key code 63`   | Not a valid AS keycode; also routes through `CGEventPost`    |
| Hammerspoon `hs.eventtap`   | Same as BTT — `CGEventPost` path                             |
| **Karabiner-Elements**      | **Works** — DriverKit VirtualHIDDevice emits at driver level |
