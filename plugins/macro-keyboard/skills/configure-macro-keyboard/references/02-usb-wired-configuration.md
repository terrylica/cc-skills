# USB-C Wired Configuration (Current)

How the pad is configured right now, when connected via USB-C.

## Mapping Summary

| Physical Button | Firmware Emits | Remapped To                                                                      | What It Does                                                                  |
| --------------- | -------------- | -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| **Top**         | `Ctrl+C`       | **Single-tap** → `Fn` (after ~200ms); **Double-tap ≤200ms** → `Command+V`        | Single tap toggles Typeless dictation; double tap pastes the system clipboard |
| **Middle**      | `Ctrl+V`       | **Single-tap** → `Shift+Return` (after ~200ms); **Double-tap ≤200ms** → `Return` | Single tap inserts a newline in chat/compose; double tap commits/sends        |
| **Bottom**      | `Ctrl+X`       | `Command+Delete`                                                                 | Delete from cursor to start of line                                           |

Apple keyboard's built-in Fn key is untouched by this rule. Your coworker using the MacBook Fn for Typeless is unaffected.

## Stack

```
[Macro pad button press]
        ↓
USB HID boot keyboard report (modifier byte + keycode)
        ↓
macOS kernel IOKit HID layer
        ↓
Karabiner DriverKit grabber (seizes the device, routes events)
        ↓
Complex Modifications rule engine (matches VID/PID + Ctrl+{C|V})
        ↓
Karabiner Virtual HID Device (emits replacement keycode)
        ↓
macOS CGEvent stream (Fn appears as kCGEventFlagMaskSecondaryFn)
        ↓
Typeless's koffi CGEventTap / Cocoa text field
```

## Current Rule

Located in `~/.config/karabiner/karabiner.json` → profile 0 → `complex_modifications.rules`. Exported verbatim in [`references/karabiner-rule.json`](references/karabiner-rule.json).

Abridged USB-only view — the full live rule covers USB + Bluetooth in 10 manipulators (top and middle each have a tap/double-tap pair × 2 transports + bottom × 2 transports). See `raw/karabiner-rule.json` for the verbatim dump.

```json
{
  "description": "Jieli macro pad: Ctrl+C -> single-tap Fn / double-tap Cmd+V (top); Ctrl+V -> single-tap Shift+Return / double-tap Return (middle); Ctrl+X -> Command+Delete (bottom)",
  "manipulators": [
    {
      "type": "basic",
      "from": {
        "simultaneous": [{ "key_code": "left_control" }, { "key_code": "c" }],
        "simultaneous_options": {
          "key_down_order": "insensitive",
          "key_up_order": "insensitive",
          "detect_key_down_uninterruptedly": true
        }
      },
      "to": [
        { "key_code": "v", "modifiers": ["left_command"] },
        { "set_variable": { "name": "jieli_top_tap", "value": 0 } }
      ],
      "conditions": [
        {
          "type": "device_if",
          "identifiers": [{ "vendor_id": 19530, "product_id": 16725 }]
        },
        { "type": "variable_if", "name": "jieli_top_tap", "value": 1 }
      ]
    },
    {
      "type": "basic",
      "parameters": { "basic.to_delayed_action_delay_milliseconds": 200 },
      "from": {
        "simultaneous": [{ "key_code": "left_control" }, { "key_code": "c" }],
        "simultaneous_options": {
          "key_down_order": "insensitive",
          "key_up_order": "insensitive",
          "detect_key_down_uninterruptedly": true
        }
      },
      "to": [{ "set_variable": { "name": "jieli_top_tap", "value": 1 } }],
      "to_delayed_action": {
        "to_if_invoked": [
          { "apple_vendor_top_case_key_code": "keyboard_fn" },
          { "set_variable": { "name": "jieli_top_tap", "value": 0 } }
        ],
        "to_if_canceled": [
          { "set_variable": { "name": "jieli_top_tap", "value": 0 } }
        ]
      },
      "conditions": [
        {
          "type": "device_if",
          "identifiers": [{ "vendor_id": 19530, "product_id": 16725 }]
        }
      ]
    },
    {
      "type": "basic",
      "from": {
        "simultaneous": [{ "key_code": "left_control" }, { "key_code": "v" }],
        "simultaneous_options": {
          "key_down_order": "insensitive",
          "key_up_order": "insensitive",
          "detect_key_down_uninterruptedly": true
        }
      },
      "to": [
        { "key_code": "return_or_enter" },
        { "set_variable": { "name": "jieli_middle_tap", "value": 0 } }
      ],
      "conditions": [
        {
          "type": "device_if",
          "identifiers": [{ "vendor_id": 19530, "product_id": 16725 }]
        },
        { "type": "variable_if", "name": "jieli_middle_tap", "value": 1 }
      ]
    },
    {
      "type": "basic",
      "parameters": { "basic.to_delayed_action_delay_milliseconds": 200 },
      "from": {
        "simultaneous": [{ "key_code": "left_control" }, { "key_code": "v" }],
        "simultaneous_options": {
          "key_down_order": "insensitive",
          "key_up_order": "insensitive",
          "detect_key_down_uninterruptedly": true
        }
      },
      "to": [{ "set_variable": { "name": "jieli_middle_tap", "value": 1 } }],
      "to_delayed_action": {
        "to_if_invoked": [
          { "key_code": "return_or_enter", "modifiers": ["left_shift"] },
          { "set_variable": { "name": "jieli_middle_tap", "value": 0 } }
        ],
        "to_if_canceled": [
          { "set_variable": { "name": "jieli_middle_tap", "value": 0 } }
        ]
      },
      "conditions": [
        {
          "type": "device_if",
          "identifiers": [{ "vendor_id": 19530, "product_id": 16725 }]
        }
      ]
    }
  ]
}
```

### How the tap/double-tap pattern works (top + middle buttons)

Both the top and middle buttons use the same two-manipulator pattern, each scoped to its own runtime variable (`jieli_top_tap` for the top button, `jieli_middle_tap` for the middle). For the middle button (`Ctrl+V`):

1. **Second-tap detector** (listed first — Karabiner evaluates top-down, first match wins): matches only when `jieli_middle_tap == 1`. Emits `Return` and resets the variable.
2. **First-tap handler**: matches when the variable is `0` (unset). Sets the variable to `1` and starts a 200ms delayed action:
   - `to_if_invoked` (timer elapsed, no second press arrived) → emit `Shift+Return` + reset variable
   - `to_if_canceled` (second press arrived, canceling the delay before it fired) → just reset the variable (the second-tap detector already handled the commit)

The top button (`Ctrl+C`) substitutes its own targets and variable name: single-tap → `Fn` (Apple vendor keyboard Fn for Typeless), double-tap → `Cmd+V` (paste). Otherwise the structure is identical. **Use a distinct variable per button** — sharing a variable across buttons would let a tap on one button arm the double-tap detector on another.

**Design tradeoff**: single-tap has ~200ms discrimination latency (unavoidable in any tap/double-tap scheme) but double-tap is instant. This is the "safety" framing: the more common action (newline / Typeless) is safer/slower, the decisive action (send / paste) is deliberate and fast. To invert (fast single-tap, delayed double-tap) swap the two targets in the JSON. For zero-latency alternatives, see `03-patterns.md` → "Tap vs. double-tap discrimination" (suggests tap-vs-hold when latency matters).

**Top-button caveat — Fn-as-push-to-talk doesn't work in this scheme.** Because the Fn keystroke fires only after the 200ms detection window expires, holding the top key emits a single delayed Fn keypress, not a sustained Fn-down state. Push-to-talk (hold to dictate) needs the original "no double-tap, fire Fn immediately" rule — collapse the two top-button manipulators back into a single immediate-Fn manipulator (see git history of `raw/karabiner-rule.json` before the top-button double-tap addition). This skill assumes Typeless is configured as **tap-to-toggle Fn**, not push-to-talk.

**Tuning**: `basic.to_delayed_action_delay_milliseconds: 200` is the double-tap window. Raise it (250-300) if users miss double-taps, lower it (150) if they accidentally trigger the double-tap target when meaning the single-tap target. The top and middle button windows are independent — tune each separately.

## Changing the Mapping

Karabiner auto-reloads on file save — no restart needed. Edits take effect within about 1 second.

### Add a binding for the bottom button (currently unused)

Append a third manipulator inside the rule's `manipulators` array:

```json
{
  "type": "basic",
  "from": {
    "simultaneous": [{ "key_code": "left_control" }, { "key_code": "x" }],
    "simultaneous_options": {
      "key_down_order": "insensitive",
      "key_up_order": "insensitive",
      "detect_key_down_uninterruptedly": true
    }
  },
  "to": [{ "key_code": "YOUR_TARGET" }],
  "conditions": [
    {
      "type": "device_if",
      "identifiers": [{ "vendor_id": 19530, "product_id": 16725 }]
    }
  ]
}
```

Useful `YOUR_TARGET` values:

| Target                                             | Effect                   |
| -------------------------------------------------- | ------------------------ |
| `{"key_code": "escape"}`                           | Escape                   |
| `{"key_code": "delete_or_backspace"}`              | Backspace                |
| `{"key_code": "spacebar"}`                         | Space                    |
| `{"key_code": "tab"}`                              | Tab                      |
| `{"consumer_key_code": "mute"}`                    | System mute              |
| `{"consumer_key_code": "play_or_pause"}`           | Media play/pause         |
| `{"shell_command": "open -a 'Some App.app'"}`      | Launch an app            |
| `{"key_code": "c", "modifiers": ["left_command"]}` | Real Cmd+C (copy on Mac) |

### Change the top or middle button

Edit the matching manipulator's `to` array in place. Whatever keycode you put there is what the button emits.

## Why Karabiner, Not BTT or hidutil

**BTT's `CGEventPost`** cannot produce a functional Fn key. Fn requires an HID device declaring the `NX_DEVICE_CAPABILITY_INPUTKEYBOARD_FUNCTION` capability. App-layer synthetic events don't carry this capability, so Typeless's `CGEventTap` filter ignores them.

**`hidutil` alone** cannot emit Fn either, and it can only remap single keycodes — not modifier+key combos. It would solve the "isolate a keycode to this device only" half of the problem, but not the "produce a real Fn" half.

**Karabiner-Elements** installs a DriverKit Virtual HID Device that declares the Fn capability. When its rule fires, events flow through its virtual keyboard as authentic, OS-trusted keystrokes. This is the only FOSS path on macOS Sequoia that satisfies both requirements.

## Persistence Across Reboots

Karabiner registers its privileged daemons via macOS's `SMAppService` API. They auto-start at login because:

- The DriverKit extension is active and enabled: `org.pqrs.Karabiner-DriverKit-VirtualHIDDevice (1.8.0)`
- The daemons are registered in System Settings → General → Login Items & Extensions → "Allow in the Background" — all Karabiner entries are toggled on

If the daemons ever fail to come up after a reboot (symptom: pad keys emit unchanged Ctrl+C/V/X), check that toggle. Sometimes a major macOS update resets Login Items approvals.

## Troubleshooting

| Symptom                                                               | Likely Cause                     | Check / Fix                                                                                                                                                                                                                                  |
| --------------------------------------------------------------------- | -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Pad emits Ctrl+C/V/X unmodified                                       | Karabiner daemon not running     | `pgrep -l karabiner` — expect `Karabiner-Core-Service`, `karabiner_console_user_server`, `karabiner_session_monitor`, `Karabiner-NotificationWindow`. If missing, check Login Items approval                                                 |
| Pad is visible in Karabiner's devices list but rule doesn't fire      | Karabiner not grabbing the pad   | `grep "USB Composite Device" /var/log/karabiner/core_service.log \| tail -2` — last line should say `(grabbed)`. If it says `(stopped)`, pad was unplugged or set to `ignore`                                                                |
| Top button triggers something other than Typeless (e.g. emoji picker) | Globe key behavior overriding    | `defaults read com.apple.HIToolbox AppleFnUsageType` — should be `0` (Do Nothing). If not, change in System Settings → Keyboard → "Press 🌐 key to..."                                                                                       |
| Fn fires but Typeless silent                                          | Typeless stopped listening       | Restart Typeless.app. If still silent, check Typeless's `app-settings.json` has `"pushToTalk": "Fn"`                                                                                                                                         |
| Top button single-tap pastes instead of activating Fn                 | Variable stuck at `1`            | Same fix as the middle button — see "Variable stuck" row below. Apply to `jieli_top_tap` instead of `jieli_middle_tap`.                                                                                                                      |
| Top button's double-tap pastes nothing                                | Clipboard empty or app blocks ⌘V | Verify with manual ⌘V in the same app. The rule synthesises a real `Cmd+V` so any app accepting clipboard paste will receive it; sandboxed apps that block synthetic events (1Password CLI, some IDEs) will not.                             |
| Middle button inserts text instead of newline                         | Rule targeting wrong keycode     | Verify both Ctrl+V manipulators: the second-tap detector's `to` has `return_or_enter`; the first-tap handler's `to_if_invoked` has `return_or_enter` + `modifiers: ["left_shift"]`. Neither target should be `v`.                            |
| Tap-button fires double-tap target on single press                    | Variable stuck at `1`            | Kickstart Karabiner to clear runtime variables: `launchctl kickstart -k gui/$(id -u)/org.pqrs.karabiner.karabiner_console_user_server`. Or force a config reload by touching the file. Affects either `jieli_top_tap` or `jieli_middle_tap`. |
| 200ms single-tap delay feels sluggish                                 | Default detection window         | Edit the affected first-tap manipulator's `parameters.basic.to_delayed_action_delay_milliseconds` to a lower value (e.g. 150). Tradeoff: fewer successful double-tap detections. Top and middle are tuned independently.                     |
| Double-tap fails — two single-tap targets fire back-to-back           | Taps were slower than window     | Raise `basic.to_delayed_action_delay_milliseconds` to 250-300. Tradeoff: more single-tap latency.                                                                                                                                            |

## Diagnostic Commands (non-sudo)

```bash
# Is Karabiner running?
pgrep -l karabiner

# Is the pad currently grabbed?
grep "USB Composite Device" /var/log/karabiner/core_service.log | tail -2

# What does Karabiner see as the connected devices?
karabiner_cli --list-connected-devices | jq '.[] | select(.device_identifiers.vendor_id == 19530)'

# Current rules in config
jq '.profiles[0].complex_modifications.rules[] | .description' ~/.config/karabiner/karabiner.json

# Full pad-specific rule
jq '.profiles[0].complex_modifications.rules[] | select(.description | startswith("Jieli"))' ~/.config/karabiner/karabiner.json
```

## Reverting

**Disable only this rule**: Karabiner-Elements → Complex Modifications → toggle off "Jieli macro pad: …". Keeps Karabiner running; other rules (AudioPrioritySetter, Ultra Custom Shortcut, Option-L script) stay active.

**Restore pre-change config byte-for-byte**. Karabiner doesn't auto-snapshot, so always back up before editing:

```bash
# Before any change:
cp ~/.config/karabiner/karabiner.json \
   ~/.config/karabiner/karabiner.json.bak.$(date +%Y%m%d-%H%M%S)

# To revert:
cp ~/.config/karabiner/karabiner.json.bak.<YOUR_TIMESTAMP> \
   ~/.config/karabiner/karabiner.json
```

Karabiner will auto-reload the restored file within ~1 second (watch the daemon log at `/var/log/karabiner/core_service.log` to confirm).

**Full Karabiner uninstall**:

```bash
brew uninstall --cask karabiner-elements
```

Then remove the DriverKit extension in System Settings → General → Login Items & Extensions → Driver Extensions.

## Known Limitations

- **Push-to-talk minimum latency**: `basic.simultaneous_threshold_milliseconds` in the Karabiner config is `50` by default. That's the ceiling on how long Karabiner waits to confirm both Ctrl and the letter are pressed simultaneously. For push-to-talk this is imperceptible; for fast-twitch games it could matter.
- **Pad firmware not reconfigurable on macOS**. Changing which keycode each button emits requires either the Windows-only Jieli vendor tool or reverse-engineering the 64-byte HID config channel — not attempted here.
- **Bottom button's Ctrl+X passes through** and will trigger Cut in text fields that accept Ctrl+X (some cross-platform apps) or do nothing (most Mac-native apps that expect Cmd+X). Choose a bound target for this button if you want predictable behavior everywhere.
