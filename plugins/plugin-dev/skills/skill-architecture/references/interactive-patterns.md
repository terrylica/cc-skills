**Skill**: [Skill Architecture](../SKILL.md)

# Interactive Patterns (AskUserQuestion)

Skills that manage multi-option workflows, destructive operations, or diagnostic processes should integrate `AskUserQuestion` for structured user interaction. This reference documents five canonical patterns.

---

## Prerequisites

Include `AskUserQuestion` in the skill's `allowed-tools` field:

```yaml
---
name: my-skill
description: ...
allowed-tools: Read, Bash, Glob, AskUserQuestion
---
```

---

## Pattern 1: Intent Branching

Present action options when a single skill handles multiple related operations.

**Use when**: The skill supports start/stop/restart, create/update/delete, or other mutually exclusive actions.

**Structure**:

```markdown
## Phase 1: Determine Intent

Use AskUserQuestion to present available actions:

"What would you like to do?"

- Start service
- Stop service
- Restart service
- View logs
```

**TodoWrite integration**:

```
1. [Preflight] Check current service state
2. [Ask] Present action options via AskUserQuestion
3. [Execute] Perform selected action
4. [Verify] Confirm state change
```

**Guidelines**:

- List the most common action first
- Include a status/diagnostic option when available
- Limit to 4 options per question (use follow-up questions for sub-choices)

---

## Pattern 2: Destructive Action Confirmation

Require explicit confirmation before irreversible operations.

**Use when**: The operation deletes data, stops services, removes configurations, or modifies shared state.

**Structure**:

```markdown
## Phase 1: Confirm Scope

Present what will be affected:

"This will remove the following:"

- Runtime environment (~500MB)
- Shell integrations (symlinks)
- Temporary files
- Secrets (optional, requires separate confirmation)

"Proceed with removal?"

- Full removal (all components)
- Partial removal (keep secrets and config)
- Cancel
```

**TodoWrite integration**:

```
1. [Preflight] Inventory components to remove
2. [Ask] Confirm removal scope via AskUserQuestion
3. [Execute] Remove in dependency order
4. [Verify] Confirm removal complete
5. [Ask] Remove secrets? (separate confirmation)
```

**Guidelines**:

- List exactly what will be affected (sizes, counts)
- Always include a "Cancel" or "Dry run" option
- Separate secrets removal into its own confirmation step
- Document what is preserved and why

---

## Pattern 3: Configuration Group Selection

Present categorized settings for the user to choose which to adjust.

**Use when**: The skill manages configuration with multiple independent groups (voice, performance, queue, security, etc.).

**Structure**:

```markdown
## Phase 1: Read Current Configuration

Read and display current values from the configuration SSoT.

## Phase 2: Select Group

Use AskUserQuestion to present config categories:

"Which settings would you like to adjust?"

- Voice settings (language, model, speed)
- Performance settings (timeout, concurrency, queue depth)
- Notification settings (channels, rate limits)
- Security settings (tokens, permissions)
```

**TodoWrite integration**:

```
1. [Preflight] Read current configuration from SSoT
2. [Ask] Select configuration group via AskUserQuestion
3. [Ask] Choose specific values to change
4. [Execute] Edit configuration SSoT
5. [Verify] Validate new values against constraints
6. [Execute] Restart service if needed
```

**Guidelines**:

- Show current values before asking what to change
- Group by concern (not alphabetically)
- Validate ranges and types after editing
- Indicate which changes require a service restart

---

## Pattern 4: Symptom Collection

Gather problem context from the user to guide diagnostic workflows.

**Use when**: The skill performs troubleshooting and the root cause depends on symptoms the user has observed.

**Structure**:

```markdown
## Phase 1: Collect Symptoms

Use AskUserQuestion to understand the problem:

"What are you experiencing?"

- No output at all
- Output is wrong or garbled
- Intermittent failures
- Error messages in logs

"When did this start?"

- After a recent change
- Randomly / no clear trigger
- After system restart
```

**TodoWrite integration**:

```
1. [Ask] Collect symptoms via AskUserQuestion
2. [Execute] Run targeted diagnostics based on symptoms
3. [Execute] Check Known Issue Table for matches
4. [Ask] Confirm suspected root cause with user
5. [Execute] Apply fix
6. [Verify] Confirm issue resolved
```

**Guidelines**:

- Start broad ("what happened?"), then narrow ("when?", "what changed?")
- Map symptoms to diagnostic commands (avoid running all checks for every issue)
- Present findings before applying fixes
- Cross-reference a Known Issue Table when available (see [Advanced Topics](./advanced-topics.md))

---

## Pattern 5: Feedback Collection

Gather user preferences after presenting options or completing an action.

**Use when**: The skill compares alternatives (A/B testing voices, themes, configurations) or needs subjective judgment.

**Structure**:

```markdown
## Phase 5: Collect Feedback

After presenting options A, B, and C:

"Which option did you prefer?"

- Option A
- Option B
- Option C
- None of these / try different options

"Apply this as the new default?"

- Yes, update configuration
- No, keep current default
```

**TodoWrite integration**:

```
1. [Preflight] Verify comparison environment ready
2. [Execute] Present option A
3. [Execute] Present option B
4. [Ask] Which option preferred?
5. [Ask] Apply as new default?
6. [Execute] Update configuration if confirmed
```

**Guidelines**:

- Present options with objective metadata (grade, rating, characteristics) alongside subjective experience
- Always offer a "none / try more" option
- Separate preference from application (ask "which?" then "apply?")
- Log preferences for future reference

---

## Anti-Patterns

| Anti-Pattern                 | Problem                                  | Fix                                    |
| ---------------------------- | ---------------------------------------- | -------------------------------------- |
| Asking without showing state | User can't make informed decision        | Always display current state first     |
| Single "Are you sure?"       | Too vague for destructive operations     | List exactly what will be affected     |
| Too many questions           | Decision fatigue, user abandons workflow | Maximum 2-3 questions per phase        |
| No cancel option             | User feels trapped                       | Always include cancel/skip             |
| Asking after the fact        | "Did that work?" without verification    | Run automated checks instead of asking |

---

## Combining with Phased Execution

Interactive patterns integrate naturally with [Phased Execution](./phased-execution.md):

```
Preflight → [Ask] Intent → Execute → Verify → [Ask] Feedback
```

The `[Ask]` phase label signals that user interaction is needed at that step. This helps both Claude (knows to use AskUserQuestion) and the user (sees where input is needed in the TodoWrite checklist).
