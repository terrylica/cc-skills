# Structural Coupling Analysis

Principles for analyzing and reducing coupling before extracting code. These address the LLM tendency to jump straight to "extract method/class" without first understanding the coupling topology.

---

## §1. Seam Identification (Michael Feathers)

A **seam** is a place where behavior can be altered without editing the code at that point. Identifying seams before refactoring prevents cutting across natural boundaries.

**Types of seams:**

- **Object seam**: Replace a dependency via polymorphism (pass an interface, swap the implementation)
- **Preprocessing seam**: Alter behavior via build config, feature flags, or environment variables
- **Link seam**: Swap behavior at the module/import level (dependency injection, module mocking)

**Why this matters for LLMs**: The instinct is to extract code based on visual grouping — "these lines look related, extract them." But if the extraction cuts across a seam, you create a function that straddles two concerns and is harder to change than the original. Extracting _at_ a seam creates clean boundaries because the seam is already a point of behavioral variation.

**How to apply**:

1. Before extracting, ask: "where can behavior be altered without editing this code?"
2. Those alteration points are seams. Extract _at_ the seam, not across it.
3. If no seam exists for the change you need, create one first — introduce a parameter, extract an interface, or add an indirection layer. Then extract.

---

## §2. Connascence Spectrum

Connascence measures the strength of coupling between components. It has a hierarchy — not all coupling is equally harmful. The goal is to refactor toward weaker forms, especially across module boundaries.

From weakest (acceptable) to strongest (refactor away):

| Strength | Type            | Example                                 | Across boundaries?              |
| -------- | --------------- | --------------------------------------- | ------------------------------- |
| 1        | Name (CoN)      | Using the same function name            | Yes — this is fine              |
| 2        | Type (CoT)      | Agreeing on a type for a parameter      | Yes — this is fine              |
| 3        | Meaning (CoM)   | `status: 1` means "active"              | No — use an enum                |
| 4        | Position (CoP)  | Argument order matters                  | No — use named params/kwargs    |
| 5        | Algorithm (CoA) | Must use same hash algorithm            | No — extract into shared module |
| 6        | Execution (CoE) | `init()` must be called before `run()`  | No — enforce via type-state     |
| 7        | Timing (CoT)    | Race conditions between components      | No — eliminate or synchronize   |
| 8        | Value (CoV)     | Values in two places must be consistent | No — single source of truth     |
| 9        | Identity (CoI)  | Must be the exact same instance         | No — make explicit              |

**How to apply**:

- Across module boundaries, only Name (CoN) and Type (CoT) connascence should exist.
- If you find Position (CoP) or stronger crossing a boundary, _that's_ the refactoring target — not the code that merely "looks messy."
- When reviewing a refactoring plan, check: does this change introduce stronger connascence than what existed before? If so, reconsider.

---

## §3. Stability Metrics (Robert C. Martin)

These metrics determine the _direction_ dependencies should flow. LLMs don't naturally reason about coupling directionality.

**Definitions:**

- **Afferent coupling (Ca)** = number of external modules that depend on this module (incoming arrows)
- **Efferent coupling (Ce)** = number of external modules this module depends on (outgoing arrows)
- **Instability I** = Ce / (Ca + Ce). Range: 0 (maximally stable, hard to change) to 1 (maximally unstable, easy to change)

**Two key principles:**

1. **Stable Dependencies Principle**: Depend in the direction of stability. A module with I=0.8 (unstable) can depend on a module with I=0.2 (stable), but not the reverse. A volatile module must NOT be depended upon by a stable one — it drags the stable module into instability.

2. **Stable Abstractions Principle**: Stable modules (low I, many dependents) should be abstract. If a module has high Ca (many things depend on it) but is concrete, it becomes a painful bottleneck — it resists change but change is needed.

**How to apply**:

Before moving code between modules, estimate I for both. Move code so dependencies flow from higher I to lower I. If you're about to make a stable, concrete module more complex, consider extracting an interface first.

---

## §4. Divergent Change vs. Shotgun Surgery

These are **opposite** code smells that require **opposite** fixes. LLMs routinely confuse them.

| Smell                | Symptom                                                                                                        | Correct Fix                                     |
| -------------------- | -------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| **Divergent change** | One module changes for multiple unrelated reasons (billing logic + auth logic + UI formatting all in one file) | **Split** the module by reason-for-change       |
| **Shotgun surgery**  | One logical change (e.g., adding a new payment method) requires touching 5+ scattered files                    | **Merge** the scattered concern into one module |

**The diagnostic questions:**

- "How many _reasons_ does this module change?" → If >1, it's divergent change → **split**
- "How many _modules_ does this single reason touch?" → If >3, it's shotgun surgery → **merge**

**Why LLMs get this wrong**: Both smells involve "too much changing." LLMs pattern-match on "things are changing a lot, so I should break them apart." But shotgun surgery requires the _opposite_ — merging scattered pieces together. The distinguishing factor is whether the unit of analysis is the module (divergent) or the reason-for-change (shotgun).

---

## §5. Data Ownership

Every important data structure should have a clear **owning module** — the single module responsible for creating, mutating, and enforcing invariants on that data. Other modules may read the data via contracts (function calls, events, read-only views) but should never mutate it directly.

**Why LLMs miss this**: LLMs often create "shared schema" modules where multiple modules import and freely mutate the same data structures. This creates invisible coupling — any module can put the data into an invalid state, and debugging requires understanding every mutation site.

**How to apply**:

- For each core data structure, ask: "which module is responsible for this data being correct?"
- That module owns the type definition and all write operations
- Other modules get read-only access or request changes through the owner's API
- Avoid "shared schema everywhere" unless the schema is intentionally canonical (e.g., a protobuf contract)

**Red flag**: If you see the same struct/class being mutated in 3+ different modules, ownership is unclear and invariants are undefended.

---

## §6. Volatility Isolation

High-volatility code (vendor SDKs, file format parsers, framework adapters, DB drivers) should sit behind narrow, stable interfaces. This prevents churn in volatile dependencies from rippling into stable business logic.

**Why LLMs miss this**: LLMs don't assess how often a dependency changes. They wrap things for "clean architecture" reasons but miss the primary motivation: **isolating the blast radius of change**. A stable API wrapped around unstable internals is good. Mixing stable and unstable concerns is not.

**How to apply**:

- Identify volatile dependencies: anything with frequent version bumps, breaking API changes, or vendor lock-in risk
- Wrap each behind a narrow interface that exposes only what your code needs
- The interface should use your domain's types, not the vendor's types (this overlaps with Anti-Corruption Layer — see `architecture.md` §2)
- When the vendor SDK changes, only the adapter module changes; business logic is untouched

**Volatility spectrum** (from most volatile to most stable):

1. External vendor SDKs and third-party APIs
2. Framework-specific code (web framework, ORM, UI toolkit)
3. Infrastructure (database driver, message queue, cache)
4. Business rules and domain logic (should be the most stable layer)
