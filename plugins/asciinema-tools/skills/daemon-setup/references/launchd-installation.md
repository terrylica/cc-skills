# launchd Installation Guide

## Phase 5: Daemon Configuration

**Use AskUserQuestion:**

```
Question: "Configure chunking settings:"
Header: "Settings"
Options:
  - label: "Default (30s idle, zstd-3) (Recommended)"
    description: "Balanced chunking frequency and compression"
  - label: "Fast (15s idle, zstd-1)"
    description: "More frequent chunks, less compression"
  - label: "Compact (60s idle, zstd-6)"
    description: "Less frequent chunks, higher compression"
  - label: "Custom"
    description: "Enter specific values"
```

**If "Custom", use AskUserQuestion:**

```
Question: "Enter idle threshold in seconds (how long to wait before pushing a chunk):"
Header: "Idle"
Options:
  - label: "Enter value"
    description: "Recommended: 15-120 seconds"
```

Then:

```
Question: "Enter zstd compression level (1-19, higher = smaller files but slower):"
Header: "Compression"
Options:
  - label: "Enter value"
    description: "Recommended: 1-6 for real-time use"
```

## Phase 6: Install launchd Service

### Generate plist from template

```bash
/usr/bin/env bash << 'GENERATE_PLIST_EOF'
IDLE_THRESHOLD="${1:-30}"
ZSTD_LEVEL="${2:-3}"

TEMPLATE_PATH="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/asciinema-tools}/scripts/asciinema-chunker.plist.template"
DAEMON_PATH="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/asciinema-tools}/scripts/idle-chunker-daemon.sh"
PLIST_PATH="$HOME/Library/LaunchAgents/com.cc-skills.asciinema-chunker.plist"

# Validate required files exist
if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "ERROR: Template not found at: $TEMPLATE_PATH"
  echo "Ensure asciinema-tools plugin is properly installed."
  exit 1
fi

if [[ ! -f "$DAEMON_PATH" ]]; then
  echo "ERROR: Daemon script not found at: $DAEMON_PATH"
  echo "Ensure asciinema-tools plugin is properly installed."
  exit 1
fi

if ! mkdir -p "$HOME/Library/LaunchAgents" 2>&1; then
  echo "ERROR: Cannot create LaunchAgents directory"
  exit 1
fi

if ! mkdir -p "$HOME/.asciinema/logs" 2>&1; then
  echo "ERROR: Cannot create logs directory at ~/.asciinema/logs"
  exit 1
fi

# Read template and substitute placeholders
sed \
  -e "s|{{HOME}}|$HOME|g" \
  -e "s|{{USER}}|$USER|g" \
  -e "s|{{DAEMON_PATH}}|$DAEMON_PATH|g" \
  -e "s|{{IDLE_THRESHOLD}}|$IDLE_THRESHOLD|g" \
  -e "s|{{ZSTD_LEVEL}}|$ZSTD_LEVEL|g" \
  "$TEMPLATE_PATH" > "$PLIST_PATH"

echo "PLIST_GENERATED:$PLIST_PATH"
GENERATE_PLIST_EOF
```

### Confirm installation

**Use AskUserQuestion:**

```
Question: "Ready to install the launchd service. This will:"
Header: "Install"
description: |
  - Install to: ~/Library/LaunchAgents/com.cc-skills.asciinema-chunker.plist
  - Start on login: Yes
  - Auto-restart on crash: Yes
  - Idle threshold: {idle}s
  - Compression: zstd-{level}
Options:
  - label: "Install and start now (Recommended)"
    description: "Install plist and start the daemon immediately"
  - label: "Install but don't start yet"
    description: "Install plist only, start manually later"
  - label: "Show plist file first"
    description: "Display the generated plist content"
```

**If "Show plist file first":**

Display plist content, then loop back to question.

### Install and start

**If "Install and start now":**

```bash
/usr/bin/env bash << 'INSTALL_DAEMON_EOF'
PLIST_PATH="$HOME/Library/LaunchAgents/com.cc-skills.asciinema-chunker.plist"

# Unload if already running (may fail if not loaded - that's expected)
if ! launchctl unload "$PLIST_PATH" 2>/dev/null; then
  echo "INFO: No existing daemon to unload (first install)"
fi

# Load and start
if launchctl load "$PLIST_PATH"; then
  echo "INSTALL_OK"
  sleep 2
  if launchctl list 2>/dev/null | grep -q "asciinema-chunker"; then
    echo "DAEMON_RUNNING"
  else
    echo "DAEMON_NOT_RUNNING"
  fi
else
  echo "INSTALL_FAILED"
fi
INSTALL_DAEMON_EOF
```
