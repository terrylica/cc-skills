# Swift/macOS-Specific Modularization

Modularization principles for Swift on macOS that LLMs consistently miss. In Swift, the best modularization work is about controlling **access, import, and binary/distribution boundaries** — not creating more folders or frameworks.

---

## §1. Default to Package/Target Boundaries, Not Frameworks

In modern Xcode/SwiftPM, a **target is already a module boundary**. Use local Swift packages and SwiftPM targets as the default modularization unit.

**Boundary type selection** (choose consciously):

| Boundary Type         | When to Use                                                             |
| --------------------- | ----------------------------------------------------------------------- |
| Package target/module | Default — source-level modularity within the app                        |
| Macro target          | Swift macros (forced separate target, sandboxed execution)              |
| Framework/XCFramework | Separately distributed binaries, independently versioned SDK components |
| Mergeable library     | Keep library-shaped dev boundaries without separate runtime binaries    |

**LLM blind spot**: Models reach for frameworks by default. Reserve frameworks/XCFrameworks for code built and updated separately from its clients. Library evolution (`BUILD_LIBRARY_FOR_DISTRIBUTION`) is off by default — don't enable it for modules that are always built and shipped together.

---

## §2. Access Control as Architecture

Swift has fine-grained access control that LLMs under-use. The `package` access modifier (SE-0386) exists specifically so symbols can be shared across modules within the same package without making them `public`.

**Access level hierarchy** (narrowest first):

| Level         | Scope                             | When to use                                        |
| ------------- | --------------------------------- | -------------------------------------------------- |
| `private`     | Current declaration               | Default for implementation details                 |
| `fileprivate` | Current file                      | When multiple types in one file need shared access |
| `internal`    | Current module/target             | Default for intra-module use                       |
| `package`     | Current package                   | Share across sibling modules without going public  |
| `public`      | Any importing module              | Part of the stable API surface                     |
| `open`        | Any module + subclassing/override | Only when external subclassing is intentional      |

**How to apply**: Prefer `package` over `public` when sharing across sibling modules within the same Swift package. Use `public` instead of `open` unless you intentionally want external subclassing.

---

## §3. Explicit Import Visibility (SE-0409)

SE-0409 added access-level modifiers on `import`. In current language modes (including Swift 6), imports default to `public` for source compatibility — meaning `import Foo` accidentally keeps dependency exposure broader than intended.

```swift
// WRONG: implicit public import — leaks dependency to consumers
import Foundation

// RIGHT: explicit import visibility
internal import CryptoKit  // implementation-only dependency
package import SharedUtils  // shared within this package only
public import DomainTypes   // intentionally part of this module's public surface
```

**How to apply**: Write `internal import`, `package import`, or `public import` deliberately. Prefer `internal import` for implementation-only dependencies. This replaces the deprecated `@_implementationOnly import`.

---

## §4. `@_spi` as Exception, Not Default

Swift's SPI (`@_spi(name)`) lets you expose "friend APIs" across module boundaries. But it's still an underscored mechanism.

**Correct priority order for inter-module sharing**:

1. `internal`/`package` access — covers most cases
2. Scoped imports (SE-0409) — controls what consumers see
3. `@_spi` — only when you genuinely need friend APIs that normal access control can't express

**LLM blind spot**: Models reach for `@_spi` as a first-class modularity tool. It should be a deliberate exception for rare cases.

---

## §5. Module Aliasing for Collisions (SE-0339)

SwiftPM's module aliasing resolves naming collisions without source edits. But it has important limits:

- Works for **pure Swift modules** only
- Works for **source builds**, not distributed binaries
- Has caveats with ObjC/C/C++ interop and runtime reflection

**How to apply**: Use module aliasing when you have genuine naming collisions. Don't use it as a general modularity strategy — it's a collision resolver, not a boundary designer.

---

## §6. Macro Target Isolation

Swift macros are not "just another helper module." A macro target:

- Is its own target type (built as a host executable)
- Executes in a sandbox (no filesystem or network access)
- Is automatically available to dependent targets
- Is coupled to `swift-syntax` releases (toolchain-coupled)

**How to apply**:

- Keep macro targets thin — only macro definitions and syntax transformations
- Push shared domain logic into normal library targets
- Treat macro code as more toolchain-coupled than ordinary domain code
- Same principle as Rust proc-macros: thin boundary, shared semantics elsewhere

---

## §7. Resources as Target-Owned Bundles

SwiftPM scopes resources to targets and treats them as module-local bundles accessed via `Bundle.module`. Resources are target-owned, not globally shared.

**How to apply**:

- UI assets, templates, and data files belong to the target that uses them
- Only extract a resource module when you want a real bundle-ownership boundary, not just to tidy folders
- Access resources via the package-provided `Bundle.module` mechanism

---

## §8. Public API Governance

Once a package/module becomes a real boundary, you need tooling to protect it.

| Tool                                                        | Purpose                                                            |
| ----------------------------------------------------------- | ------------------------------------------------------------------ |
| `swift package diagnose-api-breaking-changes`               | Detect semver regressions in public API                            |
| Tuist `graph`                                               | Visualize module dependency graph                                  |
| Tuist `inspect implicit-imports`                            | Find hidden dependency edges                                       |
| Periphery                                                   | Dead code/declaration detection (supports macOS + Xcode + SwiftPM) |
| `cargo doc --document-private-items` equivalent: Xcode DocC | Inspect internal vs public API surface                             |

**How to apply**: Run `diagnose-api-breaking-changes` before publishing any package update. Use Tuist or manual graph inspection to detect implicit imports and hidden dependency edges.

**Library evolution caveat**: Enabling `BUILD_LIBRARY_FOR_DISTRIBUTION` changes performance characteristics and affects exhaustive switch on enums (`@frozen` vs non-frozen). Only enable for separately distributed binary frameworks.
