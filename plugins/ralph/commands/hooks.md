---
description: "Install/uninstall ralph hooks to ~/.claude/settings.json"
allowed-tools: Read, Bash, TodoWrite, TodoRead
argument-hint: "[install|uninstall|status]"
---

# Ralph Hooks Manager

Manage ralph loop hooks installation in `~/.claude/settings.json`.

Claude Code only loads hooks from settings.json, not from plugin hooks.json files. This command installs/uninstalls the ralph Stop and PreToolUse hooks that enable autonomous loop mode.

## Actions

| Action      | Description                                      |
| ----------- | ------------------------------------------------ |
| `status`    | Comprehensive preflight check (deps, paths, etc) |
| `install`   | Add ralph hooks to settings.json                 |
| `uninstall` | Remove ralph hooks from settings.json            |

## Execution

Parse `$ARGUMENTS` and run the management script:

```bash
# Use /usr/bin/env bash for macOS zsh compatibility (see ADR: shell-command-portability-zsh)
/usr/bin/env bash << 'RALPH_HOOKS_SCRIPT'
set -euo pipefail

ACTION="${ARGUMENTS:-status}"
SETTINGS="$HOME/.claude/settings.json"
INSTALL_TS_FILE="$HOME/.claude/ralph-hooks-installed-at"
MARKER="ralph/hooks/"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Auto-detect plugin root (same logic as manage-hooks.sh)
detect_plugin_root() {
    if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
        echo "$CLAUDE_PLUGIN_ROOT"
        return
    fi
    local marketplace="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/ralph"
    if [[ -d "$marketplace/hooks" ]]; then
        echo "$marketplace"
        return
    fi
    local cache_base="$HOME/.claude/plugins/cache/cc-skills/ralph"
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

# Comprehensive preflight check
do_preflight() {
    local errors=0
    local warnings=0
    local PLUGIN_ROOT
    PLUGIN_ROOT="$(detect_plugin_root)"

    echo -e "${CYAN}=== Ralph Hooks Preflight Check ===${NC}"
    echo ""

    # 1. Plugin Root Detection
    echo -e "${CYAN}Plugin Location:${NC}"
    if [[ -n "$PLUGIN_ROOT" && -d "$PLUGIN_ROOT" ]]; then
        echo -e "  ${GREEN}✓${NC} $PLUGIN_ROOT"
    else
        echo -e "  ${RED}✗${NC} Could not detect plugin installation"
        echo -e "      Expected: marketplace, cache, or CLAUDE_PLUGIN_ROOT"
        ((errors++))
    fi
    echo ""

    # 2. Dependency Checks
    echo -e "${CYAN}Dependencies:${NC}"

    # Check jq
    if command -v jq &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} jq $(jq --version 2>/dev/null | head -1)"
    else
        echo -e "  ${RED}✗${NC} jq - REQUIRED. Install: brew install jq"
        ((errors++))
    fi

    # Check uv
    if command -v uv &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} uv $(uv --version 2>/dev/null | awk '{print $2}')"
    else
        echo -e "  ${RED}✗${NC} uv - REQUIRED. Install: brew install uv"
        ((errors++))
    fi

    # Check Python version
    local py_version
    py_version=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "")
    if [[ -n "$py_version" ]]; then
        local major="${py_version%%.*}"
        local minor="${py_version#*.}"
        if [[ "$major" -ge 3 && "$minor" -ge 11 ]]; then
            echo -e "  ${GREEN}✓${NC} Python $py_version"
        else
            echo -e "  ${RED}✗${NC} Python $py_version - REQUIRES 3.11+"
            ((errors++))
        fi
    else
        echo -e "  ${RED}✗${NC} Python - not found"
        ((errors++))
    fi
    echo ""

    # 3. Hook Script Checks
    echo -e "${CYAN}Hook Scripts:${NC}"
    if [[ -n "$PLUGIN_ROOT" ]]; then
        local stop_hook="$PLUGIN_ROOT/hooks/loop-until-done.py"
        local pretooluse_hook="$PLUGIN_ROOT/hooks/archive-plan.sh"

        if [[ -f "$stop_hook" ]]; then
            if [[ -x "$stop_hook" ]]; then
                echo -e "  ${GREEN}✓${NC} loop-until-done.py"
            else
                echo -e "  ${YELLOW}⚠${NC} loop-until-done.py (not executable)"
                ((warnings++))
            fi
        else
            echo -e "  ${RED}✗${NC} loop-until-done.py - NOT FOUND"
            ((errors++))
        fi

        if [[ -f "$pretooluse_hook" ]]; then
            if [[ -x "$pretooluse_hook" ]]; then
                echo -e "  ${GREEN}✓${NC} archive-plan.sh"
            else
                echo -e "  ${YELLOW}⚠${NC} archive-plan.sh (not executable)"
                ((warnings++))
            fi
        else
            echo -e "  ${RED}✗${NC} archive-plan.sh - NOT FOUND"
            ((errors++))
        fi
    else
        echo -e "  ${RED}✗${NC} Cannot check - plugin root unknown"
        ((errors++))
    fi
    echo ""

    # 4. Hook Registration Check
    echo -e "${CYAN}Hook Registration:${NC}"
    local hook_count=0
    if [[ -f "$SETTINGS" ]] && command -v jq &>/dev/null; then
        hook_count=$(jq '[.hooks | to_entries[]? | .value[]? | .hooks[]? | select(.command | contains("'"$MARKER"'"))] | length' "$SETTINGS" 2>/dev/null || echo "0")
    fi

    if [[ "$hook_count" -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC} $hook_count hook(s) registered in settings.json"
        # Show which hooks
        jq -r '.hooks | to_entries[]? | select(.value[]? | .hooks[]? | .command | contains("'"$MARKER"'")) | "      - \(.key)"' "$SETTINGS" 2>/dev/null | sort -u
    else
        echo -e "  ${RED}✗${NC} No hooks registered"
        echo -e "      Run: /ralph:hooks install"
        ((errors++))
    fi
    echo ""

    # 5. Session Restart Detection (Critical)
    echo -e "${CYAN}Session Status:${NC}"
    if [[ -f "$INSTALL_TS_FILE" ]]; then
        local install_ts
        install_ts=$(cat "$INSTALL_TS_FILE")

        # Get session start time from .claude directory mtime as proxy
        local session_ts
        session_ts=$(stat -f %m "$HOME/.claude" 2>/dev/null || stat -c %Y "$HOME/.claude" 2>/dev/null || echo "0")

        # Also check projects dir which changes more frequently
        local projects_dir="$HOME/.claude/projects"
        if [[ -d "$projects_dir" ]]; then
            local projects_ts
            projects_ts=$(stat -f %m "$projects_dir" 2>/dev/null || stat -c %Y "$projects_dir" 2>/dev/null || echo "0")
            if [[ "$projects_ts" -gt "$session_ts" ]]; then
                session_ts="$projects_ts"
            fi
        fi

        if [[ "$install_ts" -gt "$session_ts" ]]; then
            echo -e "  ${RED}✗${NC} Hooks installed AFTER session started!"
            local install_date
            install_date=$(date -r "$install_ts" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$install_ts" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
            echo -e "      Installed at: $install_date"
            echo -e "      ${YELLOW}ACTION: Restart Claude Code for hooks to activate${NC}"
            ((errors++))
        else
            echo -e "  ${GREEN}✓${NC} Hooks installed before this session"
        fi
    else
        if [[ "$hook_count" -gt 0 ]]; then
            echo -e "  ${YELLOW}⚠${NC} No install timestamp (legacy install)"
            echo -e "      Consider re-running: /ralph:hooks install"
            ((warnings++))
        else
            echo -e "  ${CYAN}○${NC} No hooks installed yet"
        fi
    fi
    echo ""

    # Summary
    echo -e "${CYAN}=== Summary ===${NC}"
    if [[ "$errors" -eq 0 && "$warnings" -eq 0 ]]; then
        echo -e "${GREEN}All preflight checks passed!${NC}"
        echo "Ralph is ready. Run: /ralph:start"
        return 0
    elif [[ "$errors" -eq 0 ]]; then
        echo -e "${YELLOW}$warnings warning(s), but system is usable${NC}"
        return 0
    else
        echo -e "${RED}$errors error(s) must be fixed before using Ralph${NC}"
        return 1
    fi
}

# Route action
case "$ACTION" in
    status)
        do_preflight
        ;;
    install|uninstall)
        PLUGIN_DIR="$(detect_plugin_root)"
        if [[ -z "$PLUGIN_DIR" ]]; then
            echo -e "${RED}ERROR:${NC} Cannot detect plugin installation" >&2
            exit 1
        fi
        bash "$PLUGIN_DIR/scripts/manage-hooks.sh" "$ACTION"
        ;;
    *)
        echo "Usage: /ralph:hooks [install|uninstall|status]"
        exit 1
        ;;
esac
RALPH_HOOKS_SCRIPT
```

## Post-Action Reminder

After install/uninstall operations:

**IMPORTANT: Restart Claude Code session for changes to take effect.**

The hooks are loaded at session start. Modifications to settings.json require a restart.
