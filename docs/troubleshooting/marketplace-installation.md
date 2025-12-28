# Troubleshooting cc-skills Marketplace Installation

Comprehensive guide for resolving Claude Code plugin marketplace installation failures when installing the `terrylica/cc-skills` marketplace.

---

## Prerequisites Checklist

Before troubleshooting, verify these requirements:

| Requirement          | Check Command                                          | Expected Output         |
| -------------------- | ------------------------------------------------------ | ----------------------- |
| Claude Code CLI      | `claude --version`                                     | Version 2.x.x or higher |
| Git installed        | `git --version`                                        | git version 2.x.x       |
| Network connectivity | `curl -I https://github.com`                           | HTTP 200                |
| HTTPS access to repo | `git ls-remote https://github.com/terrylica/cc-skills` | refs/heads/main         |

---

## Issues by Error Type

### 0. Most Common: "Plugin not found" After Successful Add

**Symptom** (most frequently reported issue):

```
> /plugin marketplace add terrylica/cc-skills
└ Successfully added marketplace: cc-skills

> /plugin
└ (no content)

> /plugin install cc-skills
└ Plugin "cc-skills" not found in any marketplace
```

**GitHub Issue**: [#9297](https://github.com/anthropics/claude-code/issues/9297)

**Root Cause**: Claude Code uses **SSH clone** (`git@github.com:...`) instead of HTTPS. For users without SSH keys configured, the clone hangs silently. The command reports "success" but the directory is **empty**.

**Diagnosis**:

```bash
# Check if marketplace directory has content
ls ~/.claude/plugins/marketplaces/

# If directory exists but is empty (or only has .git), SSH clone failed
ls -la ~/.claude/plugins/marketplaces/terrylica-cc-skills/
```

**Solution** (manual HTTPS clone):

```bash
# Remove the empty/broken marketplace
rm -rf ~/.claude/plugins/marketplaces/terrylica-cc-skills

# Clone manually using HTTPS (works without SSH keys)
git clone https://github.com/terrylica/cc-skills.git ~/.claude/plugins/marketplaces/terrylica-cc-skills

# Now install works
# In Claude Code:
/plugin install cc-skills
```

**Permanent Fix** (prevent future SSH issues):

```bash
# Force git to use HTTPS for all GitHub repos
git config --global url."https://github.com/".insteadOf git@github.com:
git config --global url."https://github.com/".insteadOf ssh://git@github.com/
```

---

### 1. Network/Clone Failures

#### Early EOF During Clone

**Symptom**:

```
Error: Failed to clone marketplace repository: Cloning into '~/.claude/plugins/marketplaces/terrylica-cc-skills'...
fatal: early EOF
```

**Diagnosis**: The git transfer was interrupted before completion. This typically happens with large repositories on unstable connections.

**Root Cause**: Network buffer too small, HTTP/2 issues, or connection interrupted.

**Solution** (try in order):

```bash
# Step 1: Disable git compression
git config --global core.compression 0

# Step 2: Increase HTTP buffer size
git config --global http.postBuffer 524288000

# Step 3: Disable HTTP/2 (can cause connection resets)
git config --global http.version HTTP/1.1

# Step 4: Retry installation
# In Claude Code:
/plugin marketplace add terrylica/cc-skills
```

**Verification**: Check if marketplace was added:

```bash
ls ~/.claude/plugins/marketplaces/
```

**Prevention**: These git config changes persist globally and prevent future issues.

---

#### Clone Hangs Indefinitely

**Symptom**: The `/plugin marketplace add` command shows "Cloning..." but never completes.

**GitHub Issue**: [#9297](https://github.com/anthropics/claude-code/issues/9297)

**Diagnosis**: Check if git can clone manually:

```bash
timeout 60 git clone --depth 1 https://github.com/terrylica/cc-skills.git /tmp/test-clone
```

**Root Cause**: Firewall, proxy, or VPN blocking the connection.

**Solution**:

```bash
# Check for proxy settings
env | grep -i proxy

# If behind corporate proxy, configure git
git config --global http.proxy http://proxy.example.com:8080

# If proxy is blocking, try without it
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY

# Retry installation in Claude Code
```

**Alternative**: Download as ZIP and install locally:

```bash
# Download from browser: https://github.com/terrylica/cc-skills/archive/refs/heads/main.zip
# Unzip and use local path
/plugin marketplace add /path/to/cc-skills
```

---

#### Repository Not Found

**Symptom**:

```
Error: Repository not found
```

**Diagnosis**: Verify the repository is accessible:

```bash
curl -I https://api.github.com/repos/terrylica/cc-skills
```

**Root Cause**: Typo in marketplace name or repository is private/renamed.

**Solution**:

```bash
# Correct command (note exact spelling)
/plugin marketplace add terrylica/cc-skills

# NOT: cc_skills, ccskills, or CC-Skills
```

---

### 2. Authentication Issues

#### SSH Clone Fails, HTTPS Works

**Symptom**: Installation fails with SSH-related errors.

**GitHub Issue**: [#9719](https://github.com/anthropics/claude-code/issues/9719)

**Diagnosis**:

```bash
# Test SSH connectivity
ssh -T git@github.com

# Test HTTPS connectivity
git ls-remote https://github.com/terrylica/cc-skills.git
```

**Root Cause**: Claude Code may default to SSH, but SSH keys aren't configured.

**Solution**: Force HTTPS for GitHub:

```bash
git config --global url."https://github.com/".insteadOf git@github.com:
git config --global url."https://github.com/".insteadOf ssh://git@github.com/

# Retry installation
```

---

#### HTTPS Authentication Prompt

**Symptom**: Prompted for username/password during clone.

**Diagnosis**: Check if GitHub CLI is authenticated:

```bash
gh auth status
```

**Solution**:

```bash
# Authenticate with GitHub CLI
gh auth login

# Or use credential manager
git config --global credential.helper osxkeychain  # macOS
git config --global credential.helper manager      # Windows
git config --global credential.helper cache        # Linux
```

---

#### Permission Denied (publickey)

**Symptom**:

```
Permission denied (publickey)
```

**Diagnosis**:

```bash
ssh -vT git@github.com 2>&1 | head -20
```

**Solution**:

```bash
# Generate SSH key if missing
ssh-keygen -t ed25519 -C "your_email@example.com"

# Add to SSH agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Add public key to GitHub: https://github.com/settings/keys
cat ~/.ssh/id_ed25519.pub
```

---

### 3. State/Cache Issues

#### Plugin Management State Corruption

**Symptom**: Inconsistent plugin state - shows installed but also not installed.

**GitHub Issue**: [#9426](https://github.com/anthropics/claude-code/issues/9426)

**Diagnosis**:

```bash
# Check marketplace directory
ls -la ~/.claude/plugins/marketplaces/

# Check settings.json
cat ~/.claude/settings.json | jq '.plugins // empty'
```

**Solution**:

```bash
# Remove corrupted marketplace
rm -rf ~/.claude/plugins/marketplaces/terrylica-cc-skills

# Clear any stale plugin state
rm -rf ~/.claude/plugins/cache/cc-skills

# Re-add marketplace
# In Claude Code:
/plugin marketplace add terrylica/cc-skills
```

---

#### Discovery Broken After Update

**Symptom**: After updating Claude Code, `/plugin` shows "cannot find any marketplace".

**GitHub Issue**: [#13471](https://github.com/anthropics/claude-code/issues/13471)

**Solution**:

```bash
# Re-add the marketplace
/plugin marketplace add terrylica/cc-skills

# Then reinstall plugins
/plugin install cc-skills
```

---

#### Stale Marketplace Cache

**Symptom**: Old version installed even after marketplace update.

**Diagnosis**:

```bash
# Check cached version
ls ~/.claude/plugins/cache/cc-skills/
```

**Solution**:

```bash
# Clear cache for cc-skills
rm -rf ~/.claude/plugins/cache/cc-skills

# Update marketplace
/plugin marketplace update terrylica/cc-skills

# Reinstall
/plugin install cc-skills
```

---

### 4. Platform-Specific Issues

#### WSL Path Issues (Windows)

**Symptom**: Paths not resolved correctly in WSL environment.

**Diagnosis**:

```bash
echo $HOME
# Should be /home/username, NOT /mnt/c/Users/...
```

**Solution**:

```bash
# Ensure HOME is set correctly in WSL
export HOME=/home/$(whoami)

# Add to ~/.bashrc for persistence
echo 'export HOME=/home/$(whoami)' >> ~/.bashrc
```

---

#### macOS Keychain Interference

**Symptom**: Repeated credential prompts or authentication failures.

**Solution**:

```bash
# Clear git credentials from keychain
git credential-osxkeychain erase <<EOF
protocol=https
host=github.com
EOF

# Re-authenticate
gh auth login
```

---

#### Non-GitHub Repository Failures

**Symptom**: Adding non-GitHub marketplaces fails.

**GitHub Issue**: [#10403](https://github.com/anthropics/claude-code/issues/10403)

**Root Cause**: Claude Code currently only fully supports GitHub-hosted marketplaces.

**Solution**: Use GitHub as marketplace host, or use local path:

```bash
# Clone manually
git clone https://gitlab.com/your/marketplace.git ~/my-marketplace

# Add as local marketplace
/plugin marketplace add ~/my-marketplace
```

---

## Meta-Prompt for Self-Service Troubleshooting

**Copy this entire prompt into a new Claude Code session** to get guided troubleshooting help:

---

````
I'm having trouble installing the cc-skills marketplace. Help me diagnose and fix the issue.

**My Error**: [PASTE YOUR ERROR MESSAGE HERE]

**Please run these diagnostic commands and analyze the output**:

1. Environment check:
```bash
echo "=== Environment ===" && \
claude --version && \
git --version && \
echo "HOME: $HOME" && \
echo "Platform: $(uname -s)" && \
echo "Shell: $SHELL"
````

1. Network connectivity:

```bash
echo "=== Network ===" && \
curl -s -o /dev/null -w "%{http_code}" https://github.com && echo " (GitHub)" && \
git ls-remote --exit-code https://github.com/terrylica/cc-skills.git 2>&1 | head -3
```

1. Current marketplace state:

```bash
echo "=== Marketplace State ===" && \
ls -la ~/.claude/plugins/marketplaces/ 2>/dev/null || echo "No marketplaces directory" && \
ls -la ~/.claude/plugins/cache/cc-skills/ 2>/dev/null || echo "No cc-skills cache"
```

1. Git configuration:

```bash
echo "=== Git Config ===" && \
git config --global --list 2>/dev/null | grep -E "http|credential|core.compression|url" || echo "No relevant git config"
```

**Known Solutions Database**:

| Error Pattern             | Likely Cause         | Fix Command                                                               |
| ------------------------- | -------------------- | ------------------------------------------------------------------------- |
| "early EOF"               | Network buffer       | `git config --global http.postBuffer 524288000`                           |
| "SSH: Connection refused" | SSH not configured   | `git config --global url."https://github.com/".insteadOf git@github.com:` |
| "Repository not found"    | Typo or private repo | Verify: `terrylica/cc-skills`                                             |
| Hangs indefinitely        | Firewall/proxy       | `git config --global http.version HTTP/1.1`                               |
| "Permission denied"       | SSH key missing      | Use HTTPS or configure SSH                                                |

**After diagnosing**, provide:

1. Root cause analysis based on diagnostic output
2. Specific fix commands I should run
3. Verification steps to confirm the fix worked

**If this is a hooks-related issue after successful installation**, I may need to reinstall hooks:

```
/ralph:hooks uninstall
# Exit and restart Claude Code
/ralph:hooks install
# Exit and restart Claude Code again
/ralph:hooks status
```

**References**:

- [cc-skills Installation Guide](https://github.com/terrylica/cc-skills#installation)
- [Claude Code Plugins Docs](https://docs.anthropic.com/en/docs/claude-code/plugins)

````

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
````

### Marketplace State

```bash
# List installed marketplaces
ls -la ~/.claude/plugins/marketplaces/

# View marketplace entries
find ~/.claude/plugins/marketplaces -name "marketplace.json" -exec cat {} \; | jq '.plugins[].name' 2>/dev/null

# Check plugin installation state
ls -la ~/.claude/skills/
ls -la ~/.claude/plugins/cache/
```

### Network Diagnostics

```bash
# Test GitHub HTTPS
git ls-remote https://github.com/terrylica/cc-skills.git

# Test with shallow clone (reduces data transfer)
git clone --depth 1 https://github.com/terrylica/cc-skills.git /tmp/test-clone && rm -rf /tmp/test-clone

# Check proxy settings
env | grep -i proxy
```

### Reset Commands

```bash
# Remove marketplace (to re-add fresh)
rm -rf ~/.claude/plugins/marketplaces/terrylica-cc-skills

# Clear plugin cache
rm -rf ~/.claude/plugins/cache/cc-skills

# Reset git credential cache
git credential reject <<EOF
protocol=https
host=github.com
EOF

# Full Claude Code plugin reset (DESTRUCTIVE - backs up first)
mv ~/.claude/plugins ~/.claude/plugins.bak.$(date +%s)
```

---

## External References

### Official Documentation

- [Claude Code Getting Started](https://docs.anthropic.com/en/docs/claude-code/getting-started)
- [Claude Code Plugins](https://docs.anthropic.com/en/docs/claude-code/plugins)
- [cc-skills README](https://github.com/terrylica/cc-skills#readme)

### Related GitHub Issues

- [#9297](https://github.com/anthropics/claude-code/issues/9297) - Plugin marketplace add hangs indefinitely
- [#9719](https://github.com/anthropics/claude-code/issues/9719) - SSH clone fails, HTTPS works
- [#9426](https://github.com/anthropics/claude-code/issues/9426) - Plugin management state issues
- [#10403](https://github.com/anthropics/claude-code/issues/10403) - Non-GitHub repos fail
- [#13471](https://github.com/anthropics/claude-code/issues/13471) - Discovery broken after update

### Git Troubleshooting

- [GitHub Community: Early EOF Solutions](https://github.com/orgs/community/discussions/48568)
- [Medium: Fixing Fatal Early EOF](https://medium.com/@mectayn/resolving-fatal-early-eof-error-in-git-a-practical-solution-b2f4c1a8b43f)
- [GitHub SSH Troubleshooting](https://docs.github.com/en/authentication/troubleshooting-ssh)

### Internal Documentation

- [cc-skills Installation](/README.md#installation)
- [Ralph Getting Started](/plugins/ralph/GETTING-STARTED.md)
