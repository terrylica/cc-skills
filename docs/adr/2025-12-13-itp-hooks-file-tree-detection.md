---
status: accepted
date: 2025-12-13
decision-maker: Terry Li
consulted:
  [
    Explore Agent (hook detection logic),
    Explore Agent (file tree patterns),
    Plan Agent (implementation design),
  ]
research-method: multi-agent
clarification-iterations: 1
perspectives:
  [Developer Experience, False Positive Prevention, Minimal Complexity]
---

# Detect File Trees to Avoid False Positives in ASCII Diagram Blocking

**Related**: [Plan File Exemption ADR](/docs/adr/2025-12-09-itp-hooks-plan-file-exemption.md)

## Context and Problem Statement

The `pretooluse-guard.sh` hook blocks markdown writes containing 10+ box-drawing characters without a `<summary>graph-easy source</summary>` block. This enforcement ensures reproducible diagrams in production documentation.

However, this blocking also affects **file/directory trees** which use box-drawing characters (`├`, `└`, `│`, `─`) but are NOT diagrams requiring reproducibility:

```
src/
├── main.py
├── utils.py
└── __init__.py
```

A 15-item directory tree easily exceeds the 10-character threshold, causing false positives and blocking legitimate documentation.

## Decision Drivers

- **Developer experience**: File trees are common documentation patterns
- **False positive cost**: Blocking valid content disrupts workflow
- **Minimal complexity**: Solution should not significantly complicate the hook
- **Preserve enforcement**: Box diagrams should still require graph-easy source

## Considered Options

1. **Character-based heuristic**: Detect absence of box corners
2. **Pattern-based heuristic**: Match `├──` or `└──` patterns
3. **Threshold adjustment**: Increase character count from 10 to 30+
4. **Allowlist patterns**: Explicit file tree syntax detection

## Decision Outcome

**Chosen option**: "Character-based heuristic"

File trees use `├`, `└`, `│`, `─` but NEVER use box corners (`┌`, `┐`, `┘`) that form enclosed shapes. If content has no box corners, it's not a box diagram.

| Content Type | Uses `├ └ │ ─` | Uses `┌ ┐ ┘` |
| ------------ | -------------- | ------------ |
| File trees   | Yes            | No           |
| Box diagrams | Yes            | Yes          |

### Implementation

**File**: `plugins/itp-hooks/hooks/pretooluse-guard.sh`

Insert early-exit check after getting content, before existing BOX_CHARS logic:

```bash
# File tree detection - skip blocking for content without box corners
# File trees use ├ └ │ ─ but NEVER use ┌ ┐ ┘ (corners that form enclosed boxes)
BOX_CORNER_CHARS='[┌╔┏╭┐╗┓╮┘╝┛╯]'
if ! echo "$CONTENT" | grep -q "$BOX_CORNER_CHARS"; then
    exit 0
fi
```

**Character set**:

- Top-left corners: `┌`, `╔`, `┏`, `╭`
- Top-right corners: `┐`, `╗`, `┓`, `╮`
- Bottom-right corners: `┘`, `╝`, `┛`, `╯`
- **Excluded**: `└` (bottom-left) — used in file trees as `└──`

### Consequences

**Good**:

- File trees allowed without source blocks
- Zero false positives for common documentation patterns
- Minimal code addition (~5 lines)
- Box diagrams still require graph-easy source

**Neutral**:

- Additional grep check adds ~1ms overhead

**Bad**:

- Edge case: ASCII art using only bottom-left corners would pass (unlikely scenario)

## More Information

- Related: [Plan file exemption](/docs/adr/2025-12-09-itp-hooks-plan-file-exemption.md) uses path-based detection
- This ADR uses character-based detection for content analysis
- Combined, these exemptions cover ephemeral plans and structural documentation
