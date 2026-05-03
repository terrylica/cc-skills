# Principles — why this skill is shaped the way it is

> Read this once before extending the kernel, forking it, or making major
> changes to a page's structure. The class names, file paths, and CDN URLs
> in `SKILL.md` are concrete _instances_ of the principles below. Internalize
> the principles, and you can deviate intelligently from any specific instance
> without breaking the architecture.

## The five load-bearing principles

These are the rules the kernel was built around. Every other decision in the
skill follows from them.

### 1. Single source of truth

Every visual decision lives in exactly one place: the kernel CSS. Colors,
spacing, type, shadows, borders, hover states, gradients — all defined once.

**Why it matters.** A design system fragments the moment a second source
appears. If `--brand-primary` is `#2563eb` in the kernel and `bg-blue-600`
in some HTML utility class, you now have two truths and your future self
will desync them. The kernel doesn't permit utility-class soup precisely
because that's how desync starts.

**How to detect a violation.** If you find yourself writing `style="..."`
or `<style>...</style>` inside HTML, you've violated SSoT. The fix is to
add the pattern to the kernel (if it's recurring) or to put the override
in `overrides.css` (if it's per-page).

### 2. Semantic over atomic

Class names describe what an element _is_, not what it _looks like_.
`<div class="metric-card">`, never `<div class="rounded-lg shadow-md p-6 border bg-white">`.

**Why it matters.** Atomic class strings turn HTML into a liability for
both humans and AI agents. To change "all metric cards lift on hover by 4px
instead of 2px," you'd have to grep for the right combination of utility
classes across every page; with semantic names you edit `.metric-card:hover`
once. Semantic markup also compresses prompts: an LLM editing a 30-line HTML
fragment with semantic class names has full context; the same fragment with
30 atomic classes per element is mostly noise.

**How to detect a violation.** If a class name describes a property
(`flex-row`, `text-blue-600`, `mt-4`), it's atomic. The kernel's utility
layer is intentionally tiny (`.stack`, `.text-mono`, `.text-muted`,
`.visually-hidden`) — anything beyond that should be a component class.

### 3. Token-driven

Every concrete value (color, spacing, font size, shadow, border radius)
flows from a CSS custom property defined at `:root`. No magic numbers in
component CSS.

**Why it matters.** A design system is a network of relationships, not a
list of values. The kernel exposes two universal multipliers (`--density`,
`--font-scale`) that propagate through ~40 derived tokens. Changing one
ripples in a coordinated way; changing 40 is a refactor.

**The contract.** When you add a new component, never write `padding: 14px`.
Write `padding: var(--card-pad)` (or compose from `--space-N`). When you
need a color, never write `#1d4ed8`. Write `var(--brand-primary-strong)`.
If the token you need doesn't exist, add it to the `tokens` layer first.

### 4. Cascade discipline

`@layer reset, tokens, base, layout, components, utilities` is declared once
at the top of the kernel. Every rule lives in exactly one layer. Layers
later in the order win specificity ties regardless of selector strength
or source order.

**Why it matters.** Without `@layer`, CSS specificity is a probabilistic
mess: a class selector beats a tag selector beats an attribute selector,
unless `!important` is involved, unless a later rule overrides an earlier
one with the same specificity, etc. With `@layer`, you read the layer
order at the top and KNOW which rule wins. Edits are predictable.

**Where overrides live.** Per-page overrides in `overrides.css` are
_outside_ the kernel's `@layer` declarations, which means they always win
over the kernel — a fact users rely on. If you want kernel changes to win
over user overrides, that's a different architecture (the user would need
`!important`, which we don't want).

### 5. No hidden state

No JavaScript. No inline `<style>`. No `style=""` attributes. No theme
toggles that depend on cookies or localStorage. No fonts loaded outside
the kernel. No images that change layout when missing.

**Why it matters.** A page that depends on hidden state can't be
screenshotted, archived, link-checked, or rendered in any context that
doesn't replay that state. A showcase page is _evidence_ — it has to read
the same to a human reviewer in 6 months as it does to you right now. JS
breaks that. Inline styles break that. Cookie-driven themes break that.

**The escape valve.** If you genuinely need a behavior that requires JS
(say, a sortable table), put it in a SECOND file (`enhancements.js`) and
make sure the page is still readable and accurate without it. The kernel
itself stays pure HTML+CSS.

## AI-collaboration patterns (why this design is LLM-friendly)

The kernel was designed with the working assumption that an AI agent will
spend more time reading and editing it than any human. Specific patterns
follow:

- **Predictable token names beat invented ones.** `--blue-7` is a name an
  AI can predict from `--blue-6` without context. `$brandColorMain` is
  one name in 10,000 it might invent. The kernel uses Open Props' naming
  conventions because they are systematic; a model that sees one knows
  twenty.

- **Single-file edits review better than multi-file edits.** Every
  component lives in `assets/showcase.css`; every per-page tweak in
  `overrides.css`. A diff for a kernel change is one file, one section.
  A diff for re-theming a page is one file, ~5 lines. Reviewers (human or
  AI) can audit changes without holding multiple files in their head.

- **Semantic class names compress prompts.** A model summarizing a page
  with `<article class="metric-card">` retains the meaning. The same
  page with `<article class="rounded-lg shadow-md p-6 border bg-white">`
  exhausts attention budget on layout noise. Semantic naming is the
  highest-leverage prompt-compression technique in HTML/CSS work.

- **`@layer` makes specificity predictable.** When an AI edits the
  kernel and adds a rule, it doesn't have to compute selector specificity
  in its head. The layer order tells it whether the new rule will win.
  Predictability beats cleverness.

- **Dark-mode-only beats `light-dark()` for showcase pages.** A page
  whose appearance depends on the _viewer's_ OS settings can't be reviewed
  by screenshot consistently. The kernel sets `color-scheme: dark` to
  pin the look. If you need light-mode showcase pages, fork the kernel and
  build a light variant — don't auto-switch based on `prefers-color-scheme`.

## Why a CDN, not a local copy

A page that links to a copy of the kernel fixes its appearance to whatever
existed when it was scaffolded. Kernel improvements never reach it. By
linking to jsDelivr (a CDN), every page reflects the latest kernel within
the chosen version pin (`@main` for live, `@vN.N.N` for stability), so a
single push to the kernel ripples coordinated visual updates across every
page in every repo. That's the whole point — the kernel is genuinely
shared infrastructure, not a snippet.

## Why marketplace.json, not per-plugin plugin.json

The cc-skills marketplace centralizes versioning in one file. Per-plugin
`plugin.json` files exist for plugin discovery but aren't synced. New
plugins get a single entry in `.claude-plugin/marketplace.json`; the entry
is bumped (along with all 36 others) every time semantic-release runs.

**The implication for forks:** if you fork cc-skills to publish your own
kernel, you inherit this single-file architecture. Adding a new plugin
means one entry in marketplace.json, period. No webhook, no manual sync.
