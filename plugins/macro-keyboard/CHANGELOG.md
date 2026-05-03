# Changelog

All notable changes to the `macro-keyboard` plugin are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning tracks the cc-skills marketplace (synchronized major version across all plugins).

## Unreleased — 2026-05-02

### Changed — Bottom button: tap/double-tap added, then revised, mechanism made transport-asymmetric

Three rapid iterations on the bottom button on the same day:

**Iteration 1 (morning, 13:07)** — Added Karabiner-side tap/double-tap discrimination on the bottom button (matching the established top + middle pattern). Single-tap → `down_arrow` cursor nudge; double-tap → `Cmd+Delete` line-clear. New runtime variable `jieli_bottom_tap`. Manipulator count: 10 → 12. Backup: `~/.config/karabiner/karabiner.json.bak.before-bottom-tap-20260502-130639`.

**Iteration 2 (afternoon, 14:18)** — Revised targets to `up_arrow` (single tap) / `down_arrow` (double tap). Both directions are reversible navigation — pick whichever you reach for more often as the single-tap. Backup: `~/.config/karabiner/karabiner.json.bak.before-bottom-arrows-20260502-141718`.

**Iteration 3 (afternoon, 14:35)** — During testing, **discovered via Karabiner-EventViewer that the pad's BT firmware does its own double-tap detection on the bottom button only**. Double-tapping over Bluetooth emits `Option+Z` (not a repeated `equal_sign`), so the Karabiner-side software discrimination never fired the double-tap target. Restructured the BT bottom path: dropped the software discrimination, replaced manipulators 11 + 12 with two simple immediate-translation manipulators (`equal_sign` → `up_arrow`, `Option+Z` → `down_arrow`). USB bottom path kept its software discrimination (USB still emits `Ctrl+X` on every press). Top + middle buttons continue to use software discrimination on both transports — they're not affected by firmware-side discrimination. Manipulator count stays at 12. The variable `jieli_bottom_tap` is now used only on USB.

### Asymmetric-mechanism summary (post-iteration 3)

| Button | USB mechanism                                                                                            | BT mechanism                                                                                                                                                |
| ------ | -------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Top    | Software discrimination (Karabiner `set_variable` + `to_delayed_action`; pad emits `Ctrl+C` every press) | Software discrimination (pad emits `page_up` every press)                                                                                                   |
| Middle | Software discrimination (pad emits `Ctrl+V` every press)                                                 | Software discrimination (pad emits `page_down` every press)                                                                                                 |
| Bottom | Software discrimination (pad emits `Ctrl+X` every press)                                                 | **Firmware-decided keycode translation** (pad firmware emits `equal_sign` for single tap, `Option+Z` for double tap; Karabiner translates each immediately) |

User-facing behavior is identical (single-tap = up_arrow, double-tap = down_arrow). Only inspecting the rule reveals the asymmetry.

### Caveats

**No auto-repeat on the bottom button on either transport**: USB single-tap fires once after the 200ms detection window expires; BT firmware emits one discrete event per gesture (no key-down/key-up stream). Real macOS arrow keys auto-repeat when held; this remap does not. To restore continuous scroll on USB, collapse the pair into a single immediate-target manipulator. On BT you can't restore it — the firmware doesn't emit a stream.

**Top-button PTT-incompatibility caveat from 2026-04-24 still applies**: holding the top key won't sustain Fn-down because Fn fires only after the 200ms detection window expires. Use Typeless tap-to-toggle, not push-to-talk.

### Updated docs

- `references/raw/karabiner-rule.json` — 10 → 12 manipulators (count unchanged across iterations 2 + 3, but BT bottom manipulators became immediate translations rather than detector/handler pair). Description string now lists the asymmetric mechanisms.
- `references/02-usb-wired-configuration.md` — mapping table (bottom row now `up_arrow` / `down_arrow`), abridged JSON view's count-comment notes the 12-manipulator total and the asymmetric BT bottom mechanism, "How the tap/double-tap pattern works" section reframed for top + middle + (USB) bottom; troubleshooting rows updated for arrow-key targets; "Bottom button's Ctrl+X passes through" limitation rewritten as the universal "no key auto-repeat" caveat
- `references/08-bluetooth-configuration.md` — Status section adds **Important asymmetry** callout. Mapping table now shows `equal_sign` (single) / `Option+Z` (double) for the bottom row. Manipulator structure list (1-12) updated: items 11 + 12 are now "single-tap translator" + "double-tap translator", not detector/handler. New "Why USB and BT use different mechanisms for the bottom button" subsection explains the firmware behavior. Bottom-button caveat updated for the firmware-emits-one-event-per-gesture reality.
- `references/09-turnkey-walkthrough.md` — Full 12-manipulator JSON updated (USB bottom = software pair; BT bottom = two immediate translations). Behavior table notes the asymmetric mechanism. "Why the tap/double-tap on bottom (and why it differs by transport)" explainer added. Verification step rewritten to mention both mechanisms. Variations table refreshed for bottom button (no longer "destructive deliberate" framing — both targets are reversible). "Adapt for your pad" notes call out checking both transports for firmware-side discrimination. Credits & provenance line updated with the iteration history.
- `references/overview.md` — Current-status bullets and quick-reference mapping table reflect the asymmetric mechanism.
- `references/03-patterns.md` — Live-examples line clarifies that the BT bottom does NOT use Karabiner-side discrimination. **New pattern added**: "Translate pad-firmware-decided keycodes (no Karabiner-side discrimination)" — the recipe for the case where the pad's firmware emits two distinct keycodes for single-vs-double-tap. Anti-pattern warning's auto-repeat trap updated for the current `up_arrow` target.
- `references/04-anti-patterns.md` — **New entry**: "Assuming the pad emits the same keycode on single-tap and double-tap on every transport". Documents the 2026-05-02 surprise + the fix + the EventViewer test recipe.
- `SKILL.md` — Manipulator count math reframed (8 software-discriminated for top + middle, 2 software-discriminated for USB bottom, 2 firmware-translated for BT bottom = 12). Turnkey description updated.
- `CLAUDE.md` (plugin) — Tap-vs-double-tap section now describes both techniques (software discrimination + firmware-decided-keycode translation) with the live examples for each. File-list descriptions for `02-` / `08-` / `raw/` updated. Patterns description now lists both techniques.
- `skills/configure-macro-keyboard/CLAUDE.md` — Critical Invariants gains an 8th item documenting the asymmetric bottom-button mechanism. Recent Changes log records all three iterations. Common Edits note that the BT bottom path can NOT be tuned via `to_delayed_action_delay_milliseconds` (firmware-controlled). File table descriptions for `02-` / `08-` updated to mention the asymmetry.
- `README.md` — Turnkey TIP and Quick Example bullets reflect the new bindings + the asymmetric mechanism note.

### Live config

Applied to `~/.config/karabiner/karabiner.json` in three iterations on 2026-05-02:

- 13:07:33 — Iteration 1 (down_arrow / Cmd+Delete, software discrimination)
- 14:18:18 — Iteration 2 (up_arrow / down_arrow, software discrimination on both transports)
- 14:35:10 — Iteration 3 (up_arrow / down_arrow, asymmetric mechanism: USB software, BT firmware-translation)

Karabiner reloaded cleanly each time. Functional verification done by user via Karabiner-EventViewer + real-app testing after iteration 3.

## 2026-04-24

### Changed — Top button gains tap/double-tap pair

Extended the tap-vs-double-tap pattern from the middle button to the top button in the live MacroKeyBot rule. The top button now does:

- **Single-tap** (after ~200ms) → `Fn` (Apple vendor keyboard Fn) — toggles Typeless dictation
- **Double-tap** (≤200ms) → `Cmd+V` (paste)

The 6-manipulator middle-button-only tap/double-tap rule grew to 10 manipulators (top × 2 transports + middle × 2 transports + bottom × 2 transports, with the top and middle each using a 2-manipulator detector/handler pair per transport).

**New runtime variable**: `jieli_top_tap` (parallels `jieli_middle_tap`). Each button needs its own variable to prevent a tap on one from arming the double-tap detector on another.

**Caveat (documented in `02-usb-wired-configuration.md`, `08-bluetooth-configuration.md`, `09-turnkey-walkthrough.md`, `03-patterns.md`)**: because Fn now fires only after the 200ms detection window expires, this rule is **incompatible with Typeless's push-to-talk mode** (hold-to-talk). It assumes Typeless is configured as tap-to-toggle Fn. To restore PTT, collapse the top-button pair back into the original single-manipulator immediate-Fn form (see git history of `references/raw/karabiner-rule.json` from before this change).

### Updated docs

- `references/raw/karabiner-rule.json` — 8 → 10 manipulators with new top-button pair on USB (Ctrl+C) and BT (page_up)
- `references/02-usb-wired-configuration.md` — mapping table, abridged JSON view, "How the tap/double-tap pattern works" section now covers both top + middle, troubleshooting table gains top-button-specific rows, PTT caveat added
- `references/08-bluetooth-configuration.md` — mapping table, manipulator structure (numbered list), other-modes and switching-modes references updated to the new manipulator layout, PTT caveat added
- `references/09-turnkey-walkthrough.md` — full 10-manipulator JSON, behavior table, adapt-for-your-pad notes (collapse-to-PTT recipe), variations table for top button, verification step's expected manipulator count, PTT caveat near the top
- `references/overview.md` — current-status bullets and quick-reference mapping table
- `references/03-patterns.md` — live-examples line now lists both top + middle pairs, anti-pattern warning concrete-references the top-button PTT trap with a recipe to collapse back
- `references/07-bluetooth-toolbox.md` — pairing-day Step 3 reworded for tap-toggle vs PTT
- `SKILL.md` — manipulator count math, turnkey description
- `CLAUDE.md` (plugin) — tap-vs-double-tap section names both live examples, file-list descriptions for `02-` / `08-` / `raw/`
- `README.md` — turnkey TIP, Quick Example bullets, manipulator count

### Live config

Applied to `~/.config/karabiner/karabiner.json` on 2026-04-24 (backup at `~/.config/karabiner/karabiner.json.bak.before-top-tap-20260424-143528`). Karabiner reloaded cleanly; functional verification pending (Typeless toggle on single-tap, paste on double-tap).

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
