# asciinema-tools Plugin Architecture

## Status

Accepted

## Context and Problem Statement

The cc-skills `devops-tools` plugin contains 3 asciinema-related skills mixed with unrelated DevOps tooling (Doppler, ClickHouse, Telegram bots). Additionally, there's no skill for analyzing .cast files for Claude Code consumption, and no prescriptive workflow for streaming recordings to GitHub during sessions.

Key challenges:

1. 3.8GB, 22-hour recordings need semantic analysis capabilities
2. Claude Code's Read/Grep tools require clean text, not raw NDJSON
3. Existing asciinema skills are scattered across devops-tools
4. No pre-session bootstrap workflow for automatic recording and streaming

## Decision Drivers

- Need semantic analysis of multi-gigabyte terminal recordings
- Claude Code's Read/Grep tools require clean text input
- Existing asciinema skills lack cohesion in devops-tools
- Per-repository orphan branch streaming requires prescriptive setup
- Pre-Claude bootstrap workflow needed to capture everything automatically

## Considered Options

1. **Add analysis skill to devops-tools** - Minimal change, keep existing structure
2. **Create dedicated asciinema-tools plugin** - Clean separation, focused namespace
3. **Inline scripts without skill framework** - No structure, no reusability

## Decision Outcome

Chosen option: **Option 2 - Dedicated asciinema-tools plugin** because:

- Single-responsibility principle for plugin cohesion
- Clear namespace (`/asciinema-tools:*` commands)
- Room for future asciinema-specific skills
- Prescriptive workflows with comprehensive AskUserQuestion flows
- Pre-Claude bootstrap workflow for automatic session capture

### Plugin Structure

```
~/eon/cc-skills/plugins/asciinema-tools/
├── LICENSE                           # MIT (copy from devops-tools)
├── README.md                         # Plugin overview + skill table
├── commands/
│   ├── record.md                     # /asciinema-tools:record
│   ├── play.md                       # /asciinema-tools:play
│   ├── backup.md                     # /asciinema-tools:backup
│   ├── format.md                     # /asciinema-tools:format
│   ├── convert.md                    # /asciinema-tools:convert
│   ├── analyze.md                    # /asciinema-tools:analyze
│   ├── full-workflow.md              # /asciinema-tools:full-workflow
│   ├── post-session.md               # /asciinema-tools:post-session
│   ├── bootstrap.md                  # /asciinema-tools:bootstrap (PRE-CLAUDE)
│   ├── setup.md                      # /asciinema-tools:setup
│   └── hooks.md                      # /asciinema-tools:hooks
├── scripts/
│   ├── bootstrap-claude-session.sh   # Shell script to run BEFORE entering Claude
│   └── idle-chunker.sh               # Generated per-repo chunker script
└── skills/
    ├── asciinema-recorder/           # MIGRATED from devops-tools
    │   └── SKILL.md
    ├── asciinema-player/             # MIGRATED from devops-tools
    │   └── SKILL.md
    ├── asciinema-streaming-backup/   # MIGRATED from devops-tools
    │   ├── SKILL.md
    │   └── references/
    ├── asciinema-cast-format/        # NEW: v3 format reference
    │   └── SKILL.md
    ├── asciinema-converter/          # NEW: .cast to .txt conversion
    │   └── SKILL.md
    └── asciinema-analyzer/           # NEW: keyword/semantic analysis
        ├── SKILL.md
        └── references/
```

### Analysis Tool Selection

| Tool    | Decision  | Rationale                              |
| ------- | --------- | -------------------------------------- |
| ripgrep | Primary   | 50-200ms for 4MB, already installed    |
| YAKE    | Secondary | Unsupervised, no GPU, 0.22s/113K chars |
| spaCy   | Tertiary  | EntityRuler for custom NER patterns    |
| keyBERT | Rejected  | Requires GPU, overkill for logs        |

### Per-Repository Orphan Branch Architecture

Each repository maintains its own orphan branch for recordings:

```
┌────────────────────────────────────────────────────────────────────────────┐
│                        PER-REPOSITORY ORPHAN BRANCHES                       │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Repository                    Orphan Branch              Local Clone       │
│  ─────────────────────────────────────────────────────────────────────────  │
│  terrylica/alpha-forge     →  asciinema-recordings  →  ~/asciinema_recordings/alpha-forge/  │
│  terrylica/cc-skills       →  asciinema-recordings  →  ~/asciinema_recordings/cc-skills/    │
│  459ecs/private-project    →  asciinema-recordings  →  ~/asciinema_recordings/private-project/ │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

### Pre-Claude Bootstrap Workflow

The `/asciinema-tools:bootstrap` command generates a script that runs OUTSIDE Claude Code CLI:

```
1. ONE-TIME SETUP (in Claude Code):
   /asciinema-tools:bootstrap
   → Creates orphan branch if needed
   → Generates bootstrap-claude-session.sh script

2. EACH SESSION (in terminal, BEFORE claude):
   $ source bootstrap-claude-session.sh
   → Starts asciinema recording
   → Starts idle-chunker (streams to GitHub)
   → Traps EXIT for cleanup

3. WORK (in Claude Code):
   $ claude
   → Work normally
   → All terminal output recorded
   → Chunks pushed to GitHub every 30s idle

4. EXIT:
   Ctrl+D or /exit
   → Cleanup trap fires
   → Final chunk pushed
   → GitHub Actions recompresses to brotli
```

### Consequences

**Positive:**

- Clean separation of asciinema concerns from DevOps tooling
- Comprehensive prescriptive workflows with AskUserQuestion
- Smart argument behavior (skip questions when CLI args provided)
- Auto-detection of repository context for orphan branch setup
- Validated tooling stack (ripgrep primary, YAKE secondary)

**Negative:**

- Migration effort to move 3 skills from devops-tools
- Need to update devops-tools README after migration
- Users must update their mental model of skill locations

**Neutral:**

- Bootstrap script runs outside Claude Code (by design)
- GitHub Actions required for brotli recompression

## Validation

### Skill-Architecture Compliance

- All bash blocks use heredoc wrapper: `/usr/bin/env bash << 'NAME_EOF'`
- No `declare -A` (bash 4+ only)
- No `grep -P` (not portable)
- No hardcoded user paths (use `$HOME`)
- Relative links for skill-internal files
- Repo-root links for ADRs/specs

### Functional Requirements

1. `/asciinema-tools:convert` produces .txt from .cast (950:1 compression)
2. `/asciinema-tools:analyze` finds keywords with timestamps
3. `/asciinema-tools:bootstrap` generates working pre-Claude script
4. Orphan branch created with GitHub Actions workflow
5. Streaming works: chunks pushed to GitHub during session

## Related

- [Shell Command Portability ADR](/docs/adr/2025-12-06-shell-command-portability-zsh.md)
- [Plugin Authoring Guide](/docs/plugin-authoring.md)
- [asciinema v3 Format Reference](https://docs.asciinema.org/manual/asciicast/v2/)
