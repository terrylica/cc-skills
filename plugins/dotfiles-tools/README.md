# dotfiles-tools

Chezmoi dotfile management plugin for Claude Code with natural language workflows.

## Skills

| Skill                 | Description                                             |
| --------------------- | ------------------------------------------------------- |
| **chezmoi-workflows** | Track, sync, push dotfiles via natural language prompts |

## Installation

```bash
/plugin marketplace add terrylica/cc-skills
/plugin install dotfiles-tools@cc-skills
```

## Usage

Skills are model-invoked — Claude automatically activates them based on context.

**Trigger phrases:**

- "I edited .zshrc. Track the changes." → chezmoi-workflows
- "Sync my dotfiles from remote." → chezmoi-workflows
- "Push my dotfile changes to GitHub." → chezmoi-workflows
- "Check my dotfile status." → chezmoi-workflows

## Key Features

- **6 Prompt Patterns**: Track changes, sync, push, status, track new, resolve conflicts
- **SLO Validation**: Automatic availability, correctness, observability checks
- **Template Support**: Works with chezmoi `.tmpl` files
- **Secret Detection**: Fail-fast on detected secrets

## Requirements

- Chezmoi 2.66.1+ (`brew install chezmoi`)
- Git 2.51.1+
- Platform: macOS (primary), Linux (secondary)

## License

MIT
