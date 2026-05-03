# MacroKeyBot — Turnkey Walkthrough

End-to-end recipe for replicating the "MacroKeyBot" setup: a ~$10 three-key USB-C/Bluetooth pad remapped to act as a dictation trigger, a safer-than-usual Return key, and a delete-to-start shortcut. Copy-paste-ready; swap VID/PIDs for your hardware.

> **Goal of this doc**: take someone from "I saw this cool pad online" to "my Mac now responds to three chunky buttons on my desk" in under 30 minutes. If you get stuck anywhere, the linked deep-reference docs have the full explanation.

## What You're Building

A single rule in Karabiner-Elements that scopes three physical buttons on a cheap HID pad to three different macOS actions, without touching your MacBook's built-in keyboard. Works identically over USB-C and Bluetooth even though the pad's BT firmware emits different keycodes than its USB side.

**The user-facing behavior**:

| Button | Single-tap action                                  | Double-tap action (≤200ms)          | Real-world use                                                                                                                      |
| ------ | -------------------------------------------------- | ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Top    | Toggle Typeless / dictation (real Fn, after 200ms) | Paste (`Cmd+V`)                     | Tap to start/stop dictation; double-tap to paste the system clipboard                                                               |
| Middle | Insert newline (`Shift+Return`, after 200ms)       | Commit/send (`Return`)              | Chat composers, Claude Code prompt, email compose — safer-than-usual "send"                                                         |
| Bottom | Cursor up one line (`up_arrow`)                    | Cursor down one line (`down_arrow`) | Tap to step up; double-tap to step down. **Asymmetric mechanism** — see "Why the bottom-button uses two different mechanisms" below |

**Why the tap/double-tap on middle**: in most chat apps, a stray `Return` sends a half-typed message. By making the single-tap insert a newline and the double-tap send, accidentally-sent messages become nearly impossible. You pay ~200ms of detection latency on every newline — a fair trade if you've ever misfired a `Return` at work.

**Why the tap/double-tap on top**: dictation is a soft, two-handed action; paste needs a one-handed shortcut you can hit without breaking flow. Tap to toggle Typeless, double-tap when you want the clipboard.

**Why the tap/double-tap on bottom (and why it differs by transport)**: cursor up + down are both reversible navigation, so the single-tap latency cost matters less than for the other buttons. The interesting twist is **the pad's BT firmware does its own double-tap detection on the bottom button only** — single tap emits `equal_sign`, double tap emits `Option+Z` (verified 2026-05-02 via Karabiner-EventViewer). On USB the same button emits `Ctrl+X` for every press. Consequently the rule uses two different mechanisms for the bottom button: USB does Karabiner-side `set_variable`+`to_delayed_action` discrimination; BT translates the firmware-decided keycode immediately. User-facing behavior is identical (tap = up, double-tap = down) — the asymmetry is invisible unless you inspect the rule.

> **Top-button caveat** — the 200ms tap-detection window means Fn fires only after release, not on press-and-hold. That makes this rule **incompatible with Typeless's push-to-talk mode** (hold to dictate). Use Typeless's tap-to-toggle Fn mode, or — if you need PTT — collapse the top-button pair back into the original single-manipulator-per-transport "Fn fires immediately" rule (see git history of `references/raw/karabiner-rule.json` from before the top-button double-tap addition).

> **Bottom-button caveat** — arrow keys do not auto-repeat on hold on either transport. On USB the single-tap target (`up_arrow`) fires once after the 200ms window; on BT the pad's firmware emits one discrete event per gesture (no key-down/key-up stream). Real macOS arrow keys auto-repeat for scrolling; this remap does not. To navigate a long list, tap repeatedly. To restore continuous scroll on USB, collapse the USB pair back into a single immediate-`up_arrow` manipulator. On BT you can't restore auto-repeat — the firmware doesn't emit a stream.

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
  "description": "MacroKeyBot: Top single-tap -> Fn (Typeless toggle) / double-tap -> Cmd+V (paste); Middle single-tap -> Shift+Return / double-tap -> Return; Bottom single-tap -> up_arrow / double-tap -> down_arrow. USB uses Karabiner-side detection on bottom (Ctrl+X for both presses); BT uses pad-firmware detection (equal_sign single, Option+Z double).",
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
        { "key_code": "down_arrow" },
        { "set_variable": { "name": "macrokeybot_bottom_tap", "value": 0 } }
      ],
      "conditions": [
        {
          "type": "device_if",
          "identifiers": [
            { "vendor_id": 19530, "product_id": 16725 },
            { "vendor_id": 1256, "product_id": 28705 }
          ]
        },
        { "type": "variable_if", "name": "macrokeybot_bottom_tap", "value": 1 }
      ]
    },
    {
      "type": "basic",
      "parameters": { "basic.to_delayed_action_delay_milliseconds": 200 },
      "from": {
        "simultaneous": [{ "key_code": "left_control" }, { "key_code": "x" }],
        "simultaneous_options": {
          "key_down_order": "insensitive",
          "key_up_order": "insensitive",
          "detect_key_down_uninterruptedly": true
        }
      },
      "to": [
        { "set_variable": { "name": "macrokeybot_bottom_tap", "value": 1 } }
      ],
      "to_delayed_action": {
        "to_if_invoked": [
          { "key_code": "up_arrow" },
          { "set_variable": { "name": "macrokeybot_bottom_tap", "value": 0 } }
        ],
        "to_if_canceled": [
          { "set_variable": { "name": "macrokeybot_bottom_tap", "value": 0 } }
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
      "from": { "key_code": "equal_sign" },
      "to": [{ "key_code": "up_arrow" }],
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
        "key_code": "z",
        "modifiers": { "mandatory": ["left_option"] }
      },
      "to": [{ "key_code": "down_arrow" }],
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
- If your BT mode emits something other than `page_up / page_down / equal_sign` on a single tap (top + middle + bottom), substitute the matching `from.key_code` values in the BT-side manipulators (5-8 and 11). For the bottom button on BT, also **check what the pad emits on a double tap** — the worked-example pad emits `Option+Z` due to firmware-side double-tap detection. If yours emits a different chord, update manipulator 12's `from` accordingly. If yours emits the _same_ keycode for single and double tap (no firmware discrimination), use the USB-style software detection pattern (mirror manipulators 9 + 10 to the BT keycode and drop manipulator 11).
- If you don't care about Bluetooth: delete the BT-side manipulators (numbers 5-8 and 11-12 — the ones whose `from` uses `page_up` / `page_down` / `equal_sign` / `left_option`+`z`), and remove the BT identifier from every remaining `device_if`. You'll end up with 6 manipulators instead of 12.
- If you don't want the top-button double-tap (you need Fn-as-push-to-talk, or one binding is enough): delete manipulators 1 and 5 (the `variable_if`-guarded paste detectors), and replace manipulators 2 and 6 with the simpler immediate-Fn form — drop `parameters`, `to_delayed_action`, and `variable_if`; set `to: [{ "apple_vendor_top_case_key_code": "keyboard_fn" }]`. You'll go from 12 → 10 manipulators.
- If you don't want the bottom-button double-tap (you want `up_arrow` to auto-repeat for fast scrolling, or a single-action key is enough): on USB, delete manipulator 9 and replace 10 with a single immediate-target manipulator (drop `parameters`, `to_delayed_action`, and `variable_if`; set `to: [{ "key_code": "up_arrow" }]`). On BT, delete manipulator 12 (the `Option+Z` translator) and keep 11 (the `equal_sign` → `up_arrow` immediate translator). You'll go from 12 → 10 manipulators. Note: this still won't restore auto-repeat over BT — the pad's firmware emits one discrete event per gesture either way.
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
# Expect: manipulator_count: 12 (or 6 if you dropped the BT side; or 10 if you dropped one button's double-tap pair)
```

**Functional test** (the only test that matters):

| Action                               | Expected result                                                                                                                                                                                                                     |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Single-tap Top (don't press fast)    | After ~200ms, Fn fires once. Typeless / dictation UI toggles on (or off, on the next single-tap).                                                                                                                                   |
| Double-tap Top (fast, <200ms)        | The system clipboard is pasted at the cursor. Same effect as ⌘V.                                                                                                                                                                    |
| Single-tap Middle (don't press fast) | After ~200ms, a newline is inserted. In Claude Code: text bumps to next line; in Slack: new line in composer.                                                                                                                       |
| Double-tap Middle (fast, <200ms)     | The message is sent / Return fires immediately on the second press.                                                                                                                                                                 |
| Single-tap Bottom (don't press fast) | The cursor / selection moves up one line. On USB this fires after ~200ms; on BT the pad's firmware decides "single tap" and emits `equal_sign` immediately. Either way, one `up_arrow` keystroke.                                   |
| Double-tap Bottom (fast)             | The cursor / selection moves down one line. On USB the second press triggers the `variable_if` detector (immediate `down_arrow`). On BT the pad's firmware emits `Option+Z` which Karabiner translates to `down_arrow` immediately. |
| Hold Bottom                          | Exactly one `up_arrow` fires (no auto-repeat). This is by design on both transports — see the bottom-button caveat above.                                                                                                           |

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

Keep the `set_variable` + `device_if` + `variable_if` structure unchanged. **Use a distinct variable name per button** (the rule above uses `macrokeybot_top_tap`, `macrokeybot_middle_tap`, `macrokeybot_bottom_tap`) — sharing a variable across buttons would let a tap on one button arm the double-tap detector on another.

The same alternates table works for the top button — common pairings:

| Use case                           | Single-tap target         | Double-tap target             | Framing                                                    |
| ---------------------------------- | ------------------------- | ----------------------------- | ---------------------------------------------------------- |
| Dictation + paste (our default)    | `Fn` (Typeless toggle)    | `Cmd+V` (paste)               | Dictation is two-handed; paste is the one-handed companion |
| Mute mic + push-to-talk substitute | `Cmd+Shift+M` (Zoom mute) | `Cmd+Shift+A` (toggle audio)  | Mute is fast, audio toggle is deliberate                   |
| Copy + copy-path in Finder         | `Cmd+C`                   | `Cmd+Option+C`                | Everyday copy is fast, "copy full path" is deliberate      |
| App launcher pair                  | `open -a 'Notes'`         | `open -a 'Notes' && new note` | Switch is fast, create-and-switch is deliberate            |

And for the bottom button — pair two related actions where the single-tap is the more common one:

| Use case                       | Single-tap target         | Double-tap target         | Framing                                                                                                                                                                                                   |
| ------------------------------ | ------------------------- | ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Cursor up + down (our default) | `up_arrow`                | `down_arrow`              | Both reversible; pick the direction you reach for more often as the single-tap (we picked `up_arrow` because the bottom key sits closer to the user when worn around the neck — going "up" feels natural) |
| Browser tab navigation         | `Cmd+]` (next tab)        | `Cmd+W` (close tab)       | Switching tabs is fast; closing one needs intent                                                                                                                                                          |
| Read receipt + archive         | `Cmd+Shift+U` (mark read) | `e` (Gmail/Slack archive) | Triage is fast; archival commits to action                                                                                                                                                                |
| Window cycle + close           | `Cmd+\`` (next window)    | `Cmd+W` (close window)    | Switching windows is fast; closing needs intent                                                                                                                                                           |

> **Heads-up if your bottom-button BT signals differ**: the worked-example pad uses pad-firmware-side double-tap detection on BT (`equal_sign` for single, `Option+Z` for double). If you change the bottom button's targets, you only need to update the `to` arrays of manipulators 9 (USB detector), 10 (USB handler's `to_if_invoked`), 11 (BT single-tap translator), and 12 (BT double-tap translator). The `from` keycodes are pad-firmware-defined and don't change.

If you'd rather keep the bottom button as a single-action key (no double-tap layer), the decision-tree table in [`SKILL.md`](../SKILL.md#decision-tree-which-target-keycode) shows common target JSON for Fn, media keys, shell commands, app launchers, etc. — see the "Adapt for your pad" recipe above for collapsing the pair back into a single immediate-target manipulator per transport.

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

This walkthrough distills ~2 days of live exploration on a Jieli/Free3-P 3-key pad, captured in [`01-hardware-identification.md`](01-hardware-identification.md) through [`08-bluetooth-configuration.md`](08-bluetooth-configuration.md). The middle-button tap/double-tap pattern was added on 2026-04-23 to give Return a safer-than-default behavior; the same pattern was extended to the top button on 2026-04-24 (single-tap → Fn for Typeless toggle, double-tap → Cmd+V paste); to the bottom button on 2026-05-02 (initially single-tap → `down_arrow` cursor nudge, double-tap → `Cmd+Delete` line-clear); and revised later the same day to single-tap → `up_arrow`, double-tap → `down_arrow`. The 2026-05-02 revision also surfaced a hardware-level surprise: **the pad's BT firmware runs its own double-tap detection on the bottom button only**, emitting `equal_sign` for single tap and `Option+Z` for double tap. The rule was restructured to translate those firmware-decided keycodes immediately on BT while keeping the original `set_variable` + `to_delayed_action` software discrimination on USB (where the pad emits `Ctrl+X` for every press). Top + middle buttons remain pure software discrimination on both transports. All patterns, traps, and adaptation notes here have been field-tested on the development laptop. If a detail doesn't survive contact with your reality, open an issue — this file is meant to evolve.
