# ADR: Release-Notes Extensiveness Guard (2026-07-21)

**Date**: 2026-07-21  
**Status**: Accepted  
**Severity**: Hard block (PreToolUse deny, reason-gated escape hatch)

---

## Context

Releases produced by semantic-release default to a terse commit dump — a bare
`Bug Fixes` / `Features` list of one-line commit subjects with commit/issue
links and nothing else. That records _which commits landed_ but never the _why_:
the motivation, the essence of the change, or its impact on a reader. The
operator wants **every** release (any repo, any version bump) to carry
extensive, humanly-readable notes in **both** paragraph (narrative) **and** point
form, enforced automatically rather than by memory.

Research into the 2025 idiom (Keep a Changelog, Common Changelog, semantic-release
FAQ) converges on a hybrid: keep semantic-release + Conventional Commits for the
machinery, but adopt the Keep a Changelog human-first discipline and the Common
Changelog audit trail. The durable leverage point is the multi-paragraph
Conventional-Commit **body**, where the reasoning must exist. Note (verified on
v22.15.0): the DEFAULT semantic-release release-notes generator renders only each
commit's **subject line**, not the body — so a rich body satisfies the guard and
preserves the reasoning in git, but the published notes are made extensive by
augmenting the GitHub Release body (or customizing the generator template).

Decisions locked with the operator (AskUserQuestion): source = rich commit bodies

- augmented GitHub Release body; trigger = on release/tag; enforcement = hard
  block; scope = global (ship in `itp-hooks`).

---

## Decision

Add a global **PreToolUse Bash guard**, `pretooluse-release-notes-extensiveness-guard.ts`,
that hard-blocks (deny, exit 2) release/tag commands whose notes fail an
extensiveness bar, choosing the strongest _measurable_ criterion at each
interception point:

- `gh release create` / `gh release edit` → measure inline `--notes` /
  `--notes-file` text; require a narrative paragraph **and** ≥3 bullets.
- Annotated semver `git tag -m` / `-F` → measure the tag message; same bar.
- `semantic-release`, `npx/bunx semantic-release`, `mise run release[:*]` →
  inspect the Conventional-Commit **bodies** of releasable commits
  (`feat`/`fix`/`perf` + `BREAKING CHANGE`) since the last tag; block when they
  are collectively thin, listing the thin commits by hash.

**Key traits**:

- **Pure classifier** (`release-notes-extensiveness-patterns.ts`) split from the
  thin IO driver — mirrors the git-worktree-guard split; fully unit-tested.
- **Fail-open**: any parse/IO/git error → allow. Unresolvable notes values
  (`$(…)`, `$VAR`, unreadable `--notes-file`) → allow (cannot prove thinness).
- **Reason-gated escape hatch**: `RELEASE-NOTES-OK: <≥10-char reason>` for a
  genuinely un-narratable release; registered in the iter-111 canonical registry,
  detected via the iter-107 shared helper.
- **Tunable thresholds** as named exports at the top of the patterns file.
- **Doctrine SSoT**: `~/.claude/release-notes-doctrine-CLAUDE.md` (the mandatory
  universal format + authoring workflow), linked from every deny message.

---

## Rationale

1. **Enforce at the immutable moment.** For the semantic-release path, notes come
   from commit bodies. Inspecting those bodies at release time enforces the
   "rich commit bodies" source exactly before they become immutable notes —
   stronger than an acknowledgment prompt, and it names the thin commits.

2. **Measurable, low false-positive.** The guard blocks only concrete, measurable
   thinness. Anything it cannot resolve is allowed, so real work is never blocked
   by a parsing gap.

3. **Reuses existing infra.** Reuses `allow`/`deny`/`parseStdinOrAllow`/
   `trackHookError` from `pretooluse-helpers.ts`, `splitSegments`-free
   whole-command detection (multi-line notes must not be fragmented), and the
   iter-107 escape-hatch helper. No new utility code.

4. **Hard block with a deliberate valve.** Unlike the WebFetch guard (never
   succeeds → no hatch), a release must remain possible for genuine dep/chore
   bumps; the reason-gated marker keeps the default path "make it rich," not
   "type the token."

5. **Global by construction.** Shipping in `itp-hooks` (installed for every repo)
   satisfies the "universally applicable" goal without per-repo wiring.

---

## Consequences

- **Positive**: every release now carries a narrative + point-form summary;
  commit-body discipline is enforced where it feeds the changelog; the format is
  documented once in a global SSoT.
- **Negative / cost**: the semantic-release path shells `git log` (5–8s timeout,
  fail-open); manual hand-tags of a semver with a one-line message are now
  blocked (intended); thresholds may need tuning after real-world use (hence the
  named-export constants).
- **Placement**: registered before `pretooluse-pueue-wrap-guard.ts`, which must
  remain the last PreToolUse entry (iter-61 audit / GitHub #15897).

---

## Alternatives considered

- **Reminder-only (non-blocking)**: rejected — the operator explicitly chose a
  hard block; a passive nudge is ignorable.
- **Block the release command pending a typed acknowledgment**: weaker than
  measuring commit bodies and adds friction without proof of richness.
- **Per-repo hook / CI check**: rejected — violates the global scope decision and
  the local-first CI/CD doctrine (no GitHub Actions for gates).
