---
name: setup
description: Bootstrap the html-showcase pipeline into the current repo. Copies build-nav.py, check-orphan-pages.py, and site.sh into <repo>/scripts/, ensures **/.published.json is gitignored, and (optionally) seeds a starter site directory. Idempotent and non-destructive. Use when the user invokes `/html-showcase:setup`, asks to "install the showcase scripts", "bootstrap a sitemap-organized site", or wants to publish HTML pages to bigblack via Tailscale from a fresh repo.
allowed-tools: Read, Bash, AskUserQuestion
argument-hint: "[--site <name>] [--force] [--repo <path>]"
disable-model-invocation: false
---

# /html-showcase:setup — install the pipeline into a repo

> **Self-Evolving Skill**: If a step here is wrong or a workaround was needed, fix this file immediately, don't defer. Only update for real, reproducible issues.

## What this skill does

This skill is a thin orchestrator around `scripts/install.sh`, the shipped one-shot bootstrap. It:

1. Runs a **preflight check** (no writes) to see what's already installed
2. Reports the diff between the canonical pipeline and the current repo
3. Asks the user whether to proceed (unless they passed `--yes`)
4. Runs the install with the same flags the user requested

After running, the target repo has:

```
<repo>/
├── scripts/
│   ├── build-nav.py             ◄── universal sitemap + auto-nav builder
│   ├── check-orphan-pages.py    ◄── pure-stdlib orphan detector
│   └── site.sh                  ◄── nav + validate + push wrapper
├── .gitignore                   ◄── now includes **/.published.json
└── (optional) <site>/           ◄── seeded with index.html, overrides.css, lychee.toml
```

`install.sh` itself is **not** copied into the target repo — it stays in the plugin and is the canonical install entry point.

## When this skill fires

- The user types `/html-showcase:setup` (with or without flags).
- The user asks to "install the showcase scripts", "bootstrap a sitemap-organized site", "set up html-showcase in this repo".
- The user wants to publish a static HTML site to bigblack via Tailscale and is starting from a fresh repo.

It does **not** fire for:

- Authoring a new page (that's `/html-showcase:page-template`)
- Editing the kernel CSS (no setup needed; just edit `assets/showcase.css`)

## How to invoke (the model's procedure)

The skill follows the four-phase setup pattern used by other cc-skills plugins (`/itp:setup`, `/itp-hooks:setup`, `/asciinema-tools:setup`).

### Phase 1 — Preflight

Resolve the install script and run `--check` to see what's missing without writing anything.

```bash
INSTALL="${CLAUDE_PLUGIN_ROOT}/skills/page-template/scripts/install.sh"
[[ -f "$INSTALL" ]] || INSTALL="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/html-showcase/skills/page-template/scripts/install.sh"

bash "$INSTALL" --check
```

Exit codes:

- `0` — everything already installed; report success and stop.
- `10` — at least one item missing or out-of-date; proceed to phase 2.
- non-zero (other) — script error; report and stop.

### Phase 2 — Present findings + gate

Show the user what's missing (the `✗` lines from the preflight output), then ask via `AskUserQuestion`:

> "Install the html-showcase pipeline into this repo? This copies 3 scripts into `<repo>/scripts/` and adds one line to `.gitignore`. Idempotent and safe to re-run."
>
> Options:
>
> - **Yes** — proceed with install
> - **Yes, with starter site** — also seed `<repo>/contractor-site/` (or another name) with `index.html`, `overrides.css`, `lychee.toml`
> - **No** — abort

If the user passed `--yes` (or equivalent), skip the gate.

### Phase 3 — Install (only if approved)

```bash
# Plain install
bash "$INSTALL"

# With starter site
bash "$INSTALL" --site "${SITE_NAME:-contractor-site}"

# Force overwrite (only if the user explicitly asks)
bash "$INSTALL" --force
```

### Phase 4 — Verify + summarize

Re-run `bash "$INSTALL" --check` and confirm exit code 0. Print a short next-steps summary:

```
✓ Pipeline installed. Next steps:

  1. Author HTML files in <site-dir>/ and any <site-dir>/<section-slug>/
     (each subdir of the site root with *.html becomes a "section").

  2. Build the sitemap + auto-nav rail:
       scripts/site.sh nav <site-dir>

  3. Validate (lychee + orphan-page check):
       scripts/site.sh check <site-dir>

  4. (Optional) Publish to bigblack via Tailscale:
       scripts/site.sh push <site-dir>

For authoring guidance:  /html-showcase:page-template
For the architecture:    plugins/html-showcase/CLAUDE.md
```

## Dependencies the user needs

Confirmed by the `--check` output:

- `python3` ≥ 3.10 (preinstalled on macOS, but verify with `command -v python3`)
- `lychee` (only for `site.sh check` / `push`) — `brew install lychee`
- `rsync`, `ssh`, `git` — preinstalled on macOS

If `lychee` is missing, the install still succeeds (it's only used at validation time). The model should mention it in the next-steps summary so the user installs it before running `scripts/site.sh check`.

## Hard rules

- **Never run install without preflight.** The preflight is what makes the skill non-destructive.
- **Always gate destructive operations on `AskUserQuestion`** unless the user passed `--yes`. The skill's contract is "I won't surprise you."
- **Pass through `--repo <path>` when the user names a different target.** Default is `git rev-parse --show-toplevel || pwd`, which is usually right.
- **Don't re-implement the install logic in the skill.** All file copying lives in `install.sh`. The skill is an orchestrator, not a re-implementation.

## Post-Execution Reflection

0. **Locate yourself.** This SKILL.md lives at `plugins/html-showcase/skills/setup/SKILL.md`.
1. **What failed?** If `install.sh --check` reported wrong state, fix the script. If a phase missed a user expectation, fix this SKILL.md.
2. **What worked?** Promote any successful patterns into `references/` or back into the skill body.
3. **What drifted?** Keep this skill's command list and the install.sh `--help` output aligned.
4. **Log it.** Add a short note to the plugin's CLAUDE.md if you changed an invariant.

Do NOT defer. The next invocation inherits whatever you leave behind.
