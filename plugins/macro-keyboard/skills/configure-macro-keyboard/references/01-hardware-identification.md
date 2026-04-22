# Hardware Identification

Everything discoverable about the device from macOS without opening it up.

## USB Device Descriptor

| Field                    | Value                  | Interpretation                                                                                                    |
| ------------------------ | ---------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `bcdUSB`                 | `1.10`                 | USB 1.1 spec (Full Speed only)                                                                                    |
| `bDeviceClass`           | `0` (Unknown)          | Per-interface class (device is composite)                                                                         |
| `idVendor`               | `0x4c4a` (19530)       | Jieli Technology Co., Ltd. — Chinese AV SoC manufacturer. Not in the common usb.ids fork, so lsusb shows bare hex |
| `idProduct`              | `0x4155` (16725)       | Product identifier within Jieli's space                                                                           |
| `bcdDevice`              | `1.00`                 | Firmware version 1.0 (factory, never updated)                                                                     |
| `iManufacturer` (string) | `Jieli Technology`     | Generic — indicates the pad vendor did not customize firmware strings                                             |
| `iProduct` (string)      | `USB Composite Device` | Generic default — strongly suggests white-label reference firmware                                                |
| `iSerialNumber` (string) | `433132303730362E`     | Hex of ASCII `C1207062.` — likely a factory-assigned unit ID, trailing period is significant                      |
| `bNumConfigurations`     | `1`                    | Single USB configuration                                                                                          |
| `MaxPower`               | 100 mA                 | Low-power device (typical for a 3-button pad with no LEDs)                                                        |
| Negotiated speed         | `12 Mbps`              | Full Speed — confirms the MCU does not implement USB 2.0 High Speed                                               |

## USB Interface Structure

The device is a **USB Composite Device** with 4 interfaces — one HID, one mass storage, and a CDC ACM serial pair:

| Interface | Class                 | Subclass      | Protocol               | Purpose                                                                              |
| --------- | --------------------- | ------------- | ---------------------- | ------------------------------------------------------------------------------------ |
| 0         | `0x08` (Mass Storage) | `0x06` (SCSI) | `0x50` (BBB)           | Virtual disk — dormant on macOS (activates only on Windows for config tool delivery) |
| 1         | `0x03` (HID)          | `0x00` (None) | `0x01` (Boot Keyboard) | The actual keyboard interface. Emits standard 8-byte keyboard reports                |
| 2         | `0x02` (CDC)          | `0x02` (ACM)  | `0x01` (AT commands)   | Control endpoint for a virtual serial port                                           |
| 3         | `0x0A` (CDC Data)     | —             | —                      | Data endpoint paired with interface 2                                                |

On macOS, the CDC interfaces spawn `/dev/cu.usbmodem103` and `/dev/tty.usbmodem103`. The serial port is quiet at 9600 8N1 (no unsolicited output). The protocol for driving it is not publicly documented — likely used by a Windows-only vendor config tool.

## HID Report Descriptor

Captured via `ioreg -c IOHIDDevice` (full hex in [`references/ioreg-hid-device.txt`](references/ioreg-hid-device.txt)):

```
05 01          Usage Page (Generic Desktop)
09 06          Usage (Keyboard)
A1 01          Collection (Application)
  05 07          Usage Page (Key Codes)
  19 E0          Usage Minimum (0xE0 = Left Control)
  29 E7          Usage Maximum (0xE7 = Right GUI)
  15 00          Logical Minimum (0)
  25 01          Logical Maximum (1)
  75 01          Report Size (1 bit)
  95 08          Report Count (8)
  81 02          Input (Data, Variable, Absolute) — 8 bits for modifiers
  95 01          Report Count (1)
  75 08          Report Size (8)
  81 01          Input (Constant)                    — 1 reserved byte
  95 06          Report Count (6)
  75 08          Report Size (8)
  15 00          Logical Minimum (0)
  25 FF          Logical Maximum (255)
  05 07          Usage Page (Key Codes)
  19 00          Usage Minimum (0)
  29 FF          Usage Maximum (255)
  81 00          Input (Data, Array)                 — 6 bytes of keycodes
C0             End Collection
```

This is a **bog-standard USB HID boot keyboard report** (1 byte modifiers + 1 reserved + 6 keycodes = 8 bytes). It's the same descriptor shipped by nearly every cheap keyboard. There is no vendor-specific HID usage page, no additional consumer control usage, and no configuration endpoint advertised over HID.

**Implication**: the pad identifies itself as "just a keyboard" to macOS, which is why BTT/Karabiner/macOS all treat its events identically to any other keyboard. Remapping happens because we can filter by VID/PID, not because the pad offers any special protocol.

## Firmware Button Wiring (verified 2026-04-21)

Pressing each physical button emits a **full Ctrl-modifier + letter combo** (both modifier and key in one HID report):

| Physical button | Emitted combo      |
| --------------- | ------------------ |
| Top             | `Left Control + C` |
| Middle          | `Left Control + V` |
| Bottom          | `Left Control + X` |

Note: this is **not** the conventional cut/copy/paste order (which would be C→X→V top-to-bottom). The middle button emits V, not X. This was verified experimentally — assumptions about pad layouts should always be verified via Karabiner-EventViewer or similar, never inferred from "standard" conventions.

## Chip / SoC Family (Inferred)

Jieli's registered USB VID is `0x4c4a`. Chips in their AC69xx family commonly drive composite USB devices with this exact interface mix (HID + Mass Storage + CDC ACM). Candidate SoCs, in order of likelihood based on this device's capabilities:

- **AC6966B** / **AC6925** — mid-range SoCs with USB HID + mass storage + serial over USB. Common in 2020-era cheap macro pads.
- **AC6955** — slightly newer variant.

Without physical PCB inspection (or running a Windows vendor tool that reveals the chip version), this is inferred — not confirmed. If PCB inspection becomes relevant, the markings to look for are `AC69xxB` or `JL AC69xx` silkscreened on the main chip.

## Why This Device is NOT QMK/VIA-Compatible

QMK firmware runs on specific microcontroller families: AVR (ATmega32u4), ARM Cortex-M0/M4 from ST/NXP, and RP2040. Jieli SoCs use a proprietary RISC core (not ARM, not AVR) and are not supported by QMK. VIA and Vial are client-side tools that speak a specific HID command set only present in QMK/Vial firmware, so they cannot detect or configure this pad.

**The firmware is also not user-reprogrammable on macOS**. Jieli's factory flashing tools are Windows-only; the 64-byte raw HID config channel (if present) is not publicly documented. To change which keycode each button emits, you must remap _after_ the fact at the OS level (as we do with Karabiner).

## Device Signature for Rule Scoping

When writing any OS-level rule (Karabiner, `hidutil`, custom tools) that should apply _only_ to this pad and not to the Apple built-in keyboard or any other connected keyboard, match on:

```json
{
  "vendor_id": 19530,
  "product_id": 16725
}
```

or in hexadecimal for `hidutil`:

```json
{ "VendorID": 0x4c4a, "ProductID": 0x4155 }
```

The serial number can be used for additional uniqueness if you happen to own multiple identical pads, but for a single-unit use case the VID/PID pair is sufficient and more portable.
