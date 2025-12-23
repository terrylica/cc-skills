**Skill**: [semantic-release](../SKILL.md)

## Workflow Patterns

**Default: Local releases** - Fast, immediate file updates, no CI/CD wait time.

**GitHub Actions**: Optional backup only (2-5 minute delay not recommended for primary workflow).

### Pattern A: Personal Projects (Level 2 + Level 4)

Use for solo projects where you want consistent personal defaults.

**1. Create User Config** (One-time setup)

```bash
/usr/bin/env bash << 'CONFIG_EOF'
# Environment-agnostic path
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp}"
cd "$PLUGIN_DIR/skills/semantic-release"
./scripts/init_user_config.sh
CONFIG_EOF
```

Creates `~/semantic-release-config/` with:

- Git repository (version control your defaults)
- npm package structure (`@username/semantic-release-config`)
- 2025-compliant plugin versions

**2. Customize Defaults** (Optional)

```bash
cd ~/semantic-release-config
vim index.js  # Edit your personal defaults
git add . && git commit -m "feat: customize defaults"
```

**3. Publish** (Optional, for sharing)

```bash
cd ~/semantic-release-config
npm publish --access public
```

**4. Use in Projects**

```bash
/usr/bin/env bash << 'WORKFLOW_PATTERNS_SCRIPT_EOF'
cd /path/to/project
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp}"
"$PLUGIN_DIR/skills/semantic-release/scripts/init_project.sh" --user
WORKFLOW_PATTERNS_SCRIPT_EOF
```

This creates project `.releaserc.yml`:

```yaml
extends: "@username/semantic-release-config"
```

**5. Run Releases Locally** (Primary workflow)

Follow the [Local Release Workflow](./local-release-workflow.md) for the canonical 4-phase process.

```bash
npm run release:dry   # Preview changes
npm run release       # Create release (auto-pushes via successCmd + postrelease)
```

**Note**: Push is handled automatically - no manual `git push` needed.

**Advantages over GitHub Actions:**

- ⚡ Instant (vs 2-5 minute CI/CD wait)
- ✅ Immediate local file sync
- ✅ No `git pull` required to continue working
- ✅ Automatic push via successCmd

### Pattern B: Team Projects (Level 3 + Level 4)

Use for company/team projects requiring shared standards.

**1. Create Organization Config** (Team lead, one-time)

```bash
/usr/bin/env bash << 'CONFIG_EOF_2'
# Environment-agnostic path
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp}"
cd "$PLUGIN_DIR/skills/semantic-release"
./scripts/create_org_config.sh mycompany semantic-release-config ~/org-configs/
CONFIG_EOF_2
```

Creates `~/org-configs/semantic-release-config/` with npm package structure.

**2. Customize for Organization**

```bash
cd ~/org-configs/semantic-release-config
vim index.js  # Set company standards
git remote add origin https://github.com/mycompany/semantic-release-config.git
git push -u origin main
```

**3. Publish to npm**

```bash
npm publish --access public
```

**4. Use in Team Projects** (All team members)

```bash
/usr/bin/env bash << 'CONFIG_EOF_3'
cd /path/to/team-project
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp}"
"$PLUGIN_DIR/skills/semantic-release/scripts/init_project.sh" --org mycompany/semantic-release-config
CONFIG_EOF_3
```

This creates project `.releaserc.yml`:

```yaml
extends: "@mycompany/semantic-release-config"
```

**5. Run Releases Locally** (Recommended)

Follow the [Local Release Workflow](./local-release-workflow.md) for the canonical 4-phase process.

```bash
npm run release:dry   # Preview changes
npm run release       # Create release (auto-pushes)
```

**Note**: GitHub Actions option available but not recommended due to 2-5 minute delay vs instant local releases.

### Pattern C: Standalone Projects (Level 4 Only)

Use for one-off projects with unique requirements.

**Initialize with Inline Config**

```bash
/usr/bin/env bash << 'WORKFLOW_PATTERNS_SCRIPT_EOF_2'
cd /path/to/project
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp}"
"$PLUGIN_DIR/skills/semantic-release/scripts/init_project.sh" --inline
WORKFLOW_PATTERNS_SCRIPT_EOF_2
```

This creates self-contained `.releaserc.yml` with all configuration inline (no extends).

**Run Releases Locally**

Follow the [Local Release Workflow](./local-release-workflow.md) for the canonical 4-phase process.

```bash
npm run release:dry   # Preview changes
npm run release       # Create release (auto-pushes)
```

**Local releases recommended** - Avoid GitHub Actions 2-5 minute wait, get instant file updates.

### All-in-One Release Function

For a shell function that handles the complete 4-phase workflow (PREFLIGHT → SYNC → RELEASE → POSTFLIGHT), see the [Local Release Workflow Quick Reference](./local-release-workflow.md#quick-reference).

**Key features**:

- Validates prerequisites (gh CLI, global semantic-release, authentication, git repo)
- Enforces main branch requirement
- **Preflight**: Blocks release if working directory not clean or no releasable commits
- **Sync**: Pull with rebase, push before release
- **Release**: Execute semantic-release with automatic push via successCmd
- **Postflight**: Verifies pristine state, updates tracking refs
