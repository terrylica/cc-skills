#!/usr/bin/env bash
# Regression: the release sync scripts keep a bounded number of backups and never copy settings.json for a no-op (issue #218)
#
# sync-hooks-to-settings.sh used to copy ~/.claude/settings.json on every release, even when there
# was nothing to prune, and never removed the copies: 772 of them (22 MB) on one machine. It now
# touches nothing when there is nothing to prune, and when it does copy, it shares the
# CC_SKILLS_BACKUP_RETENTION cap (scripts/lib/backup-retention.sh) with sync-commands-to-settings.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS_SCRIPT="$REPO_ROOT/scripts/sync-hooks-to-settings.sh"
RETENTION_LIB="$REPO_ROOT/scripts/lib/backup-retention.sh"
FIXTURE_ROOT="$(mktemp -d -t sync-backup-retention.XXXXXX)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

CLEAN_SETTINGS='{"model":"opus","hooks":{"Stop":[{"matcher":"*","hooks":[{"type":"command","command":"bun /Users/x/.claude/other/hook.ts"}]}]}}'
DIRTY_SETTINGS='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bun /Users/x/.claude/plugins/marketplaces/cc-skills/plugins/itp-hooks/hooks/a.ts"}]}]}}'

failures=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n     %s\n' "$1" "$2"; failures=$((failures + 1)); }

new_home() {
    local home="$FIXTURE_ROOT/$1"
    mkdir -p "$home/.claude/backups"
    printf '%s' "$2" > "$home/.claude/settings.json"
    echo "$home"
}
count_backups() { find "$1/.claude/backups" -maxdepth 1 -name 'settings.json.backup.*' | wc -l | tr -d ' '; }

echo "→ release sync backup retention (issue #218)"

# 1. Nothing to prune: no copy, and the file is left byte-for-byte as it was.
home=$(new_home clean "$CLEAN_SETTINGS")
before=$(cat "$home/.claude/settings.json")
HOME="$home" "$HOOKS_SCRIPT" >/dev/null
n=$(count_backups "$home")
if [[ "$n" == "0" && "$(cat "$home/.claude/settings.json")" == "$before" ]]; then
    pass "no-op run makes no backup and leaves settings.json untouched"
else
    fail "no-op run makes no backup and leaves settings.json untouched" "backups=$n, file changed=$([[ "$(cat "$home/.claude/settings.json")" == "$before" ]] && echo no || echo yes)"
fi

# 2. Something to prune: exactly one copy, holding the pre-prune content.
home=$(new_home dirty "$DIRTY_SETTINGS")
HOME="$home" "$HOOKS_SCRIPT" >/dev/null
n=$(count_backups "$home")
copy=$(find "$home/.claude/backups" -maxdepth 1 -name 'settings.json.backup.*' | awk 'NR==1')
if [[ "$n" == "1" && "$(cat "$copy")" == "$DIRTY_SETTINGS" ]]; then
    pass "pruning run keeps one backup of the pre-prune file"
else
    fail "pruning run keeps one backup of the pre-prune file" "backups=$n"
fi

# 3. Retention: 8 old copies + the new one -> newest 5 kept; files a human parked there survive.
home=$(new_home retention "$DIRTY_SETTINGS")
for d in 01 02 03 04 05 06 07 08; do echo old > "$home/.claude/backups/settings.json.backup.202601${d}_000000"; done
echo mine > "$home/.claude/backups/settings.json.backup.keep-me"
echo mine > "$home/.claude/backups/settings.json.20260101-manual.bak"
HOME="$home" "$HOOKS_SCRIPT" >/dev/null
stamped=$(find "$home/.claude/backups" -maxdepth 1 -name 'settings.json.backup.20[0-9]*_[0-9]*' | wc -l | tr -d ' ')
oldest_gone=$([[ ! -e "$home/.claude/backups/settings.json.backup.20260104_000000" ]] && echo yes || echo no)
oldest_kept=$([[ -e "$home/.claude/backups/settings.json.backup.20260105_000000" ]] && echo yes || echo no)
human=$([[ -e "$home/.claude/backups/settings.json.backup.keep-me" && -e "$home/.claude/backups/settings.json.20260101-manual.bak" ]] && echo yes || echo no)
if [[ "$stamped" == "5" && "$oldest_gone" == "yes" && "$oldest_kept" == "yes" && "$human" == "yes" ]]; then
    pass "keeps the newest 5 timestamped copies and never touches other names"
else
    fail "keeps the newest 5 timestamped copies and never touches other names" "stamped=$stamped oldest_gone=$oldest_gone oldest_kept=$oldest_kept human_files=$human"
fi

# 4. The shared helper honours CC_SKILLS_BACKUP_RETENTION and handles the commands.* directories too.
dir="$FIXTURE_ROOT/lib-dirs"
mkdir -p "$dir"
for d in 01 02 03 04; do mkdir "$dir/commands.202601${d}_000000"; done
mkdir "$dir/commands.manual"
removed=$(CC_SKILLS_BACKUP_RETENTION=2 bash -c 'source "$1"; prune_backup_snapshots "$2" "commands."' _ "$RETENTION_LIB" "$dir")
left=$(find "$dir" -maxdepth 1 -mindepth 1 -name 'commands.2*' | wc -l | tr -d ' ')
if [[ "$removed" == "2" && "$left" == "2" && -d "$dir/commands.manual" && -d "$dir/commands.20260104_000000" ]]; then
    pass "CC_SKILLS_BACKUP_RETENTION=2 keeps the 2 newest command snapshots"
else
    fail "CC_SKILLS_BACKUP_RETENTION=2 keeps the 2 newest command snapshots" "removed=$removed left=$left"
fi

echo
if [[ $failures -eq 0 ]]; then
    echo "✓ PASSED — backups are made only when needed and stay bounded"
else
    echo "✗ FAILED — $failures case(s)"
    exit 1
fi
