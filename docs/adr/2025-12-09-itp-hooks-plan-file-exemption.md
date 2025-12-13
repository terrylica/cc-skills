---
status: accepted
date: 2025-12-09
decision-maker: Terry Li
consulted:
  [
    Explore Agent (pretooluse-guard analysis),
    Explore Agent (plan file patterns),
  ]
research-method: multi-agent
clarification-iterations: 2
perspectives: [Usability, Configuration, Backward Compatibility]
---

# Exempt Plan Files from ASCII Diagram Blocking in pretooluse-guard.sh

> **Update 2025-12-12**: Broadened exemption pattern from `/.claude/plans/` to any `/plans/` directory. Removed configurable env var — now unconditional.

**Design Spec**: [Implementation Spec](/docs/design/2025-12-09-itp-hooks-plan-file-exemption/spec.md)

## Context and Problem Statement

The `pretooluse-guard.sh` hook in the itp-hooks plugin blocks writes to markdown files containing ASCII box-drawing characters (≥10 chars) without a `<summary>graph-easy source</summary>` block. This enforcement ensures reproducible diagrams in production documentation.

However, this blocking also affects **plan files** (`~/.claude/plans/*.md`) which are:

1. AI-generated during Claude's planning phase
2. Ephemeral (overwritten on new planning sessions)
3. May contain tables or diagrams that don't yet have graph-easy source blocks

This creates a workflow disruption where Claude cannot write plan files with tables, forcing workarounds during the planning phase.

### Before/After Diagram

**Before**: Plan file writes blocked by ASCII diagram enforcement

```
⏮️ Before: Plan File Write Blocked

     ╭────────────────────────╮
     │    Claude Planning     │
     ╰────────────────────────╯
       │
       ∨
     ┌────────────────────────┐
     │    Write Plan File     │
     │ (~/.claude/plans/*.md) │
     └────────────────────────┘
       │
       ∨
     ┌────────────────────────┐
     │  pretooluse-guard.sh   │
     └────────────────────────┘
       │
       ∨
     ┌────────────────────────┐
     │      ASCII Check       │
     │   (box chars >= 10)    │
     └────────────────────────┘
       │
       │ no source block
       ∨
     ╔════════════════════════╗
     ║        BLOCKED         ║
     ║        (exit 2)        ║
     ╚════════════════════════╝
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏮️ Before: Plan File Write Blocked"; flow: south; }
[ Claude Planning ] { shape: rounded; }
[ Write Plan File\n(~/.claude/plans/*.md) ]
[ pretooluse-guard.sh ]
[ ASCII Check\n(box chars >= 10) ]
[ BLOCKED\n(exit 2) ] { border: double; }

[ Claude Planning ] -> [ Write Plan File\n(~/.claude/plans/*.md) ]
[ Write Plan File\n(~/.claude/plans/*.md) ] -> [ pretooluse-guard.sh ]
[ pretooluse-guard.sh ] -> [ ASCII Check\n(box chars >= 10) ]
[ ASCII Check\n(box chars >= 10) ] -- no source block --> [ BLOCKED\n(exit 2) ]
```

</details>

**After**: Plan files exempted via configurable environment variable

```
⏭️ After: Plan Files Exempted

╭──────────────────────────╮
│     Claude Planning      │
╰──────────────────────────╯
  │
  ∨
┌──────────────────────────┐
│     Write Plan File      │
│  (~/.claude/plans/*.md)  │
└──────────────────────────┘
  │
  ∨
┌──────────────────────────┐
│   pretooluse-guard.sh    │
└──────────────────────────┘
  │
  ∨
┌──────────────────────────┐
│     Plan Path Check      │
└──────────────────────────┘
  │
  │ matches /.claude/plans/
  ∨
┌──────────────────────────┐
│ ITP_HOOKS_EXEMPT_PLANS?  │
└──────────────────────────┘
  │
  │ true or unset
  ∨
╭──────────────────────────╮
│         ALLOWED          │
│         (exit 0)         │
╰──────────────────────────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏭️ After: Plan Files Exempted"; flow: south; }
[ Claude Planning ] { shape: rounded; }
[ Write Plan File\n(~/.claude/plans/*.md) ]
[ pretooluse-guard.sh ]
[ Plan Path Check ]
[ ITP_HOOKS_EXEMPT_PLANS? ]
[ ALLOWED\n(exit 0) ] { shape: rounded; }

[ Claude Planning ] -> [ Write Plan File\n(~/.claude/plans/*.md) ]
[ Write Plan File\n(~/.claude/plans/*.md) ] -> [ pretooluse-guard.sh ]
[ pretooluse-guard.sh ] -> [ Plan Path Check ]
[ Plan Path Check ] -- matches /.claude/plans/ --> [ ITP_HOOKS_EXEMPT_PLANS? ]
[ ITP_HOOKS_EXEMPT_PLANS? ] -- true or unset --> [ ALLOWED\n(exit 0) ]
```

</details>

## Decision Drivers

- **Workflow continuity**: Planning should not be interrupted by enforcement rules meant for production docs
- **Configuration as SSoT**: Environment variables managed via mise for consistency
- **Backward compatibility**: Existing behavior preserved when variable not set (with warning)
- **Explicit opt-out**: Users can re-enable blocking for plan files if desired

## Considered Options

1. **Hard-coded exemption**: Always exempt plan files (no configuration)
2. **Environment variable with default true**: Configurable via mise, defaults to exempt
3. **Environment variable with default false**: Require explicit opt-in to exempt
4. **Path-based configuration file**: Separate config file for exempt paths

## Decision Outcome

**Chosen option**: ~~"Environment variable with default true + warning when unset"~~ → **Unconditional exemption** (updated 2025-12-12)

~~This provides:~~
~~- Immediate fix for workflow disruption (defaults to exempt)~~
~~- Warning message when mise not configured (encourages SSoT setup)~~
~~- Explicit control via `ITP_HOOKS_EXEMPT_PLANS` variable~~
~~- Zero breaking changes for existing users~~

**Simplified approach** (2025-12-12): Unconditional exemption for any `/plans/*.md` path. Rationale:

- Plan directories are inherently ephemeral/working documents
- Configuration overhead not justified for this use case
- Broader pattern (`/plans/`) covers workspace archives like `tmp/plans/`

### Implementation

**File**: `plugins/itp-hooks/hooks/pretooluse-guard.sh`

**Logic** (simplified 2025-12-12):

```bash
# Exempt plan files from ASCII art blocking
# Matches any /plans/*.md path (Claude plans, workspace archives, etc.)
if [[ "$FILE_PATH" =~ /plans/.*\.md$ ]]; then
    exit 0
fi
```

**Matches**:

- `~/.claude/plans/*.md` (Claude's canonical plan location)
- `tmp/plans/*.md` (workspace plan archives)
- `docs/plans/*.md` (any plans directory)

~~**Configuration** (mise SSoT)~~ — No longer needed; exemption is unconditional.

## Architecture

```
🏗️ Architecture: Plan File Exemption Flow

╔═════════════╗  exports   ┌─────────┐  reads   ┌──────────┐     ┌────────────┐  other   ┌─────────────┐
║ mise config ║ ─────────> │ ENV VAR │ ───────> │ guard.sh │ ──> │ Path Check │ ───────> │ ASCII Check │
╚═════════════╝            └─────────┘          └──────────┘     └────────────┘          └─────────────┘
                                                                   │
                                                                   │ plan file
                                                                   ∨
                                                                 ╭────────────╮
                                                                 │   Exempt   │
                                                                 ╰────────────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ Architecture: Plan File Exemption Flow"; flow: east; }
[ mise config ] { border: double; }
[ ENV VAR ]
[ guard.sh ]
[ Path Check ]
[ Exempt ] { shape: rounded; }
[ ASCII Check ]

[ mise config ] -- exports --> [ ENV VAR ]
[ ENV VAR ] -- reads --> [ guard.sh ]
[ guard.sh ] -> [ Path Check ]
[ Path Check ] -- plan file --> [ Exempt ]
[ Path Check ] -- other --> [ ASCII Check ]
```

</details>

### Consequences

**Good**:

- Plan files can contain tables/diagrams without blocking
- ~~Configurable behavior via mise environment variables~~ → Simpler unconditional logic (updated 2025-12-12)
- ~~Warning guides users toward SSoT pattern~~ → No warnings needed
- No breaking changes
- Broader coverage: any `/plans/` directory now exempt

**Neutral**:

- ~~Additional conditional logic in hook (~7 lines)~~ → Reduced to 4 lines (updated 2025-12-12)
- ~~New environment variable to document~~ → No env var needed

**Bad**:

- Plan files with ASCII diagrams won't be validated (acceptable for ephemeral docs)
- Broader pattern could exempt unintended files in `/plans/` directories (low risk)

## More Information

- Related: ASCII diagram enforcement for production docs remains unchanged
- ~~Pattern: Uses bash `${VAR+x}` expansion to detect unset vs empty variables~~ → Simplified to unconditional check (2025-12-12)
- ~~SSoT: mise `[env]` section is the canonical location for this configuration~~ → No longer applicable
- **Update 2025-12-12**: Pattern broadened from `/.claude/plans/` to `/plans/`, configuration removed
