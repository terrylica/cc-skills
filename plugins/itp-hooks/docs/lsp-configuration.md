# LSP Configuration

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — moved verbatim from the hub 2026-06-11 (CLAUDE.md size-guard refactor: hub was 112k chars, limit 40k).

## LSP Configuration

**Status**: DISABLED (2026-01-12) - pyright-langserver caused process storms.

### To Disable LSP (all three required)

```bash
# 1. Environment variable
grep ENABLE_LSP_TOOL ~/.zshenv  # Should show: export ENABLE_LSP_TOOL=0

# 2. Config file
ls ~/.claude/cclsp-config.json  # Should not exist (or .disabled)

# 3. Plugin setting
grep pyright-lsp ~/.claude/settings.json  # Should show: false
```

### To Re-enable LSP

```bash
# 1. ~/.zshenv
export ENABLE_LSP_TOOL=1

# 2. Restore config (if needed)
mv ~/.claude/cclsp-config.json.disabled ~/.claude/cclsp-config.json

# 3. ~/.claude/settings.json
"pyright-lsp@claude-plugins-official": true
```

**Verify**: `ps aux | grep -c '[p]yright'` (should be 0 when disabled)

