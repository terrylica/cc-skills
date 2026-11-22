---
name: braille-tally
description: The Braille Tally — rank anything a person will read on a few axes at once, as one word-sized shape of Braille cells (⣿⣶⣴), one cell per axis, where level n of 8 is a cell with n dots. Default axes, in order, Importance · Urgency · Simplicity. Use it on every list of outstanding items, decisions, options, asks, tasks or recommendations that a human reads — and on every AskUserQuestion option, where a guard requires it. Prints, reads, draws (HTML, no font needed) and ranks tallies (Pareto fronts, no weights). TRIGGERS - braille tally, tally, rank these, prioritise, priority list, outstanding items, open items, what is waiting, options to choose from, AskUserQuestion, importance urgency simplicity, ranking glyph.
allowed-tools: Bash, Read
---

# Braille Tally

> **Self-Evolving Skill**: This skill improves through use. If a rule below proves wrong in a real app, a measurement no longer holds, or a workaround was needed: fix this file, `lib/tally.ts` and the tests at once, don't defer. Only update for real, reproducible issues.

A **Braille Tally** ranks an item on a few axes at once without merging them into one number. It is a short run of Braille cells, one per axis. **Level n (1–8) is the cell with exactly n dots**, filled from the bottom row up, so a taller column always means "more":

```
level  1 2 3 4 5 6 7 8
cell   ⡀ ⣀ ⣠ ⣤ ⣴ ⣶ ⣾ ⣿
```

Example: `⣿⣶⣴` is very important, fairly urgent, and moderately simple. `⡀⡀⡀` is the lowest on all three.

## The rules

1. **Default axes, in this order: Importance · Urgency · Simplicity.**
   - **Importance:** how much it serves the goal and protects the future.
   - **Urgency:** how soon it matters.
   - **Simplicity:** how little it takes to do or answer.

   For all three, taller is "sooner": do the tall ones first. Any other axes are allowed only with a legend that names them.

2. **Every tallied list carries the legend once, at its head.** AskUserQuestion is the exception: no legend there, because its axes are always the default three. The default legend is: _Braille Tally: Importance · Urgency · Simplicity, each column ⡀ (lowest) to ⣿ (highest), relative to the other items._
3. **Levels are relative.** Set each axis by comparing the items on that axis only, then snap to 1–8. Where a project has written anchors for the levels (what 8, 6, 4, 2 and 1 mean on each axis), use them, so adding an item does not reshuffle the others.
4. **Never merge the axes.** Order items by **Pareto front**:
   - front 1 is what no other item beats on every axis at once, front 2 is what only front 1 beats, and so on;
   - inside a front, the most urgent comes first, then the most important, then the simplest.
5. **Where it goes:**
   - **Lists a person reads** (open items, asks, tasks, findings, recommendations, plans, digests): each item starts with its tally.
   - **AskUserQuestion:** each option label starts with its tally and one space, always on the default axes, with no legend line in the question (operator, 2026-11-20: no preamble). Options are in rank order, so the first option is the recommended one and is in front 1. A guard in this plugin enforces both.
   - **Plain text that may be read without the shape** (an email's plain part, a screen reader): add the levels after the tally, `⣀⣿⣿ (2·8·8)`.
   - **HTML** (email bodies, web pages): draw it with `html`, which needs no Braille font, and keep the levels in small text beside it.
6. **Not for secrets or identity:** a tally carries only levels, so it is safe in any public place.

## Commands

```bash
BT="$(cc-plugin-root braille-tally)/scripts/braille-tally.ts"
bun "$BT" tally 8 6 5               # ⣿⣶⣴
bun "$BT" tally 2 8 8 --levels      # ⣀⣿⣿ (2·8·8)
bun "$BT" parse ⣠⣴⣾                 # 3 5 7
bun "$BT" legend                    # the default legend line
bun "$BT" legend --axes "Value,Risk,Effort"
bun "$BT" html 2 8 8 --levels --ink "#3c4043"   # drawn, for email and web pages
printf '%s\n' '{"id":"a","levels":[2,8,8]}' '{"id":"b","levels":[8,6,8]}' | bun "$BT" rank   # ranked, with fronts
bun "$BT" spec                      # the command set as JSON
```

Code that needs it can import `lib/tally.ts`, which has no dependencies: `tally`, `tallyWithLevels`, `levelsOf`, `legend`, `dominates`, `fronts`, `ranked`, `outOfRank` and `html`.

## The AskUserQuestion guard

`hooks/askuserquestion-tally-guard.ts` (PreToolUse, matcher `AskUserQuestion`) denies the call, with the exact fix, when any of these holds:

- an option label does not start with a tally;
- the options of one question have different numbers of cells;
- a later option beats an earlier one on every axis.

It fails open on anything unexpected.

**Escape:** put `BRAILLE-TALLY-EXEMPT` anywhere in the question, only when its options genuinely cannot be ranked. The token is named here and in the hook, and deliberately not in the deny message.

## Why Braille cells

These were measured in Chrome on macOS in a replica of Gmail's subject line, plain text in Google Sans with the system's fallbacks:

- **Block characters don't line up.** The Unicode block characters ▁▂▃▄▅▆▇█ come from several fonts in one line: Hiragino Sans for most, Arial for ▄, Helvetica for █. █ and ▄ end about 2.5 px lower, ▄ is narrower (9.9 px against 14 px), and the 7/8 block ▉ leaves a gap where the others touch. Fonts cover block elements unevenly ([fileformat.info](https://www.fileformat.info/info/unicode/block/block_elements/fontsupport.htm)), they sit at different heights in different fonts ([Unicode L2/17-194](https://www.unicode.org/L2/L2017/17194-block-elements.pdf); [Jon Udell](https://blog.jonudell.net/2021/08/05/the-tao-of-unicode-sparklines/)), and they are designed to join into one bar ([Hayden Schiff](https://www.schiff.io/blog/2020/04/16/google-sheets-scroll-chart/)).
- **One font draws every Braille pattern** (Apple Braille on macOS). All eight levels have one width (9.6 px at 14 px) and one bottom line, and the gap between cells is built into the font, so a tally is evenly spaced by construction.
- **Limits:**
  - Dotted columns are fainter than solid bars, and odd levels look like a small stair.
  - Typed Braille needs a font with Braille Patterns, and some apps fall back badly ([BossTerm #407](https://github.com/kshivang/BossTerm/issues/407)). The drawn HTML form and the levels in text do not depend on one.
  - Measured on macOS only.

## Evolution log

- **2026-11-20 — created.** _Trigger_: the operator's request to give the dot glyph, first used to rank asks in one project, a unique name and make it a convention for every project, device and agent, especially AskUserQuestion. _Choices (AskUserQuestion)_:
  - the name "Braille Tally";
  - a public plugin;
  - three fixed default axes, others only with a legend;
  - a blocking AskUserQuestion guard;
  - the tally at the start of each label, options ranked.

  _Evidence_: the measurements above; 17 tests in `tests/tally.test.ts`, including one that checks every drawn level against its Braille code point.
- **2026-11-20 (b) — no legend in AskUserQuestion.** _Trigger_: the operator: the legend line "should be removed from all AskUserQuestion … No need to be in the front of AskUserQuestion as preamble". _Fix_: the guard no longer requires "Braille Tally" in the question text; AskUserQuestion always uses the default axes; lists keep their legend. _Evidence_: a test that a tallied, ranked question without a legend passes.

## Post-Execution Reflection

After using this skill, check before closing the task:

1. **Did a tally render badly somewhere** (misaligned, empty boxes, wrong height)? Measure it, name the app and font, and add it to "Why Braille cells" and the README's limits.
2. **Did the guard block a question that could not honestly be ranked,** or let through one that should have been? Fix `problems()` with a test that reproduces it.
3. **Did a list need axes other than Importance · Urgency · Simplicity?** If the same other axes keep recurring, record them here as a named variant with its own legend.
