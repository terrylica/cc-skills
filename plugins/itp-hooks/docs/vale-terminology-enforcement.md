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

