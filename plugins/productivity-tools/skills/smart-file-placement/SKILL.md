---
name: smart-file-placement
description: Organizes files into hierarchical workspace directories automatically. Use when creating files, organizing workspace, asking where to place files, or mentioning scratch directory.
allowed-tools: Read, Glob, Bash, Edit, Write
---

# Smart File Placement

Workspace orchestrator that automatically places files in the right directory tier based on purpose and lifecycle.

## Overview

Three-tier hierarchical workspace:

- **/var/tmp/$workplace** - Ephemeral session files (cleared after session)
- **$scratch** - Project working files (git-aware: $toplevel/scratch in repos)
- **Git repository** - Production code (never auto-place here)

## When This Skill Activates

- User creates/writes/saves files
- User asks "where should I put X?"
- User mentions: workspace, scratch, directory structure, file placement

## Automatic File Placement Logic

### Smart Inference Heuristics

**Command Context Analysis:**

- "debug" → /var/tmp/$workplace
- "test", "experiment" → $scratch
- "create script", "add feature" → Prompt for git repo location

**File Characteristics:**

- Extensions: _.log, _.tmp, _\_debug._ → /var/tmp
- Extensions: _.draft, _.wip, test\_\* → $scratch
- Source code: User confirms location (safety)

**Lifecycle Signals:**

- Keywords: "temporary", "quick" → /var/tmp
- Keywords: "working on", "draft", "experiment" → $scratch
- Keywords: "production", "commit", "add to repo" → Git repo (manual)

### Placement Decision Tree

```
1. Analyze user request + file characteristics
2. Infer tier: ephemeral | working | permanent
3. Check if target directory exists
   → Missing: Auto-create with mkdir -p
4. Check git status (if in repo)
   → Ensure target not in tracked paths
5. State location: "Creating X in /var/tmp/$workplace/"
6. Execute file operation
```

## Workspace Initialization

When directories don't exist, automatically run initialization:

```bash
if toplevel=$(git rev-parse --show-toplevel 2>/dev/null); then
  workplace=$(basename "$toplevel")
  scratch="$toplevel/scratch"
else
  workplace=$(basename "$PWD")
  scratch="$HOME/$workplace/scratch"
fi

mkdir -p "/var/tmp/$workplace" "$scratch"
```

## Git Integration

### Git-Aware Scratch Directory

- **In git repo**: `$scratch = $toplevel/scratch` (project root)
- **Outside repo**: `$scratch = $HOME/$workplace/scratch`

### Auto-Update .gitignore

When initializing workspace in git repo, automatically add:

```gitignore
# Auto-added by smart-file-placement skill
/scratch/
/var/tmp/
```

**Safety**: Check if patterns already exist before adding.

### Never Auto-Place in Git-Tracked Locations

Before placing files:

1. Check if path is git-tracked: `git ls-files --error-unmatch <path>`
2. If tracked: Abort auto-placement, ask user for confirmation
3. Safety rule: Only auto-place in /var/tmp, $scratch, or /tmp

## Transparency

Claude states location for every file operation:

- "Creating debug.log in /var/tmp/my-project/"
- "Saving experiment.py in $scratch (~/project/scratch/)"

Does NOT explain reasoning (concise operation).

## Examples

### Example 1: Debug Output

**User**: "Run this and capture debug output"
**Claude inference**: debug → /var/tmp
**Action**: Creates output.log in `/var/tmp/my-project/output.log`
**Claude says**: "Creating output.log in /var/tmp/my-project/"

### Example 2: Experimental Script

**User**: "Let me experiment with a data processing script"
**Claude inference**: experiment → $scratch
**Action**: Creates process_data.py in `$scratch/process_data.py`
**Claude says**: "Creating process_data.py in $scratch (~/project/scratch/)"

### Example 3: Production Code

**User**: "Create a new API endpoint"
**Claude inference**: production code → git repo
**Action**: Does NOT auto-place, asks user for location
**Claude says**: "Where should I create this endpoint file? (src/api/...)"

## Security Constraints

1. ✅ Never auto-place in git-tracked directories
2. ✅ Auto-create missing directories (mkdir -p)
3. ✅ Validate all paths within approved boundaries
4. ✅ No automatic file deletion/cleanup

## No Cleanup Operations

Skill only handles placement. User manually manages:

- Session cleanup: `rm -rf /var/tmp/$workplace`
- Scratch cleanup: User reviews/archives as needed

## Initialization Script

The embedded initialization script at `${CLAUDE_PLUGIN_ROOT}/skills/smart-file-placement/scripts/init-workspace.sh` can be:

- Called automatically when skill detects missing directories
- Run manually to set up workspace structure
- Used as Claude Code launch wrapper

To use as launch wrapper, run:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/smart-file-placement/scripts/init-workspace.sh && claude --debug ...
```
