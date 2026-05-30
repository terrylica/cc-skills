# html-showcase Plugin

> Sitemap-organized static HTML mini-sites with a CDN-served CSS kernel and an
> auto-discovered, auto-fitting navigation rail. Filesystem layout IS the
> navigation graph.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [plugins/CLAUDE.md](../CLAUDE.md)

## Overview

Scaffolds polished static HTML pages (provenance reports, contractor
showcases, telemetry dashboards, weekly digests, audit results) that share a
single CSS kernel served from jsDelivr. A multi-page mini-site needs **zero
hand-written navigation**: drop HTML files in directories, run
`build-nav.py`, and the sitemap + per-page nav rail rewrite themselves.

The architecture is built on six load-bearing principles:

1. **SSoT for visual decisions** — the kernel is the only source for color, spacing, type
2. **Semantic over atomic** — class names describe what an element _is_
3. **Token-driven** — all values flow from CSS custom properties
4. **Cascade discipline** — `@layer` ordering enforces specificity globally
5. **No hidden state** — no JS, no inline CSS, no scattered overrides
6. **Filesystem-as-sitemap** — directory layout IS the navigation graph

See [`skills/page-template/references/principles.md`](./skills/page-template/references/principles.md)
for the full rationale.

## Skills

- [page-template](./skills/page-template/SKILL.md) — scaffold a sitemap-organized HTML site (templates + scripts + design contract)
- [setup](./skills/setup/SKILL.md) — install the pipeline scripts into the current repo (idempotent, non-destructive)

## Commands

| Command                        | Purpose                                                                              |
| ------------------------------ | ------------------------------------------------------------------------------------ |
| `/html-showcase:setup`         | Bootstrap a repo: install `scripts/build-nav.py`, `check-orphan-pages.py`, `site.sh` |
| `/html-showcase:page-template` | Scaffold a new HTML showcase page or multi-page site                                 |

Either skill can be invoked without the other; setup is the one-shot
bootstrapper, page-template is the authoring guide.

## Dependencies

| Tool      | Required for           | Install                                           |
| --------- | ---------------------- | ------------------------------------------------- |
| `python3` | `build-nav.py`         | macOS ships 3.9+; this plugin works on **3.10+**  |
| `lychee`  | link validation        | `brew install lychee` (or `cargo install lychee`) |
| `rsync`   | publishing to bigblack | preinstalled on macOS                             |
| `ssh`     | publishing to bigblack | preinstalled on macOS                             |
| `git`     | repo detection         | preinstalled on macOS                             |

The scripts use **only Python stdlib** — no `pip install` step. Lychee is the
only non-built-in tool, and the publishing path (`site.sh push`) is opt-in.

## Critical Invariants

These are baked into the design — break them and the system bends out of
shape. If you find yourself wanting to violate one, that's a signal to
re-read the principle, not to work around it.

- **The kernel is the SSoT for every visual decision.** No inline `<style>`,
  no `style=""` attrs, no utility-class soup. HTML composes components; HTML
  never invents components.
- **The CSS kernel is CDN-served, not copied.** `assets/showcase.css` is
  served from `cdn.jsdelivr.net/gh/terrylica/cc-skills@main/...` so a single
  kernel push ripples coordinated visual updates across every page in every
  repo. Local copies fix a page's appearance to whatever existed when it
  was scaffolded.
- **The navigation rail is generated, not hand-written.** Content between
  `<!-- AUTO-NAV-START -->` and `<!-- AUTO-NAV-END -->` markers is rewritten
  on every `build-nav.py` run. Hand edits don't survive.
- **The auto-nav rail's CSS/JS travel with the site dir, not the CDN.** They
  live in `<site-root>/auto-nav.{css,js}` so a repo can adopt the rail
  without adopting the kernel CSS, and so the rail still works for sites
  served from networks that can't reach jsDelivr.
- **Sections sort by date prefix when available.** Slugs matching
  `YYYY-MM-DD-<rest>` trigger chronological newest-first ordering for ALL
  sections; mixed sets put dated sections first, then undated alphabetical.
- **Pages within a section sort newest-first, with a pin escape hatch.**
  The tier order inside a section (top to bottom) is:
  1. The section's `index.html` — always first.
  2. **Pinned pages** — any page containing `<!-- nav-pin -->` (or
     `<!-- nav-pin: N -->` for explicit priority where lower = higher up)
     in its HTML body. Ties broken by descending iter-N then descending
     birthtime. This is the user's escape hatch for "this canonical
     anchor page stays at the top even when 50 newer iterations land."
  3. **Unpinned `index_iter_<N>_<slug>.html` pages** — sorted
     **descending by N** (iter_315 above iter_314 above iter_2, integer
     compare so `iter_10` correctly outranks `iter_2`).
  4. **Other unpinned top-level pages** — sorted by filesystem birthtime,
     newest first.
  5. **Nested pages** — grouped by subdirectory, then `index.html` first,
     then alphabetical within each subdir.

  **Why newest-first by default**: when a campaign produces iter_1 →
  iter_N, the operator's most-pressing question is "what's the latest?"
  — that page should sit at the top of the rail, not buried hundreds of
  entries down. The previous chronological-ascending default forced the
  user to scroll past stale work to reach the active edge.

  **Why birthtime over mtime**: rebuilds, find-replace passes, and CI
  all touch `mtime` — using it would re-order the rail every time
  anyone edits anything. Birthtime is set once and never moves.
  **Why iter-N over birthtime when available**: birthtime resets on
  `git clone` (new inodes), so for cross-machine canonical ordering
  the `iter-N` filename token is the durable signal.
  **Why a comment marker, not a sidecar file, for pins**: the marker
  lives WITH the page so renaming, regenerating, or git-cloning the
  file never desynchronizes pin state from page identity. No manifest
  to keep in sync; no orphaned `.nav-pin` file to forget about.

- **Page-theme freedom; rail theme is the constant.** Individual pages
  can adopt any color scheme the AI judges appropriate for the content
  (dark dashboard, light contractor showcase, sepia post-mortem) —
  pages are not required to coordinate with each other. The nav rail
  and the site-map stay dark across every page so the navigation
  surface is the recognizable anchor across the whole site. If a page
  needs to override its own background, it does so in its own
  `overrides.css`; the rail's appearance is not configurable per page
  on purpose.
- **Nav rail + site-map are ALWAYS dark.** The rail's `auto-nav.css`
  and the site-map's inline `<style>` both pin `color-scheme: dark` and
  use the slate-950 / slate-300 / indigo-400 palette regardless of the
  host page's theme. The rail is the _constant_ across every page in
  the system, and inconsistent rail theming was reported as a real
  user-facing bug (e.g., a dark dashboard page with a glaring white
  rail). If you want a light variant of the rail in the future, gate
  it on a class on the `<details>` element — never let "the page
  happens to be light, so the rail follows" leak in.
- **Cache-bust via `?v=N` only.** When the rail's CSS or JS body inside
  `build-nav.py` changes, bump `--asset-version` (default in the script).
  The browser sees a new URL and re-fetches; we don't rely on
  `Cache-Control` headers.
- **Prev/Next keys are bare `[` / `]`, and the handler MUST stay guarded.**
  Bare brackets are deliberate: `Cmd+[` / `Cmd+]` are macOS Back/Forward, so
  the unmodified keys are free to repurpose for sibling navigation. The
  `AUTO_NAV_JS_BODY` keydown handler must always early-return when any
  modifier is held or when focus is in an input / textarea / select /
  contenteditable element — otherwise it would hijack typing in the Pagefind
  search box. Never relax these guards; never switch to a modified chord
  (that would collide with the browser's own shortcuts).
- **Body gutter is part of the rail contract.** The rail injects
  `padding-left: 28px` (collapsed) / `padding-left: 40px` (open) and
  `padding-right: 28px` on `<body>` via `!important`, plus a clamped
  `max-width` so wide pages cannot push content underneath the rail.
  This was added per user feedback 2026-05-26 (the iter_315
  PRESENTATION_REFACTOR): without the gutter, page content butted
  directly against the rail's right edge and the eye had nowhere to
  land between the two visual surfaces. Pages declaring their own
  `body { padding: ... }` will be overridden — that's intentional.

## Recent Changes

- **2026-05-29 — within-section Prev/Next (asset version v7).** Ported the
  firing-219 navigation pattern from the `opendeviationbar-patterns`
  dashboard rail:
  - **`‹ ›` buttons on the "Site" header row** (Section 1 of `render_rail()`).
    They ride the existing header via `display: flex; justify-content:
space-between` (`.rail-h-nav`), so they add **zero** vertical height.
    Disabled (greyed, `pointer-events: none`) at the ends of the sequence.
    Only rendered for pages inside a section; the home/top-level rail keeps
    a plain "Site" header.
  - **Chrome-safe `[` / `]` keyboard shortcut** (`AUTO_NAV_JS_BODY` keydown
    handler). Bare `[` = previous sibling, `]` = next. The handler bails when
    any modifier (`metaKey`/`ctrlKey`/`altKey`/`shiftKey`) is held or when
    focus is in `INPUT`/`TEXTAREA`/`SELECT`/`contenteditable`, so it never
    hijacks typing in the search box. Bare brackets are unreserved on macOS
    (only `Cmd+[` / `Cmd+]` are Back/Forward).
  - **Neighbor semantics**: prev/next are the visually-adjacent siblings in
    the flat `section["pages"]` list — `‹` = the page above (newer, since the
    list is newest-first), `›` = the page below (older). URLs are surfaced as
    `data-prev-url` / `data-next-url` on `<details class="auto-nav-rail">`
    (absent at the ends) and read by the keydown handler.
  - New CSS: `.rail-h-nav` / `.rail-prevnext` / `.rail-pn` / `.rail-pn-disabled`
    in `AUTO_NAV_CSS_BODY`.
- **2026-05-26 — iter_315 PRESENTATION_REFACTOR (asset version v6).**
  Three concurrent changes ported from a downstream user-facing edit
  into the plugin defaults:
  - **Body gutter (28-40px)**: rail now injects `padding-left` /
    `padding-right` / clamped `max-width` on `<body>` so page content
    has breathing room next to the rail.
  - **Rail typography shrunk ~20%**: base rail font 0.9rem → 0.72rem,
    cascading into `.rail-h` 0.7→0.58rem, `.rail-date` 0.7→0.58rem,
    `.rail-link` 0.86→0.7rem, `.rail-toggle-icon` 1.25→1.05rem,
    `.rail-toggle-label` 0.78→0.65rem, Pagefind UI inputs/results
    correspondingly tightened. The rail now reads as a dense index,
    not a billboard.
  - **Site-map tightened**: body font 0.92rem baseline, h1 1.55rem,
    headings 1rem, list items 0.85em, deeper background palette
    (`#0b1120` outer / `#111c33` container) to match the dashboard
    spokes' visual register.
  - **Newest-first iter-N ordering**: pages within a section now sort
    descending by iter-N (was ascending), and unpinned non-iter pages
    sort descending by birthtime. `<!-- nav-pin -->` comment marker
    added as an escape hatch for anchoring a canonical page to the
    top regardless of newer iterations.

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│  Authored HTML (per-page, per-section index)                       │
│  arranges semantic components from the kernel                      │
└────────────────────────────────────────────────────────────────────┘
            │                                      │
            ▼                                      ▼
┌──────────────────────────────┐    ┌───────────────────────────────┐
│  showcase.css (kernel)       │    │  build-nav.py walks site root │
│  served from jsDelivr CDN    │    │  → site-map.html              │
│  - tokens, components        │    │  → auto-nav.css, auto-nav.js  │
│  - @layer reset, tokens,     │    │  → injects rail HTML between  │
│    base, layout, components, │    │    AUTO-NAV-START/END markers │
│    utilities                 │    │  Idempotent. Pure stdlib.     │
└──────────────────────────────┘    └───────────────────────────────┘
                                                    │
                                                    ▼
                                    ┌───────────────────────────────┐
                                    │  site.sh check / push         │
                                    │  → lychee + orphan-check      │
                                    │  → rsync to bigblack via      │
                                    │    Tailscale (optional)       │
                                    └───────────────────────────────┘
```

## File Layout

```
plugins/html-showcase/
├── plugin.json                    Plugin manifest
├── README.md                      User-facing GitHub entry point
├── CLAUDE.md                      ◄── This file (maintainer SSoT)
├── assets/
│   └── showcase.css               CSS kernel (served from jsDelivr)
└── skills/
    ├── setup/
    │   └── SKILL.md               /html-showcase:setup orchestrator
    └── page-template/
        ├── SKILL.md               /html-showcase:page-template
        ├── references/
        │   ├── principles.md      The WHY — 5 + 1 principles
        │   ├── sitemap.md         Filesystem-as-sitemap contract
        │   ├── contributing.md    The HOW — 4 contributor stances
        │   └── publishing.md      The WHERE — bigblack tailnet setup
        ├── scripts/
        │   ├── build-nav.py       Universal sitemap + auto-nav builder
        │   ├── check-orphan-pages.py   Pure-stdlib orphan detector
        │   ├── site.sh            Build + validate + publish wrapper
        │   └── install.sh         One-shot bootstrap into any repo
        └── templates/
            ├── index.html         Site home / page skeleton
            ├── section-index.html Section landing skeleton
            ├── overrides.css.example   Per-site customization sample
            └── lychee.toml        Link-checker config
```

## When to Edit What

| Change                          | Edit                                                                                    |
| ------------------------------- | --------------------------------------------------------------------------------------- |
| Re-theme one page               | The page's `overrides.css`                                                              |
| Add a missing visual component  | `assets/showcase.css` (Stance 3 — affects every page)                                   |
| Change rail behavior or styling | `AUTO_NAV_CSS_BODY` / `AUTO_NAV_JS_BODY` in `build-nav.py`, then bump `--asset-version` |
| Change section ordering rules   | `walk_site()` in `build-nav.py`                                                         |
| Change publish destination      | Env vars (`SITE_BIGBLACK_SSH`, `SITE_BIGBLACK_ROOT`, `SITE_BASE_URL`) — no edit needed  |
| Update one of the principles    | `skills/page-template/references/principles.md`                                         |

## Related Documentation

- [Skill SKILL.md](./skills/page-template/SKILL.md) — full skill instructions
- [principles.md](./skills/page-template/references/principles.md) — design rationale
- [sitemap.md](./skills/page-template/references/sitemap.md) — auto-nav contract
- [publishing.md](./skills/page-template/references/publishing.md) — bigblack tailnet setup
- [contributing.md](./skills/page-template/references/contributing.md) — four contributor stances
