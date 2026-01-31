# doc-tools

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-9-blue.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

Comprehensive documentation tools for Claude Code: ASCII diagram validation, documentation standards, LaTeX compilation, and Pandoc PDF generation.

Merged from `doc-tools` + `doc-build-tools` plugins.

## Skills

| Skill                     | Description                                                        |
| ------------------------- | ------------------------------------------------------------------ |
| `ascii-diagram-validator` | Validates ASCII box-drawing diagram alignment in markdown files    |
| `documentation-standards` | Markdown documentation standards for LLM-optimized architecture    |
| `glossary-management`     | Manage terminology glossary with Vale vocabulary sync              |
| `latex-build`             | Build automation with latexmk, live preview, dependency tracking   |
| `latex-setup`             | macOS environment setup with MacTeX, Skim viewer, and SyncTeX      |
| `latex-tables`            | Modern table creation with tabularray package                      |
| `pandoc-pdf-generation`   | Markdown to PDF with XeLaTeX, section numbering, TOC, bibliography |
| `plotext-financial-chart` | ASCII financial line charts with dot marker for GitHub markdown    |
| `terminal-print`          | Print iTerm2 terminal output to HP network printer via PDF         |

## Installation

```bash
/plugin marketplace add terrylica/cc-skills
/plugin install doc-tools@cc-skills
```

## Usage

Skills are model-invoked — Claude automatically activates them based on context.

**Trigger phrases:**

- "validate ASCII diagram" → ascii-diagram-validator
- "markdown documentation standards" → documentation-standards
- "sync terms", "glossary validation", "Vale vocabulary" → glossary-management
- "compile my LaTeX document" → latex-build
- "set up LaTeX on my Mac" → latex-setup
- "create a LaTeX table" → latex-tables
- "generate PDF from markdown", "convert to PDF" → pandoc-pdf-generation
- "financial chart", "line chart", "price chart", "plotext" → plotext-financial-chart
- "print terminal", "print session output", "terminal to printer" → terminal-print

## Features

### Documentation Quality

- ASCII box-drawing alignment validation
- Hub-and-spoke progressive disclosure patterns
- Section numbering rules for Pandoc PDF generation

### LaTeX & PDF Build

- Production-proven build script with XeLaTeX
- Section numbering with `--number-sections`
- Table of contents support
- Bibliography with BibTeX/CSL
- LaTeX table spacing fixes

## Dependencies

| Component | Required         | Installation                           |
| --------- | ---------------- | -------------------------------------- |
| MacTeX    | For LaTeX skills | `brew install --cask mactex`           |
| Pandoc    | For PDF gen      | `brew install pandoc`                  |
| Skim      | For PDF preview  | `brew install --cask skim`             |
| Vale      | For glossary     | `brew install vale`                    |
| plotext   | For charts       | `uv pip install plotext`               |
| macOS     | For setup skill  | Required for MacTeX/Skim configuration |

## Troubleshooting

| Issue                          | Cause                  | Solution                            |
| ------------------------------ | ---------------------- | ----------------------------------- |
| xelatex not found              | MacTeX not installed   | `brew install --cask mactex`        |
| Pandoc PDF fails               | Missing LaTeX packages | Run `tlmgr install <package>`       |
| ASCII diagram validation fails | Misaligned characters  | Check Unicode box-drawing alignment |
| Bibliography not rendering     | Missing citeproc       | Add `--citeproc` flag to pandoc     |
| Skim not syncing               | SyncTeX disabled       | Enable in MacTeX preferences        |

## License

MIT
