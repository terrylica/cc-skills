#!/usr/bin/env bash
# Offline link check over every tracked markdown file: relative paths, root-relative paths and anchors. Deterministic and network-free by design, so it can eventually gate. External URL liveness is NOT checked here — see link-check-external.

# ─────────────────────────────────────────────────────────────────────────────
# Why this exists, and why it is OFFLINE
# ─────────────────────────────────────────────────────────────────────────────
#
# Until 2026-09-03 nothing in this repo ever ran a link check. `lychee.toml`
# existed, `plugins/link-tools/` shipped a 495-line stop-link-check.py, and
# neither was reachable: link-tools has no hooks.json, and `lychee` appeared zero
# times in moon.yml and zero times in tasks/. The config was ALSO broken — lychee
# 0.24 turned `include_fragments` from a bool into an enum, so every invocation
# died at config load — but that was the smaller problem. A checker nothing calls
# does not need to work.
#
# That is the THIRD occurrence of this class here. moon.yml's own `check` task
# carries the comment "A gate that is not in the gate is not a gate", four lines
# above a deps list that did not include link checking.
#
# OFFLINE IS DELIBERATE. External URL liveness depends on the network, on remote
# sites' uptime, and on rate limits — it produces red runs for reasons that have
# nothing to do with this repository. That is the phantom-red class that was just
# removed from the perf tests, and importing it into the docs gate would repeat
# the mistake in a new place. Internal links are a pure function of the tree:
# same bytes, same verdict, every time, in milliseconds.

set -euo pipefail

# --root-dir resolves the repo-root-relative links (`/docs/adr/x.md`) that this
# repo's own link convention prescribes. Without it lychee reports every one of
# them as an error — 417 rather than the true 235, an inflation of ~77% that
# would have been reported as broken links.
#
# --git-common-dir, not --show-toplevel, is NOT needed here: we want the WORKING
# tree root, which --show-toplevel gives correctly inside a worktree too.
LINK_CHECK_REPOSITORY_ROOT_ABSOLUTE_PATH="$(git rev-parse --show-toplevel)"
cd "$LINK_CHECK_REPOSITORY_ROOT_ABSOLUTE_PATH"

# Fixtures that contain deliberately-invalid links so a test can assert they are
# caught. Excluding them is not weakening the check; including them would mean
# asserting that intentionally-broken fixtures are unbroken.
LINK_CHECK_DELIBERATE_VIOLATION_FIXTURE_PATHS=(
    "plugins/statusline-tools/tests/fixtures"
)

exclude_args=()
for fixture_path in "${LINK_CHECK_DELIBERATE_VIOLATION_FIXTURE_PATHS[@]}"; do
    exclude_args+=(--exclude-path "$fixture_path")
done

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Offline link check (internal links only — no network)"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

LINK_CHECK_EXIT_CODE=0
bunx lychee \
    --config lychee.toml \
    --offline \
    --no-progress \
    --root-dir "$LINK_CHECK_REPOSITORY_ROOT_ABSOLUTE_PATH" \
    "${exclude_args[@]}" \
    './**/*.md' || LINK_CHECK_EXIT_CODE=$?

echo ""
if [[ "$LINK_CHECK_EXIT_CODE" -eq 0 ]]; then
    echo "  ✓ every internal link resolves"
else
    echo "  ✗ broken internal links found (lychee exit $LINK_CHECK_EXIT_CODE)"
    echo ""
    echo "  NOT YET WIRED INTO \`moon run repo:check\`. Measured 2026-09-03 on a"
    echo "  clean tree: 235 errors across 2,119 unique internal links. Adding a"
    echo "  red gate to the gate would block every commit in the repo, so the"
    echo "  count is being driven down first — tracked as a repo issue. Wire this"
    echo "  into check.deps the moment it reaches zero, and not before."
fi

exit "$LINK_CHECK_EXIT_CODE"
