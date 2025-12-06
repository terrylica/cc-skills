# devops-tools

DevOps automation plugin for Claude Code with Doppler credential workflows and session recovery troubleshooting.

## Skills

| Skill                 | Description                                                        |
| --------------------- | ------------------------------------------------------------------ |
| **doppler-workflows** | PyPI publishing, AWS credential rotation, multi-service patterns   |
| **session-recovery**  | Troubleshoot Claude Code session issues and HOME variable problems |

## Installation

```bash
/plugin marketplace add terrylica/cc-skills
/plugin install devops-tools@cc-skills
```

## Usage

Skills are model-invoked — Claude automatically activates them based on context.

**Trigger phrases:**

- "publish to PyPI" → doppler-workflows
- "rotate AWS credentials" → doppler-workflows
- "no conversations found to resume" → session-recovery
- "sessions not saving" → session-recovery

## Key Features

### Doppler Workflows

- PyPI token management with project-scoped tokens
- AWS credential rotation with zero-exposure workflow
- Multi-token/multi-account patterns
- Troubleshooting 403 errors and token issues

### Session Recovery

- HOME variable diagnosis
- Session file location troubleshooting
- Legacy session migration
- IDE/terminal configuration checks

## Requirements

- Doppler CLI installed (`brew install dopplerhq/cli/doppler`)
- Claude Code CLI

## License

MIT
