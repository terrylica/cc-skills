# braille-tally

The **Braille Tally** ranks an item on a few axes at once without merging them into one number. It is a short run of Braille cells, one per axis, where **level n of 8 is the cell with n dots**:

```
level  1 2 3 4 5 6 7 8
cell   ⡀ ⣀ ⣠ ⣤ ⣴ ⣶ ⣾ ⣿
```

The default axes, in order, are **Importance · Urgency · Simplicity**. For example, `⣿⣶⣴` means very important, fairly urgent and moderately simple. A taller column always means "do it sooner".

```
Braille Tally: Importance · Urgency · Simplicity, each column ⡀ (lowest) to ⣿ (highest), relative to the other items.

1. ⣿⣿⣶  Rotate the leaked API key
2. ⣶⣿⣿  Renew the TLS certificate (expires Friday)
3. ⣤⣠⣿  Pick the next release date
```

**Why Braille cells:** one font draws every Braille pattern, so a tally stays evenly spaced and bottom-aligned even in plain text: a mail subject line, a terminal, a chat. The block characters ▁…█ come from several fonts in one line and do not line up.

## What the plugin gives you

| Part                        | What it does                                                                                                                                                               |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Skill `braille-tally`       | The convention: axes, legend, Pareto ranking, where tallies go, the measurements behind it                                                                                 |
| `scripts/braille-tally.ts`  | `tally`, `parse`, `legend`, `html` (drawn, no font needed, for email and web pages), `rank` (Pareto fronts) and `spec`                                                     |
| `lib/tally.ts`              | The same functions to import, with no dependencies                                                                                                                         |
| Hook: issue-title guard     | Blocks creating or retitling a GitHub issue (`gh issue create/edit`, `gh api`, a shell script that does either, GitHub MCP tools) when the title does not start with a tally and one space. The glyph alone: `⣿⣶⣴ Fix the login timeout`. A reader scanning the issue list sees how each issue was assessed |
| Hook: AskUserQuestion guard | Blocks a question in two cases: an option label that doesn't start with a tally, or options out of rank. The question itself needs no legend: its axes are always the default three. It says exactly what to fix |

## Adopt it

1. Install the plugin:

   ```bash
   claude plugin marketplace add terrylica/cc-skills
   claude plugin install braille-tally@cc-skills
   ```

   It needs [Bun](https://bun.sh) on the PATH.

2. Add one line to your own `CLAUDE.md` (user-level or project-level), so every session uses it on lists too, not only in AskUserQuestion and issue titles:

   ```markdown
   - **Braille Tally on everything a person reads that ranks items** (open items, options, asks, tasks): each item starts with its tally, Importance · Urgency · Simplicity, levels ⡀…⣿, with the legend once per list; every GitHub issue title starts with its tally → `Skill(braille-tally:braille-tally)`.
   ```

3. Optional: in HTML (emails, web pages), draw tallies with `bun scripts/braille-tally.ts html 2 8 8 --levels`, so they render without a Braille font.

The tally carries only levels, never personal data, so it is safe anywhere.

## Limits

- Dotted columns are fainter than solid bars.
- Typed Braille needs a font with Braille Patterns; most systems have one, but check yours. The drawn HTML form and the levels in text don't need one.
- In **bold** text, Chrome on macOS falls back to an outline Braille face that draws a hollow ring at every unraised dot, so GitHub's semibold issue list shows full grids of rings. Safari and Windows browsers are unaffected. A CSS alias for the page or a user stylesheet fixes it: see "Reading tallies on macOS Chrome" in the skill.
- Measured on macOS, and the bold fallback also on Windows. Reports from other systems are welcome.
