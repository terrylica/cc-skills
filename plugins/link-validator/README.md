# link-validator Plugin

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-1-blue.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

Validate markdown link portability in Claude Code skills and plugins for cross-installation compatibility.

## The Problem

Skills with absolute repo paths break when installed elsewhere:

| Path Type       | Example                 | Works When Installed? |
| --------------- | ----------------------- | --------------------- |
| Absolute repo   | `/skills/foo/SKILL.md`  | No - path breaks      |
| Relative        | `./references/guide.md` | Yes - always resolves |
| Relative parent | `../sibling/SKILL.md`   | Yes - always resolves |

## When to Use

- Before distributing a skill or plugin
- After creating new markdown links in skills
- When CI reports link validation failures
- To audit existing skills for portability issues

## Features

- **Zero Dependencies**: PEP 723 inline script - runs with `uv run` directly
- **Clear Violations Report**: Shows file, line number, and suggested fix
- **Recursive Validation**: Validates entire plugins with multiple skills
- **Exit Codes**: Machine-readable results for CI integration

## Quick Start

```bash
# Validate a single skill
uv run scripts/validate_links.py ~/.claude/skills/my-skill/

# Validate a plugin with multiple skills
uv run scripts/validate_links.py ~/.claude/plugins/my-plugin/

# Validate current directory
uv run scripts/validate_links.py .
```

## Exit Codes

| Code | Meaning                                 |
| ---- | --------------------------------------- |
| 0    | All links valid (relative paths)        |
| 1    | Violations found (absolute repo paths)  |
| 2    | Error (invalid path, no markdown files) |

## What Gets Checked

**Flagged as Violations:**

- `/skills/foo/SKILL.md` - Absolute repo path
- `/docs/guide.md` - Absolute repo path

**Allowed (Pass):**

- `./references/guide.md` - Relative same directory
- `../sibling/SKILL.md` - Relative parent
- `https://example.com` - External URL
- `#section` - Anchor link

## Installation

```bash
# Via Claude Code plugin manager
/plugin install cc-skills@link-validator

# Or manually copy
cp -r plugins/link-validator ~/.claude/skills/
```

## References

- [Link Patterns Reference](./references/link-patterns.md) - Detailed pattern explanations and fix strategies

---

**Built for Claude Code CLI** | Ensures skill portability across installations
