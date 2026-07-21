# Meta-Prompt: Autonomous Polyglot Monorepo Bootstrap (moon + proto + Bun, Nx-convergent)

> **Role**: You are a Principal Software Architect specializing in AI-native monorepo design.
> **Mission**: Construct a production-grade polyglot monorepo from scratch, optimized for agentic workflows with Claude Code.
> **Constraint**: The human will not touch any code. You execute everything autonomously, verifying at each phase.
> **Supersedes**: the Pants + mise bootstrap (kept at `itp/skills/mise-tasks/references/bootstrap-monorepo.md` for legacy repos). This document is the canonical greenfield path as of 2026-06.

## Table of Contents

- [Tooling Stack: moon + proto + Bun](#tooling-stack-moon--proto--bun)
- [Migration Map: old stack → new stack](#migration-map-old-stack--new-stack)
- [Nx-Convergence Design Rules](#nx-convergence-design-rules)
- [Phase 0: Pre-Flight Verification](#phase-0-pre-flight-verification)
- [Phase 1: Foundational Structure](#phase-1-foundational-structure)
- [Phase 2: Root CLAUDE.md — The Hub](#phase-2-root-claudemd--the-hub)
- [Phase 3: Configuration Files](#phase-3-configuration-files)
- [Phase 4: Verification Checklist](#phase-4-verification-checklist)
- [Phase 5: Per-Language Package Init](#phase-5-per-language-package-init)
- [Phase 6: Cross-Language Contracts (the polyglot kernel doctrine)](#phase-6-cross-language-contracts-the-polyglot-kernel-doctrine)
- [Phase 7: CLI-First Machine-Readable Surface](#phase-7-cli-first-machine-readable-surface)
- [Phase 8: GitHub Repository Setup](#phase-8-github-repository-setup)
- [Phase 9: Release Workflow (local-first)](#phase-9-release-workflow-local-first)
- [Testing Patterns by Language](#testing-patterns-by-language)
- [Doctrine Appendix (hard-won, cross-repo)](#doctrine-appendix-hard-won-cross-repo)
- [Success Criteria](#success-criteria)

---

## Tooling Stack: moon + proto + Bun

One toolchain manager, one task orchestrator, one TS runtime — wired together by TypeScript, accelerated by Bun, ready to converge on Nx without restructuring.

| Tool                | Responsibility                                                                                     |
| ------------------- | -------------------------------------------------------------------------------------------------- |
| **proto**           | Toolchain versions (bun, node, python, rust, go, …) pinned in repo-local `.prototools`             |
| **moon**            | Project graph + task orchestration + caching + affected detection (`moon ci`, `--affected`)        |
| **Bun**             | TS runtime for every script, glue tool, CLI, and test (`bun test`); root `package.json` workspaces |
| **uv**              | Python: per-run interpreters (`uv run -p <version>`), workspace deps, lockfile                     |
| **cargo / maturin** | Rust crates; PyO3 extension wheels where Python needs the hot path                                 |
| **biome + oxlint**  | TS/JS lint+format (fast, zero-config baseline)                                                     |
| **ruff + ty**       | Python lint+format + type-check                                                                    |
| **pre-commit**      | Guard battery (hooks are the enforcement layer — see Doctrine appendix)                            |

**Principles** (constants; the tools above are the current best options):

1. **TypeScript is the control plane.** Orchestration, glue, CLIs, contract generation, and dashboards are TS-on-Bun. Other languages are engines behind contracts.
2. **Language selection default (greenfield tiebreaker)**: Bun/TS > Python; Go > Rust. A SOTA-native ecosystem or an existing convention overrides the default.
3. **Tasks call native tools** (`uv run …`, `cargo …`, `bun …`) via moon `script:` — moon adds the graph, caching, and affected detection; it never hides what actually runs.
4. **Machine-readable everything**: `moon query projects|tasks` JSON is the agent-discoverable task surface; CLIs emit `cli_spec.json` (JSON Schema 2020-12).

## Migration Map: old stack → new stack

| Concern              | Old (Pants + mise)                 | New (moon + proto)                                                                                                                                       |
| -------------------- | ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tool versions        | `mise.toml [tools]`                | `.prototools`                                                                                                                                            |
| Env vars / secrets   | `mise.toml [env]` + `read_file()`  | task-local env in `moon.yml` `env:`; secrets via 1Password CLI or `$HOME/.claude/.secrets/*` read at task start — NEVER `exec()`-style template subprocs |
| Task runner          | `mise run <task>` / Pants goals    | `moon run <project>:<task>`                                                                                                                              |
| Affected detection   | `pants --changed-since=…`          | `moon ci` / `moon run :task --affected` / `moon query projects --affected`                                                                               |
| Build metadata       | `BUILD` files + `pants tailor`     | one `moon.yml` per project + explicit `projects:` map                                                                                                    |
| Dependency inference | Pants engine                       | explicit `dependsOn`/`deps` in `moon.yml` (transparent > inferred)                                                                                       |
| Release              | mise file tasks → semantic-release | identical pattern, invoked as a moon task; multi-project repos add per-project namespaced tags via the monorepo fork (Phase 9 case B)                    |

Legacy repos on mise stay on mise until proven at parity — migrate per-repo, never big-bang (the migration playbook: run both side by side, cut tasks over one at a time, delete `.mise.toml` last).

## Nx-Convergence Design Rules

The goal is that a later `nx init` is **mechanical**, not a restructuring. Encode these from day one:

1. **One project per directory, explicitly registered** in `.moon/workspace.yml` `projects:` (no glob soup). Nx and moon both model an explicit project graph.
2. **Uniform task vocabulary across every project**: `lint`, `fmt`, `test`, `build`, `check` (composite). Affected pipelines and future Nx target-defaults depend on this uniformity.
3. **Root `package.json` declares Bun workspaces** (`"workspaces": ["packages/*", "apps/*"]`) — Nx detects projects from workspaces; Bun installs from it today.
4. **Tags on every project** (`tags: ['lang:rust', 'layer:engine']` in `moon.yml`) — maps 1:1 to Nx tags for dependency-boundary rules later.
5. **Declared outputs** for every generating task (`outputs: [...]`) — both orchestrators cache on declared outputs.
6. **No orchestrator-specific logic inside scripts.** A task's `script:` must run standalone from the repo root. The orchestrator is swappable; the scripts are the truth.
7. **Generated code lives in committed, clearly-marked dirs** (`gen/`, `generated/`) with drift-check tasks (regenerate-to-temp, byte-diff) — identical pattern under Nx.

---

## Phase 0: Pre-Flight Verification

```bash
# proto is the only global prerequisite
command -v proto || curl -fsSL https://moonrepo.dev/install/proto.sh | bash
proto --version

# Pin moon globally once (repo-local pins come from .prototools)
proto install moon && proto pin --to global moon <version>   # SSoT-OK
```

Create project root and initialize git:

```bash
mkdir -p ~/eon/<repo-name> && cd ~/eon/<repo-name>
git init
```

PATH discipline (process-storm prevention): proto shims go in `~/.zshenv` ONLY; full shell integration in `~/.zshrc` only.

```bash
# ~/.zshenv (idempotent)
export PROTO_HOME="$HOME/.proto"
export PATH="$PROTO_HOME/shims:$PROTO_HOME/bin:$PATH"
```

## Phase 1: Foundational Structure

```
<repo-name>/
├── CLAUDE.md                  # Hub: link farm root (progressive disclosure)
├── .prototools                # proto: toolchain pins (SSoT for versions)
├── .moon/
│   └── workspace.yml          # moon: explicit project graph + vcs
├── package.json               # Bun workspaces root (also: semantic-release home)
├── biome.json                 # TS/JS lint+format baseline
├── .pre-commit-config.yaml    # guard battery
├── .gitignore
├── .claude/
│   └── skills/                # project-local skills (the ONLY .claude content tracked)
├── docs/
│   ├── architecture/          # dated design docs + roadmaps
│   └── adr/                   # dated architecture decision records
├── packages/                  # TS control plane (Bun)
│   ├── cli/                   #   the repo console (dispatcher + cli_spec.json)
│   │   ├── CLAUDE.md
│   │   ├── moon.yml
│   │   ├── package.json
│   │   └── cli.ts
│   └── contracts/             #   generated cross-language types + drift gate
│       ├── CLAUDE.md
│       ├── moon.yml
│       └── gen/
├── crates/                    # Rust engines (one crate per dir)
│   └── core_rs/
│       ├── CLAUDE.md
│       ├── moon.yml
│       ├── Cargo.toml
│       └── src/
├── src/<python_package>/      # Python library (uv workspace root member)
│   └── CLAUDE.md
├── services/                  # deployable long-running services (any language)
├── schemas/                   # language-neutral contract SSoT (JSON Schema / .proto)
└── scripts/                   # automation; hooks/ subdir for pre-commit guards
```

```bash
mkdir -p .moon .claude/skills docs/{architecture,adr} packages/{cli,contracts/gen} \
         crates/core_rs/src services schemas scripts/hooks
```

Adapt the language mix to the repo: drop `crates/` for a pure-TS repo, drop `src/<python>` when no Python. The structure rule is the constant: **engines behind contracts, TS control plane on top, one explicit project per directory**.

## Phase 2: Root CLAUDE.md — The Hub

The root `CLAUDE.md` is a **link farm** — essentials only; every topic links to its SSoT spoke (`<dir>/CLAUDE.md`). Update spokes, not the hub.

```markdown
# <Repo Name>

One-paragraph identity: what this repo is, in domain terms.

## Quick Reference

| Action            | Command                      |
| ----------------- | ---------------------------- |
| Everything (CI)   | `moon ci`                    |
| Test a project    | `moon run <project>:test`    |
| Affected only     | `moon run :test --affected`  |
| Task surface (AI) | `moon query tasks` (JSON)    |
| Project graph     | `moon query projects` (JSON) |

**Stack**: proto (toolchains) · moon (orchestration) · Bun/TS (control plane) · <engines>.

## Navigation (Spoke Index)

| Scope            | Spoke                                                        |
| ---------------- | ------------------------------------------------------------ |
| TS console (CLI) | [packages/cli/CLAUDE.md](packages/cli/CLAUDE.md)             |
| Contracts        | [packages/contracts/CLAUDE.md](packages/contracts/CLAUDE.md) |
| Rust engine      | [crates/core_rs/CLAUDE.md](crates/core_rs/CLAUDE.md)         |
| ADRs             | docs/adr/ (dated)                                            |

## Critical Rules

1. <repo-specific invariants, one line each, detail in spokes>
```

## Phase 3: Configuration Files

### .prototools

```toml
# proto — canonical tool/version manager. One pin per toolchain actually used.
# SSoT-OK: placeholders; pin concrete versions at bootstrap time.
bun = "<version>"
python = "<version>"
rust = "<version>"
node = "<version>"     # only if a tool genuinely needs node (semantic-release does)
uv = "<version>"
```

### .moon/workspace.yml

```yaml
# yaml-language-server: $schema=https://moonrepo.dev/schemas/workspace.json
# Explicit project map (Nx-convergence rule 1) — no glob soup.
projects:
  repo: "." # repo-level umbrella tasks (release, docs)
  cli: "packages/cli"
  contracts: "packages/contracts"
  core_rs: "crates/core_rs"
  # py_lib: '.'  # a root-level Python package registers as its own project id

vcs:
  client: "git"
  defaultBranch: "main"
```

### Root package.json (Bun workspaces + release home)

```json
{
  "name": "<repo-name>",
  "private": true,
  "workspaces": ["packages/*"],
  "devDependencies": {
    "@biomejs/biome": "<version>",
    "semantic-release": "<version>",
    "@semantic-release/commit-analyzer": "<version>",
    "@semantic-release/release-notes-generator": "<version>",
    "@semantic-release/changelog": "<version>",
    "@semantic-release/exec": "<version>",
    "@semantic-release/git": "<version>",
    "@semantic-release/github": "<version>",
    "conventional-changelog-conventionalcommits": "<version>",
    "js-yaml": "<version>",
    "@rimac-technology/semantic-release-monorepo": "<version>"
  }
}
```

> The last three devDeps power **per-project** releases (Phase 9 case B). Install the fork with
> `npm i -D --ignore-scripts @rimac-technology/semantic-release-monorepo` — its `husky` prepare-script
> errors on a non-workspace root otherwise. Drop them for a single-releasable-unit repo (case A).

### Per-project moon.yml exemplars

**TypeScript (packages/cli/moon.yml)** — uniform vocabulary + tags:

```yaml
# yaml-language-server: $schema=https://moonrepo.dev/schemas/project.json
layer: "application"
language: "typescript"
tags: ["lang:ts", "layer:control-plane"]

tasks:
  lint:
    script: "bunx @biomejs/biome check . && bunx oxlint ."
  test:
    script: "bun test"
  spec-check:
    # CLI drift gate: regenerate cli_spec.json to temp, byte-diff against committed.
    script: "bun cli.ts spec --check"
    options: { cache: false }
  check:
    deps: ["~:lint", "~:test", "~:spec-check"]
```

**Rust (crates/core_rs/moon.yml)**:

```yaml
layer: "library"
language: "rust"
tags: ["lang:rust", "layer:engine"]

tasks:
  fmt:
    script: "cargo fmt --check"
  lint:
    script: "cargo clippy --all-targets -- -D warnings"
  test:
    script: "cargo test"
  check:
    deps: ["~:fmt", "~:lint", "~:test"]
```

**Python (root project moon.yml or src-level)**:

```yaml
layer: "library"
language: "python"
tags: ["lang:python", "layer:library"]

tasks:
  sync:
    script: "uv sync --python <version> --extra dev" # SSoT-OK
    options: { cache: false }
  lint:
    script: "uv run -p <version> ruff check src/ tests/" # SSoT-OK
  test:
    # GOTCHA: `uv run` prunes dev extras — pytest MUST be `uv run --extra dev`.
    script: "uv run --extra dev -p <version> pytest tests/" # SSoT-OK
    options: { cache: false }
  check:
    deps: ["~:lint", "~:test"]
```

Notes that save hours:

- `options: { runFromWorkspaceRoot: true }` whenever a script addresses repo-root paths.
- `options: { cache: false }` for guards, parity tests, and anything network/DB-touching.
- A composite `check` per project + `moon ci` at the root = the whole quality gate.

### biome.json (baseline)

```json
{
  "$schema": "https://biomejs.dev/schemas/<version>/schema.json",
  "formatter": { "enabled": true },
  "linter": { "enabled": true, "rules": { "recommended": true } }
}
```

### .gitignore (git tracking discipline)

```gitignore
# Claude Code — track ONLY skills (use * not / so negation works)
.claude/*
!.claude/skills/

# Dependencies / build
node_modules/
target/
.venv/
__pycache__/
dist/
build/

# moon
.moon/cache/
.moon/docker/

# Logs + local
logs/
*.local.*

# Secrets (never commit)
.env*
*.key
*.pem
```

### .pre-commit-config.yaml (guard battery seed)

```yaml
repos:
  - repo: local
    hooks:
      - id: ruff-check
        name: ruff (auto-fix aborts commit — re-stage and retry)
        entry: uv run -p <version> ruff check --fix # SSoT-OK
        language: system
        types: [python]
      - id: biome-check
        name: biome (TS/JS)
        entry: bunx @biomejs/biome check
        language: system
        types_or: [ts, tsx, javascript]
      # Grow the battery from day one: ban-eval-exec, ban-hardcoded-secrets,
      # CWE-377 tmp-literals, version-guard (versions only in manifests),
      # contract drift gates. Each guard = one hook + one escape-hatch token.
```

## Phase 4: Verification Checklist

```bash
proto use                      # install all .prototools pins
moon query projects | head     # project graph resolves
moon run cli:check             # uniform per-project gate
moon ci                        # affected pipeline end-to-end
bun install                    # workspaces resolve
git add -A && git commit -m "chore: bootstrap moon+proto polyglot monorepo scaffold"
```

ALWAYS verify `git log --oneline -1` after committing — hook batteries can pass individually yet abort the commit.

## Phase 5: Per-Language Package Init

### TypeScript (Bun)

```bash
cd packages/cli && bun init -y
bun add -d @types/bun
# Style gates you will hit: prefer .toSorted() over .sort(), optional chaining
# (a?.b) over guard chains, no var, no 'use strict' (modules imply it).
```

### Python (uv workspace)

```bash
uv init --lib --python <version>      # SSoT-OK
uv add <runtime-deps>
# Dev deps hoisted to ROOT pyproject [dependency-groups]/[project.optional-dependencies];
# members keep runtime deps only. Run tests from REPO ROOT:
#   uv run --extra dev -p <version> pytest <path-from-root>
```

### Rust (+ optional Python binding)

```bash
cd crates/core_rs && cargo init --lib
```

When the crate is a PyO3 extension module, hard-won rules:

- **Test binaries cannot link libpython** under `extension-module`: keep logic in pure-Rust
  core functions; the `#[pyfunction]` is a thin wrapper. Unit tests call the core.
- **Cross-arch float determinism**: `.cargo/config.toml` with `target-feature=-fma` +
  `target-cpu=generic` when bit-parity across machines is a requirement.
- **Remote installs**: build a wheel (`maturin build --release -i <python>`) and
  `uv pip install <wheel> --force-reinstall` — never `maturin develop` on remote hosts.

### Buildless browser assets (if the repo ships any)

A zero-build, `file://`-compatible asset (classic IIFE + window global) is a **first-class
moon project too**: its own `moon.yml` with guard tasks, vendored third-party libs under
`lib/vendor/` with **sha256 sidecar pins** + a fail-loud `vendor-pin` task, and a JSON-Schema
data contract with a contract-check task. Never let a reusable lib depend on a content dir.

## Phase 6: Cross-Language Contracts (the polyglot kernel doctrine)

**A hot or shared kernel's SSoT is language-neutral — NEVER a host-language file.** Python is
orchestration/consumer, not kernel. Choose the pattern by the 8-float-op test (`+ − × ÷ √ fma neg abs`):

| Pattern                      | When                                                       | Mechanism                                                                                                                                           |
| ---------------------------- | ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| **A — conformance vectors**  | kernel math fits the 8 ops deterministically               | one reference impl per language + shared test-vector files (JSON/CSV with expected outputs, sha256-pinned); every language must reproduce bit-exact |
| **B — one WASM/native core** | anything beyond the 8 ops (transcendentals, stateful FSMs) | ONE compiled core (Rust → wasm/cdylib/PyO3) + thin per-language bindings; bindings are glue-only                                                    |

**Pattern B mechanism gate** (verified 2026-06): if the kernel needs threads or host-grade
throughput → native core (cdylib + PyO3/napi-rs bindings), NOT WASM — WASI threading is still
roadmapped with no ship date (WASI 0.3, Feb 2026, added async only). For the full boundary
decision ladder (process → RPC → Arrow data-plane → FFI → WASM component) and verified tool
status, see [cross-language-interop.md](./cross-language-interop.md).

Contract types:

- `schemas/*.json` (JSON Schema 2020-12) or `schemas/*.proto` are the SSoT.
- Generated per-language types live in committed `gen/` dirs.
- Every `gen/` dir gets a **drift gate**: a task that regenerates into a temp dir and
  byte-diffs against the committed copy (`moon run contracts:check`).
- Bindings carry **parity tests** against the core (count them: "140/140 bit parity" is a
  task output, not a vibe).
- Proto SSoT: gate with `buf breaking` and **pick the category deliberately** — `FILE`
  (source-level, strictest) vs `PACKAGE` vs `WIRE_JSON` vs `WIRE` (binary only). A field
  rename passes `WIRE` yet breaks every generated SDK.
- JSON Schema SSoT: it's a constraint language, not a type spec — codegen is lossy. Keep
  codegen-bound schemas in the constructive subset (objects + `required`, enums, arrays,
  scalars); avoid `not` / `multipleOf` / heavy `allOf`. Rust side: typify (Rust-only,
  `x-rust-type` round-trip).

## Phase 7: CLI-First Machine-Readable Surface

Anything tunable is a CLI flag; the flag/command set is the machine-readable SSoT that AI
agents introspect — not `--help` prose.

- The repo console (`packages/cli`) drives BOTH its dispatcher AND its emitted
  `cli_spec.json` (JSON Schema 2020-12) from ONE in-code `COMMANDS` table — they cannot drift.
- `moon run cli:spec-check` is the drift gate (regenerate → byte-diff).
- Errors: RFC 9457 problem+json shape where the CLI returns structured errors.
- `moon query tasks` JSON is the second machine-readable surface; together they make the
  repo agent-navigable without reading prose.

## Phase 8: GitHub Repository Setup

```bash
gh repo create <owner>/<repo> --private --source=. --push
gh repo edit <owner>/<repo> --description "<one-liner>" \
  --add-topic monorepo --add-topic polyglot --add-topic moonrepo --add-topic bun

# Labels: pkg:<project> per project + type:{bug,feature,docs,refactor,perf,ci}
gh label create "pkg:cli" --color "F7DF1E" --description "TS console"
gh label create "type:bug" --color "D73A4A" --description "Something isn't working"
# … (repeat per project/type)
```

LICENSE (MIT unless told otherwise), README with badges + quick start + project table,
git-town for branch workflow (`git config git-town.main-branch main`,
`git config git-town.sync-feature-strategy rebase`).

## Phase 9: Release Workflow (local-first)

**Local-first CI/CD is doctrine**: quality gates run locally via `moon ci` / `moon run
<project>:check` — NEVER in GitHub Actions. Actions are reserved for: semantic-release,
CodeQL, Dependabot, deployment. Releases run **locally** (`--no-ci`); private repos publish
**tags + CHANGELOG + GitHub Release only** (NO `@semantic-release/npm`).

**Pick your case first:**

- **Case A — one releasable unit** (the repo ships as a single version): stock `semantic-release`, one
  `.releaserc.yml`, tag `v${version}`. Use this for single-package repos.
- **Case B — multiple independently-versioned projects** (a real monorepo): **per-project namespaced tags**
  (`<project>/v${version}`) via **`@rimac-technology/semantic-release-monorepo`**, driven by a cosmiconfig
  **dispatcher** `.releaserc.cjs`, plus one repo-wide **umbrella** stream on stock `semantic-release`. This is
  the **operator monorepo standard** — verified in `claude-sys` (6 streams). Details below.

### Case A — single releasable unit

`.releaserc.yml` (root):

```yaml
branches: [main]
plugins:
  - - "@semantic-release/exec"
    - verifyConditionsCmd: |
        if [ -n "$(git status --porcelain)" ]; then echo "dirty tree"; exit 1; fi
  - - "@semantic-release/commit-analyzer"
    - releaseRules:
        - { type: "docs", release: "patch" }
        - { type: "chore", release: "patch" }
        - { type: "refactor", release: "patch" }
        - { type: "test", release: "patch" }
        - { type: "build", release: "patch" }
        - { type: "ci", release: "patch" }
  - "@semantic-release/release-notes-generator"
  - "@semantic-release/changelog"
  - - "@semantic-release/git"
    - assets: [CHANGELOG.md, package.json]
      message: "chore(release): ${nextRelease.version} [skip ci]"
  - "@semantic-release/github"
```

moon task (repo project):

```yaml
release-full:
  script: |
    test -z "$(git status --porcelain)" || { echo "dirty tree"; exit 1; }
    test "$(git branch --show-current)" = "main" || { echo "not on main"; exit 1; }
    bunx semantic-release --no-ci
  options: { cache: false, runFromWorkspaceRoot: true }
```

> The `@semantic-release/exec` plugin uses Lodash templates — avoid bash `${VAR:-default}`
> syntax inside exec commands.

#### Extensive release notes (surface the commit BODY, not just the subject)

**Doctrine**: every release must carry extensive, human-readable notes — a narrative
paragraph (the _why_) **and** a point-form list (the _what_). SSoT:
`~/.claude/release-notes-doctrine-CLAUDE.md`; enforced globally by the `itp-hooks`
release-notes-extensiveness-guard (hard-blocks thin `gh release` / `git tag` /
semantic-release commands).

**Gotcha**: the default `@semantic-release/release-notes-generator` (Angular preset)
renders **only each commit's subject line** — its `writerOpts.transform` drops the
body. So rich multi-paragraph Conventional-Commit bodies never reach the published
notes. To surface them you need a JS `writerOpts` (a function YAML cannot hold), so use
a **`release.config.cjs`** instead of `.releaserc.yml` (delete the YAML — cosmiconfig
finds `.releaserc.{yaml,yml}` **before** `release.config.cjs`, so a leftover YAML shadows
the JS config):

```js
// release.config.cjs — body-preserving notes. The writer merges { ...commit, ...patch },
// so returning the body (and a commitPartial that prints {{body}}) surfaces it.
const COMMIT_PARTIAL_WITH_BODY =
  "…the Angular commit.hbs verbatim…\n{{~#if body}}\n\n{{body}}\n{{~/if}}\n";
module.exports = {
  branches: ["main"],
  plugins: [
    /* …analyzer, changelog, git, github… */
    [
      "@semantic-release/release-notes-generator",
      {
        writerOpts: {
          // reproduce the Angular preset's transform (type→"Features"/…, scope, subject
          // autolink, ref de-dup) and add `body: commit.body` to the returned object
          transform: (commit, context) => ({
            /* …preset fields…, */ body: commit.body,
          }),
          commitPartial: COMMIT_PARTIAL_WITH_BODY,
        },
      },
    ],
  ],
};
```

> **Reference implementation** (copy this, don't re-derive): `cc-skills`
> `release.config.cjs` — the full verbatim commit template, the faithful
> body-preserving transform, and the lodash-`${nextRelease.version}`-placeholder
> handling, pinned by `test/release-config-body-surfacing.test.ts`. For the manual /
> per-release path (or repos that skip the JS config), `mise run release:augment --
--tag <tag> --notes-file <path>` edits the GitHub Release through the same
> extensiveness gate (`scripts/augment-release-notes.mjs`).

### Case B — per-project monorepo releases (the standard)

**Why a fork.** Stock semantic-release has **no path filter** — its `commitPaths` option is silently
**ignored** (upstream semantic-release#1279 / #1212), so a naive per-project config computes its version off
the **whole repo**. `@rimac-technology/semantic-release-monorepo` fixes this: its `modifyContextCommits` tags
each commit with a `filePaths` array (from `git diff-tree`) and then calls a **`processCommits(commits)`** hook
from your config — keep only the commits that touched this project's folder, and the version is scoped correctly.
(It also auto-detects npm/yarn workspaces via `npm query .workspace`, but that returns null on a non-workspace
repo — so we drive scoping **entirely** through `processCommits`, which works from the repo root with no
workspaces.)

**Why a dispatcher.** semantic-release v25's `--extends <file.yml>` cannot load a YAML path (it `require()`s it,
and require has no YAML loader). So keep **one YAML per stream** (`.releaserc-<profile>.yml`) and select it with a
`RELEASE_PROFILE` env var from a cosmiconfig-discovered `.releaserc.cjs`, which also **derives `processCommits`
from each profile's `commitPaths`** (DRY: the same `commitPaths` list documents intent AND enforces scope):

```js
// .releaserc.cjs — cosmiconfig dispatcher. RELEASE_PROFILE selects the stream.
// Per-project streams (with commitPaths) run the `semantic-release-monorepo` bin;
// the umbrella (no commitPaths) runs the stock `semantic-release` bin.
const fs = require("node:fs");
const path = require("node:path");
const yaml = require("js-yaml");

const profile = process.env.RELEASE_PROFILE || "repo";
const file = path.join(__dirname, `.releaserc-${profile}.yml`);
if (!fs.existsSync(file))
  throw new Error(`unknown RELEASE_PROFILE '${profile}' (${file})`);

const config = yaml.load(fs.readFileSync(file, "utf8"));

// Scope this stream to its own folder: the monorepo fork calls config.processCommits(commits),
// where each commit carries a filePaths array. Keep only commits under one of the commitPaths dirs.
if (Array.isArray(config.commitPaths) && config.commitPaths.length > 0) {
  const prefixes = config.commitPaths.map(
    (p) => p.replace(/\*+$/, "").replace(/\/+$/, "") + "/",
  );
  config.processCommits = (commits) =>
    (commits || []).filter((c) =>
      (c.filePaths || []).some((fp) =>
        prefixes.some((pre) => fp.startsWith(pre)),
      ),
    );
}
module.exports = config;
```

**Per-project stream** `.releaserc-<project>.yml` (slash tag + `commitPaths` + exec preflight/push; `github`
assets optional):

```yaml
tagFormat: "<project>/v${version}" # namespaced → no collision with sibling projects or the umbrella
commitPaths: ["packages/<project>/**"] # the dispatcher turns this into processCommits
branches: [main]
plugins:
  - [
      "@semantic-release/commit-analyzer",
      { preset: conventionalcommits, releaseRules: *rules },
    ]
  - [
      "@semantic-release/release-notes-generator",
      { preset: conventionalcommits },
    ]
  - - "@semantic-release/exec"
    - verifyConditionsCmd: "./scripts/release-preflight.sh" # clean tree + on main + token
      successCmd: "git push --follow-tags origin main"
  - [
      "@semantic-release/changelog",
      { changelogFile: packages/<project>/CHANGELOG.md },
    ]
  - - "@semantic-release/git"
    - assets: [packages/<project>/CHANGELOG.md, packages/<project>/package.json]
      message: "chore(release): <project> ${nextRelease.version} [skip ci]"
  - ["@semantic-release/github", { assets: [] }]
```

The **umbrella** `.releaserc-repo.yml` is the same minus `commitPaths` + `tagFormat: "v${version}"` — it runs the
**stock** `semantic-release` bin over the whole repo (so config/doc commits that touch no project still cut a repo
release). A `fix(x):` under a project advances BOTH that project's tag and the umbrella — correct, the repo did change.

**moon tasks** — umbrella uses `semantic-release`; every per-project stream uses `semantic-release-monorepo`:

```yaml
# repo (umbrella) project moon.yml
release-preflight:
  {
    script: "./scripts/release-preflight.sh",
    options: { cache: false, runFromWorkspaceRoot: true },
  }
release-dry:
  {
    script: "RELEASE_PROFILE=repo npx semantic-release --no-ci --dry-run",
    deps: ["repo:release-preflight"],
    options: { cache: false, runFromWorkspaceRoot: true },
  }
release:
  {
    script: "RELEASE_PROFILE=repo npx semantic-release --no-ci",
    deps: ["repo:release-preflight"],
    options: { cache: false, runFromWorkspaceRoot: true },
  }

# <project> project moon.yml (note the -monorepo bin)
release-dry:
  {
    script: "RELEASE_PROFILE=<project> npx semantic-release-monorepo --no-ci --dry-run",
    deps: ["repo:release-preflight"],
    options: { cache: false, runFromWorkspaceRoot: true },
  }
release:
  {
    script: "RELEASE_PROFILE=<project> npx semantic-release-monorepo --no-ci",
    deps: ["repo:release-preflight"],
    options: { cache: false, runFromWorkspaceRoot: true },
  }
```

**Gotchas (all verified):**

- **Install the fork with `npm i -D --ignore-scripts`** — its `husky` prepare-script errors on a non-workspace root.
- **Fork CLI builds `tty.WriteStream(1)`** → run it to a **terminal, pipe, or `| tee`**; a direct `> file.log`
  redirect throws `ERR_TTY_INIT_FAILED` (harmless — `moon run` and bare terminal runs are unaffected).
- **Always `*:release-dry` first.** A correct dry-run shows a project ignoring commits outside its `commitPaths`
  (e.g. hundreds of repo commits since a `<project>/v*` tag → "no relevant changes" when none touched the folder).
- **Namespaced tags need a baseline.** Seed the first `<project>/v<x>` tag (or let the first release start at the
  fork's default) so `Found N commits since last release` counts from the right point.
- Preflight sources the GitHub token from the environment (never argv/log); mint a **dedicated fine-grained PAT**
  (`gh-tools:gh-fine-grained-pat`) scoped to Contents+Releases and store it in the vault, not `gh auth`.

## Testing Patterns by Language

| Language       | Runner          | Invocation (from repo root)                                                                               |
| -------------- | --------------- | --------------------------------------------------------------------------------------------------------- |
| TS/Bun         | `bun:test`      | `moon run <proj>:test` → `bun test`                                                                       |
| Python         | pytest          | `uv run --extra dev -p <version> pytest <path>` (NEVER bare `uv run pytest` — dev extras get pruned)      |
| Rust           | cargo           | `cargo test` (pure-Rust cores; pyfunction wrappers excluded from link)                                    |
| Bindings       | parity          | dedicated parity suites vs the language-neutral SSoT (bit-equal floats: both-NaN or `==`)                 |
| Browser assets | playwright-core | headless guards as moon tasks (containment, parity, contract); golden-pixel only if single-machine-pinned |

## Doctrine Appendix (hard-won, cross-repo)

1. **Process-storm prevention**: no `exec()`-style subprocess templating in any env layer;
   PID-specific kills (never `pkill -f`); shims PATH in `~/.zshenv` only.
2. **Hub-and-spoke CLAUDE.md**: root = link farm; every directory with behavior gets a
   spoke; update spokes, not the hub.
3. **Append-only research/docs discipline** (if the repo hosts findings): corrections are
   new sibling files, never retro-edits; sha256 sidecars on canonical artifacts.
4. **Vendored third-party assets**: pinned copy in a `vendor/` dir + sha256 sidecar +
   fail-loud verify task. No CDN loads in committed pages.
5. **Version strings live in manifests only** (Cargo.toml / pyproject.toml / package.json);
   docs use `<version>` placeholders or an `SSoT-OK` escape hatch.
6. **Inline suppressions** (`# noqa`, `# type: ignore`, `// biome-ignore`) require codes +
   justification, or use config-level overrides; bare suppressions are banned by hooks.
7. **SR&ED commit trailers** (optional, Canada CRA): `SRED-Type:` / `SRED-Claim:` trailers +
   the `sred-commit-guard` hook from itp-hooks — see the legacy reference's SR&ED section,
   which remains current.

## Success Criteria

- [ ] `proto use` installs every pin; `proto --version` + `moon --version` resolve from shims
- [ ] `moon query projects` lists every registered project with tags
- [ ] Every project answers `moon run <proj>:check` green
- [ ] `moon ci` runs the affected pipeline without error
- [ ] `bun install` resolves workspaces; `bun test` green where TS exists
- [ ] Contracts: `gen/` committed + drift gate green; parity suites green
- [ ] `cli_spec.json` emitted + `spec-check` green
- [ ] Root CLAUDE.md hub + one spoke per project, all links valid
- [ ] GitHub repo decorated (description, topics, labels, LICENSE, README)
- [ ] Release wired: case A → `moon run repo:release-full`; case B → per-project `<project>:release-dry` scopes to
      its own `commitPaths` (a dry-run ignores commits outside the folder) + the umbrella covers the whole repo
- [ ] Nx-convergence rules honored (explicit projects, uniform task names, tags, declared outputs, orchestrator-free scripts)

## Related Resources

- [moonrepo docs](https://moonrepo.dev/docs) · [proto docs](https://moonrepo.dev/docs/proto) · [Bun docs](https://bun.sh/docs)
- [Nx docs](https://nx.dev/) — the convergence target; revisit when repo > ~30 projects or remote caching/distributed execution pays
- Legacy bootstrap (Pants + mise): `itp/skills/mise-tasks/references/bootstrap-monorepo.md`
- `itp:semantic-release` skill — release automation deep dive (single-unit case A)
- Per-project monorepo releases (case B): Phase 9 above — `@rimac-technology/semantic-release-monorepo` + the
  `.releaserc.cjs` dispatcher. Reference implementation: `claude-sys` (6 streams, verified).
- JSON Schema 2020-12 · RFC 9457 problem+json · Conventional Commits
