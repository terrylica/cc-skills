---
name: dead-code-detector
description: Detect unused/unreachable code in polyglot codebases (Python, TypeScript, Rust). TRIGGERS - dead code, unused functions, unused imports, unreachable code.
allowed-tools: Read, Grep, Bash, Edit, Write
---

# Dead Code Detector

Find and remove unused code across Python, TypeScript, and Rust codebases.

## Tools by Language

| Language   | Tool                                                      | Detects                                       |
| ---------- | --------------------------------------------------------- | --------------------------------------------- |
| Python     | [vulture](https://github.com/jendrikseipp/vulture) v2.14+ | Unused imports, functions, classes, variables |
| TypeScript | [knip](https://knip.dev/) v5.0+                           | Unused exports, dependencies, files           |
| Rust       | `cargo clippy` + `rustc` lints                            | Unused functions, imports, dead_code warnings |

**Why these tools?**

- **vulture**: AST-based, confidence scoring (60-100%), whitelist support
- **knip**: Successor to ts-prune (maintenance mode), monorepo-aware, auto-fix
- **cargo clippy**: Built-in to Rust toolchain, zero additional deps

---

## When to Use This Skill

Use this skill when:

- Cleaning up a codebase before release
- Refactoring to reduce maintenance burden
- Investigating bundle size / compile time issues
- Onboarding to understand what code is actually used

**NOT for**: Code duplication (use `quality-tools:code-clone-assistant`)

---

## Quick Start Workflow

### Python (vulture)

```bash
# Step 1: Install
uv pip install vulture

# Step 2: Scan with 80% confidence threshold
vulture src/ --min-confidence 80

# Step 3: Generate whitelist for false positives
vulture src/ --make-whitelist > vulture_whitelist.py

# Step 4: Re-scan with whitelist
vulture src/ vulture_whitelist.py --min-confidence 80
```

### TypeScript (knip)

```bash
# Step 1: Install (project-local recommended)
bun add -d knip

# Step 2: Initialize config
bunx knip --init

# Step 3: Scan for dead code
bunx knip

# Step 4: Auto-fix (removes unused exports)
bunx knip --fix
```

### Rust (cargo clippy)

```bash
# Step 1: Scan for dead code warnings
cargo clippy -- -W dead_code -W unused_imports -W unused_variables

# Step 2: For stricter enforcement
cargo clippy -- -D dead_code  # Deny (error) instead of warn

# Step 3: Auto-fix what's possible
cargo clippy --fix --allow-dirty
```

---

## Confidence and False Positives

### Python (vulture)

| Confidence | Meaning                                     | Action                          |
| ---------- | ------------------------------------------- | ------------------------------- |
| 100%       | Guaranteed unused in analyzed files         | Safe to remove                  |
| 80-99%     | Very likely unused                          | Review before removing          |
| 60-79%     | Possibly unused (dynamic calls, frameworks) | Add to whitelist if intentional |

**Common false positives**:

- Django/Flask view functions (called by framework)
- pytest fixtures (implicitly used)
- `__all__` exports
- Celery tasks

### TypeScript (knip)

Knip uses TypeScript's type system for accuracy. Configure in `knip.json`:

```json
{
  "entry": ["src/index.ts"],
  "project": ["src/**/*.ts"],
  "ignore": ["**/*.test.ts"],
  "ignoreDependencies": ["@types/*"]
}
```

### Rust

Suppress false positives with attributes:

```rust
#[allow(dead_code)]  // Single item
fn intentionally_unused() {}

// Or module-wide
#![allow(dead_code)]
```

---

## Integration with CI

### Python (pyproject.toml)

```toml
[tool.vulture]
min_confidence = 80
paths = ["src"]
exclude = ["*_test.py", "conftest.py"]
```

### TypeScript (package.json)

```json
{
  "scripts": {
    "dead-code": "knip",
    "dead-code:fix": "knip --fix"
  }
}
```

### Rust (Cargo.toml)

```toml
[lints.rust]
dead_code = "warn"
unused_imports = "warn"
```

---

## Reference Documentation

For detailed information, see:

- [Python Workflow](./references/python-workflow.md) - vulture advanced usage
- [TypeScript Workflow](./references/typescript-workflow.md) - knip configuration
- [Rust Workflow](./references/rust-workflow.md) - clippy lint categories

---

## Troubleshooting

| Issue                         | Cause                     | Solution                                                           |
| ----------------------------- | ------------------------- | ------------------------------------------------------------------ |
| vulture reports Django views  | Framework magic           | Add to whitelist: `vulture --make-whitelist`                       |
| knip misses dynamic imports   | Not in entry points       | Add to `entry` array in knip.json                                  |
| Rust warns about test helpers | Tests compiled separately | Use `#[cfg(test)]` module with `#[allow(...)]`                     |
| Too many false positives      | Threshold too low         | Increase `--min-confidence` (vulture) or configure ignore patterns |
| Missing type exports (TS)     | Type-only exports         | knip handles these automatically since v5                          |

---

## Multi-Perspective Validation (Critical)

**IMPORTANT**: Before removing any detected "dead code", spawn parallel subagents to validate findings from multiple perspectives. Dead code may actually be **unimplemented features** or **incomplete integrations**.

### Classification Matrix

| Finding Type    | True Dead Code                | Unimplemented Feature               | Incomplete Integration    |
| --------------- | ----------------------------- | ----------------------------------- | ------------------------- |
| Unused function | No callers, no tests, no docs | Has TODO/FIXME, referenced in specs | Partial call chain exists |
| Unused export   | Not imported anywhere         | In public API, documented           | Used in sibling package   |
| Unused import   | Typo, refactored away         | Needed for side effects             | Type-only usage           |
| Unused variable | Assigned but never read       | Placeholder for future              | Debug/logging removed     |

### Validation Workflow

After running detection tools, **spawn these parallel subagents**:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Dead Code Findings                           │
└─────────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ Intent Agent    │ │ Integration     │ │ History Agent   │
│                 │ │ Agent           │ │                 │
│ - Check TODOs   │ │ - Trace call    │ │ - Git blame     │
│ - Search specs  │ │   chains        │ │ - Commit msgs   │
│ - Find issues   │ │ - Check exports │ │ - PR context    │
│ - Read ADRs     │ │ - Test coverage │ │ - Author intent │
└─────────────────┘ └─────────────────┘ └─────────────────┘
          │                   │                   │
          └───────────────────┼───────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              AskUserQuestion: Confirm Classification            │
│  [ ] True dead code - safe to remove                            │
│  [ ] Unimplemented - create GitHub Issue to track               │
│  [ ] Incomplete - investigate integration gaps                  │
│  [ ] False positive - add to whitelist                          │
└─────────────────────────────────────────────────────────────────┘
```

### Agent Prompts

**Intent Agent** (searches for planned usage):

```
Search for references to [SYMBOL] in:
1. TODO/FIXME comments in codebase
2. GitHub Issues (open and closed)
3. ADRs and design docs
4. README and CLAUDE.md files
Report: Was this code planned but not yet integrated?
```

**Integration Agent** (traces execution paths):

```
For [SYMBOL], analyze:
1. All import/require statements
2. Dynamic imports (importlib, require.resolve)
3. Framework magic (decorators, annotations, config)
4. Test files that may exercise this code
Report: Is there a partial or indirect call chain?
```

**History Agent** (investigates provenance):

```
For [SYMBOL], check:
1. git blame - who wrote it and when
2. Commit message - what was the intent
3. PR description - was it part of larger feature
4. Recent commits - was calling code removed
Report: Was this intentionally orphaned or accidentally broken?
```

### Example: Validating Python Findings

```bash
# Step 1: Run vulture
vulture src/ --min-confidence 80 > findings.txt

# Step 2: For each high-confidence finding, spawn validation
# (Claude Code will use Task tool with Explore agents)
```

**Sample finding**: `unused function 'calculate_metrics' (src/analytics.py:45)`

**Multi-agent investigation results**:

- Intent Agent: "Found TODO in src/dashboard.py:12 - 'integrate calculate_metrics here'"
- Integration Agent: "Function is imported in tests/test_analytics.py but test is skipped"
- History Agent: "Added in PR #234 'Add analytics foundation' - dashboard integration deferred"

**Conclusion**: NOT dead code - it's an **unimplemented feature**. Create tracking issue.

### User Confirmation Flow

After agent analysis, use `AskUserQuestion` with `multiSelect: true`:

```typescript
AskUserQuestion({
  questions: [
    {
      question: "How should we handle these findings?",
      header: "Action",
      multiSelect: true,
      options: [
        {
          label: "Remove confirmed dead code",
          description: "Delete items verified as truly unused",
        },
        {
          label: "Create issues for unimplemented",
          description: "Track planned features in GitHub Issues",
        },
        {
          label: "Investigate incomplete integrations",
          description: "Spawn deeper analysis for partial implementations",
        },
        {
          label: "Update whitelist",
          description: "Add false positives to tool whitelist",
        },
      ],
    },
  ],
});
```

### Risk Classification

| Risk Level   | Criteria                                               | Action                     |
| ------------ | ------------------------------------------------------ | -------------------------- |
| **Low**      | 100% confidence, no references anywhere, >6 months old | Auto-remove with commit    |
| **Medium**   | 80-99% confidence, some indirect references            | Validate with agents first |
| **High**     | <80% confidence, recent code, has tests                | Manual review required     |
| **Critical** | Public API, documented, has dependents                 | NEVER auto-remove          |

---

## Sources

- [vulture GitHub](https://github.com/jendrikseipp/vulture)
- [knip documentation](https://knip.dev/)
- [Effective TypeScript: Use knip](https://effectivetypescript.com/2023/07/29/knip/)
- [Rust dead_code lint](https://doc.rust-lang.org/rust-by-example/attribute/unused.html)
- [DCE-LLM research paper](https://aclanthology.org/2025.naacl-long.501.pdf) (emerging LLM-based approach)
