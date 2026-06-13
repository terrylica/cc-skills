---
name: bootstrap-monorepo
description: Autonomous polyglot monorepo bootstrap meta-prompt on the moon + proto + Bun stack (Nx-convergent). TRIGGERS - new monorepo, new repository, polyglot setup, scaffold repo, moon proto bootstrap, monorepo from scratch.
allowed-tools: Read
disable-model-invocation: false
---

# Bootstrap Polyglot Monorepo (moon + proto + Bun, Nx-convergent)

Canonical reference lives in THIS skill:

→ **See**: [references/bootstrap-monorepo.md](references/bootstrap-monorepo.md)

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## When to Use This Skill

Use this skill when:

- Starting ANY new repository — single-language or polyglot (the structure scales down)
- Setting up a moon-orchestrated, proto-pinned, Bun/TypeScript-wired monorepo
- Wiring engines (Rust/Python/Go) behind contracts under a TS control plane
- You want the repo Nx-convergent from day one (later `nx init` is mechanical, not a restructure)

## Stack

| Tool           | Responsibility                                                                     |
| -------------- | ---------------------------------------------------------------------------------- |
| **proto**      | Toolchain versions (bun, python, rust, node, …) pinned in repo-local `.prototools` |
| **moon**       | Project graph + task orchestration + caching + affected detection (`moon ci`)      |
| **Bun**        | TS runtime for every script, CLI, glue tool, and test; root workspaces             |
| **uv / cargo** | Python / Rust engines invoked natively from moon `script:` tasks                   |

TypeScript is the control plane; other languages are engines behind language-neutral contracts (JSON Schema 2020-12 / proto) with drift gates and parity tests.

## Quick Commands

```bash
# After bootstrap:
moon ci                          # affected quality pipeline
moon run <project>:check         # one project's full gate (lint+test+drift)
moon query projects              # machine-readable project graph (agents read this)
moon query tasks                 # machine-readable task surface
proto use                        # install all .prototools pins on a fresh machine
```

## Legacy Path

Pre-2026-06 repos on **Pants + mise**: the old reference remains at
[../mise-tasks/references/bootstrap-monorepo.md](../mise-tasks/references/bootstrap-monorepo.md).
Migrate per-repo (parity-first, cut tasks over one at a time), never big-bang.

## Related Skills

- `itp:semantic-release` - Release automation (local-first; Actions only for release/CodeQL/Dependabot/deploy)
- `itp:mise-tasks` / `itp:mise-configuration` - legacy mise-era orchestration (still valid for unmigrated repos)

---

## Troubleshooting

| Issue                                                | Cause                                                  | Solution                                                                  |
| ---------------------------------------------------- | ------------------------------------------------------ | ------------------------------------------------------------------------- |
| `proto::detect::failed` for moon                     | tool installed but no version pinned                   | `proto pin --to global moon <version>` (or add to `.prototools`)          |
| `moon` not found over ssh                            | shims not on non-interactive PATH                      | export `PROTO_HOME` + shims PATH in `~/.zshenv` (NOT only `.zshrc`)       |
| Python tests "No module named pytest"                | `uv run` prunes dev extras                             | `uv run --extra dev -p <version> pytest <path>` from repo root            |
| PyO3 crate `cargo test` link errors (`_PyBool_Type`) | tests reference `#[pyfunction]` under extension-module | keep logic in pure-Rust core fns; tests call the core, wrapper stays thin |
| Task runs in wrong cwd                               | script assumes repo root                               | `options: { runFromWorkspaceRoot: true }` in the task                     |
| Guard task wrongly cached                            | moon caches by default                                 | `options: { cache: false }` on guards/parity/network tasks                |
| Commit "passed" but didn't land                      | a hook auto-fixed files and aborted                    | re-stage and retry; ALWAYS verify `git log --oneline -1` after commit     |

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If the underlying tool's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
