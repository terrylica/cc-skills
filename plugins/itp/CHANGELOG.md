# [3.0.0](https://github.com/terrylica/cc-skills/compare/v2.0.0...v3.0.0) (2025-12-04)

### Features

- **plugin:** rename from itp-workflow to itp for shorter invocation
- **commands:** change `/itp-workflow:itp` to `/itp` and `/itp-workflow:itp-setup` to `/itp-setup`
- **docs:** update all GitHub URLs from `terrylica/itp-workflow` to `terrylica/cc-skills`

### Bug Fixes

- **deps:** simplify Node.js requirement to use latest version
- **docs:** standardize `GH_TOKEN` to `GITHUB_TOKEN` across all semantic-release documentation

### BREAKING CHANGES

- **commands:** Slash commands renamed - use `/itp` instead of `/itp-workflow:itp`

# [2.0.0](https://github.com/terrylica/cc-skills/compare/v1.1.8...v2.0.0) (2025-12-04)

### Features

- **skills:** add standalone graph-easy skill for general GFM diagrams ([b4107f0](https://github.com/terrylica/cc-skills/commit/b4107f06cfc7333970f7e19a38bb777691498686))
- **skills:** enforce mandatory emoji+title in graph-easy diagrams ([891da89](https://github.com/terrylica/cc-skills/commit/891da89bb27d32089664b6d9aaf45abf1abf5e33))

### BREAKING CHANGES

- **skills:** ADRs with unlabeled diagrams will fail preflight.

## [1.1.8](https://github.com/terrylica/cc-skills/compare/v1.1.7...v1.1.8) (2025-12-04)

### Bug Fixes

- **adr-graph-easy:** add explicit GFM collapsible section syntax documentation ([e8bd4ee](https://github.com/terrylica/cc-skills/commit/e8bd4ee56371f05319cf0eadde7ff8fdc3c18ca3))

## [1.1.7](https://github.com/terrylica/cc-skills/compare/v1.1.6...v1.1.7) (2025-12-04)

### Bug Fixes

- **adr-graph-easy:** make collapsible source block MANDATORY for all diagrams ([1df3015](https://github.com/terrylica/cc-skills/commit/1df30151cb38bb7b3ea44a7ffcdf7e66ee8e845c))

## [1.1.6](https://github.com/terrylica/cc-skills/compare/v1.1.5...v1.1.6) (2025-12-04)

### Bug Fixes

- **docs:** add link to Anthropic Claude Code changelog ([8bb2294](https://github.com/terrylica/cc-skills/commit/8bb2294cd203b4544f608dbf709ef918292d63cf))

## [1.1.5](https://github.com/terrylica/cc-skills/compare/v1.1.4...v1.1.5) (2025-12-04)

### Bug Fixes

- **docs:** add Path A vs Path B comparison table ([2e6a643](https://github.com/terrylica/cc-skills/commit/2e6a64303bc765667dac7e0c9c2ea6994241f93a))

## [1.1.4](https://github.com/terrylica/cc-skills/compare/v1.1.3...v1.1.4) (2025-12-04)

### Bug Fixes

- **docs:** use SlashCommand tool call syntax for Path A feedback input ([9bb068e](https://github.com/terrylica/cc-skills/commit/9bb068e50e748f51f89c98e81f84d0aaf271b90e))

## [1.1.3](https://github.com/terrylica/cc-skills/compare/v1.1.2...v1.1.3) (2025-12-04)

### Bug Fixes

- **docs:** update graph-easy diagram with option 3 selection wording ([b6eacd8](https://github.com/terrylica/cc-skills/commit/b6eacd8d191be3b8aace8dec64828b9a6425a68b))

## [1.1.2](https://github.com/terrylica/cc-skills/compare/v1.1.1...v1.1.2) (2025-12-04)

### Bug Fixes

- **docs:** correct two-path workflow - both are rejection paths ([21c9fe6](https://github.com/terrylica/cc-skills/commit/21c9fe6e3ba53602919c42edb6e5ae14f5b9d0cb))

## [1.1.1](https://github.com/terrylica/cc-skills/compare/v1.1.0...v1.1.1) (2025-12-04)

### Bug Fixes

- **docs:** render two-path workflow diagram with graph-easy ([e99430e](https://github.com/terrylica/cc-skills/commit/e99430e96818145190078921624a63f45f057e22))

# [1.1.0](https://github.com/terrylica/cc-skills/compare/v1.0.1...v1.1.0) (2025-12-04)

### Features

- **docs:** add Path B workflow for plan rejection entry point ([452372e](https://github.com/terrylica/cc-skills/commit/452372ea4ce5b4f82be4f178d684560ce6596b69))

## [1.0.1](https://github.com/terrylica/cc-skills/compare/v1.0.0...v1.0.1) (2025-12-03)

### Bug Fixes

- **release:** update marketplace plugin.json during releases ([312cdc7](https://github.com/terrylica/cc-skills/commit/312cdc726c96bca59781d58ef9aea52fd683ec34))
- **semantic-release:** add mandatory account alignment check for multi-account setups ([ee0ba9b](https://github.com/terrylica/cc-skills/commit/ee0ba9bb883a43b898688194c4958a1fc8f245fa))

# Changelog

All notable changes to the itp plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-12-03

### Added

- **Versioning infrastructure**: Added `plugin.json` with semantic versioning
- **Phase 3 skip feedback**: Clear confirmation message when workflow ends on feature branch
- **Skill execution order**: Documented sequential order for Phase 1 skills
- **Branch verification**: Continuation mode (`-c`) now verifies branch matches ADR context
- **Diagram examples**: New reference doc for ADR-type-specific diagram patterns

### Changed

- **ADR status timing**: Clarified that status sync happens BEFORE first task (not after)
- **TodoWrite Phase 3**: Added conditional markers to indicate skip behavior on feature branches
- **Environment-agnostic paths**: Script paths now support both plugin and manual installation

### Fixed

- **Skill name consistency**: All references now use `impl-standards` (was `implement-plan-engineering-standards`)
- **pypi-doppler branch guard**: Added main/master branch validation to prevent accidental publishes

### Removed

- **Emoji in frontmatter**: Moved from description field to body content for cross-platform compatibility
- **Non-standard frontmatter**: Removed `critical-first-action` field (not recognized by Claude Code)

## Upgrade Notes

### From Pre-1.0.0

If you installed manually to `~/.claude/`:

1. **Backup your customizations** (if any):

   ```bash
   cp ~/.claude/commands/go.md ~/.claude/commands/go.md.backup
   ```

2. **Pull latest and reinstall**:

   ```bash
   cd /path/to/cc-skills && git pull
   cp commands/*.md ~/.claude/commands/
   cp -r skills/* ~/.claude/skills/
   ```

3. **Merge any custom modifications** from your backup

### Path Changes

Script paths now use environment detection:

```bash
# Old (manual only)
bash ~/.claude/skills/itp/scripts/install-dependencies.sh

# New (works in both contexts)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}"
bash "$PLUGIN_DIR/scripts/install-dependencies.sh"
```
