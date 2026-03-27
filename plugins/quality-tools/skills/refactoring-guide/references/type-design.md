# Type-Level Design for Refactoring

Principles for using the type system to eliminate categories of bugs at compile time. LLMs consistently under-use types as a design tool, defaulting to runtime validation and primitive types where compile-time guarantees are possible.

---

## §1. Parse, Don't Validate (Alexis King)

Validation checks a condition and throws; parsing checks a condition and returns a typed result that encodes the proof. The difference is that parsing _preserves the evidence_ of validity in the type system.

```python
# WRONG: validate then pass raw — nothing prevents passing unvalidated str later
def process_email(raw: str):
    if not is_valid_email(raw):
        raise ValueError("invalid email")
    send_to(raw)  # raw is still str

# RIGHT: parse into a type that proves validity
class Email:
    def __init__(self, raw: str):
        if not is_valid_email(raw):
            raise ValueError("invalid email")
        self.address = raw  # construction IS the proof

def process_email(email: Email):  # type signature requires proof
    send_to(email)
```

**Why this matters**: With validation, every function downstream must trust that someone upstream validated correctly. With parsing, the type signature _is_ the proof — if you have an `Email`, it was validated at construction. This eliminates an entire category of "forgot to validate" bugs.

**How to apply**: At every system boundary (user input, API response, file read, environment variable), parse into a domain type. Downstream functions accept the parsed type, never the raw input. If a function accepts `str` where it should accept `Email`, that's a refactoring target.

---

## §2. Make Illegal States Unrepresentable

When a type has boolean or optional fields that can't actually vary independently, the type allows states that should be impossible. Discriminated unions eliminate these ghost states.

```typescript
// WRONG: 4 boolean combos, only 2 are valid
// (connected=false, authenticated=true is impossible)
type Connection = { connected: boolean; authenticated: boolean };

// RIGHT: only valid states exist
type Connection =
  | { state: "disconnected" }
  | { state: "connected"; socket: WebSocket }
  | { state: "authenticated"; socket: WebSocket; token: string };
```

**How to apply**: When you see a boolean field or optional field, ask: "can the other fields be set independently of this one?" If the answer is no — if some combinations are nonsensical — replace with a discriminated union. Each variant carries exactly the fields that are valid in that state.

**Language-specific patterns:**

- **TypeScript**: Discriminated unions with a literal `type` or `state` field
- **Python**: `@dataclass` subclasses or `Literal` union types (3.8+), or `enum.Enum`
- **Rust**: `enum` with associated data (the gold standard)
- **Go**: Interface with unexported methods + concrete structs per state

---

## §3. Newtype / Branded Types

Wrapping primitive types in distinct domain types prevents accidentally swapping arguments that happen to share a primitive type.

```typescript
// Branded type pattern (TypeScript)
type UserId = string & { readonly __brand: unique symbol };
type Email = string & { readonly __brand: unique symbol };

function sendEmail(to: Email, from: UserId) {} // compiler catches swapped args
```

```python
# Python: NewType for lightweight distinction
from typing import NewType

UserId = NewType("UserId", str)
Email = NewType("Email", str)

def send_email(to: Email, sender: UserId) -> None: ...
```

**How to apply**: If two parameters have the same primitive type but different semantic meaning — especially across module boundaries — wrap them. Common candidates: IDs of different entity types, file paths vs URLs, amounts in different currencies, timestamps in different timezones.

---

## §4. Temporal Coupling → Type-State Pattern

Temporal coupling exists when methods must be called in a specific order but nothing in the API enforces it. The type-state pattern makes the ordering un-break-able by returning a new type after each step.

```python
# WRONG: temporal coupling — caller must know the magic order
client = Client()
client.connect()      # must call first
client.authenticate() # must call second
client.send(data)     # only valid after both — but compiles regardless

# RIGHT: type-state makes wrong order impossible
class Disconnected:
    def connect(self, host: str) -> Connected: ...

class Connected:
    def authenticate(self, creds: Credentials) -> Authenticated: ...

class Authenticated:
    def send(self, data: bytes) -> None: ...

# Usage: the only path is Disconnected → Connected → Authenticated
session = Disconnected().connect("host").authenticate(creds)
session.send(data)
# session.connect(...)  # AttributeError — can't go backwards
```

**How to apply**: When you see a sequence where method B is only valid after method A, or documentation says "you must call X before Y," that's temporal coupling. The fix: each step returns a _different type_ that only exposes the methods valid in the new state. This converts a runtime "you forgot to initialize" crash into a compile-time (or at least type-checker) error.
