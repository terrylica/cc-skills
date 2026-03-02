# Governance & Maintenance Model

> Task 9: Governance & Maintenance Model — Synthesize findings from Tasks 1, 3, and 6 to propose governance structure with ownership assignments and maintenance workflows.

**Date**: 2026-03-02  
**Task**: task-9  
**Agent**: TrueFalcon

---

## Executive Summary

This document establishes a governance model for the cc-skills documentation ecosystem based on findings from:

- **Task 1**: Documentation Standards Audit (standards-compliance-matrix.md)
- **Task 3**: Toolchain & Automation Landscape (tool-inventory.md)
- **Task 6**: Content Deduplication Analysis (deduplication-analysis.md)

The governance model addresses identified inconsistencies, assigns ownership, and defines maintenance workflows to ensure long-term documentation health.

---

## 1. Current State Assessment

### 1.1 Findings Summary

| Area | Status | Issues |
|------|--------|--------|
| **Plugin Count** | ⚠️ Inconsistent | Root CLAUDE.md says 20, plugins/CLAUDE.md says 21, marketplace.json has 23 |
| **CLAUDE.md Compliance** | 🟡 Partial | 87% follow Hub+Sibling pattern, 78% have Skills tables, 70% have Commands |
| **Toolchain Maturity** | 🟢 High (validation) / 🔴 Low (linting) | validate-plugins.mjs is excellent; no markdown/CLAUDE.md linting |
| **Content Duplication** | 🟡 Medium | 7 plugins missing Skills, 16 missing Commands, orphaned files exist |
| **Link Health** | 🟡 Medium | Some broken links, lychee configured but manual |

### 1.2 Risk Assessment

| Risk | Severity | Impact |
|------|----------|--------|
| Plugin count inconsistency causes confusion | Medium | Developer trust, onboarding |
| Missing CLAUDE.md sections reduce discoverability | Medium | Tool adoption, usability |
| No automated CLAUDE.md validation | High | Drift over time |
| Orphaned docs reduce navigation clarity | Low | User confusion |
| No markdown linting | Medium | Format inconsistencies |

---

## 2. Ownership Structure

### 2.1 Documentation Ownership Matrix

| Area | Owner | Deputy | Review Cadence |
|------|-------|--------|----------------|
| **Root CLAUDE.md** | @terryli | - | Per release |
| **plugins/CLAUDE.md** | @terryli | - | Per release |
| **Plugin CLAUDE.md files** | Plugin author | @terryli | Per plugin release |
| **docs/CLAUDE.md** | @terryli | - | Quarterly |
| **docs/adr/** | ADR author | @terryli | On creation |
| **docs/design/** | Design author | @terryli | On creation |
| **SKILL.md files** | Skill author | Plugin owner | Per skill update |
| **marketplace.json** | @terryli | - | Per plugin add/remove |

### 2.2 Automation Ownership

| Tool/Script | Owner | Maintenance Responsibility |
|-------------|-------|---------------------------|
| validate-plugins.mjs | @terryli | Fix schema issues, add validations |
| lychee.toml | @terryli | Update ignore patterns, CI integration |
| sync-*.sh scripts | @terryli | Fix path issues, add new sync types |
| .releaserc.yml | @terryli | Update on new release requirements |
| .mise/tasks/ | @terryli | Maintain release tasks |

### 2.3 Plugin Category Ownership

| Category | Plugins | Primary Owner |
|----------|---------|---------------|
| **Workflow** | itp, itp-hooks, ru | @terryli |
| **Development** | plugin-dev, gh-tools, git-town-workflow | @terryli |
| **DevOps** | devops-tools, dotfiles-tools, quality-tools | @terryli |
| **Communication** | gmail-commander, calcom-commander | @terryli |
| **Media** | kokoro-tts, tts-telegram-sync, asciinema-tools | @terryli |
| **Finance** | mql5, quant-research | @terryli |
| **System** | mise, rust-tools, link-tools, statusline-tools | @terryli |

---

## 3. Maintenance Workflows

### 3.1 Plugin CLAUDE.md Updates

**Required Sections** (enforced by validate-plugins.mjs):
1. Header: `# <plugin-name> Plugin`
2. Description: `> Brief description (blockquote)`
3. Hub Link: `**Hub**: [Root CLAUDE.md](../../CLAUDE.md)`
4. Sibling Links: `**Sibling**: [<name> CLAUDE.md](../<path>/CLAUDE.md)`
5. Skills Table (if skills exist)
6. Commands Table (if commands exist)
7. Hooks Table (if hooks exist)

**Workflow**:
1. Plugin Author updates CLAUDE.md
2. Run `bun scripts/validate-plugins.mjs`
3. Fix any validation errors
4. Create PR
5. Reviewer checks compliance
6. Merge and release

### 3.2 Documentation Review Cadence

| Document Type | Review Frequency | Trigger |
|---------------|------------------|---------|
| Root CLAUDE.md | Per release | Version bump |
| plugins/CLAUDE.md | Per release | Plugin add/remove |
| Individual Plugin CLAUDE.md | Per plugin release | Plugin version bump |
| docs/CLAUDE.md | Quarterly | Scheduled |
| ADRs | On creation | ADR author self-review |
| SKILL.md | Per skill update | Skill version bump |

### 3.3 Link Maintenance

**Broken Link Prevention**:
- Run `lychee` before each release
- Add lychee to CI pipeline
- Use relative links for internal refs, full URLs for external

**Link Fix Priority**:
1. Critical: Links to SKILL.md files (breaks tool discovery)
2. High: Links to plugin CLAUDE.md files (breaks navigation)
3. Medium: Links to docs/*.md (breaks context)
4. Low: External links (check quarterly)

---

## 4. Immediate Actions

### 4.1 Critical Fixes (Before Next Release)

| # | Action | Owner | Effort |
|---|--------|-------|--------|
| C1 | Fix plugin count in root CLAUDE.md: "20 plugins" → "23 plugins" | @terryli | 5 min |
| C2 | Fix plugin count in plugins/CLAUDE.md: "21 plugins" → "23 plugins" | @terryli | 5 min |
| C3 | Add missing Sibling link to kokoro-tts/CLAUDE.md | @terryli | 5 min |
| C4 | Fix or delete orphaned files (tool-inventory.md, 2 design docs) | @terryli | 30 min |

### 4.2 Short-Term Improvements (This Quarter)

| # | Action | Owner | Effort |
|---|--------|-------|--------|
| S1 | Integrate lychee into CI pipeline | @terryli | 2 hrs |
| S2 | Add CLAUDE.md validation to validate-plugins.mjs | @terryli | 4 hrs |
| S3 | Add missing Skills tables to 7 plugins | @terryli | 2 hrs |
| S4 | Add missing Commands tables to 16 plugins | @terryli | 3 hrs |
| S5 | Create shared 1Password reference doc | @terryli | 1 hr |

### 4.3 Long-Term Improvements (This Year)

| # | Action | Owner | Effort |
|---|--------|-------|--------|
| L1 | Create SKILL.md schema and validator | @terryli | 8 hrs |
| L2 | Build documentation dashboard with coverage metrics | @terryli | 16 hrs |
| L3 | Add markdown linting (markdownlint) | @terryli | 4 hrs |

---

## 5. Enforcement Mechanisms

### 5.1 Pre-Release Validation

All releases must pass:

```bash
# 1. Validate plugins
bun scripts/validate-plugins.mjs

# 2. Check links
lychee --config lychee.toml

# 3. Verify plugin count consistency
grep -c '"name":' .claude-plugin/marketplace.json  # Should be 23
```

### 5.2 CI Integration

Recommended additions to CI pipeline:

```yaml
# .github/workflows/docs.yml (new)
name: Documentation
on: [push, pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Validate plugins
        run: bun scripts/validate-plugins.mjs
      - name: Check links
        run: lychee --config lychee.toml --exit-code-with-issue
```

### 5.3 Schema Enforcement

Extend `validate-plugins.mjs` to validate:

- CLAUDE.md existence in each plugin
- Required sections (header, hub link, sibling link)
- Table structures (Skills, Commands, Hooks)

---

## 6. Monitoring & Metrics

### 6.1 Health Indicators

| Metric | Target | Current | Status |
|--------|--------|---------|--------|
| Plugin count accuracy | 100% | 87% (20/23) | 🔴 |
| CLAUDE.md compliance | 100% | 87% (20/23) | 🟡 |
| Skills table coverage | 100% | 78% (18/23) | 🟡 |
| Commands table coverage | 100% | 70% (16/23) | 🟡 |
| Broken internal links | 0 | TBD | 🟡 |
| Orphaned docs | 0 | 3 | 🔴 |

### 6.2 Dashboard

Suggested metrics to track over time:

- CLAUDE.md compliance rate by plugin
- SKILL.md frontmatter completeness
- Link error rate over time
- Time to fix critical issues
- Documentation coverage by category

---

## 7. Recommendations Summary

### High Priority

1. **Fix plugin count inconsistencies** (C1, C2)
   - Change "20 plugins" → "23 plugins" in root CLAUDE.md
   - Change "21 plugins" → "23 plugins" in plugins/CLAUDE.md

2. **Fix missing navigation** (C3)
   - Add Sibling link to kokoro-tts/CLAUDE.md

3. **Address orphaned content** (C4)
   - Integrate or delete tool-inventory.md, itp-hooks-file-tree-detection.md, clickhouse-skill-documentation-gaps/spec.md

### Medium Priority

4. **Automate link checking** (S1)
   - Add lychee to CI pipeline

5. **Add CLAUDE.md validation** (S2)
   - Extend validate-plugins.mjs with CLAUDE.md checks

6. **Complete documentation sections** (S3, S4)
   - Add Skills/Commands tables to plugins missing them

### Long Term

7. **Create SKILL.md schema** (L1)
8. **Build metrics dashboard** (L2)
9. **Add markdown linting** (L3)

---

## Appendix A: Plugin Compliance Status

| Plugin | Overall | Hub+Sibling | Skills | Commands | Fixes Needed |
|--------|---------|-------------|--------|----------|---------------|
| plugin-dev | Good | ✓ | ✓ | ✓ | - |
| itp | Good | ✓ | ✓ | ✓ | - |
| gh-tools | Good | ✓ | ✓ | - | Add Commands table |
| link-tools | Good | ✓ | ✓ | - | Add Commands table |
| devops-tools | Good | ✓ | ✓ | - | Add Commands table |
| dotfiles-tools | Good | ✓ | ✓ | ✓ | - |
| doc-tools | Good | ✓ | ✓ | - | Add Commands table |
| quality-tools | Good | ✓ | ✓ | - | Add Commands table |
| productivity-tools | Excellent | ✓ | ✓ | ✓ | - |
| mql5 | Good | ✓ | ✓ | - | Add Commands table |
| itp-hooks | Good | ✓ | ✓ | - | Add Commands table |
| ru | Excellent | ✓ | ✓ | ✓ | - |
| statusline-tools | Excellent | ✓ | ✓ | ✓ | - |
| asciinema-tools | Good | ✓ | ✓ | ✓ | - |
| git-town-workflow | Fair | ✓ | - | ✓ | Add Skills table |
| quant-research | Good | ✓ | ✓ | - | Add Commands table |
| gmail-commander | Fair | ✓ | - | ✓ | Add Skills table |
| kokoro-tts | Fair | ⚠ Hub only | ✓ | - | Add Sibling link, Commands table |
| tts-telegram-sync | Fair | ✓ | - | - | Add Skills table, Commands table |
| calcom-commander | Fair | ✓ | - | - | Add Skills table, Commands table |
| mise | Fair | ✓ | - | ✓ | Add Skills table |
| gitnexus-tools | Good | ✓ | ✓ | - | Add Commands table |
| rust-tools | Good | ✓ | ✓ | ✓ | - |

---

## Appendix B: Tool Maturity Assessment

| Tool | Maturity | Owner | Recommendation |
|------|----------|-------|----------------|
| validate-plugins.mjs | 🟢 High | @terryli | Expand with CLAUDE.md validation |
| lychee | 🟡 Medium | @terryli | Add to CI |
| sync-commands-to-settings.sh | 🟢 High | @terryli | Maintain |
| sync-hooks-to-settings.sh | 🟢 High | @terryli | Maintain |
| semantic-release | 🟢 High | @terryli | Maintain |
| sync-versions.mjs | 🟢 High | @terryli | Maintain |
| markdownlint | 🔴 None | - | Add to validate-plugins.mjs |

---

## Appendix C: References

- Task 1: [docs/standards-compliance-matrix.md](./standards-compliance-matrix.md)
- Task 3: [docs/tool-inventory.md](./tool-inventory.md)
- Task 6: [docs/deduplication-analysis.md](./deduplication-analysis.md)
- Marketplace: [.claude-plugin/marketplace.json](../.claude-plugin/marketplace.json)
- Validation: [scripts/validate-plugins.mjs](../scripts/validate-plugins.mjs)

---

*Generated by Task 9: Governance & Maintenance Model*
