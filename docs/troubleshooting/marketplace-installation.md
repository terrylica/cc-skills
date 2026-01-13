# Troubleshooting cc-skills Marketplace Installation

Comprehensive guide for resolving Claude Code plugin marketplace installation failures when installing the `terrylica/cc-skills` marketplace.

---

## Prerequisites Checklist

Before troubleshooting, verify these requirements:

| Requirement          | Check Command                                          | Expected Output |
| -------------------- | ------------------------------------------------------ | --------------- |
| Claude Code CLI      | `claude --version`                                     | Version 2.x.x+  |
| Git installed        | `git --version`                                        | git version 2.x |
| Network connectivity | `curl -I https://github.com`                           | HTTP 200        |
| HTTPS access to repo | `git ls-remote https://github.com/terrylica/cc-skills` | refs/heads/main |

---

## Correct Installation Commands

**Important**: Plugin commands must be run in your **terminal**, not inside Claude Code as slash commands.

### Adding the Marketplace

```bash
# CORRECT - Run in terminal
claude plugin marketplace add terrylica/cc-skills

# WRONG - This is NOT a slash command
# /plugin marketplace add terrylica/cc-skills
```

### Installing Plugins

```bash
# CORRECT - Run in terminal
claude plugin install itp@cc-skills
claude plugin install plugin-dev@cc-skills

# Install all plugins at once
for p in itp plugin-dev gh-tools link-tools devops-tools dotfiles-tools doc-tools quality-tools productivity-tools mql5 itp-hooks alpha-forge-worktree ralph iterm2-layout-config statusline-tools notion-api asciinema-tools git-town-workflow; do claude plugin install "$p@cc-skills"; done
```

### Marketplace Directory

The marketplace is cloned to:

```
~/.claude/plugins/marketplaces/cc-skills/
```

**NOT** `~/.claude/plugins/marketplaces/terrylica-cc-skills/` (older format).

---

## Issues by Error Type

### 0. Most Common: "Source path does not exist"

**Symptom**:

```
Installing plugin "itp@cc-skills"...
✘ Failed to install plugin "itp@cc-skills": Source path does not exist: $HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp/
```

**Root Cause**: Trailing slashes in `marketplace.json` source paths, or marketplace repository out of sync.

**Solution**:

```bash
# Update the marketplace repository
cd ~/.claude/plugins/marketplaces/cc-skills
git pull

# Retry installation
claude plugin install itp@cc-skills
```

If still failing, the marketplace may have schema issues. Check for trailing slashes:

```bash
# Source paths should NOT have trailing slashes
cat ~/.claude/plugins/marketplaces/cc-skills/.claude-plugin/marketplace.json | grep '"source"'
# CORRECT: "./plugins/itp"
# WRONG:   "./plugins/itp/"
```

---

### 1. "Plugin not found" After Successful Marketplace Add

**Symptom**:

```bash
$ claude plugin marketplace add terrylica/cc-skills
✔ Successfully added marketplace: cc-skills

$ claude plugin install itp@cc-skills
✘ Failed to install plugin "itp@cc-skills": Plugin "itp@cc-skills" not found
```

**Root Cause**: Claude Code uses SSH clone by default. Without SSH keys, clone fails silently.

**Diagnosis**:

```bash
# Check if marketplace directory has content
ls ~/.claude/plugins/marketplaces/cc-skills/

# If empty or missing, SSH clone failed
```

**Solution** (manual HTTPS clone):

```bash
# Remove the broken marketplace
claude plugin marketplace remove cc-skills
rm -rf ~/.claude/plugins/marketplaces/cc-skills

# Clone manually using HTTPS
git clone https://github.com/terrylica/cc-skills.git ~/.claude/plugins/marketplaces/cc-skills

# Add entry to known_marketplaces.json
# Edit ~/.claude/plugins/known_marketplaces.json and add:
# "cc-skills": {
#   "source": {"source": "github", "repo": "terrylica/cc-skills"},
#   "installLocation": "$HOME/.claude/plugins/marketplaces/cc-skills",
#   "lastUpdated": "2026-01-13T00:00:00.000Z"
# }

# Now install works
claude plugin install itp@cc-skills
```

**Permanent Fix** (prevent future SSH issues):

```bash
# Force git to use HTTPS for all GitHub repos
git config --global url."https://github.com/".insteadOf git@github.com:
git config --global url."https://github.com/".insteadOf ssh://git@github.com/
```

---

### 2. Slash Commands Not Appearing After Installation

**Symptom**: Plugins installed successfully, but `/itp:go`, `/plugin-dev:create`, etc. don't appear in autocomplete.

**Root Cause**: Several possible causes:

- Session not restarted after installation
- Plugin cache out of sync with marketplace
- `installed_plugins.json` has stale entries

**Solution**:

```bash
# 1. Verify plugin is installed
cat ~/.claude/plugins/installed_plugins.json | grep "cc-skills"

# 2. Clear stale cache
rm -rf ~/.claude/plugins/cache/cc-skills

# 3. Reinstall the plugin
claude plugin install itp@cc-skills

# 4. Restart Claude Code (required for command discovery)
```

---

### 3. Version Mismatch

**Symptom**: Old plugin version installed even after marketplace update.

**Diagnosis**:

```bash
# Check marketplace version
cat ~/.claude/plugins/marketplaces/cc-skills/plugin.json | jq '.version'

# Check cached version
ls ~/.claude/plugins/cache/cc-skills/itp/
```

**Solution**:

```bash
# Update marketplace
cd ~/.claude/plugins/marketplaces/cc-skills
git pull

# Clear plugin cache
rm -rf ~/.claude/plugins/cache/cc-skills/itp

# Reinstall
claude plugin install itp@cc-skills
```

---

### 4. Hooks Not Working

**Symptom**: Hooks don't trigger after plugin installation.

**Root Cause**: Hooks must be explicitly synced to `~/.claude/settings.json`.

**Solution**:

```bash
# Clone the repository if not already cloned for development
git clone https://github.com/terrylica/cc-skills.git /tmp/cc-skills

# Run the hook sync script
/tmp/cc-skills/scripts/sync-hooks-to-settings.sh

# Verify hooks are registered
cat ~/.claude/settings.json | jq '.hooks | keys'
# Should show: ["PreToolUse", "PostToolUse", "Stop"]

# Restart Claude Code
```

---

### 5. Invalid plugin.json Errors

**Symptom**:

```
✘ Failed to install plugin: Plugin has an invalid manifest file.
Validation errors: author: Invalid input: expected object, received string
```

**Root Cause**: The `plugin.json` has schema violations.

**Common issues**:

- `author` is a string instead of object
- Custom fields like `commands_dir`, `references_dir`, `scripts_dir`
- Trailing slashes in source paths

**Valid plugin.json format**:

```json
{
  "name": "my-plugin",
  "version": "<version>",
  "description": "Plugin description (min 10 chars)",
  "keywords": ["keyword1", "keyword2"],
  "author": {
    "name": "Your Name",
    "url": "https://github.com/username"
  }
}
```

---

### 6. Network/Clone Failures

#### Early EOF During Clone

**Symptom**:

```
fatal: early EOF
```

**Solution**:

```bash
# Increase HTTP buffer size
git config --global http.postBuffer 524288000

# Disable git compression
git config --global core.compression 0

# Disable HTTP/2
git config --global http.version HTTP/1.1

# Retry
claude plugin marketplace add terrylica/cc-skills
```

#### Clone Hangs Indefinitely

**Symptom**: Command shows "Cloning..." but never completes.

**Solution**:

```bash
# Check for proxy settings
env | grep -i proxy

# Clone manually with timeout
timeout 60 git clone --depth 1 https://github.com/terrylica/cc-skills.git ~/.claude/plugins/marketplaces/cc-skills

# If behind proxy
git config --global http.proxy http://proxy.example.com:8080
```

---

## Diagnostic Commands Quick Reference

### Environment

```bash
# Check Claude Code version
claude --version

# Check git version and config
git --version
git config --global --list | grep -E "http|credential|core"

# Check SSH setup
ssh -vT git@github.com 2>&1 | head -20
```

### Marketplace State

```bash
# List installed marketplaces
claude plugin marketplace list

# Check marketplace directory
ls -la ~/.claude/plugins/marketplaces/cc-skills/

# Check known_marketplaces.json
cat ~/.claude/plugins/known_marketplaces.json | jq '.["cc-skills"]'

# Check installed plugins
cat ~/.claude/plugins/installed_plugins.json | jq '.plugins | keys | .[] | select(contains("cc-skills"))'

# Check plugin cache
ls -la ~/.claude/plugins/cache/cc-skills/
```

### Reset Commands

```bash
# Remove marketplace (to re-add fresh)
claude plugin marketplace remove cc-skills
rm -rf ~/.claude/plugins/marketplaces/cc-skills

# Clear plugin cache
rm -rf ~/.claude/plugins/cache/cc-skills

# Full reset (DESTRUCTIVE - backup first)
mv ~/.claude/plugins ~/.claude/plugins.bak.$(date +%s)
```

---

## Known Claude Code Issues

| Issue                                                            | Description                                          | Workaround                                           |
| ---------------------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| [#14929](https://github.com/anthropics/claude-code/issues/14929) | Commands from directory-based marketplaces not found | Use GitHub source instead of directory source        |
| SSH clone failures                                               | Silent failure when marketplace uses SSH             | Manual HTTPS clone + edit known_marketplaces.json    |
| Trailing slash in source paths                                   | "Source path does not exist" error                   | Remove trailing slashes from marketplace.json source |

---

## External References

### Official Documentation

- [Claude Code Getting Started](https://docs.anthropic.com/en/docs/claude-code/getting-started)
- [Claude Code Plugins](https://docs.anthropic.com/en/docs/claude-code/plugins)
- [cc-skills README](https://github.com/terrylica/cc-skills#readme)

### Related GitHub Issues

- [#14929](https://github.com/anthropics/claude-code/issues/14929) - Directory-based marketplace commands not discovered
- [#9719](https://github.com/anthropics/claude-code/issues/9719) - SSH clone fails, HTTPS works
- [#9426](https://github.com/anthropics/claude-code/issues/9426) - Plugin management state issues

### Internal Documentation

- [cc-skills Installation](/README.md#installation)
- [Ralph Getting Started](/plugins/ralph/GETTING-STARTED.md)
