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

And once the basics work, a sixth challenge often appears: with only 3 buttons, users want more than 3 actions. The reusable trick here is:

1. **Tap-vs-double-tap discrimination** — two complementary techniques, both used by the live MacroKeyBot rule:
   - **Software discrimination** (Karabiner-side): coordinate two manipulators via `set_variable` + `to_delayed_action` sharing one `from` trigger. Single-tap target fires after a 200ms detection window expires; double-tap target fires on the second press (which cancels the pending single-tap). Used for top + middle on both transports (USB + BT) and bottom on USB. Each button needs its own variable name (`jieli_top_tap`, `jieli_middle_tap`, `jieli_bottom_tap`) to prevent cross-arming. Live examples:
     - Middle button Shift+Return / Return (2026-04-23)
     - Top button Fn / Cmd+V (2026-04-24)
     - Bottom button initial down_arrow / Cmd+Delete (2026-05-02 morning)
     - Bottom button current up_arrow / down_arrow (2026-05-02 afternoon)
   - **Firmware-decided keycode translation** (pad-firmware-side, no Karabiner discrimination): when the pad's firmware itself decides single-vs-double-tap and emits two different keycodes, Karabiner just translates each immediately — no variable, no delayed action. Used for the bottom button on BT only: pad firmware emits `equal_sign` for single tap, `Option+Z` for double tap; rule maps each to `up_arrow` / `down_arrow`. Discovered via Karabiner-EventViewer 2026-05-02. **Always check both transports of every button for firmware-side discrimination before assuming software discrimination is needed** — see [`04-anti-patterns.md`](./skills/configure-macro-keyboard/references/04-anti-patterns.md) → "Assuming the pad emits the same keycode on single-tap and double-tap on every transport".

   Both techniques + their anti-patterns (PTT-incompatibility, no-auto-repeat, firmware-discrimination assumption) are in [`03-patterns.md`](./skills/configure-macro-keyboard/references/03-patterns.md). Total: 12 manipulators in the live rule.

All six traps were hit and solved during the live Jieli/Free3-P work captured here. The plugin packages the reusable patterns + a device-specific worked example ("MacroKeyBot").

## Skills

Each skill has its own CLAUDE.md (per-skill SSoT for invariants, edit conventions, and recent-change pointers — read this before editing files inside a skill directory). The SKILL.md is the user-invocable workflow; the CLAUDE.md is the maintainer's compass.

| Skill                                                                  | When to Use                                                                                                 | Per-skill SSoT                                                                                                                    |
| ---------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| [configure-macro-keyboard](./skills/configure-macro-keyboard/SKILL.md) | End-to-end: identify device → write Karabiner rule → scope to the device → handle USB + BT in the same rule | [CLAUDE.md](./skills/configure-macro-keyboard/CLAUDE.md) — file table, critical invariants, recent changes, common-edits playbook |
| [emit-fn-key-on-macos](./skills/emit-fn-key-on-macos/SKILL.md)         | Specific subtask — emit real Fn (for Typeless push-to-talk, macOS dictation, etc.); covers why BTT fails    | [CLAUDE.md](./skills/emit-fn-key-on-macos/CLAUDE.md) — primitive vs consumer split, the `to_if_held_down`-with-Fn anti-pattern    |
| [diagnose-hid-keycodes](./skills/diagnose-hid-keycodes/SKILL.md)       | Find out what a mystery HID button emits — `ignore: true` diagnostic rule + Karabiner-EventViewer + Quartz  | [CLAUDE.md](./skills/diagnose-hid-keycodes/CLAUDE.md) — `ignore: true` discipline, Quartz vs macOS screenshot focus trap          |

## Worked Example: Jieli/Free3-P 3-Key Pad

The device-specific config lives under `configure-macro-keyboard/references/`:

- **`09-turnkey-walkthrough.md`** — **start here for replication** — copy-paste-ready 30-minute MacroKeyBot recipe for any 3-key pad, with VID/PID placeholders, complete 12-manipulator config (top + middle: software discrimination on both transports; bottom: software discrimination on USB, firmware-decided-keycode translation on BT), and variation bindings for different use cases
- `overview.md` — TL;DR of device signatures + mapping table
- `01-hardware-identification.md` — VID/PID, HID descriptor decode, chip family inference
- `02-usb-wired-configuration.md` — live USB rule with `simultaneous: [Ctrl, C/V/X]` matchers + tap/double-tap pairs on top (Fn / Cmd+V), middle (Shift+Return / Return), and bottom (up_arrow / down_arrow) buttons; cross-references the asymmetric BT bottom-button mechanism in `08-bluetooth-configuration.md`
- `03-patterns.md` — reusable techniques (`simultaneous` vs `mandatory`, `device_if`, Quartz capture, `ignore:true`, tap-vs-double-tap software discrimination, pad-firmware-decided-keycode translation)
- `04-anti-patterns.md` — dead-ends (BTT `CGEventPost`, hidutil combos, QMK/VIA on Jieli, Touch-ID-triggering audits, tap-vs-hold Fn emission)
- `05-bluetooth-roadmap.md` — historical pre-pairing plan
- `06-bluetooth-landscape-survey.md` — 2026 macro-pad ecosystem survey
- `07-bluetooth-toolbox.md` — tier-ranked FOSS tools for BT control on macOS
- `08-bluetooth-configuration.md` — live BT rule with mode-4 firmware. Top + middle use Karabiner-side software discrimination (page_up / page_down emitted on every press, same as USB). Bottom uses pad-firmware-side discrimination — `equal_sign` on single tap → `up_arrow`, `Option+Z` on double tap → `down_arrow`. Documents the asymmetry and how to detect it on a new pad.
- `raw/` — verbatim `lsusb -v`, `system_profiler`, `ioreg`, and Karabiner exports regenerated on change (currently: 12-manipulator live rule)

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
