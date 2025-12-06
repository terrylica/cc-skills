# latex-tools

LaTeX document automation plugin for Claude Code with build, setup, and table generation skills.

## Skills

| Skill            | Description                                                          |
| ---------------- | -------------------------------------------------------------------- |
| **latex-build**  | Build automation with latexmk, live preview, and dependency tracking |
| **latex-setup**  | macOS environment setup with MacTeX, Skim viewer, and SyncTeX        |
| **latex-tables** | Modern table creation with tabularray package                        |

## Installation

```bash
/plugin marketplace add terrylica/cc-skills
/plugin install latex-tools@cc-skills
```

## Usage

Skills are model-invoked — Claude automatically activates them based on context.

**Trigger phrases:**

- "compile my LaTeX document" → latex-build
- "set up LaTeX on my Mac" → latex-setup
- "create a LaTeX table" → latex-tables

## Requirements

- macOS (for latex-setup with MacTeX/Skim)
- MacTeX or TeX Live installation (for latex-build)

## License

MIT
