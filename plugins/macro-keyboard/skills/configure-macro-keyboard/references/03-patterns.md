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

## Pattern: Atomic commits after verifying each change

**What**: After every rule change, verify it works via EventViewer or direct test before moving to the next. If something breaks later, you can `git bisect` or revert to a known-good state.

**Why**: This session went through ~5 rule iterations (Ctrl+C rule → Ctrl+X rule → all-three rule → Ctrl+X=Return+Ctrl+C=Fn rule → Ctrl+V=Return+Ctrl+C=Fn rule). Each one was observable and reversible. If I'd batched all changes into one commit at the end, a regression would have been harder to localize.

**When to use**: Always for config changes. Especially valuable for keyboard/input configs where "broken" may mean "can't type to debug."
