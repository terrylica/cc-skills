# Vale Terminology Enforcement

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md).

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

1. **pretooluse-vale-claude-md-guard.ts** → subhook `vale-claude-md-guard` of the [PreToolUse Write/Edit orchestrator](./pretooluse-write-edit-orchestrator.md); runs Vale on the proposed content and rejects warning-or-error findings

**PostToolUse (informational after edit)**:

1. **posttooluse-vale-claude-md.ts** → subhook `vale-claude-md` of the [PostToolUse Write/Edit orchestrator](./posttooluse-write-edit-orchestrator.md); runs Vale and shows terminology violations (visibility only)
2. **posttooluse-glossary-sync.ts** → its own `Write|Edit` entry; when `~/.claude/docs/GLOSSARY.md` itself is edited, updates the Vale vocabulary
3. **posttooluse-terminology-sync.ts** → its own `Write|Edit` entry; syncs a project CLAUDE.md's terms to the global GLOSSARY.md, detects duplicates, then runs `~/.claude/tools/bin/glossary-sync.ts` to refresh the Vale vocabulary

### Implementation Details (pretooluse-vale-claude-md-guard.ts)

1. **Scope**: only paths ending in `CLAUDE.md`, and only when `~/.claude/.vale.ini` exists (no config, no enforcement). It does not walk up for a project `.vale.ini`.
2. **Proposed content**: Write lints `content`; Edit applies `old_string` → `new_string` to the on-disk file first. The result is written to a temp directory as `CLAUDE.md` and linted there.
3. **Edit scoping**: findings are limited to the changed-line range ± 3 lines, so pre-existing issues elsewhere in the file do not block an edit.
4. **Severity**: `VALE_CLAUDE_MD_GUARD_SEVERITY_INCLUSION_THRESHOLD = "warning"` counts warnings and errors.
5. **Cost**: the heaviest subhook in its registry (Vale typically takes 100–300 ms), so it runs last, with a 12000 ms orchestrator timeout.

The classifier is `classifyValeTerminologyConformanceOnClaudeMdGuardForOrchestrator`, exported under the alias `classifyValeClaudeMdGuardForOrchestrator`.

### Implementation Details (posttooluse-vale-claude-md.ts)

The PostToolUse Vale hook is **cwd-agnostic** and works from any directory:

1. **Config discovery**: Walks UP from the file's directory to find `.vale.ini`, falls back to `~/.claude/.vale.ini`
2. **Directory change**: Runs `vale --config <ini> --output=JSON <file>` from the file's directory so glob patterns like `[CLAUDE.md]` match
3. **Parsing**: Reads Vale's JSON output and counts errors, warnings and suggestions
4. **Edit scoping**: For an Edit (not `replace_all`), reports only findings in the changed-line range ± 3 lines; a Write reports the whole file
5. **Skips**: throwaway files in temp directories; and silently does nothing when `vale` is not installed or its 10000 ms subprocess timeout fires (orchestrator timeout 12000 ms)

The classifier is `classifyValeTerminologyConformanceOnEditedClaudeMdFileForPostToolUseOrchestrator`, exported under the alias `classifyValeClaudeMdForPostToolUseOrchestrator`. Both Vale hooks also run standalone through their `import.meta.main` guards.

### PreToolUse vs PostToolUse

| Hook Type   | When             | Can Reject? | Use Case                         |
| ----------- | ---------------- | ----------- | -------------------------------- |
| PreToolUse  | BEFORE tool runs | YES         | Block bad edits                  |
| PostToolUse | AFTER tool runs  | NO          | Inform about issues (visibility) |

The PreToolUse hook uses `permissionDecision: "deny"` (hard rejection). Set `VALE_CLAUDE_MD_GUARD_ENFORCEMENT_MODE` to `"ask"` in `pretooluse-vale-claude-md-guard.ts` for a permission dialog instead.

> **Note**: glossary-sync and terminology-sync are separate hooks in the same `Write|Edit` matcher group, so Claude Code runs them in parallel; neither waits for the other. terminology-sync refreshes the Vale vocabulary itself after merging terms.

### Duplicate Detection

The terminology-sync hook scans ALL configured CLAUDE.md files and reports conflicts with `decision: "block"` (the edit has already happened; the block makes the conflict visible to Claude, which must resolve it):

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
