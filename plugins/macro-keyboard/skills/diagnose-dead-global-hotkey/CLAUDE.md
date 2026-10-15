# diagnose-dead-global-hotkey Skill

> Find where on the macOS input path a global hotkey is lost or rewritten while one app is frontmost: a DriverKit remapper rule below the tap layer, an app's active keyboard-grab tap, Secure Event Input, or the hotkey owner. Ships three `swift`-interpreted scripts and two layer-specific fixes.

**Hub**: [Plugin CLAUDE.md](../../CLAUDE.md) | **Sibling skills**: [diagnose-hid-keycodes](../diagnose-hid-keycodes/CLAUDE.md) · [configure-macro-keyboard](../configure-macro-keyboard/CLAUDE.md) · [emit-fn-key-on-macos](../emit-fn-key-on-macos/CLAUDE.md)

## What This Skill Owns

| File                            | Role                                                                                         | Edit policy                                                                                                       |
| ------------------------------- | -------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `SKILL.md`                      | Input-path model, workflow, log-to-cause table, Fix A (remapper exception), Fix B (grab off) | Add a table row only for a pattern seen in a real log; add an app to the Fix B table only after measuring its tap |
| `scripts/tap-census.swift`      | Read-only list of keyboard event taps                                                        | Keep read-only                                                                                                    |
| `scripts/key-path-logger.swift` | Four listen-only taps; logs Cmd/Ctrl/Opt key-downs only                                      | Must stay listen-only and must never log plain typing                                                             |
| `scripts/hotkey-probe.swift`    | Synthetic chord at the HID tap, window-count check on a watched app                          | Keep the remapper-blindness warning in its header                                                                 |

## Critical Invariants

1. **Synthetic events bypass Karabiner.** `CGEventPost` enters above the DriverKit virtual keyboard, so the probe cannot see a remapper rule. Any conclusion about remapping needs a physical press in the logger. This is the trap that made the first diagnosis of the original case wrong.
2. **The logger must include Control and Option chords.** A Command→Control remap makes a Command-only filter log nothing, which looks like "the key never arrived".
3. **The scripts stay device- and person-agnostic.** App names and keycodes are arguments, never constants. No hostnames, accounts or personal setup in this skill.
4. **Run the scripts in the main session, not a subagent.** On macOS, subagents must not compile and execute binaries (it can saturate code-signing daemons); `swift <file>` compiles in place.

## Recent Changes

- **2026-10-15: created.** Case: a screenshot app's Cmd+Shift+X failed over a TigerVNC viewer. Two independent causes measured: a Karabiner `frontmost_application_if` rule (Command→Control for the viewer) rewrote the chord in every window state, and TigerVNC 1.16's `FullscreenSystemKeys` installed an active Session tap in full screen. Fix A and Fix B each verified with the logger and the tap census.
