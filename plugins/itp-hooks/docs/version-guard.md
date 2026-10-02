# version-guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md). Hook: [`pretooluse-version-guard.ts`](../hooks/pretooluse-version-guard.ts), subhook `version-guard` of the [PreToolUse Write/Edit orchestrator](./pretooluse-write-edit-orchestrator.md) (first in the registry, timeout 3000 ms).

## What it blocks

A Write or Edit of a `.md` file whose new text (`content` for Write, `new_string` for Edit) contains a hardcoded version. The version belongs only in `Cargo.toml`, `pyproject.toml` or `package.json`; docs use a `<version>` placeholder or a registry link. A placeholder elsewhere in the same text does not exempt it.

Detected shapes (`HARDCODED_VERSION_DETECTION_REGEX_PATTERNS`):

Below, `N` stands for a run of digits; the spoke avoids literal versions so editing it is never blocked.

- `= "N.N.N"` (TOML/Rust), `==N.N.N` and `~=N.N.N` (Python), `"version": "N.N.N"` (JSON)
- `Version: N.N.N` and `**Version**: N.N.N` in prose
- `vN.N.N`, but not `vN.N.N+`, which is a minimum requirement
- pre-releases `N.N.N-alpha`, `-beta` or `-rc` (optionally `.N`), and calendar versions `YYYY.M.D`

Two-segment versions, `>=` constraints and XML `version="N.N"` boilerplate are deliberately not matched, and fenced `xml`/`html`/`plist` code blocks are stripped before matching.

## Exempt paths

`HARDCODED_VERSION_EXEMPT_FILE_PATH_REGEX_PATTERNS`: any dot-prefixed directory (`.claude/`, `.github/`, `.planning/`, …), paths containing `CHANGELOG`, `MIGRATION`, `HISTORY` or `ADR-<n>`, directories `archive/`, `milestones/`, `planning/`, `plans/`, `reports/`, `output/`/`outputs/`, `adr/`, `development/`, `node_modules`, crate-level `crates/<name>/README.md`, anything under `/tmp/`, and `LOOP_CONTRACT*.md`.

It is also skipped in plan mode ([plan-mode-detection.md](./plan-mode-detection.md); ADR [/docs/adr/2026-02-05-plan-mode-detection-hooks.md](/docs/adr/2026-02-05-plan-mode-detection-hooks.md)).

## Escape hatch

`SSoT-OK` anywhere in the new text (for example `# SSoT-OK` or `<!-- SSoT-OK -->`), case-sensitive and file-wide, detected by the shared marker helper in [`lib/escape-hatch-marker-detection-iter107.ts`](../hooks/lib/escape-hatch-marker-detection-iter107.ts). The [ssot-principles](./ssot-principles.md) reminder honours the same token.

## Code

The classifier is `classifyVersionGuardForOrchestrator`. The file also runs standalone (`bun pretooluse-version-guard.ts < payload.json`) through its `import.meta.main` guard. See [HOOKS.md "In-Process Orchestrators"](../../../docs/HOOKS.md#in-process-orchestrators).
