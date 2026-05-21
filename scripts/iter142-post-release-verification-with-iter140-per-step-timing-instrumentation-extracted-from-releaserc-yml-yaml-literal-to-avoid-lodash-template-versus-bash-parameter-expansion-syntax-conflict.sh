#!/usr/bin/env bash
# iter-142: post-release verification with iter-140 per-step EPOCHREALTIME timing
# instrumentation, EXTRACTED from .releaserc.yml YAML literal heredoc so it stops
# being run through lodash-es template processing by @semantic-release/exec.
#
# Why this script exists (the bug it fixes):
#   @semantic-release/exec passes successCmd through lodash-es template() before
#   invoking the shell. Lodash interprets `${name}` as a JavaScript template
#   expression to evaluate against the release context (nextRelease.version etc.).
#   Iter-140 introduced bash parameter-expansion with default value
#   (`${RELEASE_TIMING_PROFILE:-0}`) directly inside the successCmd YAML literal.
#   Lodash tried to JS-eval `RELEASE_TIMING_PROFILE:-0` and bombed with
#   "SyntaxError: Unexpected token ':'" — the entire post-release verification
#   block silently never ran (observed live on v21.58.2). Marketplace clone
#   updates, hook sync, plugin cache verification, and jsDelivr CDN purge were
#   all skipped, leaving the local environment in a stale half-shipped state.
#
# Why extraction (not lodash-escape) is the right fix:
#   The successCmd block is ~200 lines of bash. Embedding it in YAML and dancing
#   around lodash-template syntax landmines is fragile. Future iters that want to
#   add `${VAR:-default}` parameter expansions, here-docs, or any sequence that
#   looks like a JS template will keep hitting this trap. Externalizing the bash
#   into a real file lets shellcheck see it, lets tests source it, and reduces
#   the .releaserc.yml successCmd to a single-token lodash expression
#   (`${nextRelease.version}` passed as argv[1]) which is exactly what lodash
#   templates were designed for.
#
# Invariants preserved across the extraction (identical behavior to iter-140):
#   - Step 1: marketplace-clone git-fetch-tags + git-reset-hard-to-vN
#   - Step 2: claude --print /plugin update cc-skills subprocess-bootstrap
#   - Step 3: ELIMINATED (was hardcoded `sleep 2`, removed by iter-140)
#   - Step 4: plugin-cache version-verification (with graceful-degrade)
#   - Step 5: sync-hooks-to-settings.sh invocation
#   - Step 6: hook-files-in-cache jq-empty validation
#   - Step 7: jsDelivr CDN purge + tagged-URL smoke-test loop
#   - Step 8: final summary banner
#   - Per-step iter-140 EPOCHREALTIME timing wrappers (gated on
#     RELEASE_TIMING_PROFILE=1) + end-of-block top-N slowest ranking
#     (ITER140_TOP_N_SLOWEST_SUCCESSCMD_STEPS_TO_DISPLAY, default 5)

set -euo pipefail

# VERSION arrives as $1 from .releaserc.yml `successCmd: "./scripts/iter142-...sh ${nextRelease.version}"`
# (single well-formed lodash expression — no syntax conflict).
VERSION="${1:?usage: $0 <next-release-version>; called by @semantic-release/exec successCmd}"

CACHE_DIR="$HOME/.claude/plugins/cache/cc-skills"
MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/cc-skills"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  POST-RELEASE: Automated Plugin Update & Verification"
echo "═══════════════════════════════════════════════════════════"

# Iter-140: per-successCmd-step EPOCHREALTIME timing instrumentation gated on
# RELEASE_TIMING_PROFILE=1. Mirrors the iter-139 pipeline-level pattern at the
# next-deeper structural level: where iter-139 measures each `mise run release:X`
# phase, iter-140 measures each of the seven post-release successCmd steps
# (marketplace-update, claude-plugin-trigger, cache-verify, hooks-sync,
# hooks-verify, jsDelivr-purge-and-smoke-test, final-summary). Unlocks
# data-driven optimization of the post-release block which iter-139 measured
# as part of the dominant Phase 2 (30.9s, 70% of release wall-clock).
# Per-step ranking emitted end-of-block.
__iter140_per_successcmd_step_timing_record_array_for_top_n_slowest_bottleneck_ranking_summary=()
__iter140_current_post_release_successcmd_step_start_seconds_using_epochrealtime=""
__iter140_current_post_release_successcmd_step_human_readable_label=""

__iter140_start_post_release_successcmd_step_with_epochrealtime_wall_clock_capture() {
    __iter140_current_post_release_successcmd_step_human_readable_label="$1"
    if [[ "${RELEASE_TIMING_PROFILE:-0}" == "1" ]]; then
        __iter140_current_post_release_successcmd_step_start_seconds_using_epochrealtime="$EPOCHREALTIME"
    fi
}

__iter140_end_post_release_successcmd_step_with_epochrealtime_wall_clock_capture() {
    if [[ "${RELEASE_TIMING_PROFILE:-0}" == "1" ]] && [[ -n "$__iter140_current_post_release_successcmd_step_start_seconds_using_epochrealtime" ]]; then
        local end_seconds="$EPOCHREALTIME"
        local elapsed_ms
        elapsed_ms=$(awk -v s="$__iter140_current_post_release_successcmd_step_start_seconds_using_epochrealtime" -v e="$end_seconds" 'BEGIN { printf "%.0f", (e - s) * 1000 }')
        echo "  ⧗ successCmd-step elapsed: ${elapsed_ms}ms (${__iter140_current_post_release_successcmd_step_human_readable_label})"
        __iter140_per_successcmd_step_timing_record_array_for_top_n_slowest_bottleneck_ranking_summary+=("${elapsed_ms}"$'\t'"${__iter140_current_post_release_successcmd_step_human_readable_label}")
    fi
}

# Step 1: Update marketplace git repo (source of truth)
__iter140_start_post_release_successcmd_step_with_epochrealtime_wall_clock_capture \
    "Step 1: marketplace-clone git-fetch-tags + git-reset-hard-to-vN + plugin.json version-confirmation"
echo "→ Step 1: Updating marketplace repo..."
if [[ -d "$MARKETPLACE_DIR/.git" ]]; then
  cd "$MARKETPLACE_DIR"
  git fetch origin --tags --quiet
  git reset --hard "v$VERSION" --quiet 2>/dev/null || git reset --hard origin/main --quiet
  REPO_VERSION=$(jq -r '.version' plugin.json 2>/dev/null || echo "unknown")
  if [[ "$REPO_VERSION" == "$VERSION" ]]; then
    echo "  ✓ Marketplace repo updated to v$VERSION"
  else
    echo "  ✗ FAILED: Marketplace repo at v$REPO_VERSION, expected v$VERSION"
    exit 1
  fi
else
  echo "  ⚠ Marketplace repo not found at $MARKETPLACE_DIR"
fi
__iter140_end_post_release_successcmd_step_with_epochrealtime_wall_clock_capture

# Step 2: Trigger Claude Code plugin update
# Iter-140 cost-watch: this step bootstraps a full claude subprocess just to fire
# one slash command. Empirical data from iter-140 instrumentation will confirm
# whether this is the dominant cost inside the successCmd block (suspected
# ~10-15s); iter-143+ candidate is to replace this with a direct
# cache-invalidation primitive if so.
__iter140_start_post_release_successcmd_step_with_epochrealtime_wall_clock_capture \
    "Step 2: claude --print /plugin update cc-skills subprocess-bootstrap (bootstraps full Claude Code instance for one slash command)"
echo "→ Step 2: Triggering Claude Code plugin update..."
if command -v claude &>/dev/null; then
  # Use claude in non-interactive mode to update plugin
  claude --print "/plugin update cc-skills" 2>&1 | head -20 || true
  echo "  ✓ Plugin update triggered"
else
  echo "  ⚠ Claude Code not found in PATH, skipping automatic update"
fi
__iter140_end_post_release_successcmd_step_with_epochrealtime_wall_clock_capture

# Step 3: ELIMINATED by iter-140.
# Previously: `sleep 2` (hardcoded 2-second wait for cache to populate before
# Step 4 verification). Iter-140 removed because Step 4 already handles graceful
# degrade — if the cache hasn't populated by the time verification runs, it
# reports "may need session restart" (existing branch). The unconditional
# 2-second wait was burning operator wall-clock for no functional benefit.
# Net save: 2000ms per release (4-5% of the post-release successCmd block;
# ~0.5% of pipeline).

# Step 4: Verify cache has new version
__iter140_start_post_release_successcmd_step_with_epochrealtime_wall_clock_capture \
    "Step 4: plugin-cache version-verification (ls $CACHE_DIR/<plugin>/$VERSION presence check + graceful-degrade fallback to latest-cached comparison)"
echo "→ Step 3: Verifying plugin cache..."
if [[ -d "$CACHE_DIR" ]]; then
  # Iter-142: replaced `ls -1 | head -1` (SC2012 — fragile on non-alphanumeric
  # filenames) with bash glob-into-array + basename idiom. shopt nullglob is
  # scoped so empty directory yields empty array (no literal `*` artifact).
  shopt -s nullglob
  cache_dir_plugin_subdirectories_iter142=("$CACHE_DIR"/*/)
  shopt -u nullglob
  SAMPLE_PLUGIN=""
  if (( ${#cache_dir_plugin_subdirectories_iter142[@]} > 0 )); then
    SAMPLE_PLUGIN=$(basename "${cache_dir_plugin_subdirectories_iter142[0]}")
  fi
  if [[ -n "$SAMPLE_PLUGIN" && -d "$CACHE_DIR/$SAMPLE_PLUGIN/$VERSION" ]]; then
    echo "  ✓ Cache verified: v$VERSION present"
  elif [[ -n "$SAMPLE_PLUGIN" ]]; then
    # Iter-142: find -exec basename + sort -V replaces `ls -1 | sort -V | tail`
    # (SC2012) — find handles non-alphanumeric filenames safely; sort -V still
    # required because cache subdirs are semver strings (e.g. v21.58.2).
    LATEST_CACHED=$(find "$CACHE_DIR/$SAMPLE_PLUGIN" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort -V | tail -1)
    if [[ "$LATEST_CACHED" == "$VERSION" ]]; then
      echo "  ✓ Cache verified: v$VERSION is latest"
    else
      echo "  ⚠ Cache has v$LATEST_CACHED, v$VERSION may need session restart"
    fi
  fi
fi
__iter140_end_post_release_successcmd_step_with_epochrealtime_wall_clock_capture

# Step 5: Sync hooks to settings.json (auto-install new hooks)
__iter140_start_post_release_successcmd_step_with_epochrealtime_wall_clock_capture \
    "Step 5: sync-hooks-to-settings.sh invocation (auto-install new hooks into ~/.claude/settings.json from marketplace)"
echo "→ Step 4: Syncing hooks to settings.json..."
SYNC_SCRIPT="$MARKETPLACE_DIR/scripts/sync-hooks-to-settings.sh"
if [[ -x "$SYNC_SCRIPT" ]]; then
  "$SYNC_SCRIPT"
else
  echo "  ⚠ Hook sync script not found at $SYNC_SCRIPT"
fi
__iter140_end_post_release_successcmd_step_with_epochrealtime_wall_clock_capture

# Step 6: Verify hook files in cache (for plugins with hooks)
__iter140_start_post_release_successcmd_step_with_epochrealtime_wall_clock_capture \
    "Step 6: hook-files-in-cache validation (jq-empty per hooks.json across all plugin cache directories — verify all hooks.json files parse as valid JSON)"
echo "→ Step 5: Verifying hook files..."
HOOKS_VERIFIED=0
HOOKS_MISSING=0
# Iter-142: replaced `for x in $(ls -1 ...)` (SC2045 — fragile word-split of ls
# output; breaks on whitespace/glob chars in filenames) with bash glob iteration
# + basename. shopt nullglob scoped to avoid literal `*/` artifact on empty.
shopt -s nullglob
hook_verification_plugin_cache_subdirectories_iter142=("$CACHE_DIR"/*/)
shopt -u nullglob
for PLUGIN_CACHE_SUBDIRECTORY_ITER142 in "${hook_verification_plugin_cache_subdirectories_iter142[@]}"; do
  PLUGIN_NAME=$(basename "$PLUGIN_CACHE_SUBDIRECTORY_ITER142")
  HOOKS_JSON="$CACHE_DIR/$PLUGIN_NAME/$VERSION/hooks/hooks.json"
  if [[ -f "$HOOKS_JSON" ]]; then
    # Validate hooks.json is valid JSON
    if jq empty "$HOOKS_JSON" 2>/dev/null; then
      # Iter 22: ++ form returns exit 1 on first call (VAR was 0); +=1 always 0
      ((HOOKS_VERIFIED+=1))
    else
      echo "  ✗ Invalid JSON: $PLUGIN_NAME/hooks/hooks.json"
      ((HOOKS_MISSING+=1))
    fi
  fi
done
if [[ $HOOKS_VERIFIED -gt 0 ]]; then
  echo "  ✓ Hook files verified: $HOOKS_VERIFIED plugin(s) with hooks"
fi
if [[ $HOOKS_MISSING -gt 0 ]]; then
  echo "  ⚠ Hook issues found: $HOOKS_MISSING plugin(s)"
fi
__iter140_end_post_release_successcmd_step_with_epochrealtime_wall_clock_capture

# Step 7: jsDelivr CDN purge + smoke-test for html-showcase kernel CSS
__iter140_start_post_release_successcmd_step_with_epochrealtime_wall_clock_capture \
    "Step 7: jsDelivr-CDN-purge + tagged-URL-smoke-test loop over plugins/html-showcase/assets/* (curl purge.jsdelivr.net @main + curl cdn.jsdelivr.net @vN for each asset)"
# Auto-discovers CDN-served assets via the html-showcase plugin's assets/
# directory. Adding new files there picks them up on the next release with zero
# config change here.
if [[ -d "$MARKETPLACE_DIR/plugins/html-showcase/assets" ]]; then
  echo "→ Step 6: Refreshing jsDelivr CDN for html-showcase assets..."
  PURGED=0
  SMOKE_OK=0
  SMOKE_FAIL=0
  for ASSET_PATH in "$MARKETPLACE_DIR/plugins/html-showcase/assets"/*; do
    [[ -f "$ASSET_PATH" ]] || continue
    ASSET_NAME=$(basename "$ASSET_PATH")
    REL_PATH="plugins/html-showcase/assets/$ASSET_NAME"

    # 7a. Purge @main cache so kernel edits go live worldwide within seconds.
    #     Tagged URLs (@v$VERSION) are immutable; no purge needed.
    if curl -fsSL --max-time 10 \
        "https://purge.jsdelivr.net/gh/terrylica/cc-skills@main/$REL_PATH" \
        >/dev/null 2>&1; then
      # Iter 22: ((VAR++)) returns exit 1 when VAR starts at 0 (post-increment
      # returns the OLD value 0 → arithmetic context returns falsy → set -e
      # kills the script). Use += assignment which always returns 0.
      ((PURGED+=1))
    fi

    # 7b. Smoke-test that the new tagged URL resolves with correct MIME. Pages
    #     that pin to v$VERSION must work immediately on release.
    CDN_URL="https://cdn.jsdelivr.net/gh/terrylica/cc-skills@v$VERSION/$REL_PATH"
    if curl -fsSL --max-time 15 -o /dev/null -w "%{http_code}" "$CDN_URL" \
        | grep -q "^200$"; then
      ((SMOKE_OK+=1))
    else
      ((SMOKE_FAIL+=1))
      echo "  ✗ Smoke-test failed: $CDN_URL"
    fi
  done
  if [[ $PURGED -gt 0 ]]; then
    echo "  ✓ Purged @main cache for $PURGED asset(s)"
  fi
  if [[ $SMOKE_OK -gt 0 ]]; then
    echo "  ✓ Smoke-test passed: $SMOKE_OK asset(s) reachable at @v$VERSION"
  fi
  if [[ $SMOKE_FAIL -gt 0 ]]; then
    echo "  ⚠ Smoke-test: $SMOKE_FAIL asset(s) not yet propagated (transient; jsDelivr usually catches up within 60s)"
  fi
fi
__iter140_end_post_release_successcmd_step_with_epochrealtime_wall_clock_capture

# Step 8: Final summary
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✓ Post-release verification complete for v$VERSION"
echo "═══════════════════════════════════════════════════════════"

# Iter-140: emit top-N slowest successCmd steps ranking when
# RELEASE_TIMING_PROFILE=1. Mirrors iter-130/139 ranking pattern at the deepest
# structural level (successCmd internals). Unlocks data-driven iter-143+
# optimization of whichever step dominates (suspected: Step 2 claude --print
# subprocess-bootstrap).
if [[ "${RELEASE_TIMING_PROFILE:-0}" == "1" ]] && [[ "${#__iter140_per_successcmd_step_timing_record_array_for_top_n_slowest_bottleneck_ranking_summary[@]}" -gt 0 ]]; then
    __iter140_top_n_threshold_for_slowest_successcmd_step_ranking_display="${ITER140_TOP_N_SLOWEST_SUCCESSCMD_STEPS_TO_DISPLAY:-5}"
    echo ""
    echo "  ⧗ ─── Top ${__iter140_top_n_threshold_for_slowest_successcmd_step_ranking_display} slowest successCmd steps (iter-140 post-release-block bottleneck ranking) ───"
    printf '%s\n' "${__iter140_per_successcmd_step_timing_record_array_for_top_n_slowest_bottleneck_ranking_summary[@]}" \
        | sort -rn -k1 \
        | head -n "${__iter140_top_n_threshold_for_slowest_successcmd_step_ranking_display}" \
        | awk -F'\t' '{ printf "      %2d. %6d ms  %s\n", NR, $1, $2 }'
    echo "  ⧗ (override count via ITER140_TOP_N_SLOWEST_SUCCESSCMD_STEPS_TO_DISPLAY=N)"
fi
