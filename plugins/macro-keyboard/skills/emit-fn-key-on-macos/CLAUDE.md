# emit-fn-key-on-macos Skill

> Focused coverage of the one thing BetterTouchTool, `hidutil`, and QMK-on-locked-firmware all fail at: emitting a real Apple Fn key on macOS. Karabiner's `apple_vendor_top_case_key_code: keyboard_fn` (HID Usage Page `0x00FF`, Usage `0x03`) is the only userland path because it routes through DriverKit VirtualHIDDevice with the `NX_DEVICE_CAPABILITY_INPUTKEYBOARD_FUNCTION` capability declared.

**Hub**: [Plugin CLAUDE.md](../../CLAUDE.md) | **Sibling skills**: [configure-macro-keyboard](../configure-macro-keyboard/CLAUDE.md) · [diagnose-hid-keycodes](../diagnose-hid-keycodes/CLAUDE.md)

## What This Skill Owns

| File                              | Role                                                                                  | Edit policy                                                                                                                                                    |
| --------------------------------- | ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `SKILL.md`                        | Why-only-Karabiner explanation, with the canonical Karabiner snippet for emitting Fn. | Edit when a new Fn-emission method is verified to work (or to fail). Always test against Typeless `pushToTalk: "Fn"` AND macOS native dictation double-tap-Fn. |
| `references/failed-approaches.md` | Condensed catalog of every Fn-emission attempt that didn't work. Append-only history. | Add new failures here. Don't remove entries — future readers need to know what's been tried.                                                                   |

## Critical Invariants

1. **Real Fn requires the DriverKit VirtualHIDDevice capability declaration.** App-layer synthetic events from `CGEventPost` (BTT, Hammerspoon, custom Swift apps) will never satisfy Typeless's `CGEventTap` filter or macOS dictation. This is not a bug — it's an OS-level safety mechanism around Fn / globe key behavior.
2. **`key_code: fn` and `modifiers: ["fn"]` are no-ops in Karabiner.** Only `apple_vendor_top_case_key_code: keyboard_fn` works. Don't paste examples from old Karabiner docs that suggest otherwise.
3. **`to_if_held_down` with `keyboard_fn` breaks Fn system-wide.** Verified failure (see `references/failed-approaches.md`). If you need tap-vs-hold discrimination on a button targeting Fn, use `to_delayed_action` (see [configure-macro-keyboard](../configure-macro-keyboard/CLAUDE.md) → "Top-button caveat") or pick a different gesture.
4. **The Globe key (`com.apple.HIToolbox AppleFnUsageType`) can hijack Fn presses.** If a remap fires Fn but Typeless doesn't see it, check that `defaults read com.apple.HIToolbox AppleFnUsageType` returns `0` (Do Nothing). System Settings → Keyboard → "Press 🌐 key to..." controls this.

## Recent Changes

- **2026-04-24** — A consumer of this skill (configure-macro-keyboard) shifted from immediate-Fn-on-press to delayed-Fn-via-`to_delayed_action` for the MacroKeyBot top button. **No changes to this skill.** The Fn emission primitive is unchanged; only the trigger pattern in the consumer changed. The PTT-incompatibility caveat lives in the consumer's docs, not here.

## Discoverability Notes

- This skill is intentionally narrow. If a user asks "how do I make my macro pad emit Fn?", they probably want [`configure-macro-keyboard`](../configure-macro-keyboard/SKILL.md) (which uses this skill's primitive). This one is for the deeper "why doesn't BTT work?" question.
- The TRIGGERS frontmatter in `SKILL.md` is comprehensive (BTT failure symptoms, hidutil mapping not working, kCGEventFlagMaskSecondaryFn, etc.) — keep it broad to catch users arriving from search-based confusion.
