# Bluetooth Configuration (Live)

How the pad is configured over Bluetooth, paralleling [`02-usb-wired-configuration.md`](02-usb-wired-configuration.md). Verified working 2026-04-21.

## Status

✅ **Pad works over Bluetooth with identical user-facing behavior as USB-C.** Top = Typeless push-to-talk, middle = Return, bottom = pass-through. Same Karabiner rule handles both transports plus the BT mode-4 firmware quirks.

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

| Physical Button | BT emits (mode 4) | Remapped to      | Effect                              |
| --------------- | ----------------- | ---------------- | ----------------------------------- |
| **Top**         | `page_up`         | `Fn`             | Typeless push-to-talk               |
| **Middle**      | `page_down`       | `Return`         | Insert newline                      |
| **Bottom**      | `equal_sign`      | `Command+Delete` | Delete from cursor to start of line |

## The Karabiner Rule (Full)

Located in `~/.config/karabiner/karabiner.json` → profile 0 → `complex_modifications.rules` → rule named `Jieli/Free3-P macro pad: ...`. Verbatim export in [`references/karabiner-rule.json`](references/karabiner-rule.json).

**Structure**: one rule, six manipulators, each with the same `device_if` scoping to both USB and BT identifiers:

```json
"conditions": [{
  "type": "device_if",
  "identifiers": [
    {"vendor_id": 19530, "product_id": 16725},   // USB-C transport (Jieli)
    {"vendor_id": 1256,  "product_id": 28705}    // Bluetooth transport (Samsung-borrowed VID)
  ]
}]
```

**Manipulators**:

1. **USB mode** — `simultaneous` match on `left_control` + `c` → `apple_vendor_top_case_key_code: keyboard_fn`
2. **USB mode** — `simultaneous` match on `left_control` + `v` → `key_code: return_or_enter`
3. **USB mode** — `simultaneous` match on `left_control` + `x` → `key_code: delete_or_backspace` + `modifiers: ["left_command"]` (Command+Delete)
4. **BT mode 4** — plain match on `key_code: page_up` → `apple_vendor_top_case_key_code: keyboard_fn`
5. **BT mode 4** — plain match on `key_code: page_down` → `key_code: return_or_enter`
6. **BT mode 4** — plain match on `key_code: equal_sign` → `key_code: delete_or_backspace` + `modifiers: ["left_command"]` (Command+Delete)

Each transport's path triggers a different manipulator. The target (Fn or Return) is identical across both transports, so user experience is transport-agnostic.

### Handling Other BT Modes

If you ever switch the pad to mode 1 (Media/Volume) or modes 2/3, the pad's keycodes won't match manipulators 3 or 4, so they'll pass through to macOS normally:

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

**USB-C → BT**: unplug USB-C. macOS auto-terminates the USB transport; BT reconnects in 5-6 seconds. Karabiner re-grabs via the BT VID/PID identifier. Manipulators 3 and 4 (page_up/page_down) become active in mode 4.

**BT → USB-C**: plug in USB-C. macOS prefers USB; BT stays paired but disconnected. Manipulators 1 and 2 (Ctrl+C/V) become active.

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
