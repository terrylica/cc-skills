**Skill**: [Chezmoi Workflows](../SKILL.md)

## Configuration Reference

**chezmoi.toml** (at `~/.config/chezmoi/chezmoi.toml`):

```toml
[edit]
  command = "hx"        # Helix editor
  apply = false         # Manual apply after review

[git]
  autoadd = true        # Auto-stage changes
  autocommit = true     # Auto-commit on add/apply
  autopush = false      # Claude Code handles push

[add]
  secrets = "error"     # Fail on secret detection
```

**Key Settings**:

- `autocommit = true`: Automatic commits on `chezmoi add` and `chezmoi apply`
- `autopush = false`: Manual push for review (Claude Code handles this)
- `secrets = "error"`: Fail-fast on detected secrets (prevents SECRET-001 type issues)

---

## Template Handling

**When user edits a templated file** (files ending in `.tmpl` in source directory):

1. **Identify template**
   - Check if file is template: `ls $(chezmoi source-path)/dot_[filename].tmpl`

2. **Edit source template**

   ```bash
   chezmoi edit ~/.filename
   ```

   OR manually edit the template file directly

3. **Test template rendering**

   ```bash
   chezmoi execute-template < "$(chezmoi source-path)/dot_filename.tmpl"
   ```

   Expected: Valid rendered output, no template errors

4. **Apply to home directory**

   ```bash
   chezmoi apply ~/.filename
   ```

5. **Commit and push**

   ```bash
   chezmoi git -- add dot_filename.tmpl
   chezmoi git -- commit -m "Update filename template"
   chezmoi git -- push
   ```

**Template Variables**:

- `.chezmoi.os` - darwin, linux
- `.chezmoi.arch` - arm64, amd64
- `.chezmoi.homeDir` - /Users/username
- `.chezmoi.hostname` - hostname
- `.data.git.name`, `.data.git.email` - From chezmoi.toml
