# html-showcase Plugin

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-2-blue.svg)]()
[![Commands](https://img.shields.io/badge/Commands-2-green.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

Sitemap-organized **static HTML mini-sites** with a CDN-served CSS kernel and an auto-discovered, auto-fitting navigation rail. **The filesystem layout IS the navigation graph** — drop HTML files in directories, run one script, and the sitemap + per-page rail rewrite themselves.

> [!NOTE]
> No JS framework. No SSG. No build step beyond `python3 build-nav.py`. The entire pipeline is pure stdlib + a CSS file. Pages render correctly opened directly via `file://` and stay correct after years of evolving content.

## Features

- **Filesystem-as-sitemap** — every subdirectory of the site root with `*.html` becomes a "section"; `YYYY-MM-DD-` slug prefixes auto-sort newest-first
- **Auto-fitting nav rail** — measures the longest unwrapped link via `width: max-content` and opens at "just enough" width; drag to resize, double-click to re-fit, persisted in `localStorage`
- **CSS kernel served from jsDelivr** — `assets/showcase.css` is canonical infrastructure; one push ripples coordinated visual updates across every page using the kernel
- **Idempotent build** — re-running `build-nav.py` with no source changes mutates zero files; safe in CI or pre-commit hooks
- **Tailscale-published by default** — `site.sh push` rsyncs to bigblack via your tailnet (no DNS, no public exposure, no auth UI), with lychee + orphan-page validation as the only gate
- **Self-bootstrapping** — `install.sh` drops the entire pipeline (`build-nav.py`, `check-orphan-pages.py`, `site.sh`) into any repo's `scripts/` dir in one command

## When to Use

Static HTML pages that record structured technical work — audits, commits, metrics, reports, contractor showcases, telemetry views, weekly digests. Anything that benefits from a polished presentation surface with full link provenance and zero hand-maintained navigation.

**Not** for: blog posts, marketing landing pages, interactive web apps.

## Quick Start

```bash
# 1. Bootstrap the pipeline into any repo (idempotent, non-destructive)
PLUGIN=${CLAUDE_PLUGIN_ROOT:-~/.claude/plugins/marketplaces/cc-skills/plugins/html-showcase}
bash "$PLUGIN/skills/page-template/scripts/install.sh" --site contractor-site

# 2. Author HTML files in contractor-site/ and any contractor-site/<slug>/
#    Fill in the {{ PLACEHOLDERS }} in the templates, then build the sitemap:
scripts/site.sh nav contractor-site

# 3. Validate (lychee + orphan-page check)
scripts/site.sh check contractor-site

# 4. (Optional) publish to bigblack on the tailnet
scripts/site.sh push contractor-site

# 5. View
open contractor-site/index.html
```

Or invoke as a slash command from Claude Code:

```
/html-showcase:setup           # bootstrap the pipeline into the current repo
/html-showcase:page-template   # scaffold a new showcase page with the templates
```

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│  Authored HTML — semantic markup, no inline styles                 │
└────────────────────────────────────────────────────────────────────┘
            │                                      │
            ▼                                      ▼
┌──────────────────────────────┐    ┌───────────────────────────────┐
│  showcase.css (kernel)       │    │  build-nav.py walks site root │
│  via jsDelivr CDN            │    │  → site-map.html              │
│  - tokens, components,       │    │  → auto-nav.css, auto-nav.js  │
│    @layer cascade discipline │    │  → injects rail HTML between  │
│  - one knob: --density       │    │    AUTO-NAV-START/END markers │
└──────────────────────────────┘    └───────────────────────────────┘
                                                    │
                                                    ▼
                                    ┌───────────────────────────────┐
                                    │  site.sh check / push         │
                                    │  → lychee + orphan validator  │
                                    │  → rsync to bigblack          │
                                    └───────────────────────────────┘
```

Six load-bearing principles drive the design — see [`skills/page-template/references/principles.md`](./skills/page-template/references/principles.md) for the full rationale.

## Skills

| Skill                                              | Purpose                                                                      |
| -------------------------------------------------- | ---------------------------------------------------------------------------- |
| [`page-template`](./skills/page-template/SKILL.md) | Scaffold a sitemap-organized HTML site (templates, scripts, design contract) |
| [`setup`](./skills/setup/SKILL.md)                 | One-shot install of the pipeline scripts into the current repo               |

## Dependencies

| Tool      | Required for           | Install                                           |
| --------- | ---------------------- | ------------------------------------------------- |
| `python3` | `build-nav.py`         | macOS ships 3.9+; this plugin works on **3.10+**  |
| `lychee`  | link validation        | `brew install lychee` (or `cargo install lychee`) |
| `rsync`   | publishing to bigblack | preinstalled on macOS                             |
| `ssh`     | publishing to bigblack | preinstalled on macOS                             |
| `git`     | repo detection         | preinstalled on macOS                             |

The scripts use **only Python stdlib** — no `pip install` step. Lychee is the only non-built-in tool, and the publishing path (`site.sh push`) is opt-in.

## CDN Versioning

The kernel URL pins to either `@main` (always-latest, used during iteration) or `@v<X.Y.Z>` (immutable tagged release, used for production stability):

```
@main      → always-latest         → use during development; jsDelivr cache flushed automatically on each release
@v<X.Y.Z>  → immutable, tagged     → use for production-stable pages
@<sha>     → immutable, commit-locked → use for forensic-grade pinning
```

Sites bootstrapped via `install.sh` and the `templates/index.html` skeleton pin to `@main` by default.

## Documentation Map

- [CLAUDE.md](./CLAUDE.md) — maintainer SSoT (invariants, architecture, when-to-edit-what)
- [SKILL.md](./skills/page-template/SKILL.md) — user-facing skill instructions
- [`references/principles.md`](./skills/page-template/references/principles.md) — the WHY (5 + 1 design principles)
- [`references/sitemap.md`](./skills/page-template/references/sitemap.md) — filesystem-as-sitemap contract, rail behavior
- [`references/contributing.md`](./skills/page-template/references/contributing.md) — four contributor stances
- [`references/publishing.md`](./skills/page-template/references/publishing.md) — bigblack tailnet publishing setup

## License

MIT — see [LICENSE](../../LICENSE) at the repo root.
