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
  Pages within a section sort `index.html` first, then alphabetical.
- **Cache-bust via `?v=N` only.** When the rail's CSS or JS body inside
  `build-nav.py` changes, bump `--asset-version` (default in the script).
  The browser sees a new URL and re-fetches; we don't rely on
  `Cache-Control` headers.

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
