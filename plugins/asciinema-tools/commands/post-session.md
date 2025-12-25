---
description: Post-session workflow - convert + analyze in one step. TRIGGERS - post session, analyze recording, session review.
allowed-tools: Bash, Grep, AskUserQuestion, Glob, Write
argument-hint: "[file] [-q|--quick] [-f|--full] [-d domains] [--json] [--open]"
---

# /asciinema-tools:post-session

Post-session analysis: convert .cast to .txt and run analysis.

## Arguments

| Argument        | Description                        |
| --------------- | ---------------------------------- |
| `file`          | Path to .cast file                 |
| `-q, --quick`   | Quick analysis (curated + summary) |
| `-f, --full`    | Full analysis (curated + YAKE)     |
| `-d, --domains` | Domains: `trading,ml,dev,claude`   |
| `--json`        | Export results as JSON             |
| `--open`        | Open output in editor              |

## Execution

Chains: convert -> analyze -> report

### Skip Logic

- If `file` provided -> use that file
- If `-q` or `-f` provided -> skip workflow config
- If `-d` provided -> use specified domains

### Workflow

1. **Config**: Single AskUserQuestion for all options
2. **Convert**: Run asciinema convert -f txt
3. **Analyze**: Run keyword analysis
4. **Report**: Display or export results

## Example Usage

```bash
# Quick analysis on recent session
/asciinema-tools:post-session session.cast -q -d trading

# Full analysis with JSON export
/asciinema-tools:post-session session.cast -f --json

# Interactive mode
/asciinema-tools:post-session
```
