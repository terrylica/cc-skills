# asciinema-tools Plugin

> Terminal recording automation: asciinema capture, launchd daemon for background chunking, Keychain PAT storage, Pushover notifications, cast conversion, and semantic analysis.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [devops-tools CLAUDE.md](../devops-tools/CLAUDE.md)

## Overview

Full terminal recording lifecycle: record sessions, stream to GitHub, convert to searchable text, and extract insights with semantic analysis. Includes a launchd daemon for background idle-chunking.

## Skills

| Skill                        | Purpose                                                     |
| ---------------------------- | ----------------------------------------------------------- |
| `asciinema-player`           | Play .cast recordings in iTerm2 with speed controls         |
| `asciinema-recorder`         | Record sessions with dynamic workspace-based filenames      |
| `asciinema-streaming-backup` | Real-time backup to GitHub orphan branch with idle-chunking |
| `asciinema-cast-format`      | Reference for asciinema v3 NDJSON format                    |
| `asciinema-converter`        | Convert .cast to .txt for analysis (950:1 compression)      |
| `asciinema-analyzer`         | Keyword extraction and density analysis                     |

## Commands

| Command                          | Purpose                                    |
| -------------------------------- | ------------------------------------------ |
| `/asciinema-tools:record`        | Start terminal recording                   |
| `/asciinema-tools:play`          | Play .cast recordings in iTerm2            |
| `/asciinema-tools:backup`        | Stream-backup to GitHub                    |
| `/asciinema-tools:format`        | Reference for .cast format                 |
| `/asciinema-tools:convert`       | Convert .cast to .txt                      |
| `/asciinema-tools:analyze`       | Semantic analysis of recordings            |
| `/asciinema-tools:summarize`     | AI-powered iterative deep-dive             |
| `/asciinema-tools:post-session`  | Finalize + convert + summarize             |
| `/asciinema-tools:full-workflow` | Record + backup + convert + analyze        |
| `/asciinema-tools:bootstrap`     | Pre-session setup (runs OUTSIDE Claude)    |
| `/asciinema-tools:finalize`      | Finalize orphaned recordings               |
| `/asciinema-tools:setup`         | Check and install dependencies             |
| `/asciinema-tools:hooks`         | Install/uninstall auto-backup hooks        |
| `/asciinema-tools:daemon-setup`  | Set up chunker daemon (interactive wizard) |
| `/asciinema-tools:daemon-start`  | Start the chunker daemon                   |
| `/asciinema-tools:daemon-stop`   | Stop the chunker daemon                    |
| `/asciinema-tools:daemon-status` | Check daemon status                        |
| `/asciinema-tools:daemon-logs`   | View chunker daemon logs                   |

## Analysis Pipeline

| Tier | Tool    | Speed (4MB) | Use Case                  |
| ---- | ------- | ----------- | ------------------------- |
| 1    | ripgrep | 50-200ms    | Curated keyword search    |
| 2    | YAKE    | 1-5s        | Auto-discover keywords    |
| 3    | TF-IDF  | 5-30s       | Topic modeling (optional) |
