# Release Workflow Guide

Comprehensive guide for releasing cc-skills marketplace plugins.

## Quick Start

```bash
# Check release status
moon run repo:release-status

# Dry run (preview)
moon run repo:release-dry

# Full release (seven phases)
moon run repo:release-full
```

## Release Workflow — Seven Phases, Five Standalone Tasks

Two different counts appear in this repo and **both are correct, because they count different things**. `tasks/release/full` is, verbatim, "the seven-phase release orchestrator that wraps preflight + presync + version + sync + verify + chronicle + postflight" — that is the pipeline `moon run repo:release-full` actually executes. But only **five** of those seven are individually runnable moon tasks, which is why `moon.yml` labels them "Phase 1" through "Phase 5". Pre-sync and chronicle exist only inside the orchestrator script; they have no standalone moon task, though like every phase they remain plain scripts and run identically as `bash tasks/release/presync` and `bash tasks/release/chronicle`.

| Phase      | Standalone command                           | Description                                                                                      |
| ---------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Preflight  | `moon run repo:release-preflight` (Phase 1)  | Validate clean working dir, GH_TOKEN, plugin manifests, releasable conventional commits          |
| Pre-sync   | orchestrator-only, no standalone task        | Mirror current main HEAD to ~/.claude marketplace clone so the live env reflects pending changes |
| Version    | `moon run repo:release-version` (Phase 2)    | Run semantic-release (bump + CHANGELOG + git tag + GitHub release)                               |
| Sync       | `moon run repo:release-sync` (Phase 3)       | Update the marketplace clone and plugin cache, sync commands, remove pre-v20.2.3 hook copies     |
| Verify     | `moon run repo:release-verify` (Phase 4)     | Confirm git tag, GitHub release, marketplace, hook files, runtime artifact consistency           |
| Chronicle  | orchestrator-only, no standalone task        | Session-chronicle bundle (private repos only)                                                    |
| Postflight | `moon run repo:release-postflight` (Phase 5) | Reset lockfile drift, confirm clean working dir, confirm all commits pushed                      |

## Available moon Tasks

```bash
moon query tasks                   # List all tasks
moon run repo:release-status       # Current version info
moon run repo:release-preflight    # Validate before release (Phase 1)
moon run repo:release-version      # semantic-release only (Phase 2)
moon run repo:release-sync         # Marketplace + cache sync (Phase 3)
moon run repo:release-verify       # Verify release artifacts (Phase 4)
moon run repo:release-postflight   # Git state validation (Phase 5)
moon run repo:release-full         # Complete seven-phase workflow
moon run repo:release-dry          # Dry-run preview
bash tasks/release/hooks           # Install hooks only (script only — no moon task)
moon run repo:release-clean        # Clean old cache versions
bash tasks/release/augment --tag <tag> --notes-file <path>   # Replace a GitHub Release body with gated extensive notes
```

Every phase is a plain script under `tasks/`, so `bash tasks/release/<phase>` runs it identically with no moon involved — the moon task is a thin wrapper, which is what makes the orchestrator swappable. Args after `--` and the `ITER*` env-var knobs documented below both pass through the wrapper unchanged.

### Extensive release notes

Release notes must carry BOTH a narrative paragraph (the _why_) and a point-form list
(the _what_) — doctrine SSoT `~/.claude/release-notes-doctrine-CLAUDE.md`, enforced by the
`itp-hooks` release-notes-extensiveness-guard. Two mechanisms surface the substance:

- **Automatic (in-generator)**: `release.config.cjs` carries a body-preserving
  `writerOpts` so the full multi-paragraph commit **body** appears under each entry (the
  default Angular preset renders subject-only). Pinned by `test/release-config-body-surfacing.test.ts`.
- **Manual / cross-repo**: `bash tasks/release/augment --tag <tag> --notes-file <path>`
  edits the GitHub Release through the same extensiveness gate (`scripts/augment-release-notes.mjs`).

<!-- SSoT-OK: the release numbers below are historical incident references, not version pins -->

#### Five ways the body used to arrive mangled (all fixed 2026-08-19)

All five sat BETWEEN the extensiveness guard and GitHub, so the guard passed bodies that
rendered wrong. The PreToolUse guard could not see any of them either: it covers
`gh release create`, and semantic-release publishes through the GitHub API. Pinned by
`scripts/release-config-body-reflow.test.ts`, which asserts against **rendered** output —
a transform-only test passes while every release still looks wrong.

- **Silent truncation.** `conventional-commits-parser`'s default `fieldPattern` is
  `/^-(.*?)-$/`, which a line of dashes matches. A setext heading underline or a
  horizontal rule diverts every remaining body line into a field no template emits.
  The v27.0.1 incident: 66 body lines in, 8 published. `fieldPattern` is now a
  never-matching regex on **both** `commit-analyzer` and `release-notes-generator` —
  they must mirror.
- **Body swallowed by its bullet.** Handlebars strips the trailing newline of a line
  holding a lone block tag, so the template's blank line collapsed and GFM read the body
  as a lazy continuation of the `* subject` bullet. The template now carries two blank
  lines so one survives.
- **Hard-wrapped prose.** Commit bodies are correctly wrapped at ~72 columns; GFM turns
  every newline inside a paragraph into a literal `<br>`. The transform reflows via
  `scripts/reflow-release-notes.ts` — imported, never reimplemented, so it cannot drift
  from `repo:release-augment`. That module must stay free of top-level `await`, or Node refuses
  the `require()` and the transform silently falls back to the raw body.
- **Aligned blocks flattened.** CommonMark reads an indented-by-under-four block as
  ordinary prose, so the reflow joined hand-aligned tables into one line. Indented lines
  holding a run of 2+ interior spaces are now preserved.
- **Angle brackets silently eaten.** GFM interprets raw HTML, so `Vec<T>` published as
  "Vec" — the type parameter _deleted_, with no warning. `<details>` opened a collapsible
  section that swallowed everything after it; `a<b and c>d` became bold. Every
  angle-bracket occurrence in the last 400 commit bodies of this repo is prose or a CLI
  placeholder (`<uuid>`, `<path>`, `<Command,Handler>`, `<verify|probe|bench>`), so
  `scripts/escape-commit-body-html.ts` now escapes `<` outside code spans, fences and
  markdown autolinks. Only `<` — escaping `>` would corrupt the `->` in aligned tables.
  Escaping runs BEFORE the reflow, because the reflow treats a line starting with `<` as a
  standalone HTML block and would otherwise leave that line hard-wrapped.
  **If you ever want real HTML in a release body, put it in a notes file and use
  `repo:release-augment`; a commit message is plain text.**

A sixth, in the guard itself: it judged the **longest** paragraph rather than asking
whether **any** paragraph qualified, so a long aligned table masked a real narrative and
blocked correct notes. Fixed in `release-notes-extensiveness-patterns.ts`.

## Commit Conventions

Every commit type releases (marketplace constraint). `feat` bumps the minor version, a breaking change the major, everything else the patch:

| Type        | Release | Release Notes |
| ----------- | ------- | ------------- |
| `feat:`     | minor   | Features      |
| `fix:`      | patch   | Bug Fixes     |
| `docs:`     | patch   | Not shown     |
| `chore:`    | patch   | Not shown     |
| `refactor:` | patch   | Not shown     |

**Tip**: Use `fix(docs):` for documentation changes that should appear in release notes. Subjects: 50 characters as the target, 72 as the hard cap; the body carries the detail.

## Post-Release Automation

The Sync and Verify phases:

1. **Update the marketplace clone** at `~/.claude/plugins/marketplaces/cc-skills` to the new tag.
2. **Refresh the plugin cache** so the next session loads the new version.
3. **Run `scripts/sync-hooks-to-settings.sh`**, which removes cc-skills hook entries that installs older than v20.2.3 copied into `~/.claude/settings.json`. It never adds any: plugin hooks load from each plugin's `hooks/hooks.json`. On a clean machine it touches nothing.
4. **Run `scripts/sync-commands-to-settings.sh`** and keep the newest `CC_SKILLS_BACKUP_RETENTION` (default 5) snapshots of `~/.claude/commands/`.
5. **Verify** the tag, the GitHub release, the cache and the hook files.

## Manual Release (npm)

Runs semantic-release only: no presync, sync, verify or postflight. Prefer `moon run repo:release-full`.

```bash
npm run release:dry   # Dry run
npm run release       # Production release
```

## Troubleshooting

### Release blocked by preflight

```bash
moon run repo:release-preflight            # See which check failed
GH_TOKEN="$(gh auth token)" moon run repo:release-preflight   # GH_TOKEN not set (release-full derives it itself)
bun scripts/validate-plugins.mjs           # Plugin validation
```

**Dirty working directory:** commit the work, or move it to its own worktree — but do not then run the release FROM a worktree (next section). Do not reach for a bare `git stash`: the stash stack is shared by every worktree and session on this clone, so a bare stash or pop can take someone else's changes. If you must, use `git stash push -u -m "<unique-tag>"` and restore by SHA with `git stash apply <sha>`.

### Never release from a git worktree of a checkout someone is using

semantic-release syncs the release branch with `git fetch --tags --update-head-ok <url> +refs/heads/main:refs/heads/main`, a forced update. A worktree shares `refs/heads/main` with the main checkout, so running any release task (even `release-dry`) from a worktree moves the main checkout's branch to `origin/main` while its index and files stay put. Its `git status` then shows the whole difference as staged changes, and the next commit there silently reverts everything upstream. Seen 2026-10-10: 376 files, undone with `git update-ref refs/heads/main <previous-sha>` (find it with `git reflog show refs/heads/main`).

Release from the main checkout when it is clean, or from a dedicated fresh clone (next section) — never from a worktree.

### Push refused by the privacy gate for commits you did not touch

semantic-release pushes with `--tags`, which sends **every local tag**. The 2026-10-07 history scrub deleted all tags from the public remote, but an older clone still holds its pre-scrub tags (including local `archive/*` bookmarks), and they point at commits carrying scrubbed identifiers. The privacy gate refuses the push, correctly, and the release stops after creating its local commit.

Check with `git ls-remote --tags origin` against `git tag | wc -l`. Either remove the stale local tags (destructive to local bookmarks — the clone owner's call), or release from a fresh clone:

```bash
git clone git@github.com-terrylica:terrylica/cc-skills.git ../cc-skills-release && cd ../cc-skills-release
git tag vX.Y.Z <sha of the last "chore(release): X.Y.Z" commit>   # only if that tag is missing on origin
bash scripts/install-hooks.sh && moon run repo:commits-install-hook && bun install --frozen-lockfile
moon run repo:release-full
```

Without the last-release tag, semantic-release would restart the version at 1.0.0. The privacy gate is a config-based hook in the global gitconfig, so it guards a fresh clone too.

### Hooks not firing after release

Restart Claude Code, then type `/hooks`: it lists every configured hook with its source, and cc-skills hooks show as coming from a plugin. A cc-skills hook listed under user settings is a pre-v20.2.3 leftover; `./scripts/sync-hooks-to-settings.sh` removes it.

### Cache not updated

```bash
moon run repo:release-clean   # Clean old cache versions
moon run repo:release-sync    # Re-run the sync phase
```

## Diagnostics and Knobs

Environment variables read by the release and test scripts. All are optional, and the defaults keep output unchanged. Names before #224 began with an iteration number (`ITER134_…`); those still work and are listed under [Deprecated names](#deprecated-names).

### Timing

| Variable                                                           | Effect                                                                                                                         | Default            |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ | ------------------ |
| `PREFLIGHT_TIMING_PROFILE=1`                                       | Per-check elapsed time in `repo:release-preflight`, a total, and a slowest-checks ranking                                      | off                |
| `PREFLIGHT_TIMING_TOP_N`                          | Length of that preflight ranking                                                                                               | 5                  |
| `RELEASE_TIMING_PROFILE=1`                                         | Per-phase elapsed time for `repo:release-full`, a total, and a slowest-phases ranking                                          | off                |
| `RELEASE_TIMING_TOP_N`                  | Length of the release-phase ranking                                                                                            | 5                  |
| `RELEASE_SUCCESSCMD_TOP_N`                | Length of the post-release `successCmd` step ranking (with `RELEASE_TIMING_PROFILE=1`)                                         | 5                  |
| `MARKETPLACE_HOOK_REGRESSION_SUITE_TOP_N_SLOWEST_TESTS_TO_DISPLAY` | Adds a slowest-tests ranking to `repo:test-hooks`                                                                              | unset (no ranking) |
| `SEMREL_TIMING_PARSER_TOP_N`          | Ranking length for `scripts/iter144-release-step-timing-parser.py`, which attributes semantic-release time per debug namespace | 10                 |
| `RELEASE_VARIANCE_RUNS`                               | Captures for `scripts/iter147-release-timing-variance-harness.py` (p50/p95/stddev per namespace; at least 2)                   | 5                  |
| `RELEASE_VARIANCE_REPLAY=1`             | Re-analyse the harness's existing `/tmp` logs instead of capturing                                                             | off                |

Compare timings across several runs, not one: the release is dominated by network round trips whose run-to-run spread can exceed the effect being measured. The variance harness flags namespaces whose stddev/p50 exceeds 0.20.

### Parallelism

| Variable                                                              | Effect                                                                                                 | Default                  |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ------------------------ |
| `MARKETPLACE_HOOK_REGRESSION_PARALLEL_LANES`                          | Worker count for `repo:test-hooks`                                                                     | `clamp(ncpu − 4, 4, 12)` |
| `PREFLIGHT_AUDIT_PARALLEL_LANES`                              | Worker count for preflight's audit fan-out                                                             | `clamp(ncpu − 4, 4, 12)` |
| `PREFLIGHT_AUDIT_SERIAL=1`                   | Run those audits one at a time (diagnosis only)                                                        | off                      |
| `MARKETPLACE_HOOK_REGRESSION_SUITE_PARENT_INVOCATION_RECURSION_GUARD` | Set by the suite runner itself so tests that call the runner skip their nested tier. Not for operators | —                        |

### Test tiers and fixtures

| Variable                                     | Effect                                                                                         | Default              |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------- | -------------------- |
| `TEST_PREFLIGHT_INTEGRATION=1`   | Adds the slow preflight-integration tier to `test-iter130-131-bottleneck-ranking-summaries.sh` | off                  |
| `TEST_SERIAL_MODE_INTEGRATION=1` | Adds the serial-mode tier to `test-iter134-parallel-preflight-audit-fan-out.sh`                | off                  |
| `AUDIT_REPO_ROOT_OVERRIDE`                   | Repository root an audit scans, for running it against a synthetic fixture                     | the audit's own repo |
| `COMMITS_REPO_ROOT`                 | Repository root for `tasks/commits/pending-release`                                            | the current repo     |

### Deprecated names

Each knob's old name is still read when the new one is unset, and using it prints one line on stderr naming the replacement. Every shell script, including the `commit-msg` hook (installed repositories run it in place through an exec shim), resolves both through `cc_knob` in `scripts/lib/env-knob.sh`; the two Python scripts carry the same rule inline. The aliases go when #226 retires them.

| Name | Deprecated alias |
| --- | --- |
| `PREFLIGHT_TIMING_TOP_N` | `ITER130_TOP_N_SLOWEST_CHECKS_TO_DISPLAY` |
| `RELEASE_TIMING_TOP_N` | `ITER139_TOP_N_SLOWEST_RELEASE_PHASES_TO_DISPLAY` |
| `RELEASE_SUCCESSCMD_TOP_N` | `ITER140_TOP_N_SLOWEST_SUCCESSCMD_STEPS_TO_DISPLAY` |
| `SEMREL_TIMING_PARSER_TOP_N` | `ITER144_TOP_N_SLOWEST_PLUGIN_LIFECYCLE_STEPS_TO_DISPLAY` |
| `RELEASE_VARIANCE_RUNS` | `ITER147_VARIANCE_PROFILE_RUN_COUNT` |
| `RELEASE_VARIANCE_REPLAY` | `ITER147_VARIANCE_PROFILE_REPLAY_FROM_EXISTING_LOGS` |
| `PREFLIGHT_AUDIT_PARALLEL_LANES` | `ITER134_PREFLIGHT_AUDIT_PARALLEL_LANES` |
| `PREFLIGHT_AUDIT_SERIAL` | `ITER134_DISABLE_PREFLIGHT_AUDIT_PARALLELIZATION` |
| `TEST_PREFLIGHT_INTEGRATION` | `ITER132_RUN_PREFLIGHT_INTEGRATION_TIER` |
| `TEST_SERIAL_MODE_INTEGRATION` | `ITER135_RUN_SERIAL_MODE_INTEGRATION_TIER` |
| `COMMITS_REPO_ROOT` | `ITER165_REPO_ROOT_OVERRIDE` |
| `RELEASE_HISTORY_COUNT` | `ITER150_COMMIT_COUNT_TO_DISPLAY` |
| `RELEASE_HISTORY_WRAP` | `ITER150_SOFT_WRAP_COLUMN_WIDTH` |
| `RELEASE_HISTORY_INDENT` | `ITER150_CONTINUATION_INDENT` |
| `COMMITS_HEALTH_WINDOW` | `ITER152_COMMIT_COUNT_TO_ANALYZE` |
| `COMMITS_SUBJECT_HARD_CAP` | `ITER152_SUBJECT_HARD_CAP_THRESHOLD_CHARS` |
| `COMMITS_SUBJECT_TARGET` | `ITER152_SUBJECT_HARD_TARGET_THRESHOLD_CHARS` |
| `COMMITS_HEALTH_BAR_WIDTH` | `ITER152_HISTOGRAM_BAR_WIDTH` |
| `COMMITS_HEALTH_LONGEST_COUNT` | `ITER152_WORST_OFFENDER_CALLOUT_COUNT` |
| `COMMITS_HOOK_FAIL_MODE` | `ITER157_COMMIT_MSG_HOOK_FAIL_MODE_ON_ADVISOR_NOT_FOUND` |
| `COMMITS_HOOK_CC_SKILLS_PATH` | `ITER157_COMMIT_MSG_HOOK_CC_SKILLS_REPO_PATH_OVERRIDE` |
| `PRECOMMIT_MANIFEST_E2E_TRIALS` | `ITER159_VALIDATION_TRIAL_COUNT_PER_SUBJECT_VARIANT` |
| `COMMITS_DOCTOR_CC_SKILLS_ROOT` | `ITER160_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH_OVERRIDE` |

### Release speed (semantic-release)

semantic-release verifies push access with a real `git push --dry-run` on every run (the `semantic-release:get-git-auth-url` debug namespace), and the release config cannot skip it. Two opt-ins reuse one SSH connection for it instead:

- `RELEASE_SSH_MULTIPLEXING_ENABLED=1 moon run repo:release-full` sets `GIT_SSH_COMMAND` with `ControlMaster` for that run only; `~/.ssh/config` is not touched.
- `scripts/iter146-github-ssh-controlmaster-setup.sh` adds a persistent `ControlMaster` block for `github.com` to `~/.ssh/config`, and refuses if a `Host github.com` block already exists.

`scripts/iter148-ssh-multiplexing-speedup-check.sh` measures both conditions with the variance harness.

On a fresh clone, run `scripts/iter145-fix-empty-release-notes-refs.sh` once. It backfills the semantic-release notes refs that a few old tags lack; without them semantic-release logs a swallowed `JSON.parse` error per tag on every run. The refs are local and are not pushed.

## Conventional-Commits Toolkit

`bash tasks/commits/_default` prints the in-terminal cheatsheet. Every argument-taking task is declared `command:` with `shell: false` in `moon.yml`, so `moon run repo:<task> -- ARGS` and `bash tasks/<path> ARGS` are equivalent. `tasks/commits/advise` takes its subject after a `--`, and `tasks/release/history` its git-log range, so through moon there are two separators: `moon run repo:commits-advise -- --json -- "feat: foo"`.

| Tool                                                                 | What it does                                                                                                                                                                                                                                                                                                                    |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `moon run repo:release-history`                                      | `git log` with long subjects soft-wrapped (`RELEASE_HISTORY_COUNT`, default 10; `RELEASE_HISTORY_WRAP`, default 80; `RELEASE_HISTORY_INDENT`, continuation indent, default 8)                                                                                                                                                                                         |
| `moon run repo:commits-health` (`--json`)                            | Five panels for the last N commits against the N before: readable view, subject-length histogram, longest subjects, type counts, trend verdict (IMPROVING / REGRESSING / STABLE / MIXED)                                                                                                                                        |
| `bash tasks/commits/advise -- "<subject>"`                           | Classifies a subject before you commit. `--json` for machine output, `--strict` exits non-zero on a compound prefix or a missing type, `--message-file <path>` reads a full message including a `BREAKING CHANGE` footer; with no argument on a TTY it reads `.git/COMMIT_EDITMSG`. Also previews the bump and the next version |
| `moon run repo:commits-pending-release` (`--json`)                   | The next release version and the commit that decides it, across every commit since the last tag                                                                                                                                                                                                                                 |
| `moon run repo:commits-status` (`--json`)                            | Self-check of the toolkit's scripts, libraries and end-to-end chain; `COMMITS_DOCTOR_CC_SKILLS_ROOT` points it at another cc-skills checkout                                                                                                                                                                                                                                                             |
| `moon run repo:commits-install-hook` / `repo:commits-uninstall-hook` | Installs or removes a `commit-msg` hook running the advisor in `--strict` mode. Fails open if the advisor is missing; `COMMITS_HOOK_FAIL_MODE=closed` makes it fail closed. The hook finds cc-skills through `COMMITS_HOOK_CC_SKILLS_PATH`, then `git config cc-skills.repo-path`, then `~/eon/cc-skills`                                                                                                                      |
| `.pre-commit-hooks.yaml`                                             | Hook id `cc-skills-commits-advise-commit-msg` for repositories using the [pre-commit](https://pre-commit.com) framework (`pre-commit install --hook-type commit-msg`); `scripts/iter159-pre-commit-manifest-e2e-check.sh` exercises it end to end, `PRECOMMIT_MANIFEST_E2E_TRIALS` trials per subject (default 1)                                                                                                                                                           |
| `bash tasks/commits/conventional-conformance.sh`                     | The preflight's conventional-commits check on its own; subjects over 72 characters are reported but never block a release                                                                                                                                                                                                       |
| `moon run repo:commits-perf-baseline`                                | Wall-clock baseline for the toolkit's own scripts                                                                                                                                                                                                                                                                               |

`repo:commits-health` tunables: `COMMITS_HEALTH_WINDOW` (10), `COMMITS_SUBJECT_HARD_CAP` (72), `COMMITS_SUBJECT_TARGET` (50), `COMMITS_HEALTH_BAR_WIDTH` (20), `COMMITS_HEALTH_LONGEST_COUNT` (3). JSON output from these tools escapes strings through one shared library, `scripts/lib/iter155-json-string-escape.sh`.

## Preflight Maintenance: Reading Audit Counts

`tasks/release/preflight` reads each audit's count from the audit's summary line. Two rules keep that from breaking the gate:

**Rename both sides together.** When an audit's summary wording changes, update `tasks/release/preflight` and the audit's `tasks/tests/test-audit-*.sh` in the same commit. A wording the preflight no longer matches yields an empty count.

**Extract with a reader that drains its input.** The preflight runs under `set -euo pipefail`. Use:

```bash
VAR=$( { grep -oE 'PATTERN' file || true; } | grep -oE '[0-9]+$' | awk 'NR==1' || echo 0)
echo "  ✓ Result: ${VAR:-0}"
```

`{ … || true; }` keeps a missing summary line from failing the pipeline, and `${VAR:-0}` reports 0 rather than an empty string. Never end such a pipeline with `head -1`: if `head` closes the pipe while the producer is still writing, the producer exits 141, `pipefail` fails the pipeline, `|| echo 0` runs as well, and `VAR` holds the real count followed by a second line, `0`. `awk 'NR==1'` reads everything, so the producer always finishes.

## Key Files

| File                                   | Purpose                                                               |
| -------------------------------------- | --------------------------------------------------------------------- |
| `release.config.cjs`                   | semantic-release configuration (release rules, body-preserving notes) |
| `tasks/release/*`                      | Release phase scripts, wrapped by the `repo:release-*` moon tasks     |
| `scripts/release-preflight.sh`         | Preflight run by semantic-release's `verifyConditions`                |
| `scripts/sync-hooks-to-settings.sh`    | Removes pre-v20.2.3 cc-skills hook copies from `settings.json`        |
| `scripts/sync-commands-to-settings.sh` | Syncs plugin skills to `~/.claude/commands/`                          |
| `scripts/lib/backup-retention.sh`      | `CC_SKILLS_BACKUP_RETENTION` for both sync scripts                    |
| `scripts/sync-versions.mjs`            | Version alignment across files                                        |

## Related Documentation

- [Version Management ADR](/docs/adr/2025-12-05-centralized-version-management.md)
