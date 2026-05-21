# Release Workflow Guide

Comprehensive guide for releasing cc-skills marketplace plugins.

## Quick Start

```bash
# Check release status
mise run release:status

# Dry run (preview)
mise run release:dry

# Full release (6 phases)
mise run release:full
```

## 6-Phase Release Workflow

The `release:full` task runs all six phases in sequence (matches the canonical task description in `.mise/tasks/release/full`).

| Phase      | Command                       | Description                                                                              |
| ---------- | ----------------------------- | ---------------------------------------------------------------------------------------- |
| Preflight  | `mise run release:preflight`  | Validate clean working dir, GH_TOKEN, plugin manifests, releasable conventional commits  |
| Pre-sync   | `mise run release:presync`    | Mirror current main HEAD to ~/.claude marketplace clone so the live env reflects pending |
| Version    | `mise run release:version`    | Run semantic-release (bump + CHANGELOG + git tag + GitHub release)                       |
| Sync       | `mise run release:sync`       | Update marketplace repo, sync hooks/commands to settings.json, populate plugin cache     |
| Verify     | `mise run release:verify`     | Confirm git tag, GitHub release, marketplace, hook files, runtime artifact consistency   |
| Postflight | `mise run release:postflight` | Reset lockfile drift, confirm clean working dir, confirm all commits pushed              |

## Available mise Tasks

```bash
mise tasks                    # List all tasks
mise run release              # Show help
mise run release:status       # Current version info
mise run release:preflight    # Validate before release
mise run release:version      # semantic-release only
mise run release:sync         # Sync hooks + cache
mise run release:verify       # Verify release artifacts
mise run release:postflight   # Git state validation
mise run release:full         # Complete 6-phase workflow
mise run release:dry          # Dry-run preview
mise run release:hooks        # Install hooks only
mise run release:clean        # Clean old cache versions
```

## Commit Conventions

All commit types trigger patch releases (marketplace constraint):

| Type        | Release | Release Notes |
| ----------- | ------- | ------------- |
| `feat:`     | minor   | Features      |
| `fix:`      | patch   | Bug Fixes     |
| `docs:`     | patch   | Not shown     |
| `chore:`    | patch   | Not shown     |
| `refactor:` | patch   | Not shown     |

**Tip**: Use `fix(docs):` for documentation changes that should appear in release notes.

## Post-Release Automation

The release workflow automatically:

1. **Updates marketplace repo** - `~/.claude/plugins/marketplaces/cc-skills`
2. **Syncs hooks** - Merges all `hooks.json` files to `~/.claude/settings.json`
3. **Triggers plugin update** - Refreshes plugin cache
4. **Verifies artifacts** - Confirms tag, release, cache presence

## Manual Release (npm)

```bash
# Dry run
npm run release:dry

# Production release
npm run release
```

## Troubleshooting

### Release blocked by preflight

```bash
# Check specific issue
mise run release:preflight

# Common fixes:
git stash                    # Dirty working directory
gh auth login                # GitHub auth expired
bun scripts/validate-plugins.mjs  # Plugin validation
```

### Hooks not synced after release

```bash
# Manual sync
./scripts/sync-hooks-to-settings.sh

# Restart Claude Code for hooks to take effect
```

### Cache not updated

```bash
# Clean old versions
mise run release:clean

# Force re-sync
mise run release:sync
```

<!-- SSoT-OK: the following Phase-2-bottleneck section references HISTORICAL
     release-tag names + forensic-finding tag IDs as immutable identifiers,
     not the current cc-skills version (which lives in package.json /
     plugin.json as the SSoT). Version-guard escape hatch per the iter-107
     marker convention. The 5 tag IDs documented below are the load-bearing
     forensic signature of iter-145's notes-backfill fix. -->

## Phase 2 (semantic-release) Internal Bottleneck Breakdown — iter-144/145/146

The release pipeline's **Phase 2 (`mise run release:version`, which runs semantic-release)** consumes ~30s of the typical ~45s release wall-clock (67%). Iter-144 instrumentation (`scripts/iter144-...py`) parses semantic-release's `DEBUG=semantic-release:*` stderr output to attribute cumulative milliseconds to each `semantic-release:<namespace>` subsystem, surfacing where the time actually goes.

### How to measure

```bash
DEBUG=semantic-release:* npx semantic-release --dry-run --no-ci 2> /tmp/semrel-debug.log
python3 scripts/iter144-semantic-release-plugin-lifecycle-step-timing-instrumentation-via-debug-namespace-stderr-output-parser-emitting-top-n-slowest-bottleneck-ranking-with-cumulative-elapsed-milliseconds-summed-per-plugin-step.py /tmp/semrel-debug.log
```

Operator-tunable Top-N count: set `ITER144_TOP_N_SLOWEST_PLUGIN_LIFECYCLE_STEPS_TO_DISPLAY=N` (default 10). The parser emits TWO ranking dimensions:

1. **`per debug-namespace`** (ACCURATE): every executed code path has its own namespace, no marker-based misattribution. This is the actionable target for further optimization.
2. **`per plugin/lifecycle-step`** (LOADING-PHASE-ONLY): based on `options-for` markers in the debug log. Misattributes post-loading execution to the last loaded step (typically `@semantic-release/exec/fail`). Use dimension 1 for execution-phase attribution.

### Known bottlenecks (iter-144 empirical findings — cc-skills @ 882 git tags, M-series mac)

| Rank | Subsystem                           | ms    | What it does                                                          | Iter     |
| ---- | ----------------------------------- | ----- | --------------------------------------------------------------------- | -------- |
| 1    | `semantic-release:get-git-auth-url` | ~1700 | One `git push --dry-run --no-verify` round-trip to verify push access | iter-146 |
| 2    | `semantic-release:get-tags`         | ~2300 | Walk all 882 tags + read all 877 sibling notes refs                   | iter-145 |
| 3    | `semantic-release:config`           | ~140  | Load `.releaserc.yml` + plugin config resolution                      | —        |
| 4    | `semantic-release:plugins`          | ~16   | Plugin loading + verifyConditions invocation                          | —        |
| 5    | `semantic-release:git`              | ~15   | Internal git utility calls                                            | —        |
| 6    | `semantic-release:get-commits`      | ~11   | List commits since last tag                                           | —        |

### Iter-145 forensic finding (FIXED)

Iter-144 surfaced **5 silent `JSON.parse` SyntaxError stack traces per release**, swallowed by the `catch (error) { debug(error); }` block at `semantic-release/lib/git.js:346`. Root cause: 5 historical tags (the v4.x + v5.1.x cohort cataloged in `scripts/iter145-...sh`) lacked attached notes in `refs/notes/semantic-release-*`. The `%N` format placeholder returned empty string for those tags; `line.trim().split("\t")` produced a single-element array; destructuring yielded `notePart = undefined`; `JSON.parse(undefined)` coerced to `JSON.parse("undefined")` which threw `"undefined" is not valid JSON`.

Iter-145 fixed by backfilling canonical `{"channels":[null]}` notes attached to each tag's COMMIT (not tag object — annotated-tag-aware `tag^{commit}` dereferencing required). Verification: post-fix forensic count is 0.

Re-run `scripts/iter145-fix-malformed-empty-semantic-release-notes-refs-...sh` on any new cc-skills clone to re-apply the local-only fix (notes refs are not pushed to remote in current config).

### Iter-146 finding: `get-git-auth-url`'s `verifyAuth` algorithm

`node_modules/semantic-release/lib/get-git-auth-url.js` line 91-93 ALWAYS runs `verifyAuth(repositoryUrl, branch, {cwd, env})` first, regardless of any token env vars. `verifyAuth` executes:

```bash
git push --dry-run --no-verify <repositoryUrl> HEAD:<branch>
```

This is a real network round-trip to GitHub doing SSH key exchange or HTTPS+TLS+token-handshake. ~1.7s per call on a warm-DNS connection from a residential US-west link. There is no documented `--skip-auth-verify` flag (semantic-release#2053 has been open since 2021 requesting this). The only operator-side leverage is to make the round-trip faster.

### Iter-146 optional optimization: SSH ControlMaster connection multiplexing

OpenSSH ControlMaster persists an authenticated SSH session for a configurable TTL. Once primed, subsequent SSH operations to the same host reuse the persistent connection, skipping key exchange (~1.5s saved per call).

Operator opt-in setup: run `scripts/iter146-configure-ssh-controlmaster-for-github-com-...sh` (idempotent, backs up `~/.ssh/config`, scoped to `Host github.com` only). After applying, the next release's `verifyAuth` cost should drop from ~1.7s to ~100-200ms per call.

**This is a per-developer-machine optimization** — not pushed to the repo, not enforced for collaborators. The setup script is provided as documentation + automation but operators must consciously opt in (modifies `~/.ssh/config`).

### Iter-147 complementary optimization: env-var-scoped SSH multiplexing (no `~/.ssh/config` modification required)

Iter-146's setup script refuses to modify `~/.ssh/config` when a pre-existing `Host github.com` block is detected from another source (e.g., operators with `IdentityFile` pins for anti-key-leak defense). Iter-147 ships a complementary, non-invasive lever for those operators:

```bash
# Enable env-var-scoped SSH ControlMaster for THIS release run only:
RELEASE_SSH_MULTIPLEXING_ENABLED=1 mise run release:full
```

The release orchestrator exports `GIT_SSH_COMMAND="ssh -o ControlMaster=auto -o ControlPath=~/.ssh/controlmasters/%r@%h:%p -o ControlPersist=10m"` for the duration of the pipeline only, idempotently creates `~/.ssh/controlmasters/` with mode `0700`, and lets the process tree inherit the env var. Differences from iter-146:

| Property                                       | Iter-146 (`~/.ssh/config` modification) | Iter-147 (`GIT_SSH_COMMAND` env var)    |
| ---------------------------------------------- | --------------------------------------- | --------------------------------------- |
| Persistence                                    | Permanent across all SSH operations     | Scoped to one `release:full` invocation |
| Operator config touched                        | Yes (`~/.ssh/config` appended)          | No (only `~/.ssh/controlmasters/` dir)  |
| Conflict with existing `Host github.com` block | Setup script refuses to modify          | Bypasses entirely — config untouched    |
| Speedup target                                 | Same (`verifyAuth` 1.7s → ~100-200ms)   | Same                                    |
| Reversibility                                  | Remove block from `~/.ssh/config`       | Unset env var (no state to undo)        |

Both paths target the same `semantic-release:get-git-auth-url` bottleneck. Use iter-147's env-var path when your existing `~/.ssh/config` has `Host github.com` directives you don't want auto-modified.

### Iter-147 variance-characterization harness (prevents single-sample-variance traps)

The per-release wall-clock distribution is dominated by SSH-handshake and GitHub-API round-trip noise with standard deviation that can exceed the perf-delta of any single optimization. Single-sample BEFORE/AFTER comparisons (one measurement of the old version vs. one measurement of the new) routinely return misleading conclusions — both spurious "regressions" and spurious "speedups". To prevent future iter-NNN proposals from chasing these phantoms, iter-147 ships a back-to-back N-run capture-and-percentile harness:

```bash
# Default 5 back-to-back dry-run captures, per-namespace p50/p95/mean/stddev/min/max/range:
uv run --python 3.13 scripts/iter147-empirical-n-run-variance-characterization-harness-for-semantic-release-namespace-timings-via-iter144-parser-emitting-p50-p95-mean-stddev-min-max-range.py

# Custom run count via ITER147_VARIANCE_PROFILE_RUN_COUNT (must be at least 2 — variance undefined for n=1):
ITER147_VARIANCE_PROFILE_RUN_COUNT=10 uv run --python 3.13 scripts/iter147-...py

# Replay existing /tmp/iter147-variance-profile-run-{i}.log without re-capturing (fast re-analysis):
ITER147_VARIANCE_PROFILE_REPLAY_FROM_EXISTING_LOGS=1 uv run --python 3.13 scripts/iter147-...py
```

Output format includes a "variance-flag" column marking namespaces whose stddev/p50 ratio exceeds **0.20** — these are the namespaces where single-sample comparisons are unreliable, and any optimization targeting them must demonstrate distribution-level improvement (p50 or p95 shift across N samples), not point-sample improvement.

**Gotcha — working directory cleanliness affects namespace coverage**: `npx semantic-release --dry-run` runs `scripts/release-preflight.sh` in `verifyConditions`, which aborts on dirty `git status --porcelain`. When preflight aborts, downstream namespaces like `semantic-release:get-tags` never execute and won't appear in the distribution table. Capture against a clean working directory for full namespace cohort.

### Iter-148 empirical validation of the SSH multiplexing claim — measured 3.30x speedup (not conjectural 10-15x)

The iter-146 setup script docstring originally claimed "~1.7s → ~100-200ms (10-15x speedup)" sourced from OpenSSH community docs on warm-handshake reuse. **That claim was conjectural** — never measured on this machine, against this release pipeline, with this `semantic-release` version. Iter-148 ships a wrapper that runs the iter-147 variance harness in BOTH conditions (baseline + multiplexed) back-to-back and emits a side-by-side distribution delta table:

```bash
scripts/iter148-empirical-validation-wrapper-comparing-baseline-versus-multiplexed-ssh-session-using-iter147-variance-harness-emitting-side-by-side-distribution-delta-table-for-get-git-auth-url-bottleneck-speedup-claim.sh

# With custom run count (same env var as iter-147 harness):
ITER147_VARIANCE_PROFILE_RUN_COUNT=10 scripts/iter148-...sh
```

#### Empirical results (cc-skills production machine, n=3 captures per condition)

| Namespace                           | BEFORE p50 | BEFORE p95 | BEFORE σ | AFTER p50 | AFTER p95 | AFTER σ | Δp50 (ms) |   Speedup |
| ----------------------------------- | ---------: | ---------: | -------: | --------: | --------: | ------: | --------: | --------: |
| `semantic-release:get-git-auth-url` |       6051 |       6067 |     32.7 |  **1835** |      1861 |    30.6 | **−4216** | **3.30x** |
| `semantic-release:config`           |         71 |         77 |      3.8 |        72 |        72 |     1.2 |        +1 |     0.99x |
| `semantic-release:plugins`          |         16 |         17 |      0.6 |        17 |        18 |     1.5 |        +1 |     0.94x |

**Verdict**: iter-146/147 SSH multiplexing claim is **VALIDATED** at distribution level. The actual measured speedup is **3.30x (~4.2 seconds saved per release)**, not the originally-claimed 10-15x. The gap between claim and reality is because `verifyAuth` includes more than the raw SSH key exchange the OpenSSH docs measure — there's per-call `git push --dry-run` setup, TCP teardown overhead, and protocol negotiation that doesn't accelerate from connection reuse.

**Distribution-level confidence**: Both conditions have σ ≈ 30ms (very stable — neither distribution flagged HIGH variance by the iter-147 σ/p50 > 0.20 trap detector). The 3.30x ratio is signal, not single-sample noise. Operator can confidently enable `RELEASE_SSH_MULTIPLEXING_ENABLED=1` or the iter-146 setup script knowing the speedup is empirically real.

## Operator-Facing Release-History Readable View (iter-150)

Run `mise run release:history` to render `git log` with awk-based soft-wrap of the verbose iter-N commit subjects to terminal-width with proper indentation and color. Addresses the operator-readability problem caused by the kebab-cased verbose conventional-commit subjects in the iter-144-through-iter-149 cohort (754–1078 chars per subject on one line — unreadable in `git log --oneline`, GitHub UI lists, and code-review tools).

```bash
# Default: last 10 commits, 80-col wrap
mise run release:history

# Custom run count + wrap width
ITER150_COMMIT_COUNT_TO_DISPLAY=20 ITER150_SOFT_WRAP_COLUMN_WIDTH=120 mise run release:history

# Pass extra git-log args after `--`
mise run release:history -- main~30..HEAD
```

### Going-forward commit-subject convention (iter-150 acknowledgement)

The /loop verbose-self-explanatory directive explicitly enumerates **identifiers** (file/function/class/variable/constant/test/benchmark names) — it does NOT mandate verbose git commit SUBJECTS. The industry-standard [conventional-commits specification](https://www.conventionalcommits.org/) 50/72 rule applies:

- Subject ≤ 50 chars hard cap (≤ 72 chars soft cap) — for `git log --oneline` scanability
- Body wrapped at 72 chars per line — for full detail
- Blank line separates subject from body

Going-forward iters should use **short subject + verbose body**, e.g.:

```
perf(release): iter-N <short hyphenated descriptive headline>

<verbose multi-paragraph body with full forensic detail,
wrapped at 72 chars per line — searchable via `git log --grep`
which matches body text too, preserving the searchability
the verbose-naming directive optimizes for>
```

Existing iter-144-through-iter-149 history is preserved as-is; the iter-150 renderer provides a band-aid readable view rather than rewriting history. Future iters from iter-151 onward should adopt the convention.

### Preflight self-enforcement of the 72-char hard cap (iter-151)

The iter-82 conventional-commits validator (run as preflight `Check 4l`) was extended in iter-151 to add a sixth classification bucket: `LONG-SUBJECT-EXCEEDS-ITER150-72-CHAR-HARD-CAP`. Conformant commits whose subject exceeds 72 chars are counted as an **informational overlay** — they do not block strict-mode release (semantic-release parses any subject length identically and the existing iter-144-149 history would all fail), but they surface as a labelled diagnostic block during every preflight run with a per-commit measured-char-count, an explanatory paragraph, and a cross-reference to `mise run release:history` for viewing the existing long-subject history readably.

The overlay-not-replacement design means a single commit can simultaneously belong to the standard-conformant bucket (which it does for semantic-release purposes) AND the long-subject overlay bucket (which surfaces the readability defect). The strict-mode blocking total formula is unchanged:

```
total_violations_blocking_strict_mode = compound_prefix + missing_type
```

Long-subject overlay violations do NOT contribute to strict-mode blocking. This is the only practical enforcement point per the cc-skills Local-First CI/CD Policy (no GitHub Actions for linting); commitlint's `header-max-length=72` rule would normally enforce this in CI but cannot be wired here.

To see the overlay output:

```bash
mise run audit-recent-git-commit-messages-...
# or via the preflight wrapper:
mise run release:preflight    # Check 4l informational output
```

Regression pin: `.mise/tasks/tests/test-iter151-...sh` (19 assertions across 6 groups covering structural validity, scaffolding declarations, length-measurement wiring, summary/diagnostic output, informational-only design invariant, and functional smoke test against the actual cc-skills repo).

### Operator-Facing Commits Health Dashboard (iter-152)

The iter-150 (VIEW) → iter-151 (DETECT) usability arc closes with iter-152's consolidated operator-facing dashboard `mise run commits:health`, which fuses both prior layers plus new aggregations into a single short-named entry point. Five panels:

1. **Panel 1 — Readable view**: delegates to the iter-150 awk-based soft-wrap renderer (single source of truth for readable rendering; no logic duplication).
2. **Panel 2 — Subject-length distribution histogram**: ASCII bar chart with bins anchored on the conventional-commits 50/72 industry rule — ≤50 (hard target), 51-72 (hard cap), 73-100 (mild over-cap), 101-200 (verbose-naming-era), 201-500 (heavy), 501-1000 (extreme), 1000+ (iter-144-149 outlier territory).
3. **Panel 3 — Worst offenders**: top-N (default 3) commits by char count with sha + measured length + truncated subject preview, so operators can target attention precisely.
4. **Panel 4 — Conventional-commits type distribution**: per-type count + ASCII bar across the 11 canonical sem-rel types (feat/fix/perf/chore/docs/refactor/test/build/ci/style/revert), giving visibility into release-cadence drivers.
5. **Panel 5 — Trend signal**: compares the current N-commit window against the previous N-commit window on two axes — median (p50) subject length and ≤72-cap conformance rate — and emits one of four verdicts: **IMPROVING** / **REGRESSING** / **STABLE** / **MIXED**.

**Why p50 not mean**: the iter-144-iter-149 cohort produced 754-1078 char outliers that would dominate any mean-based signal. The median is robust against these extremes — operators see the _typical_ commit shape, not the worst.

**Empirical proof iter-150 is working**: First smoke test against actual cc-skills `HEAD~10..HEAD` vs `HEAD~20..HEAD~10` showed:

- Median subject length: previous=177 chars → current=40 chars (Δ -77.5%)
- ≤72-cap conformance rate: previous=50% → current=60% (Δ +10pp)
- **Verdict: IMPROVING** (shorter subjects, higher conformance)

The convention adoption is empirically working — the dashboard surfaces it.

**Operator usage**:

```bash
# Default: last 10 commits vs previous 10
mise run commits:health

# Custom window size
ITER152_COMMIT_COUNT_TO_ANALYZE=20 mise run commits:health

# Stricter project: cap at 50 chars instead of 72
ITER152_SUBJECT_HARD_CAP_THRESHOLD_CHARS=50 mise run commits:health
```

**Tunables** (all with `ITER152_` prefix for namespace clarity): `COMMIT_COUNT_TO_ANALYZE` (default 10), `SUBJECT_HARD_CAP_THRESHOLD_CHARS` (default 72), `SUBJECT_HARD_TARGET_THRESHOLD_CHARS` (default 50), `HISTOGRAM_BAR_WIDTH` (default 20 cols), `WORST_OFFENDER_CALLOUT_COUNT` (default 3).

Regression pin: `.mise/tasks/tests/test-iter152-...sh` (28 assertions across 6 groups covering structural validity, env-var tunable honor, panel-by-panel design contract, trend-verdict 4-way state machine, mise wrapper delegation, and functional smoke test emitting all 5 panel headers + at least one histogram bar).

## Preflight Gate Maintenance

### Opt-In Per-Phase Wall-Clock Timing Instrumentation (iter-73)

`.mise/tasks/release/preflight` ships with env-var-gated per-phase timing instrumentation. Default behavior is unchanged — no output, no measurable overhead. Set `PREFLIGHT_TIMING_PROFILE=1` in the environment to surface a `⧗ phase elapsed: Nms (label)` line after each visible `→` phase header, plus a whole-script total at the end. Useful when preflight feels slow and you want to know which phase dominates without spelunking through subprocess calls.

```bash
PREFLIGHT_TIMING_PROFILE=1 mise run release:preflight 2>&1 | grep '⧗'
```

#### Iter-73 baseline (machine: macOS arm64, M-series, mise bash 5.3.9)

| Rank | Phase                                                 | ms   | % of preflight |
| ---- | ----------------------------------------------------- | ---- | -------------- |
| 1    | Check 4e: marketplace-wide hook regression suite      | 3819 | 38.7%          |
| 2    | Check 4b: self-evolution sandwich (217 SKILL.md scan) | 2032 | 20.6%          |
| 3    | Check 4h: INVERSE PreToolUse schema audit             | 863  | 8.7%           |
| 4    | Check 4d: chronicle slicing (37 assertions)           | 650  | 6.6%           |
| 5    | Check 4f: PreToolUse schema audit                     | 613  | 6.2%           |
| 6    | Check 4j: additionalContext-pentad audit              | 491  | 5.0%           |
| 7    | Check 4i: wildcard-matcher audit                      | 468  | 4.7%           |
| 8    | Check 4g: pueue-wrap-guard ordering audit             | 435  | 4.4%           |
| 9    | Check 4: plugin manifest validation (bun)             | 327  | 3.3%           |
| 10   | Check 4c: hook registration sanity                    | 102  | 1.0%           |
| 11   | Check 5: releasable commits since last tag            | 16   | 0.2%           |
| —    | Whole-script total                                    | 9871 | 100%           |

Top 2 phases accounted for **59% of preflight wall time** at iter-73 baseline.

#### Iter-74 measurement (after single-pass-awk-scanner replacement of Check 4b)

| Rank | Phase                                            | ms       | % of preflight | Δ from iter-73                      |
| ---- | ------------------------------------------------ | -------- | -------------- | ----------------------------------- |
| 1    | Check 4e: marketplace-wide hook regression suite | 3870     | 48.8%          | +51ms (test added)                  |
| 2    | Check 4h: INVERSE PreToolUse schema audit        | 847      | 10.7%          | -16ms                               |
| 3    | Check 4f: PreToolUse schema audit                | 652      | 8.2%           | +39ms                               |
| 4    | Check 4d: chronicle slicing (37 assertions)      | 648      | 8.2%           | -2ms                                |
| 5    | Check 4j: additionalContext-pentad audit         | 488      | 6.2%           | -3ms                                |
| 6    | Check 4g: pueue-wrap-guard ordering audit        | 441      | 5.6%           | +6ms                                |
| 7    | Check 4i: wildcard-matcher audit                 | 425      | 5.4%           | -43ms                               |
| 8    | Check 4: plugin manifest validation (bun)        | 308      | 3.9%           | -19ms                               |
| 9    | Check 4c: hook registration sanity               | 111      | 1.4%           | +9ms                                |
| 10   | **Check 4b: self-evolution sandwich**            | **73**   | **0.9%**       | **−1959ms (−96.4%, 27.8× speedup)** |
| 11   | Check 1: working directory clean                 | 18       | 0.2%           | new (instrumented)                  |
| 12   | Check 5: releasable commits since last tag       | 16       | 0.2%           | unchanged                           |
| 13   | Check 2-3: GH_TOKEN + GH_ACCOUNT env             | 2        | 0.0%           | new (instrumented)                  |
| —    | **Whole-script total**                           | **7924** | **100%**       | **−1947ms (−19.7%)**                |

Iter-74 win: replaced 217-file × 8-fork-exec storm (~1736 forks) with a single awk process invocation emitting TSV records to a fork-free bash post-processor. The actual speedup (27.8×) exceeded the conservative ~4× forecast because fork overhead on macOS aarch64 is amortized down to ~0.34ms per file when batched into one process versus ~9.4ms per file when forking serially.

#### Iter-75 measurement (after xargs-P parallelization of Check 4e)

| Rank | Phase                                                           | ms       | % of preflight | Δ from iter-74                      |
| ---- | --------------------------------------------------------------- | -------- | -------------- | ----------------------------------- |
| 1    | **Check 4e: marketplace-wide hook regression suite (parallel)** | **1381** | **23.1%**      | **−2489ms (−64.3%, 2.80× speedup)** |
| 2    | Check 4h: INVERSE PreToolUse schema audit                       | 964      | 16.1%          | +117ms                              |
| 3    | Check 4f: PreToolUse schema audit                               | 786      | 13.1%          | +134ms                              |
| 4    | Check 4d: chronicle slicing (37 assertions)                     | 742      | 12.4%          | +94ms                               |
| 5    | Check 4j: additionalContext-pentad audit                        | 524      | 8.8%           | +36ms                               |
| 6    | Check 4i: wildcard-matcher audit                                | 488      | 8.2%           | +63ms                               |
| 7    | Check 4g: pueue-wrap-guard ordering audit                       | 482      | 8.1%           | +41ms                               |
| 8    | Check 4: plugin manifest validation (bun)                       | 323      | 5.4%           | +15ms                               |
| 9    | Check 4c: hook registration sanity                              | 139      | 2.3%           | +28ms                               |
| 10   | Check 4b: self-evolution sandwich                               | 76       | 1.3%           | +3ms                                |
| 11   | Check 1: working directory clean                                | 25       | 0.4%           | +7ms                                |
| 12   | Check 5: releasable commits since last tag                      | 16       | 0.3%           | unchanged                           |
| 13   | Check 2-3: GH_TOKEN + GH_ACCOUNT env                            | 3        | 0.1%           | +1ms                                |
| —    | **Whole-script total**                                          | **5979** | **100%**       | **−1945ms (−24.5%)**                |

Iter-75 win: replaced sequential `for` loop with `xargs -P` (operator-tunable via `MARKETPLACE_HOOK_REGRESSION_PARALLEL_LANES`, default 8) running per-test bash worker that captures stdout+exit-code to per-test files in a shared mktemp results directory. Aggregation runs sequentially in stable sort order AFTER all parallel jobs complete, preserving the iter-54 UX (compact summary on PASS, full output on FAIL) bit-for-bit. Distribution flattened — Check 4e is no longer dominant.

#### Cumulative iter-73 → iter-75 progression

| Iter          | Phase Optimized                   | Change                  | Whole-script preflight                        |
| ------------- | --------------------------------- | ----------------------- | --------------------------------------------- |
| 73 (baseline) | — (instrumentation only)          | —                       | 9871ms                                        |
| 74            | Check 4b: single-pass awk scanner | 2032 → 73ms (−1959ms)   | 7924ms (−19.7%)                               |
| 75            | Check 4e: xargs-P parallelization | 3870 → 1381ms (−2489ms) | 5979ms (−24.5% additional, −39.4% cumulative) |

#### Iter-76+ optimization candidates (forensic notes for future iterations)

After iter-75 flattened the distribution, the top-4 phases are within 1.9× of each other (1381 / 964 / 786 / 742 ms). No single dominant lever remains. Highest-leverage incremental wins:

- **Check 4e bin-packing tail (1381ms)**: bound by the longest single test (`userpromptsubmit-1password-context-injection-prejq-fastpath` at 635ms) + second-longest (`posttooluse-1password-pattern-reminder` at 429ms) = 1064ms theoretical floor. Further parallel-lane scaling cannot improve this. Path forward: optimize the slowest tests themselves (reduce probe count, batch jq, share fixture loading).
- **Checks 4f + 4h combined (1750ms, 29.3% combined)**: PreToolUse and INVERSE PreToolUse schema audits scan hooks.json twice. Candidate: combine into a single audit task that scans hooks.json once and dispatches per-source-file regex in one pass. Estimated saving ~300-500ms.
- **Check 4d (742ms)**: chronicle slicing test (37 assertions, bun-based). Bun startup dominates; out-of-scope for marketplace-side fixes unless we batch all assertions into a single bun invocation.

The PREFLIGHT_TIMING_PROFILE=1 instrumentation has now validated two predicted perf wins end-to-end. Keep the knob shipped default-off; it will validate iter-76+ wins the same way.

### Operator-Tunable Perf Knobs (iter-73 → iter-132 cumulative reference)

Six operator-facing env-var knobs accumulated during the iter-73 → iter-132 perf+usability campaign. All default-off / sensible-default; opt in to surface diagnostic output or override built-in heuristics. Listed in order of common-use frequency.

#### `PREFLIGHT_TIMING_PROFILE=1` (iter-73, enhanced iter-130)

Surface per-phase wall-clock timing instrumentation during `mise run release:preflight`. Default off — preflight output is unchanged. When set:

- Emits `⧗ phase elapsed: Nms (Check X: label)` line after each check
- Emits whole-script total at end-of-script
- **Iter-130 enhancement**: emits a `Top N slowest preflight checks` bottleneck-ranking summary at end-of-script (default N=5), so operators iterating on perf see the dominant cost without manually scanning all `⧗` lines

```bash
# Bare timing
PREFLIGHT_TIMING_PROFILE=1 mise run release:preflight 2>&1 | grep '⧗'

# Top 3 instead of default top 5
PREFLIGHT_TIMING_PROFILE=1 \
  ITER130_TOP_N_SLOWEST_CHECKS_TO_DISPLAY=3 \
  mise run release:preflight 2>&1 | tail -15
```

#### `ITER140_TOP_N_SLOWEST_SUCCESSCMD_STEPS_TO_DISPLAY=N` (iter-140)

Override count for the iter-140 post-release `successCmd` per-step bottleneck ranking emitted when `RELEASE_TIMING_PROFILE=1`. Default 5. Mirrors `ITER130_TOP_N_SLOWEST_CHECKS_TO_DISPLAY` + `ITER139_TOP_N_SLOWEST_RELEASE_PHASES_TO_DISPLAY` at the deepest instrumentation level — `successCmd` step internals INSIDE Phase 2 (semantic-release).

Iter-140 also eliminated a hardcoded `sleep 2` between the `claude --print` plugin-update trigger and the cache-verify step. Net save: ~2000ms per release. The cache-verify step already handles the "cache not yet populated" graceful-degrade branch with a "may need session restart" warning, so the unconditional 2s wait had no functional benefit.

```bash
# Surface top 7 (= all) successCmd steps with their elapsed-ms
RELEASE_TIMING_PROFILE=1 \
  ITER140_TOP_N_SLOWEST_SUCCESSCMD_STEPS_TO_DISPLAY=7 \
  mise run release:full 2>&1 | grep -E '(⧗|successCmd)'
```

The seven instrumented steps (in execution order):

1. marketplace-clone git-fetch-tags + git-reset-hard-to-vN + plugin.json version-confirmation
2. **claude --print /plugin update cc-skills subprocess-bootstrap** (suspected dominant cost — full Claude Code instance bootstrap for one slash command; iter-141+ optimization candidate)
3. (Step 3 ELIMINATED by iter-140 — was `sleep 2`)
4. plugin-cache version-verification
5. sync-hooks-to-settings.sh invocation
6. hook-files-in-cache validation (jq-empty across all plugin cache directories)
7. jsDelivr-CDN-purge + tagged-URL-smoke-test loop over plugins/html-showcase/assets/\*

#### `RELEASE_TIMING_PROFILE=1` (iter-139)

Surface per-phase wall-clock timing for the **entire 7-phase release pipeline** (preflight → presync → version → sync → verify → chronicle → postflight). Mirrors the iter-73/130 preflight-internal pattern at the pipeline level. Default off — release output unchanged. When set:

- Emits `⧗ release-phase elapsed: Nms (Phase X: label)` after each phase completes
- Emits a `Top N slowest release phases` end-of-pipeline bottleneck-ranking summary (default N=5)
- Emits the whole-pipeline total for sum-of-phases vs wall-clock sanity check
- Compatible with `PREFLIGHT_TIMING_PROFILE=1` — set both for full per-check + per-phase visibility

```bash
# Profile a release end-to-end with both pipeline-level + preflight-internal timing
RELEASE_TIMING_PROFILE=1 \
  PREFLIGHT_TIMING_PROFILE=1 \
  mise run release:full 2>&1 | grep -E '(⧗|✓ Release)'

# Top 7 slowest phases (i.e., the full pipeline)
RELEASE_TIMING_PROFILE=1 \
  ITER139_TOP_N_SLOWEST_RELEASE_PHASES_TO_DISPLAY=7 \
  mise run release:full
```

Use when iterating on the ~45-55s post-preflight portion of release wall-clock. Iter-138 cut preflight from ~10.74s to ~4.5s; iter-139 unblocks the same data-driven approach for the OTHER ~90% of release time.

#### `MARKETPLACE_HOOK_REGRESSION_SUITE_TOP_N_SLOWEST_TESTS_TO_DISPLAY=N` (iter-131)

Surface per-test wall-clock ranking in the marketplace hook regression suite output. Default unset (no ranking section emitted; output bit-for-bit identical to pre-iter-131 for CI consumers). When set to a positive integer N:

- Each test's wall-clock captured via `$EPOCHREALTIME` start/end + awk math in the xargs -P worker
- Per-test elapsed-ms written to a sidecar `.elapsed_ms` file (sub-millisecond cost — no fork)
- End-of-aggregation emits `Top N slowest tests` ranked-descending summary

```bash
# Surface top 5 slowest tests with their elapsed-ms
MARKETPLACE_HOOK_REGRESSION_SUITE_TOP_N_SLOWEST_TESTS_TO_DISPLAY=5 \
  mise run test-marketplace-hook-regression-suite 2>&1 | tail -15
```

Useful when iterating on test perf — surfaces the bun-spawn-heavy orchestrator tests dominating wall-clock.

#### `MARKETPLACE_HOOK_REGRESSION_PARALLEL_LANES=N` (iter-75, adaptive default iter-128)

Override the parallel-lane count for the marketplace hook regression suite. **Default is adaptive**: `clamp(sysctl_hw_ncpu - 4, 4, 12)` — leaves 4-core headroom for OS+IDE, floors at 4 for low-end laptops, ceilings at 12 to avoid the bun-cold-start contention plateau measured at lanes=12 during iter-128 (lanes=10 is empirically the sweet spot on 14-core M-series; lanes=12 regressed 4-5%).

- 4-core machines: 4 lanes (floor)
- 8-core machines: 4 lanes
- 14-core M-series: 10 lanes (sweet spot)
- 16-core machines: 12 lanes (ceiling)

```bash
# Override to a specific count (e.g., for benchmarking or CI runners)
MARKETPLACE_HOOK_REGRESSION_PARALLEL_LANES=8 \
  mise run test-marketplace-hook-regression-suite
```

#### `ITER134_PREFLIGHT_AUDIT_PARALLEL_LANES=N` (iter-134)

Override the parallel-lane count for the **preflight audit fan-out** (Checks 4f-4v). **Default is adaptive**: same `clamp(sysctl_hw_ncpu - 4, 4, 12)` heuristic as iter-128's marketplace-suite (see above). Iter-134 introduces the parallel pre-warm that compresses ~2603ms of sequential audit work into ~510ms wall-clock (longest single audit caps the Phase-A blocking wait) — a **~30% reduction in total preflight wall-clock** (~7000ms → ~4900ms on a 14-core M-series host).

The 17 parallelized audits are independent kebab-case scans of the marketplace and share no mutable state, so the same iter-128 sweet-spot calibration applies. Override when benchmarking or running on a CI host with different CPU topology.

```bash
# Override audit-pre-warm lane count (different from MARKETPLACE_HOOK_REGRESSION_PARALLEL_LANES above)
ITER134_PREFLIGHT_AUDIT_PARALLEL_LANES=8 mise run release:preflight
```

#### `ITER134_DISABLE_PREFLIGHT_AUDIT_PARALLELIZATION=1` (iter-134)

Opt-out escape hatch for the iter-134 audit pre-warm. **Default off** — audits run in parallel via xargs -P. When set to `1`, the pre-warm forces `-P 1` (serial execution through xargs), preserving the sidecar contract while reverting to pre-iter-134 sequential timing. Use when diagnosing audit-suite issues where parallel-stdout ordering could confuse the per-check post-processing.

```bash
# Force serial audit execution (diagnostic only — costs ~2s wall-clock)
ITER134_DISABLE_PREFLIGHT_AUDIT_PARALLELIZATION=1 \
  PREFLIGHT_TIMING_PROFILE=1 \
  mise run release:preflight 2>&1 | grep '⧗'
```

#### `ITER132_RUN_PREFLIGHT_INTEGRATION_TIER=1` (iter-132)

Opt-in flag for the iter-132 regression test's preflight-integration tier. Default off — the test's standalone mode runs Tier 1 (source-fingerprint, ~50ms) + Tier 2.B (iter-131 suite integration, ~3s) but skips Tier 2.A (iter-130 preflight integration, ~7s) to keep the regression test fast in the common case. Enable when you're specifically iterating on the iter-130 preflight-summary feature.

#### `ITER135_RUN_SERIAL_MODE_INTEGRATION_TIER=1` (iter-135)

Opt-in flag for the iter-135 regression test's serial-mode-opt-out integration tier. Default off — the test's standalone mode runs Tier 1 (source-fingerprint, ~50ms) + Tier 2.A-D (parallel-mode integration, ~5s) but skips Tier 2.E (serial-mode opt-out integration, ~6s) to keep the regression test fast in the common case. Enable when specifically validating the `ITER134_DISABLE_PREFLIGHT_AUDIT_PARALLELIZATION=1` escape hatch.

```bash
ITER135_RUN_SERIAL_MODE_INTEGRATION_TIER=1 \
  bash .mise/tasks/tests/test-iter134-parallel-fan-out-preflight-audit-subprocesses-*.sh
```

```bash
ITER132_RUN_PREFLIGHT_INTEGRATION_TIER=1 \
  bash .mise/tasks/tests/test-iter130-and-iter131-bottleneck-ranking-summaries-*.sh
```

#### `AUDIT_REPO_ROOT_OVERRIDE=/path/to/synthetic/fixture/repo` (iter-62)

Override the repo root scanned by audit tasks. Default unset — audits resolve their repo root from `$BASH_SOURCE` (their own location in the marketplace). Override when running an audit against a synthetic fixture fleet to verify it correctly detects (or doesn't detect) violations.

```bash
# Run iter-62 inverse-schema audit against a synthetic fixture
AUDIT_REPO_ROOT_OVERRIDE=/tmp/fixture-fleet \
  bash .mise/tasks/audit-non-pretooluse-hooks-for-accidental-use-of-pretooluse-only-hookSpecificOutput-permissionDecision-field-...
```

#### `MARKETPLACE_HOOK_REGRESSION_SUITE_PARENT_INVOCATION_RECURSION_GUARD=1` (iter-75)

**Not an operator knob** — set automatically by the marketplace regression suite runner when it invokes per-test bash workers. Tests that need to invoke the runner themselves (e.g., iter-75 parity test, iter-132 bottleneck-ranking test) check this guard and self-skip their inner-runner integration tier to prevent infinite recursion. Documented here for completeness.

### Brittle-Banner-Grep Anti-Pattern (iter-69/70 lesson)

`.mise/tasks/release/preflight` parses audit task output by grep-extracting summary banners. **Hardcoded banner phrasing creates brittle coupling**: when an audit evolves its scope and renames its summary banner (e.g. iter-67 "Total registered Stop hooks scanned:" → iter-69 "Total registered pentad-member hooks scanned:" during the Stop → Stop+SubagentStop+SessionEnd+PreCompact+Notification pentad expansion), the preflight grep returns no match, `set -o pipefail` propagates the failure, and the gate silently aborts with no actionable diagnostic.

#### Forensic case

iter-69 first ship attempt: extended pentad audit shipped with renamed banner. Preflight Check 4j called the audit, audit exited 0 (no violations), but downstream banner-grep returned empty → pipefail → preflight aborted at "Running additionalContext-silently-dropped pentad audit..." with `[release:preflight] ERROR task failed` and no further diagnostic. Fixed in commit c75e6915.

#### Defensive pattern (iter-70 uniformity)

All preflight grep extractions use this pattern:

```bash
VAR=$( { grep -oE 'PATTERN' file || true; } | grep -oE '[0-9]+$' | head -1 || echo 0)
echo "  ✓ Result: ${VAR:-0}"
```

Three layers of defense:

1. **`{ grep ... || true; }`** — first grep always exits 0; swallows pipefail when banner phrasing changes.
2. **`|| echo 0`** — full-pipeline fallback; defends against any downstream pipeline failure (e.g. malformed log file).
3. **`${VAR:-0}`** — interpolation default; reports `0` rather than empty string if everything upstream produces no output.

#### Why this matters

Without defenses, a future audit rename ANYWHERE in the marketplace can crash preflight with zero diagnostic, blocking releases until an operator manually bisects the bash. With defenses, the gate gracefully degrades to `0` reporting and the human-readable summary line still emits — operators see "Pueue-wrap-guard ordering: 0 ok (0 violations)" instead of "ERROR task failed".

#### Maintenance rule for future audit changes

When extending an audit's scope and renaming its summary banner, you MUST update **both** sites coherently in the same commit:

- `.mise/tasks/tests/test-audit-*.sh` grep (regression test)
- `.mise/tasks/release/preflight` grep (release gate)

The defensive pattern above reduces the blast radius if you forget — but the only way to ensure the gate keeps reporting accurate counts is coherent dual-site updates.

## Key Files

| File                                | Purpose                        |
| ----------------------------------- | ------------------------------ |
| `.releaserc.yml`                    | semantic-release configuration |
| `.mise/tasks/release:*`             | mise release tasks             |
| `scripts/release-preflight.sh`      | Preflight validation           |
| `scripts/sync-hooks-to-settings.sh` | Hook synchronization           |
| `scripts/sync-versions.mjs`         | Version alignment across files |

## Related Documentation

- [semantic-release Skill](/plugins/itp/skills/semantic-release/SKILL.md)
- [Version Management ADR](/docs/adr/2025-12-05-centralized-version-management.md)
