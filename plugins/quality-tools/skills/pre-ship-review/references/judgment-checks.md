**Skill**: [Pre-Ship Review](../SKILL.md)

# Judgment Checks Reference

Detailed procedures for Phase 3 human-judgment checks. These require understanding intent, domain correctness, and architectural fitness -- they cannot be fully automated.

---

## Check 1: Architecture Boundaries

**Anti-pattern**: Core code references capability-specific names, creating coupling that violates architectural separation.

**How to check**:

1. Search for hardcoded lists of feature/plugin/module names in core code:

   ```
   Look for: sets, lists, or dicts containing specific plugin/feature names
   Example violation: RISK_PLUGINS = {"var_historical", "sortino_ratio", ...}
   ```

2. Apply the "add another" test:
   - Would adding a new feature/plugin of this type require modifying core code?
   - If yes, the boundary is violated.

3. Check for imports flowing in the wrong direction:
   - Core should never import from capabilities/plugins
   - Capabilities may import from core (dependency flows inward)

**Fix approach**: Replace hardcoded names with:

- Registry lookups
- Configuration/metadata on the plugins themselves
- Convention-based discovery (tags, naming patterns)

---

## Check 2: Domain Correctness

**Anti-pattern**: Constants, formulas, or domain-specific values are mathematically incorrect or mislabeled.

**How to check**:

1. For each new constant or formula, verify against the cited source:
   - Is the paper/textbook cited? If not, find the authoritative source.
   - Does the implementation match the formula exactly?
   - Are the units correct? (Annual vs daily, percent vs decimal)

2. Check label-value alignment:
   - A constant named `LAMBDA_DAILY` should contain the daily-frequency value
   - A constant named `RISK_FREE_RATE` should be in the expected units (daily/annual)

3. Common domain traps:
   - Annualization factors: `sqrt(252)` for daily returns, `sqrt(12)` for monthly
   - Frequency scaling: Power-law rules like Ravn-Uhlig (lambda \* ratio^4)
   - Confidence levels: 95% VaR vs 97.5% CVaR (Basel III)

**Fix approach**: Add inline comments citing the source and showing the calculation.

---

## Check 3: Test Quality

**Anti-pattern**: Tests test side-effects of the target function rather than the function itself.

**How to check**:

1. For each test, verify the call chain:
   - Does `test_alpha_plugin` actually call the `alpha` function directly?
   - Or does it call `beta` which internally computes alpha as a side-effect?

2. Apply the "break it" test:
   - If you introduce a bug in the target function, does THIS test fail?
   - If the bug only fails a different test, the test is indirect.

3. Check assertion quality:
   - Are assertions specific? (`assert result["col"] == expected_value`)
   - Or vague? (`assert len(result) > 0`, `assert result is not None`)

4. Check edge case coverage:
   - Empty input / no data
   - NaN values / missing data
   - Single element / minimum viable input
   - Boundary values (exact thresholds)

**Fix approach**: Each test should:

- Call the target function directly
- Assert on the specific output of that function
- Cover at least one happy path and one edge case

---

## Check 4: Dependency Transparency

**Anti-pattern**: Component A requires component B to run first, but this dependency is undocumented and only discoverable at runtime.

**How to check**:

1. For each new component, trace its required inputs:
   - What columns/data does it expect to exist?
   - Where are those columns created?
   - Is the creator always run before this component?

2. Check for "magic columns" -- columns that appear without explicit creation:
   - A function expects `market.return` column but doesn't document where it comes from
   - A plugin reads `eval.beta` column that only exists after another plugin runs

3. Verify that error messages for missing dependencies are actionable:
   - BAD: `KeyError: 'market.return'`
   - GOOD: `"market.return column not found. Run eval.beta first or provide market_col parameter."`

**Fix approach**:

- Document dependencies in function docstrings and decorator metadata
- Add actionable error messages when dependencies are missing
- Consider auto-creating missing dependencies when possible

---

## Check 5: Performance

**Anti-pattern**: O(n^2) or worse algorithmic complexity when O(n) is possible.

**How to check**:

1. Look for nested loops over the same data:

   ```python
   # O(n^2) - expanding window pattern
   for i in range(len(data)):
       window = data[:i+1]  # Growing window
       result[i] = some_computation(window)
   ```

2. Look for per-element operations on arrays:

   ```python
   # O(n) per element = O(n^2) total
   for i in range(len(data)):
       result[i] = np.linalg.lstsq(X[:i+1], y[:i+1])  # Full solve each step
   ```

3. Check for opportunities to vectorize:
   - Loop over rows -> pandas/numpy vectorized operation
   - Repeated computation -> cache/memoize
   - Expanding window -> rolling window or single full-sample computation

**Fix approach**: Replace with:

- Single full-sample computation (when mathematically equivalent)
- Rolling window operations (`pandas.rolling`, `numpy.convolve`)
- Vectorized operations (`numpy` broadcasting, `pandas.apply`)

---

## Check 6: Error Message Quality

**Anti-pattern**: Error messages describe what went wrong but not what to do about it.

**How to check**:

For each `raise` statement or error log in new code, ask:

1. Does the message tell the user what **action** to take?
   - BAD: `"Column 'x' not found"`
   - GOOD: `"Column 'x' not found in panel. Ensure data plugin outputs this column, or specify an alternative via the column_x parameter."`

2. Does it reference the specific value that failed?
   - BAD: `"Invalid parameter"`
   - GOOD: `"Parameter 'window' must be positive, got -5"`

3. Does it provide context for debugging?
   - BAD: `"Insufficient data"`
   - GOOD: `"Symbol BTCUSDT has 15 observations, minimum required is 30 for beta calculation"`

**Fix approach**: Every error message should answer: "What should I do now?"

---

## Check 7: Example Accuracy

**Anti-pattern**: Examples/documentation show parameters or behavior that the code silently ignores.

**How to check**:

1. For each example file (YAML, JSON, config, README code blocks):
   - List every parameter name used
   - Verify each parameter exists in the target function's signature
   - Check it's NOT absorbed by `**kwargs` or `**_` without effect

2. For each parameter shown in examples:
   - Does changing the value actually change the output?
   - If the function ignores it, the example is misleading

3. Common traps:
   - `window: 252` passed but function uses all available data
   - `periods_per_year: 365` passed but function hardcodes 252
   - `annualize: true` passed but function doesn't have this parameter

**Fix approach**:

- Remove parameters from examples that the code doesn't use
- OR implement the parameter in the code
- Never leave aspirational parameters in examples
