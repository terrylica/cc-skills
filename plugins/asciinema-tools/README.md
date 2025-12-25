# asciinema-tools

Terminal recording, playback, streaming, and analysis plugin for Claude Code. Record sessions, stream to GitHub, convert to searchable text, and extract insights with semantic analysis.

## Skills

| Skill                          | Description                                                        |
| ------------------------------ | ------------------------------------------------------------------ |
| **asciinema-player**           | Play .cast recordings in iTerm2 with speed controls                |
| **asciinema-recorder**         | Record Claude Code sessions with dynamic workspace-based filenames |
| **asciinema-streaming-backup** | Real-time backup to GitHub orphan branch with idle-chunking        |
| **asciinema-cast-format**      | Reference for asciinema v3 NDJSON format (header, events, parsing) |
| **asciinema-converter**        | Convert .cast to .txt for Claude Code analysis (950:1 compression) |
| **asciinema-analyzer**         | Keyword extraction and density analysis for recordings             |

## Commands

| Command                          | Description                                            |
| -------------------------------- | ------------------------------------------------------ |
| `/asciinema-tools:record`        | Start terminal recording with asciinema                |
| `/asciinema-tools:play`          | Play .cast recordings in iTerm2                        |
| `/asciinema-tools:backup`        | Stream-backup active recordings to GitHub              |
| `/asciinema-tools:format`        | Reference for asciinema v3 .cast format                |
| `/asciinema-tools:convert`       | Convert .cast to .txt for analysis                     |
| `/asciinema-tools:analyze`       | Semantic analysis of converted recordings              |
| `/asciinema-tools:post-session`  | Post-session workflow: convert + analyze               |
| `/asciinema-tools:full-workflow` | Full workflow: record + backup + convert + analyze     |
| `/asciinema-tools:bootstrap`     | Pre-session setup for automatic streaming (PRE-CLAUDE) |
| `/asciinema-tools:setup`         | Check and install dependencies                         |
| `/asciinema-tools:hooks`         | Install/uninstall auto-backup hooks                    |

## Installation

```bash
/plugin marketplace add terrylica/cc-skills
/plugin install asciinema-tools@cc-skills
```

## Usage

Skills are model-invoked based on context. Commands can be invoked directly.

**Skill trigger phrases:**

- "play recording", ".cast file", "terminal recording" -> asciinema-player
- "record session", "asciinema record", "capture terminal" -> asciinema-recorder
- "streaming backup", "orphan branch", "chunked recording" -> asciinema-streaming-backup
- "cast format", "asciicast spec", "event codes" -> asciinema-cast-format
- "convert cast", "cast to txt", "prepare for analysis" -> asciinema-converter
- "analyze cast", "keyword extraction", "density analysis" -> asciinema-analyzer

## Key Features

### Recording & Playback

- **asciinema-player**: Play .cast files in iTerm2 (handles 700MB+ files)
  - Speed controls: 2x, 6x, 16x, custom
  - Clean iTerm2 window via AppleScript
  - Interactive options with AskUserQuestion

- **asciinema-recorder**: Record Claude Code sessions
  - Dynamic filename: `{workspace}_{datetime}.cast`
  - Saves to `$PWD/tmp/` (gitignored)
  - Title, idle limit, quiet mode options

### Streaming Backup

- **asciinema-streaming-backup**: Real-time backup to GitHub orphan branch
  - Per-repository orphan branches
  - Idle-detection chunking (30s default)
  - zstd streaming compression (concatenatable)
  - GitHub Actions auto-recompresses to brotli (~300:1)

- **bootstrap command**: Pre-Claude session setup
  - Runs OUTSIDE Claude Code CLI
  - Sets up asciinema recording + idle-chunker
  - Streams everything to GitHub automatically
  - Cleanup on exit via trap

### Analysis Pipeline

- **asciinema-converter**: Convert .cast to .txt
  - 3.8GB -> 4MB (950:1 compression ratio)
  - ANSI stripped, clean text output
  - Optional timestamp index for navigation

- **asciinema-analyzer**: Semantic analysis
  - Tiered analysis: ripgrep (50-200ms) -> YAKE (1-5s)
  - Curated keyword sets: trading, ML/AI, development, Claude Code
  - Density analysis: find high-concentration sections
  - Auto-discovery with YAKE unsupervised extraction

### Analysis Tiers

| Tier | Tool    | Speed (4MB) | Use Case                  |
| ---- | ------- | ----------- | ------------------------- |
| 1    | ripgrep | 50-200ms    | Curated keyword search    |
| 2    | YAKE    | 1-5s        | Auto-discover keywords    |
| 3    | TF-IDF  | 5-30s       | Topic modeling (optional) |

## Workflow Examples

### Quick Post-Session Analysis

```
/asciinema-tools:post-session session.cast -q -d trading
```

Converts to .txt and runs quick curated keyword analysis for trading domain.

### Full Pre-Claude Workflow

```bash
# 1. In Claude Code: generate bootstrap script
/asciinema-tools:bootstrap

# 2. Exit Claude, run bootstrap
source bootstrap-claude-session.sh

# 3. Start Claude - everything streams automatically
claude

# 4. When done, exit - cleanup runs via trap
exit
```

### Manual Analysis Pipeline

```
/asciinema-tools:convert session.cast --index
/asciinema-tools:analyze session.txt -d trading,ml -t full
```

## Dependencies

| Component       | Required | Installation                 |
| --------------- | -------- | ---------------------------- |
| asciinema CLI   | Yes      | `brew install asciinema`     |
| iTerm2          | Play     | `brew install --cask iterm2` |
| ripgrep         | Analysis | `brew install ripgrep`       |
| YAKE (optional) | Analysis | `uv run --with yake`         |
| fswatch         | Backup   | `brew install fswatch`       |
| gh CLI          | Backup   | `brew install gh`            |

Run `/asciinema-tools:setup` to check and install dependencies.

## Architecture

See [ADR: asciinema-tools Plugin](/docs/adr/2025-12-24-asciinema-tools-plugin.md) for architectural decisions.
