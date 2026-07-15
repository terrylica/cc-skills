# Evolution Log

> **Convention**: Reverse chronological order (newest on top, oldest at bottom). Prepend new entries.

---

## 2026-07-14: Phase 9 — per-project monorepo releases via the Rimac fork (case A/B split)

**What changed**: Phase 9 (Release Workflow) now splits into **case A** (one releasable unit — stock
`semantic-release`, unchanged) and **case B** (multiple independently-versioned projects — the monorepo standard).
Case B documents: **`@rimac-technology/semantic-release-monorepo`** (because stock semantic-release silently ignores
`commitPaths` — upstream #1279/#1212, so a naive per-project config versions off the whole repo); a cosmiconfig
`.releaserc.cjs` **dispatcher** keyed by `RELEASE_PROFILE` that **derives each stream's `processCommits` from its
`commitPaths`** (one list, both documents intent and enforces scope); slash-namespaced tags `<project>/v${version}`;
a repo-wide **umbrella** stream on stock semantic-release; per-project moon `release`/`release-dry` tasks on the
`-monorepo` bin gated by `repo:release-preflight`. Root `package.json` devDeps extended with the fork +
`conventional-changelog-conventionalcommits` + `js-yaml` + analyzer/notes/exec. Documented gotchas: install with
`npm i -D --ignore-scripts` (husky), the fork CLI's `tty.WriteStream(1)` breaks on `> file` redirect (use a pipe/
`tee`), always `release-dry` first, seed a baseline tag, source the token from a dedicated fine-grained PAT.

**Why**: USER DIRECTIVE 2026-07-14 — after adopting this pattern in `claude-sys` (6 streams, scoping verified via
dry-run: 389 commits since `typeless/v*` all outside `typeless/**` → correctly "no release"), standardize it so all
future monorepo builds configure releases the same way. The fork's mechanism was confirmed by reading its
`dist/cli.js` (`modifyContextCommits` → `semanticConfig.options.processCommits`), not assumed.

**Files affected**: `SKILL.md` (new "Releases (local-first)" section), `references/bootstrap-monorepo.md` (Phase 9
rewrite, root `package.json` devDeps, migration map, Success Criteria, Related Resources). Reference implementation:
`claude-sys` (`.releaserc.cjs` + `.releaserc-*.yml`).

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
