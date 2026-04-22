# macro-keyboard

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-3-blue.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

Configure cheap 3-key USB-C/Bluetooth macro pads on macOS with Karabiner-Elements. Covers Fn emission, device-scoped remaps, HID diagnostics, and dual-transport (USB + Bluetooth) rules for pads whose BT firmware emits different keycodes than USB.

> [!NOTE]
> This plugin was distilled from live work on a Jieli/Free3-P 3-key pad (VID `0x4c4a` USB / `0x04E8` BT). The patterns apply to any cheap HID pad from AliExpress or Amazon — Jieli, Realtek, CH57x — that cannot be flashed with QMK/VIA/Vial.

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

## Quick Example: Jieli/Free3-P

After pairing + USB plug-in:

```bash
# 1. Identify the device
ioreg -p IOUSB -l -w 0 | grep -A 20 "USB Composite Device"
# → VID 0x4c4a, PID 0x4155 (USB)
# → BT: pair via System Settings; signature 0x04E8 / 0x7021 / "Free3-P"

# 2. What does the top button emit?
# Create a rule with "ignore": true, press the button, watch Karabiner-EventViewer
# → USB: Ctrl+C (one HID report) → requires simultaneous matcher
# → BT mode 4: page_up (plain key)

# 3. Write the rule
#    ~/.config/karabiner/karabiner.json → complex_modifications.rules → append
#    One rule, device_if covering BOTH VID/PIDs, six manipulators (3 buttons × 2 transports)

# 4. Verify the grab
karabiner_cli --list-connected-devices | jq '.[] | select(.product == "Free3-P")'
```

Full JSON exports live in `skills/configure-macro-keyboard/references/raw/karabiner-rule.json`.

## The Five Traps This Plugin Documents

Five concrete traps the plugin's skills and references walk you through — all hit live on a Jieli/Free3-P pad:

1. Single-report modifier+key combos (default Karabiner `mandatory` misses them) → use `simultaneous`
2. Different VID/PID over Bluetooth than USB (Samsung-borrowed `0x04E8`) → one `device_if` with both identifiers
3. `CGEventPost` cannot emit real Fn → only Karabiner's DriverKit path works
4. Hidden BT firmware modes emit different keycodes per mode → diagnose all modes, pick the one with rarest keys
5. Sudo TCC.db audits trigger Touch ID → use `karabiner_cli --list-connected-devices` non-sudo

Full per-trap root cause + fix in [`CLAUDE.md`](./CLAUDE.md#why-this-plugin-exists) and full dead-end catalog in [`skills/configure-macro-keyboard/references/04-anti-patterns.md`](./skills/configure-macro-keyboard/references/04-anti-patterns.md).

## Platform Support

| Platform    | Status                                                                                                                      |
| ----------- | --------------------------------------------------------------------------------------------------------------------------- |
| macOS 13+   | ✅ Supported                                                                                                                |
| macOS 12    | ⚠️ Untested                                                                                                                 |
| Linux       | ❌ Karabiner is macOS-only. Use `hidutil` + `input-remapper` / QMK flashing instead (different skill — not in this plugin). |
| Windows/WSL | ❌ Not supported                                                                                                            |

## License

MIT
