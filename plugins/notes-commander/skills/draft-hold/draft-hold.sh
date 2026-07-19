#!/usr/bin/env bash
# draft-hold — thin shim → Bun/TypeScript engine (scripts/draft-hold.ts, notes-commander plugin).
#
# Formatting + hardening live in the shared notes-core engine: prose auto-reflows, lists stay
# per-item, ``` fences verbatim; creation verifies a real note id came back (macOS 26 silent
# no-op guard), transient AppleEvent errors retry, and `new` read-back-verifies the save.
# This wrapper exists so `$DH ...` call sites (and SKILL.md) keep working after the migration
# from the standalone draft-hold plugin (2026-07-18).
#
# Usage (unchanged):
#   draft-hold.sh new "<title>"  [--session UUID] [--project NAME] [--folder NAME] [--no-verify]  # body on STDIN
#   draft-hold.sh get "<title>"  [--folder NAME] [--body-only]
#   draft-hold.sh list           [--folder NAME]
#   draft-hold.sh sticky "<title>" [--folder NAME]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v bun >/dev/null 2>&1 || {
  echo "draft-hold requires Bun on PATH (https://bun.sh). Install it, then retry." >&2
  exit 127
}

# Engine resolution across cache layers: the relative path works in-repo AND in the Layer-2
# marketplace mirror (both are full copies). The Layer-3 operator cache strips scripts/, so
# fall back to the L2 mirror path there (same pattern as gmail-commander).
eng="$here/../../scripts/draft-hold.ts"
if [[ ! -f "$eng" ]]; then
  eng="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/notes-commander/scripts/draft-hold.ts"
fi
[[ -f "$eng" ]] || {
  echo "draft-hold engine not found (searched plugin scripts/ and the cc-skills marketplace mirror)." >&2
  exit 127
}

exec bun "$eng" "$@"
