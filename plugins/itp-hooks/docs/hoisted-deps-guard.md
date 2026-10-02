# hoisted-deps-guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md). Hook: [`pretooluse-hoisted-deps-guard.ts`](../hooks/pretooluse-hoisted-deps-guard.ts), subhook `hoisted-deps-guard` of the [PreToolUse Write/Edit orchestrator](./pretooluse-write-edit-orchestrator.md) (timeout 4000 ms). ADR: [/docs/adr/2026-01-22-pyproject-toml-root-only-policy.md](/docs/adr/2026-01-22-pyproject-toml-root-only-policy.md).

## Policies

Applies to a Write or Edit of any path ending in `pyproject.toml`. The git root comes from `git rev-parse --show-toplevel` in the file's directory (falling back to the working directory when that directory does not exist yet). The policies are checked in order and the first violation denies:

| #   | Tag                     | Denies when                                                                                                                                        |
| --- | ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `[PYPROJECT-ROOT-ONLY]` | the `pyproject.toml` is not at the git root, unless it is a maturin/PyO3 crate (below)                                                             |
| 2   | `[PATH-ESCAPE]`         | a `[tool.uv.sources]` `path = …` in the new text resolves outside the git root                                                                     |
| 3   | `[HOISTED-DEPS]`        | the file is under `packages/<name>/`, `libs/<name>/`, `services/<name>/` or `apps/<name>/` and the new text declares a `[dependency-groups]` table |

Policies 2 and 3 read the new text only (`content` for Write, `new_string` for Edit). When no git root can be resolved, policies 1 and 2 are skipped.

**Maturin carve-out** (policy 1): a `pyproject.toml` with a sibling `Cargo.toml` is allowed when the new text declares `build-backend = "maturin"`, or the sibling `Cargo.toml` declares a `cdylib` crate type. maturin reads both files from the crate directory, so this layout is required, not fragmentation.

Each deny reason explains the fix: a `[tool.uv.workspace]` member list in the root, a git or `workspace = true` source instead of an escaping path, and dev dependencies hoisted to the root `[dependency-groups]`.

There is no escape-hatch marker.

## Code

The classifier is `classifyHoistedDepsGuardForOrchestrator`. The file also runs standalone (`bun pretooluse-hoisted-deps-guard.ts < payload.json`) through its `import.meta.main` guard; tests are in [`pretooluse-hoisted-deps-guard.test.mjs`](../hooks/pretooluse-hoisted-deps-guard.test.mjs).
