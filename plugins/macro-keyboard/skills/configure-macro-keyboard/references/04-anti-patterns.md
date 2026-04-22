# Anti-Patterns

Dead-ends, wrong turns, and things we tried that didn't work. Recorded here so future debugging sessions don't re-walk the same paths.

## Anti-pattern: BetterTouchTool `CGEventPost` for Fn emission

**What we tried**: Bind a BTT keyboard shortcut trigger on `Ctrl+C` (the pad's top button) to output the Fn key, so Typeless would see push-to-talk.

**Why it failed**: BTT uses `CGEventPost` to synthesize keystrokes. This API cannot set the `kCGEventFlagMaskSecondaryFn` bit authentically — that bit is only honored by macOS when the originating HID device declares `NX_DEVICE_CAPABILITY_INPUTKEYBOARD_FUNCTION`. BTT is an app, not an HID device, so its emitted "Fn" events are silently dropped by `CGEventTap` consumers like Typeless.

**The lesson**: Any time you need to emit a keystroke that requires modifier-flag provenance (Fn/Globe, and some system-only consumer keys), app-layer tools are insufficient. You need a DriverKit virtual HID device. On macOS today, Karabiner-Elements is the only mature FOSS option.

**Alternative considered**: Changing Typeless's `pushToTalk` shortcut to something BTT _can_ emit (F13-F20 or Ctrl+Opt+Cmd+something). Ruled out because the coworker shares the Typeless subscription and uses the real Fn key — we couldn't change the shortcut without breaking their workflow.

## Anti-pattern: `hidutil` alone for Fn emission

**What we considered**: Remap the pad's Ctrl+C → Fn using `hidutil property --matching ... --set '{"UserKeyMapping":...}'`.

**Why it wouldn't work**: `hidutil` maps single HID usage codes to other single usage codes on a per-device basis. It can't match on a _combination_ (Ctrl+C is two simultaneous keys). It also can't _emit_ Fn as a proper modifier event — it would emit the `0xFF00/0x03` usage but without the capability declaration, macOS would still route it as a regular key press, not a modifier flag change.

**The lesson**: `hidutil` is great for single-keycode remaps (Caps Lock → Escape, etc.) but insufficient for modifier+key combos or any remap whose target requires device capability declarations.

## Anti-pattern: VIA / Vial / QMK Toolbox on Jieli firmware

**What we considered**: Install VIA or Vial to reconfigure the pad's firmware directly so each button emits a user-chosen keycode.

**Why it wouldn't work**: Jieli SoCs use a proprietary RISC core, not AVR or ARM. QMK firmware doesn't support Jieli. VIA and Vial are client-side tools that speak a specific HID command set only present in QMK/Vial firmware — they won't detect or configure a Jieli device.

**Secondary issue on macOS 2026**: The Homebrew casks for VIA (`via`), Vial (`vial`), and QMK Toolbox are Intel-only and Gatekeeper-deprecated. Installing them requires Rosetta 2 (~500 MB) to even run. Combined with the firmware incompatibility, there's zero upside.

**The lesson**: Before reaching for QMK/VIA/Vial, verify the target device's MCU family. If it's Jieli, Nordic, or another non-QMK SoC, don't waste time installing these tools.

## Anti-pattern: `{"any": "key_code"}` at top level of `from`

**What we tried**: A diagnostic "catch-all" Karabiner rule designed to match any keypress from the pad:

```json
{
  "type": "basic",
  "from": {
    "any": "key_code",
    "modifiers": {"optional": ["any"]}
  },
  "to": [{"key_code": "fn"}],
  "conditions": [{"type": "device_if", "identifiers": [...]}]
}
```

**Why it failed**: `"any": "key_code"` is only valid _inside_ a `simultaneous` block — not as a top-level `from` field. Karabiner silently ignores manipulators with invalid `from` syntax instead of logging an error. The rule was accepted by `jq` as valid JSON but did nothing.

**The lesson**: Karabiner's config validation is lenient — don't assume "no error = rule is working." Always verify a new manipulator fires by observing its effect (EventViewer or downstream behavior).

## Anti-pattern: Inferring button-to-keycode mapping from a fast sequence test

**What we did**: User pressed "top mid bottom" in rapid sequence. The event log showed Ctrl+C → Fn (rule-fired) → Ctrl+V. We inferred top=Ctrl+C, middle=Ctrl+X, bottom=Ctrl+V.

**Why it was wrong**: The inference required an assumption about the press order that was never verified. Later single-button testing revealed the actual wiring was top=Ctrl+C, middle=Ctrl+V, bottom=Ctrl+X — the middle and bottom were swapped relative to our inference.

**The cost**: One wasted rule iteration (Ctrl+X → Return, which ended up on the wrong physical button), plus user confusion when "middle" didn't do what was expected.

**The lesson**: For each physical button, isolate a single press and verify its keycode independently. Never trust a multi-press sequence to pin down individual mappings. The `ignore: true` + EventViewer technique is the right tool for this — use it _before_ writing rules that differentiate between buttons.

## Anti-pattern: `sudo launchctl bootstrap` for SMAppService-registered daemons

**What we tried**: Manually bootstrap Karabiner's privileged daemons with `sudo launchctl bootstrap system /path/to/Karabiner-Core-Service.plist`.

**Why it failed**: `Bootstrap failed: 5: Input/output error`. Karabiner 15.x uses macOS's `SMAppService` API, where the daemons are registered at install time but must be enabled by the user via System Settings → General → Login Items & Extensions → "Allow in the Background". `launchctl bootstrap` is blocked for SMAppService-registered services until the user grants that permission.

**The lesson**: On macOS Sequoia, any third-party service using `SMAppService` requires user approval in Login Items. There is no scripted workaround — it's an intentional security policy. Tell the user once, and the toggle persists across reboots.

## Anti-pattern: Sudo TCC database queries for authorization audits

**What we tried**: `sudo sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db "SELECT client, auth_value FROM access WHERE service='kTCCServiceListenEvent'"` to verify Input Monitoring was granted to Karabiner.

**Why we stopped**: Triggered a Touch ID prompt. User flagged this as undesirable.

**The alternative that works**: Run `karabiner_cli --list-connected-devices`. If it returns a non-empty device list including the pad, Input Monitoring must be granted — otherwise the call would fail or return only virtual devices. The fact that the tool works _is itself_ the audit evidence.

**The lesson**: Prefer user-scope, non-privileged evidence of authorization (like observing a privileged feature working) over root-scope direct database queries. Works faster, avoids biometric prompts, and is more portable.

## Anti-pattern: Assuming factory button order follows cut/copy/paste convention

**What we assumed**: A 3-key pad emitting Ctrl+C/X/V would be wired top=C (copy), middle=X (cut), bottom=V (paste) — the conventional toolbar order.

**Actual wiring**: top=C, middle=V, bottom=X. No standard applies — each pad vendor wires them arbitrarily.

**The lesson**: Cheap macro pads don't follow any layout convention. Verify each button individually before writing rules. See Pattern: Isolate a device for inspection via `ignore: true`.

## Anti-pattern: Changing Typeless's `pushToTalk` to F13 without a working emitter

**What we considered at one point**: Edit `~/Library/Application Support/Typeless/app-settings.json` to set `"pushToTalk": "F13"`, then `hidutil`-remap the pad's Ctrl+C to F13 on the device only. This would avoid the Fn-emission problem entirely.

**Why it was blocked**: User's coworker shares the Typeless subscription and uses the real Fn key. Changing Typeless's shortcut would break their workflow. This constraint pushed us back to the Karabiner+virtual-Fn path.

**The lesson**: Always check whether your proposed solution affects other users of the system or account. A "lighter" solution isn't actually lighter if it breaks someone else's workflow.

## Anti-pattern: Silent formatting drift from hook processing

**What happened**: After each `Write` to a markdown file, a PostToolUse hook reformatted the content (probably prettier or similar). The visible content stays the same but indentation / line wrapping shifts.

**Why it's mostly benign**: The formatter is idempotent and doesn't change semantics.

**Why to stay aware**: If you later want to `Edit` a specific `old_string` in one of these files, the formatter may have rewrapped lines, so you must `Read` first to see the post-format state. The claude-code harness warned about this explicitly.

**The lesson**: After `Write`-ing a file that gets auto-formatted, `Read` it before the next `Edit` targeting specific lines.

## Anti-pattern: Over-eager memory file updates before workflow is stable

**What happened**: Memory file `reference_jieli_macropad_karabiner.md` was updated three times in this session as the rule evolved. Each update required re-reading, re-editing, and keeping MEMORY.md index in sync. Early updates became stale within minutes.

**The lesson**: During rapid iteration, wait for the workflow to stabilize before committing to memory files. Better to update memory once at the end than to repeatedly rewrite it during the discovery phase.
