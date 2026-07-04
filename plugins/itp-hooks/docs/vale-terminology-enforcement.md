# Vale Terminology Enforcement

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — moved verbatim from the hub 2026-06-11 (CLAUDE.md size-guard refactor: hub was 112k chars, limit 40k).

## Vale Terminology Enforcement

The Vale terminology hooks enforce consistent terminology across all CLAUDE.md files.

### Architecture

```
~/.claude/docs/GLOSSARY.md  ◄──── SSoT (Single Source of Truth)
         │
         │ bidirectional sync via glossary-sync.ts
         ▼
~/.claude/.vale/styles/
  ├── config/vocabularies/TradingFitness/accept.txt
  └── TradingFitness/Terminology.yml
```

### Hook Chain (PreToolUse + PostToolUse)

**PreToolUse (REJECTS before edit)**:

1. **pretooluse-vale-claude-md-guard.ts** → Runs Vale on proposed content, REJECTS if issues found

**PostToolUse (informational after edit)**:

1. **posttooluse-vale-claude-md.ts** → Runs Vale, shows terminology violations (visibility only)
2. **posttooluse-glossary-sync.ts** → (if GLOSSARY.md changed) Updates Vale vocabulary
3. **posttooluse-terminology-sync.ts** → Syncs project terms to global GLOSSARY.md + duplicate detection

### Implementation Details (posttooluse-vale-claude-md.ts)

The PostToolUse Vale hook is **cwd-agnostic** and works from any directory:

1. **Config discovery**: Walks UP from the file's directory to find `.vale.ini`, falls back to `~/.claude/.vale.ini`
2. **Directory change**: Runs Vale from the file's directory so glob patterns like `[CLAUDE.md]` match
3. **ANSI stripping**: Removes color codes from Vale output for reliable regex parsing
4. **Summary parsing**: Extracts error/warning/suggestion counts from Vale's summary line

### PreToolUse vs PostToolUse

| Hook Type   | When             | Can Reject? | Use Case                         |
| ----------- | ---------------- | ----------- | -------------------------------- |
| PreToolUse  | BEFORE tool runs | YES         | Block bad edits                  |
| PostToolUse | AFTER tool runs  | NO          | Inform about issues (visibility) |

The PreToolUse hook uses `permissionDecision: "deny"` (hard rejection). Change MODE to `"ask"` for a permission dialog instead.

> **Note**: glossary-sync runs before terminology-sync to ensure Vale vocabulary is current before terminology validation.

### Duplicate Detection

The terminology-sync hook scans ALL configured CLAUDE.md files and BLOCKS on conflicts:

| Conflict Type     | Example                                      | Action Required               |
| ----------------- | -------------------------------------------- | ----------------------------- |
| Definition        | "ITH" defined differently in 2 projects      | Consolidate to ONE definition |
| Acronym           | "ITH" vs "Investment-TH" for same term       | Standardize to ONE acronym    |
| Acronym collision | "CV" = "Coefficient of Variation" AND others | Rename one acronym            |

### Scan Configuration

Edit `~/.claude/docs/GLOSSARY.md` to configure scan paths:

```markdown
<!-- SCAN_PATHS:
- ~/eon/*/CLAUDE.md
- ~/eon/*/*/CLAUDE.md
- ~/.claude/docs/GLOSSARY.md
-->
```


## Original hub-table narrative (PreToolUse, moved 2026-06-11)

> Moved VERBATIM from the PreToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: (inlined in iter-91 orchestrator)

**Rejects** Write/Edit on `CLAUDE.md` files with `vale` lint warning-or-error findings (terminology config at `~/.claude/.vale.ini`). Edit-path scoping limits findings to changed-line range ± 3-line buffer so pre-existing issues elsewhere don't false-positive. The precise algorithm-encoding classifier name is `classifyValeTerminologyConformanceOnClaudeMdGuardForOrchestrator`; the alias `classifyValeClaudeMdGuardForOrchestrator` preserves symmetric naming with sibling subhooks. Heaviest classifier in the registry: spawns external `vale` subprocess against a tempfile holding proposed content (100-300ms typical wall-clock). Iter-91 registry `timeoutMs: 12000ms` provides generous headroom for slow-disk/cold-cache machines. **This was the FINAL subhook of the iter-84 → iter-91 PreToolUse Write\|Edit migration arc**; standalone hook remains runnable for direct-CLI invocation. Lightest-first registry position: LAST (after `file-size-guard`).

## Original hub-table narrative (PostToolUse, moved 2026-06-11)

> Moved VERBATIM from the PostToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: (inlined in iter-96 orchestrator)

Vale terminology check on CLAUDE.md files (informational only — visibility, not blocking). **Iter-96 fifth inlined PostToolUse subhook (5/15 in arc)** — async Bun.spawn via shared lib helpers. PostToolUse twin to the iter-91 PreToolUse vale-claude-md-guard (that one BLOCKS before edit; this one INFORMS after edit). Walks up from edited file directory looking for `.vale.ini`, falls back to `~/.claude/.vale.ini`. Edit-path line-scoping ±3-line buffer prevents pre-existing-issue spam. Algorithm encoded in `classifyValeTerminologyConformanceOnEditedClaudeMdFileForPostToolUseOrchestrator`; alias `classifyValeClaudeMdForPostToolUseOrchestrator`. Standalone hook still runnable via `import.meta.main` guard.

## Original hub-table narrative (PostToolUse, moved 2026-06-11)

> Moved VERBATIM from the PostToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: Write\|Edit

Auto-sync GLOSSARY.md to Vale vocabulary

## Original hub-table narrative (PostToolUse, moved 2026-06-11)

> Moved VERBATIM from the PostToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: Write\|Edit

Project CLAUDE.md to global GLOSSARY.md sync
