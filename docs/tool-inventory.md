# Toolchain & Automation Landscape

## Overview

This document catalogs all documentation-related tools, scripts, and automation in the cc-skills ecosystem, with maturity assessment and consolidation opportunities.

---

## Tool Inventory

### 1. Validation & Linting

| Tool                   | Path                           | Purpose                                                                                                     | Maturity                                                                                             |
| ---------------------- | ------------------------------ | ----------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `validate-plugins.mjs` | `scripts/validate-plugins.mjs` | Comprehensive plugin validation: marketplace.json entries, paths, hooks, dependencies, SKILL.md frontmatter | **High** - Production-ready with AJV schema validation, supports `--fix`, `--strict`, `--deps` flags |
| `lychee`               | External (via `lychee.toml`)   | Link checking for all markdown files                                                                        | **Medium** - On-demand via `/link-tools:link-validation`                                             |

### 2. Synchronization Scripts

| Script                         | Path                                   | Purpose                                                       | Maturity                                                       |
| ------------------------------ | -------------------------------------- | ------------------------------------------------------------- | -------------------------------------------------------------- |
| `sync-commands-to-settings.sh` | `scripts/sync-commands-to-settings.sh` | Syncs plugin skills to `~/.claude/commands/` with namespacing | **High** - Automated post-release, handles provenance tracking |
| `sync-hooks-to-settings.sh`    | `scripts/sync-hooks-to-settings.sh`    | Merges plugin hooks.json into user settings                   | **High** - Post-release automation with deduplication          |
| `sync-enabled-plugins.sh`      | `scripts/sync-enabled-plugins.sh`      | Auto-enables new marketplace plugins in settings              | **Medium** - Manual execution, could be automated              |

### 3. Release & Versioning

| Tool                   | Path                           | Purpose                                   | Maturity                                |
| ---------------------- | ------------------------------ | ----------------------------------------- | --------------------------------------- |
| `semantic-release`     | `.releaserc.yml`               | Automated releases with changelog         | **High** - Full CI/CD pipeline          |
| `sync-versions.mjs`    | `scripts/sync-versions.mjs`    | Centralized version synchronization       | **High** - Called by semantic-release   |
| `release-preflight.sh` | `scripts/release-preflight.sh` | Prevents dirty working directory releases | **High** - Integrated in .releaserc.yml |

### 4. Automation Tasks

| Task                | Path                            | Purpose                  | Maturity |
| ------------------- | ------------------------------- | ------------------------ | -------- |
| `release/verify`    | `.mise/tasks/release/verify`    | Pre-release verification | **High** |
| `release/sync`      | `.mise/tasks/release/sync`      | Post-release sync        | **High** |
| `release/preflight` | `.mise/tasks/release/preflight` | Pre-flight checks        | **High** |
| `release/full`      | `.mise/tasks/release/full`      | Full release pipeline    | **High** |
| `release/dry`       | `.mise/tasks/release/dry`       | Dry-run release          | **High** |

### 5. Documentation Generators

| Generator                | Path                                                                 | Purpose                                  | Maturity                                |
| ------------------------ | -------------------------------------------------------------------- | ---------------------------------------- | --------------------------------------- |
| `generate-doc-notes.mjs` | `plugins/itp/skills/semantic-release/scripts/generate-doc-notes.mjs` | ADR/Design Spec linking in release notes | **High** - Integrated in .releaserc.yml |

---

## Manual vs Automated Processes

### Fully Automated (High Maturity)

1. **Release Pipeline**: semantic-release handles versioning, changelog, GitHub release, marketplace sync
2. **Command Sync**: `sync-commands-to-settings.sh` runs post-release
3. **Hook Sync**: `sync-hooks-to-settings.sh` runs post-release
4. **Plugin Validation**: `validate-plugins.mjs` runs pre-release checks
5. **Version Sync**: `sync-versions.mjs` runs during release prepare phase

### Semi-Automated (Medium Maturity)

1. **Link Checking**: lychee on-demand via `/link-tools:link-validation`
2. **Plugin Enablement**: `sync-enabled-plugins.sh` - manual execution required

### Manual Processes (Gaps)

1. **Documentation Formatting**: No automated linting/formatting (e.g., prettier for markdown)
2. **Cross-Reference Validation**: No validation that internal doc links are correct
3. **CLAUDE.md Consistency**: No automated check that plugin CLAUDE.md files follow standards
4. **SKILL.md Template Enforcement**: No validation of SKILL.md structure/content

---

## Gaps & Consolidation Opportunities

### High-Priority Gaps

1. **No Markdown Linting**: Consider adding `markdownlint` or `remark-lint` to validate:
   - Heading hierarchy
   - Link validity (beyond lychee's external link checks)
   - Code block syntax
   - Table formatting

2. **No CLAUDE.md Standard Validator**: Task-1 revealed inconsistencies in plugin CLAUDE.md files. Could extend `validate-plugins.mjs` to:
   - Verify required sections exist
   - Check header format consistency
   - Validate navigation table completeness

3. **No SKILL.md Template Validator**: Each skill should have consistent structure:
   - Frontmatter (name, description)
   - Usage examples
   - Parameters/slots documentation
   - Cross-references to related skills

### Medium-Priority Opportunities

1. **Lychee Integration**: Available on-demand via `/link-tools:link-validation`
2. **Automated Plugin Enablement**: Run `sync-enabled-plugins.sh` as part of post-release

### Low-Priority/Exploratory

1. **Documentation Coverage Metrics**: Track % of plugins with complete CLAUDE.md, SKILL.md coverage
2. **Auto-generated Indexes**: Consider generating plugin index from marketplace.json

---

## Maturity Assessment Summary

| Category                   | Maturity  | Notes                                             |
| -------------------------- | --------- | ------------------------------------------------- |
| Plugin Validation          | 🟢 High   | AJV schemas, comprehensive checks, CI integration |
| Release Automation         | 🟢 High   | Full pipeline from commit to user installation    |
| Link Checking              | 🟡 Medium | On-demand via skill                               |
| Documentation Linting      | 🔴 Low    | No markdown/CLAUDE.md validators                  |
| Cross-Reference Validation | 🔴 Low    | No internal link validation                       |
| Plugin Enablement          | 🟡 Medium | Manual script exists but not automated            |

---

## Recommendations

### Immediate (Quick Wins)

1. **Link checking**: Available on-demand via `/link-tools:link-validation`
2. **Run sync-enabled-plugins.sh post-release**: Add to .releaserc.yml successCmd

### Short-Term

1. **Add markdownlint to validate-plugins.mjs**: Check CLAUDE.md formatting
2. **Extend validate-plugins.mjs**: Add CLAUDE.md structure validation

### Long-Term

1. **Create SKILL.md schema**: Define required sections, validate all skills
2. **Build documentation dashboard**: Track coverage metrics over time

---

## Related Tasks

- Task-1: Documentation Standards Audit (completed) - Found CLAUDE.md inconsistencies
- Task-2: Cross-Platform Format Analysis (completed) - Format inventory created
- Task-4: Version Consistency Strategy - Related to version management tools
- Task-8: Accessibility & Findability Review - Links and navigation assessment
