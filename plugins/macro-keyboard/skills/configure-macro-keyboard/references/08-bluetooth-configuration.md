# Bluetooth Configuration (Live)

How the pad is configured over Bluetooth, paralleling [`02-usb-wired-configuration.md`](02-usb-wired-configuration.md). Verified working 2026-04-21.

## Status

✅ **Pad works over Bluetooth with identical user-facing behavior as USB-C.** Top = tap/double-tap pair (single-tap = Fn for Typeless, double-tap = Cmd+V paste), middle = tap/double-tap pair (single-tap = Shift+Return newline, double-tap = Return send), bottom = Command+Delete. Same Karabiner rule handles both transports plus the BT mode-4 firmware quirks.

The initial assumption in the earlier roadmap — that BT would emit the same Ctrl+C/V/X as USB — was wrong. The pad has **four distinct BT modes** with different keycode firmware, none of which emit Ctrl+C/V/X. We chose mode 4 and added parallel manipulators to the Karabiner rule.

## Bluetooth Device Signature

| Field                    | Value                  | Notes                                                                                    |
| ------------------------ | ---------------------- | ---------------------------------------------------------------------------------------- |
| **Bluetooth name**       | `Free3-P`              | Vendor product code, not the USB product string                                          |
| **Bluetooth address**    | `EC:BD:E4:D3:F7:97`    | Use with `blueutil --connect` / `--info`                                                 |
| **Bluetooth Vendor ID**  | `0x04E8` (1256)        | **Samsung Electronics** — cheap BT modules borrow this VID for Mac/iOS HID compatibility |
| **Bluetooth Product ID** | `0x7021` (28705)       | Generic HID keyboard variant under Samsung's space                                       |
| **Firmware Version**     | `0.1.11`               | Reported by macOS Bluetooth stack                                                        |
| **Minor Type**           | `Keyboard`             | macOS treats it as keyboard                                                              |
| **Services**             | `0x800020 < HID ACL >` | **Classic Bluetooth HID**, not BLE                                                       |
| **RSSI (typical)**       | `-40 dBm`              | Excellent at desk distance                                                               |

**Why the BT VID/PID differs from USB (0x4c4a/0x4155)**: the pad's BT chip is physically separate from the USB-facing controller, and the vendor chose to use Samsung's allow-listed VID. This is harmless; Karabiner's rule just needs a second `device_if` identifier covering the BT ID pair.

## BT Firmware Has 4 Modes — We Use Mode 4

The pad firmware exposes four distinct key-emission modes over Bluetooth. Each mode maps the three physical buttons to different HID keycodes:

| Mode                    | Top                | Middle             | Bottom                  | Best For                                                                         |
| ----------------------- | ------------------ | ------------------ | ----------------------- | -------------------------------------------------------------------------------- |
| 1 (Media/Volume)        | `volume_increment` | `volume_decrement` | `spacebar` (play/pause) | Listening to music — default out of the box                                      |
| 2                       | — not explored —   |                    |                         |                                                                                  |
| 3                       | — not explored —   |                    |                         |                                                                                  |
| **4 (Page Navigation)** | `page_up`          | `page_down`        | `equal_sign`            | **Our choice** — plain keyboard keys that are rarely used, easy to remap cleanly |

**Why mode 4 is the right pick**:

1. All three keys live on the standard Keyboard HID page (0x07) — easy for Karabiner to match with plain `from.key_code`, no `simultaneous` or consumer-code gymnastics.
2. `page_up` and `page_down` are keys you rarely press on a macOS keyboard (most apps use trackpad scroll instead), so remapping them to Fn/Return doesn't collide with muscle memory.
3. `equal_sign` is the `=` key, also rarely pressed as a dedicated key — good "reserved" slot for future binding.

Mode-switching button combo: **not yet identified**. The manual/vendor listing described 4 modes but the button combo wasn't documented in a way we could decode. Attempts that did NOT work: holding all 3 keys × 5 seconds; holding top alone. If you later discover the combo, document it in this file.

## Mapping (Same UX as USB)

| Physical Button | BT emits (mode 4) | Remapped to                                                                                    | Effect                                                      |
| --------------- | ----------------- | ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| **Top**         | `page_up`         | **Single-tap** → `Fn` (after ~200ms); **Double-tap ≤200ms** → `Cmd+V` (paste)                  | Tap toggles Typeless dictation; double-tap pastes clipboard |
| **Middle**      | `page_down`       | **Single-tap** → `Shift+Return` (after ~200ms); **Double-tap ≤200ms** → `Return` (send/commit) | Newline (safe default) vs. deliberate send                  |
| **Bottom**      | `equal_sign`      | `Command+Delete`                                                                               | Delete from cursor to start of line                         |

## The Karabiner Rule (Full)

Located in `~/.config/karabiner/karabiner.json` → profile 0 → `complex_modifications.rules` → rule named `Jieli/Free3-P macro pad: ...`. Verbatim export in [`references/karabiner-rule.json`](references/karabiner-rule.json).

**Structure**: one rule, ten manipulators (the top and middle buttons each use a tap/double-tap pair per transport; bottom is a single manipulator per transport). All manipulators share the same `device_if` scoping to both USB and BT identifiers:

```json
"conditions": [{
  "type": "device_if",
  "identifiers": [
    {"vendor_id": 19530, "product_id": 16725},   // USB-C transport (Jieli)
    {"vendor_id": 1256,  "product_id": 28705}    // Bluetooth transport (Samsung-borrowed VID)
  ]
}]
```

**Manipulators** (order matters — Karabiner matches top-down, first match wins):

1. **USB top, double-tap detector** — `simultaneous` match on `left_control` + `c`, guarded by `variable_if jieli_top_tap == 1` → emit `key_code: v` + `modifiers: ["left_command"]` (paste) + reset variable to `0`
2. **USB top, first-tap handler** — `simultaneous` match on `left_control` + `c`, no variable guard → set `jieli_top_tap = 1`; `to_delayed_action` (200ms): `to_if_invoked` emits `apple_vendor_top_case_key_code: keyboard_fn` + resets variable; `to_if_canceled` just resets variable
3. **USB middle, double-tap detector** — `simultaneous` match on `left_control` + `v`, guarded by `variable_if jieli_middle_tap == 1` → emit `key_code: return_or_enter` + reset variable to `0`
4. **USB middle, first-tap handler** — `simultaneous` match on `left_control` + `v`, no variable guard → set `jieli_middle_tap = 1`; `to_delayed_action` (200ms): `to_if_invoked` emits `return_or_enter` + `modifiers: ["left_shift"]` + resets variable; `to_if_canceled` just resets variable
5. **BT top, double-tap detector** — plain match on `key_code: page_up`, guarded by `variable_if jieli_top_tap == 1` → emit `Cmd+V` + reset variable
6. **BT top, first-tap handler** — plain match on `key_code: page_up`, no variable guard → set variable + 200ms delayed Fn / reset on cancel
7. **BT middle, double-tap detector** — plain match on `key_code: page_down`, guarded by `variable_if jieli_middle_tap == 1` → emit `key_code: return_or_enter` + reset variable
8. **BT middle, first-tap handler** — plain match on `key_code: page_down`, no variable guard → set variable + 200ms delayed Shift+Return / reset on cancel
9. **USB bottom** — `simultaneous` match on `left_control` + `x` → `key_code: delete_or_backspace` + `modifiers: ["left_command"]`
10. **BT bottom** — plain match on `key_code: equal_sign` → `key_code: delete_or_backspace` + `modifiers: ["left_command"]`

Each transport's path triggers a different manipulator. The targets are identical across both transports, so user experience is transport-agnostic. The variables `jieli_top_tap` and `jieli_middle_tap` are each shared across the USB and BT transports of their respective buttons — harmless because only one transport is physically active at a time. Top and middle each have their own variable so a tap on one button cannot arm the double-tap detector on the other.

**Why the detector must come before the handler**: Karabiner evaluates manipulators top-down. When the relevant variable (`jieli_top_tap` or `jieli_middle_tap`) is already `1` (first-tap fired within the last 200ms), the detector's variable condition matches first and fires the double-tap target, canceling the pending delayed action. When the variable is `0` (default), the detector fails and execution falls through to the handler, which starts a new tap cycle. See `03-patterns.md` → "Tap vs. double-tap discrimination" for the reusable pattern in isolation, and `02-usb-wired-configuration.md#how-the-tapdouble-tap-pattern-works-top--middle-buttons` for a deeper walkthrough.

**Top-button caveat**: because the Fn keystroke fires only after the 200ms detection window expires, holding the top key produces a single delayed Fn keypress — not the sustained Fn-down state required for push-to-talk. Use Typeless's tap-to-toggle Fn mode if you adopt this rule. To restore push-to-talk, collapse the top-button pair back into a single immediate-Fn manipulator per transport.

### Handling Other BT Modes

If you ever switch the pad to mode 1 (Media/Volume) or modes 2/3, the pad's keycodes won't match the BT manipulators (5-8 in the list above), so they'll pass through to macOS normally:

- Mode 1 top (volume_increment) → macOS raises system volume as expected. Not what we want for push-to-talk, but harmless.
- Mode 1 middle (volume_decrement) → volume down.
- Mode 1 bottom (spacebar) → play/pause in whatever app has focus.

To support multiple BT modes simultaneously, just add more manipulators. E.g., `consumer_key_code: volume_increment → Fn` + `consumer_key_code: volume_decrement → Return` would give you push-to-talk in mode 1 too. Not added now since mode 4 is the chosen working mode.

## Auto-Reconnect on Sleep/Wake

**Current stance: Option C — no auto-reconnect automation added.**

The pad auto-reconnects reliably on this setup within ~6 seconds of macOS wake (verified: USB termination at 14:41:28 → Free3-P grabbed at 14:41:34). Adding sleepwatcher-based force-reconnect would be unnecessary complexity right now.

If you later observe silent mid-meeting disconnects (pad stays "paired" but "disconnected" in System Settings), revisit the three options in [`07-bluetooth-toolbox.md`](07-bluetooth-toolbox.md#auto-reconnect-on-sleepwake):

- **Option A** — Extend the upstream `ssh-tunnel-companion` plugin's wakeup script to also call `blueutil --connect EC-BD-E4-D3-F7-97`
- **Option B** — Use Hammerspoon's `hs.caffeinate.watcher` (Hammerspoon already installed, not currently running)
- **Option C** — Skip (current)

## Switching Modes Between USB-C and Bluetooth

**USB-C → BT**: unplug USB-C. macOS auto-terminates the USB transport; BT reconnects in 5-6 seconds. Karabiner re-grabs via the BT VID/PID identifier. The BT manipulators (5-8: page_up/page_down pairs and equal_sign) become active in mode 4.

**BT → USB-C**: plug in USB-C. macOS prefers USB; BT stays paired but disconnected. The USB manipulators (1-4: Ctrl+C/V pairs and Ctrl+X) become active.

**Both attached simultaneously**: don't. macOS may double-emit. The pad's firmware may stop responding to BT while USB is plugged in (cheap-pad charging mode).

## Diagnostic Commands

```bash
# Is the pad connected over BT right now?
blueutil --info EC-BD-E4-D3-F7-97

# Force reconnect (if "paired" but "not connected")
blueutil --connect EC-BD-E4-D3-F7-97

# Karabiner's view of the BT pad
karabiner_cli --list-connected-devices | jq '.[] | select(.product == "Free3-P")'

# Confirm Karabiner is grabbing
grep "Free3-P" /var/log/karabiner/core_service.log | tail -2

# Live event inspection: open Karabiner-EventViewer → Main tab → press pad buttons
open -a "Karabiner-EventViewer"
```

## Known Unknowns

- **How to switch between the 4 BT modes** — combo not yet identified. If the pad's manual/box/listing is found, document the combo here.
- **What modes 2 and 3 emit** — unexplored. Would need mode-switching first.
- **Battery behavior** — the pad has no visible battery indicator. Likely coin-cell or small Li-Po. Check `blueutil --info` periodically for battery percentage if advertised.
- **Multi-host BT switching** — if the pad supports pairing with multiple hosts simultaneously, that's not documented here. Most cheap pads are single-host.
