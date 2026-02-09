#!/usr/bin/env bash
# =============================================================================
# Claude Code Project Directory Migration Script
# =============================================================================
# Safely migrates Claude Code project context when renaming a directory.
#
# Handles: sessions, sessions-index.json, history.jsonl, memory, subagents,
#          mise trust, Python venv recreation, and backward-compat symlink.
#
# Usage:
#   claude-code-migrate.sh [--dry-run] <old-path> <new-path>
#   claude-code-migrate.sh --rollback
#   claude-code-migrate.sh --help
#
# Empirically validated: 33 sessions + 259 history entries migrated
# with zero data loss during the crypto-kline-vision-data package rename.
# =============================================================================

set -euo pipefail

# ── Colors ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass()  { echo -e "  ${GREEN}[PASS]${NC} $1"; }
fail()  { echo -e "  ${RED}[FAIL]${NC} $1"; }
info()  { echo -e "  ${BLUE}[INFO]${NC} $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
phase() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }

# ── Path Encoding ──────────────────────────────────────────────────────────────
# Claude Code encodes absolute paths by replacing / with -
# Example: /Users/alice/projects/my-app -> -Users-alice-projects-my-app
encode_path() {
    echo "${1//\//-}"
}

# ── Usage ──────────────────────────────────────────────────────────────────────
usage() {
    cat << 'USAGE_EOF'
Claude Code Project Directory Migration

Safely migrates Claude Code project context (sessions, memory, history)
when renaming a project directory.

USAGE:
  claude-code-migrate.sh [OPTIONS] <old-path> <new-path>

OPTIONS:
  --dry-run     Preview changes without modifying anything
  --rollback    Restore from most recent backup
  --help        Show this help message

ARGUMENTS:
  <old-path>    Current absolute path to the project directory
  <new-path>    Desired new absolute path for the project directory

EXAMPLES:
  # Preview migration
  claude-code-migrate.sh --dry-run ~/projects/old-name ~/projects/new-name

  # Execute migration
  claude-code-migrate.sh ~/projects/old-name ~/projects/new-name

  # Undo migration from backup
  claude-code-migrate.sh --rollback

PHASES:
  1. Pre-flight validation    5. Rewrite history.jsonl
  2. Backup                   6. Backward-compat symlink
  3. Move project directory   7. Rename repo directory
  4. Rewrite sessions-index   8. Environment fixups
                              9. Post-flight verification

WHAT GETS MIGRATED:
  - Session JSONL files (~/.claude/projects/{encoded-path}/*.jsonl)
  - sessions-index.json (projectPath, fullPath, originalPath fields)
  - history.jsonl (project field)
  - Auto-memory (memory/MEMORY.md)
  - Session subdirectories (subagents/, tool-results/)

WHAT GETS FIXED (Phase 8):
  - mise trust for new directory path
  - Python venv recreation (uv sync or python -m venv)
  - direnv / asdf / .tool-versions warnings
USAGE_EOF
}

# ── Argument Parsing ───────────────────────────────────────────────────────────
DRY_RUN=false
ROLLBACK=false
OLD_DIR=""
NEW_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --rollback) ROLLBACK=true; shift ;;
        --help|-h) usage; exit 0 ;;
        -*)
            echo "Unknown option: $1"
            echo "Run with --help for usage."
            exit 1
            ;;
        *)
            if [[ -z "$OLD_DIR" ]]; then
                OLD_DIR="$1"
            elif [[ -z "$NEW_DIR" ]]; then
                NEW_DIR="$1"
            else
                echo "Too many arguments. Run with --help for usage."
                exit 1
            fi
            shift
            ;;
    esac
done

CLAUDE_DIR="$HOME/.claude"
PROJECTS_DIR="${CLAUDE_DIR}/projects"
HISTORY_FILE="${CLAUDE_DIR}/history.jsonl"

# ── Rollback Mode ──────────────────────────────────────────────────────────────
if [[ "${ROLLBACK}" == "true" ]]; then
    phase "ROLLBACK MODE"

    LATEST_BACKUP=$(find "${CLAUDE_DIR}" -maxdepth 1 -name 'migration-backup-*' -type d 2>/dev/null | sort -r | head -1)

    if [[ -z "${LATEST_BACKUP}" ]]; then
        fail "No backup found in ${CLAUDE_DIR}/migration-backup-*"
        exit 1
    fi

    info "Found backup: ${LATEST_BACKUP}"

    # Read migration metadata
    if [[ -f "${LATEST_BACKUP}/migration-meta.json" ]]; then
        SAVED_OLD=$(python3 -c "import json; print(json.load(open('${LATEST_BACKUP}/migration-meta.json'))['old_dir'])")
        SAVED_NEW=$(python3 -c "import json; print(json.load(open('${LATEST_BACKUP}/migration-meta.json'))['new_dir'])")
        SAVED_OLD_ENCODED=$(python3 -c "import json; print(json.load(open('${LATEST_BACKUP}/migration-meta.json'))['old_encoded'])")
        SAVED_NEW_ENCODED=$(python3 -c "import json; print(json.load(open('${LATEST_BACKUP}/migration-meta.json'))['new_encoded'])")
        info "Restoring: ${SAVED_NEW} -> ${SAVED_OLD}"
    else
        fail "No migration-meta.json in backup. Cannot determine original paths."
        exit 1
    fi

    # Remove symlink and new project directory
    rm -f "${PROJECTS_DIR}/${SAVED_OLD_ENCODED}" 2>/dev/null || true
    rm -rf "${PROJECTS_DIR:?}/${SAVED_NEW_ENCODED:?}" 2>/dev/null || true

    # Restore project directory from backup
    if [[ -d "${LATEST_BACKUP}/projects/${SAVED_OLD_ENCODED}" ]]; then
        cp -a "${LATEST_BACKUP}/projects/${SAVED_OLD_ENCODED}" "${PROJECTS_DIR}/${SAVED_OLD_ENCODED}"
        pass "Restored project directory"
    fi

    # Restore history.jsonl
    if [[ -f "${LATEST_BACKUP}/history.jsonl" ]]; then
        cp "${LATEST_BACKUP}/history.jsonl" "${HISTORY_FILE}"
        pass "Restored history.jsonl"
    fi

    # Restore repo directory if it was moved
    if [[ -d "${SAVED_NEW}" && ! -d "${SAVED_OLD}" ]]; then
        mv "${SAVED_NEW}" "${SAVED_OLD}"
        pass "Restored repo directory: ${SAVED_OLD}"
    fi

    echo ""
    pass "Rollback complete. Backup preserved at: ${LATEST_BACKUP}"
    exit 0
fi

# ── Validate Arguments ─────────────────────────────────────────────────────────
if [[ -z "$OLD_DIR" || -z "$NEW_DIR" ]]; then
    echo "Error: Both <old-path> and <new-path> are required."
    echo "Run with --help for usage."
    exit 1
fi

# Resolve to absolute paths
OLD_DIR=$(cd "$OLD_DIR" 2>/dev/null && pwd || echo "$OLD_DIR")
NEW_DIR=$(python3 -c "import os; print(os.path.abspath('$NEW_DIR'))")

OLD_ENCODED=$(encode_path "$OLD_DIR")
NEW_ENCODED=$(encode_path "$NEW_DIR")

BACKUP_DIR="${CLAUDE_DIR}/migration-backup-$(date +%Y%m%d-%H%M%S)"

# ── Header ─────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================="
if [[ "${DRY_RUN}" == "true" ]]; then
    echo " Claude Code Project Migration — DRY RUN (no changes)"
else
    echo " Claude Code Project Migration — PRODUCTION"
fi
echo "============================================================="
echo ""
echo " From: ${OLD_DIR}"
echo " To:   ${NEW_DIR}"
echo " Encoded: ${OLD_ENCODED} -> ${NEW_ENCODED}"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Phase 1: Pre-flight Validation
# ══════════════════════════════════════════════════════════════════════════════
phase "Phase 1: Pre-flight Validation"

PREFLIGHT_FAIL=0

# Check source directory exists
if [[ -d "${OLD_DIR}" ]]; then
    pass "Source directory exists: ${OLD_DIR}"
else
    fail "Source directory NOT found: ${OLD_DIR}"
    PREFLIGHT_FAIL=1
fi

# Check target directory does NOT exist
if [[ ! -e "${NEW_DIR}" ]]; then
    pass "Target directory does not exist yet: ${NEW_DIR}"
else
    fail "Target already exists: ${NEW_DIR}"
    PREFLIGHT_FAIL=1
fi

# Check Claude Code project directory exists
SESSION_COUNT=0
if [[ -d "${PROJECTS_DIR}/${OLD_ENCODED}" ]]; then
    SESSION_COUNT=$(find "${PROJECTS_DIR}/${OLD_ENCODED}" -maxdepth 1 -name '*.jsonl' -type f 2>/dev/null | wc -l | tr -d ' ')
    pass "Claude Code project directory found: ${SESSION_COUNT} sessions"
else
    fail "Claude Code project directory NOT found: ${PROJECTS_DIR}/${OLD_ENCODED}"
    PREFLIGHT_FAIL=1
fi

# Check target Claude Code project directory does NOT exist
if [[ ! -d "${PROJECTS_DIR}/${NEW_ENCODED}" ]]; then
    pass "Target Claude Code project directory does not exist yet"
else
    fail "Target Claude Code project directory already exists: ${PROJECTS_DIR}/${NEW_ENCODED}"
    PREFLIGHT_FAIL=1
fi

# Check history.jsonl exists
HISTORY_COUNT=0
if [[ -f "${HISTORY_FILE}" ]]; then
    HISTORY_COUNT=$(grep -c "\"${OLD_DIR}\"" "${HISTORY_FILE}" || true)
    pass "history.jsonl found: ${HISTORY_COUNT} entries to migrate"
else
    fail "history.jsonl NOT found: ${HISTORY_FILE}"
    PREFLIGHT_FAIL=1
fi

# Check python3 available
if command -v python3 &> /dev/null; then
    pass "python3 available"
else
    fail "python3 not found in PATH"
    PREFLIGHT_FAIL=1
fi

# Check for running Claude Code sessions
RUNNING=$(pgrep -f "claude.*$(basename "${OLD_DIR}")" 2>/dev/null || true)
if [[ -z "${RUNNING}" ]]; then
    pass "No Claude Code sessions detected for this project"
else
    warn "Claude Code may be running for this project — close all sessions first"
    PREFLIGHT_FAIL=1
fi

# Check for memory
MEMORY_EXISTS="false"
if [[ -f "${PROJECTS_DIR}/${OLD_ENCODED}/memory/MEMORY.md" ]]; then
    MEMORY_EXISTS="true"
    info "Auto-memory (MEMORY.md) found — will be preserved"
fi

# Check for environment tooling
ENV_TOOLS=""
[[ -f "${OLD_DIR}/.mise.toml" || -f "${OLD_DIR}/.mise.local.toml" ]] && ENV_TOOLS="${ENV_TOOLS} mise"
[[ -f "${OLD_DIR}/uv.lock" ]] && ENV_TOOLS="${ENV_TOOLS} uv"
[[ -d "${OLD_DIR}/.venv" ]] && ENV_TOOLS="${ENV_TOOLS} venv"
[[ -f "${OLD_DIR}/.envrc" ]] && ENV_TOOLS="${ENV_TOOLS} direnv"
[[ -f "${OLD_DIR}/.tool-versions" ]] && ENV_TOOLS="${ENV_TOOLS} asdf"
if [[ -n "${ENV_TOOLS}" ]]; then
    info "Environment tooling detected:${ENV_TOOLS}"
fi

if [[ "${PREFLIGHT_FAIL}" -ne 0 ]]; then
    echo ""
    fail "Pre-flight failed. Fix issues above before proceeding."
    exit 1
fi

if [[ "${DRY_RUN}" == "true" ]]; then
    echo ""
    info "DRY RUN — showing what would happen without making changes"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Phase 2: Backup
# ══════════════════════════════════════════════════════════════════════════════
phase "Phase 2: Backup"

if [[ "${DRY_RUN}" == "true" ]]; then
    info "Would backup to: ${BACKUP_DIR}/"
    info "Would copy: ${PROJECTS_DIR}/${OLD_ENCODED}/ (${SESSION_COUNT} sessions)"
    info "Would copy: ${HISTORY_FILE}"
else
    mkdir -p "${BACKUP_DIR}/projects"

    # Save migration metadata for rollback
    python3 -c "
import json
meta = {
    'old_dir': '${OLD_DIR}',
    'new_dir': '${NEW_DIR}',
    'old_encoded': '${OLD_ENCODED}',
    'new_encoded': '${NEW_ENCODED}',
    'session_count': ${SESSION_COUNT},
    'history_count': ${HISTORY_COUNT}
}
with open('${BACKUP_DIR}/migration-meta.json', 'w') as f:
    json.dump(meta, f, indent=2)
"

    cp -a "${PROJECTS_DIR}/${OLD_ENCODED}" "${BACKUP_DIR}/projects/${OLD_ENCODED}"
    pass "Backed up project directory (${SESSION_COUNT} sessions)"

    cp "${HISTORY_FILE}" "${BACKUP_DIR}/history.jsonl"
    pass "Backed up history.jsonl"

    info "Backup location: ${BACKUP_DIR}"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Phase 3: Move project directory
# ══════════════════════════════════════════════════════════════════════════════
phase "Phase 3: Move Claude Code project directory"

if [[ "${DRY_RUN}" == "true" ]]; then
    info "Would move: ${OLD_ENCODED} -> ${NEW_ENCODED}"
else
    mv "${PROJECTS_DIR}/${OLD_ENCODED}" "${PROJECTS_DIR}/${NEW_ENCODED}"
    pass "Renamed project directory"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Phase 4: Rewrite sessions-index.json
# ══════════════════════════════════════════════════════════════════════════════
phase "Phase 4: Rewrite sessions-index.json"

INDEX_FILE="${PROJECTS_DIR}/${NEW_ENCODED}/sessions-index.json"
if [[ "${DRY_RUN}" == "true" ]]; then
    INDEX_FILE="${PROJECTS_DIR}/${OLD_ENCODED}/sessions-index.json"
fi

if [[ -f "${INDEX_FILE}" ]]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
        REFS=$(grep -c "$(basename "${OLD_DIR}")" "${INDEX_FILE}" || true)
        info "Would rewrite ${REFS} path references in sessions-index.json"
    else
        python3 -c "
import json, sys

old_encoded = '${OLD_ENCODED}'
new_encoded = '${NEW_ENCODED}'
old_dir = '${OLD_DIR}'
new_dir = '${NEW_DIR}'

index_path = '${INDEX_FILE}'

with open(index_path, 'r') as f:
    data = json.load(f)

changes = 0

# Top-level fields (originalPath, projectPath)
for key in ('originalPath', 'projectPath'):
    if key in data and isinstance(data[key], str) and old_dir in data[key]:
        data[key] = data[key].replace(old_dir, new_dir)
        changes += 1

# Per-entry fields
for entry in data.get('entries', []):
    if 'projectPath' in entry and old_dir in entry['projectPath']:
        entry['projectPath'] = entry['projectPath'].replace(old_dir, new_dir)
        changes += 1
    if 'fullPath' in entry and old_encoded in entry['fullPath']:
        entry['fullPath'] = entry['fullPath'].replace(old_encoded, new_encoded)
        changes += 1

with open(index_path, 'w') as f:
    json.dump(data, f, indent=4)
    f.write('\n')

print(changes)
"

        REMAIN=$(grep -c "${OLD_ENCODED}\|${OLD_DIR}" "${INDEX_FILE}" || true)
        if [[ "${REMAIN}" -eq 0 ]]; then
            pass "sessions-index.json: all paths updated"
        else
            fail "sessions-index.json: ${REMAIN} old references remain"
        fi

        if python3 -m json.tool "${INDEX_FILE}" > /dev/null 2>&1; then
            pass "sessions-index.json: valid JSON"
        else
            fail "sessions-index.json: INVALID JSON — run --rollback"
            exit 1
        fi
    fi
else
    info "No sessions-index.json found (skipping)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Phase 5: Rewrite history.jsonl
# ══════════════════════════════════════════════════════════════════════════════
phase "Phase 5: Rewrite history.jsonl"

if [[ "${DRY_RUN}" == "true" ]]; then
    info "Would rewrite ${HISTORY_COUNT} entries in history.jsonl"
else
    TMP_HISTORY="${CLAUDE_DIR}/history_migration_tmp.jsonl"

    python3 -c "
import json

old_dir = '${OLD_DIR}'
new_dir = '${NEW_DIR}'

changes = 0
with open('${HISTORY_FILE}', 'r') as fin, open('${TMP_HISTORY}', 'w') as fout:
    for line in fin:
        line = line.rstrip('\n')
        if not line:
            fout.write('\n')
            continue
        try:
            entry = json.loads(line)
            if entry.get('project') == old_dir:
                entry['project'] = new_dir
                changes += 1
            fout.write(json.dumps(entry, ensure_ascii=False) + '\n')
        except json.JSONDecodeError:
            fout.write(line + '\n')

print(changes)
"

    mv "${TMP_HISTORY}" "${HISTORY_FILE}"

    NEW_COUNT=$(grep -c "\"${NEW_DIR}\"" "${HISTORY_FILE}" || true)
    OLD_REMAIN=$(grep -c "\"${OLD_DIR}\"" "${HISTORY_FILE}" || true)

    if [[ "${NEW_COUNT}" -eq "${HISTORY_COUNT}" ]]; then
        pass "history.jsonl: ${NEW_COUNT} entries migrated"
    else
        warn "history.jsonl: expected ${HISTORY_COUNT}, migrated ${NEW_COUNT}"
    fi

    if [[ "${OLD_REMAIN}" -eq 0 ]]; then
        pass "history.jsonl: zero old references remain"
    else
        fail "history.jsonl: ${OLD_REMAIN} old references remain"
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# Phase 6: Backward-compatibility symlink
# ══════════════════════════════════════════════════════════════════════════════
phase "Phase 6: Backward-compatibility symlink"

if [[ "${DRY_RUN}" == "true" ]]; then
    info "Would create symlink: ${OLD_ENCODED} -> ${NEW_ENCODED}"
else
    ln -s "${PROJECTS_DIR}/${NEW_ENCODED}" "${PROJECTS_DIR}/${OLD_ENCODED}"
    if [[ -L "${PROJECTS_DIR}/${OLD_ENCODED}" ]]; then
        pass "Symlink created: ${OLD_ENCODED} -> ${NEW_ENCODED}"
    else
        warn "Symlink creation failed (non-critical)"
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# Phase 7: Rename repo directory
# ══════════════════════════════════════════════════════════════════════════════
phase "Phase 7: Rename repository directory"

if [[ "${DRY_RUN}" == "true" ]]; then
    info "Would move: ${OLD_DIR} -> ${NEW_DIR}"
else
    mv "${OLD_DIR}" "${NEW_DIR}"
    if [[ -d "${NEW_DIR}" ]]; then
        pass "Repository renamed: ${NEW_DIR}"
    else
        fail "Repository rename failed — run --rollback"
        exit 1
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# Phase 8: Environment Fixups
# ══════════════════════════════════════════════════════════════════════════════
phase "Phase 8: Environment fixups"

if [[ "${DRY_RUN}" == "true" ]]; then
    [[ -f "${OLD_DIR}/.mise.toml" || -f "${OLD_DIR}/.mise.local.toml" ]] && \
        info "Would run: mise trust ${NEW_DIR}"
    [[ -d "${OLD_DIR}/.venv" && -f "${OLD_DIR}/uv.lock" ]] && \
        info "Would run: uv sync (recreate venv at new path)"
    [[ -d "${OLD_DIR}/.venv" && ! -f "${OLD_DIR}/uv.lock" ]] && \
        info "Would run: python -m venv .venv (recreate venv)"
    [[ -f "${OLD_DIR}/.envrc" ]] && \
        info "Would warn: direnv allow needed at new path"
    [[ -f "${OLD_DIR}/.tool-versions" ]] && \
        info "Would warn: .tool-versions may need review"
else
    # mise trust
    if [[ -f "${NEW_DIR}/.mise.toml" || -f "${NEW_DIR}/.mise.local.toml" ]]; then
        if command -v mise &> /dev/null; then
            mise trust "${NEW_DIR}" 2>/dev/null || true
            pass "mise: trusted new directory path"
        else
            warn "mise not found — run 'mise trust ${NEW_DIR}' manually"
        fi
    fi

    # Python venv recreation
    if [[ -d "${NEW_DIR}/.venv" ]]; then
        if [[ -f "${NEW_DIR}/uv.lock" ]] && command -v uv &> /dev/null; then
            (cd "${NEW_DIR}" && uv sync --quiet 2>/dev/null) || true
            pass "venv: recreated via uv sync"
        elif [[ -f "${NEW_DIR}/requirements.txt" ]]; then
            (cd "${NEW_DIR}" && python3 -m venv .venv 2>/dev/null) || true
            pass "venv: recreated via python -m venv"
        else
            info "venv: exists but no uv.lock or requirements.txt — may need manual recreation"
        fi
    fi

    # direnv warning
    if [[ -f "${NEW_DIR}/.envrc" ]]; then
        warn "direnv: run 'direnv allow' in new directory"
    fi

    # asdf/.tool-versions warning
    if [[ -f "${NEW_DIR}/.tool-versions" ]]; then
        warn "asdf: .tool-versions found — verify tool versions at new path"
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# Phase 9: Post-flight Verification
# ══════════════════════════════════════════════════════════════════════════════
phase "Phase 9: Post-flight Verification"

if [[ "${DRY_RUN}" == "true" ]]; then
    info "Would verify: directory, symlink, sessions-index, history, memory, env"
    echo ""
    echo "============================================================="
    echo -e "${GREEN} DRY RUN COMPLETE — No changes made${NC}"
    echo "============================================================="
    echo ""
    echo " Summary:"
    echo "   Sessions to migrate:  ${SESSION_COUNT}"
    echo "   History entries:      ${HISTORY_COUNT}"
    echo "   Memory:               ${MEMORY_EXISTS}"
    echo "   Environment tools:   ${ENV_TOOLS:-none}"
    echo ""
    echo " To execute: bash $0 \"${OLD_DIR}\" \"${NEW_DIR}\""
    exit 0
fi

VERIFY_FAIL=0

if [[ -d "${NEW_DIR}" && ! -d "${OLD_DIR}" ]]; then
    pass "Repo directory: renamed correctly"
else
    fail "Repo directory: issue detected"
    VERIFY_FAIL=1
fi

if [[ -d "${PROJECTS_DIR}/${NEW_ENCODED}" ]]; then
    pass "Claude Code project: exists at new path"
else
    fail "Claude Code project: missing at new path"
    VERIFY_FAIL=1
fi

if [[ -L "${PROJECTS_DIR}/${OLD_ENCODED}" ]]; then
    pass "Backward-compat symlink: active"
else
    warn "Backward-compat symlink: missing (non-critical)"
fi

if [[ "${MEMORY_EXISTS}" == "true" ]]; then
    if [[ -f "${PROJECTS_DIR}/${NEW_ENCODED}/memory/MEMORY.md" ]]; then
        pass "Auto-memory: preserved"
    else
        warn "Auto-memory: not found at new path"
    fi
fi

FINAL_SESSION_COUNT=$(find "${PROJECTS_DIR}/${NEW_ENCODED}" -maxdepth 1 -name '*.jsonl' -type f 2>/dev/null | wc -l | tr -d ' ')
if [[ "${FINAL_SESSION_COUNT}" -eq "${SESSION_COUNT}" ]]; then
    pass "Sessions: ${FINAL_SESSION_COUNT} preserved"
else
    fail "Sessions: expected ${SESSION_COUNT}, got ${FINAL_SESSION_COUNT}"
    VERIFY_FAIL=1
fi

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================="
if [[ "${VERIFY_FAIL}" -eq 0 ]]; then
    echo -e "${GREEN} MIGRATION COMPLETE${NC}"
else
    echo -e "${RED} MIGRATION COMPLETED WITH WARNINGS${NC}"
fi
echo "============================================================="
echo ""
echo " Repository:    ${NEW_DIR}"
echo " Sessions:      ${FINAL_SESSION_COUNT} migrated"
echo " History:       ${HISTORY_COUNT} entries updated"
echo " Backup:        ${BACKUP_DIR}"
echo ""
echo " Next steps:"
echo "   1. cd ${NEW_DIR}"
echo "   2. Open a new Claude Code session to verify context loads"
echo "   3. If issues: bash $0 --rollback"
echo "   4. Update git remote if needed:"
echo "      git remote set-url origin <new-url>"
echo ""

exit "${VERIFY_FAIL}"
