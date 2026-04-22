# Changelog

All notable changes to the `macro-keyboard` plugin are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning tracks the cc-skills marketplace (synchronized major version across all plugins).

## [15.0.0] — 2026-04-21

### Added — Initial Release

Plugin migrated from the amonic personal automation repo (`~/own/amonic/docs/macro-keyboard/`) into the cc-skills marketplace as the canonical reusable reference for cheap 3-key USB-C/Bluetooth macro pads on macOS.

- **Three skills** covering the full workflow:
  - `configure-macro-keyboard` — end-to-end: identify device → write Karabiner rule → scope via `device_if` → handle USB + Bluetooth in one rule
  - `emit-fn-key-on-macos` — focused coverage of why only Karabiner's `apple_vendor_top_case_key_code: keyboard_fn` emits real Fn (BTT / hidutil / QMK-on-locked-firmware all fail)
  - `diagnose-hid-keycodes` — `vk_none` no-op diagnostic rule + Karabiner-EventViewer + Quartz focus-free screen capture workflow

- **Deep reference docs** under `skills/configure-macro-keyboard/references/`:
  - `overview.md` — device signatures + mapping table TL;DR
  - `01-hardware-identification.md` — VID/PID, HID descriptor decode, chip family inference
  - `02-usb-wired-configuration.md` — live USB rule with `simultaneous: [Ctrl, C/V/X]` matchers
  - `03-patterns.md` — reusable techniques (`simultaneous` vs `mandatory`, `device_if`, Quartz capture, `ignore: true`)
  - `04-anti-patterns.md` — dead-ends (BTT `CGEventPost`, hidutil combos, QMK/VIA on Jieli, Touch-ID-triggering audits)
  - `05-bluetooth-roadmap.md` — historical pre-pairing plan
  - `06-bluetooth-landscape-survey.md` — 2026 macro-pad ecosystem survey
  - `07-bluetooth-toolbox.md` — tier-ranked FOSS tools for BT control on macOS (last validated 2026-04-21)
  - `08-bluetooth-configuration.md` — live BT rule with mode-4 firmware (page_up/page_down/equal_sign)

- **Raw hardware dumps** under `skills/configure-macro-keyboard/references/raw/` (captured 2026-04-21 on the development laptop):
  - `lsusb-verbose.txt`, `system-profiler.txt`, `system-profiler-bluetooth.txt`, `ioreg-hid-device.txt`
  - `karabiner-rule.json` — verbatim export of the current working 6-manipulator rule
  - `karabiner-bluetooth-device.json` — Karabiner's view of the paired Free3-P

- **Supporting skill references**:
  - `skills/emit-fn-key-on-macos/references/failed-approaches.md` — condensed failure catalog for Fn emission attempts
  - `skills/diagnose-hid-keycodes/references/diagnostic-workflow.md` — expanded step-by-step with Case 1/2/3 edge cases (single-report combos, consumer keys, multi-interface devices)

### Post-release polish (same day)

After initial commit, a 9-reviewer consensus pass surfaced:

- Fixed `plugin.json` version to align with marketplace sibling plugins
- Registered in `plugins/CLAUDE.md` hub (was missing)
- Expanded `TRIGGERS` in all three SKILL frontmatters with user-centric phrases (BTT failure symptoms, Stream Deck alternative, bluetooth-remap, real Apple Fn)
- Trimmed `allowed-tools` to only what each skill actually uses (dropped unused `Grep`/`Glob`)
- Removed JSON `//` comment that would break copy-paste of the rule skeleton
- Rewrote `diagnose-hid-keycodes` Step 2 to remove a "Wait... actually don't..." backtrack that read as draft notes
- Added `Prerequisite Check` section to `emit-fn-key-on-macos` (Karabiner DriverKit install, Input Monitoring, Accessibility, Sequoia Login Items toggle)
- Added bidirectional `Sibling Skills` sections to all three SKILLs so discovery chains close in both directions

### Upstream provenance

All reusable patterns originated from hands-on work on a Jieli AC69xx-based Free3-P pad (2026-02 to 2026-04). The original repo (`~/own/amonic/docs/macro-keyboard/`) now serves as a device-specific config journal for the development laptop; this plugin is the canonical reusable reference for any cheap 3-key HID pad on macOS.
