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

Top 2 phases account for **59% of preflight wall time** — these are the highest-leverage iter-74+ optimization targets.

#### Iter-74+ optimization candidates (forensic notes for future iterations)

- **Check 4e (38.7%)**: auto-discovered marketplace-wide hook regression suite. Currently 14 test files run serially. Candidate: parallel execution via `xargs -P` (estimated 1-2s savings; subject to bun startup parallelism and shared `/tmp` log file contention).
- **Check 4b (20.6%)**: self-evolution sandwich check loops over 217 SKILL.md files spawning ~5 fork/execs each (awk + head + grep + cut + wc). Candidate: rewrite the per-file body as a single awk/bun script that processes all files in one process. Estimated ~1.5s savings (~2032ms → ~500ms).
- **Check 4h (8.7%)**: INVERSE PreToolUse schema audit. ~860ms is justified for what it does (scanning all non-PreToolUse hooks for forbidden field usage). Lower-priority target; gate this against the iter-74+ planning to avoid premature optimization.

The instrumentation is a permanent self-diagnosis tool — keep it shipped, default-off, so future iterations can capture before/after measurements to validate perf wins.

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
