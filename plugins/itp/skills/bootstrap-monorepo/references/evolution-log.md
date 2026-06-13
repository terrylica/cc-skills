# Evolution Log

> **Convention**: Reverse chronological order (newest on top, oldest at bottom). Prepend new entries.

---

## 2026-06-12: Total refactor — Pants + mise → moon + proto + Bun (Nx-convergent)

**What changed**: The skill is no longer a redirect into `itp:mise-tasks`. It now carries its
own canonical reference (`references/bootstrap-monorepo.md`) on the new stack: proto pins
(`.prototools`), moon orchestration (explicit `projects:` map, per-project `moon.yml`, uniform
`lint/fmt/test/check` vocabulary, `moon ci` affected pipeline), Bun-first TypeScript control
plane, engines (Rust/Python/Go) behind language-neutral contracts (JSON Schema 2020-12 /
proto) with drift gates + parity tests, CLI-first `cli_spec.json`, local-first CI/CD, and
explicit **Nx-convergence design rules** so a later `nx init` is mechanical.

**Why**: USER DIRECTIVE 2026-06-12 — make the scaffold totally domain-agnostic and conform to
the proven production conventions of the `opendeviationbar-patterns` mise→moon/proto migration
(the living exemplar: moon project graph incl. buildless browser assets as first-class
projects, sha256-pinned vendoring, PyO3 pure-core/thin-wrapper test pattern, `uv run
--extra dev` gotcha, process-storm-safe shims in `~/.zshenv`).

**Files affected**: `SKILL.md` (rewritten), `references/bootstrap-monorepo.md` (new
canonical), `../mise-tasks/references/bootstrap-monorepo.md` (deprecation banner added; its
SR&ED section remains current and is referenced).

---

## 2026-02-26: Initial Evolution Log

**Status**: Skill is in use and maintained. Track improvements here.

### Purpose

This evolution log tracks updates to the skill. Each entry should note:

- What changed (content, structure, tooling)
- Why it changed (bug fix, feature request, best practice)
- Files affected

### How to Use

1. When updating SKILL.md or references, add an entry here with the date
2. Keep entries reverse-chronological (newest first)
3. Link to ADRs or GitHub issues when relevant
4. Reference specific line changes when helpful

---
