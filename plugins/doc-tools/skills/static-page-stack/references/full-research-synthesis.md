# Full Research Synthesis (2026-04-25, 18 parallel agents) <!-- SSoT-OK: versions below are research-timestamp evidence, not canonical pins -->

This is the comparative analysis backing the recommendations in `SKILL.md`. Original research lives in the project that triggered it: `~/eon/opendeviationbar-patterns/findings/dashboard/spokes/2026-04-25-postmortem/learn/_research-static-page-stack-2026.md`.

## Method

18 parallel research agents, each researching one specific area of the static-page stack. Constraints encoded in every prompt:

- Three aesthetic DNAs: magazine/data-journalism + technical-doc + computational notebook
- Three SVG sources: programmatic charts + hand-authored inline + whiteboard-style
- Explicitly NOT text-source diagrams (Mermaid/Graphviz)

Version numbers below are evidence of currency at research time. They are not canonical pins — install the latest from the upstream URL.

## Per-layer findings

### Authoring framework

**Top: Quarto.** MIT license. Manuscript layout + Closeread extension for scrollytelling. Native Observable Plot integration via OJS cells. Multi-page navigation with sidebar + cross-references. Used in production by Deutsche Bundesbank, Bank for International Settlements, US Geological Survey. Quarto 2 (Rust rewrite) announced for 2026; current 1.x line stable through year-end. Default theme requires custom SCSS investment (~1-2 weeks) to reach magazine quality.

**Strong alternative: Observable Framework.** ISC license. Multi-page static dashboard via file-based routing. Polyglot data loaders (Python/R/JS run at build time). Plot-first. Active maintenance through 2026 (most recent point release in Q1 2026). Risk: Observable Inc layoffs (2023, possibly later) — fork viability is the contingency.

**Strong alternative for cross-linking: Quartz.** MIT, current major v4 line (2024-2026), ~12k stars. TypeScript/JSX, Markdown-native. Bidirectional links + graph view + backlinks panel out of the box. Best fit when forensic-investigation cross-linking is the dominant navigation property.

**Other notable: Jupyter Book 2 / MyST.** BSD-3-Clause. Strong multi-page TOC with `myst.yml`. Status: Alpha (not stable yet) — risk for production at the time of writing.

**Functional but not magazine: Astro Starlight + MDX.** MIT. Functional-docs default theme. ~1-2 weeks of custom CSS to reach magazine parity. Best when MDX component flexibility is the priority.

**VitePress.** MIT. Vue-centric. Powers vuejs.org/vitejs.dev. Default theme plain; custom theme via slot system + CSS variables. Picks: extend default theme rather than replace.

**Manubot.** AGPL 3.0. Manuscripts-as-website with GitHub-hosted Git workflow. Built on Pandoc. Best for collaborative academic content with chain-of-custody requirements.

**The Pudding's svelte-starter.** MIT. Real shippable boilerplate from data-journalism gold standard. Svelte+Vite stack. Closest to magazine-grade out of the box but requires Svelte expertise.

**Avoid: Distill.pub template.** Stopped publishing in 2021. Repo alive (~972 stars) but no funding story. Modern equivalent is Quarto + Closeread.

**Avoid: Idyll-lang.** Last meaningful update Feb 2023. Effectively dormant.

**Avoid: Pollen.** Racket-only ecosystem; niche; minimal community since around 2020.

### Charts (programmatic SVG)

**Top: Observable Plot.** ISC. Cleaner defaults than Vega-Lite. ~95% of bar/line/scatter/heatmap needs. Mike Bostock-led. Stable 0.6.x line at research time, healthy maintenance pace. Native fit with Quarto + Observable Framework.

**Vega-Lite.** BSD-3-Clause. Best for complex specs, dynamic generation, interactive charts. JSON verbosity is the friction.

**Apache ECharts.** Apache 2.0. Wins on polished interactive dashboards (Canvas/SVG hybrid). ~80 KB minified bundle. Better aesthetics than Plot for very-data-heavy dashboards. Steeper config learning curve.

**D3.** GPL-3.0 (note: source-disclosure required if you ship D3 code). 20+ years battle-tested. Use when Plot doesn't cover your case (custom path, force simulation, 100k+ points).

**Pancake (Svelte-native).** MIT. Pure-static, server-side render, zero JS. Maintenance is dormant (last update ~4 years ago at research time) — note risk.

**rough.js / roughViz / chart.xkcd.** MIT. Sketchy programmatic SVG. Use sparingly for "exploratory / uncertainty implied" framing.

**Avoid: visx (React-only), Plotly (~300 KB bundle), Chart.js (canvas, no SVG semantic).**

### Diagrams (whiteboard / sketchy)

**Top: Excalidraw + excalidraw_export CLI.** MIT, recent stable point release (April 2026), mature. CLI options: `Timmmm/excalidraw_export`, `realazthat/excalidraw-brute-export-cli`, `JRJurman/excalidraw-to-svg`. Export light + dark variants, post-process to strip hard-coded colors, wrap in component using `data-theme`.

**tldraw.** Recent v4 line at research time, stable. SVG export ~13% smaller than Excalidraw via DOM-based rendering. **Non-FOSS license**: hobby (watermarked, non-commercial) or **$6,000/year commercial**. tldraw v1.x remains MIT but is legacy. Default to Excalidraw unless tldraw's specific features (interactive embeds, polished hand-drawn aesthetic) justify the cost.

**Penpot.** MPL 2.0. Full design suite, heavier than whiteboard tools.

### CSS / design system

**Top: Open Props.** MIT. Adam Argyle (Google/Chrome Labs). 500+ CSS variable design tokens (color/space/type/shadow/animation). ~4 KB Brotli. Multiple distribution formats (CSS/JS/JSON). Compatible with inline SVG theming via CSS custom properties.

**Modern CSS features that change the game (2025-2026 production-ready):**

- OKLCH colors (~82% support) — generate palettes from a single hue
- Container queries (~92% support) — components responsive to container, not viewport
- `@scope` (late 2025) — CSS scope without BEM
- `light-dark()` function — native light/dark switching
- `text-wrap: pretty/balance` — magazine-grade typography
- View Transitions API (full-page MPA support 2026) — smooth animations between static pages without JS

**Pico.css.** MIT, current v2 line, ~14.8k stars. Classless semantic styling with OKLCH theming. Multiple themes built-in. Trade-off: less granular control than Open Props.

**Water.css / Sakura / NewCSS.** Lighter, classless. Sakura is dual-tone via SASS. NewCSS is terminal/retro aesthetic.

### Typography

**FOSS body fonts (best defaults):** Inter (sans), IBM Plex Serif or Crimson Pro (editorial), Fira Code or Source Code Pro (mono). All elevate to magazine-grade output.

**Variable fonts:** Recursive (5 axes including Casual). Subset to axes you use to manage file size (typical variable font: ~100-200 KB).

**Fluid type scales:** utopia.fyi generates `clamp()` functions eliminating breakpoints.

**Color:** OKLCH is the production standard. Tools: oklch.fyi, oklch.com, Figma OKLCH plugin. Generate palettes by varying L, holding hue+chroma. Store as CSS custom properties: `--color-primary-50` through `--color-primary-900`. Named tokens beat scales.

### Scrollytelling

**Closeread.** Quarto extension, active 2024-2026. Native scrollytelling for Quarto users. Sticky figures + scroll-triggered reveals.

**Scrollama.** ~7 KB, IntersectionObserver-based. Russell Goldenberg (The Pudding). Industry standard primitive when not using Closeread.

**GSAP ScrollTrigger.** Now fully free (Webflow acquisition). ~30 KB. Best for cinematic scrubbing or pin-unpin sequences. Overkill for simple figure swaps.

**Lenis.** ~3 KB smooth scrolling, doesn't break CSS `sticky`. Companion to Scrollama, not replacement.

**Avoid: Idyll-lang.** Dormant.

### Inline SVG composition patterns

**Token propagation:** `<path fill="var(--icon-primary, #000)" d="..."/>`. CSS custom properties propagate INTO inline SVG. Use `currentColor` for single-color icons.

**Accessibility:**

```html
<svg
  role="img"
  aria-labelledby="fig-title"
  aria-describedby="fig-desc"
  viewBox="0 0 24 24"
>
  <title id="fig-title">Architecture diagram: request flow</title>
  <desc id="fig-desc">
    Shows client → API gateway → service mesh with 3 replicas
  </desc>
  <!-- paths -->
</svg>
```

**Symbol/use for shared icons:**

```html
<svg hidden>
  <defs>
    <symbol id="icon-download" viewBox="0 0 24 24">
      <path fill="var(--icon-primary, #000)" d="..." />
    </symbol>
  </defs>
</svg>
<svg role="img" aria-labelledby="ref-dl">
  <use href="#icon-download" />
  <title id="ref-dl">Download</title>
</svg>
```

**Caveat:** `<use>` doesn't grant CSS access to inner `<path>` elements (Shadow DOM boundary). Use CSS variable fallbacks in the symbol definition.

**Optimization:** SVGOMG (browser-based) or SVGO (CLI). 50%+ file reduction.

**Inline vs `<img src=...svg>`:** Inline for token-driven/interactive SVGs; external for reused decorative assets where HTTP/2 caching wins.

## URLs

See `sota-urls.md` for the full link list grouped by layer.
