# asciinema-tools Plugin

> Terminal recording automation: asciinema capture, launchd daemon for background chunking, Keychain PAT storage, Pushover notifications, cast conversion, and semantic analysis.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [devops-tools CLAUDE.md](../devops-tools/CLAUDE.md)

## Overview

Full terminal recording lifecycle: record sessions, stream to GitHub, convert to searchable text, and extract insights with semantic analysis. Includes a launchd daemon for background idle-chunking.

## Skills

- [analyze](./skills/analyze/SKILL.md)
- [asciinema-analyzer](./skills/asciinema-analyzer/SKILL.md)
- [asciinema-cast-format](./skills/asciinema-cast-format/SKILL.md)
- [asciinema-converter](./skills/asciinema-converter/SKILL.md)
- [asciinema-player](./skills/asciinema-player/SKILL.md)
- [asciinema-recorder](./skills/asciinema-recorder/SKILL.md)
- [asciinema-streaming-backup](./skills/asciinema-streaming-backup/SKILL.md)
- [backup](./skills/backup/SKILL.md)
- [bootstrap](./skills/bootstrap/SKILL.md)
- [convert](./skills/convert/SKILL.md)
- [daemon-logs](./skills/daemon-logs/SKILL.md)
- [daemon-setup](./skills/daemon-setup/SKILL.md)
- [daemon-start](./skills/daemon-start/SKILL.md)
- [daemon-status](./skills/daemon-status/SKILL.md)
- [daemon-stop](./skills/daemon-stop/SKILL.md)
- [finalize](./skills/finalize/SKILL.md)
- [format](./skills/format/SKILL.md)
- [full-workflow](./skills/full-workflow/SKILL.md)
- [hooks](./skills/hooks/SKILL.md)
- [play](./skills/play/SKILL.md)
- [post-session](./skills/post-session/SKILL.md)
- [record](./skills/record/SKILL.md)
- [setup](./skills/setup/SKILL.md)
- [summarize](./skills/summarize/SKILL.md)

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
