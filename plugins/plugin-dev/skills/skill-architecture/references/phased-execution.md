**Skill**: [Skill Architecture](../SKILL.md)

# Phased Execution Patterns

Robust skills follow a phased execution model that prevents failures, guides users through complex operations, and verifies outcomes. This reference documents the core pattern and its variants.

---

## Core Pattern: Preflight → Execute → Verify

Every non-trivial skill workflow should follow three phases:

### Phase 0: Preflight

Verify prerequisites exist and the system is in a valid state before starting work.

**What to check**:

- Required tools installed (`command -v tool`)
- Required services running (`pgrep -la service`)
- Configuration files present and valid
- No conflicting processes or stale lock files
- Sufficient permissions for the operation

**Fail fast**: If any preflight check fails, stop immediately with an actionable error message. Never proceed with missing prerequisites.

```
[Preflight] Verify bun installed: command -v bun
[Preflight] Verify mise installed: command -v mise
[Preflight] Verify config exists: test -f config.toml
[Preflight] Check no conflicting processes: ! pgrep -f "service-name"
```

### Phase 1: Execute

Perform the core operation with clear progress indicators.

```
[Execute] Install dependencies
[Execute] Configure environment
[Execute] Start service
```

### Phase 2: Verify

Confirm the operation succeeded by checking expected outcomes.

```
[Verify] Service responds to health check
[Verify] Config values match expectations
[Verify] No errors in log output
```

---

## TodoWrite Phase Labels

Use bracketed phase labels in TodoWrite templates for clarity and traceability:

| Label         | Purpose                   | Example                                      |
| ------------- | ------------------------- | -------------------------------------------- |
| `[Preflight]` | Prerequisite verification | `[Preflight] Verify Python 3.13 installed`   |
| `[Execute]`   | Core operation steps      | `[Execute] Install package dependencies`     |
| `[Verify]`    | Outcome confirmation      | `[Verify] Service responds on port 8080`     |
| `[Cleanup]`   | Post-operation tidying    | `[Cleanup] Remove temporary build artifacts` |
| `[Ask]`       | User input required       | `[Ask] Select configuration profile`         |

**Template example**:

```
1. [Preflight] Verify all prerequisites installed
2. [Preflight] Check no conflicting processes running
3. [Preflight] Validate configuration file
4. [Execute] Stop existing service
5. [Execute] Install new version
6. [Execute] Apply configuration
7. [Verify] Service starts successfully
8. [Verify] Health check passes
9. [Cleanup] Remove old version artifacts
```

---

## Variant: Sandwich Verification

Capture baseline state before an operation, execute, then re-run the same checks to compare.

**Use when**: Upgrading components, applying configuration changes, or any operation where regressions are possible.

**Pattern**:

```
1. [Preflight] Run health check (record baseline)
2. [Preflight] Record current versions
3. [Execute] Perform upgrade/change
4. [Verify] Re-run same health check
5. [Verify] Compare versions (old → new)
6. [Verify] Confirm no regressions (all checks still pass)
```

**Key principle**: The pre-check and post-check must be identical. Use the same diagnostic commands before and after so results are directly comparable.

**Example health check table**:

```markdown
| Subsystem       | Before             | After              | Status  |
| --------------- | ------------------ | ------------------ | ------- |
| Service process | Running (PID 1234) | Running (PID 5678) | OK      |
| API endpoint    | 200 OK             | 200 OK             | OK      |
| Version         | 1.2.0              | 1.3.0              | Updated |
| Dependencies    | All present        | All present        | OK      |
```

---

## Variant: Dependency-Aware Teardown

Remove components in the correct order, respecting dependencies between them.

**Use when**: Uninstalling, cleaning up, or decommissioning multi-component systems.

**Pattern**:

```
1. [Ask] Confirm teardown scope (full vs partial)
2. [Execute] Stop running processes (must come first)
3. [Execute] Remove runtime artifacts (venvs, caches)
4. [Execute] Remove integrations (symlinks, hooks, cron jobs)
5. [Execute] Clean temporary files
6. [Ask] Confirm secrets removal (optional, explicit consent)
```

**Ordering rules**:

1. Processes must stop before their files can be removed
2. Dependents must be removed before their dependencies
3. Secrets removal is always optional and requires explicit confirmation
4. Configuration and source code are preserved by default (for easy reinstall)

**Document what is NOT removed and why**:

```markdown
| Preserved     | Reason                                     | Location                 |
| ------------- | ------------------------------------------ | ------------------------ |
| Model cache   | Large download, reusable across reinstalls | ~/.cache/models/         |
| Source code   | Git-tracked, not a runtime artifact        | ~/project/src/           |
| Configuration | SSoT for environment, needed for reinstall | ~/project/mise.toml      |
| Audit logs    | Compliance/debugging history               | ~/.local/share/app/logs/ |
```

**Reversibility**: Each removal step should note whether it is reversible. Stopping a process is reversible (restart it). Deleting a venv is partially reversible (recreate it). Deleting secrets requires re-provisioning.

---

## Variant: Config Read-Edit-Validate-Apply

Manage configuration through a structured read-edit-validate cycle using a single source of truth.

**Use when**: Skills that manage settings, environment variables, or configuration files.

**Pattern**:

```
1. [Preflight] Read current config from SSoT
2. [Ask] Present config groups to user (categorized by concern)
3. [Execute] Edit selected values in SSoT
4. [Verify] Validate new values against constraints (ranges, types, enums)
5. [Execute] Apply changes (restart service if needed)
6. [Verify] Confirm new values are active
```

**Configuration grouping**: Present settings categorized by concern, not alphabetically:

```markdown
Which settings to adjust?

- Voice settings (language, voice model, speed)
- Performance settings (timeout, queue depth, concurrency)
- Notification settings (channels, rate limits, formatting)
- Security settings (tokens, permissions, audit level)
```

**Validation rules**: Each setting should have documented constraints:

```markdown
| Setting    | Type  | Range                       | Default |
| ---------- | ----- | --------------------------- | ------- |
| speed      | float | 0.5-2.0                     | 1.25    |
| timeout_ms | int   | 1000-60000                  | 15000   |
| max_queue  | int   | 1-100                       | 5       |
| voice      | enum  | [voice_a, voice_b, voice_c] | voice_a |
```

**SSoT principle**: All configuration lives in one file. Skills read from and write to this single location. No duplicated config values across multiple files.

---

## Combining Phases with Interactive Patterns

Phased execution often combines with [Interactive Patterns](./interactive-patterns.md):

```
1. [Preflight] Verify prerequisites
2. [Ask] What would you like to do? (intent branching)
3. [Execute] Perform selected action
4. [Verify] Confirm result
5. [Ask] Satisfied with the outcome? (feedback)
```

See [Interactive Patterns](./interactive-patterns.md) for detailed AskUserQuestion patterns.

---

## Anti-Patterns

| Anti-Pattern                   | Problem                                     | Fix                                  |
| ------------------------------ | ------------------------------------------- | ------------------------------------ |
| Skip preflight                 | Operation fails mid-way, harder to diagnose | Always check prerequisites first     |
| No verification                | Silent failures go unnoticed                | Always confirm expected outcomes     |
| Verify different things        | Pre and post checks not comparable          | Use identical diagnostic commands    |
| Remove before stop             | Files locked by running process             | Always stop processes first          |
| Edit config without validation | Invalid values cause runtime errors         | Validate constraints before applying |
| Hardcode removal order         | Dependencies change over time               | Document ordering rationale          |
