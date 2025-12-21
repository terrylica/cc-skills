---
name: asciinema-player
description: Play .cast terminal recordings in browser with seek controls. TRIGGERS - asciinema, .cast file, terminal recording, play cast, recording playback, play recording. Generates HTML player, starts HTTP server, provides localhost link with Quick Tutorial.
allowed-tools: Read, Bash, Write, Glob
---

# asciinema-player

Play terminal session recordings (.cast files) in a browser with full playback controls including seek bar, speed adjustment, and keyboard shortcuts.

> **Platform**: macOS, Linux only (no Windows support)

---

## FIRST - TodoWrite Task Templates

**MANDATORY**: Select and load the appropriate template into TodoWrite before any skill work.

### Template A - Play Single Recording

```
1. Identify .cast file path from user context
2. Run serve_cast.py with path
3. Verify HTTP server started
4. Display Quick Tutorial output (see below)
5. Provide clickable localhost URL
```

### Template B - Discover and Play Recordings

```
1. Glob for *.cast files in workspace/directory
2. Present list of discovered recordings with sizes
3. Let user select recording
4. Run serve_cast.py for selected file
5. Display Quick Tutorial output
6. Provide clickable localhost URL
```

### Template C - Customize Playback

```
1. Identify .cast file from user
2. Ask about speed preference (default 1x)
3. Ask about theme preference (default monokai)
4. Run serve_cast.py with custom options
5. Display Quick Tutorial output
6. Provide clickable localhost URL
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

## Workflow

1. **Detect** - Identify .cast file path from user mention or Glob discovery
2. **Generate** - Run `serve_cast.py` to create player.html from template
3. **Server** - Check if HTTP server running; start if not
4. **Output** - Display Quick Tutorial and provide clickable link

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

### Documentation

- [asciinema-player docs](https://docs.asciinema.org/manual/player/)
- [Player Options Reference](./references/player-options.md)

### Cleanup (when done)

```bash
# Stop the HTTP server
pkill -f "http.server {port}"
```
````

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
