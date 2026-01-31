---
description: Check and install dependencies for asciinema-tools. TRIGGERS - setup, check deps, preflight.
allowed-tools: Bash, AskUserQuestion
argument-hint: "[check|install|repair] [--all] [--core] [--optional] [-y|--yes]"
---

# /asciinema-tools:setup

Check and install all dependencies for asciinema-tools.

## Arguments

| Argument     | Description                       |
| ------------ | --------------------------------- |
| `check`      | Run preflight check (default)     |
| `install`    | Install missing dependencies      |
| `repair`     | Reinstall/upgrade all components  |
| `--all`      | Install all (core + optional)     |
| `--core`     | Install core only (asciinema, rg) |
| `--optional` | Install optional only             |
| `-y, --yes`  | Skip confirmation prompts         |

## Dependencies

| Component | Type     | Installation                 |
| --------- | -------- | ---------------------------- |
| asciinema | Core     | `brew install asciinema`     |
| ripgrep   | Core     | `brew install ripgrep`       |
| iTerm2    | Optional | `brew install --cask iterm2` |
| fswatch   | Optional | `brew install fswatch`       |
| gh CLI    | Optional | `brew install gh`            |
| YAKE      | Optional | `uv run --with yake`         |

## Execution

### Skip Logic

- If action provided -> skip Phase 1 (action selection)
- If `--core/--all/--optional` provided -> skip Phase 2
- If `-y` provided -> skip all confirmations

### Workflow

1. **Check**: Run preflight for all dependencies
2. **Action**: AskUserQuestion for action type
3. **Selection**: AskUserQuestion for components
4. **Install**: Run selected installations
5. **Verify**: Confirm installation success

## Examples

```bash
# Check all dependencies
/asciinema-tools:setup check

# Install core dependencies
/asciinema-tools:setup install --core

# Install everything without prompts
/asciinema-tools:setup install --all -y
```

## Troubleshooting

| Issue               | Cause                  | Solution                           |
| ------------------- | ---------------------- | ---------------------------------- |
| brew not found      | Homebrew not installed | Install from <https://brew.sh>     |
| Permission denied   | Need sudo for install  | Run `brew doctor` for diagnostics  |
| asciinema not found | PATH not updated       | Restart terminal or source profile |
| gh auth failed      | Not authenticated      | Run `gh auth login`                |
| YAKE import error   | Python package missing | `uv pip install yake`              |
