---
name: asciinema-recorder
description: Record Claude Code sessions with asciinema. TRIGGERS - record session, asciinema record, capture terminal, record claude, demo recording, record ASCII, ASCII terminal, terminal screen capture, shell screen capture, ASCII screen capture, screen recording. Generates ready-to-copy commands with dynamic workspace-based filenames.
allowed-tools: Read, Bash, Glob
---

# asciinema-recorder

Generate ready-to-copy commands for recording Claude Code sessions with asciinema. Dynamically creates filenames based on workspace and datetime.

> **Platform**: macOS, Linux (requires asciinema CLI)

---

## Why This Skill?

This skill generates ready-to-copy recording commands with:

- Dynamic workspace-based filename
- Datetime stamp for uniqueness
- Saves to project's tmp/ folder (gitignored)

---

## Requirements

| Component         | Required | Installation             |
| ----------------- | -------- | ------------------------ |
| **asciinema CLI** | Yes      | `brew install asciinema` |

---

## Workflow Phases

### Phase 0: Preflight Check

**Purpose**: Verify asciinema is installed.

```bash
# Check asciinema CLI
which asciinema && asciinema --version
```

If missing, provide installation command:

```bash
# macOS
brew install asciinema

# Linux (apt)
sudo apt install asciinema

# Linux (pip)
pip install asciinema
```

---

### Phase 1: Detect Context & Generate Command

**Purpose**: Generate a copy-paste ready recording command.

#### Step 1.1: Detect Workspace

Extract workspace name from `$PWD`:

```bash
/usr/bin/env bash << 'SKILL_SCRIPT_EOF'
WORKSPACE=$(basename "$PWD")
echo "Workspace: $WORKSPACE"
SKILL_SCRIPT_EOF
```

#### Step 1.2: Generate Datetime

```bash
/usr/bin/env bash << 'SKILL_SCRIPT_EOF_2'
DATETIME=$(date +%Y-%m-%d_%H-%M)
echo "Datetime: $DATETIME"
SKILL_SCRIPT_EOF_2
```

#### Step 1.3: Construct Command

Build the full recording command:

```bash
/usr/bin/env bash << 'SKILL_SCRIPT_EOF_3'
# Command format
asciinema rec $PWD/tmp/${WORKSPACE}_${DATETIME}.cast
SKILL_SCRIPT_EOF_3
```

**Example output (for a project called "my-app"):**

```bash
asciinema rec /home/user/projects/my-app/tmp/my-app_2025-12-21_14-30.cast
```

#### Step 1.4: Ensure tmp/ Directory Exists

```bash
mkdir -p $PWD/tmp
```

---

### Phase 2: User Guidance

**Purpose**: Explain the recording workflow step-by-step.

Present these instructions:

```markdown
## Recording Instructions

1. **Exit Claude Code** - Type `exit` or press `Ctrl+D`
2. **Copy the command** shown above
3. **Paste and run** in your terminal (starts a recorded shell)
4. **Run `claude`** to start Claude Code inside the recording
5. Work normally - everything is captured
6. **Exit Claude Code** - Type `exit` or press `Ctrl+D`
7. **Exit the recording shell** - Type `exit` or press `Ctrl+D` again

Your recording will be saved to:
`$PWD/tmp/{workspace}_{datetime}.cast`
```

---

### Phase 3: Additional Info

**Purpose**: Provide helpful tips for after recording.

```markdown
## Tips

- **Environment variable**: `ASCIINEMA_REC=1` is set during recording
- **Playback**: Use `asciinema-player` skill or `asciinema play file.cast`
- **Upload (optional)**: `asciinema upload file.cast` (requires account)
- **Markers**: Add `asciinema marker` during recording for navigation points
```

---

## TodoWrite Task Templates

### Template: Record Claude Code Session

```
1. [Preflight] Check asciinema CLI installed
2. [Preflight] Offer installation if missing
3. [Context] Detect current workspace from $PWD
4. [Context] Generate datetime slug
5. [Context] Ensure tmp/ directory exists
6. [Command] Construct full recording command
7. [Guidance] Display step-by-step instructions
8. [Guidance] Show additional tips (playback, upload)
9. Verify against Skill Quality Checklist
```

---

## Post-Change Checklist

After modifying this skill:

1. [ ] Command generation still uses `$PWD` (no hardcoded paths)
2. [ ] Guidance steps remain clear and platform-agnostic
3. [ ] TodoWrite template matches actual workflow
4. [ ] README.md entry remains accurate
5. [ ] Validate with quick_validate.py

---

## CLI Options Reference

| Option | Flag | Description                         |
| ------ | ---- | ----------------------------------- |
| Title  | `-t` | Recording title (for asciinema.org) |
| Quiet  | `-q` | Suppress status messages            |
| Append | `-a` | Append to existing recording        |

---

## Troubleshooting

### "Cannot record from within Claude Code"

**Cause**: asciinema must wrap the program, not be started from inside.

**Fix**: Exit Claude Code first, then run the generated command.

### "Recording file too large"

**Cause**: Long sessions produce large files.

**Fix**:

- Use `asciinema upload` to store online instead of locally
- Split long sessions into smaller recordings

### "Playback shows garbled output"

**Cause**: Terminal size mismatch.

**Fix**: Use `-r` flag during playback to resize terminal.

---

## Reference Documentation

- [asciinema rec Usage](https://docs.asciinema.org/manual/cli/usage/)
- [asciinema CLI Options](https://man.archlinux.org/man/extra/asciinema/asciinema-rec.1.en)
- [asciinema Markers](https://docs.asciinema.org/manual/cli/markers/)
