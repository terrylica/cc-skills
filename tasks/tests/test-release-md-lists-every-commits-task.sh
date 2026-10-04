#!/usr/bin/env bash
# Regression: docs/RELEASE.md names every conventional-commits moon task, derived from moon.yml (issue #222)
#
# The previous guard (test-iter168) pinned the old toolkit index word for word: an iteration-range
# header, "11 operator-facing tools", a 5.17x speedup figure. That kept history in the guide and
# still missed a real task: repo:commits-perf-baseline was in moon.yml and in neither version of the
# doc. This test reads the task list from moon.yml, so a new commits task is covered the day it
# lands and no number or wording is pinned.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MOON_YML="$REPO_ROOT/moon.yml"
RELEASE_MD="$REPO_ROOT/docs/RELEASE.md"

tasks=()
while IFS= read -r t; do
    [[ -n "$t" ]] && tasks+=("$t")
done < <(grep -oE '^  (commits-[a-z0-9-]+|release-history):' "$MOON_YML" | tr -d ' :')

echo "→ docs/RELEASE.md names every conventional-commits moon task (issue #222)"

# Cannot pass vacuously: zero tasks means moon.yml's layout moved, not that the doc is complete.
if (( ${#tasks[@]} == 0 )); then
    echo "  ✗ found no commits-* or release-history task in moon.yml; the pattern no longer matches"
    exit 2
fi

missing=0
for t in "${tasks[@]}"; do
    if grep -qF "repo:$t" "$RELEASE_MD"; then
        echo "  ✓ repo:$t"
    else
        echo "  ✗ repo:$t is a moon task but docs/RELEASE.md does not name it"
        missing=$((missing + 1))
    fi
done

echo
if (( missing == 0 )); then
    echo "✓ PASSED — all ${#tasks[@]} tasks documented"
else
    echo "✗ FAILED — $missing of ${#tasks[@]} tasks undocumented"
    exit 1
fi
