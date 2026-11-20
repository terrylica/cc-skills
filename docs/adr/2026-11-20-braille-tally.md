# ADR: The Braille Tally, a ranking glyph for everything a person reads (2026-11-20)

- **Date**: 2026-11-20
- **Status**: Accepted
- **Severity**: Convention, plus a hard block on AskUserQuestion (PreToolUse deny, token escape)
- **Design spec**: [/docs/design/2026-11-20-braille-tally/spec.md](/docs/design/2026-11-20-braille-tally/spec.md)

## Context

Lists that ask a person to choose or act (outstanding items, asks, options, findings) were ranked in prose, or by a single score that merged several concerns into one number. A project that ranked its asks on three axes (importance, urgency, simplicity) wanted the ranking readable at a glance as one shape per item. The first form, Unicode block characters ▁…█, failed in plain text:

- **The bars come from several fonts in one line.** Measured in Chrome on macOS in a replica of Gmail's subject line (Google Sans, then the system's fallbacks): ▁▂▃▅▆▇▉ come from Hiragino Sans, ▄ from Arial, █ from Helvetica.
- **So they misalign.** █ and ▄ end about 2.5 px lower, ▄ is 9.9 px wide against 14 px, and ▉ leaves a gap where the others touch.

Fonts cover block elements unevenly ([fileformat.info](https://www.fileformat.info/info/unicode/block/block_elements/fontsupport.htm)), they sit at different heights in different fonts ([Unicode L2/17-194](https://www.unicode.org/L2/L2017/17194-block-elements.pdf)), and they are built to join into one bar ([Hayden Schiff](https://www.schiff.io/blog/2020/04/16/google-sheets-scroll-chart/)).

Braille patterns do not have this problem. One font draws all of them (Apple Braille on macOS), with one width (9.6 px at 14 px) and one bottom line, and the gap between cells is built into the font. The operator asked for the shape to get a unique name and to become a convention across every project, device, agent and ally, used as often as possible, especially in AskUserQuestion.

## Decision

1. **Name: the Braille Tally.** It is a run of Braille cells, one per axis. Level n of 8 is the cell with exactly n dots, filled from the bottom row up: `⡀⣀⣠⣤⣴⣶⣾⣿`. "Tally" because the dots count the level.
2. **Default axes, fixed order: Importance · Urgency · Simplicity.** Other axes are allowed only with a legend that names them, so the shape means the same thing wherever it appears without one.
3. **Ranking without weights:** Pareto fronts, with ties inside a front broken by urgency, then importance, then simplicity.
4. **AskUserQuestion is held to it by a guard.** Each option label starts with a tally and one space, and options are in rank order. The question carries no legend: its axes are always the default three (operator, 2026-11-20, the same day: "No need to be in the front of AskUserQuestion as preamble"). A PreToolUse hook denies the call otherwise, with the exact fix. It fails open on anything unexpected. The escape token is documented in the skill, never in the deny message.
5. **One public plugin, `braille-tally`, is the home.** It holds the skill (the SSoT of the convention), a dependency-free library, a CLI (`tally`, `parse`, `legend`, `html`, `rank`, `spec`) and the guard. Adopters add one line to their own CLAUDE.md so the tally reaches lists as well as questions.
6. **HTML draws the tally rather than typing it.** In HTML (email bodies, web pages) the tally is drawn from the Braille bit pattern as small boxes, so it needs no Braille font. Plain text that may be read without the shape adds the levels: `⣀⣿⣿ (2·8·8)`.

## Alternatives rejected

- **A weighted score** (WSJF, ICE): it merges the axes into one number, which is what the operator ruled out.
- **Block characters ▁…█:** they misalign, as measured above.
- **Block characters with spacers:** narrow spaces evened the gaps, but ▄ still dipped and kept its own width.
- **Numbers only** (`2·8·8`): they always align, but give no shape at a glance. They are kept as the companion to the tally, not as a replacement.
- **A reminder in place of a guard:** easy to drift from. The operator chose the guard so that the habit is enforced rather than remembered.

## Consequences

- One shape and one legend in every list, question, subject line and page, and a ranking that never hides a trade-off in one number.
- AskUserQuestion calls cost a little more thought: every option needs three honest levels.
- **Typed tallies depend on a Braille font.** Most systems ship one, and some apps fall back badly ([BossTerm #407](https://github.com/kshivang/BossTerm/issues/407)). The drawn HTML form and the levels in text do not depend on one. Measured on macOS only so far.
