# Rust-Specific Modularization

Rust modularization principles that LLMs consistently miss. In Rust, modularity quality is measured less by directory neatness and more by how well you control **visibility, public API evolution, feature unification, and dependency exposure**.

---

## §1. Visibility as Architecture

In Rust, `pub(crate)`, `pub(super)`, and `pub(in path)` are first-class boundary controls, not minor cleanup tools. LLMs default to `pub` on everything.

**How to apply**:

- Aggressively prefer the narrowest visibility that works
- Build a clean public façade with `pub use` re-exports in `lib.rs` or a top-level module
- Internal paths stay private; the public surface is curated, not a mirror of the filesystem
- Think of visibility annotations as load-bearing architecture, not syntax decoration

---

## §2. Public API Surface as the Real Boundary

Modularity in Rust is not just "who can call what today" but "what changes stay non-breaking later." Exposing concrete fields, unsealed extension points, or raw representation types weakens boundaries even when the code looks cleaner.

**Protective patterns**:

- **Sealed traits**: Prevent external implementations via a private supertrait
- **Private struct fields**: Force construction through `::new()` — preserves invariants
- **Newtypes**: Wrap primitives to prevent representation leakage
- **Non-exhaustive enums**: `#[non_exhaustive]` preserves ability to add variants

**How to apply**: Before declaring anything `pub`, ask: "will I regret this being part of my semver contract?" Use `cargo-public-api` to list and diff your public surface.

---

## §3. Crate Boundaries vs. Module Boundaries

LLMs often split code into more crates without asking whether the boundary is meant to be semver-stable. Crate boundaries in Rust carry compatibility consequences that module boundaries don't.

**When to create a new crate** (any of these justify it):

- Different semver release cadence
- Proc-macro requirement (forced separate crate)
- Compile-time isolation needed
- Different dependency policy or license requirements
- Independently testable/deployable unit

**When NOT to create a new crate**:

- Just to organize files (use modules within the same crate)
- To "look more modular" without actual boundary justification

---

## §4. Façade Modules and Re-Exports

A Rust library benefits from private internal structure plus a curated public façade. `pub use` declarations redirect public names away from private canonical paths.

```rust
// lib.rs — curated public façade
pub use self::parser::Parser;
pub use self::executor::ExecutionResult;
// internal topology is hidden — users see a flat, domain-shaped API

// Internal modules stay private
mod parser;
mod executor;
mod optimizer; // not re-exported — implementation detail
```

**How to apply**: The filesystem/module tree is an implementation detail. The `pub use` surface in `lib.rs` is the real API. Don't mirror internal structure in the public surface.

---

## §5. Proc-Macro Boundary Isolation

Procedural macros must live in a crate of type `proc-macro`, and they cannot be used from the crate where they are defined. This is a forced architectural boundary.

**How to apply**:

- Keep proc-macro crates tiny — only the macro definitions
- Push shared semantics (types, validation logic, builder patterns) into a normal library crate
- The proc-macro crate depends on the shared library crate, not vice versa
- Don't let proc-macro crates become dumping grounds for business logic

---

## §6. Cargo Features as Module Design

Features are not just build toggles — they are part of how modularity behaves under compilation. **Cargo features are additive**, which means enabling a feature can never disable functionality.

**LLM blind spot**: Models split crates cleanly, then ignore feature interactions that recombine them into surprising build surfaces.

**How to apply**:

- Treat feature flags as part of the modular architecture, not just CI configuration
- Audit feature additivity: enabling feature A + feature B must not create conflicts
- Don't use features for mutually exclusive configurations (use separate crates instead)
- Document which features expose which public API surface

---

## §7. Workspace Feature Unification

Cargo's feature unification means that if any crate in a workspace enables a feature on a shared dependency, ALL crates in that workspace get that feature. This is a major Rust-specific blind spot.

**Tools**:

- `cargo-hakari` — manages workspace-hack crates to control unification
- `cargo-hack` — tests all feature combinations to catch unification surprises
- `cargo tree -e features` — visualize which features are actually enabled and why

**How to apply**: A modular design that looks correct at the package level can be operationally unstable because feature unification changes what dependencies get built. Always check: "what features does my crate get when built as part of the workspace vs. standalone?"

---

## §8. Workspaces for Governance, Not Domain Boundaries

Cargo workspaces share a lockfile and target directory, and support `workspace.dependencies`, `workspace.package`, and `workspace.lints`. This is excellent for version/lint/metadata policy.

**LLM blind spot**: Models overuse workspaces as if centralization were the same as modularity. A workspace is a governance tool, not a domain boundary.

**How to apply**:

- Use `workspace.dependencies` to centralize version pins
- Use `workspace.lints` to enforce consistent lint policy
- Don't conflate "same workspace" with "same domain" — crates in a workspace can serve completely unrelated purposes
- The workspace boundary doesn't define module cohesion

---

## §9. Dependency Exposure Control

On nightly, Cargo's `public-dependency` feature marks dependencies as public or private, and rustc's `exported_private_dependencies` lint warns if a private dependency leaks into your public interface.

**How to apply**:

- Identify which dependencies' types appear in your public API
- Those are your true public dependencies — everything else should be implementation-private
- When a dependency's types leak into your public surface, you're coupling your semver stability to that dependency's release cadence
- Use `cargo-public-api` to detect leakage

---

## §10. Dependency Policy Tooling

In Rust, modularization is not complete until you have dependency-graph policy:

| Tool                  | Purpose                                                    |
| --------------------- | ---------------------------------------------------------- |
| `cargo-deny`          | Lint dependency graph: bans, licenses, advisories, sources |
| `cargo-vet`           | Audit third-party dependencies against trusted reviews     |
| `cargo-semver-checks` | Catch semver regressions in public API changes             |
| `cargo-public-api`    | List and diff public API surface (nightly)                 |
| `cargo-modules`       | Visualize module structure and internal dependency graph   |
| `cargo-udeps`         | Detect unused dependencies (nightly)                       |
| `cargo-machete`       | Faster but imprecise unused dependency detection (stable)  |
| `cargo-hack`          | Test all feature combinations                              |
| `cargo-hakari`        | Manage workspace feature unification                       |

**How to apply**: Include these in CI and run them before proposing modularization changes. The model should reason about what these tools would report, not just what the code "looks like."
