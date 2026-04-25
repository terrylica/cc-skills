# Macro Keyboard Module

Dedicated documentation for the 3-key USB-C/Bluetooth macro pad, covering hardware identification, current configuration, patterns and anti-patterns, and the roadmap for Bluetooth enablement.

## Current Status

- **USB-C wired mode**: ✅ working. Remapped via Karabiner so TOP is a tap/double-tap pair (single-tap = Fn for Typeless dictation toggle, double-tap = Cmd+V paste), MIDDLE is a tap/double-tap pair (single-tap = Shift+Return newline, double-tap = Return send), BOTTOM is Command+Delete (delete-to-start-of-line). See [`02-usb-wired-configuration.md`](02-usb-wired-configuration.md).
- **Bluetooth mode**: ✅ working on firmware mode 4 (page_up / page_down / equal_sign). Same Karabiner rule extended with parallel BT manipulators — page_up→tap/double-tap pair (Fn / Cmd+V), page_down→tap/double-tap pair (Shift+Return / Return), equal_sign→Command+Delete. See [`08-bluetooth-configuration.md`](08-bluetooth-configuration.md).

## Contents

| File                                                                   | What's Inside                                                                                                                                                                                                                   |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`01-hardware-identification.md`](01-hardware-identification.md)       | Manufacturer, VID/PID, serial, USB interface structure, HID descriptor decoded, chip-family inference, why the device identifies as "USB Composite Device"                                                                      |
| [`02-usb-wired-configuration.md`](02-usb-wired-configuration.md)       | Current Karabiner rule, exact JSON, behavior table, why Karabiner vs. BTT, step-by-step change instructions, troubleshooting, revert recipes                                                                                    |
| [`03-patterns.md`](03-patterns.md)                                     | Re-usable techniques that worked: `simultaneous` vs `mandatory` modifiers, device-scoped rules, Quartz window ID capture, `ignore:true` for un-grabbing, Apple vendor Fn encoding                                               |
| [`04-anti-patterns.md`](04-anti-patterns.md)                           | Dead-ends to avoid: BTT `CGEventPost` for Fn, hidutil for collision-scoped remaps, VIA/Vial on Jieli firmware, `{"any": "key_code"}` at top level, assuming button-to-keycode without verification, Touch-ID-triggering audits  |
| [`05-bluetooth-roadmap.md`](05-bluetooth-roadmap.md)                   | Upcoming work: pairing, mode switch, how to identify the BT HID peripheral, preserving existing Karabiner rule across transport types                                                                                           |
| [`06-bluetooth-landscape-survey.md`](06-bluetooth-landscape-survey.md) | 2026 ecosystem survey: form factors, brands (Stream Deck, Loupedeck, ZMK/QMK/Vial boards, AliExpress Jieli/CH57x), BLE vs Classic HID, latency, battery, reconnect patterns, firmware options                                   |
| [`07-bluetooth-toolbox.md`](07-bluetooth-toolbox.md)                   | Evaluated + spiked FOSS tools for BT control on this Mac: tier-ranked `blueutil` / `sleepwatcher` / `Hammerspoon` / `bleak` / `LightBlue` / `PacketLogger`, install state, caveats (CoreBluetooth HID lock), pairing-day recipe |
| [`08-bluetooth-configuration.md`](08-bluetooth-configuration.md)       | Live BT config: Free3-P device signature (Samsung-borrowed VID 0x04E8/0x7021), 4 firmware modes (we use mode 4: page_up/page_down/equal_sign), extended Karabiner rule with USB + BT manipulators, switching between transports |
| [`references/`](references/)                                           | Verbatim hardware dumps captured 2026-04-21: full `lsusb -v` output, `system_profiler` (USB tree + BT metadata), `ioreg` HID device entry, current Karabiner rule export with USB + BT manipulators                             |

## Quick Reference

**Device signatures** (use these values when writing any new rule or tool):

| Transport | Vendor ID        | Product ID       | Name                   | Notes                                                         |
| --------- | ---------------- | ---------------- | ---------------------- | ------------------------------------------------------------- |
| USB-C     | `0x4c4a` (19530) | `0x4155` (16725) | `USB Composite Device` | Jieli Technology; serial `C1207062.`                          |
| Bluetooth | `0x04E8` (1256)  | `0x7021` (28705) | `Free3-P`              | Samsung-borrowed VID; MAC `EC:BD:E4:D3:F7:97`; Classic BT HID |

**Current button mapping** — same user-facing behavior across both transports:

| Physical | USB-C emits | BT mode-4 emits | Effect after Karabiner                                                                                          |
| -------- | ----------- | --------------- | --------------------------------------------------------------------------------------------------------------- |
| Top      | `Ctrl+C`    | `page_up`       | **Single-tap** = `Fn` (Typeless toggle, ~200ms after release); **Double-tap ≤200ms** = `Cmd+V` (paste)          |
| Middle   | `Ctrl+V`    | `page_down`     | **Single-tap** = `Shift+Return` (newline, ~200ms after release); **Double-tap ≤200ms** = `Return` (send/commit) |
| Bottom   | `Ctrl+X`    | `equal_sign`    | `Command+Delete` (delete to start of line)                                                                      |

The pad's BT firmware has 4 distinct modes; we use mode 4 because its native keys (PageUp, PageDown, `=`) are rarely used on macOS and map cleanly to Fn/Return via Karabiner.

**Config file**: `~/.config/karabiner/karabiner.json` → profile 0 → `complex_modifications.rules` → rule named `Jieli/Free3-P macro pad: ...`

**Pre-change backups**: Karabiner doesn't auto-snapshot. Always back up before editing:

```bash
cp ~/.config/karabiner/karabiner.json \
   ~/.config/karabiner/karabiner.json.bak.$(date +%Y%m%d-%H%M%S)
```
