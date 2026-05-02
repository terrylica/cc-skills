---
name: page-template
description: Scaffold a new HTML showcase page (provenance reports, contractor showcases, telemetry dashboards, weekly digests, audit results) with the canonical CSS kernel + skeleton template. Use whenever the user asks for an HTML page that presents structured technical work — metrics, commits, audit findings, before/after comparisons, anything that needs a polished presentation surface with full link provenance. Also use when the user mentions "showcase", "presentation page", "contractor portfolio", "audit results page", "telemetry report", "weekly digest", or "static HTML report". Do NOT use for blog posts, marketing landing pages, or interactive web apps.
allowed-tools: Read, Write, Edit, Bash
---

# HTML Showcase — Page Template

> **Self-Evolving Skill**: This skill improves through use. If instructions
> are wrong, parameters drifted, or a workaround was needed — fix this file
> immediately, don't defer. Only update for real, reproducible issues.

A static HTML page that links to a shared CSS kernel and follows a
canonical layout. The kernel lives on jsDelivr; pages are pure HTML
with optional per-page CSS overrides. The architecture is built on five
principles — **read [`references/principles.md`](references/principles.md)
first** to internalize the WHY before extending or forking.

## Read this skill at the principle level, not the instruction level

Every concrete artifact in this skill (class names, file paths, the
specific CDN URL, the commit-message conventions) is an _instance_ of a
small set of underlying principles. If you understand the principles,
you can deviate intelligently from any specific instance without breaking
the architecture. If you only follow the instructions, you'll bend the
system out of shape the first time something doesn't fit your case.

The principles are catalogued in [`references/principles.md`](references/principles.md):

1. **Single source of truth** — every visual decision lives in one file
2. **Semantic over atomic** — class names describe what an element _is_
3. **Token-driven** — every concrete value flows from a CSS custom property
4. **Cascade discipline** — `@layer` ordering enforces specificity globally
5. **No hidden state** — no JS, no inline CSS, no scattered overrides

Plus AI-collaboration patterns (why this design is LLM-friendly), and
the rationale for using a CDN rather than copies.

## Three-layer hierarchy

| Layer                | Mutability                     | What it controls                                                | Where it lives                       |
| -------------------- | ------------------------------ | --------------------------------------------------------------- | ------------------------------------ |
| **H1 — Kernel**      | Edit once → ripples everywhere | Tokens (color, spacing, type), reset, base elements, components | `assets/showcase.css` (jsDelivr CDN) |
| **H2 — Composition** | Per-page                       | Section order, content, semantic markup                         | The HTML file itself                 |
| **H3 — Overrides**   | Per-page (optional)            | Color or density tweaks for ONE page                            | `overrides.css` next to the HTML     |

The kernel is the SSoT for every visual decision. HTML never invents
styles; it only arranges components defined by the kernel. To customize
one page, drop a few CSS variables into `overrides.css`. To customize
EVERY page, edit the kernel.

## Four contributor stances

Pick the role that matches your task. Full workflow for each in
[`references/contributing.md`](references/contributing.md).

| Role            | Example task                                                  | Edits               | Affects                          |
| --------------- | ------------------------------------------------------------- | ------------------- | -------------------------------- |
| **Consumer**    | "Make me a contractor showcase page"                          | Your HTML           | Just your page                   |
| **Customizer**  | "Re-theme this page with our brand teal"                      | `overrides.css`     | Just your page                   |
| **Contributor** | "Add a `.timeline` component to the kernel"                   | Kernel CSS upstream | Every page using this kernel     |
| **Publisher**   | "Our team forks the kernel and publishes from our own GitHub" | Your fork's kernel  | Pages that pin to _your_ CDN URL |

## When to use this skill

- Creating a new static HTML page that records structured work (audits,
  commits, metrics, reports, contractor showcases, telemetry views)
- Replacing inline-CSS pages with the shared design system
- Bootstrapping a multi-page mini-site that grows into a contractor
  portfolio, weekly-digest archive, or release-notes hub

Do NOT use for: blog posts, marketing landing pages, interactive web apps.

## What ships in this skill

| Path                              | Role                                                             |
| --------------------------------- | ---------------------------------------------------------------- |
| `templates/index.html`            | Page skeleton with hero + 3 example sections + footer            |
| `templates/overrides.css.example` | Reference for per-page customization (rename to `overrides.css`) |
| `templates/lychee.toml`           | Link-checker config                                              |
| `scripts/check-orphan-pages.py`   | Pure-stdlib orphan-page graph validator                          |
| `references/principles.md`        | The WHY — five principles + AI patterns                          |
| `references/contributing.md`      | The HOW — four stances with full workflows                       |

The CSS kernel itself lives at the **plugin** level
(`plugins/html-showcase/assets/showcase.css`) and is served from jsDelivr —
the skeleton HTML references the public CDN URL, not a local file.

## Universal density knobs

Two CSS custom properties at the top of `showcase.css` control the entire
visual rhythm. Override either in `overrides.css` to retune one page:

```css
:root {
  --density: 0.85; /* spacing multiplier; 1.0 baseline, lower = tighter */
  --font-scale: 0.94; /* type multiplier; 1.0 baseline, lower = smaller */
}
```

Every padding, gap, margin, and section rhythm in the kernel derives from
the spacing scale; the spacing scale derives from `--density`. Body font
size derives from `--font-scale`. There are no scattered magic numbers in
component CSS — see Principle 3 in `references/principles.md`.

## Component vocabulary

The kernel defines these semantic classes; HTML uses them. To inspect the
full set, open the kernel CSS and search for class selectors.

| Class                                                                                          | Purpose                                                                  |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `.hero` + `.hero__inner` / `__eyebrow` / `__title` / `__lede` / `__cta-row`                    | Top banner with gradient                                                 |
| `.chip--solid` / `.chip--ghost`                                                                | Hero CTA buttons                                                         |
| `.metric-grid` + `.metric-card`                                                                | At-a-glance number panel; modifiers `--accent`, `--success`, `--warning` |
| `.phase-grid` + `.phase-card`                                                                  | Phased timeline cards; modifiers `--audit`, `--fix`, `--perf`            |
| `.commit-stack` + `.commit-card`                                                               | Detailed commit cards with SHA chip + details grid                       |
| `.bug-grid` + `.bug-card` (`--high` modifier)                                                  | Compact issue cards                                                      |
| `.feature-grid` + `.feature-card`                                                              | Generic 4-column showcase grid with icon                                 |
| `.reco-list` + `.reco-item` (`--p0` / `--p1` / `--p2`)                                         | Priority-ordered recommendations                                         |
| `.badge` (`--high` / `--medium` / `--low` / `--success` / `--info` / `--neutral` / `--accent`) | Severity / status labels                                                 |
| `.section-head` / `.section-intro`                                                             | Per-section title row + framing paragraph                                |
| `.shell`                                                                                       | Centered content shell with max-width and responsive padding             |
| `.site-footer` + `.site-footer__grid` / `__legal`                                              | Provenance footer                                                        |

If your page needs a component not in this table, you have two choices —
both legitimate, both documented in `references/contributing.md`:

- **Add it to the kernel** (Stance 3): semantic class name in the
  `components` `@layer`, token-referenced values, BEM modifier variants.
- **Use a local override** for one-off cases (Stance 2): only if the
  pattern is genuinely unique to one page; recurring patterns belong in
  the kernel.

## Quick start (Consumer stance)

```bash
DEST=/path/to/site-dir
PLUGIN=${CLAUDE_PLUGIN_ROOT:-~/.claude/plugins/marketplaces/cc-skills/plugins/html-showcase}

mkdir -p "$DEST"
cp "$PLUGIN/skills/page-template/templates/index.html" "$DEST/"
cp "$PLUGIN/skills/page-template/templates/lychee.toml" "$DEST/"

# (Optional, only if customizing colors / density)
cp "$PLUGIN/skills/page-template/templates/overrides.css.example" "$DEST/overrides.css"

# Fill {{ PLACEHOLDERS }} in index.html, then:
open "$DEST/index.html"

# Verify:
lychee --config "$DEST/lychee.toml" "$DEST/**/*.html"
python3 "$PLUGIN/skills/page-template/scripts/check-orphan-pages.py" "$DEST/"
```

For the other three stances (Customizer, Contributor, Publisher), see
[`references/contributing.md`](references/contributing.md).

## CDN versioning

The kernel URL pins to the `@main` branch during early iteration, then
to a tagged release once the kernel stabilizes:

```
@main      → always-latest         → use during development; jsDelivr cache flushed automatically on each release
@v<X.Y.Z>  → immutable, content-locked → use for production-stable pages
@<sha>     → immutable, commit-locked  → use for forensic-grade pinning
```

The release flow auto-purges `@main` and smoke-tests `@v<X.Y.Z>` after
each release. To force-refresh `@main` between releases (e.g., during
heavy iteration on the kernel), run `mise run release:cdn-purge` from
the cc-skills repo. To bypass cache entirely on a single page, append
`?v=$(date +%s)` to the kernel link.

## Hard rules

These are baked into the kernel and templates; if you find yourself
wanting to break them, fix the kernel instead (see Stance 3 in
`references/contributing.md`).

- No inline `<style>` blocks.
- No `style=""` attributes on HTML elements.
- No utility-class soup in HTML — class names are semantic
  (`.metric-card`, `.badge--high`), never atomic
  (`flex p-4 bg-blue-500`).
- The kernel is the single source of truth for every visual decision.
- HTML only arranges components; it never invents them.
- Every page must pass Lychee link-check and the orphan-page detector
  before it's considered shipped.

## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path before editing.
1. **What failed?** — Fix the instruction. If a kernel component was missing, add it (Stance 3). If a _principle_ was unclear, fix `references/principles.md`.
2. **What worked better than expected?** — If a new section pattern recurs, distill it into a kernel component.
3. **What drifted?** — Keep CDN URL pins, override examples, and component vocabulary aligned with the actual kernel.
4. **Log it.** — Evolution-log entry with trigger, fix, evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
