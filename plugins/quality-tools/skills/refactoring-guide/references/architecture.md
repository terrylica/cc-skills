# Architectural Refactoring Patterns

Patterns for refactoring at the architectural level — separating concerns across system layers and managing large-scale migrations safely.

---

## §1. Functional Core, Imperative Shell (Gary Bernhardt)

Every function should be _either_ pure (computes and returns, no side effects) _or_ a shell (orchestrates IO, minimal logic). Functions that do both are the primary source of untestable, hard-to-refactor code.

```python
# WRONG: IO and logic interleaved — can't test discount logic without a DB
def process_order(order_id: str):
    order = db.fetch(order_id)         # IO
    if order.total > 100:              # logic
        discount = order.total * 0.1   # logic
        db.apply_discount(order, discount)  # IO
        send_email(order.customer)     # IO

# RIGHT: pure core computes, shell orchestrates
def calculate_discount(order: Order) -> Optional[Discount]:  # pure — testable
    if order.total > 100:
        return Discount(order.total * 0.1)
    return None

def process_order(order_id: str):  # shell — only IO orchestration
    order = db.fetch(order_id)
    if discount := calculate_discount(order):
        db.apply_discount(order, discount)
        send_email(order.customer)
```

**Why LLMs get this wrong**: LLMs write code top-to-bottom as a narrative — "first fetch, then check, then save." This naturally interleaves IO with logic. The refactoring move is to _pull the logic out_ into pure functions that receive data and return decisions, leaving the shell as a thin orchestrator.

**How to apply**: For any function that both reads/writes external state AND contains conditional logic, extract the conditional logic into a pure function. The pure function takes data in, returns a decision. The shell feeds data to the pure function and acts on the result.

---

## §2. Anti-Corruption Layer (Eric Evans)

At every external integration boundary, create a translation layer that converts external models into internal domain types. Internal business logic should never directly handle external schemas — they change without notice, they have different naming conventions, and they carry concerns your domain doesn't care about.

```python
# WRONG: Stripe's schema leaks throughout internal code
def process(stripe_event: dict):
    if stripe_event["type"] == "payment_intent.succeeded":
        amount = stripe_event["data"]["object"]["amount"]
        customer = stripe_event["data"]["object"]["customer"]
        # 20 more lines of Stripe-specific field access...

# RIGHT: translate at boundary, use internal domain types everywhere else
@dataclass
class PaymentReceived:  # internal domain event
    amount_cents: int
    customer_id: str

def from_stripe(event: dict) -> PaymentReceived:  # ACL — only place that knows Stripe's schema
    return PaymentReceived(
        amount_cents=event["data"]["object"]["amount"],
        customer_id=event["data"]["object"]["customer"],
    )

def process(payment: PaymentReceived):  # business logic — clean, testable
    ...
```

**How to apply**: At every integration boundary (third-party API, database ORM, message queue, file format), write a translation function or module that converts external representations into internal domain types. The rest of the codebase uses only the internal types. When the external API changes, only the ACL changes.

---

## §3. Strangler Fig (Martin Fowler)

For replacing existing systems or modules, never do a big-bang rewrite. Instead, wrap the old code in a facade, route traffic through it, replace one path at a time, and remove the facade when migration is complete.

**The process:**

1. Create a facade/adapter in front of the old code
2. Route all callers through the facade
3. Implement new logic behind the facade for one use case
4. Verify the new path works (tests, monitoring)
5. Repeat for the next use case
6. When all paths are migrated, remove the facade and the old code

**Why LLMs get this wrong**: LLMs prefer clean rewrites — they generate a fresh implementation and replace the old one in one shot. This works for small functions but fails catastrophically for modules with many callers, complex state, or subtle edge cases that the rewrite misses. The strangler fig approach ensures old and new coexist and both work at every step.

**How to apply**: For every refactoring PR involving module replacement, both old and new code must coexist and both must pass tests. If you can't keep both working simultaneously, the migration scope is too large — use smaller increments.

---

## §4. Mikado Method (Ola Ellnestam & Daniel Brolund)

For large refactors that touch many files, the Mikado method prevents the tangled intermediate states that LLMs create when they push forward through compilation errors.

**The process:**

1. **Attempt** the goal change directly
2. **If it breaks**, record what broke as a prerequisite on a dependency graph (the "Mikado graph")
3. **Revert** the goal change completely (git checkout/stash)
4. **Recursively apply** the method to each prerequisite, working bottom-up from leaves
5. **When all prerequisites are green**, apply the goal change — it now succeeds cleanly

**Why LLMs get this wrong**: When a refactoring causes a compilation error or test failure, LLMs try to fix it immediately, creating cascading changes that tangle multiple concerns. The Mikado insight is that _reverting and working bottom-up_ is faster and safer than pushing forward through breakage.

**How to apply**: For any refactoring that touches >3 files, use Mikado. The key discipline is: when something breaks, **don't fix forward** — revert and add the broken thing as a prerequisite. This ensures every intermediate commit is green and the refactoring can be abandoned at any point without leaving the codebase in a broken state.

**Example Mikado graph:**

```
Goal: Replace OldAuth with NewAuth
├── Prerequisite: Extract AuthInterface from OldAuth
│   ├── Prerequisite: Move shared types to auth-types module
│   └── Prerequisite: Remove direct OldAuth imports in billing/
└── Prerequisite: Add NewAuth adapter implementing AuthInterface
    └── Prerequisite: Create NewAuth credential store
```

Work leaves first (bottom-up): shared types → remove direct imports → extract interface → create credential store → add adapter → replace.

---

## §5. Composition Root Pattern

All wiring (dependency injection, configuration loading, service construction) should happen at one place near the boundary of the application — the **composition root** — not spread through reusable modules.

**Why LLMs miss this**: LLMs scatter construction and wiring throughout the codebase. A service creates its own database connection, a handler constructs its own logger, a utility reads environment variables directly. This makes modules hard to test, hard to reconfigure, and invisibly coupled to their environment.

**How to apply**:

- The composition root is typically `main()`, the app entry point, or a dedicated wiring module
- It creates all services, injects dependencies, loads configuration, and starts the application
- Reusable modules accept their dependencies as parameters — they never construct or discover them
- This is the one place where it's acceptable to import config globally, instantiate database connections, and wire things together

```python
# composition root (main.py) — the only place that knows about all concrete implementations
def main():
    db = create_database(os.environ["DB_URL"])
    mailer = SmtpMailer(os.environ["SMTP_HOST"])
    billing = BillingService(db, mailer)  # inject dependencies
    app = create_app(billing)
    app.run()
```
