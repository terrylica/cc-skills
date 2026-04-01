#!/usr/bin/env bash
# Sync agent-reach skill files from upstream Panniantong/Agent-Reach
# Usage: bash plugins/agent-reach/scripts/sync-upstream.sh [--dry-run]
set -euo pipefail

REPO="Panniantong/Agent-Reach"
UPSTREAM_PREFIX="agent_reach/skill"
LOCAL_DIR="plugins/agent-reach/skills/agent-reach"
DRY_RUN="${1:-}"

# Reference files to sync (same path in upstream and local)
REF_FILES="references/search.md references/social.md references/career.md references/dev.md references/web.md references/video.md"

# SKILL.md is NOT auto-synced — it has local frontmatter (allowed-tools, preflight)
# Only references are synced verbatim from upstream

cd "$(git rev-parse --show-toplevel)"

CHANGED=0
for ref_file in $REF_FILES; do
  local_file="${LOCAL_DIR}/${ref_file}"
  upstream_path="${UPSTREAM_PREFIX}/${ref_file}"

  # Fetch from GitHub API
  CONTENT=$(gh api "repos/${REPO}/contents/${upstream_path}" 2>/dev/null | jq -r '.content' | base64 -d 2>/dev/null) || {
    echo "  SKIP  ${ref_file} (fetch failed)"
    continue
  }

  if [[ -f "$local_file" ]]; then
    # Compare via diff (strip SSoT-OK header, ignore trailing whitespace)
    LOCAL_STRIPPED=$(sed '/^<!-- # SSoT-OK/d' "$local_file" | sed '/./,$!d')
    if diff -q <(printf '%s' "$LOCAL_STRIPPED") <(printf '%s' "$CONTENT") &>/dev/null; then
      echo "  OK    ${ref_file} (up to date)"
      continue
    fi
  fi

  CHANGED=$((CHANGED + 1))

  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo "  DIFF  ${ref_file} (would update)"
    continue
  fi

  # Preserve SSoT-OK header if the file needs one
  HEADER=""
  if [[ -f "$local_file" ]] && head -1 "$local_file" | grep -q 'SSoT-OK'; then
    HEADER=$(head -1 "$local_file")$'\n\n'
  fi

  mkdir -p "$(dirname "$local_file")"
  printf '%s%s\n' "$HEADER" "$CONTENT" > "$local_file"
  echo "  SYNC  ${ref_file}"
done

if [[ $CHANGED -eq 0 ]]; then
  echo "All reference files up to date with ${REPO}."
else
  echo "${CHANGED} file(s) updated from ${REPO}."
fi
