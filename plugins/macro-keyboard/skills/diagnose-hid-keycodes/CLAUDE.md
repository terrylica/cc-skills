# diagnose-hid-keycodes Skill

> Find out what a mystery HID button actually emits, without guessing. Combines Karabiner's `ignore: true` (or `vk_none`) diagnostic rule with `Karabiner-EventViewer` and Quartz focus-free screen capture so you can press a button and screenshot its raw event without losing focus.

**Hub**: [Plugin CLAUDE.md](../../CLAUDE.md) | **Sibling skills**: [configure-macro-keyboard](../configure-macro-keyboard/CLAUDE.md) · [emit-fn-key-on-macos](../emit-fn-key-on-macos/CLAUDE.md)

## What This Skill Owns

| File                                | Role                                                                                                                    | Edit policy                                                                                              |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `SKILL.md`                          | Diagnostic workflow: temporarily un-grab the device, watch EventViewer, screenshot via Quartz to keep focus on the pad. | Edit when a new diagnostic technique proves useful — e.g., a new way to capture multi-report HID events. |
| `references/diagnostic-workflow.md` | Step-by-step with Case 1/2/3 edge cases (single-report combos, consumer keys, multi-interface devices).                 | Add new edge cases here. Each case should reference a real device that exhibited the behavior.           |

## Critical Invariants

1. **`ignore: true` un-grabs the device but leaves Karabiner running.** This is the key trick — without it, Karabiner intercepts the raw events before EventViewer can show them. Don't try to disable Karabiner globally during diagnosis.
2. **Always remove `ignore: true` after diagnosis.** Otherwise your remap won't fire (Karabiner won't grab the pad). The `configure-macro-keyboard` SKILL.md has a callout for this.
3. **Use Quartz screen capture, not the macOS screenshot app.** The macOS screenshot app steals focus, which causes the pad to start emitting events to whatever stole focus instead of EventViewer. The Quartz approach in `references/diagnostic-workflow.md` is focus-free.
4. **Cheap pads emit modifier+key in one HID report.** EventViewer will show this as "Ctrl+C" appearing simultaneously, not "Ctrl press → C press → Ctrl release → C release". When you write the remap, this is what forces `simultaneous` with `detect_key_down_uninterruptedly: true` (default `mandatory` matcher misses single-report combos).
5. **BT firmware modes can each emit different keycodes.** When diagnosing a BT pad, repeat the diagnosis after switching modes (if the pad supports them). The Jieli/Free3-P has 4 modes — see [`configure-macro-keyboard/references/08-bluetooth-configuration.md`](../configure-macro-keyboard/references/08-bluetooth-configuration.md#bt-firmware-has-4-modes--we-use-mode-4).

## Recent Changes

- **No changes since 2026-04-21.** The diagnostic workflow is stable. Updates to `configure-macro-keyboard` (top-button tap/double-tap added 2026-04-24) did not require new diagnosis — the underlying button-to-keycode mappings did not change; only the rule that consumes them did.

## Discoverability Notes

- This skill is the prerequisite for `configure-macro-keyboard` when working with an unknown pad. If the user already knows what their buttons emit (e.g., they bought the same Jieli/Free3-P documented in this plugin), they can skip straight to `configure-macro-keyboard`.
- TRIGGERS in `SKILL.md` cover both diagnosis-from-zero ("what does this button emit?") and diagnosis-on-failure ("my remap isn't firing — is the keycode what I think?").
