# Module Boundary Design

Principles for deciding where to draw module boundaries. The core insight: boundaries should optimize for _change locality_ (most changes stay within one module), not for _technical similarity_ (all controllers together, all models together).

---

## §1. Package by Feature, Not Layer

Vertical (feature) slicing keeps feature changes local. Horizontal (layer) slicing forces every feature change to touch every directory.

```
# WRONG: horizontal slicing — adding "notifications" touches every directory
src/controllers/user.ts
src/controllers/billing.ts
src/controllers/notification.ts   ← new
src/services/user.ts
src/services/billing.ts
src/services/notification.ts      ← new
src/models/user.ts
src/models/billing.ts
src/models/notification.ts        ← new

# RIGHT: vertical slicing — adding "notifications" is one self-contained directory
src/user/controller.ts
src/user/service.ts
src/user/model.ts
src/billing/controller.ts
src/billing/service.ts
src/billing/model.ts
src/notification/                  ← entire feature in one place
  controller.ts
  service.ts
  model.ts
```

**Diagnostic**: If a feature change requires touching >2 top-level directories, the code is sliced wrong. Each feature should be a self-contained vertical slice.

**How to apply**: When creating new modules or restructuring existing ones, group by domain concept (user, billing, notification) not by technical role (controllers, services, models). Shared infrastructure (database clients, logging, config) lives in a separate `shared/` or `infrastructure/` module that features depend on.

---

## §2. Acyclic Dependencies Principle

The module dependency graph must be a Directed Acyclic Graph (DAG). Import cycles between modules make the entire cycle effectively one giant module — you can't understand, test, or deploy any part independently.

**Detection**: If module A imports from B, and B imports from A (directly or transitively), there's a cycle.

**Three fixes:**

1. **Extract shared concept into module C** — If A and B both need the same type or function, extract it into a new module C that both depend on. The cycle becomes A→C←B.

2. **Dependency inversion** — If A depends on B's concrete implementation, define an interface in A and have B implement it. A depends only on its own interface; B depends on A's interface. The dependency direction flips.

3. **Merge A and B** — If the cycle can't be broken cleanly, the two modules are actually one module. Merge them and accept that reality.

**How to apply**: Before creating a new import, check: does this create a cycle? If yes, apply one of the three fixes. Tools like `import-graph` (JS), `pydeps` (Python), or `cargo-depgraph` (Rust) visualize the dependency graph.

---

## §3. Common Closure Principle

Classes that change together belong together. This is the module-level equivalent of the Single Responsibility Principle, but at a coarser granularity.

**Why LLMs get this wrong**: LLMs group code by _technical similarity_ — "these are all validators, put them in `validators/`; these are all formatters, put them in `formatters/`." But a billing validator and a billing formatter change together when billing requirements change. They belong in `billing/`, not in separate technical-role directories.

**Diagnostic**: Look at your git history. If two files consistently change in the same commits or PRs, they should be in the same module. If they're in different modules, that's shotgun surgery (see `structural-coupling.md` §4).

**How to apply**: When deciding where a new piece of code belongs, ask: "when this changes, what else will change?" Put it next to those things. If a code review reveals that a PR touches files in 4 different modules to accomplish one logical change, those files belong together.

---

## §4. Interface Segregation at Module Level

Don't force consumers to depend on exports they don't use. A module with a broad public API that serves multiple different consumers is actually multiple modules duct-taped together.

**Detection**: If consumer A uses functions 1-3 of a module and consumer B uses functions 4-6, the module should be split so that A and B depend on smaller, focused modules.

**Why this matters**: When functions 4-6 change, consumer A gets rebuilt/retested even though nothing it uses changed. At scale, this creates slow builds, unnecessary test runs, and false coupling signals in change analysis.

**How to apply**:

1. List all consumers of the module
2. For each consumer, note which exports they actually use
3. If there are distinct clusters (consumer group A uses one subset, group B uses another), split the module along those cluster lines
4. Shared utilities used by both clusters stay in the module or move to a shared dependency

This is especially important for "utility" modules that grow over time — they tend to become dumping grounds that couple unrelated consumers.

---

## §5. Invariant Enforcement at Boundaries

A module boundary without invariant enforcement is just file separation. Each module should **defend its own invariants** — the rules that must always be true about its data and state.

**Why LLMs miss this**: LLMs create "clean" module boundaries by moving files into directories, but leave the data structures as raw shared structs that anyone can put into an invalid state. The boundary looks good on a diagram but provides no protection.

**How to apply**:

- Replace raw shared structs with operations that preserve rules (constructors that validate, methods that maintain consistency)
- Expose fewer setters, more **intention-revealing operations**: `account.deposit(amount)` instead of `account.balance = account.balance + amount`
- The module's public API should make it impossible (or at least difficult) to violate its invariants from outside
- If an invariant can only be stated as a comment ("balance must never be negative"), the API isn't defending it — add runtime checks at the boundary

---

## §6. Error Boundary Translation

Each module should translate low-level errors into its own **error vocabulary**. Infrastructure exceptions (socket timeouts, SQL constraint violations, file permission errors) should not leak through module boundaries into business logic.

**Why LLMs miss this**: LLMs let exceptions propagate unchanged. A `ConnectionRefusedError` from a database driver surfaces in a billing function, coupling the billing logic to the database implementation. If you swap databases, error handling throughout the business layer breaks.

**How to apply**:

- At each module boundary, catch infrastructure errors and translate them into domain-meaningful errors
- `DatabaseConnectionError` → `PaymentProcessingUnavailable`
- `FileNotFoundError` → `ConfigurationMissing`
- The consuming module should only need to understand the domain error, not the infrastructure cause
- This pairs with Anti-Corruption Layer (see `architecture.md` §2) — translate data at the boundary, translate errors at the boundary
