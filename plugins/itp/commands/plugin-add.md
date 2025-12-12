---
allowed-tools: Read, Write, Edit, Bash(node:*), Bash(git:*), Bash(npm:*), Bash(ls:*), Bash(mkdir:*), Grep, Glob, TodoWrite, TodoRead, AskUserQuestion, Skill, Task
argument-hint: "[plugin-name] (optional - will prompt if not provided)"
description: "Add a new plugin to Claude Code marketplace with validation, ADR, and release automation"
---

<!-- ⛔⛔⛔ MANDATORY: READ THIS ENTIRE FILE BEFORE ANY ACTION ⛔⛔⛔ -->

# ⛔ Add Plugin to Marketplace — STOP AND READ

**DO NOT ACT ON ASSUMPTIONS. Read this file first.**

This is a structured workflow command for adding a new plugin to a Claude Code marketplace.

Your FIRST and ONLY action right now: **Execute the TodoWrite below.**

## ⛔ MANDATORY FIRST ACTION: TodoWrite Initialization

**YOUR FIRST ACTION MUST BE the TodoWrite call below.**

DO NOT:

- ❌ Create any directories before TodoWrite
- ❌ Read marketplace.json before TodoWrite
- ❌ Ask questions before TodoWrite
- ❌ Jump to any phase without completing Step 0

### Step 0.1: Detect Marketplace Root

Before executing TodoWrite, verify you're in a marketplace directory:

```bash
# Check for marketplace.json in cwd
if [ -f ".claude-plugin/marketplace.json" ]; then
  echo "✅ Marketplace detected: $(jq -r .name .claude-plugin/marketplace.json)"
else
  echo "❌ Not a marketplace directory. Run from a marketplace root."
  exit 1
fi
```

### Step 0.2: Execute MANDATORY TodoWrite

**Execute TodoWrite NOW with this template:**

```
TodoWrite with todos:

- "[Plugin] Phase 0: Detect marketplace root" | in_progress
- "[Plugin] Phase 0: Interactive prompts (name, category, components)" | pending
- "[Plugin] Phase 0: Confirm plugin doesn't exist" | pending
- "[Plugin] Phase 1: Skill → plugin-structure (scaffold)" | pending
- "[Plugin] Phase 1: Create plugin directory + plugin.json" | pending
- "[Plugin] Phase 1: Skill → implement-plan-preflight (ADR)" | pending
- "[Plugin] Phase 2: Skill → skill-architecture (if has-skills)" | pending
- "[Plugin] Phase 2: Skill → hook-development (if has-hooks)" | pending
- "[Plugin] Phase 2: Skill → command-development (if has-commands)" | pending
- "[Plugin] Phase 2: Skill → agent-development (if has-agents)" | pending
- "[Plugin] Phase 2: Agent → skill-reviewer (if skills created)" | pending
- "[Plugin] Phase 3: Add to marketplace.json" | pending
- "[Plugin] Phase 3: Run validate-plugins.mjs" | pending
- "[Plugin] Phase 3: Skill → code-hardcode-audit" | pending
- "[Plugin] Phase 3: Agent → plugin-validator" | pending
- "[Plugin] Phase 4: Git commit (conventional format)" | pending
- "[Plugin] Phase 4: Push to remote" | pending
- "[Plugin] Phase 4: Skill → semantic-release" | pending
```

**After TodoWrite completes, proceed to Phase 0 section below.**

---

## Quick Reference

### Skills Invoked (Optimized Sequence)

| Order | Skill                    | Phase | Purpose                           | Invocation                                     |
| ----- | ------------------------ | ----- | --------------------------------- | ---------------------------------------------- |
| 1     | plugin-structure         | 1     | Directory & manifest              | `Skill(plugin-dev:plugin-structure)`           |
| 2     | implement-plan-preflight | 1     | ADR + Design Spec + Diagrams      | `Skill(itp:implement-plan-preflight)`          |
| 3     | skill-architecture       | 2     | Create skills (if has-skills)     | `Skill(skill-architecture:skill-architecture)` |
| 4     | hook-development         | 2     | Create hooks (if has-hooks)       | `Skill(plugin-dev:hook-development)`           |
| 5     | command-development      | 2     | Create commands (if has-commands) | `Skill(plugin-dev:command-development)`        |
| 6     | agent-development        | 2     | Create agents (if has-agents)     | `Skill(plugin-dev:agent-development)`          |
| 7     | code-hardcode-audit      | 3     | Quality audit                     | `Skill(itp:code-hardcode-audit)`               |
| 8     | semantic-release         | 4     | Version & publish                 | `Skill(itp:semantic-release)`                  |

### Skills EXCLUDED (Redundant)

| Skill                        | Reason Excluded                                        |
| ---------------------------- | ------------------------------------------------------ |
| plugin-dev:skill-development | Use skill-architecture instead (3x more comprehensive) |
| plugin-dev:plugin-settings   | Merged into hook-development                           |
| itp:adr-graph-easy-architect | Invoked BY implement-plan-preflight (not separately)   |

### Agents Spawned

| Phase | Agent            | Purpose                  | Invocation                          |
| ----- | ---------------- | ------------------------ | ----------------------------------- |
| 2     | skill-reviewer   | Review skill quality     | `Task(plugin-dev:skill-reviewer)`   |
| 3     | plugin-validator | Validate final structure | `Task(plugin-dev:plugin-validator)` |

### File Locations

| Artifact         | Path                                    | Notes                      |
| ---------------- | --------------------------------------- | -------------------------- |
| Plugin Directory | `plugins/{name}/`                       | Main plugin folder         |
| Plugin Manifest  | `plugins/{name}/plugin.json`            | Required manifest          |
| Plugin README    | `plugins/{name}/README.md`              | Documentation              |
| Marketplace JSON | `.claude-plugin/marketplace.json`       | Must add plugin entry      |
| ADR              | `docs/adr/YYYY-MM-DD-{name}.md`         | Created by preflight skill |
| Design Spec      | `docs/design/YYYY-MM-DD-{name}/spec.md` | Created by preflight skill |

---

## Phase 0: Discovery & Validation

### 0.1 Verify Marketplace Root

First, confirm we're in a marketplace directory:

```bash
# Must have .claude-plugin/marketplace.json
ls -la .claude-plugin/marketplace.json

# Extract marketplace info
MARKETPLACE_NAME=$(jq -r .name .claude-plugin/marketplace.json)
MARKETPLACE_VERSION=$(jq -r .version .claude-plugin/marketplace.json)
echo "Marketplace: $MARKETPLACE_NAME v$MARKETPLACE_VERSION"
```

### 0.2 Interactive Prompts

Use AskUserQuestion to gather plugin details:

**Q1: Plugin Name** (if not provided as argument)

```
AskUserQuestion with questions:
- question: "What should this plugin be called? Use kebab-case (e.g., 'my-plugin-name')"
  header: "Plugin Name"
  options:
    - label: "Custom name"
      description: "Enter a kebab-case plugin name"
  multiSelect: false
```

**Q2: Category**

```
AskUserQuestion with questions:
- question: "What category does this plugin belong to?"
  header: "Category"
  options:
    - label: "development (Recommended)"
      description: "Tools for developers"
    - label: "productivity"
      description: "Workflow automation"
    - label: "devops"
      description: "Infrastructure & operations"
    - label: "documents"
      description: "Documentation tools"
  multiSelect: false
```

**Q3: Components**

```
AskUserQuestion with questions:
- question: "What components will this plugin include?"
  header: "Components"
  options:
    - label: "Skills"
      description: "Domain knowledge & capabilities (SKILL.md files)"
    - label: "Hooks"
      description: "Event-driven automation (hooks.json)"
    - label: "Commands"
      description: "Slash commands (commands/*.md)"
    - label: "Agents"
      description: "Autonomous subagents (agents/*.md)"
  multiSelect: true
```

**Store responses:**

```bash
PLUGIN_NAME="${ARGUMENTS:-<from-q1>}"
PLUGIN_CATEGORY="<from-q2>"
HAS_SKILLS=<true|false>
HAS_HOOKS=<true|false>
HAS_COMMANDS=<true|false>
HAS_AGENTS=<true|false>
```

### 0.3 Confirm Plugin Doesn't Exist

```bash
# Check if plugin directory already exists
if [ -d "plugins/$PLUGIN_NAME" ]; then
  echo "❌ Plugin already exists: plugins/$PLUGIN_NAME"
  exit 1
fi

# Check if already in marketplace.json
if jq -e ".plugins[] | select(.name == \"$PLUGIN_NAME\")" .claude-plugin/marketplace.json > /dev/null 2>&1; then
  echo "❌ Plugin already registered in marketplace.json: $PLUGIN_NAME"
  exit 1
fi

echo "✅ Plugin name '$PLUGIN_NAME' is available"
```

### Phase 0 Gate

**STOP. Verify before proceeding to Phase 1:**

- [ ] Marketplace root detected (`.claude-plugin/marketplace.json` exists)
- [ ] Plugin name collected (kebab-case, no spaces)
- [ ] Category selected
- [ ] Components selected (skills/hooks/commands/agents)
- [ ] Plugin directory does NOT exist
- [ ] Plugin NOT in marketplace.json

---

## Phase 1: Scaffold Plugin

### 1.1 Invoke plugin-structure Skill

**MANDATORY Skill tool call: `plugin-dev:plugin-structure`** — activate NOW.

This skill provides:

- Directory structure patterns
- plugin.json template
- README.md template

### 1.2 Create Plugin Directory

```bash
# Create plugin directory structure
mkdir -p plugins/$PLUGIN_NAME

# If has-skills:
mkdir -p plugins/$PLUGIN_NAME/skills

# If has-hooks:
mkdir -p plugins/$PLUGIN_NAME/hooks

# If has-commands:
mkdir -p plugins/$PLUGIN_NAME/commands

# If has-agents:
mkdir -p plugins/$PLUGIN_NAME/agents
```

### 1.3 Generate plugin.json

Get version from marketplace for consistency:

```bash
MARKETPLACE_VERSION=$(jq -r .version .claude-plugin/marketplace.json)
```

Create `plugins/$PLUGIN_NAME/plugin.json`:

```json
{
  "name": "$PLUGIN_NAME",
  "version": "$MARKETPLACE_VERSION",
  "description": "TODO: Add description",
  "author": {
    "name": "Terry Li",
    "url": "https://github.com/terrylica"
  }
}
```

### 1.4 Create ADR and Design Spec

**MANDATORY Skill tool call: `itp:implement-plan-preflight`** — activate NOW.

This skill:

- Creates ADR at `docs/adr/YYYY-MM-DD-$PLUGIN_NAME.md`
- Creates Design Spec at `docs/design/YYYY-MM-DD-$PLUGIN_NAME/spec.md`
- Internally invokes `adr-graph-easy-architect` for diagrams

**ADR ID Format:**

```bash
ADR_ID="$(date +%Y-%m-%d)-$PLUGIN_NAME"
```

### Phase 1 Gate

**STOP. Verify before proceeding to Phase 2:**

- [ ] Plugin directory exists: `plugins/$PLUGIN_NAME/`
- [ ] plugin.json created with marketplace version
- [ ] ADR exists: `docs/adr/$ADR_ID.md`
- [ ] Design spec exists: `docs/design/$ADR_ID/spec.md`
- [ ] Both diagrams in ADR (Before/After + Architecture)

---

## Phase 2: Component Creation (Conditional)

**Execute ONLY the skills for components the user selected.**

### 2.1 Skills (if has-skills)

**MANDATORY Skill tool call: `skill-architecture:skill-architecture`** — activate if skills selected.

This skill (NOT plugin-dev:skill-development) provides:

- 5 TodoWrite templates (A-E)
- SKILL.md structure
- References folder patterns
- Security practices

After skill creation, spawn reviewer agent:

**Spawn Agent: `plugin-dev:skill-reviewer`** — validate skill quality.

```
Task with subagent_type="plugin-dev:skill-reviewer"
prompt: "Review the skills created in plugins/$PLUGIN_NAME/skills/ for quality, security, and best practices."
```

### 2.2 Hooks (if has-hooks)

**MANDATORY Skill tool call: `plugin-dev:hook-development`** — activate if hooks selected.

This skill includes:

- hooks.json structure
- Event types (PreToolUse, PostToolUse, Stop, etc.)
- Settings patterns (plugin-settings merged in)

### 2.3 Commands (if has-commands)

**MANDATORY Skill tool call: `plugin-dev:command-development`** — activate if commands selected.

This skill provides:

- YAML frontmatter fields
- Argument patterns
- Dynamic arguments

### 2.4 Agents (if has-agents)

**MANDATORY Skill tool call: `plugin-dev:agent-development`** — activate if agents selected.

This skill provides:

- Agent frontmatter
- Triggering conditions
- Tool restrictions

### Phase 2 Gate

**STOP. Verify before proceeding to Phase 3:**

- [ ] All selected components created
- [ ] If skills: skill-reviewer agent completed review
- [ ] Files follow plugin-dev patterns

---

## Phase 3: Registration & Validation

### 3.1 Add to marketplace.json

Edit `.claude-plugin/marketplace.json` to add the new plugin entry:

```json
{
  "name": "$PLUGIN_NAME",
  "description": "TODO: Add description from ADR",
  "version": "$MARKETPLACE_VERSION",
  "source": "./plugins/$PLUGIN_NAME/",
  "category": "$PLUGIN_CATEGORY",
  "author": {
    "name": "Terry Li",
    "url": "https://github.com/terrylica"
  },
  "keywords": [],
  "strict": false
}
```

**If hooks exist**, add the hooks field:

```json
"hooks": "./plugins/$PLUGIN_NAME/hooks/hooks.json"
```

### 3.2 Run Validation Script

```bash
node scripts/validate-plugins.mjs
```

Expected output:

```
📦 Registered plugins: N+1
📁 Plugin directories: N+1

✅ All plugins validated successfully!
```

### 3.3 Quality Audit

**MANDATORY Skill tool call: `itp:code-hardcode-audit`** — activate NOW.

This skill checks for:

- Hardcoded values
- Magic numbers
- Duplicate constants
- Secrets

### 3.4 Plugin Validation Agent

**Spawn Agent: `plugin-dev:plugin-validator`** — validate plugin structure.

```
Task with subagent_type="plugin-dev:plugin-validator"
prompt: "Validate the plugin at plugins/$PLUGIN_NAME/ for correct structure, manifest, and component organization."
```

### Phase 3 Gate

**STOP. Verify before proceeding to Phase 4:**

- [ ] Plugin added to marketplace.json
- [ ] validate-plugins.mjs passes
- [ ] code-hardcode-audit passes
- [ ] plugin-validator agent approves

---

## Phase 4: Commit & Release

### 4.1 Stage Changes

```bash
git add plugins/$PLUGIN_NAME/
git add .claude-plugin/marketplace.json
git add docs/adr/$ADR_ID.md
git add docs/design/$ADR_ID/
```

### 4.2 Create Conventional Commit

```bash
git commit -m "feat($PLUGIN_NAME): add plugin for [brief description]

- Create plugin directory structure
- Add plugin.json manifest
- Register in marketplace.json
- Add ADR and design spec

ADR: $ADR_ID"
```

### 4.3 Push to Remote

```bash
git push origin $(git branch --show-current)
```

### 4.4 Semantic Release

**MANDATORY Skill tool call: `itp:semantic-release`** — activate NOW.

This skill:

- Tags the release
- Updates CHANGELOG
- Creates GitHub release
- Syncs versions across all plugins

**Invoke with CI=false for local execution:**

```bash
/usr/bin/env bash -c 'CI=false GITHUB_TOKEN=$(gh auth token) npm run release'
```

### Phase 4 Success Criteria

- [ ] All changes committed with conventional commit
- [ ] Pushed to remote
- [ ] semantic-release completed
- [ ] New version tag created
- [ ] GitHub release published

---

## Completion

**Workflow complete!** The new plugin is now:

1. ✅ Scaffolded with proper structure
2. ✅ Documented with ADR and design spec
3. ✅ Components created (as selected)
4. ✅ Registered in marketplace.json
5. ✅ Validated by scripts and agents
6. ✅ Released with semantic versioning

**Output the GitHub release URL:**

```bash
gh release view --json url -q .url
```

**Install the plugin in Claude Code:**

```bash
/plugin marketplace update cc-skills
/plugin install $PLUGIN_NAME@cc-skills
```
