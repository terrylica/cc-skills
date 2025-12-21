---
name: asciinema-player
description: Play .cast terminal recordings in browser with seek controls. TRIGGERS - asciinema, .cast file, terminal recording, play cast, recording playback, play recording. Uses AskUserQuestion for interactive file selection, generates HTML player, starts HTTP server.
allowed-tools: Read, Bash, Write, Glob, AskUserQuestion
---

# asciinema-player

Play terminal session recordings (.cast files) in a browser with full playback controls including seek bar, speed adjustment, and keyboard shortcuts.

> **Platform**: macOS, Linux only (no Windows support)

---

## Default Workflow (AskUserQuestion-Driven)

**This skill prioritizes interactive file discovery.** When invoked, follow this flow:

### Step 1: Discover Recordings

```bash
# Search for .cast files in current workspace and common locations
fd -e cast . --max-depth 5 2>/dev/null | head -20
```

Also check these common locations:

- Current working directory
- `./tmp/` subdirectory
- `~/scripts/tmp/`
- `~/.local/share/asciinema/`

### Step 2: Present Choices with AskUserQuestion

**If recordings found**, use AskUserQuestion to let user select:

```
Question: "Which recording would you like to play?"
Header: "Recording"
Options:
  - Label: "{filename} ({size})"
    Description: "Recorded {date}, {duration} duration"
  - Label: "{filename2} ({size})"
    Description: "Recorded {date}, {duration} duration"
  - ... (up to 4 most recent)
```

**If no recordings found**, inform user and ask for path:

```
"No .cast files found in the current workspace.

To record a terminal session:
  asciinema rec session.cast

Or provide a path to an existing .cast file."
```

### Step 3: Optional Playback Preferences

After file selection, optionally ask about preferences:

```
Question: "Customize playback settings?"
Header: "Settings"
Options:
  - Label: "Default (1x, monokai)"
    Description: "Standard playback with monokai theme"
  - Label: "Fast review (2x speed)"
    Description: "Double speed for quick review"
  - Label: "Custom"
    Description: "Choose speed and theme manually"
```

### Step 4: Generate and Serve

Run the player script and display the Quick Tutorial.

---

## FIRST - TodoWrite Task Templates

**MANDATORY**: Select and load the appropriate template into TodoWrite before any skill work.

### Template A - Interactive Discovery (Default)

```
1. Glob for *.cast files in workspace + common locations
2. AskUserQuestion: present discovered files with sizes/dates
3. AskUserQuestion: playback preferences (optional)
4. Run serve_cast.py with selected file and options
5. Verify HTTP server started
6. Display Quick Tutorial output
7. Provide clickable localhost URL
```

### Template B - Direct Playback (User Provided Path)

```
1. Validate provided .cast file path exists
2. Run serve_cast.py with path
3. Verify HTTP server started
4. Display Quick Tutorial output
5. Provide clickable localhost URL
```

### Template C - Batch Discovery

```
1. Glob for *.cast files recursively
2. Present full list with metadata (size, date, duration)
3. AskUserQuestion: let user select multiple or single
4. Generate player(s) as needed
5. Display Quick Tutorial output
```

---

## Quick Start

```bash
# Generate player and start server
uv run scripts/serve_cast.py ~/recordings/session.cast

# With options
uv run scripts/serve_cast.py session.cast --port 8080 --speed 2 --theme dracula
```

Open: <http://localhost:8000/player.html>

---

## Quick Tutorial Output (Display When Invoked)

When this skill is invoked, display the following to educate the user:

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

### Recording New Sessions

```bash
# Start recording
asciinema rec my-session.cast

# Stop recording
exit  # or Ctrl+D
```

### Documentation

- [asciinema-player docs](https://docs.asciinema.org/manual/player/)
- [Player Options Reference](./references/player-options.md)

### Cleanup (when done)

```bash
# Stop the HTTP server
pkill -f "http.server {port}"
```
````

---

## Script Usage

**Basic**:

```bash
uv run scripts/serve_cast.py <cast_file>
```

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

## Bundled Resources

| Resource                                                       | Purpose                         |
| -------------------------------------------------------------- | ------------------------------- |
| [scripts/serve_cast.py](./scripts/serve_cast.py)               | Generate player + start server  |
| [assets/player-template.html](./assets/player-template.html)   | HTML template with placeholders |
| [references/player-options.md](./references/player-options.md) | Full options reference          |

---

## Post-Change Checklist (Self-Maintenance)

After modifying THIS skill:

1. [ ] Update references/player-options.md if options changed
2. [ ] Test with real .cast file
3. [ ] Verify Quick Tutorial output is accurate
4. [ ] Validate with quick_validate.py
5. [ ] Update devops-tools/README.md if triggers changed

---

## Reference Documentation

- [Player Options Reference](./references/player-options.md) - Full configuration options
- [asciinema-player GitHub](https://github.com/asciinema/asciinema-player)
- [asciinema docs](https://docs.asciinema.org/manual/player/)
