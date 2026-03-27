# Tactical Refactoring Moves

Concrete techniques for executing refactorings safely. These address the gap between knowing _what_ to refactor and knowing _how_ to do it without breaking things.

---

## §1. Deletion as Refactoring

The best refactoring often has a negative line count. Before adding abstraction, ask: "can I just delete the code that makes this complex?"

**Deletion candidates:**

- Dead code paths that no conditional ever reaches
- Unused abstractions (interfaces with one implementor that will never have a second)
- Unnecessary indirection layers (a wrapper that just calls through)
- Backwards-compatibility shims for migrations that finished months ago
- `# TODO: remove after X` where X has long passed
- Feature flags for features that are permanently on or permanently off

**Why LLMs miss this**: LLMs are trained on code-generation tasks. Their instinct is to add, extract, wrap — creative construction. Deletion feels destructive and risky. But dead code has a maintenance cost: it confuses readers, appears in search results, and must be kept compiling when dependencies change.

**How to apply**: Before any additive refactoring (extract, wrap, abstract), first check: is there dead code that could simply be removed to solve the problem? Use `git log` and `grep` to verify something is truly unused before deleting.

---

## §2. Rule of Three

Tolerate duplication until the third instance. Two copies might diverge; three copies that remain identical are a genuine pattern worth abstracting.

**Why LLMs get this wrong**: LLMs abstract on first duplication — they see two similar blocks and immediately extract a helper. But premature abstraction creates the _wrong_ abstraction, and wrong abstractions are harder to fix than duplication. You have to undo the abstraction before you can create the right one.

**The reasoning**: With two instances, you don't yet know which parts are the stable pattern and which parts are accidental similarity. The third instance reveals the pattern — the parts that remain identical across all three are the real abstraction; the parts that differ are the parameters.

**How to apply**: When you see two similar code blocks, resist the urge to extract. Wait. If a third instance appears with the same structure, _now_ you have enough evidence to extract the right abstraction with the right parameters.

---

## §3. Inline Then Re-Extract

When a function has grown confused through years of patches, the decomposition reflects the historical accident of how it was modified, not the actual logic flow. LLMs try to split these functions further, creating more confusion.

**The technique:**

1. **Inline** everything back into the caller — expand all helper calls, unwind abstractions
2. **Read** the flattened code as one linear sequence
3. **Re-extract** with boundaries based on the actual logic flow you now see

**Why this works**: The flattened version reveals the true data flow and branching structure, stripped of the misleading names and boundaries that accumulated over time. Fresh extraction from this flat version creates a decomposition that matches reality.

**How to apply**: When a function and its helpers are hard to follow despite having "clean" names, the decomposition is probably wrong. Don't add another layer — inline everything, read it fresh, and re-decompose from scratch.

---

## §4. Parallel Change (Expand-Contract)

For modifying interfaces that have multiple callers, never change the interface in-place. Instead:

1. **Expand**: Add the new interface (new method signature, new API endpoint, new type) _alongside_ the old one
2. **Migrate**: Move callers to the new interface one at a time, each as its own commit
3. **Contract**: Remove the old interface once all callers have migrated

**Why LLMs get this wrong**: LLMs modify interfaces in-place, breaking all callers simultaneously. This forces a single atomic commit that changes the interface AND all callers — a merge conflict magnet and a rollback nightmare.

**How to apply**: For any interface with >1 caller, use expand-contract. Each step is a small, reviewable, independently deployable commit:

- Commit 1: Add new method alongside old
- Commits 2-N: Migrate callers one at a time
- Final commit: Remove old method

This is especially important for public APIs, shared libraries, and database schemas.

---

## §5. Boolean Parameter Prohibition

A boolean parameter means the function does two different things depending on the flag. At the call site, `render(template, True)` is unreadable — what does `True` mean?

```python
# WRONG: what does True mean at call site?
render(template, True)
process(data, False, True)

# RIGHT: separate methods or enum
render_with_cache(template)
render_without_cache(template)

# or: enum makes the choice explicit
render(template, cache=CachePolicy.ENABLED)
process(data, validate=ValidationMode.SKIP, compress=CompressionMode.GZIP)
```

**How to apply**: When you see a boolean parameter:

- If it changes the core behavior: split into two functions with descriptive names
- If it's a configuration toggle: use an enum with named values
- Exception: private/internal functions where the call site is 1-2 lines away and the meaning is obvious can use booleans

---

## §6. Configuration as Explicit Dependency

Global config imports create hidden coupling — every function silently depends on a global singleton, making testing hard and reasoning non-local.

```python
# WRONG: hidden dependency — can't test without manipulating global state
from config import settings
def send(msg):
    if settings.DRY_RUN: return
    actually_send(msg)

# RIGHT: explicit dependency — testable, dependencies visible in signature
def send(msg, *, dry_run: bool = False):
    if dry_run: return
    actually_send(msg)
```

**How to apply**: Pass configuration as parameters. If many functions need the same config, group related settings into a dataclass and pass that:

```python
@dataclass(frozen=True)
class EmailConfig:
    dry_run: bool = False
    smtp_host: str = "localhost"
    timeout_seconds: int = 30

def send(msg, config: EmailConfig):
    if config.dry_run: return
    ...
```

Global config imports are only acceptable at the **composition root** — the `main()` function or application entry point that wires everything together.

---

## §7. Characterization Tests Before Refactoring

Before ANY refactoring, write tests that pin the current behavior — including known bugs. These are called "characterization tests" (Michael Feathers) because they characterize what the code _actually does_, not what it _should_ do.

**The process:**

1. Write tests that cover the code's current behavior (inputs → actual outputs, even if buggy)
2. Refactor the code
3. Run the characterization tests — they must all pass
4. Only _then_ fix bugs in separate commits

**Why LLMs get this wrong**: LLMs refactor first, then discover tests break. At that point, it's unclear whether the test was wrong or the refactoring introduced a regression. By pinning behavior first, any test failure during refactoring is definitively a regression.

**How to apply**: For any refactoring that changes control flow, data flow, or module structure, write characterization tests _before_ making changes. Golden file tests (snapshot the output) are the fastest way to pin behavior for complex functions.

---

## §8. Conway's Law Alignment

Module boundaries should align with team/ownership boundaries. If two teams own different features, those features should be in different modules — even if the code is technically similar.

**Why LLMs get this wrong**: LLMs optimize for technical elegance, grouping similar code together regardless of who maintains it. But in practice, a module owned by two teams creates coordination overhead: conflicting priorities, merge conflicts, unclear responsibility for bugs, and slow review cycles.

**How to apply**: When deciding module boundaries, factor in team structure:

- One team, one module (ideal)
- Shared modules should have a single designated owner team
- If two teams keep conflicting on a shared module, split it along team lines

This applies less to solo projects and small teams, but becomes critical at scale. Even in solo projects, thinking about "future team boundaries" can inform good modularization — features that might eventually be owned by different people should be in separate modules now.

---

## §9. Over-Modularization Check

A module boundary is justified **only if it improves change isolation, ownership clarity, or dependency direction**. Not because names look neat, folders are balanced, or the architecture resembles a pattern.

**Why LLMs miss this**: LLMs reflexively split code into more modules because "modularity = good." But every boundary has a cost: indirection, more files to navigate, more imports to manage, more interfaces to maintain. A module that only reorganizes files without reducing coupling is **fake modularity**.

**Signs of over-modularization:**

- Pass-through layers with no real boundary value (a "service" that just calls the "repository" with identical arguments)
- Modules with only one caller and no independent reason to exist
- Abstractions created "for testing" that add complexity but the tests could work with simpler stubs
- Boundaries drawn for aesthetic reasons ("every feature should have its own module") rather than change-isolation reasons

**How to apply**: For every proposed module, be able to answer: "what change does this boundary protect me from?" If the answer is vague or hypothetical, the boundary probably shouldn't exist yet. It's easier to split a too-large module later than to merge a prematurely-split one.

---

## §10. Module Documentation Template

When proposing a modularization refactoring, explicitly document each proposed module. This forces clear thinking about boundaries and prevents vague "it just feels cleaner" justifications.

For each module, state:

1. **Responsibility**: One sentence — what this module does
2. **Reason(s) to change**: What real-world events cause modifications here
3. **Data ownership**: What data structures this module owns and maintains invariants on
4. **Depends on**: What this module may import/call
5. **Depended on by**: What may import/call this module
6. **Public contract**: The interface exposed to consumers
7. **Invariants**: Rules that must always hold for this module's data
8. **Side effects**: IO, network, file, database operations performed
9. **Error model**: What errors this module surfaces to consumers
10. **Why this boundary**: Why this is better than keeping the code together

The last item is the most important — it forces justification for the boundary's existence and catches over-modularization (§9).
