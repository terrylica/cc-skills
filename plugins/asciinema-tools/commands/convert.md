---
description: Convert .cast to .txt for Claude Code analysis. TRIGGERS - convert cast, cast to txt, prepare analysis.
allowed-tools: Bash, AskUserQuestion, Glob, Write
argument-hint: "[file] [-o output] [--index] [--chunks] [--dims] [--analyze]"
---

# /asciinema-tools:convert

Convert asciinema .cast recordings to clean .txt files.

## Arguments

| Argument       | Description                        |
| -------------- | ---------------------------------- |
| `file`         | Path to .cast file                 |
| `-o, --output` | Output path (default: same dir)    |
| `--index`      | Create timestamp indexed version   |
| `--chunks`     | Split at 30s+ idle pauses          |
| `--dims`       | Preserve terminal dimensions       |
| `--analyze`    | Auto-run /analyze after conversion |

## Execution

Invoke the `asciinema-converter` skill with user-selected options.

### Skip Logic

- If `file` provided -> skip Phase 1 (file selection)
- If options provided -> skip Phase 2 (options)
- If `-o` provided -> skip Phase 3 (output location)
- If `--analyze` provided -> skip Phase 5 and auto-run analyze

### Workflow

1. **Preflight**: Check asciinema convert command
2. **Discovery**: Find .cast files
3. **Selection**: AskUserQuestion for file
4. **Options**: AskUserQuestion for conversion options
5. **Location**: AskUserQuestion for output location
6. **Execute**: Run asciinema convert
7. **Report**: Display compression ratio
8. **Next**: AskUserQuestion for follow-up action
