# configure-macro-keyboard Skill

> End-to-end Karabiner workflow for cheap 3-key USB-C/Bluetooth macro pads. Identifies the device, writes a device-scoped Karabiner rule, handles dual-transport (USB + BT) configurations, and packages reusable patterns (`simultaneous` matchers, tap-vs-double-tap pairs, `device_if`).

**Hub**: [Plugin CLAUDE.md](../../CLAUDE.md) | **Sibling skills**: [emit-fn-key-on-macos](../emit-fn-key-on-macos/CLAUDE.md) · [diagnose-hid-keycodes](../diagnose-hid-keycodes/CLAUDE.md)

## What This Skill Owns

| File                                                                                            | Role                                                                                             | Edit policy                                                                                                                                                      |
| ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `SKILL.md`                                                                                      | User-invocable instructions for configuring a new pad. Loaded into context when the skill fires. | Edit when the 5-step workflow changes shape. Keep terse — references carry the depth.                                                                            |
| `references/raw/karabiner-rule.json`                                                            | **SSoT for the live MacroKeyBot rule.** Verbatim 10-manipulator export.                          | Always update in lockstep with `~/.config/karabiner/karabiner.json`. The repo file is the source — patch live config from it, not the other way around.          |
| `references/02-usb-wired-configuration.md`                                                      | Live USB rule walkthrough + tap/double-tap mechanism + troubleshooting matrix.                   | Keep mapping table, abridged JSON, and "How the tap/double-tap pattern works" section in sync with `raw/karabiner-rule.json`.                                    |
| `references/08-bluetooth-configuration.md`                                                      | Live BT rule walkthrough (mode-4 firmware) + numbered manipulator structure.                     | When the rule changes, update both the structure list and the "Switching Modes" / "Other BT Modes" sections that reference manipulator numbers.                  |
| `references/09-turnkey-walkthrough.md`                                                          | Copy-paste-ready 30-minute MacroKeyBot recipe with VID/PID placeholders.                         | The full JSON in this file is meant to be lifted as-is. Keep it equivalent to `raw/karabiner-rule.json` modulo the `macrokeybot_*` vs `jieli_*` variable rename. |
| `references/03-patterns.md`                                                                     | Reusable techniques (live examples are device-specific; the patterns are not).                   | When a new live example proves a pattern, add it under the pattern's "Live examples" line. Don't fork patterns per device.                                       |
| `references/04-anti-patterns.md`                                                                | Dead-ends + historical narrative of the original Ctrl+C → Fn rule.                               | Append-only. Don't rewrite history when the rule evolves.                                                                                                        |
| `references/overview.md`                                                                        | TL;DR mapping table + device signatures.                                                         | First place to update when the live mapping changes.                                                                                                             |
| `references/05-bluetooth-roadmap.md`                                                            | Historical pre-pairing roadmap.                                                                  | Don't update — frozen in time.                                                                                                                                   |
| `references/06-bluetooth-landscape-survey.md`                                                   | 2026 ecosystem context.                                                                          | Update only on major ecosystem shifts.                                                                                                                           |
| `references/07-bluetooth-toolbox.md`                                                            | Tier-ranked FOSS BT tools.                                                                       | Update when a tool is replaced or its install command changes.                                                                                                   |
| `references/raw/{lsusb-verbose,system-profiler,system-profiler-bluetooth,ioreg-hid-device}.txt` | Frozen hardware dumps from 2026-04-21.                                                           | Re-capture only if the pad firmware or macOS HID stack changes meaningfully.                                                                                     |
| `references/raw/karabiner-bluetooth-device.json`                                                | Karabiner's view of the paired Free3-P.                                                          | Re-capture when the BT pairing identity changes.                                                                                                                 |

## Critical Invariants

1. **`raw/karabiner-rule.json` and `~/.config/karabiner/karabiner.json` MUST stay in sync.** When updating the rule, edit the repo file first, then patch the live config (the live config has 4 sibling rules — never replace the whole file). Backup the live config before patching: `cp ~/.config/karabiner/karabiner.json ~/.config/karabiner/karabiner.json.bak.$(date +%Y%m%d-%H%M%S)`.
2. **Manipulator counts are doc-load-bearing.** The number "10" appears in `02-`, `08-`, `09-`, `overview.md`, `SKILL.md`, plugin `CLAUDE.md`, and `README.md`. When the count changes, grep all docs and update consistently — `grep -rn "10 manipulator\|10-manipulator\|ten manipulator" plugins/macro-keyboard/`.
3. **Each tap/double-tap button needs its own variable name.** Live config uses `jieli_top_tap` and `jieli_middle_tap`. Sharing a variable across buttons would let a tap on one arm the double-tap detector on another.
4. **`device_if` is non-optional on every manipulator.** Dropping it remaps the MacBook's built-in keyboard and breaks Apple's native keys. Both VID/PID identifiers (USB + BT) must be in the `identifiers` array.
5. **`apple_vendor_top_case_key_code: keyboard_fn` is the only path to real Fn.** `key_code: fn` and `modifiers: ["fn"]` are no-ops. See sibling skill `emit-fn-key-on-macos/CLAUDE.md` for the why.
6. **The top-button tap/double-tap is incompatible with Typeless push-to-talk.** Fn fires only after the 200ms detection window expires, so press-and-hold doesn't sustain Fn-down. The live config assumes Typeless is in tap-to-toggle mode. To restore PTT, collapse the top-button pair into a single immediate-Fn manipulator per transport (recipe in `09-turnkey-walkthrough.md`'s "Adapt for your pad" bullet).

## Recent Changes

- **2026-04-24** — Top button gained tap/double-tap pair (single → Fn for Typeless toggle, double → `Cmd+V` paste). Manipulator count: 8 → 10. New variable: `jieli_top_tap`. PTT-incompatibility caveat documented across all relevant references. Live config backup: `~/.config/karabiner/karabiner.json.bak.before-top-tap-20260424-143528`.
- **2026-04-23** — Middle button gained tap/double-tap pair (single → `Shift+Return`, double → `Return`). Initial introduction of the `set_variable` + `to_delayed_action` pattern.
- **2026-04-21** — Bluetooth support added (mode-4 firmware: page_up / page_down / equal_sign). Same rule, dual `device_if` identifiers.

## Common Edits

- **Change a button's target keycode**: edit `to[0]` in the relevant manipulator(s) in `raw/karabiner-rule.json`, then patch the live config. For tap/double-tap pairs, the single-tap target is in `to_delayed_action.to_if_invoked[0]` and the double-tap target is in the detector manipulator's `to[0]`.
- **Tune the double-tap window**: change `parameters.basic.to_delayed_action_delay_milliseconds` (default 200ms). The two pairs (top + middle) tune independently.
- **Add a 4th button binding**: append a manipulator with the new `from` keycode. Reuse the same `device_if` identifiers.
- **Support a new pad**: add its USB VID/PID and BT VID/PID to every manipulator's `device_if.identifiers` array. If the pad emits different keycodes, add transport-specific manipulators (don't try to alias).

## Validation

```bash
# Rule JSON parses + manipulator count is what you expect
/usr/bin/env python3 -c "import json; d=json.load(open('plugins/macro-keyboard/skills/configure-macro-keyboard/references/raw/karabiner-rule.json')); print(len(d['manipulators']))"

# Live config matches
/usr/bin/env python3 -c "
import json
live = json.load(open('/Users/<you>/.config/karabiner/karabiner.json'))
for r in live['profiles'][0]['complex_modifications']['rules']:
    if r['description'].startswith('Jieli/Free3-P'):
        print(len(r['manipulators']))
"

# Karabiner reloaded the file
tail -5 /var/log/karabiner/core_service.log
# Look for: "core_configuration is updated."
```
