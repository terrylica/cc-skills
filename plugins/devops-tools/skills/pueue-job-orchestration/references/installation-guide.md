**Skill**: [Pueue Job Orchestration](../SKILL.md)

# Installation Guide

## macOS (Local)

```bash
brew install pueue
pueued -d  # Start daemon
```

## Linux (gpu-host-1)

```bash
# Download from GitHub releases (see https://github.com/Nukesor/pueue/releases for latest)
curl -sSL https://raw.githubusercontent.com/terrylica/rangebar-py/main/scripts/setup-pueue-linux.sh | bash

# Or manually:
# SSoT-OK: Version from GitHub releases page
PUEUE_VERSION="v4.0.2"
curl -sSL "https://github.com/Nukesor/pueue/releases/download/${PUEUE_VERSION}/pueue-x86_64-unknown-linux-musl" -o ~/.local/bin/pueue
curl -sSL "https://github.com/Nukesor/pueue/releases/download/${PUEUE_VERSION}/pueued-x86_64-unknown-linux-musl" -o ~/.local/bin/pueued
chmod +x ~/.local/bin/pueue ~/.local/bin/pueued

# Start daemon
~/.local/bin/pueued -d
```

## Systemd Auto-Start (Linux)

```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/pueued.service << 'EOF'
[Unit]
Description=Pueue Daemon
After=network.target

[Service]
ExecStart=%h/.local/bin/pueued -v
Restart=on-failure

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now pueued
```

## macOS Auto-Start (launchd)

Auto-start the pueue daemon on login. Create the plist at `~/Library/LaunchAgents/com.nukesor.pueued.plist`:

```bash
# Generate the launchd plist (standard Apple plist format)  # SSoT-OK
cat > ~/Library/LaunchAgents/com.nukesor.pueued.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.nukesor.pueued</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/pueued</string>
        <string>-v</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/pueued.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/pueued.stderr.log</string>
</dict>
</plist>
PLIST
```

Then load the agent:

```bash
# Load (starts immediately + on login)
launchctl load ~/Library/LaunchAgents/com.nukesor.pueued.plist

# Unload
launchctl unload ~/Library/LaunchAgents/com.nukesor.pueued.plist

# Check status
launchctl list | grep pueued
```

**Linux equivalent**: Use systemd -- see `pueued --systemd` or create a user service in `~/.config/systemd/user/`.
