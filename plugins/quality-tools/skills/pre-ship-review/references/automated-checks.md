**Skill**: [Pre-Ship Review](../SKILL.md)

# Automated Checks Reference

Detailed procedures for Phase 1 external tool checks. Each check runs independently and can be parallelized.

---

## Scope Detection

Before running any check, determine the changed files:

```bash
/usr/bin/env bash << 'SCOPE_EOF'
# Detect base branch (main or master)
BASE=$(git rev-parse --verify main 2>/dev/null && echo main || echo master)

# Get changed files relative to base
CHANGED=$(git diff --name-only "$(git merge-base HEAD "$BASE")...HEAD")

# Filter by language
PY_FILES=$(echo "$CHANGED" | grep '\.py$' || true)
YAML_FILES=$(echo "$CHANGED" | grep -E '\.(ya?ml)$' || true)
MD_FILES=$(echo "$CHANGED" | grep '\.md$' || true)

echo "Changed Python files: $(echo "$PY_FILES" | wc -l | tr -d ' ')"
echo "Changed YAML files: $(echo "$YAML_FILES" | wc -l | tr -d ' ')"
echo "Changed Markdown files: $(echo "$MD_FILES" | wc -l | tr -d ' ')"
SCOPE_EOF
```

---

## Check 1: Pyright Strict Mode

**Anti-patterns caught**: Interface contract violations (#1), return type mismatches (#1)

**What to run**:

```bash
/usr/bin/env bash << 'PYRIGHT_EOF'
if ! command -v pyright &>/dev/null; then
  echo "SKIP: pyright not installed (pip install pyright)"
  exit 0
fi

# Run on changed Python files only
pyright --outputjson --pythonversion 3.13 $PY_FILES 2>/dev/null | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
diags = data.get('generalDiagnostics', [])
errors = [d for d in diags if d['severity'] == 'error']
print(f'Pyright: {len(errors)} errors, {len(diags) - len(errors)} warnings')
for e in errors:
    print(f\"  {e['file']}:{e['range']['start']['line']}: {e['message']}\")
"
PYRIGHT_EOF
```

**Key diagnostics to watch for**:

| Diagnostic                   | What it means                                    |
| ---------------------------- | ------------------------------------------------ |
| `reportReturnType`           | Function return type doesn't match declared type |
| `reportArgumentType`         | Caller passes wrong type to parameter            |
| `reportCallIssue`            | Function called with wrong number of args        |
| `reportMissingParameterType` | Parameter lacks type annotation                  |
| `reportUnusedImport`         | Import not used in file                          |

---

## Check 2: Vulture (Dead Code / YAGNI)

**Anti-patterns caught**: YAGNI (#7), unused constants/imports

**What to run**:

```bash
/usr/bin/env bash << 'VULTURE_EOF'
if ! command -v vulture &>/dev/null; then
  echo "SKIP: vulture not installed (pip install vulture)"
  exit 0
fi

# Run on changed files with confidence threshold
vulture $PY_FILES --min-confidence 80

# To generate an allowlist for framework entry points:
# vulture . --make-whitelist > whitelist.py
# vulture $PY_FILES whitelist.py --min-confidence 80
VULTURE_EOF
```

**Common false positives and how to handle**:

| False Positive      | Why                                         | Solution                                    |
| ------------------- | ------------------------------------------- | ------------------------------------------- |
| Plugin entry points | Discovered via framework, not direct import | Add to allowlist                            |
| Abstract methods    | Called dynamically via dispatch             | Add to allowlist                            |
| `__all__` exports   | Used by external consumers                  | Add to allowlist                            |
| Test fixtures       | Used by pytest, not direct call             | Vulture handles `conftest.py` automatically |

---

## Check 3: import-linter (Architecture Boundaries)

**Anti-patterns caught**: Architecture boundary violations (#3)

**What to run**:

```bash
/usr/bin/env bash << 'IMPORTLINT_EOF'
if ! command -v lint-imports &>/dev/null; then
  echo "SKIP: import-linter not installed (pip install import-linter)"
  exit 0
fi

lint-imports
IMPORTLINT_EOF
```

**Configuration** (in `pyproject.toml`):

```ini
[importlinter]
root_packages = your_core_package, your_capability_package

[importlinter:contract:core-independence]
name = Core does not import capabilities
type = forbidden
source_modules = your_core_package
forbidden_modules = your_capability_package

[importlinter:contract:no-circular]
name = No circular imports between packages
type = independence
modules =
    your_core_package
    your_capability_package
```

---

## Check 4: deptry (Dependency Hygiene)

**Anti-patterns caught**: Unused dependencies, missing dependencies, transitive dependency usage

**What to run**:

```bash
/usr/bin/env bash << 'DEPTRY_EOF'
if ! command -v deptry &>/dev/null; then
  echo "SKIP: deptry not installed (pip install deptry)"
  exit 0
fi

# Run per package directory (if monorepo)
for pkg_dir in packages/*/; do
  if [ -f "$pkg_dir/pyproject.toml" ]; then
    echo "Checking $pkg_dir..."
    cd "$pkg_dir" && deptry . && cd - > /dev/null
  fi
done
DEPTRY_EOF
```

---

## Check 5: Semgrep (Custom Pattern Rules)

**Anti-patterns caught**: Non-determinism (#6), misleading examples (#2), silent param absorption

Semgrep lets you define project-specific rules. Create a `.semgrep/` directory with YAML rules.

**Example rules**:

```yaml
# .semgrep/non-determinism.yaml
rules:
  - id: random-without-seed
    patterns:
      - pattern-either:
          - pattern: np.random.normal(...)
          - pattern: np.random.uniform(...)
          - pattern: np.random.randn(...)
          - pattern: random.random()
          - pattern: random.choice(...)
    message: "Random operation without explicit seed. Use np.random.default_rng(seed) for reproducibility."
    severity: WARNING
    languages: [python]

  - id: torch-random-without-seed
    pattern: torch.rand(...)
    message: "PyTorch random without manual_seed. Use torch.manual_seed(seed) for reproducibility."
    severity: WARNING
    languages: [python]
```

```yaml
# .semgrep/kwargs-absorption.yaml
rules:
  - id: kwargs-star-underscore
    pattern: |
      def $FUNC(..., **_, ...):
          ...
    message: "Function uses **_ catch-all. Verify all callers pass correct parameter names -- misnamed params are silently absorbed."
    severity: INFO
    languages: [python]
```

**What to run**:

```bash
/usr/bin/env bash << 'SEMGREP_EOF'
if ! command -v semgrep &>/dev/null; then
  echo "SKIP: semgrep not installed (brew install semgrep)"
  exit 0
fi

# Run with project rules on changed files
if [ -d ".semgrep" ]; then
  semgrep --config .semgrep/ --include="*.py" $PY_FILES --json 2>/dev/null | \
    python3 -c "
import json, sys
data = json.load(sys.stdin)
results = data.get('results', [])
print(f'Semgrep: {len(results)} findings')
for r in results:
    print(f\"  {r['path']}:{r['start']['line']}: [{r['check_id']}] {r['extra']['message']}\")
"
else
  echo "SKIP: No .semgrep/ directory found (create project-specific rules)"
fi
SEMGREP_EOF
```

---

## Check 6: Griffe (API Signature Drift)

**Anti-patterns caught**: Interface contract violations (#1), breaking changes

**What to run**:

```bash
/usr/bin/env bash << 'GRIFFE_EOF'
if ! python3 -c "import griffe" 2>/dev/null; then
  echo "SKIP: griffe not installed (pip install griffe)"
  exit 0
fi

BASE=$(git rev-parse --verify main 2>/dev/null && echo main || echo master)

# Check for breaking API changes vs base branch
griffe check --against "$BASE" your_package_name 2>&1 || true
GRIFFE_EOF
```

**What Griffe detects**:

| Change Type          | Example                       | Severity     |
| -------------------- | ----------------------------- | ------------ |
| Parameter removed    | `def f(a, b)` -> `def f(a)`   | Breaking     |
| Parameter renamed    | `column1` -> `column_x`       | Breaking     |
| Return type changed  | `-> dict` -> `-> DataFrame`   | Breaking     |
| Required param added | `def f(a)` -> `def f(a, b)`   | Breaking     |
| Optional param added | `def f(a)` -> `def f(a, b=1)` | Non-breaking |

---

## Interpreting Results

**Severity classification**:

| Severity     | Action              | Example                                              |
| ------------ | ------------------- | ---------------------------------------------------- |
| **Critical** | Fix before shipping | Return type mismatch, missing required param         |
| **High**     | Fix before shipping | Architecture boundary violation, breaking API change |
| **Medium**   | Fix or document     | Dead code, non-determinism, YAGNI constant           |
| **Low**      | Consider fixing     | Unused import, informational Semgrep finding         |

**When to override a finding**:

- Vulture reports plugin entry points as unused -> Add to allowlist
- Griffe reports intentional breaking change -> Document in changelog
- Semgrep `**_` warning on a framework convention -> Add `# nosemgrep` comment
- import-linter violation for legitimate cross-cutting concern -> Update contract
