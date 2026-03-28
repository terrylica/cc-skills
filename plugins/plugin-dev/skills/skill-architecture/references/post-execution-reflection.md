**Skill**: [Skill Architecture](../SKILL.md)

# Post-Execution Reflection

Compulsory self-rectification pattern for agent skills. After every stepwise execution, the skill reminds Claude to retrospectively examine what happened and fix the skill's own artifacts based on empirical evidence.

---

## Why This Is Compulsory

Agent skills executing stepwise are inherently fragile. Instructions written in isolation break when they meet real environments — different OS versions, missing tools, unexpected file layouts, API changes, race conditions. Without a structural feedback loop, these failures repeat identically across sessions because the skill never learns from its own execution.

The Post-Execution Reflection pattern closes this loop. It is not a nice-to-have or a best practice — it is a **structural requirement** for any skill that performs multi-step work, because:

1. **Skills accumulate drift** — Instructions written for one environment silently fail in another. Only execution reveals the drift.
2. **Anti-patterns are empirical** — You cannot predict which instructions will cause friction until the skill runs against real conditions. The skill must capture these discoveries.
3. **Scripts and references go stale** — A bundled script that worked last month may fail today due to upstream changes. Only execution reveals staleness.
4. **Patterns emerge from repetition** — When a workaround appears across multiple executions, it should be promoted to a recommended pattern in the skill itself.

---

## The Reflection Section

Every skill with stepwise execution must include this section in its SKILL.md. The section triggers at the **end** of every invocation — after Verify, before Cleanup.

### Canonical Template

All skills use this exact template. No bespoke variants — the principles are universal.

```markdown
## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path (Glob for this skill's name) before editing. All corrections target THIS file and its sibling references/ — never other documentation.
1. **What failed?** — Fix the instruction that caused it. If it could recur, add it as an anti-pattern.
2. **What worked better than expected?** — Promote it to recommended practice. Document why.
3. **What drifted?** — Any script, reference, or external dependency that no longer matches reality gets fixed now.
4. **Log it.** — Every change gets an evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
```

**Why one template, not bespoke versions**: Domain-specific reflection sections become stale the moment the domain shifts. Principle-based reflection adapts to whatever the execution actually encounters — the principles guide the agent to the right action without prescribing domain details that drift.

### Extended Template (DEPRECATED — use canonical template above)

Previously, complex skills used an extended form. This is no longer recommended — the canonical template's principles cover all cases. Retained for reference only:

```markdown
## Post-Execution Reflection

After this skill completes, reflect before closing the task:

### Error Review

- Did any step fail? Update the step's instructions with the failure mode and recovery.
- Did any step require a manual workaround? Encode the workaround into the instructions.
- Were any steps skipped as unnecessary? Consider removing or making conditional.

### Pattern Discovery

- Did a better approach emerge during execution? Promote it to the recommended approach.
- Did any instruction produce consistently good results despite seeming risky? Document WHY it works — this is a validated pattern.
- Document new patterns in a `## Recommended Patterns` section or in `references/`.

### Anti-Pattern Discovery

- Did any instruction cause recurring friction? Document the specific error and the fix.
- Did any assumption prove wrong? (e.g., "tool X is always installed" — it wasn't)
- Document new anti-patterns in a `## Anti-Patterns` section or in `references/`.

### Artifact Rectification

- **SKILL.md**: Update instructions that were wrong, unclear, or incomplete.
- **scripts/**: Fix any script that produced incorrect output or failed on edge cases.
- **references/**: Update any reference that was outdated, misleading, or incomplete.
- **evolution-log.md**: Log every change with trigger, fix, and evidence.

Do NOT skip this section. Do NOT defer fixes to "next time."
```

---

## Phased Execution Integration

The reflection phase sits between Verify and Cleanup in the standard execution model:

```
Phase 0: Preflight  — verify prerequisites
Phase 1: Execute    — perform core operation
Phase 2: Verify     — confirm outcomes
Phase 3: Reflect    — review execution, identify patterns/anti-patterns
Phase 3b: Rectify   — fix skill artifacts based on findings
Phase 4: Cleanup    — remove temporary artifacts
```

Use `[Reflect]` and `[Rectify]` labels in task templates:

```
7. [Verify] Health check passes
8. [Reflect] Review execution: any steps failed or needed workarounds?
9. [Reflect] Identify empirical patterns and anti-patterns
10. [Rectify] Update SKILL.md instructions with findings
11. [Rectify] Fix scripts/references that produced incorrect results
12. [Rectify] Log changes in evolution-log.md
13. [Cleanup] Remove temporary build artifacts
```

---

## What Gets Rectified

| Artifact         | What to check                                              | How to fix                                       |
| ---------------- | ---------------------------------------------------------- | ------------------------------------------------ |
| SKILL.md         | Instructions that were wrong, unclear, or incomplete       | Rewrite the specific step                        |
| scripts/         | Scripts that failed, produced wrong output, or had errors  | Fix the script code                              |
| references/      | References that were outdated, misleading, or missing info | Update or remove the reference                   |
| evolution-log.md | Missing entries for changes made                           | Add entry with trigger, change, evidence         |
| Anti-patterns    | Friction points not yet documented                         | Add to Anti-Patterns section or reference file   |
| Patterns         | Successful approaches not yet documented                   | Add to Recommended Patterns section or reference |

---

## Validation Requirements

The skill validator should check that skills with stepwise execution include a Post-Execution Reflection section. Detection heuristics:

1. **Section header present**: SKILL.md contains `## Post-Execution Reflection` (or close variant like `## Post-Execution Review`)
2. **Reflection triggers present**: The section contains references to error review, pattern/anti-pattern discovery, or artifact rectification
3. **Evolution log reference**: The section references `evolution-log.md`

### Validator Check (for `validate-skill.ts`)

```
CHECK: post-execution-reflection
SEVERITY: warning (skills without stepwise execution are exempt)
CONDITION: SKILL.md contains task templates with [Execute] labels
           AND does NOT contain "Post-Execution Reflection" section header
MESSAGE: "Skill performs stepwise execution but lacks Post-Execution Reflection section.
          Add one following the template in post-execution-reflection.md."
```

Skills that are purely reference (no side effects, no stepwise execution) are exempt. The validator should only flag skills that have task templates with `[Execute]` labels.

---

## Examples of Empirical Findings

These are the kinds of discoveries that the reflection phase captures:

### Pattern Example

> **Trigger**: During kokoro-tts:install, discovered that checking `sherpa-onnx` version via `python -c "import sherpa_onnx"` is unreliable because the import succeeds even with a broken installation.
>
> **Pattern**: Use `sherpa-onnx --help 2>&1 | head -1` to check the CLI binary directly. This catches broken installations that the Python import misses.
>
> **Rectification**: Updated step 5 in the install template from Python import check to CLI binary check.

### Anti-Pattern Example

> **Trigger**: During itp:go, the preflight step checked for `mise` availability but not for the specific mise task the skill needed. Execution failed at step 4 because `mise run check-full` wasn't defined in the project.
>
> **Anti-Pattern**: Checking tool installation without checking task/command availability. Tools being installed doesn't mean the required commands exist.
>
> **Rectification**: Added `[Preflight] Verify mise task exists: mise task ls | grep check-full` to the template.

### Script Fix Example

> **Trigger**: `validate-links.ts` reported false positives for anchor links containing colons (e.g., `#phase-3-reflect--rectify`). The regex treated colons as invalid characters.
>
> **Fix**: Updated the anchor validation regex in `validate-links.ts` to allow colons and ampersands in anchor fragments.
>
> **Evidence**: `Error: Invalid anchor "#phase-3-reflect--rectify" in line 42`

---

## Anti-Patterns for Reflection Itself

| Anti-Pattern                      | Problem                                                  | Fix                                                        |
| --------------------------------- | -------------------------------------------------------- | ---------------------------------------------------------- |
| Reflection without rectification  | Noticing problems but not fixing them ("will fix later") | The section MUST instruct immediate fixes                  |
| Speculative rectification         | Changing instructions based on what MIGHT go wrong       | Only rectify based on observed empirical evidence          |
| Over-rectification                | Rewriting large portions of the skill after one failure  | Fix the specific failure; don't refactor the whole skill   |
| Missing evidence in evolution log | Logging "fixed X" without the error that prompted it     | Always include the actual error/output as evidence         |
| Skipping reflection on success    | Only reflecting when things fail                         | Successful executions also reveal patterns worth capturing |
