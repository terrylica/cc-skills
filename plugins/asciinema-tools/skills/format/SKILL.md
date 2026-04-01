---
name: format
description: Reference for asciinema v3 .cast NDJSON format. TRIGGERS - cast format, asciicast spec, event codes.
allowed-tools: Read, AskUserQuestion, Bash
argument-hint: "[header|events|parsing|all] [-f file] [--live]"
model: haiku
---

# /asciinema-tools:format

Display reference documentation for the asciinema v3 .cast format.

## Arguments

| Argument     | Description                     |
| ------------ | ------------------------------- |
| `header`     | Show header field specification |
| `events`     | Show event codes deep-dive      |
| `parsing`    | Show jq/bash parsing examples   |
| `all`        | Show complete format reference  |
| `-f, --file` | Use specific .cast for examples |
| `--live`     | Run parsing examples on file    |

## Execution

Invoke the `asciinema-cast-format` skill with user-selected section.

### Skip Logic

- If section provided -> skip Phase 1 (section selection)
- If `-f` provided with `parsing` -> skip Phase 2 (example file)

### Workflow

1. **Selection**: AskUserQuestion for section
2. **Example**: AskUserQuestion for example file (if parsing)
3. **Display**: Show requested documentation

## Examples

```bash
# Show header format
/asciinema-tools:format header

# Show event codes
/asciinema-tools:format events

# Parse specific file with live examples
/asciinema-tools:format parsing -f session.cast --live
```

## Troubleshooting

| Issue          | Cause           | Solution                                     |
| -------------- | --------------- | -------------------------------------------- |
| File not found | Invalid path    | Use absolute path or ensure file exists      |
| Parse error    | Invalid NDJSON  | Check file is valid asciinema v3 format      |
| No output      | Missing section | Specify one of: header, events, parsing, all |


## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If the underlying tool's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
