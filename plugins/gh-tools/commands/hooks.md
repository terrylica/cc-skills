---
name: hooks
description: "Install/uninstall gh-tools hooks to ~/.claude/settings.json"
allowed-tools: Read, Bash, TodoWrite, TodoRead
argument-hint: "[install|uninstall|status]"
---

# gh-tools Hooks Manager

Manage gh-tools hook installation in `~/.claude/settings.json`.

This hook soft-blocks WebFetch requests to github.com URLs and suggests using the `gh` CLI instead for better data access.

## Actions

| Action      | Description                                     |
| ----------- | ----------------------------------------------- |
| `status`    | Check hook installation status and dependencies |
| `install`   | Add gh-tools hooks to settings.json             |
| `uninstall` | Remove gh-tools hooks from settings.json        |

## Why Use gh CLI Instead of WebFetch?

| Aspect         | WebFetch           | gh CLI                 |
| -------------- | ------------------ | ---------------------- |
| Authentication | None               | gh auth token          |
| Data format    | HTML scraping      | Native JSON API        |
| Rate limits    | Strict (anonymous) | Higher (authenticated) |
| Pagination     | Manual             | Automatic              |
| Metadata       | Limited            | Full (labels, etc.)    |

## Execution

Parse `$ARGUMENTS` and run the management script:

```bash
/usr/bin/env bash << 'GH_TOOLS_HOOKS_SCRIPT'
set -euo pipefail

ACTION="${ARGUMENTS:-status}"

# Auto-detect plugin root
detect_plugin_root() {
    if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
        echo "$CLAUDE_PLUGIN_ROOT"
        return
    fi
    local marketplace="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gh-tools"
    if [[ -d "$marketplace/hooks" ]]; then
        echo "$marketplace"
        return
    fi
    local cache_base="$HOME/.claude/plugins/cache/cc-skills/gh-tools"
    if [[ -d "$cache_base" ]]; then
        local latest
        latest=$(ls -1 "$cache_base" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+' | sort -V | tail -1)
        if [[ -n "$latest" && -d "$cache_base/$latest/hooks" ]]; then
            echo "$cache_base/$latest"
            return
        fi
    fi
    echo ""
}

PLUGIN_DIR="$(detect_plugin_root)"
if [[ -z "$PLUGIN_DIR" ]]; then
    echo "ERROR: Cannot detect gh-tools plugin installation" >&2
    exit 1
fi

bash "$PLUGIN_DIR/scripts/manage-hooks.sh" "$ACTION"
GH_TOOLS_HOOKS_SCRIPT
```

## Post-Action Reminder

After install/uninstall operations:

**IMPORTANT: Restart Claude Code session for changes to take effect.**

The hooks are loaded at session start. Modifications to settings.json require a restart.

## Examples

```bash
# Check current installation status
/gh-tools:hooks status

# Install the WebFetch enforcement hook
/gh-tools:hooks install

# Uninstall hooks
/gh-tools:hooks uninstall
```

## Troubleshooting

| Issue                  | Cause                 | Solution                            |
| ---------------------- | --------------------- | ----------------------------------- |
| jq not found           | jq not installed      | `brew install jq`                   |
| Plugin root not found  | Plugin not installed  | Re-install via marketplace          |
| Hooks not working      | Session not restarted | Restart Claude Code session         |
| gh not authenticated   | gh CLI not set up     | Run `gh auth login`                 |
| WebFetch still allowed | Hook not triggered    | Check settings.json has hooks entry |

## Reference

- [ADR: gh-tools WebFetch Enforcement](/docs/adr/2026-01-03-gh-tools-webfetch-enforcement.md)
