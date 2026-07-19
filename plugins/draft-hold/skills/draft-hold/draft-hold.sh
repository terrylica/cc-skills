#!/usr/bin/env bash
# draft-hold — thin shim → Bun/TypeScript engine (draft-hold.ts).
#
# The formatting logic now lives in draft-hold.ts (Bun) so the "one line per paragraph"
# contract is ENFORCED IN CODE, not left to the caller: hard-wrapped prose auto-reflows,
# Markdown lists stay per-item, and ``` fenced blocks are preserved verbatim/monospace.
# This wrapper is kept only so existing `$DH ...` call sites (and SKILL.md) keep working.
#
# Usage (unchanged):
#   draft-hold.sh new "<title>"  [--session UUID] [--project NAME] [--folder NAME]  # body on STDIN
#   draft-hold.sh get "<title>"  [--folder NAME] [--body-only]
#   draft-hold.sh list           [--folder NAME]
#   draft-hold.sh sticky "<title>" [--folder NAME]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v bun >/dev/null 2>&1 || {
  echo "draft-hold requires Bun on PATH (https://bun.sh). Install it, then retry." >&2
  exit 127
}

exec bun "$here/draft-hold.ts" "$@"
