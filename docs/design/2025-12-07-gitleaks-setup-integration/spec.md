---
adr: 2025-12-07-gitleaks-setup-integration
source: ~/.claude/plans/polymorphic-conjuring-glade.md
implementation-status: in_progress
phase: phase-1
last-updated: 2025-12-07
---

# Design Spec: Add Gitleaks to ITP Setup Command

**ADR**: [Add Gitleaks Secret Scanner to ITP Setup Command](/docs/adr/2025-12-07-gitleaks-setup-integration.md)

## Summary

Add Gitleaks to the existing `/itp:setup` command as a Code Audit Tool (Todo 4), following the established pattern for tool detection and installation.

## Why Gitleaks

**Current gap:** cc-skills has strong Doppler-based secret management but no pre-commit hook to prevent accidental secret commits.

**Gitleaks provides:**

- 160+ built-in secret patterns (PyPI tokens, GitHub tokens, AWS keys)
- Pre-commit hook integration (instant local feedback)
- Custom allowlists for false positive management
- Aligns with local-first development philosophy

## Implementation Tasks

### Task 1: Update setup.md TodoWrite Template

**File:** `/plugins/itp/commands/setup.md`

Update the TodoWrite template to include gitleaks in the Code Audit Tools todo item:

```
- "Setup: Check Code Audit Tools (ruff, semgrep, jscpd)" | pending | "Checking Audit Tools"
```

Change to:

```
- "Setup: Check Code Audit Tools (ruff, semgrep, jscpd, gitleaks)" | pending | "Checking Audit Tools"
```

### Task 2: Add Gitleaks to Todo 4 Table

**File:** `/plugins/itp/commands/setup.md`

Add gitleaks row to the Todo 4 (Code Audit Tools) table:

| Tool     | Check                 | Required        |
| -------- | --------------------- | --------------- |
| ruff     | `command -v ruff`     | For code-audit  |
| semgrep  | `command -v semgrep`  | For code-audit  |
| jscpd    | `command -v jscpd`    | For code-audit  |
| gitleaks | `command -v gitleaks` | For secret-scan |

### Task 3: Update install-dependencies.sh

**File:** `/plugins/itp/scripts/install-dependencies.sh`

**3.1:** Add gitleaks to mise-preferred tools section (in `get_install_cmd()` function):

```bash
gitleaks)  echo "mise install gitleaks && mise use --global gitleaks"; return ;;
```

**3.2:** Add platform fallbacks:

```bash
# In brew case:
gitleaks)  echo "brew install gitleaks" ;;

# In apt case:
gitleaks)  echo "sudo apt install -y gitleaks" ;;
```

**3.3:** Add gitleaks check to Code Audit section:

```bash
check_tool "gitleaks" "gitleaks" || { MISSING=$((MISSING+1)); INSTALL_GITLEAKS=$(get_install_cmd gitleaks); }
```

**3.4:** Add gitleaks to auto-install block:

```bash
[ -n "${INSTALL_GITLEAKS:-}" ] && install_tool "gitleaks" "$INSTALL_GITLEAKS"
```

### Task 4: Optional .gitleaks.toml (Deferred)

Creating `.gitleaks.toml` is optional and deferred for future consideration.

## mise Registry Confirmation

```
$ mise registry | grep gitleaks
gitleaks    aqua:gitleaks/gitleaks asdf:jmcvetta/asdf-gitleaks
```

Gitleaks is available via mise aqua backend (preferred for security over asdf plugins).

## Success Criteria

- [ ] `/itp:setup` detects gitleaks presence
- [ ] Missing gitleaks is reported in findings
- [ ] Installation works on macOS (brew) and Linux
- [ ] `command -v gitleaks` succeeds after installation
