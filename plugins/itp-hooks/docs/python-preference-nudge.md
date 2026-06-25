# Python-preference nudge

> Spoke for `hooks/posttooluse-python-preference-nudge.ts` (inlined in the iter-93 PostToolUse orchestrator). Hub: [itp-hooks CLAUDE.md](../CLAUDE.md). ADR: [/docs/adr/2026-06-25-python-preference-nudge-per-file-toml-allowlist.md](/docs/adr/2026-06-25-python-preference-nudge-per-file-toml-allowlist.md).

## What it does

On every `Write`/`Edit` of a `.py` file, emits a **non-blocking** Claude-visible reminder that the project prefers Bun/TypeScript for greenfield code (Go/Rust per SOTA) — **unless that specific file is explicitly allowed** in a `python-allowlist.toml`. Encodes `~/.claude/principles-CLAUDE.md` §"Language selection default" at edit time.

Because itp-hooks runs in every project, the nudge is global. It is informational only (PostToolUse cannot block) and never prevents a write.

## The allowlist (the only way to silence the nudge for a file)

`python-allowlist.toml`, discovered by walking up from the edited file to the repo root (stops at the first `.git`, `$HOME`, or filesystem root). Schema: [`../schemas/python-allowlist.schema.json`](../schemas/python-allowlist.schema.json) (JSON Schema 2020-12).

```toml
# python-allowlist.toml
[[allow]]
path   = "scripts/sharpe.py"   # relative to THIS file's directory (absolute also accepted)
reason = "numpy/numba SOTA-native lane"   # required, non-empty
issue  = "eon/mono#1290"                  # optional
```

A file is **allowed** iff some ancestor allowlist has an `[[allow]]` entry whose `path` (resolved relative to that allowlist's directory) matches the file **and** whose `reason` is a non-empty trimmed string.

### Rules

- **No blanket suppression.** Being inside a Python project (even legacy) does not exempt anything — every `.py` is allowed individually.
- **Reason-gated.** A blank/whitespace-only `reason` is treated as NOT allowed.
- **Reason-gated, PR-reviewed — no hash pinning.** Editing an already-listed file stays silent (the audit gate is the human reviewing the allowlist diff).
- **Multiple allowlists compose.** In a monorepo, a nested directory can carry its own `python-allowlist.toml`; nearest-first, any ancestor match allows.

## The one implicit exemption

Ephemeral throwaway scratch under a temp dir (`/tmp`, `/private/tmp`, `/var/folders`, `$TMPDIR`, `/dev/shm`) is silent — those files are discarded so nudging is noise. Implemented via the shared iter-124 helper `isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts`. This never applies to project files.

Also skipped (not first-party source): paths containing `/.venv/`, `/venv/`, `/node_modules/`, `/site-packages/`, `/__pycache__/`, `/.git/`, `/.tox/`, `/.mypy_cache/`.

## Fail-open posture

- A **malformed individual allowlist** contributes ZERO entries — it does NOT grant blanket silence (stricter than a generic fail-open, by design).
- A truly unexpected classifier error returns `noop` (never crashes the orchestrator).

## Key functions (for editing/testing)

| Function                                                  | Purpose                                                                                                |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `classifyPythonPreferenceNudgeForPostToolUseOrchestrator` | Orchestrator entry point; applies temp-skip then evaluates.                                            |
| `evaluatePythonPreferenceNudgeIgnoringTempScratch`        | Pure gate logic (tool/ext/non-first-party/allowlist), no temp-skip — unit-testable with temp fixtures. |
| `isPythonFileExplicitlyAllowed`                           | Ancestor-allowlist resolution.                                                                         |
| `findApplicablePythonAllowlistFiles`                      | The nearest-first ancestor walk.                                                                       |
| `buildPythonPreferenceReminderMessage`                    | The reminder copy.                                                                                     |

Tests: [`../hooks/posttooluse-python-preference-nudge.test.ts`](../hooks/posttooluse-python-preference-nudge.test.ts) (15 cases).

## Follow-ups (not in v1)

- An `--init` generator that scans a repo's existing `.py` and scaffolds stub entries (blank reasons, to force human justification).
- A CI / pre-commit gate that validates `python-allowlist.toml` against the JSON Schema and flags stale paths.
