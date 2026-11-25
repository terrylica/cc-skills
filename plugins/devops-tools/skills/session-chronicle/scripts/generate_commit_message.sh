#!/usr/bin/env bash
# generate_commit_message.sh - Generate a git commit message with session provenance
# Usage: ./generate_commit_message.sh <artifact_dir> <description> [related_adr]
#
# Reads the manifest.json written by extract_session_chain.sh and prints a structured
# commit message: the provenance fields, the archived files (kept locally, gitignored)
# and an optional ADR link.

set -euo pipefail

ARTIFACT_DIR="${1:-}"
DESCRIPTION="${2:-Session provenance capture}"
RELATED_ADR="${3:-}"

if [[ -z "$ARTIFACT_DIR" ]]; then
  echo "Usage: $0 <artifact_dir> <description> [related_adr]" >&2
  echo "" >&2
  echo "Arguments:" >&2
  echo "  artifact_dir   Directory containing session chronicle artifacts" >&2
  echo "  description    Short description of the finding/change" >&2
  echo "  related_adr    Related ADR slug (e.g., 2025-12-15-feature-name)" >&2
  echo "" >&2
  echo "Output: Commit message to stdout" >&2
  exit 1
fi

if [[ ! -f "$ARTIFACT_DIR/manifest.json" ]]; then
  echo "ERROR: manifest.json not found in $ARTIFACT_DIR" >&2
  exit 1
fi

MANIFEST="$ARTIFACT_DIR/manifest.json"

FILES=""
for f in "$ARTIFACT_DIR"/*.br; do
  if [[ -f "$f" ]]; then FILES="${FILES}  - $(basename "$f")"$'\n'; fi
done

printf 'feat(provenance): %s\n\nSession-Chronicle Provenance:\n' "$DESCRIPTION"
# The fields extract_session_chain.sh writes, in this order; a field the manifest lacks is left out.
jq -r '[["sessions_traced","total_sessions"],["total_lines","total_lines"],["chain_depth","chain_depth"],
        ["first_timestamp","first_timestamp"],["last_timestamp","last_timestamp"],
        ["project_path","project_path"],["compression","compression"]][] as [$label,$key]
       | select(has($key)) | "  \($label): \(.[$key])"' "$MANIFEST"

if [[ -n "$FILES" ]]; then
  printf '\nArchived sessions (local, gitignored: %s):\n%s' "$ARTIFACT_DIR" "$FILES"
fi

if [[ -n "$RELATED_ADR" ]]; then
cat << EOF

Related ADR: $RELATED_ADR
Design Spec: /docs/design/$RELATED_ADR/spec.md
EOF
fi
