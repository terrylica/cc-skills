# Registry Schema: Autonomous Loop Machine-Level Registry

**Version:** 1  
**Last Updated:** 2026-04-26  
**Purpose:** Define the machine-level registry structure that tracks every active loop on the system.

## Overview

The autonomous-loop registry is a single JSON file at `~/.claude/loops/registry.json` that serves as the canonical source of truth for all active loops on a machine. It enables:

- **Unique loop identification** via `loop_id` (derived from contract path)
- **Ownership tracking** via session ID and process ID
- **Heartbeat staleness detection** for recovery and external waker logic
- **Hook-based loop discovery** without requiring per-hook configuration

## Top-Level Structure

```json
{
  "loops": [
    { ... loop entry ... },
    { ... loop entry ... }
  ],
  "schema_version": 1
}
```

- `loops`: Array of active loop entries (see below)
- `schema_version`: Numeric version of the registry schema (currently `1`)

## Per-Loop Entry Fields

Each entry in the `loops` array represents one active loop on the system.

### loop_id

**Type:** String  
**Format:** Exactly 12 hexadecimal characters (lowercase: `[0-9a-f]{12}`)  
**Purpose:** Primary key; unique identifier derived deterministically from the absolute contract path  
**Derivation:** `sha256(realpath(contract_path))[:12]`  
**Immutable:** Yes — same contract path always yields the same `loop_id`

Example: `a1b2c3d4e5f6`

### contract_path

**Type:** String  
**Format:** Absolute filesystem path (realpath-resolved, no symlinks)  
**Purpose:** Points to the LOOP_CONTRACT.md file for this loop  
**Requirements:**

- Must be an absolute path (starts with `/` on Unix/macOS)
- Must be realpath-resolved (symlinks followed to their targets)
- Must exist and be readable at registry entry time

Example: `/Users/terrylica/eon/ff-calendar/contracts/labels.md`

### state_dir

**Type:** String  
**Format:** Absolute filesystem path  
**Purpose:** Directory where loop-specific state lives (heartbeat, locks, revision log)  
**Standard:** Usually `<repo_root>/.loop-state/<loop_id>/`  
**Requirements:**

- Must be on the same filesystem as `contract_path` (atomic rename requirement; see Pitfall #4)
- Created by Phase 2 (write operations)

Example: `/Users/terrylica/eon/ff-calendar/.loop-state/a1b2c3d4e5f6/`

### owner_session_id

**Type:** String  
**Format:** Session identifier (typically `claude_<hash>`)  
**Purpose:** Identifies the Claude session that currently owns this loop  
**Usage:** Hooks verify this matches `$CLAUDE_SESSION_ID` before writing heartbeats (prevents cross-session contamination)  
**Lifetime:** Changed when loop ownership is reclaimed (Phase 4)

Example: `claude_abc123def456`

### owner_pid

**Type:** Number (integer)  
**Format:** Valid process ID (≥ 1)  
**Purpose:** Process ID of the current owner's Claude Code instance  
**Usage:** Liveness checks via `kill -0 $owner_pid`; defends against stale ownership claims  
**Lifetime:** Changed when loop ownership is reclaimed

Example: `12345`

### owner_start_time_us

**Type:** Number (integer)  
**Format:** Microseconds since Unix epoch (January 1, 1970 UTC)  
**Purpose:** When the owner process started (PID-reuse defense; see Pitfall #1)  
**Usage:** Combined with `owner_pid` via `ps -p $owner_pid -o start=` to defend against OS reusing a PID  
**Lifetime:** Changed when loop ownership is reclaimed

Example: `1724000000000000` (approximately August 18, 2024)

### launchd_label

**Type:** String  
**Format:** `com.user.claude.loop.<loop_id>` (12 hex chars lowercase)  
**Purpose:** macOS launchd job label for the external waker (Phase 8)  
**Requirements:**

- Must be valid launchd label (alphanumeric, dots, underscores only)
- Must be globally unique (enforced by deriving from immutable `loop_id`)

Example: `com.user.claude.loop.a1b2c3d4e5f6`

### started_at_us

**Type:** Number (integer)  
**Format:** Microseconds since Unix epoch  
**Purpose:** When the current owner acquired the loop lock (distinct from process start time)  
**Usage:** Computed as `now - heartbeat_age` to determine staleness  
**Lifetime:** Updated when ownership is reclaimed; represents the most recent acquisition time

Example: `1724000000000000`

### expected_cadence_seconds

**Type:** Number (integer)  
**Format:** Positive integer ≥ 1, max 86400 (1 day)  
**Purpose:** Expected interval between heartbeat updates (in seconds)  
**Default:** 1500 (25 minutes)  
**Usage:**

- Staleness threshold: heartbeat older than `3 × expected_cadence_seconds` → consider stale for reclaim
- External waker threshold: heartbeat older than `4 × expected_cadence_seconds` → spawn resume

Typical values:

- Continuous loops (every PostToolUse): 1–5 seconds
- High-frequency loops: 60 seconds
- Hourly loops: 3600 seconds

Example: `1500`

### generation

**Type:** Number (integer)  
**Format:** Non-negative integer, monotonic  
**Purpose:** TOCTOU (time-of-check-time-of-use) defense for reclaim races (Phase 4)  
**Semantics:**

- Starts at 0 when loop first entered registry
- Incremented by 1 each time ownership is reclaimed
- Used to detect if ownership changed between read and write

Example: `1`

## Example Registry Entry (Full)

```json
{
  "loop_id": "a1b2c3d4e5f6",
  "contract_path": "/Users/terrylica/eon/ff-calendar/contracts/labels.md",
  "state_dir": "/Users/terrylica/eon/ff-calendar/.loop-state/a1b2c3d4e5f6/",
  "owner_session_id": "claude_abc123def456",
  "owner_pid": 12345,
  "owner_start_time_us": 1724000000000000,
  "launchd_label": "com.user.claude.loop.a1b2c3d4e5f6",
  "started_at_us": 1724000000000000,
  "expected_cadence_seconds": 1500,
  "generation": 1
}
```

## Schema Versioning

The `schema_version` field (at top level) identifies the format of the registry structure:

- **schema_version: 1** — Current version (Phase 1)
- **Reading newer versions:** Downstream code MUST refuse to process `schema_version > 1` and prompt the user to upgrade
- **Backward compatibility:** If future phases add optional fields, `schema_version` remains 1
- **Breaking changes:** Changing required field semantics or removing fields → increment to `schema_version: 2`

## Pitfall Mitigations

### Pitfall #1: PID Reuse Attack

**Problem:** OS can reuse a PID after a process exits, leading to false "process is alive" checks.

**Mitigation:** Combine three checks:

1. `kill -0 $owner_pid` (process exists)
2. `ps -p $owner_pid -o command=` (verify command matches expected)
3. `owner_start_time_us` comparison (verify start time matches process start time)

**Implementation:** Performed in Phase 3 during reclaim logic.

**SSoT:** Both `owner_pid` and `owner_start_time_us` fields in the registry entry.

---

### Pitfall #2: Heartbeat Staleness Ambiguity

**Problem:** Without knowing the expected cadence, stale heartbeats are ambiguous (1 second old vs. 1 day old).

**Mitigation:** `expected_cadence_seconds` field provides the reference.

**Staleness definition:**

- `heartbeat_age > 3 × expected_cadence_seconds` → stale (eligible for reclaim)
- `heartbeat_age > 4 × expected_cadence_seconds` → very stale (external waker spawns resume)

**SSoT:** `expected_cadence_seconds` field in registry entry and `heartbeat.json` file's timestamp.

---

### Pitfall #3: Unbounded Registry Growth

**Problem:** Registry could grow unbounded if stale entries are never cleaned up.

**Mitigation:** Phase 10 (status enumeration) flags entries older than 7 days as reclaim candidates; manual cleanup follows.

**SSoT:** `started_at_us` field enables age computation.

---

### Pitfall #4: Atomic Rename Filesystem Mismatch

**Problem:** `mktemp` by default creates files in `$TMPDIR` (often `/tmp` on macOS), which may be on a different filesystem than the repo. Atomic rename (`mv`) will fail with `EXDEV` if source and destination are on different filesystems.

**Mitigation:** All temporary file creation (Phase 2 and beyond) MUST use `mktemp` with the state directory as the target, not `$TMPDIR`.

**Correct pattern:**

```bash
# DO THIS:
tmp=$(mktemp "$STATE_DIR/.tmp.XXXXXX")
# ... write to $tmp ...
mv "$tmp" "$STATE_DIR/heartbeat.json"
```

**Incorrect pattern:**

```bash
# DO NOT DO THIS:
tmp=$(mktemp)  # Creates in /tmp by default
# ... write to $tmp ...
mv "$tmp" "$STATE_DIR/heartbeat.json"  # FAILS with EXDEV if filesystems differ
```

**Requirement:** `state_dir` MUST reside on the same filesystem as the contract path (both typically in the same repository).

**SSoT:** `state_dir` field documents the expected location; Phase 2+ implementations MUST check `mv` exit code and fail with a readable error if EXDEV occurs.

---

## Filesystem Safety: Atomic Rename Requirement

All future writes to the registry (Phase 2 and beyond) MUST use atomic rename for safety:

1. Create a temporary file in the same directory as the target: `mktemp "$REGISTRY_DIR/.tmp.XXXXXX"`
2. Write all data to the temporary file
3. Atomically rename: `mv "$tmp" "$REGISTRY_DIR/registry.json"`

**Why:** Atomic rename ensures the registry is never in a partially-written state. On Unix-like systems, `mv` within the same filesystem is atomic.

**Phase 1 scope:** Phase 1 does NOT write the registry. This is documented here as a constraint for Phase 2+.

**Phase 2+ responsibility:** Implement `write_registry()` and `write_registry_entry()` with atomic-rename serialization.

---

## Phase 1 Scope: Schema Definition and Read-Only Operations

**Phase 1 deliverables:**

- Define the schema (this document)
- Provide read-only helpers: `read_registry()` and `read_registry_entry()`
- Create test fixtures (empty and 1-loop registries)
- Validate fixtures against the schema

**What Phase 1 does NOT do:**

- Write the registry file
- Create `~/.claude/loops/` directory
- Write entries on loop start
- Remove entries on loop stop
- Implement locking (flock) for serialization

**Why this boundary?**

Writes depend on locking primitives (Phase 2), which in turn depend on the schema being stable (Phase 1). By finishing schema and read helpers before implementing writes, we ensure downstream phases have a clear contract to implement against.

---

## Read API (registry-lib.sh)

Two read-only functions are provided in `plugins/autonomous-loop/scripts/registry-lib.sh`:

### read_registry([registry_path_override])

**Purpose:** Load and parse the entire registry.

**Call signature:**

```bash
registry=$(read_registry [path_override])
```

**Arguments:**

- `$1` (optional): Override path to registry file (for testing); defaults to `~/.claude/loops/registry.json`

**Return value:** Valid JSON (parsed registry or empty structure)

**Behavior:**

- Missing file: returns empty registry `{"loops": [], "schema_version": 1}`
- Valid file: returns parsed JSON
- Malformed file: logs warning to stderr, returns empty registry (graceful degradation)
- Fatal error (jq not installed): returns exit code 1

**Exit code:** 0 on all graceful paths; 1 only on fatal errors

**Example:**

```bash
source plugins/autonomous-loop/scripts/registry-lib.sh

registry=$(read_registry)
count=$(echo "$registry" | jq '.loops | length')
echo "Active loops: $count"
```

### read_registry_entry(loop_id [registry_path_override])

**Purpose:** Fetch a single loop entry by loop_id.

**Call signature:**

```bash
entry=$(read_registry_entry "a1b2c3d4e5f6" [path_override])
```

**Arguments:**

- `$1`: Loop ID (must be exactly 12 hexadecimal characters)
- `$2` (optional): Override path to registry file (for testing)

**Return value:**

- If found: entry object as JSON
- If not found: empty object `{}`
- If invalid loop_id: error message to stderr, exit code 1

**Exit code:**

- 0: entry found or gracefully not found
- 1: invalid loop_id format or fatal error

**Example:**

```bash
entry=$(read_registry_entry "a1b2c3d4e5f6")
if [[ "$entry" != "{}" ]]; then
  owner=$(echo "$entry" | jq -r '.owner_session_id')
  pid=$(echo "$entry" | jq -r '.owner_pid')
  echo "Loop owned by session $owner (pid $pid)"
else
  echo "Loop not found"
fi
```

---

## Downstream Phase Usage

| Phase | Operation                   | Function                  | Notes                                |
| ----- | --------------------------- | ------------------------- | ------------------------------------ |
| 1     | Define schema               | —                         | This document                        |
| 2     | Write entry on loop start   | `write_registry()`        | Not yet implemented                  |
| 2     | Remove entry on loop stop   | `delete_registry_entry()` | Not yet implemented                  |
| 4     | Reclaim logic               | `read_registry_entry()`   | Check ownership, validate generation |
| 6     | Hook: read registry         | `read_registry()`         | Find loop by cwd prefix match        |
| 10    | Status: enumerate all loops | `read_registry()`         | List all active loops                |

---

## JSON Schema Validation

A machine-readable JSON Schema is provided at `plugins/autonomous-loop/schemas/registry.schema.json` for validators (e.g., `ajv`, `json-schema-validator`).

Use it to validate registry files before consuming them:

```bash
jq -e '.' < ~/.claude/loops/registry.json > /dev/null && \
  echo "Valid JSON"
```

Or for full schema validation:

```bash
npx ajv validate -s plugins/autonomous-loop/schemas/registry.schema.json \
  -d ~/.claude/loops/registry.json
```

---

## Testing

Test fixtures are provided:

- `tests/fixtures/registry-empty.json` — Valid registry with no loops
- `tests/fixtures/registry-1-loop.json` — Valid registry with one realistic loop entry

Both files pass the JSON Schema validation and can be used to test reading, filtering, and enumeration logic.
