# Evolution Log

> **Convention**: Reverse chronological order (newest on top, oldest at bottom). Prepend new entries.

---

## 2026-03-31: Relocate Self-Evolution for Attention Primacy/Recency

**Trigger**: Empirical observation over months that the self-evolving mechanism was not firing — skills never evolved despite instructions to do so. Research across 6 GitHub repos, 4 blog posts, and Anthropic's own context window documentation confirmed the root cause.

### Root Cause

The self-evolving instructions were buried at lines 52-93 of a 362-line SKILL.md — the attention "dead zone." Research shows:

- Context window quality degrades at **20-40% capacity** due to attention dilution (not token exhaustion)
- Instructions at document boundaries (top/bottom) receive disproportionately higher attention weight
- Fully autonomous self-improvement without admission gating produces noise faster than signal

### Changes Made

1. **New section: "Self-Evolution Protocol"** — placed immediately after frontmatter (line 12), before all other content. Contains a 3-gate admission protocol (VALUE, REDUNDANCY, FRESHNESS) that makes "do nothing" the default outcome.
2. **Moved "Post-Execution Reflection"** — from line 52 (mid-document) to absolute last section (after Reference Documentation) for maximum recency effect. Added step 4 requiring admission gate passage before writing changes.
3. **Removed "Continuous Improvement"** — consolidated into the Self-Evolution Protocol. The old 5-line section was too weak to trigger behavior.
4. **Added cross-reference** — Post-Execution Reflection step 4 now explicitly references the admission gates at the top, creating a top↔bottom sandwich.

### Key Insight

> Placement determines whether instructions get followed. "Attention primacy" (top of document) and "recency effect" (bottom of document) are the two highest-weight positions. Self-evolution instructions must occupy both — the protocol at the top sets the rules, the reflection at the bottom triggers the action. The mid-document position is where instructions go to die.

### Sources

- [191341025/Self-Evolving-Skill](https://github.com/191341025/Self-Evolving-Skill) — Five-Gate Protocol, confidence decay
- [KERNEL](https://medium.com/@ariaxhan) — deletion as evolution, file-based persistence
- [Context Window Degradation (BSWEN)](https://docs.bswen.com/blog/2026-03-19-claude-context-window-degradation/) — 20-40% capacity threshold
- [nathanonn.com](https://www.nathanonn.com/how-to-build-evolving-claude-code-rules/) — index-based loading, SKILL.md under 100 lines

---

## 2026-03-27: Add Compulsory Post-Execution Reflection

**Trigger**: User identified that agent skills executing stepwise are prone to errors that repeat silently across sessions because skills never learn from their own execution failures. The existing "Continuous Improvement" section was advisory, not structural — skills could (and did) skip reflection entirely.

### Changes Made

1. **New section in SKILL.md: "Post-Execution Reflection (Compulsory)"** — Mandatory architectural requirement (not advisory) with template, rationale, and link to reference
2. **New reference: `post-execution-reflection.md`** — Canonical pattern document with minimal and extended templates, phased execution integration, validation requirements, empirical examples, and anti-patterns for reflection itself
3. **Updated `phased-execution.md`**: Added Phase 3 (Reflect & Rectify) to core pattern, new `[Reflect]` and `[Rectify]` phase labels, updated all template examples
4. **Updated `task-templates.md`**: Template A step 8 now requires Post-Execution Reflection section; Template D step 4 adds it; Skill Quality Checklist gains two new items (reflection section present, phase labels include Reflect/Rectify)
5. **SKILL.md Reference Documentation**: Added post-execution-reflection.md link, updated phased-execution description

### Key Insight

> The difference between "advisory" and "structural" is whether the pattern survives a busy session. Advisory improvements get skipped under time pressure. Structural requirements — like YAML frontmatter or Post-Change Checklists — persist because the skill itself enforces them. Post-execution reflection must be structural to close the feedback loop.

### Related

- Memory: `project_skill_architecture_self_rectification.md` (planned upgrade, partially fulfilled)
- Gemini Deep Research issues: #67-#70

---

## 2026-03-06: Align with Anthropic skill-creator (9-Agent Deep Dive)

**Trigger**: 9-agent investigation comparing our skill-architecture against Anthropic's official [skill-creator](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md) (forked to `~/fork-tools/skills`). Found 3 CRITICAL, 3 HIGH, 3 MEDIUM gaps.

### Changes Made

1. **Description**: Converted from keyword-list format ("TRIGGERS - keyword1, keyword2") to natural language sentences per Anthropic's guidance
2. **Task Templates**: Replaced "MANDATORY" with reasoning-based explanation
3. **New section: Testing and Iteration** (~50 lines): Test prompts, evaluation methodology, iteration philosophy (generalize, keep lean, explain why, bundle repeated work)
4. **New section: Skill Writing Principles** (~15 lines): Inline key principles from Anthropic (reasoning over rigidity, pushy descriptions, natural language, keep execution out of descriptions)
5. **New reference: writing-guide.md**: Extended guidance on tone, description optimization, leanness, generalization, examples
6. **New reference: script-design.md**: Agentic script best practices (no interactive prompts, structured output, idempotency, PEP 723)
7. **TOCs added**: To reference files over 500 lines (per Anthropic's guideline)
8. **Updated Reference Documentation list**: Added links to new reference files

### Key Insight

> "We teach 'design and build correctly'; Anthropic teaches 'measure and iterate.' These are complementary halves."

Our unique value (Task Templates, 6-level precedence, CLI features, 5 structural patterns, phased execution, security practices) is preserved. The gaps filled are eval methodology, writing philosophy, and description optimization.

### Reports

9 detailed agent reports at `/tmp/skill-alignment-agents/agent{1-9}-*.md`.

---

## 2026-02-25: Add 10 Checklist Items from Official Sources

**Trigger**: Gap analysis of Skill Quality Checklist (SKILL.md) and Validation Checklist (validation-reference.md) against Claude Code docs + agentskills.io spec revealed 10 missing items.

### Items Added (both checklists)

1. `name` must match parent directory, no consecutive hyphens
2. Description not too broad (false-trigger guard)
3. SKILL.md body under 500 lines
4. Classify as reference vs task → set invocation control accordingly
5. `context: fork` requires actionable instructions (not guidelines-only)
6. `compatibility` field for external tool requirements
7. Fixed `allowed-tools` wording: "grants" not "restricts" (validation-reference.md)
8. Test activation both ways: manual `/name` AND organic triggers
9. Run `/context` to verify not excluded by budget
10. Reference-vs-task classification drives `disable-model-invocation` / `user-invocable` defaults

---

## 2026-02-25: Align with Official Claude Code Skills Docs (28 Findings)

**Trigger**: 9-agent forensic audit compared skill-architecture docs against `code.claude.com/docs/en/skills` and `agentskills.io/specification`. Found 2 CRITICAL, 8 HIGH, 11 MEDIUM, 7 LOW misalignments + 2 internal contradictions.

### Changes Made (8 Work Units)

1. **SKILL.md frontmatter**: Expanded 3-field table → 10-field table with all official fields (`context`, `agent`, `disable-model-invocation`, `user-invocable`, `argument-hint`, `allowed-permission-prompt`, `name-aliases`). Fixed `allowed-tools` semantics: grants tools, doesn't restrict. Added invocation control truth table and Skill Permission Rules.
2. **SKILL.md budget**: Added Skill Description Budget subsection (2% context window, `/context` command, `SLASH_COMMAND_TOOL_CHAR_BUDGET` override).
3. **TodoWrite → TaskCreate**: Migrated all 8 SKILL.md occurrences. Terminology now matches Claude Code's `TaskCreate` tool.
4. **SKILL.md CLI features**: Added String Substitutions table (`$ARGUMENTS`, `$N`, `${CLAUDE_SESSION_ID}`), Dynamic Context Injection (`` !`cmd` `` syntax), Extended Thinking (`ultrathink` keyword).
5. **Skill Discovery**: Added precedence chain (Enterprise > Personal > Project > Plugin > Nested > --add-dir), monorepo auto-discovery, `claude plugin enable/disable` commands.
6. **command-skill-duality.md → invocation-control.md**: Complete rewrite. Old dual-entity model replaced with merged command/skill reality. Added truth table, permission rules, migration guide, historical note.
7. **advanced-topics.md**: Fixed CLI vs API table (`SKILL.md` everywhere, `claude plugin install`, removed unverifiable 200-char limit). Added Plugin-Level Features table (`outputStyles`, `lspServers`, `mcpServers`, `settings`).
8. **validation-reference.md**: Added 6 optional `plugin.json` fields to template. **SYNC-TRACKING.md**: Updated sync date, added official docs + agentskills.io sources, added Known Spec Discrepancies table.
9. **progressive-disclosure.md**: Replaced 7 absolute paths with relative paths.
10. **Continuous Improvement**: Condensed from 42 lines to 7 lines (offset new content growth).

### Key Insight

Documentation alignment requires auditing against multiple official sources simultaneously. The Claude Code docs and Agent Skills spec have subtle discrepancies (comma vs space delimiters, `name` requirement) that must be explicitly documented rather than silently choosing one.

---

## 2026-02-13: Fix Hook Integration Anti-Pattern (CLAUDE_PLUGIN_ROOT)

**Trigger**: The `$CLAUDE_PLUGIN_ROOT` variable was recommended in the Hook Integration Pattern (advanced-topics.md) but does NOT work in hooks.json commands. When hooks.json is synced to settings.json, the variable is copied verbatim and resolves to empty string at shell execution time, causing "Module not found" errors.

### Anti-Patterns Documented

1. **`$CLAUDE_PLUGIN_ROOT` in hooks.json**: This env var only exists inside Claude Code's internal plugin skill loading context, not as a shell environment variable. Hook commands must use `$HOME`-based absolute paths.
2. **Empty TOML table sections**: mise rejects `[hooks.enter]` containing only comments (no key-value pairs). Either add a key or remove the section.

### Changes Made

1. **advanced-topics.md**: Replaced `$CLAUDE_PLUGIN_ROOT` example with `$HOME`-based path, added anti-pattern callout with comparison table, fixed guideline #6
2. **lifecycle-reference.md** (itp-hooks): Clarified `CLAUDE_PLUGIN_ROOT` documentation, added both anti-patterns to Common Pitfalls table

### Key Insight

Plugin context variables (`CLAUDE_PLUGIN_ROOT`) are available when Claude Code loads skills but NOT when hook commands execute as shell processes from settings.json. The sync script copies hooks.json commands verbatim without variable resolution. Only standard shell env vars (`$HOME`) are safe in hook commands.

---

## 2026-02-13: Extract Advanced Patterns from tts-tg-sync

**Trigger**: The tts-tg-sync plugin (8 skills, 3 commands, hooks, shared library) demonstrated 10 advanced patterns not captured in skill-architecture. These were extracted as agnostic, universally applicable patterns.

### Changes Made

1. **structural-patterns.md**: Added Pattern 5 (Suite Pattern) for multi-skill lifecycle management
2. **New: phased-execution.md**: Preflight/Execute/Verify pattern with 3 variants (Sandwich Verification, Dependency-Aware Teardown, Config Read-Edit-Validate-Apply) and TodoWrite phase labels
3. **New: command-skill-duality.md**: When to use commands vs skills, complementary design, plugin layout with both
4. **New: interactive-patterns.md**: 5 AskUserQuestion patterns (intent branching, destructive confirmation, config group selection, symptom collection, feedback collection)
5. **advanced-topics.md**: Added Known Issue Table pattern and Hook Integration pattern
6. **scripts-reference.md**: Added Shared Library pattern (scripts/lib/ convention)
7. **creation-workflow.md**: Added lifecycle and interactive questions to Steps 1-2, expanded decision matrix
8. **SKILL.md**: Added Suite Pattern to structural patterns list, Template F for lifecycle suites, 2 checklist items, 3 new reference links, expanded trigger keywords in description

### Key Insight

A single mature plugin demonstrated patterns that individual simple skills never encounter. The Suite Pattern is a fundamentally new structural category alongside Workflow, Task, Reference, and Capabilities. All patterns were generalized to use generic domain language (service, component, integration) with no TTS/Telegram-specific references.

---

## 2025-12-04: Expand Path Patterns for Script Portability

**Trigger**: Multi-agent audit found hardcoded paths across all skills/scripts.

### Problem

Path-patterns.md only covered markdown-specific patterns. Scripts had transgressions:

- `/Users/<username>/.claude/skills` (user-specific path)
- `/tmp/jscpd-report` (hardcoded temp directory)
- `~/.local/bin/graph-easy` (hardcoded binary location)

### Solution

1. Added 3 new unsafe patterns to `path-patterns.md`:
   - **Pattern 4**: Hardcoded user-specific paths (`/Users/<user>`, `/home/<user>`)
   - **Pattern 5**: Hardcoded temp directories (`/tmp`)
   - **Pattern 6**: Hardcoded binary locations (`~/.local/bin/tool`)

2. Expanded Validation Checklist with script-specific checks

3. Updated Skill Quality Checklist with inline examples:
   - Use `$HOME` not `/Users/<user>`
   - Use `tempfile.TemporaryDirectory` not `/tmp`
   - Use `command -v` not hardcoded paths

### Key Insight

Portability requires discipline in BOTH markdown AND scripts. Multi-agent parallel audit is effective for finding distributed issues across a codebase.

---

## 2025-12-04: Add Path Patterns Reference

**Trigger**: `/itp:setup` command failed due to unsupported `$(dirname "$0")` pattern in markdown.

### Problem

Command markdown files used `$(dirname "$0")` to resolve script paths, but `$0` is not set in the context where Claude reads markdown files. This is a known Claude Code bug ([#9354](https://github.com/anthropics/claude-code/issues/9354)).

### Solution

1. Created `references/path-patterns.md` documenting:
   - **Safe patterns**: Explicit fallback paths, relative links, `${BASH_SOURCE[0]}` in scripts
   - **Unsafe patterns**: `$(dirname "$0")` in markdown, bare `${CLAUDE_PLUGIN_ROOT}` without fallback
   - **Related GitHub issues**: #9354, #11278
   - **Migration guide**: How to find and fix unsafe patterns

2. Added to Skill Quality Checklist:
   - "No unsafe path patterns in markdown"

3. Added to Reference Documentation list

### Key Insight

Environment variables and bash context (`$0`, `$SCRIPT_DIR`) behave differently in actual scripts vs. markdown documentation that Claude reads. Always use explicit fallback paths for marketplace plugins.

---

## 2025-12-04: Add Continuous Improvement Section

**Trigger**: User identified gap—skill had mechanics for self-evolution but no proactive trigger.

### Problem

Skill-architecture taught HOW to make skills self-evolving (Template D, Post-Change Checklist, evolution-log) but didn't instruct Claude to ACTIVELY WATCH for improvement opportunities during normal usage.

### Solution

Added "Continuous Improvement (Proactive Self-Evolution)" section with:

- **6 improvement signals** to watch for (friction, edge cases, better patterns, confusion, tool evolution, repeated steps)
- **Immediate Update Protocol** (pause → fix → log → resume)
- **What NOT to update** (guard rails)
- **Self-Reflection Trigger** (post-task question)

### Key Insight

The distinction between reactive (what to do after changes) and proactive (actively seeking improvements) is critical. Skills should be vigilant observers, not passive recipients.

---

## 2024-12-04: Adversarial Audit Round 3 (Multi-Agent)

**Trigger**: User spawned 5 parallel sub-agents for comprehensive audit.

### Agents Deployed

| Agent             | Perspective              | Severity Found |
| ----------------- | ------------------------ | -------------- |
| Structural        | Skill Anatomy compliance | NONE           |
| Template-Tutorial | Alignment check          | MEDIUM         |
| References        | Link integrity           | LOW            |
| Description       | YAML triggers            | MEDIUM         |
| Checklist         | Self-compliance          | CRITICAL       |

### Critical Fix

**Issue**: skill-architecture not registered in `~/.claude/CLAUDE.md`
**Impact**: Violates its own teaching (Template A step 10, Tutorial Step 6)
**Fix**: Added "Global Skills" section to `~/.claude/CLAUDE.md`

### Medium Fixes

1. **YAML description** - Added specific trigger keywords: "YAML frontmatter", "validate skill", "TodoWrite templates", "bundled resources", "progressive disclosure", "allowed-tools"

2. **Orphaned file** - Added `workflow-patterns.md` to Reference Documentation

3. **Template ordering** - Swapped steps 4↔5 in Template A to match tutorial advice ("resources first, then SKILL.md")

### Low Fix

**Orphaned file**: `workflow-patterns.md` existed but wasn't referenced. Added to Reference Documentation section.

### Key Insight

Multi-agent parallel audit with different perspectives finds issues single-pass review misses. Critical issue (not registered in CLAUDE.md) was ironic - the skill teaches the very thing it violated.

---

## 2024-12-04: Adversarial Audit Round 2

**Trigger**: User requested second adversarial review to find remaining flaws.

### Flaws Found

| #   | Flaw                                                 | Location      |
| --- | ---------------------------------------------------- | ------------- |
| 1   | Skill Anatomy incomplete - missing evolution-log.md  | Lines 213-219 |
| 2   | Template D assumes config-reference.md always needed | Line 66       |
| 3   | Templates don't reference detailed tutorial          | Lines 18-83   |
| 4   | "6 Steps" title misleading vs 11-step Template A     | Line 124      |

### Changes Made

1. **Skill Anatomy updated** - Added `references/evolution-log.md` as recommended structure
2. **Template D step 5** - Changed to "(if skill manages external config)"
3. **Added cross-reference** - Templates section now links to tutorial
4. **Renamed section** - "6 Steps" → "Detailed Tutorial" with note to use templates

### Key Insight

Adversarial self-review catches inconsistencies that initial implementation misses. Two passes are better than one.

---

## 2024-12-04: TodoWrite-First Pattern + Self-Alignment

**Trigger**: User identified skill-architecture didn't follow its own standards.

### Changes Made

1. **Added TodoWrite Task Templates section** (FIRST section after frontmatter)
   - Template A: Create New Skill (11 steps)
   - Template B: Update Existing Skill
   - Template C: Add Resources to Skill
   - Template D: Convert to Self-Evolving Skill
   - Template E: Troubleshoot Skill Not Triggering
   - Skill Quality Checklist

2. **Added Post-Change Checklist (Self-Maintenance)**
   - skill-architecture now maintains itself like other skills

3. **Updated Step 4: Edit the Skill**
   - Added requirements for TodoWrite Task Templates
   - Added requirements for Post-Change Checklist

4. **Updated Step 6: Register and Iterate**
   - Added "Register skill in project CLAUDE.md"
   - Added "Verify against Skill Quality Checklist"

5. **Created this evolution-log.md**
   - skill-architecture is now self-documenting

### Flaws Fixed

| Flaw                              | Resolution                                                         |
| --------------------------------- | ------------------------------------------------------------------ |
| 6 Steps vs Template A misaligned  | Updated 6 Steps to include registration and checklist verification |
| No Post-Change Checklist for self | Added Self-Maintenance section                                     |
| Not self-evolving                 | Created evolution-log.md                                           |
| Step 4 incomplete                 | Added TodoWrite templates + Checklist requirements                 |

### Key Insight

The meta-skill that teaches skill creation must itself be an exemplar. Any pattern it teaches (TodoWrite templates, Post-Change Checklist, evolution tracking) must be present in itself.
