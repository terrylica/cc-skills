# Release Workflow Guide

Comprehensive guide for releasing cc-skills marketplace plugins.

## Quick Start

```bash
# Check release status
mise run release:status

# Dry run (preview)
mise run release:dry

# Full release (4 phases)
mise run release:full
```

## 4-Phase Release Workflow

| Phase     | Command                      | Description                             |
| --------- | ---------------------------- | --------------------------------------- |
| Preflight | `mise run release:preflight` | Validate working dir, auth, plugins     |
| Version   | `mise run release:version`   | Run semantic-release (bump + changelog) |
| Sync      | `mise run release:sync`      | Update marketplace, sync hooks          |
| Verify    | `mise run release:verify`    | Confirm tag, release, cache, hooks      |

## Available mise Tasks

```bash
mise tasks                    # List all tasks
mise run release              # Show help
mise run release:status       # Current version info
mise run release:preflight    # Validate before release
mise run release:version      # semantic-release only
mise run release:sync         # Sync hooks + cache
mise run release:verify       # Verify release artifacts
mise run release:full         # Complete 4-phase workflow
mise run release:dry          # Dry-run preview
mise run release:hooks        # Install hooks only
mise run release:clean        # Clean old cache versions
```

## Commit Conventions

All commit types trigger patch releases (marketplace constraint):

| Type        | Release | Release Notes |
| ----------- | ------- | ------------- |
| `feat:`     | minor   | Features      |
| `fix:`      | patch   | Bug Fixes     |
| `docs:`     | patch   | Not shown     |
| `chore:`    | patch   | Not shown     |
| `refactor:` | patch   | Not shown     |

**Tip**: Use `fix(docs):` for documentation changes that should appear in release notes.

## Post-Release Automation

The release workflow automatically:

1. **Updates marketplace repo** - `~/.claude/plugins/marketplaces/cc-skills`
2. **Syncs hooks** - Merges all `hooks.json` files to `~/.claude/settings.json`
3. **Triggers plugin update** - Refreshes plugin cache
4. **Verifies artifacts** - Confirms tag, release, cache presence

## Manual Release (npm)

```bash
# Dry run
npm run release:dry

# Production release
npm run release
```

## Troubleshooting

### Release blocked by preflight

```bash
# Check specific issue
mise run release:preflight

# Common fixes:
git stash                    # Dirty working directory
gh auth login                # GitHub auth expired
bun scripts/validate-plugins.mjs  # Plugin validation
```

### Hooks not synced after release

```bash
# Manual sync
./scripts/sync-hooks-to-settings.sh

# Restart Claude Code for hooks to take effect
```

### Cache not updated

```bash
# Clean old versions
mise run release:clean

# Force re-sync
mise run release:sync
```

## Key Files

| File                                | Purpose                        |
| ----------------------------------- | ------------------------------ |
| `.releaserc.yml`                    | semantic-release configuration |
| `.mise/tasks/release:*`             | mise release tasks             |
| `scripts/release-preflight.sh`      | Preflight validation           |
| `scripts/sync-hooks-to-settings.sh` | Hook synchronization           |
| `scripts/sync-versions.mjs`         | Version alignment across files |

## Related Documentation

- [semantic-release Skill](/plugins/itp/skills/semantic-release/SKILL.md)
- [Version Management ADR](/docs/adr/2025-12-05-centralized-version-management.md)
