**Skill**: [Pre-Ship Review](../SKILL.md)

# Anti-Pattern Catalog

Taxonomy of 9 integration boundary anti-patterns. Each entry includes the pattern, detection heuristic, fix approach, and a generalized example.

> **Origin**: Derived from analysis of 15 real review issues, then generalized to be project-agnostic.

---

## 1. Interface Contract Violation

**Pattern**: Parameter names differ between caller and callee. The function expects `column_x` but the caller passes `column1`. With `**kwargs` or `**_`, this fails silently.

**Detection**:

- Pyright strict mode (catches type-level mismatches)
- Griffe (catches signature drift between branches)
- Manual: trace every parameter from caller to callee

**Fix**: Rename parameters to match. If renaming, update ALL callers and examples simultaneously.

**Example**:

```python
# Caller (config/DSL)
params: { column_x: "price.close", column_y: "price.open" }

# Callee (WRONG - different names)
def my_function(*, column1: str, column2: str, **_): ...

# Callee (CORRECT - matching names)
def my_function(*, column_x: str, column_y: str, **_): ...
```

---

## 2. Misleading Examples

**Pattern**: Examples show parameters that the code silently ignores. Users expect the parameter to have an effect, but it's absorbed by `**kwargs`/`**_`.

**Detection**:

- Semgrep custom rule for `**_` catch-all functions
- Manual: for each example parameter, verify it appears in the function signature as a named kwarg

**Fix**: Remove parameters from examples that code doesn't use, OR implement them.

**Example**:

```yaml
# Example shows window parameter
- using: var_historical
  params:
    window: 252 # <- Code ignores this, uses all data
    confidence: 0.95 # <- This one actually works
```

---

## 3. Architecture Boundary Violation

**Pattern**: Core/framework code contains hardcoded references to specific plugin/feature names, breaking the separation between generic infrastructure and specific implementations.

**Detection**:

- import-linter (catches forbidden imports)
- Manual: search for hardcoded sets/lists of feature names in core code

**Fix**: Use registry lookups, metadata tags, or convention-based discovery instead of hardcoded names.

**Example**:

```python
# WRONG - core code knows about specific plugins
RISK_PLUGINS = {"var_historical", "sortino_ratio", "beta"}
if plugin_name in RISK_PLUGINS:
    dependencies = get_risk_deps()

# CORRECT - core code uses generic logic
if has_model_nodes(dag):
    dependencies = get_model_deps()
else:
    dependencies = get_risk_deps()
```

---

## 4. Incorrect Domain Constants

**Pattern**: Constants have wrong values or are mislabeled. A constant named `LAMBDA_DAILY` contains the quarterly value. A frequency-scaled constant uses the wrong scaling rule.

**Detection**:

- Semgrep (flag constants with specific naming patterns for manual review)
- Manual: cross-reference values with cited academic sources

**Fix**: Correct the value and add an inline comment citing the source and showing the derivation.

**Example**:

```python
# WRONG - labeled "daily" but contains quarterly value
HP_LAMBDA_DAILY = 1600  # This is the quarterly value!

# CORRECT - properly scaled with citation
HP_LAMBDA_DAILY = 129_600  # Ravn-Uhlig (2002): 1600 * 3^4 (monthly scaling)
```

---

## 5. Testing Gaps

**Pattern**: Tests test a side-effect of the target function rather than the function itself. If the target function breaks, the test may still pass because it's actually validating a different code path.

**Detection**:

- mutmut (mutation testing reveals weak assertions)
- Manual: trace each test's call chain to verify it reaches the target

**Fix**: Call the target function directly and assert on its specific output.

**Example**:

```python
# WRONG - tests alpha by running beta (alpha is a side-effect)
def test_alpha_plugin():
    result = beta_plugin(panel)  # beta internally computes alpha too
    assert "eval.alpha" in result.columns  # Passes, but doesn't test standalone alpha

# CORRECT - tests alpha directly
def test_alpha_plugin():
    result = alpha_plugin(panel, beta_col="eval.beta")
    assert "eval.alpha_jensen" in result.columns
```

---

## 6. Non-Determinism

**Pattern**: Random operations without explicit seeds make results non-reproducible across runs.

**Detection**:

- Semgrep custom rule for `random.*()`, `np.random.*()`, `torch.rand*()`
- Manual: search for random operations and verify seed parameter exists

**Fix**: Add a `seed` parameter. Use `np.random.default_rng(seed)` instead of module-level random state.

**Example**:

```python
# WRONG - non-reproducible
particles = np.random.normal(0, 1, size=(n_particles,))

# CORRECT - reproducible when seed is provided
rng = np.random.default_rng(seed)
particles = rng.normal(0, 1, size=(n_particles,))
```

---

## 7. YAGNI (You Aren't Gonna Need It)

**Pattern**: Constants, interfaces, or infrastructure defined for features that don't exist yet. This adds maintenance burden and confusion without current value.

**Detection**:

- Vulture (finds unused constants and functions)
- dead-code-detector (polyglot dead code detection)
- Manual: for each new constant/interface, verify at least one concrete usage exists

**Fix**: Remove unused definitions. Add them when the feature is actually implemented.

**Example**:

```python
# WRONG - constants for features that don't exist
UKF_ALPHA = 1e-3        # No Unscented Kalman Filter plugin exists
UKF_BETA = 2.0          # No Unscented Kalman Filter plugin exists
FF3_SMB_COL = "smb"     # No Fama-French 3-Factor plugin exists

# CORRECT - only define what's used
BETA_MIN_OBSERVATIONS = 30  # Used by eval.beta plugin
```

---

## 8. Hidden Dependencies

**Pattern**: Component A requires component B to run first, but this is only discoverable at runtime when A crashes with a confusing error.

**Detection**:

- Manual: trace required inputs for each component and verify their origin
- Check error messages for missing dependencies

**Fix**: Document dependencies explicitly. Add actionable error messages when dependencies are missing.

**Example**:

```python
# WRONG - crashes with KeyError when market.return doesn't exist
alpha = panel[return_col] - (risk_free + panel["market.return"] * excess)

# CORRECT - actionable error message
if market_col not in panel.columns:
    raise ValueError(
        f"Column '{market_col}' not found. "
        "Run eval.beta first (creates market.return), "
        "or provide an explicit market_col parameter."
    )
```

---

## 9. Performance Anti-Patterns

**Pattern**: O(n^2) or worse complexity when O(n) is achievable. Common in expanding-window operations and per-element matrix solves.

**Detection**:

- Manual: look for nested loops, expanding windows, per-element `lstsq`/`solve` calls

**Fix**: Replace with single full-sample computation, rolling windows, or vectorized operations.

**Example**:

```python
# WRONG - O(n^2) expanding window OLS
for i in range(min_obs, len(y)):
    X_window = X[:i+1]
    y_window = y[:i+1]
    beta, _, _, _ = np.linalg.lstsq(X_window, y_window)
    result[i] = X[i] @ beta

# CORRECT - O(n) single full-sample OLS
beta, _, _, _ = np.linalg.lstsq(X, y)
result = X @ beta
```
