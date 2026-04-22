# macro-keyboard Plugin

> Configure cheap 3-key USB-C/Bluetooth macro pads on macOS via Karabiner-Elements. Covers Fn emission (which BTT / hidutil cannot do), device-scoped remaps that don't touch the MacBook's built-in keyboard, HID diagnostic workflows, and dual-transport (USB + Bluetooth) rules for pads whose BT firmware emits different keycodes than USB.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [plugins/CLAUDE.md](../CLAUDE.md)

## Why This Plugin Exists

Generic "remap my keyboard" plugins (Karabiner skills bundled in other marketplaces, QMK/VIA, BTT) all assume flashable firmware or standard well-known HIDs. Cheap Jieli / Realtek / CH57x macro pads from AliExpress:

1. Ship with a fixed HID report descriptor — no QMK/VIA/Vial flashing possible.
2. Emit hardcoded keycode combos (e.g. `Ctrl+C`, `Ctrl+V`) out of the box — wrong if you want Fn or Return.
3. Often have **different VID/PID over Bluetooth** than over USB (and cheap pads borrow Samsung's VID to get macOS-friendly), so a single rule scoped to "USB Jieli" silently stops working when you unplug.
4. Emit modifier+key in **one HID report**, which breaks Karabiner's default sequential `mandatory` matcher and requires `simultaneous` with `detect_key_down_uninterruptedly: true`.
5. **Cannot** emit real Fn from userland via `CGEventPost` — Typeless / macOS dictation keys need a real `kCGEventFlagMaskSecondaryFn` that only DriverKit-backed remappers (Karabiner) can produce.

All five traps were hit and solved during the live Jieli/Free3-P work captured here. The plugin packages the reusable patterns + a device-specific worked example.

## Skills

| Skill                                                                  | When to Use                                                                                                 |
| ---------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| [configure-macro-keyboard](./skills/configure-macro-keyboard/SKILL.md) | End-to-end: identify device → write Karabiner rule → scope to the device → handle USB + BT in the same rule |
| [emit-fn-key-on-macos](./skills/emit-fn-key-on-macos/SKILL.md)         | Specific subtask — emit real Fn (for Typeless push-to-talk, macOS dictation, etc.); covers why BTT fails    |
| [diagnose-hid-keycodes](./skills/diagnose-hid-keycodes/SKILL.md)       | Find out what a mystery HID button emits — `ignore: true` diagnostic rule + Karabiner-EventViewer + Quartz  |

## Worked Example: Jieli/Free3-P 3-Key Pad

The device-specific config lives under `configure-macro-keyboard/references/`:

- `overview.md` — TL;DR of device signatures + mapping table
- `01-hardware-identification.md` — VID/PID, HID descriptor decode, chip family inference
- `02-usb-wired-configuration.md` — live USB rule with `simultaneous: [Ctrl, C/V/X]` matchers
- `03-patterns.md` — reusable techniques (`simultaneous` vs `mandatory`, `device_if`, Quartz capture, `ignore:true`)
- `04-anti-patterns.md` — dead-ends (BTT `CGEventPost`, hidutil combos, QMK/VIA on Jieli, Touch-ID-triggering audits)
- `05-bluetooth-roadmap.md` — historical pre-pairing plan
- `06-bluetooth-landscape-survey.md` — 2026 macro-pad ecosystem survey
- `07-bluetooth-toolbox.md` — tier-ranked FOSS tools for BT control on macOS
- `08-bluetooth-configuration.md` — live BT rule with mode-4 firmware (page_up/page_down/equal_sign)
- `raw/` — verbatim `lsusb -v`, `system_profiler`, `ioreg`, and Karabiner exports captured on the development laptop 2026-04-21

## Dependencies

| Tool                  | Install                                  | Notes                                                                               |
| --------------------- | ---------------------------------------- | ----------------------------------------------------------------------------------- |
| Karabiner-Elements    | `brew install --cask karabiner-elements` | Required. DriverKit VirtualHIDDevice is the only userland path to real Fn on macOS. |
| karabiner_cli         | bundled with Karabiner                   | Non-sudo audits of grabbed devices — avoids Touch-ID on TCC.db queries.             |
| blueutil              | `brew install blueutil`                  | BT force-connect + info queries. Not required but strongly recommended.             |
| Karabiner-EventViewer | bundled with Karabiner                   | Live HID event inspection.                                                          |

## Link Conventions

Skill-internal links use relative paths: `[X](./references/X.md)`. Cross-plugin links go through the marketplace root: `[itp](../../itp/CLAUDE.md)`. External links use full URLs.

## Upstream / Downstream

- **Upstream source** (historical evolution): `~/own/amonic/docs/macro-keyboard/` — the working directory on the development laptop where this skill was built live. The amonic spoke now points here as the canonical reference.
- **Downstream**: any future pad (different VID/PID, different keycode firmware) can be added as a new worked example under `configure-macro-keyboard/references/`. Reuse the pattern docs (`03-patterns.md`, `04-anti-patterns.md`) verbatim.
