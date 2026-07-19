#!/usr/bin/env bash
#MISE description="Run every git-TRACKED *.test.ts / *.test.mjs unit test in one `bun test` pass (741+ tests: itp-hooks, notes-commander, gmail-commander drafts, asciinema converter, …). Excludes exactly one file: gh-tools/gh-fine-grained-pat/test/autonomous.test.mjs, a LIVE browser+passkey integration test that needs a logged-in profile and real GitHub — it is env-dependent, not a unit regression. Tracked-files scoping (git ls-files) automatically excludes vendored node_modules copies (zod ships hundreds of its own test files). Complements test-marketplace-hook-regression-suite (which runs the *.sh regression tests); before this task existed, NO gate ran the TypeScript unit suites — they only ran when someone remembered to invoke bun test by hand (gap found 2026-07-18 while hardening draft-hold). Use before cutting a release or after touching any *.ts with a colocated test."
#
# test-marketplace-bun-unit-suite…
#
# Why tracked-files scoping instead of bun test's default discovery:
#   • `bun test` bare walks node_modules-adjacent trees in plugins/* and picks up
#     VENDORED test files (zod alone contributes ~250), plus the live browser
#     integration test that fails without a provisioned GitHub session.
#   • `git ls-files '*.test.ts' '*.test.mjs'` is the exact set of suites THIS repo
#     owns; new tests following the colocated *.test.ts convention are picked up
#     automatically — no task edit required.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# The one deliberate exclusion: live browser+passkey integration (env-dependent).
LIVE_INTEGRATION="gh-fine-grained-pat/test/autonomous"

mapfile -t FILES < <(git ls-files '*.test.ts' '*.test.mjs' | grep -v "$LIVE_INTEGRATION")

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "no tracked unit-test files found — nothing to run" >&2
  exit 1
fi

echo "═══════════════════════════════════════════════════════════"
echo "  Marketplace Bun Unit Suite (${#FILES[@]} tracked test files)"
echo "  excluded: 1 live browser integration test ($LIVE_INTEGRATION)"
echo "═══════════════════════════════════════════════════════════"

exec bun test "${FILES[@]}"
