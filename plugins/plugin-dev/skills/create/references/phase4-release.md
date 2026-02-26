# Phase 4: Commit & Release (Detailed)

## 4.1 Stage Changes

```bash
git add plugins/$PLUGIN_NAME/
git add .claude-plugin/marketplace.json
git add docs/adr/$ADR_ID.md
git add docs/design/$ADR_ID/
```

## 4.2 Create Conventional Commit

```bash
git commit -m "feat($PLUGIN_NAME): add plugin for [brief description]

- Create plugin directory structure
- Add plugin.json manifest
- Register in marketplace.json
- Add ADR and design spec

ADR: $ADR_ID"
```

## 4.3 Push to Remote

```bash
/usr/bin/env bash << 'GIT_EOF'
git push origin $(git branch --show-current)
GIT_EOF
```

## 4.4 Semantic Release

**MANDATORY Skill tool call: `itp:semantic-release`** -- activate NOW.

This skill:

- Tags the release
- Updates CHANGELOG
- Creates GitHub release
- Syncs versions across all plugins

**Invoke with CI=false for local execution:**

```bash
/usr/bin/env bash << 'PLUGIN_ADD_SCRIPT_EOF_5'
# PROCESS-STORM-OK
/usr/bin/env bash -c 'CI=false GITHUB_TOKEN=$(gh auth token) npm run release'
PLUGIN_ADD_SCRIPT_EOF_5
```

## Phase 4 Success Criteria

- [ ] All changes committed with conventional commit
- [ ] Pushed to remote
- [ ] semantic-release completed
- [ ] New version tag created
- [ ] GitHub release published

---

## Completion

**Workflow complete!** The new plugin is now:

1. Scaffolded with proper structure
2. Documented with ADR and design spec
3. Components created (as selected)
4. Registered in marketplace.json
5. Validated by scripts and agents
6. Released with semantic versioning

**Output the GitHub release URL:**

```bash
gh release view --json url -q .url
```

**Install the plugin in Claude Code:**

```bash
/plugin marketplace update cc-skills
/plugin install $PLUGIN_NAME@cc-skills
```
