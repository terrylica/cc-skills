**Skill**: [asciinema-player](../SKILL.md)

# Player Options Reference

Configuration options for the asciinema web player.

## Playback Options

| Option          | Type  | Default | Description                             |
| --------------- | ----- | ------- | --------------------------------------- |
| `speed`         | float | 1.0     | Playback speed (0.5 = half, 2 = double) |
| `idleTimeLimit` | int   | null    | Max idle seconds to show (clips pauses) |
| `startAt`       | int   | 0       | Start playback at N seconds             |
| `loop`          | bool  | false   | Loop playback                           |
| `autoPlay`      | bool  | false   | Start playing automatically             |

## Display Options

| Option               | Type   | Default     | Description                          |
| -------------------- | ------ | ----------- | ------------------------------------ |
| `fit`                | string | 'width'     | 'width', 'height', 'both', or 'none' |
| `theme`              | string | 'asciinema' | Color theme                          |
| `terminalFontFamily` | string | -           | Custom font family                   |
| `terminalFontSize`   | string | -           | Font size (e.g., '15px')             |

## Available Themes

- asciinema (default)
- monokai
- tango
- solarized-dark
- solarized-light
- dracula
- nord

## Keyboard Controls

| Key       | Action                    |
| --------- | ------------------------- |
| `Space`   | Play / Pause              |
| `←` `→`   | Seek 5 seconds            |
| `0-9`     | Jump to 0%-90%            |
| `[` `]`   | Decrease / Increase speed |
| `f`       | Fullscreen                |
| `Shift+←` | Seek to previous marker   |
| `Shift+→` | Seek to next marker       |

## CDN Versions

Current stable: v3.9.0

```html
<link
  rel="stylesheet"
  href="https://cdn.jsdelivr.net/npm/asciinema-player@3.9.0/dist/bundle/asciinema-player.css"
/>
<script src="https://cdn.jsdelivr.net/npm/asciinema-player@3.9.0/dist/bundle/asciinema-player.min.js"></script>
```

## Large File Handling

Tested with 751MB .cast files - works without issues. For large files:

- Use `idleTimeLimit: 2` to reduce visual pauses
- Consider `speed: 2` for faster review
- Click/drag progress bar to seek

## Script Usage

```bash
# Basic usage
uv run scripts/serve_cast.py ~/recordings/session.cast

# With options
uv run scripts/serve_cast.py session.cast --port 8080 --speed 2 --theme dracula

# Stop the server when done
pkill -f "http.server 8000"
```

## External Documentation

- [asciinema-player GitHub](https://github.com/asciinema/asciinema-player)
- [asciinema docs](https://docs.asciinema.org/manual/player/)
- [Keyboard shortcuts](https://github.com/asciinema/asciinema-player#keyboard-shortcuts)
