---
name: page-template
description: Scaffold a new HTML showcase page (provenance reports, contractor showcases, telemetry dashboards, weekly digests, audit results) with the canonical CSS kernel + skeleton template. Use whenever the user asks for an HTML page that presents structured technical work — metrics, commits, audit findings, before/after comparisons, anything that needs a polished presentation surface with full link provenance. Also use when the user mentions "showcase", "presentation page", "contractor portfolio", "audit results page", "telemetry report", "weekly digest", or "static HTML report". Do NOT use for blog posts, marketing landing pages, or interactive web apps.
allowed-tools: Read, Write, Edit, Bash
---

# HTML Showcase — Page Template

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

Scaffold a new static HTML page that links to the shared CSS kernel and
follows the project's canonical layout. The kernel lives on jsDelivr and
is shared across every repo; pages are pure HTML with optional per-page
CSS overrides.

## When to use

- Creating a new static HTML page that records structured work (audits,
  commits, metrics, reports, contractor showcases, telemetry views)
- Replacing inline-CSS pages with the shared design system
- Bootstrapping a multi-page mini-site that grows into a contractor portfolio,
  weekly-digest archive, or release-notes hub

## What ships

| Path                              | Role                                                             |
| --------------------------------- | ---------------------------------------------------------------- |
| `templates/index.html`            | Page skeleton with hero + 3 example sections + footer            |
| `templates/overrides.css.example` | Reference for per-page customization (rename to `overrides.css`) |
| `templates/lychee.toml`           | Link-checker config                                              |
| `scripts/check-orphan-pages.py`   | Pure-stdlib orphan-page graph validator                          |

The CSS kernel itself lives at the **plugin** level
(`plugins/html-showcase/assets/showcase.css`) and is served from jsDelivr —
the skeleton HTML references the public CDN URL, not a local file.

## Two-hierarchy architecture

The design enforces a strict separation:

| Layer                | What it controls                                                              | Where it lives                                   | Mutability                                       |
| -------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------ | ------------------------------------------------ |
| **H1 — Kernel**      | Tokens (colors, spacing, type, shadows), reset, base elements, all components | `assets/showcase.css` (served from jsDelivr CDN) | Edit once, ripples to every page that imports it |
| **H2 — Composition** | Which sections appear, in what order, with what content                       | The HTML file itself                             | Per-page; pure semantic markup                   |
| **H3 — Overrides**   | Per-page color or density tweaks only                                         | `overrides.css` next to the HTML                 | Optional; tiny file                              |

The HTML never invents styles. It only arranges components defined by the
kernel. To change the global look-and-feel, edit the kernel — every page
inherits the change. To customize one page only, drop a few CSS variables
into its `overrides.css`.

## Universal density knobs (in the kernel)

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
component CSS.

## How to use

1. Copy the templates into the destination directory:

   ```bash
   DEST=/path/to/site-dir
   mkdir -p "$DEST"
   cp ${CLAUDE_PLUGIN_ROOT:-~/eon/cc-skills/plugins/html-showcase}/skills/page-template/templates/index.html "$DEST/"
   cp ${CLAUDE_PLUGIN_ROOT:-~/eon/cc-skills/plugins/html-showcase}/skills/page-template/templates/lychee.toml "$DEST/"
   cp ${CLAUDE_PLUGIN_ROOT:-~/eon/cc-skills/plugins/html-showcase}/skills/page-template/templates/overrides.css.example "$DEST/overrides.css"
   ```

2. Fill in the `{{ PLACEHOLDERS }}` in `index.html` with the page's actual
   content. Keep the structure — replace only the text and links.
3. Customize colors/density (optional) by editing `overrides.css`.
4. Open the file in a browser:

   ```bash
   open "$DEST/index.html"
   ```

   No server needed — the kernel CSS is fetched from jsDelivr at page load.

5. Verify integrity:

   ```bash
   lychee --config "$DEST/lychee.toml" "$DEST/**/*.html"
   python3 ${CLAUDE_PLUGIN_ROOT:-~/eon/cc-skills/plugins/html-showcase}/skills/page-template/scripts/check-orphan-pages.py "$DEST/"
   ```

## Component vocabulary (what classes are available)

The kernel defines these semantic classes; use them in your HTML. To inspect
the full set, open the kernel CSS and search for class selectors:

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

## CDN versioning

The kernel URL pins to the `@main` branch during early iteration:

```
https://cdn.jsdelivr.net/gh/terrylica/cc-skills@main/plugins/html-showcase/assets/showcase.css
```

After the kernel stabilizes (~1-2 weeks of real use), switch to a tagged
release for stability:

```
https://cdn.jsdelivr.net/gh/terrylica/cc-skills@v1/plugins/html-showcase/assets/showcase.css
```

Tagged URLs are immutable and cached forever; pages built against `@v1`
keep looking the same regardless of future kernel edits, until you decide
to bump them to `@v2`.

### Cache-busting during iteration

While pinned to `@main`, jsDelivr's CDN caches the file for up to 7 days.
After pushing a kernel change, force a fresh fetch by hitting the purge
endpoint once:

```bash
curl -fsSL "https://purge.jsdelivr.net/gh/terrylica/cc-skills@main/plugins/html-showcase/assets/showcase.css"
```

Or, during heavy iteration, append `?v=$(date +%s)` to the kernel link in
your HTML to bypass cache entirely.

## Why a CDN, not a local copy

A page that links to a copy of the kernel fixes its appearance to whatever
existed when it was scaffolded — kernel improvements never reach it. By
linking to jsDelivr, every page always reflects the latest kernel (within
the chosen version pin), so a single edit to `assets/showcase.css` followed
by `git push` ripples a coordinated visual update across every page in
every repo. That's the whole point.

## Hard rules

These are baked into the kernel and templates; if you find yourself wanting
to break them, fix the kernel instead.

- No inline `<style>` blocks.
- No `style=""` attributes on HTML elements.
- No utility-class soup in HTML — class names are semantic (`.metric-card`,
  `.badge--high`), never atomic (`flex p-4 bg-blue-500`).
- The kernel is the single source of truth for every visual decision.
- HTML only arranges components; it never invents them.

## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path before editing.
1. **What failed?** — Fix the instruction that caused it. If the kernel was insufficient (a real component was missing), add it to the kernel and bump the version.
2. **What worked better than expected?** — Promote to recommended practice. If a new section pattern emerges across multiple pages, distill it into a kernel component.
3. **What drifted?** — Fix any script, reference, or dependency that no longer matches reality. The CDN URL pin (`@main` vs `@vN`), the override pattern, the component vocabulary table — keep them aligned with the actual kernel.
4. **Log it.** — Evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
