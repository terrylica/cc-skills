---
adr: 2025-12-07-idempotency-backup-traceability
source: ~/.claude/plans/snoopy-baking-lerdorf.md
implementation-status: implemented
phase: complete
last-updated: 2025-12-07
---

# Idempotency Fixes with Format-Aware Backup Traceability

**ADR**: [Idempotency Fixes ADR](/docs/adr/2025-12-07-idempotency-backup-traceability.md)

## Summary

Fix **16 idempotency issues** across 8 scripts using a holistic backup pattern: **sibling backups with format-aware traceability comments**. (Fix #3 removed - already idempotent)

---

## User Decisions

- **Priority**: All high-severity issues first
- **Backup location**: Sibling to original (`file.bak.TIMESTAMP`)
- **Traceability**: Format-aware comments in new files referencing backup location
- **Log rotation**: Yes, include rotation for unbounded logs
- **Re-run behavior**: Skip if exists (for init scripts)
- **.releaserc.yml**: Backup + trace comment before overwrite

---

## Holistic Principle: Format-Aware Backup Traceability

Choose traceability method based on file format. All methods are **composable, not conflicting**.

| File Type          | Traceability Method   | Format                                                |
| ------------------ | --------------------- | ----------------------------------------------------- |
| Shell (.sh)        | Single-line comment   | `# Previous version: ./file.sh.bak.YYYYMMDD_HHMMSS`   |
| YAML (.yml, .yaml) | Frontmatter field     | `backup_of: ./file.yml.bak.YYYYMMDD_HHMMSS`           |
| JSON (.json)       | Sibling metadata file | `file.json.backup-info` (JSON can't have comments)    |
| Markdown (.md)     | Frontmatter field     | `backup_of: ./file.md.bak.YYYYMMDD_HHMMSS`            |
| Plain config       | First-line comment    | `# Previous version: ./file.conf.bak.YYYYMMDD_HHMMSS` |

### Backup Naming Convention

```
{filename}.bak.{YYYYMMDD}_{HHMMSS}
```

---

## Files to Modify

### Phase 1: High-Severity (8 fixes)

| #     | File                                                                                  | Line(s) | Fix                                      |
| ----- | ------------------------------------------------------------------------------------- | ------- | ---------------------------------------- |
| 1     | `plugins/itp/skills/semantic-release/scripts/init_user_config.sh`                     | 57-68   | Skip if dir exists                       |
| 2     | `plugins/itp/skills/semantic-release/scripts/create_org_config.sh`                    | 76-78   | Check .git before git init + `\|\| true` |
| ~~3~~ | ~~`plugins/itp/skills/semantic-release/scripts/init_project.sh`~~                     | ~~189~~ | ~~REMOVED - already idempotent~~         |
| 4     | `plugins/productivity-tools/skills/smart-file-placement/scripts/init-workspace.sh`    | 31-32   | Atomic .gitignore update                 |
| 5     | `plugins/notification-tools/skills/dual-channel-watchexec/examples/bot-wrapper.sh`    | 75-93   | Atomic JSON write (mktemp + mv)          |
| 6     | `plugins/notification-tools/skills/dual-channel-watchexec/examples/bot-wrapper.sh`    | 153-160 | Atomic crash context                     |
| 7     | `plugins/notification-tools/skills/dual-channel-watchexec/examples/bot-wrapper.sh`    | 106-108 | Atomic first-run marker (mkdir)          |
| 8     | `plugins/notification-tools/skills/dual-channel-watchexec/examples/notify-restart.sh` | 198-201 | mktemp for temp files                    |
| 9     | `plugins/notification-tools/skills/dual-channel-watchexec/examples/notify-restart.sh` | 243     | trap cleanup on exit                     |

### Phase 2: Medium-Severity (4 fixes)

| #   | File                                                                                  | Line(s) | Fix                                                        |
| --- | ------------------------------------------------------------------------------------- | ------- | ---------------------------------------------------------- |
| 10  | `plugins/itp/skills/semantic-release/scripts/init_project.sh`                         | 147-180 | **Backup + trace comment** before .releaserc.yml overwrite |
| 11  | `plugins/itp/skills/pypi-doppler/scripts/publish-to-pypi.sh`                          | 259     | Safe glob cleanup with find                                |
| 12  | `plugins/notification-tools/skills/dual-channel-watchexec/examples/notify-restart.sh` | 160     | Nanosecond precision in archive names                      |
| 13  | `plugins/notification-tools/skills/dual-channel-watchexec/examples/bot-wrapper.sh`    | 110,116 | Wait for background jobs                                   |

### Phase 3: Low-Severity + Log Rotation (4 fixes)

| #   | File                                                                                  | Line(s)       | Fix                                                             |
| --- | ------------------------------------------------------------------------------------- | ------------- | --------------------------------------------------------------- |
| 14  | `plugins/itp/skills/semantic-release/scripts/init_project.sh`                         | 188-192       | Exact line match for .gitignore                                 |
| 15  | `plugins/notification-tools/skills/dual-channel-watchexec/examples/bot-wrapper.sh`    | 126           | Safe log truncation                                             |
| 16  | `plugins/notification-tools/skills/dual-channel-watchexec/examples/notify-restart.sh` | 16-21         | Log rotation (keep last 5)                                      |
| 17  | `plugins/doc-build-tools/skills/pandoc-pdf-generation/assets/build-pdf-example.sh`    | **Before 33** | Log rotation (keep last 5) - insert before LOG_FILE declaration |

---

## Detailed Fix Patterns

### Fix #1: init_user_config.sh - Skip if exists

```bash
# Current (lines 57-68)
if [ -d "$USER_CONFIG_DIR" ]; then
    echo "ERROR: $USER_CONFIG_DIR already exists"
    exit 1
fi

# Fix: Idempotent skip
if [ -d "$USER_CONFIG_DIR" ]; then
    echo "INFO: $USER_CONFIG_DIR already exists, skipping"
    exit 0
fi
```

### Fix #2: create_org_config.sh - Check git state

```bash
# Current (lines 76-78)
git init
git add .
git commit -m "Initial commit"

# Fix: Check before git ops + handle clean tree
if [ ! -d "$FULL_PATH/.git" ]; then
    git init
    git add .
    git commit -m "Initial commit" || true  # Allow clean tree
else
    echo "INFO: Git repo already initialized"
fi
```

### Fix #10: init_project.sh - Backup + Trace for .releaserc.yml

```bash
# Current (lines 147-180) - overwrites silently
cat > .releaserc.yml <<EOF
...
EOF

# Fix: Backup with format-aware traceability
if [ -f .releaserc.yml ]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP=".releaserc.yml.bak.${TIMESTAMP}"
    cp .releaserc.yml "$BACKUP"
    echo "INFO: Backed up to $BACKUP"
fi

# Write new file with traceability in YAML comment
cat > .releaserc.yml <<EOF
# Previous version: ./${BACKUP:-none}
extends: ...
EOF
```

### Fix #5-7: bot-wrapper.sh - Atomic operations

```bash
# Fix #5: Atomic JSON write (lines 75-93)
tmp=$(mktemp)
cat > "$tmp" <<WATCHEXEC_EOF
{ "pid": "$$", ... }
WATCHEXEC_EOF
mv "$tmp" "$WATCHEXEC_INFO_FILE"

# Fix #6: Atomic crash context (lines 153-160)
tmp=$(mktemp)
{
    echo "--- BOT LOG (last 20 lines) ---"
    tail -20 "$BOT_LOG" 2>/dev/null || true
    echo "--- STDERR ---"
    tail -10 "$CRASH_LOG" 2>/dev/null || true
} > "$tmp"
mv "$tmp" "$CRASH_CONTEXT"

# Fix #7: Atomic first-run marker (lines 106-108)
FIRST_RUN_MARKER="/tmp/watchexec_first_run_$$"
if mkdir "$FIRST_RUN_MARKER" 2>/dev/null; then
    REASON="startup"
else
    REASON="restart"
fi
```

### Fix #8-9: notify-restart.sh - Safe temp files

```bash
# Fix #8: Use mktemp (line 198)
MESSAGE_FILE=$(mktemp /tmp/telegram_message.XXXXXX)

# Fix #9: Trap cleanup (add near top)
trap 'rm -f "$MESSAGE_FILE"' EXIT
```

### Fix #16-17: Log rotation pattern

```bash
# For notify-restart.sh and build-pdf-example.sh
rotate_log() {
    local log_file="$1"
    local keep_count="${2:-5}"

    if [ -f "$log_file" ]; then
        mv "$log_file" "${log_file}.$(date +%s)"
        # Keep only last N logs
        ls -t "${log_file}."* 2>/dev/null | tail -n +$((keep_count + 1)) | xargs rm -f 2>/dev/null || true
    fi
}

# Usage before logging
rotate_log "$NOTIFICATION_LOG" 5
rotate_log "$LOG_FILE" 5
```

---

## Common Patterns Summary

| Pattern               | Purpose                  | Implementation                      |
| --------------------- | ------------------------ | ----------------------------------- |
| **Write-then-rename** | Atomic file operations   | `mktemp` → write → `mv`             |
| **mkdir as lock**     | Atomic first-run check   | `mkdir "$MARKER" 2>/dev/null`       |
| **Backup + trace**    | Recoverable overwrites   | `cp` → write new with trace comment |
| **Log rotation**      | Prevent unbounded growth | Rename with timestamp, keep last N  |
| **Trap cleanup**      | Safe temp file removal   | `trap 'rm -f "$TEMP"' EXIT`         |
| **Skip if exists**    | Idempotent creation      | `[ -d "$DIR" ] && exit 0`           |

---

## Testing Strategy

For each fix, verify:

1. **First run**: Creates expected state
2. **Second run**: Same end state (idempotent)
3. **Interrupted run**: No corruption (atomic)
4. **Backup exists**: Traceability comment present in new file
5. **Restore works**: Can recover from sibling .bak file

---

## Success Criteria

- [x] All 16 fixes implemented
- [x] Each script is idempotent (safe to re-run)
- [x] Backups created with traceability comments
- [x] Log rotation prevents unbounded growth
- [x] All scripts work on both macOS and Linux
