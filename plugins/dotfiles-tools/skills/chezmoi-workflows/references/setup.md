**Skill**: [Chezmoi Workflows](../SKILL.md)

## First-Time Setup

**User says**: "Set up chezmoi for me" or "Initialize my dotfiles"

### Step 1: Detect Current State

```bash
# Check if chezmoi is installed
command -v chezmoi || echo "NOT INSTALLED"

# Check if already initialized
chezmoi source-path 2>/dev/null || echo "NOT INITIALIZED"

# Check current remote (if initialized)
chezmoi git -- remote -v 2>/dev/null || echo "NO REMOTE"
```

### Step 2: Installation (if needed)

```bash
# macOS
brew install chezmoi

# Linux
sh -c "$(curl -fsLS get.chezmoi.io)"
```

### Step 3: Initialize

**Option A: Fresh start (new dotfiles repo)**

```bash
chezmoi init
```

**Option B: Clone existing repo**

```bash
chezmoi init <github-username>/dotfiles
# Or with full URL:
chezmoi init git@github.com:<username>/dotfiles.git
```

### Step 4: Configure Source Directory (Optional)

Default: `~/.local/share/chezmoi`

To use a custom location, edit `~/.config/chezmoi/chezmoi.toml`:

```toml
# Custom source directory
sourceDir = "~/own/dotfiles"
```

Then move existing source:

```bash
mv ~/.local/share/chezmoi ~/own/dotfiles
```

---

## Remote Configuration

**User says**: "Configure my dotfiles remote" or "Set up GitHub for dotfiles"

### Detect Current Remote

```bash
chezmoi git -- remote -v
```

### Set Up Private Repository

**Step 1: Create repo on GitHub**

```bash
# Using gh CLI (recommended)
gh repo create dotfiles --private --source="$(chezmoi source-path)" --push

# Or manually create on github.com, then:
chezmoi git -- remote add origin git@github.com:<username>/dotfiles.git
chezmoi git -- push -u origin main
```

### Change Remote

```bash
# View current
chezmoi git -- remote -v

# Change to different account/repo
chezmoi git -- remote set-url origin git@github.com:<new-username>/<repo>.git

# Verify
chezmoi git -- remote -v
```

### Multi-Account SSH Setup

For users with multiple GitHub accounts, configure SSH to select account by directory:

```ssh-config
# ~/.ssh/config
Host github.com
    HostName github.com
    IdentityFile ~/.ssh/id_ed25519_default

# Override for specific directories (requires Match directive)
Match host github.com exec "pwd | grep -q '/own/'"
    IdentityFile ~/.ssh/id_ed25519_personal
```

---

## Configuration Options

### chezmoi.toml Location

`~/.config/chezmoi/chezmoi.toml`

### Full Configuration Template

```toml
# Source directory (optional, defaults to ~/.local/share/chezmoi)
sourceDir = "~/own/dotfiles"

[edit]
  command = "hx"          # Your preferred editor
  apply = false           # Manual apply after review

[git]
  autoadd = true          # Auto-stage changes on chezmoi add
  autocommit = true       # Auto-commit on add/apply
  autopush = false        # Manual push (recommended for review)

[add]
  encrypt = false         # Set true if using age/gpg encryption
  secrets = "error"       # Fail on detected secrets

[data]
  # Custom template variables
  [data.git]
    name = "Your Name"
    email = "you@example.com"
```

### Verify Configuration

```bash
# Show effective config
chezmoi data

# Show source path
chezmoi source-path

# Show managed files
chezmoi managed
```

---

## Show Current Setup

**User says**: "Show my chezmoi setup" or "What's my dotfiles configuration?"

**Workflow**:

```bash
echo "=== Chezmoi Configuration ==="

echo "\n📁 Source Directory:"
chezmoi source-path

echo "\n🔗 Git Remote:"
chezmoi git -- remote -v

echo "\n📊 Git Status:"
chezmoi git -- status --short

echo "\n📝 Managed Files:"
chezmoi managed | wc -l | xargs echo "Total files:"

echo "\n⚙️ Config File:"
cat ~/.config/chezmoi/chezmoi.toml 2>/dev/null || echo "Using defaults"
```

---

## Migration Scenarios

### Migrate to Different GitHub Account

```bash
# 1. Create new repo under new account
gh auth switch -u <new-account>
gh repo create dotfiles --private

# 2. Update remote
chezmoi git -- remote set-url origin git@github.com:<new-account>/dotfiles.git

# 3. Push all history
chezmoi git -- push -u origin main --force

# 4. (Optional) Delete old repo
gh auth switch -u <old-account>
gh repo delete <old-account>/dotfiles --yes
```

### Move Source Directory

```bash
# 1. Move directory
mv "$(chezmoi source-path)" ~/new/location

# 2. Update config
cat >> ~/.config/chezmoi/chezmoi.toml << 'EOF'
sourceDir = "~/new/location"
EOF

# 3. Verify
chezmoi source-path
chezmoi status
```

---

## Troubleshooting

### "No remote configured"

```bash
chezmoi git -- remote add origin git@github.com:<username>/dotfiles.git
chezmoi git -- push -u origin main
```

### "Permission denied (publickey)"

SSH key not configured for this GitHub account. Check:

```bash
ssh -T git@github.com
```

If wrong account, configure SSH Match directives or use HTTPS:

```bash
chezmoi git -- remote set-url origin https://github.com/<username>/dotfiles.git
```

### "Source directory not found"

```bash
# Check config
grep sourceDir ~/.config/chezmoi/chezmoi.toml

# Ensure directory exists
ls -la "$(chezmoi source-path)" || echo "Directory missing!"
```
