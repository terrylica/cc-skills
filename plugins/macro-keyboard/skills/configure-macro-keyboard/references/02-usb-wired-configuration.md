# USB-C Wired Configuration (Current)

How the pad is configured right now, when connected via USB-C.

## Mapping Summary

| Physical Button | Firmware Emits | Remapped To                     | What It Does                         |
| --------------- | -------------- | ------------------------------- | ------------------------------------ |
| **Top**         | `Ctrl+C`       | `Fn` (Apple vendor keyboard Fn) | Push-to-talk for Typeless dictation  |
| **Middle**      | `Ctrl+V`       | `Return`                        | Submit / newline in any text context |
| **Bottom**      | `Ctrl+X`       | `Command+Delete`                | Delete from cursor to start of line  |

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

```json
{
  "description": "Jieli macro pad: Ctrl+C -> Fn (push-to-talk, top), Ctrl+V -> Return (middle), Ctrl+X passes through (bottom)",
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
      "to": [{ "apple_vendor_top_case_key_code": "keyboard_fn" }],
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
      "to": [{ "key_code": "return_or_enter" }],
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

| Symptom                                                               | Likely Cause                   | Check / Fix                                                                                                                                                                                  |
| --------------------------------------------------------------------- | ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Pad emits Ctrl+C/V/X unmodified                                       | Karabiner daemon not running   | `pgrep -l karabiner` — expect `Karabiner-Core-Service`, `karabiner_console_user_server`, `karabiner_session_monitor`, `Karabiner-NotificationWindow`. If missing, check Login Items approval |
| Pad is visible in Karabiner's devices list but rule doesn't fire      | Karabiner not grabbing the pad | `grep "USB Composite Device" /var/log/karabiner/core_service.log \| tail -2` — last line should say `(grabbed)`. If it says `(stopped)`, pad was unplugged or set to `ignore`                |
| Top button triggers something other than Typeless (e.g. emoji picker) | Globe key behavior overriding  | `defaults read com.apple.HIToolbox AppleFnUsageType` — should be `0` (Do Nothing). If not, change in System Settings → Keyboard → "Press 🌐 key to..."                                       |
| Fn fires but Typeless silent                                          | Typeless stopped listening     | Restart Typeless.app. If still silent, check Typeless's `app-settings.json` has `"pushToTalk": "Fn"`                                                                                         |
| Middle button inserts text instead of newline                         | Rule targeting wrong keycode   | Verify the Ctrl+V manipulator's `to` contains `return_or_enter`, not `v`                                                                                                                     |

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

**Restore pre-change config byte-for-byte**:

```bash
cp ~/.config/karabiner/karabiner.json.bak.20260421-130748 ~/.config/karabiner/karabiner.json
```

**Full Karabiner uninstall**:

```bash
brew uninstall --cask karabiner-elements
```

Then remove the DriverKit extension in System Settings → General → Login Items & Extensions → Driver Extensions.

## Known Limitations

- **Push-to-talk minimum latency**: `basic.simultaneous_threshold_milliseconds` in the Karabiner config is `50` by default. That's the ceiling on how long Karabiner waits to confirm both Ctrl and the letter are pressed simultaneously. For push-to-talk this is imperceptible; for fast-twitch games it could matter.
- **Pad firmware not reconfigurable on macOS**. Changing which keycode each button emits requires either the Windows-only Jieli vendor tool or reverse-engineering the 64-byte HID config channel — not attempted here.
- **Bottom button's Ctrl+X passes through** and will trigger Cut in text fields that accept Ctrl+X (some cross-platform apps) or do nothing (most Mac-native apps that expect Cmd+X). Choose a bound target for this button if you want predictable behavior everywhere.
