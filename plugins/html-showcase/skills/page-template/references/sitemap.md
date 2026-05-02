# Sitemap — the filesystem IS the navigation

> Read this when you're about to add a section, change a slug, hand-edit
> the rail, or wonder why the nav rerenders the way it does. The
> filesystem-as-sitemap principle is what lets a multi-page mini-site
> grow without anyone ever maintaining a hand-written nav.

## The contract

A site this skill produces has exactly one navigation source of truth:
the directory layout under `<site-root>/`. The script
`scripts/build-nav.py` walks that layout and derives:

- a master `site-map.html` at the root,
- the per-page nav rail (injected into every HTML page),
- two asset files (`auto-nav.css`, `auto-nav.js`) sitting at the root.

You author **HTML files in directories**. The script handles everything
else.

```
<site-root>/
  index.html              ← optional but recommended (site home)
  overrides.css           ← optional per-site customization
  auto-nav.css            ← generated; do not hand-edit
  auto-nav.js             ← generated; do not hand-edit
  site-map.html           ← generated; do not hand-edit
  <section-slug>/         ← any subdir with at least one *.html is a "section"
    index.html            ← section landing (optional but recommended)
    page-a.html
    page-b.html
  <YYYY-MM-DD-other>/     ← date-prefixed sections sort newest-first
    ...
```

## What the script discovers

`build-nav.py --root <site-root>` runs in three phases:

1. **Walk.** Find every `*.html` directly in `<site-root>` (the home + any
   misc top-level pages) and every `*.html` inside each subdirectory of
   `<site-root>`. Subdirectories starting with `.` or `_` are skipped
   (so `_drafts/`, `.git/`, `_research/` etc. stay invisible). Generated
   files (`site-map.html`) are excluded from the walk.

2. **Parse.** For each page, extract the `<title>` and first `<h1>`. The
   `<h1>` (when present) is what shows in the rail; the `<title>` is the
   fallback. This means the page itself is the source of truth for its
   own label — no separate metadata file.

3. **Render + inject.** Build a `site-map.html` listing every section
   and page, then write a self-contained nav rail HTML fragment into
   every page between the `<!-- AUTO-NAV-START -->` and
   `<!-- AUTO-NAV-END -->` markers. If the markers are missing, the
   script inserts them right after `<body>`.

Re-runs are **idempotent**. Running the script with no source changes
mutates zero files (the print-out says "Injected nav into 0 page(s)").

## Section ordering

The slug pattern `YYYY-MM-DD-<rest>` is detected automatically:

- If **any** section has a date prefix, **all** sections sort by date
  newest-first (sections without a date sort to the bottom).
- If **no** sections have date prefixes, sections sort alphabetically by
  slug.

Within a section, pages always sort: `index.html` first, then everything
else alphabetically.

This matches the way most teams instinctively organize a site that grows
over time (date-prefixed for journals/audits/post-mortems, plain slugs
for evergreen content). If you need a different order — manual ordering,
priority groups, etc. — that's a Stance 3 change to `build-nav.py`'s
`walk_site()` function.

## What the rail contains

Every page (except `site-map.html`, which gets its own custom render)
gets the same three-section rail:

1. **Site shortcuts** — Home + Site map.
2. **Current section** — the section's name + every sibling page (with
   the current page highlighted).
3. **Other sections** — Prev / Next neighbors in the section ordering.

Top-level pages (pages directly in `<site-root>`, not in a subdirectory)
get the home-page version of the rail: just the Site shortcuts. They
have no "section siblings" because they aren't in a section.

## The marker convention

```html
<!-- AUTO-NAV-START -->
…rail HTML, regenerated on every nav build…
<!-- AUTO-NAV-END -->
```

The markers are HTML comments, so they are invisible to readers and
inert to browsers. The script uses them as a regex anchor: replace
everything between them on each run.

**Don't hand-edit between the markers.** Your edit will survive exactly
until the next `build-nav.py` run. If you want a structural change to
the rail itself, edit `AUTO_NAV_CSS_BODY` or `render_rail()` in
`build-nav.py` and re-run.

The asset links in `<head>`:

```html
<link rel="stylesheet" id="auto-nav-css" href="auto-nav.css?v=1" />
<script id="auto-nav-js" src="auto-nav.js?v=1" defer></script>
```

are also rewritten on every run (the `id="auto-nav-…"` attributes are
how the script finds them). If you change the rail's CSS body inside
`build-nav.py`, bump `--asset-version` so caches see new URLs.

## Working with the rail

### Add a page to an existing section

```bash
cp templates/index.html <site-root>/<section-slug>/<new-page>.html
# fill in {{ placeholders }}
python3 scripts/build-nav.py --root <site-root>
```

The new page appears in:

- `<section-slug>/`'s rail (it's a sibling of the existing pages),
- the master `site-map.html`,
- every other section's "Other sections" cross-link if `<section-slug>`
  is now a Prev/Next neighbor of that section.

### Add a new section

```bash
mkdir <site-root>/<new-section-slug>
cp templates/section-index.html <site-root>/<new-section-slug>/index.html
cp templates/index.html <site-root>/<new-section-slug>/<page>.html
python3 scripts/build-nav.py --root <site-root>
```

Sections without `index.html` work fine — `build-nav.py` will treat the
first alphabetically-sorted page as the section's entry point in the
"Other sections" links. But a section landing page is the single best
place to frame the section's purpose for readers, and the
`section-index.html` template gives you that.

### Rename a section

Renaming changes the slug. Update any HTML that linked into the old
section by hand (lychee will catch the broken links), then re-run
`build-nav.py` so the rail and site-map reflect the new slug.

### Move a page between sections

Just `mv` the file. Re-run `build-nav.py`. The rail rewrites itself.
Lychee will catch any external links that referenced the old path.

## Why filesystem-as-sitemap

A handful of alternatives exist, and the trade-off matrix matters:

| Approach                                      | Pros                                                   | Cons                                                                                                  |
| --------------------------------------------- | ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| **Hand-written nav in every page**            | Maximum control                                        | Drifts the moment you add a page; one of the most reliable sources of stale links                     |
| **Hand-written `_nav.json` consumed by JS**   | Single edit point                                      | Adds a JS dependency; breaks `file://`; has to be re-generated for static hosts; Principle 5 violated |
| **Hand-written `_sections.toml` + a builder** | Sections in author-defined order                       | Two SSoTs (filesystem + manifest); easy to desync when files move                                     |
| **Filesystem-as-sitemap (this skill)**        | Zero hand-written nav; layout = nav; idempotent builds | Section order is a function of slug naming, not free                                                  |

The cost of "section order is a function of slug naming" is small in
practice — a date prefix (`YYYY-MM-DD-`) buys you chronological order
for free, and slug ordering buys you alphabetical for free. Anything
else is a custom sort, which lives in `build-nav.py` rather than in a
manifest file.

## Theming the rail

The rail's appearance lives entirely in `AUTO_NAV_CSS_BODY` inside
`build-nav.py`. It's intentionally **not** part of the showcase kernel
because:

- The rail is fixed-position infrastructure, not page content; mixing it
  with kernel components would muddy the kernel's role.
- A repo can adopt the rail without adopting the kernel CSS (e.g., a
  legacy site with its own design system can drop in `build-nav.py` for
  navigation only).
- The rail uses dark/light values appropriate for an overlay surface,
  which sometimes diverges from the page's content surface. Keeping
  them separate avoids cascade fights.

If you need the rail in a different palette, edit `AUTO_NAV_CSS_BODY`
and bump `--asset-version`. If you find yourself wanting the rail to
inherit kernel tokens, that's a deliberate cross-cutting change — open a
PR and discuss whether the rail should become a kernel component.

## When NOT to use the rail

The rail is the right shape for **multi-page mini-sites** (2 to ~50
pages, organized in 1 to ~10 sections). It's the wrong shape for:

- **A single-page showcase.** No nav is needed; remove the markers and
  the link/script tags. The kernel still works without the rail.
- **A 500-page documentation site.** At that scale you want a real
  static-site generator (Zola, Hugo, MkDocs, Astro) with proper search,
  collections, and TOC. The auto-nav is a deliberately simple tool.
- **A page that must stay layout-pristine for screenshot/archival.**
  The rail occupies left margin space; if the page is meant to be
  pixel-comparable to a previous render, omit the rail.

For these edge cases, you can author HTML pages with the kernel and
without the markers; `build-nav.py` simply skips pages that don't have
the markers and never inserts them (the insertion uses the `<body>` tag
as anchor, but only if the markers don't already exist). To opt a page
out, remove the markers from the file and add a comment so a future
maintainer knows it's intentional.

## Implementation map (for fixers)

Inside `scripts/build-nav.py`:

| Concern                      | Function / constant                     |
| ---------------------------- | --------------------------------------- |
| Constants & marker strings   | top of file                             |
| Section/page discovery       | `walk_site()`                           |
| Per-page rail HTML           | `render_rail()`                         |
| Site-map page HTML           | `render_site_map()`                     |
| Idempotent injection         | `inject_into_page()` + `inject_block()` |
| Asset link rewriting in head | `ensure_nav_assets()`                   |
| Rail CSS body                | `AUTO_NAV_CSS_BODY`                     |
| Rail JS body                 | `AUTO_NAV_JS_BODY`                      |

Edit one place per concern. The script is small enough to read end-to-end
in five minutes; don't split it without a reason.
