# MacroKeyBot — Turnkey Walkthrough

End-to-end recipe for replicating the "MacroKeyBot" setup: a ~$10 three-key USB-C/Bluetooth pad remapped to act as a dictation trigger, a safer-than-usual Return key, and a delete-to-start shortcut. Copy-paste-ready; swap VID/PIDs for your hardware.

> **Goal of this doc**: take someone from "I saw this cool pad online" to "my Mac now responds to three chunky buttons on my desk" in under 30 minutes. If you get stuck anywhere, the linked deep-reference docs have the full explanation.

## What You're Building

A single rule in Karabiner-Elements that scopes three physical buttons on a cheap HID pad to three different macOS actions, without touching your MacBook's built-in keyboard. Works identically over USB-C and Bluetooth even though the pad's BT firmware emits different keycodes than its USB side.

**The user-facing behavior**:

| Button | Single-tap action                                  | Double-tap action (≤200ms) | Real-world use                                                              |
| ------ | -------------------------------------------------- | -------------------------- | --------------------------------------------------------------------------- |
| Top    | Toggle Typeless / dictation (real Fn, after 200ms) | Paste (`Cmd+V`)            | Tap to start/stop dictation; double-tap to paste the system clipboard       |
| Middle | Insert newline (`Shift+Return`, after 200ms)       | Commit/send (`Return`)     | Chat composers, Claude Code prompt, email compose — safer-than-usual "send" |
| Bottom | Delete to start of line (`Command+Delete`)         | —                          | Clear the current line without selecting it first                           |

**Why the tap/double-tap on middle**: in most chat apps, a stray `Return` sends a half-typed message. By making the single-tap insert a newline and the double-tap send, accidentally-sent messages become nearly impossible. You pay ~200ms of detection latency on every newline — a fair trade if you've ever misfired a `Return` at work.

**Why the tap/double-tap on top**: dictation is a soft, two-handed action; paste needs a one-handed shortcut you can hit without breaking flow. Tap to toggle Typeless, double-tap when you want the clipboard.

> **Top-button caveat** — the 200ms tap-detection window means Fn fires only after release, not on press-and-hold. That makes this rule **incompatible with Typeless's push-to-talk mode** (hold to dictate). Use Typeless's tap-to-toggle Fn mode, or — if you need PTT — collapse the top-button pair back into the original single-manipulator-per-transport "Fn fires immediately" rule (see git history of `references/raw/karabiner-rule.json` from before the top-button double-tap addition).

## Shopping List

| Item                              | Where                                                                                | Price    | Notes                                                                                                              |
| --------------------------------- | ------------------------------------------------------------------------------------ | -------- | ------------------------------------------------------------------------------------------------------------------ |
| 3-key USB-C + Bluetooth macro pad | AliExpress search: "3-key macropad usb bluetooth"; Amazon: "3 key shortcut keyboard" | $8-$15   | Look for ones that list both "USB-C" and "Bluetooth 5.0" — single-transport pads work but lose the portability win |
| USB-C cable (1m short)            | Any                                                                                  | Included | Ships with the pad                                                                                                 |

The one used as the worked example throughout this plugin is a Jieli/Free3-P clone with VID `0x4c4a` (USB) / `0x04E8` (BT). Other vendors (Realtek, CH57x) behave identically — only the VID/PID pair changes.

## Prerequisites (~5 min)

```bash
# 1. Karabiner-Elements
brew install --cask karabiner-elements
open -a Karabiner-Elements    # first-run will prompt for permissions

# 2. blueutil (optional but strongly recommended for BT debugging)
brew install blueutil
```

**macOS permissions to grant** (System Settings → Privacy & Security):

- Input Monitoring → Karabiner-Elements, karabiner_grabber, karabiner_observer → ON
- Accessibility → Karabiner-Elements → ON
- On macOS Sequoia+: System Settings → General → Login Items & Extensions → "Allow in the Background" → Karabiner-Elements entries → all ON

**Verify Karabiner's privileged daemons are running**:

```bash
pgrep -l karabiner
# Expect: karabiner_grabber, karabiner_observer, karabiner_console_user_server,
#         karabiner_session_monitor, Karabiner-NotificationWindow
```

If any are missing, re-check the Login Items toggle.

## Step 1 — Identify Your Pad (USB, ~3 min)

Plug the pad in, then:

```bash
# Full USB descriptor — look for "USB Composite Device" or the vendor's product string
ioreg -p IOUSB -l -w 0 | grep -A 20 "Composite\|Macro\|HID Keyboard" | head -40

# Or the cleaner view:
system_profiler SPUSBDataType | grep -B 2 -A 15 "Composite\|Macro"
```

**Record these values** (they'll go into your Karabiner rule):

- `idVendor` → hex, e.g. `0x4c4a`
- `idProduct` → hex, e.g. `0x4155`
- product string → e.g. `USB Composite Device`

**Convert to decimal** (Karabiner's JSON uses decimal):

```bash
python3 -c "print(int('0x4c4a', 16), int('0x4155', 16))"
# → 19530 16725
```

**Confirm Karabiner sees the pad**:

```bash
karabiner_cli --list-connected-devices | jq '.[] | {product, vendor_id, product_id, is_keyboard}'
```

Your pad should appear with `is_keyboard: true` and the VID/PID you just recorded.

## Step 2 — Pair the Pad over Bluetooth (~5 min, skip if USB-only)

Most cheap pads enter BT pairing mode via a button combo — often holding the top button for 5 seconds, or a dedicated "BT" button. Check the sticker on the box or the AliExpress listing images.

```bash
# macOS native pairing
open "x-apple.systempreferences:com.apple.preferences.Bluetooth"
# → click the pad when it appears, confirm pairing

# Verify pairing
blueutil --paired | grep -i "$PAD_NAME"

# Get the BT VID/PID (often DIFFERENT from USB — many cheap pads borrow Samsung's 0x04E8)
system_profiler SPBluetoothDataType | grep -B 2 -A 20 "$PAD_NAME"
```

**Record the BT values too**:

- Bluetooth VID → e.g. `0x04E8` / decimal `1256`
- Bluetooth PID → e.g. `0x7021` / decimal `28705`
- BT MAC address → e.g. `EC:BD:E4:D3:F7:97`

**Expect the BT VID/PID to differ from USB**. The pad's BT radio is a separate chip, and manufacturers borrow Samsung's allow-listed VID (`0x04E8`) for macOS HID compatibility. See [`08-bluetooth-configuration.md`](08-bluetooth-configuration.md) for why.

## Step 3 — Discover What Each Button Emits (~5 min)

Do not assume standard mappings. Cheap pads ship with arbitrary keycodes — the worked example pad emits `Ctrl+C` / `Ctrl+V` / `Ctrl+X` on USB (nothing to do with cut/copy/paste; those just happen to be the firmware defaults). BT mode 4 emits `page_up` / `page_down` / `equal_sign`.

Use Karabiner's `ignore: true` diagnostic pattern to temporarily release the device so `Karabiner-EventViewer` shows raw HID events:

1. Open `~/.config/karabiner/karabiner.json` in your editor
2. In `profiles[0].devices`, add this entry (substitute your VID/PID):

   ```json
   {
     "identifiers": {
       "is_keyboard": true,
       "vendor_id": 19530,
       "product_id": 16725
     },
     "ignore": true,
     "disable_built_in_keyboard_if_exists": false,
     "fn_function_keys": [],
     "manipulate_caps_lock_led": false,
     "simple_modifications": [],
     "treat_as_built_in_keyboard": false
   }
   ```

3. Open Karabiner-EventViewer (bundled with Karabiner-Elements) → "Main" tab
4. Press each button, note the emitted keycode(s)
5. Switch to the BT transport (unplug USB) and repeat — record the BT-side keycodes separately
6. **Remove the `ignore: true` entry when done** (otherwise Karabiner won't grab the pad and your remap won't fire)

See [`diagnose-hid-keycodes/SKILL.md`](../../diagnose-hid-keycodes/SKILL.md) for the full diagnostic workflow including screenshot automation via Quartz window capture.

## Step 4 — Write the Rule (~10 min)

**Back up your config first**:

```bash
cp ~/.config/karabiner/karabiner.json \
   ~/.config/karabiner/karabiner.json.bak.$(date +%Y%m%d-%H%M%S)
```

Open `~/.config/karabiner/karabiner.json` in your editor. Find `profiles[0].complex_modifications.rules` (it's an array) and append this rule at the end. **Substitute your own VID/PIDs** wherever `19530 / 16725` (USB) or `1256 / 28705` (BT) appear.

```json
{
  "description": "MacroKeyBot: Top single-tap -> Fn (Typeless toggle) / double-tap -> Cmd+V (paste); Middle single-tap -> Shift+Return / double-tap -> Return; Bottom -> Command+Delete",
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
        { "set_variable": { "name": "macrokeybot_top_tap", "value": 0 } }
      ],
      "conditions": [
        {
          "type": "device_if",
          "identifiers": [
            { "vendor_id": 19530, "product_id": 16725 },
            { "vendor_id": 1256, "product_id": 28705 }
          ]
        },
        { "type": "variable_if", "name": "macrokeybot_top_tap", "value": 1 }
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
      "to": [{ "set_variable": { "name": "macrokeybot_top_tap", "value": 1 } }],
      "to_delayed_action": {
        "to_if_invoked": [
          { "apple_vendor_top_case_key_code": "keyboard_fn" },
          { "set_variable": { "name": "macrokeybot_top_tap", "value": 0 } }
        ],
        "to_if_canceled": [
          { "set_variable": { "name": "macrokeybot_top_tap", "value": 0 } }
        ]
      },
      "conditions": [
        {
          "type": "device_if",
          "identifiers": [
            { "vendor_id": 19530, "product_id": 16725 },
            { "vendor_id": 1256, "product_id": 28705 }
          ]
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
        { "set_variable": { "name": "macrokeybot_middle_tap", "value": 0 } }
      ],
      "conditions": [
        {
          "type": "device_if",
          "identifiers": [
            { "vendor_id": 19530, "product_id": 16725 },
            { "vendor_id": 1256, "product_id": 28705 }
          ]
        },
        { "type": "variable_if", "name": "macrokeybot_middle_tap", "value": 1 }
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
      "to": [
        { "set_variable": { "name": "macrokeybot_middle_tap", "value": 1 } }
      ],
      "to_delayed_action": {
        "to_if_invoked": [
          { "key_code": "return_or_enter", "modifiers": ["left_shift"] },
          { "set_variable": { "name": "macrokeybot_middle_tap", "value": 0 } }
        ],
        "to_if_canceled": [
          { "set_variable": { "name": "macrokeybot_middle_tap", "value": 0 } }
        ]
      },
      "conditions": [
        {
          "type": "device_if",
          "identifiers": [
            { "vendor_id": 19530, "product_id": 16725 },
            { "vendor_id": 1256, "product_id": 28705 }
          ]
        }
      ]
    },
    {
      "type": "basic",
      "from": { "key_code": "page_up" },
      "to": [
        { "key_code": "v", "modifiers": ["left_command"] },
        { "set_variable": { "name": "macrokeybot_top_tap", "value": 0 } }
      ],
      "conditions": [
        {
          "type": "device_if",
          "identifiers": [
            { "vendor_id": 19530, "product_id": 16725 },
            { "vendor_id": 1256, "product_id": 28705 }
          ]
        },
        { "type": "variable_if", "name": "macrokeybot_top_tap", "value": 1 }
      ]
    },
    {
      "type": "basic",
      "parameters": { "basic.to_delayed_action_delay_milliseconds": 200 },
      "from": { "key_code": "page_up" },
      "to": [{ "set_variable": { "name": "macrokeybot_top_tap", "value": 1 } }],
      "to_delayed_action": {
        "to_if_invoked": [
          { "apple_vendor_top_case_key_code": "keyboard_fn" },
          { "set_variable": { "name": "macrokeybot_top_tap", "value": 0 } }
        ],
        "to_if_canceled": [
          { "set_variable": { "name": "macrokeybot_top_tap", "value": 0 } }
        ]
      },
      "conditions": [
        {
          "type": "device_if",
          "identifiers": [
            { "vendor_id": 19530, "product_id": 16725 },
            { "vendor_id": 1256, "product_id": 28705 }
          ]
        }
      ]
    },
    {
      "type": "basic",
      "from": { "key_code": "page_down" },
      "to": [
        { "key_code": "return_or_enter" },
        { "set_variable": { "name": "macrokeybot_middle_tap", "value": 0 } }
      ],
      "conditions": [
        {
          "type": "device_if",
          "identifiers": [
            { "vendor_id": 19530, "product_id": 16725 },
            { "vendor_id": 1256, "product_id": 28705 }
          ]
        },
        { "type": "variable_if", "name": "macrokeybot_middle_tap", "value": 1 }
      ]
    },
    {
      "type": "basic",
      "parameters": { "basic.to_delayed_action_delay_milliseconds": 200 },
      "from": { "key_code": "page_down" },
      "to": [
        { "set_variable": { "name": "macrokeybot_middle_tap", "value": 1 } }
      ],
      "to_delayed_action": {
        "to_if_invoked": [
          { "key_code": "return_or_enter", "modifiers": ["left_shift"] },
          { "set_variable": { "name": "macrokeybot_middle_tap", "value": 0 } }
        ],
        "to_if_canceled": [
          { "set_variable": { "name": "macrokeybot_middle_tap", "value": 0 } }
        ]
      },
      "conditions": [
        {
          "type": "device_if",
          "identifiers": [
            { "vendor_id": 19530, "product_id": 16725 },
            { "vendor_id": 1256, "product_id": 28705 }
          ]
        }
      ]
    },
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
      "to": [
        { "key_code": "delete_or_backspace", "modifiers": ["left_command"] }
      ],
      "conditions": [
        {
          "type": "device_if",
          "identifiers": [
            { "vendor_id": 19530, "product_id": 16725 },
            { "vendor_id": 1256, "product_id": 28705 }
          ]
        }
      ]
    },
    {
      "type": "basic",
      "from": { "key_code": "equal_sign" },
      "to": [
        { "key_code": "delete_or_backspace", "modifiers": ["left_command"] }
      ],
      "conditions": [
        {
          "type": "device_if",
          "identifiers": [
            { "vendor_id": 19530, "product_id": 16725 },
            { "vendor_id": 1256, "product_id": 28705 }
          ]
        }
      ]
    }
  ]
}
```

**Adapt for your pad**:

- If your pad emits something other than `Ctrl+C / Ctrl+V / Ctrl+X` on USB, substitute the matching `key_code` values in each `from.simultaneous[1]`.
- If your BT mode emits something other than `page_up / page_down / equal_sign`, substitute the matching `from.key_code` values in the BT-side manipulators (5-10 in the rule).
- If you don't care about Bluetooth: delete the BT-side manipulators (numbers 5-10 — the ones whose `from` uses `page_up` / `page_down` / `equal_sign`), and remove the BT identifier from every remaining `device_if`. You'll end up with 5 manipulators instead of 10.
- If you don't want the top-button double-tap (you need Fn-as-push-to-talk, or one binding is enough): delete manipulators 1 and 5 (the `variable_if`-guarded paste detectors), and replace manipulators 2 and 6 with the simpler immediate-Fn form — drop `parameters`, `to_delayed_action`, and `variable_if`; set `to: [{ "apple_vendor_top_case_key_code": "keyboard_fn" }]`. You'll go from 10 → 8 manipulators.
- If you want different bindings (see "Variations" below): replace the `to` targets accordingly.

**Save the file**. Karabiner auto-reloads within ~1 second. Watch the log to confirm:

```bash
tail -f /var/log/karabiner/core_service.log
# Look for: "Load /Users/.../karabiner.json..." followed by "core_configuration is updated."
# Ctrl+C to stop tailing.
```

## Step 5 — Verify (~3 min)

```bash
# 1. Karabiner is grabbing the pad
karabiner_cli --list-connected-devices | jq '.[] | select(.vendor_id == 19530 or .vendor_id == 1256) | {product, is_grabbed}'
# Expect: is_grabbed: true

# 2. The rule is loaded
jq '.profiles[0].complex_modifications.rules[] | select(.description | startswith("MacroKeyBot")) | {description, manipulator_count: (.manipulators | length)}' ~/.config/karabiner/karabiner.json
# Expect: manipulator_count: 10 (or 5 if you dropped the BT side; or 8 if you dropped only the top-button double-tap)
```

**Functional test** (the only test that matters):

| Action                               | Expected result                                                                                               |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| Single-tap Top (don't press fast)    | After ~200ms, Fn fires once. Typeless / dictation UI toggles on (or off, on the next single-tap).             |
| Double-tap Top (fast, <200ms)        | The system clipboard is pasted at the cursor. Same effect as ⌘V.                                              |
| Single-tap Middle (don't press fast) | After ~200ms, a newline is inserted. In Claude Code: text bumps to next line; in Slack: new line in composer. |
| Double-tap Middle (fast, <200ms)     | The message is sent / Return fires immediately on the second press.                                           |
| Press Bottom                         | Everything from the cursor back to the start of the line is deleted.                                          |

If any step misbehaves, see [`02-usb-wired-configuration.md`](02-usb-wired-configuration.md#troubleshooting) or [`08-bluetooth-configuration.md`](08-bluetooth-configuration.md#diagnostic-commands).

## Variations — Pick Your Own Bindings

The structure above works for any 3-key pad with any binding. Here are common alternates for the middle button's tap/double-tap pair:

| Use case                             | Single-tap target               | Double-tap target                   | Framing                                                                       |
| ------------------------------------ | ------------------------------- | ----------------------------------- | ----------------------------------------------------------------------------- |
| Chat safety (our default)            | `Shift+Return` (newline)        | `Return` (send)                     | Newline is safe, send is deliberate — prevents accidental half-sent messages  |
| Chat speed                           | `Return` (send)                 | `Shift+Return` (newline)            | Fast on send, slower on newline — for high-throughput messaging               |
| Dismiss vs. interrupt                | `Escape`                        | `Command+.`                         | Dismiss is fast, interrupt (hard-stop a running app / debugger) is deliberate |
| Copy vs. copy-path in Finder         | `Command+C`                     | `Command+Option+C`                  | Everyday copy is fast, "copy full path" is deliberate                         |
| Git add vs. commit (via shell alias) | `Command+Shift+A` → `git add .` | `Command+Shift+C` → `git commit -v` | Stage is fast, commit needs two taps of confirmation                          |

For non-Return single-button variations, replace the affected button-pair's two manipulators' targets:

- Second-tap detector's `to[0].key_code` (or `to[0].shell_command`) = your double-tap action
- First-tap handler's `to_delayed_action.to_if_invoked[0].key_code` (or `to[0].shell_command`) = your single-tap action

Keep the `set_variable` + `device_if` + `variable_if` structure unchanged. **Use a distinct variable name per button** (the rule above uses `macrokeybot_top_tap` and `macrokeybot_middle_tap`) — sharing a variable across buttons would let a tap on one button arm the double-tap detector on the other.

The same alternates table works for the top button — common pairings:

| Use case                           | Single-tap target         | Double-tap target             | Framing                                                    |
| ---------------------------------- | ------------------------- | ----------------------------- | ---------------------------------------------------------- |
| Dictation + paste (our default)    | `Fn` (Typeless toggle)    | `Cmd+V` (paste)               | Dictation is two-handed; paste is the one-handed companion |
| Mute mic + push-to-talk substitute | `Cmd+Shift+M` (Zoom mute) | `Cmd+Shift+A` (toggle audio)  | Mute is fast, audio toggle is deliberate                   |
| Copy + copy-path in Finder         | `Cmd+C`                   | `Cmd+Option+C`                | Everyday copy is fast, "copy full path" is deliberate      |
| App launcher pair                  | `open -a 'Notes'`         | `open -a 'Notes' && new note` | Switch is fast, create-and-switch is deliberate            |

For the bottom button (single-action), the decision-tree table in [`SKILL.md`](../SKILL.md#decision-tree-which-target-keycode) shows common target JSON for Fn, media keys, shell commands, app launchers, etc.

## Rolling Back

The rule can be disabled two ways:

**Soft-disable** — keeps Karabiner running, just toggles this rule off:

```
Karabiner-Elements GUI → Complex Modifications → toggle "MacroKeyBot: ..." OFF
```

**Hard-restore** — reverts the file to before your change:

```bash
cp ~/.config/karabiner/karabiner.json.bak.<YOUR_TIMESTAMP> \
   ~/.config/karabiner/karabiner.json
```

Karabiner auto-reloads within a second.

**Fully remove Karabiner**:

```bash
brew uninstall --cask karabiner-elements
```

Then System Settings → General → Login Items & Extensions → Driver Extensions → remove the Karabiner DriverKit entry.

## What to Do Next

- Add a 4th/5th button-combo binding by appending more manipulators to the same rule (same `device_if`, different `from`).
- Extend the tap/double-tap pattern to other buttons — the mechanism in [`03-patterns.md`](03-patterns.md#pattern-tap-vs-double-tap-discrimination-on-one-button) is reusable as-is.
- Explore tap-vs-hold for zero-latency alternatives (see the anti-pattern warning in [`04-anti-patterns.md`](04-anti-patterns.md) before using `to_if_held_down` with Fn).
- Run all this through Claude Code: invoke the `configure-macro-keyboard` skill next time you set up a new pad, and Claude will walk the 5-step workflow interactively — reusing these same patterns.

## Credits & Provenance

This walkthrough distills ~2 days of live exploration on a Jieli/Free3-P 3-key pad, captured in [`01-hardware-identification.md`](01-hardware-identification.md) through [`08-bluetooth-configuration.md`](08-bluetooth-configuration.md). The middle-button tap/double-tap pattern was added on 2026-04-23 to give Return a safer-than-default behavior; the same pattern was extended to the top button on 2026-04-24 (single-tap → Fn for Typeless toggle, double-tap → Cmd+V paste). All patterns, traps, and adaptation notes here have been field-tested on the development laptop. If a detail doesn't survive contact with your reality, open an issue — this file is meant to evolve.
