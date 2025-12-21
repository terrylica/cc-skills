---
name: asciinema-player
description: Play .cast terminal recordings in browser with seek controls. TRIGGERS - asciinema, .cast file, terminal recording, play cast, recording playback, play recording. Uses AskUserQuestion for interactive file selection, generates HTML player, starts HTTP server.
allowed-tools: Read, Bash, Write, Glob, AskUserQuestion
---

# asciinema-player

Play terminal session recordings (.cast files) in a browser with full playback controls including seek bar, speed adjustment, and keyboard shortcuts.

> **Platform**: macOS, Linux only (no Windows support)

---

## Version Requirements

| Component        | Minimum Version | Strategy                                                     |
| ---------------- | --------------- | ------------------------------------------------------------ |
| asciinema-player | **3.10.0**      | Semver range `^3.10.0` auto-upgrades to latest 3.x on invoke |
| Python           | 3.8+            | For HTTP server and serve_cast.py script                     |
| asciinema CLI    | 2.4.0+          | For recording (optional for playback only)                   |

> **CRITICAL**: asciinema-player < 3.10.0 does NOT support asciicast v3 format (delta timestamps). Playback will fail silently with a stuck play button.

**Versioning Strategy**: The HTML template uses `@^3.10.0` semver range via jsDelivr CDN. This ensures:

- **Minimum 3.10.0**: Required for asciicast v3 format support
- **Auto-upgrade**: Each invocation fetches the latest compatible 3.x version
- **Stability**: Major version locked to prevent breaking changes

---

## Workflow Phases (ALL MANDATORY)

**IMPORTANT**: All phases are MANDATORY. Do NOT skip any phase. AskUserQuestion MUST be used at each decision point.

### Phase 0: Preflight Checks

**Purpose**: Verify all dependencies are installed with correct versions.

#### Step 0.1: Check Dependencies

```bash
# Check Python version
python3 --version

# Check if asciinema CLI is installed (optional for playback)
which asciinema && asciinema --version
```

#### Step 0.2: Report Status and Ask for Installation

**MANDATORY AskUserQuestion** if any dependency is missing:

```
Question: "Some dependencies are missing or outdated. Install them?"
Header: "Setup"
Options:
  - Label: "Install missing tools"
    Description: "Will install: {list of missing tools}"
  - Label: "Skip (playback only)"
    Description: "Continue without asciinema CLI (can't record, only play)"
  - Label: "Cancel"
    Description: "Abort and fix manually"
```

#### Step 0.3: Install Missing Dependencies (if confirmed)

```bash
# macOS - Install asciinema CLI
brew install asciinema

# Linux (Debian/Ubuntu)
sudo apt install asciinema

# Linux (Fedora)
sudo dnf install asciinema

# Via pip (cross-platform)
pip install asciinema
```

---

### Phase 1: File Selection (MANDATORY)

**Purpose**: Discover and select the recording to play.

#### Step 1.1: Discover Recordings

```bash
# Search for .cast files in workspace and common locations
fd -e cast . --max-depth 5 2>/dev/null | head -20

# Also check common locations
ls -la ~/scripts/tmp/*.cast 2>/dev/null
ls -la ~/.local/share/asciinema/*.cast 2>/dev/null
ls -la ./tmp/*.cast 2>/dev/null
```

#### Step 1.2: Present File Selection (MANDATORY AskUserQuestion)

**If recordings found**:

```
Question: "Which recording would you like to play?"
Header: "Recording"
Options:
  - Label: "{filename} ({size})"
    Description: "Recorded {date}, {line_count} events"
  - Label: "{filename2} ({size})"
    Description: "Recorded {date}, {line_count} events"
  - ... (up to 4 most recent)
```

**If user provided path directly**, still confirm:

```
Question: "Play this recording?"
Header: "Confirm"
Options:
  - Label: "Yes, play {filename}"
    Description: "{size}, {line_count} events"
  - Label: "Choose different file"
    Description: "Browse for other recordings"
```

**If no recordings found**:

```
Question: "No .cast files found. What would you like to do?"
Header: "No Files"
Options:
  - Label: "Enter path manually"
    Description: "Provide full path to .cast file"
  - Label: "Record new session"
    Description: "Start recording with: asciinema rec session.cast"
  - Label: "Cancel"
    Description: "Exit skill"
```

---

### Phase 2: Playback Settings (MANDATORY)

**Purpose**: Configure playback preferences before generating player.

#### Step 2.1: Ask Playback Preferences (MANDATORY AskUserQuestion)

```
Question: "Choose playback settings:"
Header: "Settings"
Options:
  - Label: "Default (1x, monokai)"
    Description: "Standard speed, dark theme"
  - Label: "Fast review (2x)"
    Description: "Double speed for quick review"
  - Label: "Presentation (1x, dracula)"
    Description: "Slower pace, high contrast theme"
  - Label: "Custom"
    Description: "Choose speed and theme manually"
```

**If "Custom" selected**, follow up with:

```
Question: "Select playback speed:"
Header: "Speed"
Options:
  - Label: "0.5x (slow)"
    Description: "Half speed for detailed review"
  - Label: "1x (normal)"
    Description: "Original recording speed"
  - Label: "2x (fast)"
    Description: "Double speed"
  - Label: "3x (very fast)"
    Description: "Triple speed for long recordings"
```

```
Question: "Select color theme:"
Header: "Theme"
Options:
  - Label: "monokai"
    Description: "Dark theme with syntax colors (default)"
  - Label: "dracula"
    Description: "Purple-tinted dark theme"
  - Label: "solarized-dark"
    Description: "Solarized dark variant"
  - Label: "nord"
    Description: "Arctic, bluish theme"
```

---

### Phase 3: Generate and Serve

**Purpose**: Create HTML player and start HTTP server.

#### Step 3.1: Generate Player

```bash
cd {skill_directory}
uv run scripts/serve_cast.py {cast_file} --port {port} --speed {speed} --theme {theme}
```

#### Step 3.2: Verify Server Started

```bash
# Check server is running
curl -s http://localhost:{port}/player.html | head -5

# Verify cast file is accessible
curl -sI http://localhost:{port}/{cast_filename} | grep "200 OK"
```

#### Step 3.3: Display Quick Tutorial

````markdown
## asciinema Player Ready

**Your recording:** `{recording_name}`
**Open in browser:** http://localhost:{port}/player.html

### Quick Keyboard Controls

| Key     | Action                    |
| ------- | ------------------------- |
| `Space` | Pause / Play              |
| `←` `→` | Seek 5 seconds            |
| `0-9`   | Jump to 0%-90%            |
| `[` `]` | Decrease / Increase speed |
| `f`     | Fullscreen                |

### Playback Tips

- **Speed up long sessions:** Press `]` multiple times for 2x, 3x, 4x speed
- **Skip idle time:** Already capped at 2 seconds max
- **Scrub timeline:** Click/drag the progress bar

### Cleanup (when done)

```bash
pkill -f "http.server {port}"
```
````

```

---

## TodoWrite Task Template (MANDATORY)

**Load this template into TodoWrite before starting**:

```

1. [Preflight] Check Python 3 installed
2. [Preflight] Check asciinema CLI (optional)
3. [Preflight] AskUserQuestion: confirm installations if needed
4. [Preflight] Install missing dependencies (if confirmed)
5. [Selection] Discover .cast files in workspace
6. [Selection] AskUserQuestion: file selection
7. [Settings] AskUserQuestion: playback preferences
8. [Settings] AskUserQuestion: custom speed/theme (if Custom selected)
9. [Generate] Run serve_cast.py with options
10. [Generate] Verify HTTP server started
11. [Generate] Display Quick Tutorial
12. [Generate] Provide clickable localhost URL

````

---

## Script Usage

**Basic**:

```bash
uv run scripts/serve_cast.py <cast_file>
````

**With options**:

```bash
uv run scripts/serve_cast.py <cast_file> --port 8080 --speed 2 --idle-limit 1 --theme dracula
```

**Arguments**:

| Argument       | Default | Description                                   |
| -------------- | ------- | --------------------------------------------- |
| `cast_file`    | -       | Path to .cast file (required)                 |
| `--port`       | 8000    | HTTP server port                              |
| `--speed`      | 1.0     | Playback speed                                |
| `--idle-limit` | 2       | Max idle seconds                              |
| `--theme`      | monokai | Color theme                                   |
| `--output-dir` | -       | Output directory (default: same as cast file) |

---

## Available Themes

- asciinema (default upstream)
- monokai (skill default)
- tango
- solarized-dark
- solarized-light
- dracula
- nord

---

## Troubleshooting

### Player shows stuck play button, won't play

**Cause**: asciicast v3 format not supported by player version < 3.10.0

**Fix**: Ensure template uses asciinema-player >= 3.10.0 (check `assets/player-template.html`)

### Server running but player can't load cast file

**Cause**: HTTP server running from wrong directory

**Fix**: The script now auto-detects port conflicts and starts a new server in the correct directory

### Large files (>100MB) slow to load

**Cause**: Browser must download and parse entire file before playback

**Workaround**: Use `asciinema play file.cast` CLI for large files, or split recording

---

## Bundled Resources

| Resource                                                       | Purpose                        |
| -------------------------------------------------------------- | ------------------------------ |
| [scripts/serve_cast.py](./scripts/serve_cast.py)               | Generate player + start server |
| [assets/player-template.html](./assets/player-template.html)   | HTML template (v3.10.0 player) |
| [references/player-options.md](./references/player-options.md) | Full options reference         |

---

## Post-Change Checklist (Self-Maintenance)

After modifying THIS skill:

1. [ ] Verify player-template.html uses asciinema-player >= 3.10.0
2. [ ] Test with asciicast v3 format file
3. [ ] Test preflight checks on clean system
4. [ ] Verify all AskUserQuestion flows work
5. [ ] Update references/player-options.md if options changed
6. [ ] Validate with quick_validate.py

---

## Reference Documentation

- [Player Options Reference](./references/player-options.md) - Full configuration options
- [asciinema-player GitHub](https://github.com/asciinema/asciinema-player)
- [asciinema docs](https://docs.asciinema.org/manual/player/)
- [asciicast v3 format](https://docs.asciinema.org/manual/asciicast/v3/)
