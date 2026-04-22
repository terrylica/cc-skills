# HID Keycode Diagnostic Workflow — Expanded

The SKILL.md gives the essentials. This expansion covers three cases that trip people up:

1. Modifier + key in ONE HID report vs. sequential reports
2. Consumer keys (media/volume) that don't show in EventViewer's Main tab
3. Multi-interface devices where only one interface emits the button you care about

## Case 1 — Telling Single-Report Combos from Sequential

Cheap pads emit `Ctrl+C` either as:

**A. One HID report** (report descriptor has the modifier byte set):

```
0x01 0x00 0x06 0x00 0x00 0x00 0x00 0x00
 │    │    │
 │    │    └─ keycode: C (0x06)
 │    └─ reserved
 └─ modifiers byte: left_control (0x01)
```

**B. Two sequential reports** (first modifier, then key):

```
Report 1: 0x01 0x00 0x00 0x00 0x00 0x00 0x00 0x00   (modifier alone)
Report 2: 0x01 0x00 0x06 0x00 0x00 0x00 0x00 0x00   (modifier + key)
```

In Karabiner-EventViewer, both look similar but the **microsecond timestamps differ**:

- Single report: `left_control` and `c` share the exact same timestamp (e.g. `13:44:02.123456`)
- Sequential: `left_control` fires ~milliseconds before `c`

**Rule for writing the Karabiner matcher**:

| Emission pattern | Karabiner matcher                                                                                                  |
| ---------------- | ------------------------------------------------------------------------------------------------------------------ |
| Single report    | `"from": {"simultaneous": [{...ctrl}, {...c}], "simultaneous_options": {"detect_key_down_uninterruptedly": true}}` |
| Sequential       | `"from": {"key_code": "c", "modifiers": {"mandatory": ["left_control"]}}`                                          |

**If unsure, use `simultaneous`** — it matches both patterns. The opposite is not true.

## Case 2 — Consumer Keys Don't Show in Main Tab

If you press a button and nothing shows in EventViewer's Main tab, check the **Unknown Events** tab. Media keys (play/pause, volume, brightness) are emitted on HID Usage Page `0x0C` (Consumer), not Usage Page `0x07` (Keyboard). Karabiner's Main tab only shows Keyboard page events.

When you find a consumer event, the matcher in Karabiner looks like:

```json
"from": {"consumer_key_code": "volume_increment"}
"from": {"consumer_key_code": "volume_decrement"}
"from": {"consumer_key_code": "play_or_pause"}
"from": {"consumer_key_code": "scan_previous_track"}
"from": {"consumer_key_code": "scan_next_track"}
```

The target uses the same namespace if you want to emit media keys: `"to": [{"consumer_key_code": "..."}]`.

## Case 3 — Multi-Interface Devices

A "USB Composite Device" like the Jieli 3-key pad typically exposes 2-4 USB interfaces (Keyboard HID, Consumer HID, System Control HID, Vendor HID). Each interface is a separate grabbable entity in Karabiner.

**Symptom**: your device_if rule matches but only some buttons trigger.

**Diagnose**:

```bash
# List all interfaces with their Karabiner device IDs
karabiner_cli --list-connected-devices | jq '.[] | select(.vendor_id == 19530)'
```

Each output item is a separate interface. Look at `is_keyboard`, `is_consumer`, `is_pointing_device`, `is_game_pad` flags.

**Fix**: if your button emits on a non-keyboard interface, the default Karabiner `device_if` (which implicitly scopes to `is_keyboard=true`) won't match. Either:

- Add `is_consumer: true` to the identifier, or
- Let Karabiner match multiple interfaces:

```json
{ "vendor_id": 19530, "product_id": 16725 }
```

(No `is_keyboard` constraint means it matches across interface types.)

## The `vk_none` No-Op Trick

For a diagnostic rule that does nothing but forces Karabiner to grab the device so EventViewer can see events:

```json
{
  "type": "basic",
  "from": { "key_code": "vk_none" },
  "to": [{ "key_code": "vk_none" }],
  "conditions": [
    {
      "type": "device_if",
      "identifiers": [{ "vendor_id": 19530, "product_id": 16725 }]
    }
  ]
}
```

`vk_none` is a Karabiner virtual key that never matches real input. The rule is inert but the `device_if` scoping forces Karabiner to attach to the device.

## Checklist: Before Concluding "The Button Emits X"

- [ ] Checked Main tab (keyboard events)
- [ ] Checked Unknown Events tab (consumer events)
- [ ] Checked Devices tab — right VID/PID/interface?
- [ ] Pressed the button both briefly and held — some firmware emits different codes on repeat
- [ ] Unplugged & replugged the pad — some pads boot into a different mode after sleep/wake
- [ ] Tested on the _transport you plan to use_ (USB and BT emit different keycodes on the same pad)
- [ ] If pad has multiple firmware modes, mapped all modes (not just the current one)

## Known Unknowns Worth Documenting

When you finish diagnosing a device, document in `configure-macro-keyboard/references/`:

1. VID/PID for USB and for BT (if BT-capable)
2. Number of USB interfaces and which one carries each button
3. Emission pattern per button (single-report vs sequential vs consumer)
4. Firmware modes and the button combos to switch between them
5. Anything that stops emitting after sleep/wake, unplug/replug, or firmware mode switch

This shortens future setup time from hours to minutes.
