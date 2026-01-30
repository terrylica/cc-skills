---
description: Install/uninstall Ralph Universal hooks to settings.json
allowed-tools: Bash
argument-hint: "[install|uninstall|status]"
---

# Ralph Universal: Hooks

Manage Ralph Universal hooks in `~/.claude/settings.json`.

## Usage

```bash
/ralph-universal:hooks install   # Add hooks to settings.json
/ralph-universal:hooks uninstall # Remove hooks from settings.json
/ralph-universal:hooks status    # Show current hook status
```

## Important

After installing hooks, you MUST restart Claude Code for them to take effect.

## Execution

```bash
/usr/bin/env bash << 'RALPH_UNIVERSAL_HOOKS'
SETTINGS="$HOME/.claude/settings.json"
COMMAND="${ARGUMENTS:-status}"
MARKER="ralph-universal/hooks/"

# Ensure settings.json exists
if [[ ! -f "$SETTINGS" ]]; then
    echo '{}' > "$SETTINGS"
fi

case "$COMMAND" in
    install)
        echo "Installing Ralph Universal hooks..."

        # Record installation timestamp
        date +%s > "$HOME/.claude/ralph-universal-hooks-installed-at"

        # Check if already installed
        if grep -q "$MARKER" "$SETTINGS" 2>/dev/null; then
            echo "Hooks already installed."
            echo ""
            echo "IMPORTANT: Restart Claude Code if you haven't already."
            exit 0
        fi

        echo ""
        echo "Hooks will be registered when you run:"
        echo "  /plugin install ralph-universal@cc-skills"
        echo ""
        echo "Then restart Claude Code for hooks to take effect."
        ;;

    uninstall)
        echo "Uninstalling Ralph Universal hooks..."

        # Remove timestamp
        rm -f "$HOME/.claude/ralph-universal-hooks-installed-at"

        echo "Hooks will be removed when you run:"
        echo "  /plugin uninstall ralph-universal@cc-skills"
        echo ""
        echo "Restart Claude Code after uninstalling."
        ;;

    status)
        echo "Ralph Universal Hooks Status"
        echo "============================"
        echo ""

        if grep -q "$MARKER" "$SETTINGS" 2>/dev/null; then
            echo "Status: INSTALLED"
            HOOK_COUNT=$(grep -o "$MARKER" "$SETTINGS" | wc -l | tr -d ' ')
            echo "Hooks: $HOOK_COUNT registered"
        else
            echo "Status: NOT INSTALLED"
            echo ""
            echo "Run: /ralph-universal:hooks install"
        fi

        if [[ -f "$HOME/.claude/ralph-universal-hooks-installed-at" ]]; then
            INSTALL_TS=$(cat "$HOME/.claude/ralph-universal-hooks-installed-at")
            INSTALL_DATE=$(date -r "$INSTALL_TS" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
            echo "Installed at: $INSTALL_DATE"
        fi
        ;;

    *)
        echo "Usage: /ralph-universal:hooks [install|uninstall|status]"
        exit 1
        ;;
esac
RALPH_UNIVERSAL_HOOKS
```
