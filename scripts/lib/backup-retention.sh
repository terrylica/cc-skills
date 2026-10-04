#!/usr/bin/env bash
# scripts/lib/backup-retention.sh — ONE home for the CC_SKILLS_BACKUP_RETENTION convention.
#
# The release sync scripts (sync-commands-to-settings.sh, sync-hooks-to-settings.sh) snapshot
# user files under ~/.claude/backups/ before they change them. Without a cap those snapshots grow
# without bound: 497 command snapshots / 986 MB (2026-09-01) and 772 settings.json copies / 22 MB
# (2026-10-04, issue #218) were measured on one machine. Both scripts keep the newest
# $CC_SKILLS_BACKUP_RETENTION (default 5) through this one function.
#
# Source it; do not execute it.

CC_SKILLS_BACKUP_RETENTION="${CC_SKILLS_BACKUP_RETENTION:-5}"

# prune_backup_snapshots <backup-dir> <prefix>
#
# Deletes the oldest entries named exactly <prefix><8 digits>_<6 digits> (what `date +%Y%m%d_%H%M%S`
# appends), keeping the newest $CC_SKILLS_BACKUP_RETENTION. The pattern is deliberately narrow:
# anything else a human parked under backups/ is invisible to it by construction, so a caller can
# never widen it into deleting data the scripts did not create. Prints how many it removed.
prune_backup_snapshots() {
    local dir="$1" prefix="$2"
    local -a snaps=()
    local entry
    while IFS= read -r entry; do
        [[ -n "$entry" ]] && snaps+=("$entry")
    done < <(find "$dir" -maxdepth 1 -mindepth 1 \
                  -name "${prefix}[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]" \
                  2>/dev/null | sort)

    # The timestamp sorts lexicographically == chronologically, so the oldest lead the list.
    local total=${#snaps[@]} removed=0 i
    if (( total > CC_SKILLS_BACKUP_RETENTION )); then
        removed=$(( total - CC_SKILLS_BACKUP_RETENTION ))
        for (( i = 0; i < removed; i++ )); do
            rm -rf -- "${snaps[i]}"
        done
    fi
    echo "$removed"
}
