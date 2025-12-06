**Skill**: [Chezmoi Workflows](../SKILL.md)

## Secret Detection

**Configuration**: `add.secrets = "error"` (fail-fast)

**When secret detected**:

```
chezmoi: /Users/username/.zshrc:283: Uncovered a GCP API key...
```

**Resolution**:

1. Operation fails immediately (fail-fast principle)
2. User must resolve:
   - Remove secret from file
   - Template it with secure source
   - Use password manager integration
3. **NEVER bypass** - secrets in git are prohibited

**Historical Example**: SECRET-001 (GEMINI_API_KEY) detected and removed from dot_zshrc.tmpl
