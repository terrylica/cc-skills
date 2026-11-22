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
- [interactive-json-form](./skills/interactive-json-form/SKILL.md) — single-file HTML form whose responses round-trip as JSON

## Commands

| Command                        | Purpose                                                                              |
| ------------------------------ | ------------------------------------------------------------------------------------ |
| `/html-showcase:setup`         | Bootstrap a repo: install `scripts/build-nav.py`, `check-orphan-pages.py`, `site.sh` |
| `/html-showcase:page-template` | Scaffold a new HTML showcase page or multi-page site                                 |

Either skill can be invoked without the other; setup is the one-shot
bootstrapper, page-template is the authoring guide.

## Dependencies

| Tool      | Required for             | Install                                           |
| --------- | ------------------------ | ------------------------------------------------- |
| `python3` | `build-nav.py`           | macOS ships 3.9+; this plugin works on **3.10+**  |
| `lychee`  | link validation          | `brew install lychee` (or `cargo install lychee`) |
| `rsync`   | publishing to <gpu-host> | preinstalled on macOS                             |
| `ssh`     | publishing to <gpu-host> | preinstalled on macOS                             |
| `git`     | repo detection           | preinstalled on macOS                             |

The scripts use **only Python stdlib** — no `pip install` step. Lychee is the
only non-built-in tool, and the publishing path (`site.sh push`) is opt-in.

## Critical Invariants

One line each; the rationale and the full ordering rules are in [sitemap.md](./skills/page-template/references/sitemap.md) and [principles.md](./skills/page-template/references/principles.md).

- **The kernel is the SSoT for every visual decision:** no inline `<style>`, no `style=""`, no utility-class soup; HTML composes kernel components and never invents them.
- **The CSS kernel is CDN-served, not copied:** `assets/showcase.css` loads from jsDelivr (`cdn.jsdelivr.net/gh/terrylica/cc-skills@main/...`), so one kernel push updates every page in every repo; a local copy freezes a page's look.
- **The nav rail is generated:** everything between `<!-- AUTO-NAV-START -->` and `<!-- AUTO-NAV-END -->` is rewritten by `build-nav.py`; its `auto-nav.{css,js}` travel with the site directory, not the CDN.
- **Ordering:** dated sections newest-first; inside a section, `index.html`, then `<!-- nav-pin -->` pages, then `index_iter_<N>_…` by descending N, then other pages by birthtime (never mtime), then nested pages.
- **The rail and site map are always dark** (`color-scheme: dark`) whatever the page's own theme; pages may theme themselves freely.
- **Cache-bust only with `?v=N`:** bump `--asset-version` in `build-nav.py` when the rail's CSS or JS changes.
- **Prev/Next are bare `[` / `]`,** and the handler must keep returning early on any modifier or when focus is in an editable element.
- **The rail owns the body gutter** (`padding-left: 28px`/`40px`, `padding-right: 28px`, `!important`); a page's own body padding is overridden on purpose.

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
                                    │  → rsync to <gpu-host> via      │
                                    │    Tailscale (optional)       │
                                    └───────────────────────────────┘
```

## File Layout

`assets/showcase.css` is the CSS kernel (served from jsDelivr); each skill keeps its own `references/`, `scripts/` and `templates/`. `git ls-files plugins/html-showcase` is the authoritative list.

## When to Edit What

| Change                          | Edit                                                                                    |
| ------------------------------- | --------------------------------------------------------------------------------------- |
| Re-theme one page               | The page's `overrides.css`                                                              |
| Add a missing visual component  | `assets/showcase.css` (Stance 3 — affects every page)                                   |
| Change rail behavior or styling | `AUTO_NAV_CSS_BODY` / `AUTO_NAV_JS_BODY` in `build-nav.py`, then bump `--asset-version` |
| Change section ordering rules   | `walk_site()` in `build-nav.py`                                                         |
| Change publish destination      | Env vars (`SITE_SSH_HOST`, `SITE_REMOTE_ROOT`, `SITE_BASE_URL`) — no edit needed        |
| Update one of the principles    | `skills/page-template/references/principles.md`                                         |

## Related Documentation

- [Skill SKILL.md](./skills/page-template/SKILL.md) — full skill instructions
- [principles.md](./skills/page-template/references/principles.md) — design rationale
- [sitemap.md](./skills/page-template/references/sitemap.md) — auto-nav contract
- [publishing.md](./skills/page-template/references/publishing.md) — <gpu-host> tailnet setup
- [contributing.md](./skills/page-template/references/contributing.md) — four contributor stances
