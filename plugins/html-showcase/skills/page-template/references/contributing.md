<!-- SSoT-OK: example version strings (e.g. @v<X.Y.Z>) are illustrative documentation
     of the publishing workflow, not actual published versions of this plugin. -->

# Contributing — four stances for using and extending the kernel

> Pick the stance that matches your task. Each stance has a different
> blast radius and a different review path. The architecture supports all
> four equally — choose based on what you actually need, not on what feels
> "more committed."

## At a glance

| #   | Stance          | Edits what                                  | Affects whom                     | Best for                                                        |
| --- | --------------- | ------------------------------------------- | -------------------------------- | --------------------------------------------------------------- |
| 1   | **Consumer**    | One HTML file in your repo                  | Just your page                   | Shipping a single showcase page quickly                         |
| 2   | **Customizer**  | One `overrides.css` next to your HTML       | Just your page                   | Re-themed page (different brand color, density) without forking |
| 3   | **Contributor** | The kernel CSS in `terrylica/cc-skills`     | Every page everywhere            | Adding a missing component or fixing a bug                      |
| 4   | **Publisher**   | A fork of `cc-skills` under your own GitHub | Pages that pin to _your_ CDN URL | A team or org wanting their own kernel canon                    |

The four stances are stable across all four — same files, same conventions,
same review surface. What changes is the URL pin in your HTML's `<link>`
and where the kernel commit lands.

---

## Stance 1 — Consumer

**You want:** a new HTML showcase page that looks like the others. You are
not customizing the kernel and you don't need any per-page color tweaks.

**Workflow:**

```bash
# 1. Copy the templates into your destination
DEST=/path/to/where/your-page/lives
mkdir -p "$DEST"
PLUGIN=${CLAUDE_PLUGIN_ROOT:-~/.claude/plugins/marketplaces/cc-skills/plugins/html-showcase}
cp "$PLUGIN/skills/page-template/templates/index.html" "$DEST/"
cp "$PLUGIN/skills/page-template/templates/lychee.toml" "$DEST/"

# 2. Fill in the {{ PLACEHOLDERS }} in index.html with real content.
#    Keep the structure; replace only text and links.

# 3. Open the page (no server needed)
open "$DEST/index.html"

# 4. Verify integrity
lychee --config "$DEST/lychee.toml" "$DEST/**/*.html"
python3 "$PLUGIN/skills/page-template/scripts/check-orphan-pages.py" "$DEST/"
```

**What URL your page links to:** `@main` (always-latest) during the kernel's
iteration phase, `@v<X.Y.Z>` (immutable tag) once the kernel is stable.

**Mental model:** you are reading from a shared library. You don't ship
the library; you pin to a version of it.

---

## Stance 2 — Customizer

**You want:** the kernel's components and rhythm, but with different brand
colors, a tighter density, or a different font for ONE page (not the whole
shared kernel).

**Workflow:**

```bash
# 1. Same as Consumer, plus copy the override example
DEST=/path/to/your-page
PLUGIN=${CLAUDE_PLUGIN_ROOT:-~/.claude/plugins/marketplaces/cc-skills/plugins/html-showcase}
cp "$PLUGIN/skills/page-template/templates/overrides.css.example" "$DEST/overrides.css"

# 2. Edit overrides.css — uncomment the variables you want to override.
#    Override file is tiny: just a :root {} block of CSS variables.
```

**Sample override:**

```css
:root {
  --brand-primary: #14b8a6; /* teal instead of blue */
  --brand-primary-deep: #0f766e;
  --density: 0.75; /* extra tight */
  --font-scale: 0.92; /* smaller body type */
}
```

The order of `<link>` tags in your HTML matters: kernel first, overrides
last, so your overrides win the cascade.

```html
<link
  rel="stylesheet"
  href="https://cdn.jsdelivr.net/gh/terrylica/cc-skills@main/plugins/html-showcase/assets/showcase.css"
/>
<link rel="stylesheet" href="overrides.css" />
```

**What's overridable:** every CSS variable defined under `:root` in the
kernel's `tokens` layer. Open the kernel CSS and search for `--`; that's
your full vocabulary. Common overrides:

| Variable                                                                | Effect                          |
| ----------------------------------------------------------------------- | ------------------------------- |
| `--density`                                                             | Spacing scale (lower = tighter) |
| `--font-scale`                                                          | Body type size                  |
| `--brand-primary`, `--brand-accent`, `--brand-amber`, `--brand-emerald` | Brand colors                    |
| `--surface-page`, `--text-headline`, `--text-body`                      | Surfaces and text               |
| `--shell-max`                                                           | Page width cap                  |
| `--font-display`, `--font-text`, `--font-mono-stack`                    | Type families                   |

**What's NOT overridable from `overrides.css`:** layout structure, component
shapes, animations. Those need to be Stance 3 (kernel edit) — by design,
because changing them on one page only is usually a smell.

**Mental model:** you are tweaking a knob, not modifying the machine.

---

## Stance 3 — Contributor (PR upstream to terrylica/cc-skills)

**You want:** a missing component (a `.timeline` for chronological events,
a `.testimonial-card` for quotes, etc.), a fixed bug, or a refined token.
The change should benefit every page that uses the kernel.

**Workflow:**

```bash
# 1. Clone or update your local copy of cc-skills
cd ~/eon/cc-skills    # or wherever your clone lives
git pull origin main
git checkout -b feat/html-showcase-add-timeline-component

# 2. Edit the kernel
$EDITOR plugins/html-showcase/assets/showcase.css

# 3. Test against an existing page that uses @main (or use ?v=$(date +%s) for cache-bust)
mise run release:cdn-purge   # forces jsDelivr to re-fetch from GitHub

# 4. Commit, push, open PR
git add plugins/html-showcase/assets/showcase.css
git commit -m "feat(html-showcase): add .timeline component"
git push -u origin feat/html-showcase-add-timeline-component
gh pr create --title "feat(html-showcase): add .timeline component" \
             --body "Adds .timeline + .timeline-item to the components layer..."
```

**What to add when extending the kernel:**

- A new component goes in the `components` `@layer`. Use a semantic class
  name (`.timeline`, not `.tl-grid`).
- All concrete values must reference existing tokens (`var(--space-N)`,
  `var(--brand-primary)`). If you need a new token, add it to the `tokens`
  layer FIRST.
- If the component has variants (e.g., `--success`, `--warning`), use BEM
  modifier syntax (`.timeline-item--success`) — matches the existing
  vocabulary.
- Update the "Component vocabulary" table in `SKILL.md` so future users
  know the new class exists.

**Review checklist** (mentally, before opening PR):

- Does the component follow Principle 1 (single SSoT)? Yes if its styles
  live entirely in the kernel.
- Does it follow Principle 2 (semantic over atomic)? Yes if the class
  name describes WHAT it is, not HOW it looks.
- Does it follow Principle 3 (token-driven)? Yes if every value references
  a token.
- Does it follow Principle 4 (cascade discipline)? Yes if it's in the right
  `@layer`.
- Does it follow Principle 5 (no hidden state)? Yes if it works without JS.

If all five are yes, the change is in the spirit of the kernel.

**What semantic-release does after merge:** the next `mise run release:full`
on `main` (typically run by the maintainer) bumps the marketplace version,
auto-purges the jsDelivr cache for `@main`, and smoke-tests the new tagged
URL. Pages pinned to `@main` see your component within seconds. Pages
pinned to `@v<X.Y.Z>` see it after a manual re-pin.

---

## Stance 4 — Publisher (your own kernel from your own fork)

**You want:** your team or org has its own brand, conventions, components,
or copyright requirements that differ from terrylica's. You publish your
own kernel from your own GitHub, and your team's pages link to your URL.

**Workflow:**

```bash
# 1. Fork cc-skills on GitHub (use your username/org, e.g. acme-corp/cc-skills)
gh repo fork terrylica/cc-skills --clone --remote --org acme-corp

# 2. Edit the kernel to match your brand
cd ~/eon/cc-skills    # your fork
$EDITOR plugins/html-showcase/assets/showcase.css

# 3. Commit and push to your fork
git add plugins/html-showcase/assets/showcase.css
git commit -m "feat(html-showcase): adopt acme brand tokens"
git push origin main
```

**Your team's CDN URL is automatically:**

```
https://cdn.jsdelivr.net/gh/acme-corp/cc-skills@main/plugins/html-showcase/assets/showcase.css
```

(swap `acme-corp` for your GitHub org/username; jsDelivr serves any public
GitHub repo without registration).

**Update your team's HTML pages** to link your fork's URL instead of
`terrylica/cc-skills`. Every showcase page across your org now reflects
your kernel.

**Pull upstream improvements** when you want them:

```bash
git remote add upstream https://github.com/terrylica/cc-skills.git
git fetch upstream
git merge upstream/main      # or rebase, your call
# Resolve conflicts in plugins/html-showcase/assets/showcase.css if any
git push origin main
```

**Optional: cut your own tagged releases** so your team's pages can pin
to `@v<X.Y.Z>` for production stability:

```bash
mise run release:full        # the cc-skills release flow works in your fork unchanged
```

This will bump _your_ fork's marketplace.json and create a tag in _your_
GitHub. Your CDN URLs at `@v<X.Y.Z>` then become immutable for your team.

**Mental model:** you are running your own copy of the shared
infrastructure. The relationship to upstream is voluntary; you can pull
improvements or diverge entirely.

---

## Cross-stance rules (true regardless of which path you take)

- **No inline CSS.** Even when customizing, the override goes in
  `overrides.css`, not `<style>` blocks or `style=""` attrs.
- **HTML never invents components.** If you need a new component, that's
  Stance 3 (kernel edit). HTML composing existing components is fine;
  inventing new visual patterns inline is not.
- **Pin URLs deliberately.** `@main` for active iteration (you accept that
  pages may shift). `@v<X.Y.Z>` for production stability (pages frozen
  forever). `@<commit-sha>` for forensic immutability (rarely needed).
- **Lychee + orphan-page check are required.** Both gates exist in the
  template; don't skip them. They are the only assurance that the page is
  reproducible from its sources.
