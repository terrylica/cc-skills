# Bluetooth Roadmap

Plan for enabling and integrating the pad's Bluetooth mode. Not yet implemented — this document is the upfront thinking so that when we do the work, we don't rediscover basics.

## Goal

Make the pad usable wirelessly via Bluetooth, with the same button behavior as the USB-C wired mode (top=Fn, middle=Return, bottom=reserved), so user experience is transport-agnostic.

## Preliminary Questions to Answer First

Before touching any code or config, we need to answer these by physical inspection + pairing attempt:

1. **Does the pad have a visible mode switch, BT pairing button, or BT indicator LED?** Check the enclosure carefully. Some cheap pads require a specific key combo (e.g., holding all 3 keys for 5 seconds) to enter pairing mode.
2. **What BT spec does it advertise?** Classic BT-HID (which pairs like a standard keyboard), or BLE HID (which needs macOS 10.15+ and is paired differently)?
3. **Is the radio always-on, or does it require USB power to be advertising?** Some pads use the USB-C port for both power _and_ data, with BT as an alternative radio that only works when powered externally.
4. **What's the Bluetooth VID/PID?** Often different from the USB VID/PID even for the same physical device. We'll need this to write a Karabiner rule scoped to the BT peripheral.

## Expected Pairing Flow

Standard Bluetooth HID peripheral discovery on macOS:

1. Put the pad in pairing mode (per its manual or the mode-switch above).
2. Open System Settings → Bluetooth.
3. Wait for "USB Composite Device" (or another name — BT device name is typically distinct from USB name) to appear.
4. Click Connect.

If the pad is BLE-HID, macOS pairs silently without a prompt. If Classic BT-HID, macOS may show a PIN dialog.

## Identifying the BT Peripheral for Karabiner

Once paired, capture the Bluetooth device identifiers:

```bash
# Non-sudo CLI (using macOS built-in)
system_profiler SPBluetoothDataType 2>/dev/null | grep -A 20 -i "jieli\|macro"

# Via Karabiner's device list (once pad sends a keystroke)
karabiner_cli --list-connected-devices | jq '.[] | select(.is_bluetooth == true)'
```

Karabiner exposes Bluetooth devices with their own identifiers; the Bluetooth transport reports a different `device_id` and potentially different `vendor_id`/`product_id` than the USB transport.

## Karabiner Rule Strategy

Two options:

**Option A — Two separate rules** (USB and Bluetooth transport each get their own `device_if` block):

```json
{
  "description": "Jieli macro pad USB",
  "manipulators": [ ... conditions: device_if with USB VID/PID ... ]
},
{
  "description": "Jieli macro pad Bluetooth",
  "manipulators": [ ... conditions: device_if with BT VID/PID ... ]
}
```

Clear separation, easy to disable either transport independently. Downside: 2x maintenance if rules change.

**Option B — Single rule with two `device_if` identifiers**:

```json
"conditions": [{
  "type": "device_if",
  "identifiers": [
    {"vendor_id": 19530, "product_id": 16725},
    {"vendor_id": <BT_VID>, "product_id": <BT_PID>}
  ]
}]
```

One rule matches either transport. Less duplication. Preferred if both transports use identical button behavior (which is the plan).

**Recommendation**: Option B, with a note in the rule description saying "matches both USB and Bluetooth transports."

## Open Risks

- **BT-HID Fn capability**: Karabiner's Virtual HID Device emits Fn successfully regardless of the source device. That part is already solved — the new transport doesn't affect emission. But _input_ on BT might have different timing/batching characteristics than USB, which could affect the `simultaneous` rule's 50ms threshold. Worth testing.
- **Auto-reconnect after Mac wake-up**: Some BT keyboards require re-pressing a key to reconnect after the Mac sleeps. If that's the case here, Karabiner might briefly miss events during the reconnect. Not a blocker — just a UX wart to document.
- **Power management**: If the pad has a battery, how does it charge? USB-C probably. How does it indicate low battery? Battery service UUID, or a dumb LED, or nothing at all? Affects documentation.
- **Interference with other BT keyboards**: Macropads with cheap BT radios sometimes interfere with other nearby BT inputs. Worth testing with Magic Keyboard/Magic Trackpad attached.
- **Bluetooth TCC implications**: On macOS Sequoia, pairing a new HID device sometimes re-prompts for Input Monitoring on every app that uses `CGEventTap`. Karabiner should not need re-approval (the TCC grant is per-app, not per-input-device), but Typeless might. Worth a quick check after pairing.

## Deliverables for the Bluetooth Phase

When we do this work, the completion criteria:

1. Pad successfully pairs with macOS and survives sleep/wake.
2. BT VID/PID captured and documented in `01-hardware-identification.md` (separate section).
3. Karabiner rule updated (Option B) to cover both transports.
4. Button behavior verified in BT mode (top=Fn triggers Typeless, middle=Return inserts newline, bottom=passes through).
5. Behavior across transport switch verified: plug USB → pad works. Unplug USB, BT takes over → pad still works. No config change required.
6. Battery / power management behavior documented (if applicable).
7. This roadmap file replaced by an `06-bluetooth-configuration.md` describing the final setup, matching the structure of `02-usb-wired-configuration.md`.

## Scope Cut

Deliberately out of scope for this phase:

- Multi-host BT switching (some pads support pairing with 2-3 devices and switching between them). Unless the pad has this feature _and_ user wants it, ignore.
- BT firmware update (if the pad exposes DFU). Not attempting firmware mods — pad's factory firmware is fine.
- Custom BT profile (reporting as a different device name). Beyond the needs of remapping.
