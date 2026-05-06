#!/usr/bin/env bash
# Cleanly remove openwolf from the current project. Idempotent.
# Mirrors openwolf's own replaceOpenWolfHooks merge logic (filter by ".wolf/hooks/" substring).

set -u  # NOT -e — every step is allowed to "already absent"; we report per-step.

PROJECT_ROOT="$(pwd)"
PROJECT_BASE="$(basename "$PROJECT_ROOT")"

echo "openwolf-remove: target = $PROJECT_ROOT"

# ─── 1. PM2 daemon (optional, fails silently if pm2 absent) ──────────────────
if command -v pm2 >/dev/null 2>&1; then
  if pm2 describe "openwolf-$PROJECT_BASE" >/dev/null 2>&1; then
    pm2 delete "openwolf-$PROJECT_BASE" >/dev/null 2>&1 && echo "  ✓ pm2: deleted openwolf-$PROJECT_BASE"
    pm2 save >/dev/null 2>&1 || true
  else
    echo "  · pm2: no openwolf-$PROJECT_BASE process"
  fi
else
  echo "  · pm2: not installed (skipping)"
fi

# ─── 2. .wolf/ directory ─────────────────────────────────────────────────────
if [ -d "$PROJECT_ROOT/.wolf" ]; then
  rm -rf "$PROJECT_ROOT/.wolf" && echo "  ✓ removed .wolf/"
else
  echo "  · .wolf/ already absent"
fi

# ─── 3. .claude/rules/openwolf.md ────────────────────────────────────────────
if [ -f "$PROJECT_ROOT/.claude/rules/openwolf.md" ]; then
  rm -f "$PROJECT_ROOT/.claude/rules/openwolf.md" && echo "  ✓ removed .claude/rules/openwolf.md"
  # Remove .claude/rules if empty
  rmdir "$PROJECT_ROOT/.claude/rules" 2>/dev/null && echo "  ✓ removed empty .claude/rules/"
else
  echo "  · .claude/rules/openwolf.md already absent"
fi

# ─── 4. .claude/settings.json — strip hooks whose command contains .wolf/hooks/
SETTINGS="$PROJECT_ROOT/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
  if command -v jq >/dev/null 2>&1 && grep -q '\.wolf/hooks/' "$SETTINGS"; then
    TMP="$(mktemp)"
    # For each event, keep only matchers whose .hooks[] commands do NOT contain ".wolf/hooks/".
    # Then drop empty hook event arrays. Preserves all unrelated top-level keys.
    jq '
      if .hooks then
        .hooks = (
          .hooks
          | to_entries
          | map(
              .value |= map(
                select(
                  ([.hooks[]?.command // ""] | map(contains(".wolf/hooks/")) | any) | not
                )
              )
            )
          | map(select(.value | length > 0))
          | from_entries
        )
        | (if (.hooks | length) == 0 then del(.hooks) else . end)
      else . end
    ' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS" && echo "  ✓ stripped openwolf hooks from .claude/settings.json"
  elif grep -q '\.wolf/hooks/' "$SETTINGS"; then
    echo "  ✗ jq not installed — cannot safely edit settings.json. Install jq or edit manually."
    echo "    Pattern to remove: any hook entry whose 'command' field contains '.wolf/hooks/'"
  else
    echo "  · .claude/settings.json: no .wolf/hooks/ references"
  fi
else
  echo "  · .claude/settings.json absent"
fi

# ─── 5. CLAUDE.md — strip the openwolf snippet ───────────────────────────────
# Snippet (225 bytes, no trailing newline) is prepended via:
#   writeText(claudeMdPath, snippetContent + "\n\n" + existing)
# So in-file the block looks like:
#   # OpenWolf
#   <blank>
#   @.wolf/OPENWOLF.md
#   <blank>
#   This project uses OpenWolf for context management. Read and follow .wolf/OPENWOLF.md every session. Check .wolf/cerebrum.md before generating code. Check .wolf/anatomy.md before reading files.
#   <blank>
#   <blank>
#   <rest of original file>
CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
if [ -f "$CLAUDE_MD" ] && grep -q '@\.wolf/OPENWOLF\.md' "$CLAUDE_MD"; then
  TMP="$(mktemp)"
  # Use awk to drop a contiguous block: from line "# OpenWolf" through the line
  # "Check .wolf/anatomy.md before reading files." plus up to 2 trailing blank lines.
  awk '
    BEGIN { skip = 0; trailing_blanks = 0 }
    !skip && /^# OpenWolf$/ { skip = 1; next }
    skip && /^Check \.wolf\/anatomy\.md before reading files\.$/ {
      skip = 0
      trailing_blanks = 2
      next
    }
    skip { next }
    trailing_blanks > 0 && /^$/ { trailing_blanks--; next }
    { trailing_blanks = 0; print }
  ' "$CLAUDE_MD" > "$TMP" && mv "$TMP" "$CLAUDE_MD" && echo "  ✓ stripped openwolf snippet from CLAUDE.md"
  # If CLAUDE.md is now empty (openwolf created it), remove it
  if [ ! -s "$CLAUDE_MD" ]; then
    rm -f "$CLAUDE_MD" && echo "  ✓ removed empty CLAUDE.md"
  fi
else
  echo "  · CLAUDE.md: no openwolf snippet"
fi

# ─── 6. ~/.openwolf/registry.json — unregister this project ──────────────────
REG="$HOME/.openwolf/registry.json"
if [ -f "$REG" ] && command -v jq >/dev/null 2>&1; then
  HERE_NORM="$(printf '%s' "$PROJECT_ROOT" | sed 's|\\|/|g' | tr '[:upper:]' '[:lower:]')"
  if jq -e --arg here "$HERE_NORM" '.projects[]? | select((.root | gsub("\\\\";"/") | ascii_downcase) == $here)' "$REG" >/dev/null 2>&1; then
    TMP="$(mktemp)"
    jq --arg here "$HERE_NORM" '
      .projects |= map(select((.root | gsub("\\\\";"/") | ascii_downcase) != $here))
    ' "$REG" > "$TMP" && mv "$TMP" "$REG" && echo "  ✓ unregistered from ~/.openwolf/registry.json"
  else
    echo "  · registry: no entry for this project"
  fi
else
  echo "  · registry: ${REG} absent or jq missing"
fi

echo "openwolf-remove: done."
