# macro-keyboard

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-3-blue.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

Configure cheap 3-key USB-C/Bluetooth macro pads on macOS with Karabiner-Elements. Covers Fn emission, device-scoped remaps, HID diagnostics, dual-transport (USB + Bluetooth) rules for pads whose BT firmware emits different keycodes than USB, and the tap-vs-double-tap pattern for giving a single button two behaviors.

> [!NOTE]
> This plugin was distilled from live work on a Jieli/Free3-P 3-key pad (VID `0x4c4a` USB / `0x04E8` BT). The patterns apply to any cheap HID pad from AliExpress or Amazon — Jieli, Realtek, CH57x — that cannot be flashed with QMK/VIA/Vial.

> [!TIP]
> **Want the turnkey recipe?** → [`skills/configure-macro-keyboard/references/09-turnkey-walkthrough.md`](./skills/configure-macro-keyboard/references/09-turnkey-walkthrough.md) — copy-paste-ready 30-minute walkthrough for a ~$10 pad with tap-vs-double-tap on top (Fn for Typeless toggle / Cmd+V paste), tap-vs-double-tap safe-Return on middle (Shift+Return / Return), Command+Delete on bottom, across USB + Bluetooth.

## What You Get

| Skill                      | Purpose                                                                                                    |
| -------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `configure-macro-keyboard` | End-to-end workflow: identify the device, write a Karabiner rule, scope it to that device, handle USB + BT |
| `emit-fn-key-on-macos`     | Emit real Fn (for Typeless push-to-talk, macOS dictation, etc.) — the one thing BTT / hidutil cannot do    |
| `diagnose-hid-keycodes`    | Find out what a mystery button emits using Karabiner's `ignore: true` diagnostic + EventViewer + Quartz    |

## Installation

### Option 1: Plugin Marketplace (Recommended)

```bash
/plugin marketplace add terrylica/cc-skills
/plugin install cc-skills@macro-keyboard
```

### Option 2: Settings Configuration

Add to `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "cc-skills": {
      "source": { "source": "github", "repo": "terrylica/cc-skills" }
    }
  }
}
```

### Option 3: Manual

```bash
git clone git@github.com:terrylica/cc-skills.git /tmp/cc-skills
cp -r /tmp/cc-skills/plugins/macro-keyboard/skills/* ~/.claude/skills/
```

## Prerequisites

| Tool               | Install                                  | Why                                                                                |
| ------------------ | ---------------------------------------- | ---------------------------------------------------------------------------------- |
| Karabiner-Elements | `brew install --cask karabiner-elements` | Required. Only userland path to real Fn on macOS (via DriverKit VirtualHIDDevice). |
| blueutil           | `brew install blueutil`                  | Optional. BT force-connect + info queries during pairing.                          |

**macOS permissions**: Karabiner needs Input Monitoring, Accessibility, and (on Sequoia+) a Login Items toggle for its privileged daemon — the skill will remind you.

## Quick Example: Jieli/Free3-P (MacroKeyBot)

After pairing + USB plug-in:

```bash
# 1. Identify the device
ioreg -p IOUSB -l -w 0 | grep -A 20 "USB Composite Device"
# → VID 0x4c4a, PID 0x4155 (USB)
# → BT: pair via System Settings; signature 0x04E8 / 0x7021 / "Free3-P"

# 2. What does each button emit?
# Create a rule with "ignore": true, press the buttons, watch Karabiner-EventViewer
# → USB: Ctrl+C / Ctrl+V / Ctrl+X (one HID report each) → requires simultaneous matcher
# → BT mode 4: page_up / page_down / equal_sign (plain keys)

# 3. Write the rule
#    ~/.config/karabiner/karabiner.json → complex_modifications.rules → append
#    One rule, device_if covering BOTH VID/PIDs, 10 manipulators:
#    - top tap/double-tap pair (USB + BT) → Fn (Typeless toggle) vs. Cmd+V (paste)
#    - middle tap/double-tap pair (USB + BT) → Shift+Return vs. Return
#    - bottom (USB + BT) → Command+Delete
#    (8 manipulators if you drop the top double-tap and bind Fn directly;
#     6 manipulators if you also drop the middle tap/double-tap.)

# 4. Verify the grab
karabiner_cli --list-connected-devices | jq '.[] | select(.product == "Free3-P")'
```

Full JSON export: [`skills/configure-macro-keyboard/references/raw/karabiner-rule.json`](./skills/configure-macro-keyboard/references/raw/karabiner-rule.json). Copy-paste-ready recipe (with VID/PID placeholders you swap for your own hardware): [`skills/configure-macro-keyboard/references/09-turnkey-walkthrough.md`](./skills/configure-macro-keyboard/references/09-turnkey-walkthrough.md).

## The Traps This Plugin Documents

Six concrete traps the plugin's skills and references walk you through — all hit live on a Jieli/Free3-P pad:

1. Single-report modifier+key combos (default Karabiner `mandatory` misses them) → use `simultaneous`
2. Different VID/PID over Bluetooth than USB (Samsung-borrowed `0x04E8`) → one `device_if` with both identifiers
3. `CGEventPost` cannot emit real Fn → only Karabiner's DriverKit path works
4. Hidden BT firmware modes emit different keycodes per mode → diagnose all modes, pick the one with rarest keys
5. Sudo TCC.db audits trigger Touch ID → use `karabiner_cli --list-connected-devices` non-sudo
6. One physical button needs to emit two different things → `set_variable` + `to_delayed_action` tap-vs-double-tap pair; the only Karabiner-native way to discriminate without `to_if_held_down` (which comes with its own Fn-specific gotchas — see anti-patterns)

Full per-trap root cause + fix in [`CLAUDE.md`](./CLAUDE.md#why-this-plugin-exists) and full dead-end catalog in [`skills/configure-macro-keyboard/references/04-anti-patterns.md`](./skills/configure-macro-keyboard/references/04-anti-patterns.md). The tap-vs-double-tap pattern lives as a standalone reusable recipe in [`03-patterns.md`](./skills/configure-macro-keyboard/references/03-patterns.md#pattern-tap-vs-double-tap-discrimination-on-one-button).

## Platform Support

| Platform    | Status                                                                                                                      |
| ----------- | --------------------------------------------------------------------------------------------------------------------------- |
| macOS 13+   | ✅ Supported                                                                                                                |
| macOS 12    | ⚠️ Untested                                                                                                                 |
| Linux       | ❌ Karabiner is macOS-only. Use `hidutil` + `input-remapper` / QMK flashing instead (different skill — not in this plugin). |
| Windows/WSL | ❌ Not supported                                                                                                            |

## License

MIT
