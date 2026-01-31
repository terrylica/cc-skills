---
description: Install/uninstall RU hooks
allowed-tools: Bash
argument-hint: "[install|uninstall|status]"
---

# RU: Hooks

Manage RU hooks in `~/.claude/settings.json`.

## Usage

```bash
/ru:hooks install   # Add hooks to settings.json
/ru:hooks uninstall # Remove hooks from settings.json
/ru:hooks status    # Show current hook status
```

## Important

After installing hooks, you MUST restart Claude Code for them to take effect.

## Execution

```bash
/usr/bin/env bash << 'RALPH_UNIVERSAL_HOOKS'
SETTINGS="$HOME/.claude/settings.json"
COMMAND="${ARGUMENTS:-status}"
MARKER="ru/hooks/"

# Ensure settings.json exists
if [[ ! -f "$SETTINGS" ]]; then
    echo '{}' > "$SETTINGS"
fi

case "$COMMAND" in
    install)
        echo "Installing RU hooks..."

        # Record installation timestamp
        date +%s > "$HOME/.claude/ru-hooks-installed-at"

        # Check if already installed
        if grep -q "$MARKER" "$SETTINGS" 2>/dev/null; then
            echo "Hooks already installed."
            echo ""
            echo "IMPORTANT: Restart Claude Code if you haven't already."
            exit 0
        fi

        echo ""
        echo "Hooks will be registered when you run:"
        echo "  /plugin install ru@cc-skills"
        echo ""
        echo "Then restart Claude Code for hooks to take effect."
        ;;

    uninstall)
        echo "Uninstalling RU hooks..."

        # Remove timestamp
        rm -f "$HOME/.claude/ru-hooks-installed-at"

        echo "Hooks will be removed when you run:"
        echo "  /plugin uninstall ru@cc-skills"
        echo ""
        echo "Restart Claude Code after uninstalling."
        ;;

    status)
        echo "RU Hooks Status"
        echo "============================"
        echo ""

        if grep -q "$MARKER" "$SETTINGS" 2>/dev/null; then
            echo "Status: INSTALLED"
            HOOK_COUNT=$(grep -o "$MARKER" "$SETTINGS" | wc -l | tr -d ' ')
            echo "Hooks: $HOOK_COUNT registered"
        else
            echo "Status: NOT INSTALLED"
            echo ""
            echo "Run: /ru:hooks install"
        fi

        if [[ -f "$HOME/.claude/ru-hooks-installed-at" ]]; then
            INSTALL_TS=$(cat "$HOME/.claude/ru-hooks-installed-at")
            INSTALL_DATE=$(date -r "$INSTALL_TS" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
            echo "Installed at: $INSTALL_DATE"
        fi
        ;;

    *)
        echo "Usage: /ru:hooks [install|uninstall|status]"
        exit 1
        ;;
esac
RALPH_UNIVERSAL_HOOKS
```

## Examples

```bash
# Check current hook status
/ru:hooks status

# Install RU hooks
/ru:hooks install

# Uninstall hooks
/ru:hooks uninstall
```

## Troubleshooting

| Issue              | Cause                    | Solution                    |
| ------------------ | ------------------------ | --------------------------- |
| Already installed  | Hooks already registered | Restart Claude Code session |
| Hooks not working  | Session not restarted    | Restart Claude Code session |
| Status shows wrong | Stale timestamp          | Re-run install command      |
