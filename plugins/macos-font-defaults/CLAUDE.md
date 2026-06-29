# macos-font-defaults Plugin

> Point macOS's fixed-width font (and TextEdit / Stickies defaults) at a chosen font — idempotently.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md)

## Why

macOS exposes no single "system monospaced font" setting. The nearest real knob is the
global `NSFixedPitchFont` default, which drives `+[NSFont userFixedPitchFontOfSize:]`.
This plugin sets that, plus TextEdit's explicit plain-text font and the Stickies default
note font, in one idempotent, parameterized script — so the same command both applies the
preference now and re-applies it on a fresh machine.

## Scope (verified 2026-06-29)

- Covers: standard-text-system apps that ask for the user fixed-pitch font (e.g. TextEdit
  plain text), and Stickies new notes.
- Does NOT cover: Terminal/iTerm/VS Code (own settings), Apple Notes (hardcoded mono face;
  only its per-note "Monostyled" style — see the `draft-hold` plugin), or system UI.

## Skill

- [macos-font-defaults](./skills/macos-font-defaults/SKILL.md)

## Script

`skills/macos-font-defaults/apply.sh {check|apply} [--font POSTSCRIPT_NAME] [--size N]`

- `check` reports the current user fixed-pitch font, global/TextEdit/Stickies values.
- `apply` sets all three to the target font (default `JetBrainsMonoNLNF-Regular`); size
  is left at the macOS default unless `--size` is given. Fails fast if the font is absent.
- Stickies' default is an archived `NSFont` in its sandbox container plist; the script
  writes it via Swift `NSKeyedArchiver`, only when it differs (quitting a running Stickies).
