# cli-anything Plugin

> Reference guide for CLI-Anything: auto-generate agent-controllable CLI harnesses for any GUI app.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [plugins/CLAUDE.md](../CLAUDE.md)

## Overview

Provides a validated reference skill for [HKUDS/CLI-Anything](https://github.com/HKUDS/CLI-Anything), a tool that auto-generates production-ready CLI interfaces for GUI applications via a 7-phase pipeline. All usage patterns in this skill have been verified against the upstream repository.

## Architecture

```
plugins/cli-anything/
├── CLAUDE.md                    # This file
└── skills/
    └── cli-anything/
        └── SKILL.md             # Full validated usage reference
```

## Skill: cli-anything

Reference guide covering:

- 4 installation methods (Claude Code marketplace, manual, OpenCode global/project)
- All 10 slash commands (Claude Code + OpenCode variants)
- Per-app usage examples: GIMP, LibreOffice, Blender, Inkscape
- Test execution patterns (`pytest`, `CLI_ANYTHING_FORCE_INSTALLED=1`)
- The 7-phase HARNESS.md pipeline
- Generated harness directory structure (PEP 420 namespace packages)
- Output verification standards (magic bytes, content analysis)
- Environment variables and prerequisites checklist

## Cross-References

- **Upstream**: [HKUDS/CLI-Anything](https://github.com/HKUDS/CLI-Anything)
- **HARNESS.md**: Methodology document in `cli-anything-plugin/HARNESS.md` (upstream)

## Skills

- [cli-anything](./skills/cli-anything/SKILL.md)
