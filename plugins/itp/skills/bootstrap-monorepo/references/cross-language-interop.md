# Cross-Language Interop Doctrine (boundary ladder + verified tool status)

> **Provenance**: two adversarial deep-research runs. Run 1 (2026-06-12, 102 agents; 87
> claims → 25 verified → 14 confirmed, 11 refuted) seeded the boundary ladder + WASM/Arrow/buf
> status. Run 2 (2026-06-13, 25 agents; 6 load-bearing claims × 3 skeptics + 7 SOTA enrichment
> searches → 6/6 confirmed) seeded the TypeScript↔Python section. Votes shown as
> `confirm-refute`. Re-verify anything time-sensitive (WASM/WASI status, tool picks) after
> ~6 months.

This reference answers ONE question for an agent: **when work must cross a programming-language
boundary, which language owns what, which mechanism do I pick, and with which FOSS?** It extends
[bootstrap-monorepo.md](./bootstrap-monorepo.md) Phase 6 (polyglot kernel doctrine).

## Language-selection default — who owns what

Before choosing a _boundary mechanism_, choose _which language owns the code_. The default is a
**greenfield tiebreaker, not a mandate** — it is overridden by (a) a **SOTA-native ecosystem**
for the domain and (b) **existing repo convention**.

- **TypeScript is the default control plane.** Use it for application logic, orchestration,
  CLIs, APIs, configuration, validation, workflow/agent automation, and anything future agents
  must refactor safely. TS is **structurally typed by default** — compatibility is by shape, so
  contracts compose without nominal ceremony, and a typed CLI/orchestration layer is the most
  agent-navigable surface. [confirmed 3-0; TS 6.0, 2026]
- **Other languages are engines behind a typed boundary**, chosen when their ecosystem is
  SOTA-native for the task:
  - **Python** — ML / data / science / quant, or any library that is Python-only or materially
    more mature in Python. (Python's type hints are **not runtime-enforced**; `typing.Protocol`
    gives structural typing only to _static_ checkers, and `@runtime_checkable` checks member
    _existence_, not signatures — so validate at the boundary, see below. [confirmed 3-0])
  - **Rust / Go** — hot kernels, systems work, single-binary tools (Go > Rust as the greenfield
    tiebreaker per the kernel doctrine).
- **Do not let an engine language leak across the repo.** A Python-only library does NOT make
  the project a Python project — wrap it behind ONE narrow, typed boundary (the ladder below)
  and keep TypeScript as the public interface and orchestrator.

> The cross-cutting SSoT for this default is the user's principles spoke (rule:
> _Bun/TS > Python, Go > Rust — greenfield tiebreaker; SOTA-native ecosystem + existing
> convention override it_). This skill restates it self-contained because it installs to
> `~/.claude/skills/` away from that spoke.

## The Boundary Decision Ladder

Climb from cheapest to most coupled. **Stop at the first rung that satisfies the latency /
volume / sharing requirement.** Each rung down adds build complexity, debugging opacity, and
CI surface — pay for it only when measured need exists.

| Rung | Mechanism                                         | Pick when                                                                                                   | Default FOSS                                                          |
| ---- | ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| 1    | **Process boundary** (CLI + JSON/NDJSON on stdio) | Default. Calls are coarse-grained; debuggability and zero build coupling matter most                        | moon `script:` tasks; RFC 9457 problem+json errors                    |
| 2    | **Schema-typed RPC** (long-lived service)         | Persistent process, streaming, or network boundary already exists                                           | protobuf + buf; ConnectRPC/gRPC                                       |
| 3    | **Data-plane** (columnar zero-copy)               | Payload is tabular/columnar and serialization dominates cost; multiple engines/languages read the same data | Apache Arrow IPC / Arrow Flight / ADBC                                |
| 4    | **In-process FFI**                                | High call frequency + small payloads; per-call overhead of rungs 1–3 dominates                              | PyO3/maturin (Rust→Py), napi-rs (Rust→Node), Bun FFI, cdylib+cbindgen |
| 5    | **One WASM component core**                       | ONE logic core must run identically in N hosts AND kernel needs no threads (see below)                      | WIT + Component Model; wasmtime, jco, componentize-py                 |

Rungs 4–5 are the Pattern B mechanisms from Phase 6; rung 1 with conformance vectors is
Pattern A. The 8-float-op test still chooses A vs B; this ladder chooses the **mechanism
within B**.

## WASM Component Model — verified status (mid-2026)

- **Wasm 3.0 ratified Sept 2025 (W3C); WASI 0.3 ratified Feb 2026** with async-style
  concurrency via `stream<T>`/`future<T>` (completion-based, io_uring/IOCP-style); supported
  in Wasmtime 46+ and jco. [3-0]
- **NO threads / true parallelism** — still roadmapped on the shared-memory threads proposal
  with **no concrete ship date**. Parallel compute, thread-pool-heavy kernels, and
  high-throughput services remain outside WASM's reach. WASI 1.0 vaguely expected late
  2026/early 2027. [3-0]
- **Toolchain maturity is uneven**: Rust stable; Python (componentize-py), Go (TinyGo), Java
  in active development — not battle-hardened. WIT auto-generates type-safe bindings
  (eliminates manual marshaling code), but debugging across the boundary remains
  non-trivial. [2-1]

**⇒ Pattern B gate amendment**: after the 8-float-op test selects Pattern B, ask **"does the
kernel need threads or host-grade throughput?"** If yes → native core (`cdylib` + per-language
bindings, e.g. PyO3/napi-rs), NOT a WASM core. Re-evaluate when WASI threading ships.

## Schema SSoT toolchain — verified status

- **protobuf + buf is the strongest drift-gate stack**: `buf breaking` distinguishes FOUR
  compatibility categories — `FILE` (source-level, strictest; what C++/Python imports need),
  `PACKAGE` (Go-style package-level), `WIRE_JSON`, `WIRE` (binary only). A field rename can
  pass `WIRE` while breaking every generated SDK — **pick the category per language
  exposure**, don't default to `WIRE`. [3-0]
- Buf Schema Registry serves generated SDKs through each language's native package manager
  (go proxy, npm, PyPI, Cargo sparse, Maven, NuGet…). [3-0] _Local-first caveat: BSR is a
  hosted service — for this stack, prefer local `buf generate` + committed `gen/` dirs with
  the Phase 6 byte-diff drift gate; treat BSR as optional distribution, not the gate._
- **JSON Schema is a constraint language, not a type specification** — codegen into
  constructive type systems is inherently lossy (Typify's own README calls JSON Schema
  "often seemingly hostile" to translation; RFC 8927/JTD exists precisely because of this).
  [3-0] **Rule**: when a JSON Schema is a codegen SSoT, keep it in the constructive subset
  (objects + `required`, enums, arrays, simple scalar types); avoid `not`, `multipleOf`,
  heavy `pattern`/`allOf` merging.
- **typify is Rust-only** (CLI `cargo typify`, `import_types!` macro, build.rs builder); it
  supports Rust↔Schema round-trips via `x-rust-type` (crate + semver-checked version +
  type path). It does NOT do multi-language codegen. [3-0] For multi-language JSON Schema
  codegen, candidates are quicktype / datamodel-code-generator — **unverified here** (the
  "datamodel-code-generator supports 9+ formats / powers Airbyte protocol models" claims
  were REFUTED 0-3; test against your schema before standardizing).

## Data-plane interop (Arrow) — verified status

- **Arrow Flight** defines language-agnostic RPC (`GetFlightInfo`, `DoGet`, `DoPut`,
  `DoExchange`) streaming Arrow record batches over gRPC, with zero-copy optimizations
  (implementations intercept encoded payloads to avoid memory copies despite the protobuf
  envelope). [3-0]
- Flight decouples metadata from data location (`FlightEndpoint`s) for parallel multi-server
  reads; `FlightInfo.ordered` is **advisory** — a server needing strict ordering must return
  a single endpoint. Transports beyond gRPC via URI schemes (`grpc://`, `grpc+tls://`,
  `http(s)://` incl. cloud presigned URLs, `arrow-flight-reuse-connection://`). [3-0]
- **Arrow is now an interoperability layer across lakehouse engines** (Flight SQL, ADBC,
  DataFusion; Spark/Dremio/DuckDB integration), not just an in-memory format. [3-0]
- Maturity: Rust/Python/Java mature; Go catching up; C# thinner.
- **When to pick rung 3**: the moment two languages exchange _tables_ (not records), switch
  from JSON/proto messages to Arrow — it removes per-language serializers entirely. For
  same-host handoff, Arrow IPC files/streams suffice; Flight only when a network hop exists.

## TypeScript ↔ Python — the most common boundary (verified 2026-06-13)

This pair appears in nearly every repo here (TS control plane + Python ML/data engine), so it
gets a concrete playbook. Map each situation onto the ladder; **the SSoT for the data shape is a
schema, validated on BOTH sides** — TS types are compile-time only and Python hints are not
runtime-enforced, so an unguarded boundary is unityped in practice.

| Situation                                       | Rung | Pick                                                                                               |
| ----------------------------------------------- | ---- | -------------------------------------------------------------------------------------------------- |
| App logic / orchestration / CLI / repo tooling  | —    | TypeScript (no boundary)                                                                           |
| One-off / batch / local Python task             | 1    | TS spawns Python over stdio with JSON; **invoke via `uv run --python 3.14`**, never bare `python3` |
| Long-running Python ML/data capability          | 2    | FastAPI service (OpenAPI 3.1) + generated TS client                                                |
| Strict versioned contract / streaming / N langs | 2    | gRPC or Connect, stubs generated by `buf` (ties to the buf doctrine above)                         |
| Two sides exchange **tables**, not records      | 3    | Apache Arrow IPC (same host) / Flight (network) — skip JSON entirely                               |
| Sub-millisecond, very high call frequency       | 4    | In-process bridge — but read the caveat; usually means "rewrite the hot bit in TS/Rust" instead    |
| Browser- or sandbox-embedded Python             | 5    | Pyodide (CPython→WASM)                                                                             |

**Verified tool picks (all confirmed 3-0, current to June 2026):**

- **Rung 1 — process boundary.** Node `child_process.spawn` (async, default `pipe` stdio) or, on
  Bun, **`Bun.spawn`** (~1.06× throughput, same POSIX API). **`bun:ffi` is C-ABI-only — NOT a
  way to call Python**; don't reach for it. Bun gotchas: `kill()` has been flaky and misconfigured
  `stdio` can keep the parent alive — set `stdio` explicitly. Run Python through `uv` (repo bans
  bare `python3` + pins 3.14). Validate the JSON payload on entry/exit.
- **Rung 2 (HTTP) — FastAPI + a generated TS client.** FastAPI auto-emits OpenAPI 3.1 from
  Pydantic models; generate the TS SDK with **`@hey-api/openapi-ts`** (FastAPI's own recommended
  tool). `openapi-typescript` for a thinner types-only client. **Avoid `openapi-generator` for TS**
  (Java, ~30 s startup, large issue backlog) — keep it only for polyglot SDK suites.
- **Rung 2 (RPC) — buf-generated stubs.** One `buf generate` emits both sides from one `.proto`:
  `buf.build/protocolbuffers/python` (Python) + `buf.build/bufbuild/protobuf-es` (TS — the only
  fully spec-compliant Protobuf-JS runtime), optionally `connect-es` for RPC. For gRPC-Python use
  `buf.build/grpc/python`; `connectrpc/python` was still beta in early 2026.
- **Boundary validation / schema sync.** Make **Pydantic v2** the Python-side SSoT — it natively
  emits JSON Schema 2020-12 — then generate TS types from that schema (`pydantic-to-typescript`,
  or export the schema and run `json-schema-to-typescript` / `@hey-api`), with a **CI drift gate**
  (regenerate → byte-diff, same pattern as Phase 6). TS runtime validator: **Zod** for ecosystem
  depth / tRPC, **Valibot** when bundle size matters (~1.4 KB tree-shaken), **TypeBox** only when
  JSON Schema _is_ the output. Keep schemas in the constructive subset (see Schema SSoT section).
- **Python ML serving (rung 2 escalation).** Default **FastAPI**; escalate to **LitServe** for
  batching/streaming/multi-GPU latency, **BentoML** for multi-model or gRPC-alongside-REST,
  **Ray Serve** for cluster fault-tolerance, **Modal** when there is no serving host (it's a
  platform, not a framework). TS-client story is identical for all: point `@hey-api/openapi-ts`
  at `/openapi.json` and regenerate on drift.
- **Rung 4 — in-process JS↔Python bridges (use sparingly).** `pythonia`/`JSPyBridge` are
  _subprocess-backed_ (~2–5 ms/call) but crash-isolated; `PythonMonkey` is truly in-process (no
  per-call serialization) **but a crash in either runtime takes down the whole process and there
  is no GC coordination**. Prefer subprocess+HTTP for production; reach for in-process only when
  sub-ms latency is genuinely load-bearing AND throughput is modest. Often the honest answer is to
  move the hot path into TS or a Rust `napi-rs` addon instead.
- **Rung 5 — Pyodide.** CPython compiled to WASM, runs in browser AND Node (≥18), with a JS↔Python
  FFI. Pure-Python wheels work; C/Rust extensions must be Emscripten-ported (NumPy/pandas/SciPy
  are pre-built) and packages needing native syscalls won't behave like desktop CPython. Use for
  browser/sandbox/notebook embedding — **not** as a default backend bridge.

> **msgspec vs Pydantic**: default Pydantic v2 (best JSON-Schema export for codegen). Switch the
> Python worker to **msgspec** only when µs-scale (de)serialization is the bottleneck (>~10k
> req/s) — it loses validation decorators and tooling-friendliness. If the worker is greenfield
> and request-driven, also weigh **Go** as the typed worker (no GIL, cleaner TS boundary).

## Anti-patterns (claims REFUTED in verification — do not assert these)

- ~"WASI Preview 2 stabilized late 2024 and widely adopted with full implementations"~ —
  refuted as stated [0-3].
- ~Blanket "FlatBuffers/Cap'n Proto for ultra-low-latency, iceoryx2 for cross-language
  shared-memory IPC"~ — sourced only to low-quality secondary blogs, refuted 0-3 as a
  general rule. These tools are real but **benchmark per use case**; don't encode them as
  defaults.
- ~"Buf remote plugins eliminate local generator toolchains"~ — refuted 0-3; keep generators
  proto-pinned locally (matches local-first CI/CD anyway).
- Treating `buf breaking --against` with the default category as full safety — a rename can
  be wire-compatible yet break every SDK (see FILE vs WIRE above).

## Open questions (candidates for the next research round)

1. Measured WASM-component boundary-crossing cost vs FFI for real workloads — no trustworthy
   published numbers surfaced.
2. Established CI patterns for lock-step versioning of N generated SDKs from one schema.
3. Which lakehouse engines ship production Flight SQL _servers_ (vs client-only).
4. Published decision trees for WASM-component vs protobuf-RPC vs Arrow Flight for new
   shared-kernel work — none found; the ladder above is this repo's own synthesis.

## Sources (primary, confirmed claims)

Run 1 — boundary ladder / WASM / Arrow / buf:

- <https://buf.build/docs/breaking/rules/> · <https://github.com/bufbuild/buf>
- <https://arrow.apache.org/docs/format/Flight.html>
- <https://arrow.apache.org/blog/2025/02/28/data-wants-to-be-free/>
- <https://github.com/oxidecomputer/typify> · <https://www.rfc-editor.org/rfc/rfc8927>
- <https://2025.wasm.io/sessions/threading-the-needle-with-concurrency-and-parallelism-in-the-component-model/>
- <https://github.com/bytecodealliance/wasmtime> · <https://github.com/bytecodealliance/jco>

Run 2 — TypeScript↔Python:

- <https://www.typescriptlang.org/docs/handbook/type-compatibility.html> (TS structural typing)
- <https://peps.python.org/pep-0544/> · <https://peps.python.org/pep-0484/> (Protocol; hints not runtime-enforced)
- <https://nodejs.org/api/child_process.html> · <https://bun.com/docs/runtime/child-process> (spawn)
- <https://fastapi.tiangolo.com/advanced/generate-clients/> · <https://github.com/hey-api/openapi-ts> (OpenAPI→TS)
- <https://grpc.io/docs/languages/> · <https://buf.build/docs/generate/> · <https://github.com/bufbuild/protobuf-es> (poly-stubs)
- <https://pyodide.org/> · <https://blog.pyodide.org/posts/314-release/> (Pyodide 314)
- <https://github.com/extremeheat/JSPyBridge> · <https://docs.pythonmonkey.io/> (in-process bridges)
- <https://jcristharif.com/msgspec/jsonschema.html> · <https://docs.pydantic.dev/> (msgspec vs Pydantic)
