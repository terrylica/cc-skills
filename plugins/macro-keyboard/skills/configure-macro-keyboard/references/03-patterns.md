# Patterns

Techniques and approaches that worked well during the USB-C wired setup. Re-use these when extending the config, adding the Bluetooth mode, or wiring up any other cheap HID peripheral on macOS.

## Pattern: Device-scoped rule via `device_if` + VID/PID

**What**: Every Karabiner manipulator for the pad includes a `conditions` array with `{"type": "device_if", "identifiers": [{"vendor_id": 19530, "product_id": 16725}]}`.

**Why**: A rule written without `device_if` would remap `Ctrl+C` on _every_ connected keyboard — including your Apple built-in — which would break normal typing immediately. The device filter narrows the rule to exactly one pair of VID/PID.

**When to use**: Any rule targeting a key combination that's common on other keyboards (Ctrl+{letter}, Cmd+{letter}, Shift+Tab, etc.). Single-device-only behavior is almost always what you want.

**Counter-example**: If you wanted the Caps Lock → Hyper (or Escape) remap to apply globally (both Apple internal and external keyboards), you wouldn't add `device_if`. The default scope is "all devices."

## Pattern: `simultaneous` (not `mandatory`) for modifier + letter combos from macro pads

**What**: Use `from.simultaneous: [{"key_code": "left_control"}, {"key_code": "c"}]` with `simultaneous_options.detect_key_down_uninterruptedly: true`, rather than `from: {"key_code": "c", "modifiers": {"mandatory": ["control"]}}`.

**Why**: Cheap HID devices like Jieli macro pads emit the modifier and the key in a **single HID report** — both change state simultaneously. Karabiner's `mandatory` form can leak the modifier through to macOS in edge cases, causing the host app to see `Ctrl+Fn` instead of plain `Fn`. The `simultaneous` form with `detect_key_down_uninterruptedly: true` guarantees both keys are consumed atomically.

**When to use**: Whenever matching a modifier+key combo from any device that emits both in one HID report. For human-typed combos on real keyboards (where modifier goes down first, then the key), `mandatory` is fine.

**Diagnostic tip**: If you write a `mandatory` rule and the post-remap event has unexpected modifiers still held, switch to `simultaneous`.

## Pattern: `apple_vendor_top_case_key_code: keyboard_fn` for the Fn target

**What**: Use `{"apple_vendor_top_case_key_code": "keyboard_fn"}` in the `to` array, rather than the shorter alias `{"key_code": "fn"}`.

**Why**: Both resolve to the same HID usage page (`0x00FF`) and usage (`0x03`) — Apple's vendor-specific Fn encoding. The explicit form bypasses Karabiner's alias lookup table. If a future Karabiner version changes how `key_code: fn` is resolved or deprecates the alias, the explicit form will still work.

**When to use**: Whenever emitting Fn. Cost of the explicit form is just a slightly longer JSON key.

## Pattern: Use the Karabiner Virtual HID Device to emit Fn

**What**: Karabiner-Elements installs a DriverKit system extension that registers a virtual HID keyboard declaring `NX_DEVICE_CAPABILITY_INPUTKEYBOARD_FUNCTION`. When a complex modification emits `keyboard_fn`, the event flows through this virtual keyboard.

**Why**: macOS's Fn modifier bit (`kCGEventFlagMaskSecondaryFn`) is only honored from events originating on devices that declare the Fn capability. App-layer synthesizers (`CGEventPost` from BTT, AppleScript key-down simulation, PyObjC synthetic events) can't set this bit authentically. Only DriverKit virtual HID devices can.

**When to use**: Whenever a consumer (like Typeless) reads Fn via `CGEventTap` flag-change events. Also the right pattern for globe-key press-simulation, dictation-key triggering, and any other "real HID modifier" use case.

## Pattern: Isolate a device for inspection via `ignore: true`

**What**: To see raw HID events from a device (unremapped), add an entry to `profiles[0].devices` in `karabiner.json`:

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

**Why**: When Karabiner is grabbing a device, `Karabiner-EventViewer` shows the _output_ of the virtual keyboard (post-modification events). To see what the physical device is actually emitting, Karabiner must release its grab. The `ignore: true` flag does this cleanly on a per-device basis.

**When to use**: Any time you need to confirm what keycode a button emits, diagnose why a rule isn't matching, or document a new device. Always revert (remove the entry) after.

**Evidence this matters**: Without this technique we would have remained stuck on "the middle button emits Ctrl+X" — an assumption that turned out wrong (middle actually emits Ctrl+V). Un-grabbing and reading raw HID events revealed the truth.

## Pattern: Capture windows by ID via Quartz, not focus

**What**: To screenshot a specific window regardless of focus state, use `CGWindowListCopyWindowInfo` (via pyobjc) to find its Window ID, then `screencapture -l <WID> -x file.png`.

```python
import Quartz
for w in Quartz.CGWindowListCopyWindowInfo(
    Quartz.kCGWindowListOptionAll, Quartz.kCGNullWindowID):
    if w.get('kCGWindowOwnerName') == 'Karabiner-EventViewer':
        wid = w.get('kCGWindowNumber')
        # screencapture -l <wid> -x out.png
```

**Why**: `osascript -e 'tell application "X" to activate'` can be defeated by macOS focus-stealing prevention, and `screencapture -x` captures only the foreground. Grabbing a window by ID captures it even when off-screen, minimized, or obscured. No Accessibility permission needed — only Screen Recording.

**When to use**: Any autonomous UI inspection workflow, especially when working from a terminal that shouldn't steal focus from the window being inspected. Perfect for letting Claude debug UI state without interrupting the user's flow.

## Pattern: Edit the config file directly to change device grab state

**What**: Karabiner re-reads `~/.config/karabiner/karabiner.json` automatically when it changes. To toggle per-device grab, ignore flag, or modifier state, edit the JSON and save — no UI interaction needed.

**Why**: The Karabiner GUI requires focus, clicking, and in some cases Accessibility-permission prompts for its child windows. File edits via `jq` are scriptable, reversible, and don't need any permissions beyond filesystem access.

**When to use**: Programmatic configuration, automated tests, scripted setup, CI-style provisioning of a new Mac.

**Example**: The `ignore: true` pattern above is a specific instance of this general pattern.

## Pattern: Non-sudo audit commands

**What**: To verify Karabiner's TCC Input Monitoring grant, daemon state, and device grab status, prefer user-scope queries over sudo:

```bash
# Daemon state (no sudo needed)
launchctl print gui/$(id -u) | grep -i karabiner

# Proof of Input Monitoring grant (because if not granted, this would return empty or error)
karabiner_cli --list-connected-devices | jq length

# Grab state from log
grep "USB Composite Device" /var/log/karabiner/core_service.log | tail -2
```

**Why**: `sudo` triggers Touch ID prompts each time (unless `sudo` session is cached). For a repeated audit loop, that's dozens of biometric prompts. Working from user-scope commands is both faster and more pleasant.

**When to use**: Always, unless the data genuinely requires root (which is rare for user-facing tools like Karabiner).

## Pattern: Tap vs. double-tap discrimination on one button

**What**: Let a single macro-pad button emit two different targets depending on whether it's pressed once or twice quickly. Use `set_variable` + `to_delayed_action` across two coordinated manipulators sharing the same `from` trigger.

**Why**: Cheap macro pads have few buttons, and some target pairs are a natural fit (`Return` vs. `Shift+Return` for chat composers; `Escape` vs. `Command+.` for dismiss vs. interrupt; `Cmd+C` vs. `Cmd+Shift+C` for copy vs. copy-path). Karabiner has no first-class "double-tap" matcher, but the delayed-action + variable pattern yields the same behavior with predictable semantics.

**When to use**: Any time one button should produce two distinct outputs and you're OK with the single-tap action firing ~200ms late (the double-tap detection window is unavoidable discrimination latency). Not the right pattern when the single-tap target is latency-sensitive — prefer `to_if_alone` + `to_if_held_down` (tap vs. hold) instead, which has zero delay on tap.

**Structure** (two manipulators sharing one `from`, ordered second-tap-detector first):

```json
{
  "description": "<button>: single-tap = X, double-tap = Y",
  "manipulators": [
    {
      "type": "basic",
      "from": {
        /* your button trigger */
      },
      "to": [
        { "key_code": "<DOUBLE_TAP_TARGET>" },
        { "set_variable": { "name": "<button>_tap", "value": 0 } }
      ],
      "conditions": [
        {
          "type": "device_if",
          "identifiers": [
            /* VID/PID */
          ]
        },
        { "type": "variable_if", "name": "<button>_tap", "value": 1 }
      ]
    },
    {
      "type": "basic",
      "parameters": { "basic.to_delayed_action_delay_milliseconds": 200 },
      "from": {
        /* same button trigger */
      },
      "to": [{ "set_variable": { "name": "<button>_tap", "value": 1 } }],
      "to_delayed_action": {
        "to_if_invoked": [
          { "key_code": "<SINGLE_TAP_TARGET>" },
          { "set_variable": { "name": "<button>_tap", "value": 0 } }
        ],
        "to_if_canceled": [
          { "set_variable": { "name": "<button>_tap", "value": 0 } }
        ]
      },
      "conditions": [
        {
          "type": "device_if",
          "identifiers": [
            /* VID/PID */
          ]
        }
      ]
    }
  ]
}
```

**Mechanism**:

1. **First tap** arrives with `<button>_tap == 0`. The detector's `variable_if` fails. Execution falls through to the handler: variable is set to `1`, a 200ms timer starts.
2. **If nothing happens within 200ms**: `to_if_invoked` fires → `SINGLE_TAP_TARGET` is emitted, variable is reset to `0`.
3. **If a second tap arrives within 200ms**: the detector's `variable_if` now matches (`== 1`). It fires first (Karabiner evaluates top-down), emitting `DOUBLE_TAP_TARGET` and resetting the variable. The still-pending delayed action is canceled automatically — `to_if_canceled` just resets the variable again (idempotent safety).

**Why the detector must come first**: Karabiner evaluates manipulators in order and takes the first match. If the handler came first, every tap would match the handler first and the detector would never fire. Order matters.

**Tuning knob**: `basic.to_delayed_action_delay_milliseconds`. Default 500 is too long for a tap/double-tap gesture — humans double-tap in 100-250ms. Start at 200ms; raise to 250-300 if users miss double-taps, lower to 150 if they accidentally trigger single-tap when meaning double. The same variable can be shared across multiple manipulators (e.g. USB + Bluetooth transports of the same button) because only one path is physically active at a time.

**Trade-off framing — choose which side pays the cost**:

| Single-tap action | Double-tap action | Framing                                                                            |
| ----------------- | ----------------- | ---------------------------------------------------------------------------------- |
| `Return` (send)   | `Shift+Return`    | Speed on send, delay on newline — good for high-throughput chat                    |
| `Shift+Return`    | `Return` (send)   | **Safety** — newline is easy, send is deliberate (accidental sends are suppressed) |
| `Escape`          | `Command+.`       | Dismiss is fast, interrupt is deliberate                                           |
| `Cmd+C`           | `Cmd+Shift+C`     | Copy is fast, copy-path is deliberate                                              |

**Live examples**: Jieli/Free3-P top button (Fn / Cmd+V) + middle button (Shift+Return / Return) on both transports, plus bottom button (up_arrow / down_arrow) on **USB only**. See `references/raw/karabiner-rule.json` for the full 12-manipulator config. **Use a distinct variable name per button** (`jieli_top_tap`, `jieli_middle_tap`, `jieli_bottom_tap`) — sharing one variable across buttons would let a tap on one arm the double-tap detector on another.

**The Jieli/Free3-P bottom button on BT does NOT use this pattern** — see "Pattern: Translate pad-firmware-decided keycodes" below for why. In short, the pad's BT firmware emits `equal_sign` for a single tap and `Option+Z` for a double tap, so Karabiner doesn't need to discriminate; it just translates each keycode immediately. **Always check what your pad emits for both single and double tap on each transport before assuming software discrimination is needed.** The `ignore: true` diagnostic ([`diagnose-hid-keycodes`](../../diagnose-hid-keycodes/SKILL.md) sibling skill) is the right tool for this.

**Anti-pattern warning**: don't pick this pattern when the latency-on-single-tap matters _or_ when the single-tap target needs key auto-repeat on hold. Two concrete failure modes:

1. **Push-to-talk** — tap-vs-double-tap on a PTT button adds 200ms before the mic opens, and holding the button doesn't sustain the modifier. Use tap-vs-hold instead (`to_if_alone` + `to_if_held_down`), which discriminates by duration rather than a commit window. **The Jieli/Free3-P top button hits this trap if Typeless is configured for push-to-talk**: Fn fires only after release, so PTT doesn't work. The live config assumes Typeless is in tap-to-toggle mode.
2. **Arrow-key auto-repeat** — `to_delayed_action`'s `to_if_invoked` fires the single-tap target as one discrete event after the timer elapses (or on key-up, whichever comes first). It does not emit a sustained key-down state, so macOS's auto-repeat doesn't kick in. **The Jieli/Free3-P bottom button hits this trap with `up_arrow`**: holding the bottom key produces one arrow keystroke, not the rapid scroll a real arrow key produces. Acceptable if you only nudge the cursor; painful if you scroll long lists.

To restore the immediate-fire / auto-repeat behavior on any button: collapse its pair into a single immediate-target manipulator per transport (drop `parameters`, `to_delayed_action`, and `variable_if`; set `to: [{ ... your target ... }]`). See git history of `references/raw/karabiner-rule.json` for snapshots before each pair was added: pre-2026-04-24 for the immediate-Fn top-button form, pre-2026-05-02 for the bottom-button single-action forms.

## Pattern: Translate pad-firmware-decided keycodes (no Karabiner-side discrimination)

**What**: When the pad's firmware emits **two different keycodes** for single-tap vs double-tap on the same physical button, you don't need Karabiner-side `set_variable` + `to_delayed_action` discrimination. Just write two simple immediate-translation manipulators — one per emitted keycode — and let the firmware do the timing.

**Why**: This is faster (no software 200ms wait), simpler (no variable, no delayed action, no `variable_if` ordering), and gives the user better feedback (single tap fires immediately).

**Trigger to look for**: open Karabiner-EventViewer's Main tab, double-tap the button quickly, and see what comes through. If you see the **same** keycode twice in a row, the pad isn't doing firmware-level discrimination — use the previous "tap vs. double-tap" pattern. If you see a **different** keycode (or chord) on the second tap, the firmware is doing it for you.

**How**:

```jsonc
// Single-tap path — translate the firmware's "single tap" keycode
{
  "type": "basic",
  "from": { "key_code": "<single-tap firmware code>" },
  "to": [{ "key_code": "<your target>" }],
  "conditions": [{ "type": "device_if", "identifiers": [/* ... */] }]
},
// Double-tap path — translate the firmware's "double tap" keycode (often a modifier+key chord)
{
  "type": "basic",
  "from": {
    "key_code": "<double-tap key>",
    "modifiers": { "mandatory": ["<double-tap modifier>"] }
  },
  "to": [{ "key_code": "<your other target>" }],
  "conditions": [{ "type": "device_if", "identifiers": [/* ... */] }]
}
```

**Live example**: Jieli/Free3-P bottom button on **Bluetooth mode 4 only** (verified 2026-05-02 via EventViewer). The pad's BT firmware emits `equal_sign` for a single tap and `Option+Z` for a double tap. The rule translates each immediately: `equal_sign` → `up_arrow`, `Option+Z` → `down_arrow`. No variable, no delayed action.

**Not all transports of the same pad behave the same way**: the same Free3-P over USB-C emits `Ctrl+X` for **every** press regardless of tap rate, so the USB path uses the original software-discrimination pattern. **Always test both transports separately.**

**Anti-pattern warning**: don't assume firmware-side discrimination is consistent across buttons. The Free3-P only does it on the bottom button — `page_up` (top) and `page_down` (middle) come through on every press, regardless of tap rate. Mixing patterns on the same physical pad is fine; the rule just has both kinds of manipulators.

## Pattern: Atomic commits after verifying each change

**What**: After every rule change, verify it works via EventViewer or direct test before moving to the next. If something breaks later, you can `git bisect` or revert to a known-good state.

**Why**: This session went through ~5 rule iterations (Ctrl+C rule → Ctrl+X rule → all-three rule → Ctrl+X=Return+Ctrl+C=Fn rule → Ctrl+V=Return+Ctrl+C=Fn rule). Each one was observable and reversible. If I'd batched all changes into one commit at the end, a regression would have been harder to localize.

**When to use**: Always for config changes. Especially valuable for keyboard/input configs where "broken" may mean "can't type to debug."
