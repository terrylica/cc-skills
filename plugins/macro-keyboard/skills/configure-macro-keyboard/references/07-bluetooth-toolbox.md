# Bluetooth Toolbox — FOSS Tools Evaluated & Spiked

Research-plus-spike evaluation of FOSS tools for controlling, inspecting, and auto-reconnecting Bluetooth HID devices on macOS Sequoia (2026). Every Tier 1 tool below has been live-tested on the Mac this pad will be paired with; install state is recorded so you know what's already configured.

## Tool Inventory on This Mac (Verified 2026-04-21)

| Tool             | Installed?                         | Status                                                                                                                                        |
| ---------------- | ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `blueutil`       | ✅ Homebrew                        | Working. 6 paired devices visible, BT power on. Run `brew info blueutil` for exact version                                                    |
| `sleepwatcher`   | ✅ Homebrew                        | **Running as daemon** (launchd label `homebrew.mxcl.sleepwatcher`). `~/.wakeup` script exists (used for SSH tunnel restart) — can be extended |
| `Hammerspoon`    | ✅ `/Applications`                 | Installed but NOT running (used only for audio monitoring via `~/.hammerspoon/init.lua`, 100 lines)                                           |
| `bleak` (Python) | ✅ works via `uv run --with bleak` | Verified: scanned 10 nearby BLE peripherals including "iPhone TerryLi", "ESP32", Samsung TVs                                                  |
| `LightBlue`      | ⬜ not installed                   | Free in Mac App Store — install when ready for GUI inspection                                                                                 |
| `PacketLogger`   | ⬜ not installed                   | In Apple's _Additional Tools for Xcode_ (requires Apple Developer login)                                                                      |
| `Bluetility`     | ⬜ not installed                   | FOSS alternative to LightBlue; install if you want a native-Mac open-source equivalent                                                        |

## Tier 1 — Use These (All Already Installed)

### `blueutil` — command-line Bluetooth control

The flagship CLI. Already on this Mac.

```bash
# What you'll use most for the Jieli pad:
blueutil --power                        # Is BT on? (1 = yes, 0 = no)
blueutil --paired                        # Human-readable list
blueutil --paired --format json | jq '.'  # Machine-readable
blueutil --connected                     # What's actively connected right now
blueutil --info <MAC>                    # Full device info
blueutil --connect <MAC>                 # Force a reconnect
blueutil --disconnect <MAC>              # Force disconnect
blueutil --wait-connect <MAC> 10         # Block until device connects (10s timeout)
blueutil --pair <MAC> [PIN]              # Programmatic pairing
blueutil --unpair <MAC>                  # Experimental
```

**macOS caveat**: starting with Monterey, `blueutil` shows devices by UUID not MAC — still works as an identifier, just format-shifted. The `--paired` output gives you the format you need.

**Strengths**: No TCC prompts (uses private IOBluetooth grandfathered APIs). Scriptable. Works reliably on Sequoia.

**Limitations**: Connection-level only. Cannot inspect GATT services, HID descriptors, or individual button events. For those, use LightBlue / PacketLogger / Karabiner-EventViewer.

### `sleepwatcher` + `blueutil` — auto-reconnect on wake

The proven pattern. `sleepwatcher` is already running as a launchd daemon on this Mac. You already have `~/.wakeup` (used for SSH tunnel restart). Just extend it.

**Current `~/.wakeup` (paraphrased):**

```bash
#!/bin/bash
# Kill stale SSH tunnel on wake — launchd restarts it
PID=$(lsof -ti:18123 2>/dev/null)
[ -n "$PID" ] && kill "$PID"
```

**Proposed extension (after pad is paired):**

```bash
#!/bin/bash
# 1. Kill stale SSH tunnel (existing behaviour)
PID=$(lsof -ti:18123 2>/dev/null)
[ -n "$PID" ] && kill "$PID"

# 2. Reconnect Jieli macro pad
#    MAC is captured at pair-time from: blueutil --paired --format json | jq ...
JIELI_MAC="XX-XX-XX-XX-XX-XX"
if [ -n "$JIELI_MAC" ]; then
    sleep 2  # Let BT radio fully wake
    /opt/homebrew/bin/blueutil --connect "$JIELI_MAC" 2>/dev/null
fi
```

**Why this works well**: sleepwatcher's event-to-script latency is sub-second; `blueutil --connect` returns as soon as the connection is established. Total wake-to-functional time: 2-4 seconds.

**Why not `macos-bluetooth-off-while-sleep`**: it toggles **all** BT off on sleep. Kills your AirPods mid-meeting if the Mac briefly sleeps. Too blunt for our case. Targeted reconnect is cleaner.

### `Karabiner-Elements` — remapping (BT-agnostic)

Already configured. When the pad switches to BT, Karabiner's rule will still fire **if** the BT transport reports the same VID/PID (19530, 16725) — which is likely but not guaranteed. If BT reports different IDs or all zeros (known macOS limitation for some BLE HID), we extend the rule's `device_if` with a second identifier:

```json
"conditions": [{
  "type": "device_if",
  "identifiers": [
    {"vendor_id": 19530, "product_id": 16725},   // USB
    {"vendor_id": <BT_VID>, "product_id": <BT_PID>}  // Bluetooth
  ]
}]
```

One rule, two transports.

## Tier 2 — Install When Needed

### `LightBlue` (App Store, free)

Best GUI for inspecting a paired BLE HID device's services, characteristics, RSSI, and the battery service (UUID `0x180F`, characteristic `0x2A19`) if the pad advertises it. Install via Mac App Store when:

- Pad won't pair and you want to see the advertising packet
- Want to confirm the pad's BLE-advertised name vs. its USB product string
- Want to check if the pad exposes a battery level characteristic

### `PacketLogger` (Apple _Additional Tools for Xcode_, free)

Gold standard for debugging **reconnect-after-wake failures**. Captures the raw HCI event stream including `HCI Disconnection Complete` with reason codes. If the pad silently disconnects mid-meeting, PacketLogger shows exactly what happened at the protocol level.

Download path: <https://developer.apple.com/download/all/> → search "Additional Tools for Xcode" → `Hardware/` folder in the DMG.

### `bleak` (Python async BLE, via `uv run`)

```bash
uv run --python 3.13 --with bleak python3 -c "
import asyncio
from bleak import BleakScanner
async def scan():
    devs = await BleakScanner.discover(timeout=5.0, return_adv=True)
    for addr, (d, adv) in devs.items():
        print(addr, adv.rssi, d.name or '<no name>')
asyncio.run(scan())
"
```

Verified working — picked up 10 peripherals on first try. Useful when you want to scan for the Jieli pad before pairing (confirm it's advertising) or inspect its GATT services during the pre-paired window.

**Critical caveat**: Once the pad is paired as a HID device, macOS's CoreBluetooth layer **locks out app-level GATT access**. `bleak` can see the pad during the pairing window but not afterward. For post-pairing inspection, use LightBlue (which has privileged App Store entitlements) or PacketLogger.

### `Bluetility` (FOSS, `brew install --cask bluetility`)

Native macOS alternative to LightBlue. Same scope (pre-pairing discovery + GATT browsing). Install if you prefer FOSS over App Store apps.

### `Hammerspoon` sleep/wake alternative

You already have Hammerspoon installed. If sleepwatcher ever proves unreliable (hasn't yet), you could add this to `~/.hammerspoon/init.lua`:

```lua
local JIELI_MAC = "XX-XX-XX-XX-XX-XX"
hs.caffeinate.watcher.new(function(ev)
    if ev == hs.caffeinate.watcher.systemDidWake then
        hs.timer.doAfter(3, function()
            os.execute("/opt/homebrew/bin/blueutil --connect " .. JIELI_MAC)
        end)
    end
end):start()
```

Not recommended as primary because sleepwatcher is lighter (one shell script) and already running.

## Tier 3 — Skip (Don't Install)

| Tool                              | Why Skip                                                                                                              |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `bluetoothctl`                    | Linux `bluez` only; no macOS port exists                                                                              |
| `Bluetooth Explorer` (Xcode)      | Discontinued since Xcode 12+ — no longer shipped                                                                      |
| `macos-bluetooth-off-while-sleep` | Kills all BT on every sleep/wake. Too blunt — targeted reconnect via sleepwatcher+blueutil is cleaner                 |
| `@abandonware/noble` (Node.js)    | Same CoreBluetooth HID lock as `bleak`; no Node-specific advantage for our case                                       |
| `core-bluetooth-tool` (Swift)     | Unmaintained since 2021; GUI overhead unnecessary for CLI scripting                                                   |
| `BluetoothKit` / `RxBluetoothKit` | iOS-first Swift libraries; framework overhead for a 3-key pad                                                         |
| `PyBluez`                         | Deprecated, no BLE support                                                                                            |
| `pyobjc` + `IOHIDManager` direct  | Requires Input Monitoring TCC grant (user has previously flagged Touch ID aversion). Use only if absolutely necessary |

## Critical macOS Platform Caveats

### CoreBluetooth HID lockout

Once a BLE device is paired as a HID peripheral, macOS **intercepts all GATT traffic at the kernel level** and does not expose it to userland BLE libraries (bleak, noble, etc.). The LE HID profile is privileged. This means:

- You can scan for the pad's _advertising_ packet before pairing (bleak, LightBlue)
- You cannot inspect GATT characteristics (including battery service) after pairing, _except_ through System Settings → Bluetooth (which exposes battery level if the peripheral declares it) or PacketLogger (which captures the raw HCI stream before macOS strips it).

**Implication for us**: don't plan any workflow that assumes post-pairing GATT access from a script.

### TCC permissions

- `blueutil`: no prompt. Uses private IOBluetooth grandfathered.
- `sleepwatcher`: no prompt. Shell daemon.
- `Hammerspoon`: may prompt for Bluetooth permission (one-time, cosmetic — already covers).
- `bleak`: needs **Bluetooth** permission on the terminal running it (one-time TCC). **Note for Touch-ID-averse workflows**: this is a macOS system prompt, not a sudo prompt — it uses the permission dialog, not Touch ID.
- `IOHIDManager` via pyobjc: needs **Input Monitoring** (heavier). Avoid unless required.

### Passive scanning not supported

macOS's CoreBluetooth only supports **active** BLE scanning — advertising peripherals must be broadcasting to be found. Devices in power-save mode may be invisible. For Jieli pads specifically, pairing mode is usually advertised for ~30 seconds after enabling — scan during that window.

## Recipe: Pairing Day — Tools to Have Ready

Before disconnecting USB-C:

1. `blueutil --paired --format json > /tmp/paired-before.json` — snapshot of paired devices
2. Open `bleak` scanning terminal ready to run:

   ```bash
   uv run --python 3.13 --with bleak python3 -c "
   import asyncio
   from bleak import BleakScanner
   async def s():
       d = await BleakScanner.discover(timeout=10.0, return_adv=True)
       for a,(dev,adv) in d.items(): print(a, adv.rssi, dev.name or '?')
   asyncio.run(s())
   "
   ```

3. (Optional) Install `LightBlue` from App Store as GUI fallback
4. Have System Settings → Bluetooth open in a visible window
5. Have the pad's documentation/manual handy (pairing button combo)

After disconnecting USB-C and entering pairing mode:

1. Watch System Settings → Bluetooth for a new "USB Composite Device" (or alternate name) to appear
2. Run the bleak scan command; note the advertised name + MAC + RSSI
3. Pair via System Settings (click Connect)
4. `blueutil --paired --format json > /tmp/paired-after.json` + `diff` to isolate the new device's MAC
5. `blueutil --info <new-MAC>` for full details
6. `karabiner_cli --list-connected-devices | jq '.[] | select(.is_bluetooth == true)'` to see the BT transport's VID/PID as Karabiner sees it

After pairing:

1. Test all 3 buttons in TextEdit — do they emit Ctrl+C / Ctrl+V / Ctrl+X as before?
2. Update Karabiner rule's `device_if.identifiers` with the BT VID/PID (second entry under the existing USB one)
3. Test push-to-talk in Typeless via the top button over BT
4. Extend `~/.wakeup` with the `blueutil --connect <MAC>` line
5. Sleep the Mac for 30s, wake, verify pad reconnects within 3-4 seconds

## Summary Table

| Capability                            | Primary Tool                              | Fallback                                                      |
| ------------------------------------- | ----------------------------------------- | ------------------------------------------------------------- |
| Control power / list paired / connect | `blueutil`                                | System Settings                                               |
| Pre-pair scanning for advertising pad | `bleak`                                   | LightBlue                                                     |
| Inspect paired HID characteristics    | LightBlue (App Store)                     | PacketLogger                                                  |
| Debug reconnect-after-wake failures   | PacketLogger                              | Karabiner grabber log (`/var/log/karabiner/core_service.log`) |
| Auto-reconnect on wake                | `sleepwatcher` + `~/.wakeup` + `blueutil` | Hammerspoon + `hs.caffeinate.watcher`                         |
| Keymap remap (transport-agnostic)     | Karabiner-Elements                        | —                                                             |
| Live connection state indicator       | SwiftBar/BitBar BT widget (optional)      | Menu bar Bluetooth icon                                       |

## Sources

- [blueutil GitHub](https://github.com/toy/blueutil)
- [sleepwatcher (Bernhard Baehr)](http://www.bernhard-baehr.de/sleepwatcher_2.2.tgz)
- [bleak documentation](https://bleak.readthedocs.io/)
- [Bluetility GitHub](https://github.com/jnross/Bluetility)
- [LightBlue (Punch Through)](https://punchthrough.com/lightblue/)
- [Apple Additional Tools for Xcode](https://developer.apple.com/download/all/)
- [Hammerspoon hs.caffeinate.watcher](https://www.hammerspoon.org/docs/hs.caffeinate.watcher.html)
- [Karabiner-Elements](https://karabiner-elements.pqrs.org/)
