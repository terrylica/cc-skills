# Design spec: braille-tally plugin

**ADR**: [/docs/adr/2026-11-20-braille-tally.md](/docs/adr/2026-11-20-braille-tally.md)

## Before and after

```
Before                                     After
──────                                     ─────
1. Rotate the leaked key (high priority)   Braille Tally: Importance · Urgency · Simplicity, ⡀ … ⣿
2. Renew the certificate (urgent, easy)    1. ⣿⣿⣶  Rotate the leaked key
3. Pick a release date (medium)            2. ⣶⣿⣿  Renew the certificate
                                           3. ⣤⣠⣿  Pick a release date
AskUserQuestion options: plain labels      AskUserQuestion options: "⣿⣶⣴ Keep the guard (Recommended)", ranked
```

## Architecture

```
skills/braille-tally/SKILL.md      the convention (SSoT): axes, legend, ranking, placement, evidence
        │
lib/tally.ts                       the only implementation, no dependencies
  CELLS ⡀⣀⣠⣤⣴⣶⣾⣿ · tally · tallyWithLevels · levelsOf · leadingTally · legend
  dominates · fronts · ranked · outOfRank · html · htmlWithLevels
        │                    │
scripts/braille-tally.ts     hooks/askuserquestion-tally-guard.ts   (PreToolUse, matcher AskUserQuestion)
  tally parse legend html      problems(input) → deny with the exact fix, or allow
  rank spec                    fail open; escape BRAILLE-TALLY-EXEMPT
        │
tests/tally.test.ts            bun test: cells from code points, ranking, drawn dots vs bits, guard (in process and as a process), CLI
```

## Guard rules

For each question in `tool_input.questions`:

1. Every option `label` matches `^[⡀⣀⣠⣤⣴⣶⣾⣿]{2,6}` (a tally of 2 to 6 cells, then one space).
2. All options of the question have the same number of cells.
3. No later option dominates an earlier one: `outOfRank` returns undefined.

Any violation produces one deny that lists every problem. When the payload is unparseable or of an unexpected shape, the guard allows the call and prints nothing.

## Drawn HTML

Each level is two inline-block columns of four block-level dots. The left column uses the bits 0x01, 0x02, 0x04 and 0x40, and the right column 0x08, 0x10, 0x20 and 0x80, top row first. A dot is filled where the level's code point has that bit. Every cell is the same size, and the bottom edge of the drawing sits on the text baseline. A test compares each of the eight levels with its code point.

## Verification

- `bun test` in `plugins/braille-tally`: 17 tests.
- `bun scripts/validate-plugins.mjs`: all plugins valid.
