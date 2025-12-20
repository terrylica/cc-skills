---
adr: 2025-12-05-itp-setup-todowrite-workflow
source: ~/.claude/plans/memoized-cooking-nygaard.md
implementation-status: completed
phase: released
last-updated: 2025-12-20
---

# Design Spec: TodoWrite-Driven Interactive Setup Workflow

**ADR**: [TodoWrite-Driven Interactive Setup Workflow](/docs/adr/2025-12-05-itp-setup-todowrite-workflow.md)

## Summary

Redesign `/itp:setup` to mirror the `/itp:go` TodoWrite-driven workflow pattern:

1. **TodoWrite FIRST** - Mandatory todo creation before any checks
2. **Preflight Check Phase** - Discover tools, mark todos as checked
3. **Interactive Gate** - Present findings, ask permission to install
4. **Installation Phase** - Only if user confirms
5. **Verification Phase** - Re-check after installation

## Implementation Tasks

### Task 1: Rewrite `setup.md` Command

**File**: `/plugins/itp/commands/setup.md`

**Complete Rewrite** following ITP command pattern:

- [x] Add YAML frontmatter with description
- [x] Add mandatory TodoWrite template section (FIRST ACTION)
- [x] Define Phase 1: Preflight Check (todos 1-5)
- [x] Define Phase 2: Present Findings with disclaimer (todo 6)
- [x] Define Phase 3: Interactive Gate (todo 7) - STOP and ask user
- [x] Define Phase 4: Installation (todo 8) - only if user confirms
- [x] Define Phase 5: Verification (todo 9)
- [x] Document flag handling table

**TodoWrite Template** (9 todos):

```json
[
  {
    "content": "Setup: Detect platform (macOS/Linux)",
    "status": "pending",
    "activeForm": "Detecting platform"
  },
  {
    "content": "Setup: Check Core Tools (uv, gh, prettier)",
    "status": "pending",
    "activeForm": "Checking Core Tools"
  },
  {
    "content": "Setup: Check ADR Diagram Tools (cpanm, graph-easy)",
    "status": "pending",
    "activeForm": "Checking ADR Tools"
  },
  {
    "content": "Setup: Check Code Audit Tools (ruff, semgrep, jscpd)",
    "status": "pending",
    "activeForm": "Checking Audit Tools"
  },
  {
    "content": "Setup: Check Release Tools (node, semantic-release)",
    "status": "pending",
    "activeForm": "Checking Release Tools"
  },
  {
    "content": "Setup: Present findings and disclaimer",
    "status": "pending",
    "activeForm": "Presenting findings"
  },
  {
    "content": "Setup: GATE - Await user decision",
    "status": "pending",
    "activeForm": "Awaiting user decision"
  },
  {
    "content": "Setup: Install missing tools (if confirmed)",
    "status": "pending",
    "activeForm": "Installing missing tools"
  },
  {
    "content": "Setup: Verify installation",
    "status": "pending",
    "activeForm": "Verifying installation"
  }
]
```

### Task 2: Modify `install-dependencies.sh` Script

**File**: `/plugins/itp/scripts/install-dependencies.sh`

**Modifications**:

- [x] Add `--detect-only` flag for platform detection without full check
- [x] Keep existing `--check` and `--install` as hidden aliases
- [x] Add `show_disclaimer()` function
- [x] Restructure for TodoWrite integration (functions callable from setup.md)

**New Flag Handling**:

```bash
case "$1" in
    --detect-only)
        detect_platform  # Just set OS, PM, HAS_MISE
        exit 0
        ;;
    --check|"")
        MODE="check"     # Default behavior
        ;;
    --install|--yes)
        MODE="install"   # Skip interactive prompt
        ;;
esac
```

**Disclaimer Function**:

```bash
show_disclaimer() {
    echo ""
    echo -e "${BLUE}Note:${NC} This plugin is developed against latest tool versions."
    echo "Your existing installations are respected."
    echo "If you encounter issues, report or consider upgrading."
}
```

## Flag Handling Summary

| Flag        | Behavior                                  |
| ----------- | ----------------------------------------- |
| (none)      | Default: Check → Gate → Ask permission    |
| `--check`   | Same as default (hidden alias)            |
| `--install` | Check → Skip gate → Install automatically |
| `--yes`     | Alias for `--install`                     |

## Edge Cases

| Case                              | Handling                                                          |
| --------------------------------- | ----------------------------------------------------------------- |
| All tools present                 | Todos 1-6 complete, Todo 7 shows "All set!", Todos 8-9 marked N/A |
| Some missing, user says "install" | Todos 8-9 execute                                                 |
| Some missing, user says "skip"    | Todos 8-9 marked skipped, show manual commands                    |
| `--install` flag                  | Skip Todo 7 gate, proceed directly to install                     |
| macOS vs Linux                    | Todo 1 detects, install commands adapt                            |

## Success Criteria

- [ ] `/itp:setup` → Creates todos, runs checks, stops at gate
- [ ] User says "install" → Installs missing, verifies
- [ ] User says "skip" → Shows manual commands, exits cleanly
- [ ] `/itp:setup --install` → Skips gate, installs automatically
- [ ] Existing installations are detected and respected
- [ ] Disclaimer shown after findings

## Commit Message

```
feat(itp): TodoWrite-driven interactive setup workflow

- Mirror /itp:go pattern with mandatory TodoWrite first
- Phase-based workflow: Check → Gate → Install → Verify
- Interactive gate asks permission before installation
- Respects existing installations, adds disclaimer
- Keep --check/--install as hidden aliases for compatibility
```
