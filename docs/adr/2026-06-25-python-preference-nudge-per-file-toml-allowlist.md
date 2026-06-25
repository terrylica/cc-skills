---
status: accepted
date: 2026-06-25
decision-maker: Terry Li
consulted: [Explore, general-purpose]
research-method: multi-agent
clarification-iterations: 2
perspectives: [DeveloperGuidance, PolicyEnforcement, MachineReadableSSoT]
---

# ADR: Python-preference nudge with a per-file TOML allowlist

## Context and Problem Statement

The user's language-selection doctrine (`~/.claude/principles-CLAUDE.md` §"Language selection default") prefers **Bun/TypeScript over Python** (and Go over Rust) for greenfield code, reserving Python for genuine SOTA-native lanes (ML / data-science / quant) or an existing Python convention. Nothing surfaced that preference to an AI coding agent at the moment it wrote a `.py` file, so greenfield Python crept in silently.

The user asked for a reminder that fires **everywhere** whenever a Python file is written/edited, with these constraints (from clarification):

1. **No blanket suppression.** Being inside a Python project — even legacy — does NOT exempt its files. "Every single Python file must be individually allowed."
2. Suppression must be **explicit, per-file, reason-gated**, and live in a **centralized machine-readable TOML allowlist** (matches the user's CLI-first machine-readable-SSoT doctrine).
3. Nudge **as frequently as possible** — every `.py` write/edit that isn't allowlisted.
4. Integrity: **reason-gated, PR-reviewed** (no content-hash pinning; editing an already-listed file stays silent).

## Decision

Add a PostToolUse subhook (`posttooluse-python-preference-nudge.ts`) to the **itp-hooks iter-93 PostToolUse orchestrator**. On every `Write`/`Edit` of a `.py` file it emits a non-blocking, Claude-visible `additional_context` reminder **unless** the file is explicitly allowed — with a non-empty `reason` — in an ancestor `python-allowlist.toml`.

### Why PostToolUse (not PreToolUse)

`hooks.json` documents a marketplace-wide invariant that **PreToolUse `additionalContext` is silently dropped** (iter-90 audit / GH #15664). The proven Claude-visible non-blocking channel is the iter-93 PostToolUse orchestrator, which merges subhook `additional_context` payloads into one `{decision:"block", reason}` emission (non-blocking — the tool already ran). Inlining a classifier into the existing orchestrator costs ~0ms cold-start and needs **no `hooks.json` change**. Because itp-hooks runs in every project, the nudge is global by construction.

### Allow mechanism (the only way to silence the nudge for a file)

A centralized **`python-allowlist.toml`** discovered by walking up from the edited file to the repo root (stops at the first `.git`, `$HOME`, or filesystem root). A file is allowed iff some ancestor allowlist has an `[[allow]]` entry whose `path` (resolved relative to that allowlist's directory) matches the file **and** whose `reason` is a non-empty trimmed string. Lineage: lychee `.lycheeignore`, gitleaks `[allowlist]`, CODEOWNERS — centralized, PR-reviewable, schema-backed (`schemas/python-allowlist.schema.json`, JSON Schema 2020-12).

```toml
# python-allowlist.toml
[[allow]]
path   = "services/etl/legacy_load.py"   # relative to this file's directory
reason = "pandas-native ETL; migration tracked"
issue  = "eon/mono#1234"                  # optional
```

## Considered Alternatives (prior-art survey)

| Mechanism                                                  | Lineage                                                                                | Why not chosen                                                                                                                   |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| **Inline pragma** (`# python-allow: reason`)               | ruff `# noqa`, detect-secrets `# pragma: allowlist secret`, eslint-disable `-- reason` | Self-documenting but an agent can add the marker itself; the user wanted one reviewable governance surface.                      |
| **Content-hash baseline**                                  | detect-secrets `.secrets.baseline`                                                     | Strongest tamper-evidence, but every legit edit invalidates the allow → high churn. User chose reason-gated/PR-reviewed instead. |
| **Glob/directory allow**                                   | ruff per-file-ignores, CODEOWNERS                                                      | Too coarse — violates "every single file individually".                                                                          |
| **Centralized exact-path TOML + required reason** (CHOSEN) | lychee, gitleaks, CODEOWNERS                                                           | Individualized, reviewable, machine-readable, low churn.                                                                         |

## Consequences

- **Positive:** matches the machine-readable-SSoT doctrine; one reviewable file per directory; hard to expand silently (visible diff); zero new hook process; global automatically.
- **Negative / accepted:** after rollout, editing any `.py` in existing repos nudges until allowlisted — this is the explicit intent. A migration `--init` scaffolder and a CI schema-validation gate are noted as follow-ups (out of scope for v1).
- **One implicit exemption:** ephemeral throwaway scratch under a temp dir (`/tmp`, `$TMPDIR`, …) via the shared iter-124 helper — never applies to project files.
- **Stricter-than-fail-open detail:** a malformed individual allowlist file contributes ZERO entries (it does not grant blanket silence); only a truly unexpected classifier error fails open to `noop`.

## Verification

`bun test plugins/itp-hooks/hooks/posttooluse-python-preference-nudge.test.ts` (15 tests); standalone + orchestrator drive with synthetic PostToolUse JSON (unlisted→nudge, reason→silent, blank-reason→nudge, temp→silent); `bun scripts/validate-plugins.mjs`.
