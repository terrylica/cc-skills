# doc-build-tools

Document build automation plugin for Claude Code: LaTeX compilation, Pandoc PDF generation, environment setup, and tables.

## Skills

| Skill                     | Description                                                          |
| ------------------------- | -------------------------------------------------------------------- |
| **latex-build**           | Build automation with latexmk, live preview, and dependency tracking |
| **latex-setup**           | macOS environment setup with MacTeX, Skim viewer, and SyncTeX        |
| **latex-tables**          | Modern table creation with tabularray package                        |
| **pandoc-pdf-generation** | Markdown to PDF with XeLaTeX, section numbering, TOC, bibliography   |

## Installation

```bash
/plugin marketplace add terrylica/cc-skills
/plugin install doc-build-tools@cc-skills
```

## Usage

Skills are model-invoked — Claude automatically activates them based on context.

**Trigger phrases:**

- "compile my LaTeX document" → latex-build
- "set up LaTeX on my Mac" → latex-setup
- "create a LaTeX table" → latex-tables
- "generate PDF from markdown", "convert to PDF" → pandoc-pdf-generation

## Key Features

### Pandoc PDF Generation

- Production-proven build script with XeLaTeX
- Section numbering with `--number-sections`
- Table of contents support
- Bibliography with BibTeX/CSL
- LaTeX table spacing fixes

## Requirements

- macOS (for latex-setup with MacTeX/Skim)
- MacTeX or TeX Live installation
- Pandoc (`brew install pandoc`)

## License

MIT
