# Bluetooth Macro Keyboard Landscape Survey (2026)

Research companion to [`05-bluetooth-roadmap.md`](05-bluetooth-roadmap.md). Summarizes the state of the wireless macro-pad ecosystem so we can enable the Jieli pad's Bluetooth mode with realistic expectations about pairing, battery, latency, reconnect behavior, and available firmware/config options.

## Executive Summary

The Bluetooth macro keyboard ecosystem in 2026 spans from 1-key remote pads to 30+ key programmable boards, with two dominant open-source firmware platforms (ZMK for wireless-first, QMK for USB-heritage devices), software-defined alternatives (Elgato Stream Deck, Loupedeck), and a sprawling AliExpress/Amazon "cheap and cheerful" sector dominated by CH57x/Jieli chipsets. For the Jieli 3-key pad in this project, enabling Bluetooth means navigating pairing complexity unique to these generic chips, managing battery behavior that differs sharply between coin cell and Li-Po designs, and empirically testing auto-reconnect on macOS before relying on wireless in mission-critical workflows like push-to-talk during meetings.

---

## 1. Popular Form Factors and Use Cases

**1-3 key remote control pads** — Push-to-talk for Zoom/Teams, Discord voice-channel toggles, OBS scene hotkeys, single-action shortcuts. Used for hands-free control when the pad sits on a desk or hangs from a lanyard. Bluetooth priority here is convenience (cable-free) over feature depth. This is the Jieli pad's category.

**4-9 key programmable pads** — OBS scene switching, Twitch chat commands, Photoshop tool cycling, Discord PTT + mute + raise-hand combos. Sweet spot for content creators and streamers; small enough to fit beside a keyboard or on a mousepad, large enough for multi-tier layer logic (Fn keys unlocking secondary functions). Most popular form factor in 2026 enthusiast builds.

**12+ key pads and mini keyboards** — Full production workflows (Photoshop palette shortcuts, video editing trim/ripple/slip, Ableton drum patterns), accessibility keyswitches (large mechanical buttons with audible feedback), coding macro sets. Often handwired using QMK or ZMK; USB-C powered for all-day use. Wireless versions rarer due to battery complexity at 12+ keys.

---

## 2. Notable Brand and Product Categories

### Premium Open-Firmware Ecosystem

- **Keebio and community handwired builds**: QMK-powered, often USB-only; enthusiast DIY culture dominates. Vial-compatible boards let users remap without reflashing.
- **Ploopy.co**: Open-source trackballs and peripherals powered by QMK; accessibility/ergonomics focus (USB-based).
- **ZMK-ready platforms**: Nice!Nano controllers (Pro Micro footprint, nRF52840 SoC) used in split keyboards and wireless macro pads. The handwired community around nRF52840 (XIAO nRF52840, SuperMini) is growing rapidly for wireless builds.

### Software-Defined Alternatives (Premium)

- **Elgato Stream Deck family**: 15-key LCD button grid; 200+ plugin integrations; $90–$120 range. Stream Deck Neo offers portability. Not programmable at firmware level — all logic lives in software. USB-only via dock.
- **Loupedeck CT / Live / Live S**: 17+ buttons + 2–3 rotary encoders; targets photo/video editing and streaming. Loupedeck Marketplace with 200+ profiles. Knob-centric design excels at continuous parameter control (audio faders, filter cutoff). $200–$400+. USB-only.

### Hobbyist QMK Macro Pads (5×5 and Smaller)

- **Ziddy Makes ZM K9 / K16**: 9-key and 16-key hotswap with QMK/Vial preloaded; often wooden base cosmetics. $50–$120.
- **TogKey Pad Pocket**: 2-key portable with QMK; Bluetooth version available.
- **Etsy boutique makers**: Custom 9/12/16-key mechanical pads; Vial support increasingly standard.

### Cheap AliExpress / Amazon Generic Sector (Jieli/CH57x territory)

- **CH57x-based pads**: USB 3-key/6-key/12-key "macro keypads" (IDs like `1189:8890`, `1189:8840`, `1189:8842`). No firmware source provided. Configurable via third-party **ch57x-keyboard-tool** (open-source Rust). Bluetooth mode usually undocumented.
- **Jieli-based pads** (our category): similar black-box firmware. Different vendor ID (`0x4c4a`) but same category — cheap AV SoCs repurposed for HID. Less community tooling than CH57x.
- **SayoDevice**: AliExpress pads with vendor GUI (usually Windows-only). Limited macOS support.
- **Amazon house brands**: $10–$30 pads; Bluetooth usually available but pairing sequence varies wildly.

### DIY Microcontroller Boards

- **Adafruit Macropad**: 12-key hotswap with RP2040; CircuitPython/Arduino-compatible. USB-only. Educational focus.
- **Pimoroni Keybow 2040**: 16 RGB buttons, RP2040, CircuitPython. USB-only. Raspberry Pi integration angle.

---

## 3. Bluetooth-Specific Considerations for End Users

### BLE HID vs. Classic Bluetooth HID

**BLE (Bluetooth Low Energy) HID** is the modern standard. Uses HID-over-GATT; negotiates a "connection interval" (how often the host checks for new keypresses). Interval can be 7.5ms–4000ms; short intervals (7.5–30ms) feel snappy but drain battery faster. BLE pairs ~30× faster than Classic BT, though ongoing latency depends on the negotiated interval. Typical end-to-end latency: 8–30ms.

**Classic Bluetooth HID** is legacy; rare in post-2020 pads. Lower ongoing power overhead once paired, but macOS handles it poorly and pairing is finickier. Most new devices skip it entirely.

**For push-to-talk**: BLE with a tight connection interval is responsive enough (typical ~10–20ms latency is imperceptible). macOS doesn't always allow OS-level interval tuning, so device firmware often controls this.

### Pairing Flow Variations

**QMK/ZMK boards**: Hold a dedicated pair button or key combination (e.g., `Fn+P` for 3 seconds) to enter pairing mode. Device appears in System Settings → Bluetooth. Standard BLE pairing, no codes. First-time setup is seamless; re-pairing after a reset is slower (5–10s vs. 1–2s for reconnection).

**Jieli / CH57x pads**: Pairing flow is **manufacturer-specific and often undocumented**. Common patterns:

- Long-press a button (3–5s) to toggle Bluetooth mode on/off.
- Some pads have a dedicated pairing button (paperclip-activated reset hole).
- After power-on in Bluetooth mode, the pad auto-advertises for ~30s; macOS picks it up in Bluetooth settings.
- Gotcha: re-entering pairing mode later often requires the same sequence again, which users forget. Battery timeout is rarely documented.

**Elgato Stream Deck, Loupedeck**: N/A (USB-only).

### Multi-Host Switching

**QMK/ZMK with layer keys**: Boards like Nice!Nano-based split keyboards support "host switch" layers (`Fn+1`, `Fn+2`, `Fn+3` to cycle paired hosts). Works well when the pad stays stationary; fragile when it sleeps and wakes to a different host priority.

**Jieli pads**: Most single-host. Switching hosts usually requires re-pairing or power-cycling.

**Elgato, Loupedeck**: N/A.

### Battery Life Expectations

**Coin cell (CR2032, 230+ mAh)**: Theoretical months of life, **real macro-pad life 2–8 weeks**. BLE transmission causes 5–20 mA current spikes; effective capacity drops to 50–70% under pulsed loads. Repeated peaks >10 mA cause permanent capacity loss. Only viable for light users (<5 presses/day).

**Li-Po pouch (300–500 mAh)**: **5–14 days with moderate daily use** (10–20 presses). Degrades through calendar aging and cycle wear (~300–500 full cycles before notable capacity loss). USB-C charging built-in is standard.

**Hot-swap / user-replaceable cells**: Some boards accept AA/AAA or swappable coin cells. Adds bulk; useful for fieldwork where charging is impractical.

**Charging behavior**: Most ZMK boards support "USB charging while active" (pad works while plugged in). QMK varies. Jieli pads usually stop responding during USB charging — firmware limitation.

### Latency: BLE vs. USB

- **USB**: ~1–5ms end-to-end.
- **BLE**: ~8–30ms depending on connection interval and OS scheduling. macOS typically lands in 10–30ms.

**For push-to-talk**: 20–30ms is imperceptible (human reaction time is ~150–200ms). The bigger real risk is **silent disconnection**, not latency itself.

### Auto-Reconnect After Sleep/Wake on macOS

**Ideal**: Pad disconnects gracefully on Mac sleep, reconnects within 1–2s on wake.

**macOS Sequoia reality**:

- Default config lets Bluetooth stay active during sleep.
- Devices should reconnect within 5s on wake. Some take 10–30s; others never reconnect and require manual re-pairing.
- Workaround: third-party tools like `macos-bluetooth-off-while-sleep` toggle Bluetooth on/off with sleep/wake events for a clean reconnection cycle.
- Known issue: unpaired devices may wake the Mac. The "Allow Bluetooth devices to wake this Mac" toggle was removed in Monterey+, frustrating for users who want to disable this.

### Interference with Magic Keyboard / Magic Trackpad

BLE shares 2.4 GHz with Wi-Fi, Bluetooth mice, Magic Trackpad. Multiple BLE devices in close proximity (pad + Magic Keyboard + Magic Trackpad + AirPods) can occasionally trigger connection dropouts or latency spikes. Impact is minimal if devices are >30cm apart or if they use staggered advertising channels. If your Magic Trackpad is right next to the pad, watch for occasional missed presses during heavy trackpad use.

---

## 4. Firmware and Software for Remapping Bluetooth Macro Pads

### ZMK (Primary Open-Source BLE Firmware)

- **Wireless-first design**. Supports nRF52840 / nRF52833 SoCs (Nordic ARM Cortex-M4).
- **Popular controllers**: Nice!Nano (Pro Micro footprint), XIAO nRF52840, SuperMini nRF52840.
- **Features**: Excellent battery life via aggressive power management; built-in multi-device support (layer keys or dedicated host-select logic); VIA/Vial support via ZMK Studio (still evolving).
- **Config workflow**: Edit `.keymap` files in GitHub → trigger firmware build → download `.uf2` → drag onto the controller's mass-storage mount.
- **Learning curve**: Moderate. Requires Devicetree syntax understanding.

### QMK (USB-Heritage, Bluetooth Bolted-On)

- Historically USB-focused. Wireless support added via external Bluetooth modules (Bluefruit LE nRF51/nRF52) or by porting to nRF SoCs.
- Weaker battery life than ZMK on wireless; no first-class multi-device switching; layer-based workarounds common.
- **VIA** requires vendor-uploaded board definitions. **Vial** is open-source and more friendly; click to change keys, instant save to device.

### Vial (Client Configuration Protocol)

- Works with QMK and (partially) ZMK; ZMK Studio is the ZMK-native equivalent.
- **UX**: Open the Vial app (macOS available at `get.vial.today`), connect the board, click a key, select a new function — change saved immediately to the keyboard. No recompile.
- Limited to 4 layers (same as VIA). Complex macros harder to express in the GUI.

### Vendor-Specific Software

- **SayoDevice config tool**: Windows-only; macOS support uncertain.
- **Stream Deck SDK**: closed-source plugin system; extensive integrations (Twitch, OBS, Discord, Spotify); no custom-firmware remapping.
- **Loupedeck Workbench**: Loupedeck-specific profiling and macro builder.

### OS-Level Remapping via Karabiner-Elements (Our Path)

For Bluetooth pads with no firmware access — i.e., generic Jieli/CH57x — Karabiner is the fallback. It's free, open, battle-tested.

- **Known Bluetooth-specific limitation**: some BLE HID devices report VID/PID as `0`, which prevents `device_if`-scoped remapping. We'll need to empirically check whether our Jieli pad's BT transport exposes the same VID/PID as USB (`0x4c4a 0x4155`), different IDs, or zeros. If zeros, we fall back to a `device_if` match on `is_bluetooth: true` + keycode pattern, which is less precise but still workable.
- **Reconnection issues** can trigger re-remap failures. Karabiner usually handles re-grab automatically, but worth testing.

---

## 5. Patterns Users Report About Using BT Macro Pads Well

### Placement

- **Wrist strap or lanyard**: hands-free PTT in meetings. Needs a responsive connection (<50ms).
- **Mousepad integration**: pad 3M-taped next to a Magic Trackpad — always accessible without reaching. Works for scene-switching during streams.
- **Desk drawer / shelf within reach**: for less-frequent macros (once an hour). Battery lasts longer when the pad isn't jostled.

### Single-Machine Setup

Pair once, leave paired. Much simpler than multi-host. Reliable auto-reconnect once established (barring the edge cases above).

### Nomadic Multi-Host

Pair to phone + tablet + Mac; rotate via a host-selection key. Good for creators jumping platforms. Higher battery impact due to more advertising.

### Low-Battery Workflow

**Critical gotcha**: The pad often goes silent without warning when battery drops below ~5%. BLE stack shuts down to preserve remaining capacity. No "low battery" indicator on most pads. Best practice: charge every 1–2 weeks for daily use, or add a launchd/cron reminder to check battery state every Friday.

### One Button Per High-Value Action

- Button 1 = PTT (Fn → Typeless)
- Button 2 = Mute (app-specific)
- Button 3 = Raise Hand (Zoom-specific)

Avoid complex multi-tap or hold logic on Bluetooth pads — latency makes them feel sluggish compared to a mechanical keyboard.

---

## 6. Anti-Patterns and Common Mistakes

- **Assuming BT latency is good enough for rhythmic typing**: do NOT use Bluetooth for rapid Vim motion macros or fast-twitch combos. The ~20ms latency compounds.
- **Buying a "QMK" pad that's actually CH57x/Jieli**: AliExpress vendors often falsely label black-box pads as "QMK compatible." Check: does the seller provide source or a flasher? If not, it's OS-level remap or nothing.
- **Not testing BT sleep/wake before the important meeting**: always do a sleep-30s → wake → press-button → count-seconds test before relying on it live.
- **Multi-host pads with confusing switching UX**: layer-based host switching (`Fn+1/2/3`) is intuitive only after practice; a sleep event may reset layer state, causing unexpected host switches mid-meeting.
- **Confusing connection state**: after a disconnect, the pad may silently stay disconnected. System Settings shows it as "paired" but "disconnected" — users don't notice until a hotkey fails. Add a visible Bluetooth monitor (BitBar widget or `lnav` log tail).
- **Chaining multi-layer macros without battery backup**: if the pad reconnects to a fresh session, layer state resets. Flatten critical actions to single-key triggers on layer 0.

---

## 7. Concrete Recommendations for This Pad

### Our Setup

- Hardware: 3-key Jieli pad, VID `0x4c4a` PID `0x4155`, USB-C + Bluetooth modes
- Primary use: Typeless push-to-talk via Fn emulation in Karabiner
- Goal: enable Bluetooth for wireless meetings

### Suggested Approach

1. **Before enabling Bluetooth** — Check the pad's enclosure for mode switch, pairing button, or indicator LED. Photo-document it for the `05-bluetooth-roadmap.md`. Note expected battery type (coin cell vs. Li-Po).

2. **First pairing on macOS** — Enter pairing mode (try holding all 3 keys for 5s, or individual buttons, or a hidden reset). Open System Settings → Bluetooth, look for an advertising device with name "USB Composite Device" or similar. Connect. Test all 3 buttons in TextEdit to confirm they emit the same Ctrl+C / Ctrl+V / Ctrl+X as USB mode.

3. **Capture Bluetooth VID/PID** — Run `system_profiler SPBluetoothDataType | grep -A 20 -i jieli` and `karabiner_cli --list-connected-devices | jq '.[] | select(.is_bluetooth == true)'` to capture the Bluetooth transport's identifiers. Note whether they match USB VID/PID or not.

4. **Karabiner rule update** — Extend the existing complex modification with a second `identifiers` entry matching the Bluetooth VID/PID. Prefer a single rule with two identifiers (simpler maintenance) over duplicate rules. See `05-bluetooth-roadmap.md` "Option B."

5. **Test sleep/wake reconnection rigorously** — sleep Mac 30s → wake → press pad → time to response. If >5s or fails, either toggle Bluetooth via a launchd wake listener, or keep USB-C as the primary mode and treat BT as nice-to-have.

6. **Battery monitoring workflow** — If pad exposes battery in System Settings → Bluetooth, add a Friday launchd reminder to check it. If not, charge weekly by default.

7. **Fallback plan** — Keep the USB-C cable with you during important meetings. If BT fails to reconnect, plug in within 30 seconds.

8. **Latency gate for PTT** — Open Zoom/Teams in a mock meeting; press pad PTT repeatedly; confirm Typeless activation feels identical to USB-C mode. If noticeable lag, keep BT for light-duty work and USB for meetings.

9. **Documentation discipline** — After successful BT enablement, replace `05-bluetooth-roadmap.md` with `06-bluetooth-configuration.md` (matching the structure of `02-usb-wired-configuration.md`). Update `01-hardware-identification.md` with a new Bluetooth section noting the BT VID/PID, pairing procedure, and any battery behavior observed.

---

## Sources

- [ZMK Firmware Documentation](https://zmk.dev/)
- [ZMK Hardware Support](https://zmk.dev/docs/hardware)
- [Bluetooth HID Introduction (novelbits.io)](https://novelbits.io/bluetooth-hid-devices-an-intro/)
- [HID over GATT Profile Specification (bluetooth.com)](https://www.bluetooth.com/specifications/specs/hid-over-gatt-profile-1-0/)
- [Nordic Semiconductor BLE Battery Life](https://blog.nordicsemi.com/getconnected/improve-battery-life-in-ultra-low-power-wireless-applications)
- [Coin Cell vs LiPo for BLE (hubble.com)](https://hubble.com/community/comparisons/coin-cell-vs-lipo-vs-aa-how-to-choose-a-battery-chemistry-for-your-ble-device/)
- [ch57x-keyboard-tool (GitHub)](https://github.com/kriomant/ch57x-keyboard-tool)
- [Vial Configurator Manual](https://get.vial.today/manual/first-use.html)
- [Karabiner-Elements Documentation](https://karabiner-elements.pqrs.org/)
- [macos-bluetooth-off-while-sleep (GitHub)](https://github.com/morishin/macos-bluetooth-off-while-sleep)
- [QMK, VIA, and Vial Visual Configurators Overview (maxzsol.com)](https://maxzsol.com/a-detailed-overview-of-qmk-via-and-vial-visual-configurators-for-mechanical-keyboards)
