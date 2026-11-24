#!/usr/bin/env bash
# Fail when an itp-hooks doc is missing from its index, or an orchestrator's spoke table is missing a subhook.
#
# tasks/hook-lint/spoke-coverage.sh
#
# Two lists in plugins/itp-hooks drifted from the thing they describe, silently (2026-11-23):
#   1. docs/spoke-index.md calls itself "the annotated index of every doc in this directory", yet three
#      guard spokes (chrome-debug-port, umbrella-no-repo, orca-worktree-agent) were in no index at all,
#      so nothing linked to two of them.
#   2. docs/posttooluse-write-edit-orchestrator.md says its registry "is the source of truth for this
#      table", yet the table had no row for publishing-standard-reminder, the registry's 12th entry.
# Counts in prose drifted the same way and were removed instead of checked; these two lists stay
# because each row carries information, so they are checked against what they list.
#
# Checks:
#   - every docs/*.md except spoke-index.md is linked from spoke-index.md as (./<name>.md);
#   - every name in a Write|Edit orchestrator's SUBHOOK_REGISTRY appears as `name` in its spoke.
# Exits 1 on any violation.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN="$REPO_ROOT/plugins/itp-hooks"
INDEX="$PLUGIN/docs/spoke-index.md"
violations=0

for doc in "$PLUGIN"/docs/*.md; do
    name="$(basename "$doc")"
    [ "$name" = "spoke-index.md" ] && continue
    if ! grep -qF "(./$name)" "$INDEX"; then
        echo "VIOLATION: docs/$name is not linked from docs/spoke-index.md"
        violations=$((violations + 1))
    fi
done

# The names inside one registry literal: from the line declaring <registry> to the first line that
# closes an array at the start of a line ("];" with only indentation before it).
registry_names() {
    awk -v reg="$2" '
        index($0, reg) && /=/ { inside = 1; next }
        inside && /^[[:space:]]*\];/ { exit }
        inside && match($0, /^[[:space:]]*name: "[^"]+"/) {
            line = substr($0, RSTART, RLENGTH); sub(/^[[:space:]]*name: "/, "", line); sub(/"$/, "", line); print line
        }
    ' "$1"
}

check_registry() {
    local source="$1" registry="$2" spoke="$3" count=0 missing=0 name
    while IFS= read -r name; do
        count=$((count + 1))
        if ! grep -qF "\`$name\`" "$spoke"; then
            echo "VIOLATION: $registry entry '$name' has no row in ${spoke#"$PLUGIN"/}"
            missing=$((missing + 1))
        fi
    done < <(registry_names "$source" "$registry")
    violations=$((violations + missing))
    if [ "$count" -eq 0 ]; then
        # An empty read means the parser no longer matches the registry's shape: fail loudly, never pass.
        echo "VIOLATION: found no entries in $registry (${source#"$PLUGIN"/}); this lint's parser needs updating"
        violations=$((violations + 1))
    elif [ "$missing" -eq 0 ]; then
        echo "OK: ${spoke#"$PLUGIN"/} names all $count entries of $registry"
    fi
}

check_registry "$PLUGIN/hooks/pretooluse-write-edit-orchestrator.ts" \
    PRETOOLUSE_EDIT_TIME_ORCHESTRATOR_SUBHOOK_REGISTRY "$PLUGIN/docs/pretooluse-write-edit-orchestrator.md"
check_registry "$PLUGIN/hooks/posttooluse-write-edit-orchestrator.ts" \
    POSTTOOLUSE_EDIT_TIME_ORCHESTRATOR_SUBHOOK_REGISTRY "$PLUGIN/docs/posttooluse-write-edit-orchestrator.md"

if [ "$violations" -gt 0 ]; then
    echo "spoke-coverage: $violations violation(s)"
    exit 1
fi
echo "spoke-coverage: every doc is indexed and every subhook has a row"
