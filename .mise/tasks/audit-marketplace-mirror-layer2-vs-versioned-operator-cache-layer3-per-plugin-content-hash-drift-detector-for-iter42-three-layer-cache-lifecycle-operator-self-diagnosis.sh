#!/usr/bin/env bash
#MISE description="Iter-76 operator-facing 3-layer-cache drift detector. For each plugin in ~/.claude/plugins/marketplaces/cc-skills/plugins/*/, compute per-file SHA-256 hashes across Layer 2 (marketplace mirror — what the operator's git pull last fetched) and Layer 3 (versioned operator cache — what Claude Code actually loads at hook fire time, at the highest SemVer tag directory under ~/.claude/plugins/cache/cc-skills/<plugin>/). Classify each plugin as FRESH (L2==L3), STALE-CACHE (L2 ahead of L3, operator should reinstall plugin), or NOT-CACHED-LAYER-3 (plugin in mirror but never installed). Exit 0 if all plugins FRESH or NOT-CACHED; exit 1 if any STALE-CACHE detected. Companion tool to the iter-42 docs/HOOKS.md hand-typed forensic recipe. SUBCOMMANDS - default (per-plugin summary table); --verbose (per-file divergence list per stale plugin); --check-plugin <name> (focus on single plugin)."

# Iter-76 multi-perspective operator-facing 3-layer-cache drift detector.
#
# Background: the 3-layer versioned cache lifecycle documented in iter-42
# (docs/HOOKS.md) means hook + skill + command source edits at the working
# tree (Layer 1) don't immediately reach the running Claude Code session.
# Edits propagate Layer 1 → Layer 2 (marketplace mirror) via `git pull`
# (or via symlink for developers), and Layer 2 → Layer 3 (versioned
# operator cache) only when semantic-release publishes a new tag AND
# the operator's Claude Code plugin runtime polls + downloads it. Until
# both happen, Layer 3 stays frozen at the pre-fix snapshot.
#
# Pre-iter-76: operators relied on a hand-typed bash recipe in docs/
# HOOKS.md "Diagnosis Recipe — 'My Hook Fix Isn't Working'" to compute
# Layer 1 → Layer 2 → Layer 3 divergence. Each plugin had to be probed
# individually. The recipe used grep-counted "marker strings" rather
# than content-equivalence — which fails if an iteration touches code
# without containing the operator's chosen marker.
#
# Iter-76 ships an algorithmic detector that bypasses the hand-typed
# recipe with content-hash comparison: shasum every file under Layer 2
# and the highest-SemVer Layer 3 directory for each plugin, then diff
# the hash lists. Three classifications:
#
#   1. FRESH (Layer 2 == Layer 3): operator's cache reflects the current
#      marketplace state. Hooks/skills/commands fire from the same
#      source code the operator could `cat` from the mirror.
#
#   2. STALE-CACHE (Layer 2 != Layer 3): the marketplace mirror has
#      changes that Layer 3 has not yet absorbed — typically because
#      semantic-release published a new tag but the operator hasn't
#      reinstalled the plugin (and the plugin runtime hasn't auto-
#      refreshed). Remediation: `claude plugin install <plugin>@cc-skills`
#      or restart Claude Code. Exit code 1 fires here.
#
#   3. NOT-CACHED-LAYER-3: the plugin exists in the marketplace mirror
#      but no versioned cache directory exists yet — the operator has
#      never installed this plugin. Not a drift, just an opt-out. Exit
#      code stays 0.
#
# Why compare Layer 2 vs Layer 3 (not Layer 1 vs Layer 3)?
#
# On developer machines (this repo's primary use case), Layer 2 is
# typically a SYMLINK to the working-tree Layer 1, so L1 == L2 by
# construction. On operator machines, there is no Layer 1 — only a
# real Layer 2 clone of the GitHub `main` branch. Comparing L2 vs L3
# unifies both cases: L2 is always "what the marketplace currently has
# from the operator's perspective", and L3 is always "what Claude Code
# actually loads". The drift between them is the operator-actionable
# signal.
#
# Forensic source: iter-42 docs/HOOKS.md "Hook Source Edits Don't Take
# Effect Until Next Tagged Release (3-Layer Versioned Cache Lifecycle)"
# section + 2026 web-research confirmation that "Update a plugin by
# reinstalling it. The plugin system doesn't have automatic updates
# yet, but reinstalling pulls the latest version." (sources cited in
# the iter-76 commit message).

set -euo pipefail

# Iter-35 bash-5.2-patsub-replacement-defense (cross-plugin sweep):
shopt -u patsub_replacement 2>/dev/null || true

MARKETPLACE_MIRROR_LAYER_2_BASE_PATH="${HOME}/.claude/plugins/marketplaces/cc-skills/plugins"
VERSIONED_OPERATOR_CACHE_LAYER_3_BASE_PATH="${HOME}/.claude/plugins/cache/cc-skills"

if [[ ! -d "$MARKETPLACE_MIRROR_LAYER_2_BASE_PATH" ]]; then
    echo "✗ Marketplace mirror (Layer 2) not found at:"
    echo "    $MARKETPLACE_MIRROR_LAYER_2_BASE_PATH"
    echo ""
    echo "  This tool runs against an INSTALLED marketplace. Run from a"
    echo "  machine that has \`claude plugin marketplace add terrylica/cc-skills\`"
    echo "  configured."
    exit 2
fi

if [[ ! -d "$VERSIONED_OPERATOR_CACHE_LAYER_3_BASE_PATH" ]]; then
    echo "✗ Versioned operator cache (Layer 3) not found at:"
    echo "    $VERSIONED_OPERATOR_CACHE_LAYER_3_BASE_PATH"
    echo ""
    echo "  No plugins have been installed yet — nothing to compare."
    echo "  Run \`claude plugin install <plugin>@cc-skills\` first."
    exit 0
fi

# Parse argv: --verbose, --check-plugin <name>, --all-divergences
EMIT_PER_FILE_DIVERGENCE_LIST_VERBOSE_MODE=0
RESTRICT_TO_SINGLE_PLUGIN_NAME=""
INCLUDE_LAYER_3_CACHE_POPULATOR_KEPT_SUBTREES_ONLY=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose)
            EMIT_PER_FILE_DIVERGENCE_LIST_VERBOSE_MODE=1
            shift
            ;;
        --check-plugin)
            RESTRICT_TO_SINGLE_PLUGIN_NAME="$2"
            shift 2
            ;;
        --all-divergences)
            # Forensic / debug mode: do NOT filter by cache-populator-
            # kept subtrees. Surfaces ALL L2-vs-L3 differences including
            # documented benign omissions (CLAUDE.md, docs/, scripts/,
            # tests/, templates/, schemas/, README.md). Use this to
            # verify the cache-populator's filter rules haven't changed
            # in a Claude Code update — if `--all-divergences` reports
            # a file that the default mode classifies as drift, the
            # cache populator now copies that path too.
            INCLUDE_LAYER_3_CACHE_POPULATOR_KEPT_SUBTREES_ONLY=0
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: $0 [--verbose] [--check-plugin <name>] [--all-divergences]"
            exit 2
            ;;
    esac
done

# Helper: produce a sorted list of "<relative-path>\t<sha256>" lines for
# every file under a given directory. Sorting ensures order-independence
# in the diff. Uses POSIX shasum (available on macOS + Linux) rather than
# sha256sum (Linux-only). The find pruning excludes git metadata + any
# build/cache dirs that may have crept into the cache snapshot.
#
# Iter-76 cache-populator-filter discovery: Claude Code's plugin cache
# populator keeps ONLY these subtrees at the plugin root when copying
# Layer 2 → Layer 3:
#
#   - hooks/      (executable hook scripts and their assets)
#   - skills/     (SKILL.md descriptors and skill assets)
#   - commands/   (slash-command markdown files)
#   - agents/     (sub-agent definitions)
#   - plugin.json (plugin manifest)
#
# Everything else at the plugin root (CLAUDE.md, README.md, docs/,
# scripts/, tests/, templates/, schemas/, LICENSE, CHANGELOG.md, .git*)
# is STRIPPED. This is an intentional dev-vs-runtime asset partition.
# The detector classifies divergences by checking whether each diverged
# path is under one of the "cache-included" subtrees: divergences under
# included paths are real drift signals; divergences under excluded
# paths are documented benign omissions.
#
# Filter applied here: the listing fed into the comparison includes ONLY
# files under cache-included paths, so the diff between L2 and L3 is
# apples-to-apples. The unfiltered scan is available via --all-divergences
# for forensic debugging (e.g., verifying the cache-populator filter
# rules haven't changed in a Claude Code update).
compute_per_file_content_hash_listing_sorted_by_relative_path() {
    local content_root_directory="$1"
    local include_only_layer_3_cache_populator_kept_subtrees="${2:-1}"
    cd "$content_root_directory"
    if [[ "$include_only_layer_3_cache_populator_kept_subtrees" == "1" ]]; then
        # Only paths Claude Code's plugin cache populator preserves.
        # The find expression accepts files at ./plugin.json OR under
        # ./hooks/ ./skills/ ./commands/ ./agents/ subtrees.
        find . \
            \( -path './hooks/*' \
            -o -path './skills/*' \
            -o -path './commands/*' \
            -o -path './agents/*' \
            -o -path './plugin.json' \) \
            -type f \
            -not -path './.git/*' \
            -not -path './node_modules/*' \
            -not -path './.venv/*' \
            -not -path './target/*' \
            -not -path './.build/*' \
            -print0 \
            | xargs -0 shasum -a 256 2>/dev/null \
            | awk '{printf "%s\t%s\n", $2, $1}' \
            | sort
    else
        # Forensic / debug mode — include EVERYTHING. Used by
        # --all-divergences to surface the full L2 vs L3 delta,
        # including documented benign omissions like CLAUDE.md, docs/,
        # scripts/, tests/, etc.
        find . -type f \
            -not -path './.git/*' \
            -not -path './node_modules/*' \
            -not -path './.venv/*' \
            -not -path './target/*' \
            -not -path './.build/*' \
            -print0 \
            | xargs -0 shasum -a 256 2>/dev/null \
            | awk '{printf "%s\t%s\n", $2, $1}' \
            | sort
    fi
}

# Per-plugin classification + drift tally
total_plugins_scanned=0
total_plugins_fresh=0
total_plugins_stale=0
total_plugins_not_cached=0
stale_plugins_list=()

echo "═══════════════════════════════════════════════════════════"
echo "  Iter-76 3-Layer Cache Drift Detector"
echo "═══════════════════════════════════════════════════════════"
echo "  Layer 2 (marketplace mirror): $MARKETPLACE_MIRROR_LAYER_2_BASE_PATH"
echo "  Layer 3 (versioned cache):    $VERSIONED_OPERATOR_CACHE_LAYER_3_BASE_PATH"
echo "═══════════════════════════════════════════════════════════"
echo ""
printf "  %-30s %-22s %s\n" "Plugin" "Verdict" "Detail"
printf "  %-30s %-22s %s\n" "------" "-------" "------"

for plugin_layer_2_directory in "$MARKETPLACE_MIRROR_LAYER_2_BASE_PATH"/*/; do
    plugin_name="$(basename "$plugin_layer_2_directory")"

    # --check-plugin filter
    if [[ -n "$RESTRICT_TO_SINGLE_PLUGIN_NAME" ]] && [[ "$plugin_name" != "$RESTRICT_TO_SINGLE_PLUGIN_NAME" ]]; then
        continue
    fi

    total_plugins_scanned=$((total_plugins_scanned + 1))

    plugin_layer_3_root_directory="$VERSIONED_OPERATOR_CACHE_LAYER_3_BASE_PATH/$plugin_name"
    if [[ ! -d "$plugin_layer_3_root_directory" ]]; then
        printf "  %-30s %-22s %s\n" \
            "$plugin_name" "NOT-CACHED-LAYER-3" "plugin not yet installed"
        total_plugins_not_cached=$((total_plugins_not_cached + 1))
        continue
    fi

    # Highest SemVer subdirectory = current Layer 3 view. Iter-42
    # docs/HOOKS.md confirms this is what Claude Code actually loads
    # at hook fire time when ${CLAUDE_PLUGIN_ROOT} is resolved.
    # SC2012 fix: `find ... -maxdepth 1 -type d` instead of `ls -1`
    # for safer non-alphanumeric-filename handling.
    highest_semver_versioned_cache_subdirectory_name=$(
        find "$plugin_layer_3_root_directory" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null \
            | sort -V \
            | tail -1
    )
    if [[ -z "$highest_semver_versioned_cache_subdirectory_name" ]]; then
        printf "  %-30s %-22s %s\n" \
            "$plugin_name" "NOT-CACHED-LAYER-3" "no versioned subdir"
        total_plugins_not_cached=$((total_plugins_not_cached + 1))
        continue
    fi
    plugin_layer_3_versioned_path="$plugin_layer_3_root_directory/$highest_semver_versioned_cache_subdirectory_name"

    # Subshells isolate the `cd` so each hash listing runs from a fresh
    # working directory — eliminates any cross-iteration cwd carry-over.
    # The second arg controls cache-populator-filter mode (default 1 =
    # only include subtrees Claude Code's cache populator preserves; 0 =
    # forensic mode includes everything).
    layer_2_per_file_hash_listing=$(compute_per_file_content_hash_listing_sorted_by_relative_path \
        "$plugin_layer_2_directory" \
        "$INCLUDE_LAYER_3_CACHE_POPULATOR_KEPT_SUBTREES_ONLY")
    layer_3_per_file_hash_listing=$(compute_per_file_content_hash_listing_sorted_by_relative_path \
        "$plugin_layer_3_versioned_path" \
        "$INCLUDE_LAYER_3_CACHE_POPULATOR_KEPT_SUBTREES_ONLY")

    if [[ "$layer_2_per_file_hash_listing" == "$layer_3_per_file_hash_listing" ]]; then
        printf "  %-30s %-22s %s\n" \
            "$plugin_name" "FRESH (L2==L3)" "$highest_semver_versioned_cache_subdirectory_name"
        total_plugins_fresh=$((total_plugins_fresh + 1))
    else
        # Count diverged files for the summary line. diff exits 1 when
        # there are differences — || true to swallow under set -e.
        per_file_divergence_diff=$(diff <(echo "$layer_2_per_file_hash_listing") <(echo "$layer_3_per_file_hash_listing") || true)
        diverged_file_count=$(echo "$per_file_divergence_diff" | grep -cE '^[<>] ' || true)
        printf "  %-30s %-22s %s\n" \
            "$plugin_name" "STALE-CACHE (L2!=L3)" "L3=$highest_semver_versioned_cache_subdirectory_name, $diverged_file_count diverged file-hash records"
        total_plugins_stale=$((total_plugins_stale + 1))
        stale_plugins_list+=("$plugin_name")

        # --verbose: emit per-file divergence list inline
        if [[ "$EMIT_PER_FILE_DIVERGENCE_LIST_VERBOSE_MODE" == "1" ]]; then
            echo "    ┌─ per-file divergence for $plugin_name:"
            # Awk picks out the < / > lines and shows the file paths
            echo "$per_file_divergence_diff" \
                | awk '
                    /^< / { sub(/^< /, ""); split($0, a, "\t"); print "    │   L2-only or different: " a[1] }
                    /^> / { sub(/^> /, ""); split($0, a, "\t"); print "    │   L3-only or different: " a[1] }
                '
            echo "    └─"
        fi
    fi
done

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Summary"
echo "═══════════════════════════════════════════════════════════"
echo "  Plugins scanned:                       $total_plugins_scanned"
echo "  FRESH (L2 == L3):                      $total_plugins_fresh"
echo "  STALE-CACHE (L2 != L3, drift):         $total_plugins_stale"
echo "  NOT-CACHED-LAYER-3 (not installed):    $total_plugins_not_cached"

if [[ "$total_plugins_stale" -gt 0 ]]; then
    echo ""
    echo "  ⚠  Stale plugins (operator should reinstall):"
    for stale_plugin_name in "${stale_plugins_list[@]}"; do
        echo "       - $stale_plugin_name"
    done
    echo ""
    echo "  Remediation (per stale plugin):"
    echo "     claude plugin install <plugin>@cc-skills"
    echo "  Then restart Claude Code OR invoke /reload-plugins in the active session."
    echo ""
    echo "  For per-file divergence details, re-run with --verbose."
    exit 1
fi

echo ""
echo "  ✓ All plugins FRESH (Layer 2 == Layer 3)"
echo "═══════════════════════════════════════════════════════════"
