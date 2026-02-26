**Skill**: [ITP Go Workflow](../SKILL.md)

# Preflight Checkpoint (MANDATORY)

**STOP. Verify artifacts exist before proceeding to Phase 1.**

Run validator:

```bash
/usr/bin/env bash << 'PREFLIGHT_EOF'
# Environment-agnostic path (explicit fallback for marketplace installation)
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp}"
uv run "$PLUGIN_DIR/skills/implement-plan-preflight/scripts/preflight_validator.py" $ADR_ID
PREFLIGHT_EOF
```

Or verify manually:

- [ ] ADR file exists at `/docs/adr/$ADR_ID.md`
- [ ] ADR has YAML frontmatter with all 7 required fields
- [ ] ADR has `status: proposed` (initial state)
- [ ] ADR has `**Design Spec**:` link in header
- [ ] **DIAGRAM CHECK 1**: ADR has **Before/After diagram** in Context section (graph-easy block showing state change)
- [ ] **DIAGRAM CHECK 2**: ADR has **Architecture diagram** in Architecture section (graph-easy block showing components)

**DIAGRAM VERIFICATION (BLOCKING):**
If either diagram is missing, **STOP** and invoke `adr-graph-easy-architect` skill again.
Search ADR for `<!-- graph-easy source:` -- you need TWO separate blocks.

- [ ] Design spec exists at `/docs/design/$ADR_ID/spec.md`
- [ ] Design spec has YAML frontmatter with all 5 required fields
- [ ] Design spec has `implementation-status: in_progress`
- [ ] Design spec has `phase: preflight`
- [ ] Design spec has `**ADR**:` backlink in header
- [ ] Feature branch created (if `-b` flag specified)

**If any item is missing**: Complete it now. Do NOT proceed to Phase 1.
