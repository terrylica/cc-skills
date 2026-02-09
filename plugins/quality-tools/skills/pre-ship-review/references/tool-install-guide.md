**Skill**: [Pre-Ship Review](../SKILL.md)

# Tool Install Guide

Installation and setup for all external tools used by the pre-ship-review skill. All tools are optional -- the skill degrades gracefully if a tool is not installed.

---

## Quick Install (All Tools)

```bash
/usr/bin/env bash << 'INSTALL_EOF'
# Tier 1: Always Run
pip install pyright vulture import-linter deptry

# Tier 2: Pattern Checks
brew install semgrep
pip install griffe

# Tier 3: Deep Checks (optional)
pip install mutmut
INSTALL_EOF
```

---

## Tool Details

### Pyright (Type Checker)

| Field    | Value                                         |
| -------- | --------------------------------------------- |
| Purpose  | Static type checking with cross-file analysis |
| Install  | `pip install pyright`                         |
| Stars    | 15.2k                                         |
| Requires | Node.js (auto-installed by pyright)           |

**Configuration** (`pyproject.toml`):

```ini
# SSoT-OK: pythonVersion should match your project's pyproject.toml python-requires
[tool.pyright]
pythonVersion = "<your-python-version>"
typeCheckingMode = "strict"
reportReturnType = true
reportArgumentType = true
reportCallIssue = true
```

**Usage**: `pyright --outputjson <files>`

---

### Vulture (Dead Code Detector)

| Field    | Value                                                |
| -------- | ---------------------------------------------------- |
| Purpose  | Find unused functions, variables, imports, constants |
| Install  | `pip install vulture`                                |
| Stars    | 4.3k                                                 |
| Requires | Python only                                          |

**Usage**:

```bash
# Basic scan
vulture <files> --min-confidence 80

# Generate allowlist for framework entry points
vulture . --make-whitelist > whitelist.py

# Scan with allowlist
vulture <files> whitelist.py --min-confidence 80
```

---

### import-linter (Architecture Enforcer)

| Field    | Value                                            |
| -------- | ------------------------------------------------ |
| Purpose  | Enforce architecture boundaries via import rules |
| Install  | `pip install import-linter`                      |
| Stars    | 942                                              |
| Requires | Configuration in `pyproject.toml`                |

**Configuration** (`pyproject.toml`):

```ini
[importlinter]
root_packages = your_core, your_plugins

[importlinter:contract:core-independence]
name = Core does not import plugins
type = forbidden
source_modules = your_core
forbidden_modules = your_plugins

[importlinter:contract:layer-order]
name = Layers are independent
type = independence
modules = your_core, your_plugins
```

**Usage**: `lint-imports`

---

### deptry (Dependency Linter)

| Field    | Value                                             |
| -------- | ------------------------------------------------- |
| Purpose  | Find unused, missing, and transitive dependencies |
| Install  | `pip install deptry`                              |
| Stars    | 1.3k                                              |
| Requires | `pyproject.toml` with dependencies listed         |

**Usage**: `deptry .` (run from package root)

---

### Semgrep (Custom Pattern Rules)

| Field    | Value                                    |
| -------- | ---------------------------------------- |
| Purpose  | Write custom lint rules as code patterns |
| Install  | `brew install semgrep`                   |
| Stars    | 14.1k                                    |
| Requires | `.semgrep/` directory with YAML rules    |

**Setup**:

1. Create `.semgrep/` directory in project root
2. Add YAML rule files (see [Automated Checks Reference](./automated-checks.md) for examples)
3. Run: `semgrep --config .semgrep/ <files>`

**Example rule** (`.semgrep/non-determinism.yaml`):

```yaml
rules:
  - id: random-without-seed
    patterns:
      - pattern-either:
          - pattern: np.random.normal(...)
          - pattern: np.random.uniform(...)
          - pattern: random.random()
    message: "Random operation without explicit seed."
    severity: WARNING
    languages: [python]
```

---

### Griffe (API Change Detector)

| Field    | Value                                        |
| -------- | -------------------------------------------- |
| Purpose  | Detect breaking API changes between git refs |
| Install  | `pip install griffe`                         |
| Stars    | 589                                          |
| Requires | Python package with importable modules       |

**Usage**:

```bash
# Compare current branch against main
griffe check --against main your_package

# Dump current API as JSON
griffe dump your_package --output json
```

---

### mutmut (Mutation Testing) -- Optional

| Field    | Value                                                               |
| -------- | ------------------------------------------------------------------- |
| Purpose  | Verify test quality by mutating code and checking if tests catch it |
| Install  | `pip install mutmut`                                                |
| Stars    | 1.2k                                                                |
| Requires | pytest test suite                                                   |

**Usage**:

```bash
# Run mutation testing on specific files
mutmut run --paths-to-mutate=<changed_files>

# View results
mutmut results

# Inspect a surviving mutant
mutmut show 42
```

**Note**: Mutation testing is slow (minutes, not seconds). Use as an optional deep check, not a blocking gate.

---

## Checking Installation Status

```bash
/usr/bin/env bash << 'CHECK_EOF'
echo "=== Pre-Ship Review Tool Status ==="
for tool in pyright vulture lint-imports deptry semgrep griffe mutmut; do
  if command -v "$tool" &>/dev/null; then
    echo "  [OK] $tool"
  else
    echo "  [--] $tool (not installed)"
  fi
done
CHECK_EOF
```
