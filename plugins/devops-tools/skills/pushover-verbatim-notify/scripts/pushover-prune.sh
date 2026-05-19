#!/usr/bin/env bash
#
# pushover-prune.sh — retention pruner for pushover-verbatim-notify JSONL audit
#
# Companion to pushover-notify.sh (writer) and pushover-lookup.sh (reader).
#
# Why this exists (iter 7, 2026-05-19):
#   - audit-YYYYMMDD.jsonl uses one-file-per-UTC-day naming, so size-based
#     rotation is irrelevant — every UTC midnight a fresh file starts.
#   - The open problem is RETENTION: old days accumulate. At a personal-fleet
#     scale of ~20 notifications/day with ~1 KB each, a year is ~7 MB — small,
#     but unbounded. Without this, the SKILL.md note "rotation not yet wired"
#     stayed true forever. With this, it becomes "retention is wired, default
#     30 days, override via env."
#
# Behavior:
#   - Default retention: 30 days (override with --keep N or env PUSHOVER_KEEP_DAYS)
#   - Default mode: dry-run (prints what WOULD be deleted). Pass --apply to delete.
#   - Never deletes today's file (current writer target).
#   - Returns the count of files deleted on stdout (machine-readable last line).
#
# Usage:
#   pushover-prune                        # dry-run, 30-day window
#   pushover-prune --keep 7               # dry-run, 7-day window
#   pushover-prune --keep 30 --apply      # actually delete
#   PUSHOVER_KEEP_DAYS=14 pushover-prune  # env override
#
# Exit codes:
#   0 = success (whether or not anything was pruned)
#   1 = parse error
#   2 = log directory missing
#

set -euo pipefail

readonly LOG_DIR="${PUSHOVER_LOG_DIR:-$HOME/.local/state/pushover}"
KEEP_DAYS="${PUSHOVER_KEEP_DAYS:-30}"
APPLY=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --keep)
            KEEP_DAYS="${2:?--keep requires a number}"
            shift 2
            ;;
        --apply)
            APPLY=1
            shift
            ;;
        --help|-h)
            /bin/cat <<'USAGE_EOF'
pushover-prune — retention pruner for ~/.local/state/pushover/audit-*.jsonl

USAGE:
  pushover-prune                     Dry-run, 30-day retention
  pushover-prune --keep N            Dry-run, N-day retention
  pushover-prune --keep N --apply    Actually delete files older than N days
  pushover-prune --help              This help

ENV:
  PUSHOVER_KEEP_DAYS  Override retention (default 30)
  PUSHOVER_LOG_DIR    Override log directory

NOTES:
  - Today's file is NEVER pruned (active writer target).
  - One file per UTC day, so "N days" = N filename-dated days.
  - Dry-run prints would-be deletions; --apply actually deletes.
USAGE_EOF
            exit 0
            ;;
        *)
            echo "pushover-prune: unknown arg: $1" >&2
            exit 1
            ;;
    esac
done

# Validate
case "$KEEP_DAYS" in
    ''|*[!0-9]*)
        echo "pushover-prune: --keep must be a non-negative integer (got: $KEEP_DAYS)" >&2
        exit 1
        ;;
esac

[ -d "$LOG_DIR" ] || { echo "pushover-prune: log dir does not exist: $LOG_DIR" >&2; exit 2; }

TODAY="$(/bin/date -u +%Y%m%d)"

# Compute cutoff date (UTC) = today minus KEEP_DAYS days
# macOS BSD date: -v-Nd; Linux GNU date: -d "N days ago"
if /bin/date -u -v-1d +%Y%m%d >/dev/null 2>&1; then
    CUTOFF="$(/bin/date -u -v-"${KEEP_DAYS}"d +%Y%m%d)"
else
    CUTOFF="$(/bin/date -u -d "${KEEP_DAYS} days ago" +%Y%m%d)"
fi

DELETED=0
KEPT=0
for f in "$LOG_DIR"/audit-*.jsonl; do
    [ -e "$f" ] || continue
    # Extract YYYYMMDD from filename
    base="$(basename "$f")"
    file_date="${base#audit-}"
    file_date="${file_date%.jsonl}"
    # Skip non-numeric (unexpected files)
    case "$file_date" in
        ''|*[!0-9]*) continue ;;
    esac
    # Never prune today's active file
    if [ "$file_date" = "$TODAY" ]; then
        KEPT=$((KEPT + 1))
        continue
    fi
    # Lexicographic comparison works because YYYYMMDD format
    if [ "$file_date" \< "$CUTOFF" ]; then
        if [ "$APPLY" -eq 1 ]; then
            /bin/rm -f -- "$f"
            echo "DELETED: $f"
        else
            echo "WOULD-DELETE: $f"
        fi
        DELETED=$((DELETED + 1))
    else
        KEPT=$((KEPT + 1))
    fi
done

if [ "$APPLY" -eq 1 ]; then
    echo "pushover-prune: deleted=$DELETED kept=$KEPT (retention=${KEEP_DAYS}d cutoff=$CUTOFF)"
else
    echo "pushover-prune: would-delete=$DELETED kept=$KEPT (retention=${KEEP_DAYS}d cutoff=$CUTOFF) — re-run with --apply to delete"
fi
