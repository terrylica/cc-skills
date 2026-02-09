# Troubleshooting Guide

Common issues after Claude Code project directory migration.

## Issue Reference

| Issue                         | Auto-fixed?          | Manual Solution                        |
| ----------------------------- | -------------------- | -------------------------------------- |
| mise trust error after rename | **Yes** (Phase 8)    | `mise trust <new-path>`                |
| `(old-name)` in shell prompt  | **Yes** (Phase 8)    | Restart terminal or `uv sync`          |
| VIRTUAL_ENV path mismatch     | **Yes** (Phase 8)    | `uv sync --dev` recreates venv         |
| "No conversations found"      | **Yes** (Phase 4)    | Re-run migration script                |
| `.envrc` not allowed          | **Warned** (Phase 8) | `direnv allow`                         |
| Git push auth fails           | No                   | Update credential helper or remote URL |
| Session subdirs missing       | No                   | Use `--rollback`, retry                |
| `.tool-versions` stale        | **Warned** (Phase 8) | Manual review                          |

## Detailed Solutions

### mise trust error

**Symptom**: `mise ERROR Config files are not trusted` after rename.

**Cause**: mise tracks trusted config files by absolute path. Directory rename invalidates the trust fingerprint.

**Auto-fix**: Phase 8 runs `mise trust <new-path>` automatically.

**Manual fix**:

```bash
mise trust /path/to/new-directory
mise trust /path/to/new-directory/.mise.local.toml  # if exists
```

### Stale venv prompt

**Symptom**: Shell prompt shows `(old-name)` instead of `(new-name)`.

**Cause**: `.venv/pyvenv.cfg` contains `prompt = old-name` and the `home` path references the old directory.

**Auto-fix**: Phase 8 runs `uv sync` which recreates the venv with correct paths.

**Manual fix**:

```bash
cd /path/to/new-directory
uv sync --dev        # if using uv
# or
rm -rf .venv && python3 -m venv .venv && pip install -e ".[dev]"
```

### "No conversations found"

**Symptom**: Claude Code shows "No conversations found to resume" after rename.

**Cause**: `sessions-index.json` still references old path, or the project directory wasn't moved.

**Fix**: Re-run the migration script. If that fails, use `--rollback` and retry.

### Git push authentication fails

**Symptom**: `remote: Invalid username or token` on git push.

**Cause**: Some credential helpers cache credentials by directory path.

**Fix**:

```bash
# Update remote URL if repo name changed
git remote set-url origin git@github.com:user/new-repo-name.git

# Or re-authenticate
git credential-osxkeychain erase <<EOF
host=github.com
protocol=https
EOF
```

### Rollback

If anything goes wrong, the script creates a timestamped backup:

```bash
# Rollback from most recent backup
bash claude-code-migrate.sh --rollback
```

Backups are stored at `~/.claude/migration-backup-YYYYMMDD-HHMMSS/` and contain:

- `projects/{old-encoded}/` — full project directory copy
- `history.jsonl` — complete history backup
- `migration-meta.json` — paths used for rollback
