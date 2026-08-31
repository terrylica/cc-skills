# itp-hooks Spoke Index

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — the annotated index of every doc in this directory. Moved out of the hub 2026-08-30 (the hub sat at 37.8k of a 40k hard character limit, and prettier's table repadding pushed any single-row edit over it).

Each spoke is the SSoT for its own subject. The hub carries only the hook inventory and the invariants; every narrative lives here or below.

## Orchestrators and lifecycle

| Spoke                                                                              | Topic                                                                              |
| ---------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| [pretooluse-write-edit-orchestrator.md](./pretooluse-write-edit-orchestrator.md)   | Iter-84→91 PreToolUse orchestrator arc                                             |
| [posttooluse-write-edit-orchestrator.md](./posttooluse-write-edit-orchestrator.md) | Iter-93+ PostToolUse orchestrator arc                                              |
| [posttooluse-reminder.md](./posttooluse-reminder.md)                               | The standalone PostToolUse reminder hook                                           |
| [stop-hooks.md](./stop-hooks.md)                                                   | Stop-hook schema correctness (iter-66 trinity + iter-69 pentad, silent-drop rules) |
| [plan-mode-detection.md](./plan-mode-detection.md)                                 | Plan-mode detection signals + which hooks honor them                               |
| [read-only-command-detection.md](./read-only-command-detection.md)                 | Read-only command detection (+ SSH remote-bypass semantics)                        |

## Guards — safety and destructive-action prevention

| Spoke                                                                  | Topic                                                                                                                                                                                                                                                             |
| ---------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [cwd-deletion-guard.md](./cwd-deletion-guard.md)                       | CWD deletion guard patterns + git-aware guidance                                                                                                                                                                                                                  |
| [git-worktree-guard.md](./git-worktree-guard.md)                       | Worktree-per-branch enforcement: blocked vs allowed matrix, git-town/gh coverage, escape hatch                                                                                                                                                                    |
| [process-storm-guard.md](./process-storm-guard.md)                     | Fork-bomb / process-storm pattern prevention                                                                                                                                                                                                                      |
| [subprocess-resource-guard.md](./subprocess-resource-guard.md)         | **Memory + concurrency bounds for hook subprocesses** — after `ty` hit 73 GB across 4 concurrent runs and froze the machine (2026-07-30). Why a timeout cannot contain a memory storm, and why every macOS memory rlimit returns EINVAL                           |
| [fake-data-guard.md](./fake-data-guard.md)                             | Fake/placeholder data prevention in production code                                                                                                                                                                                                               |
| [secret-and-pii-exposure-guard.md](./secret-and-pii-exposure-guard.md) | The 23-repo credential/PII incident, the three credential detectors and two PII detectors with their negative cases, why the credential half blocks and the PII half only reminds, both escape hatches, and the trufflehog verified-mode change to the audit gate |

## Guards — code, config and toolchain policy

| Spoke                                                            | Topic                                                                                                                                                             |
| ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [file-size-guard.md](./file-size-guard.md)                       | File-size thresholds, exclusions, configuration                                                                                                                   |
| [inline-ignore-policy.md](./inline-ignore-policy.md)             | Inline-ignore hierarchy + detection patterns                                                                                                                      |
| [hoisted-deps-guard.md](./hoisted-deps-guard.md)                 | pyproject.toml root-only + path-escape + sub-package dependency-groups policies                                                                                   |
| [mise-hygiene-guard.md](./mise-hygiene-guard.md)                 | mise.toml secrets detection + size hygiene                                                                                                                        |
| [uv-enforcement-guard.md](./uv-enforcement-guard.md)             | Non-UV Python package operations blocked (SSH-to-remote bypasses, by directive)                                                                                   |
| [pyi-stub-guard.md](./pyi-stub-guard.md)                         | Top-level definitions in Python `__init__` files blocked                                                                                                          |
| [python-preference-nudge.md](./python-preference-nudge.md)       | Python-preference nudge + per-file `python-allowlist.toml` (reason-gated, no blanket suppression)                                                                 |
| [gpu-optimization-guard.md](./gpu-optimization-guard.md)         | GPU optimization enforcement (6 policy checks)                                                                                                                    |
| [native-binary-guard.md](./native-binary-guard.md)               | Launchd native-binary enforcement + TCC anti-patterns                                                                                                             |
| [version-guard.md](./version-guard.md)                           | Hardcoded-version blocker for markdown                                                                                                                            |
| [skill-plugin-root-guard.md](./skill-plugin-root-guard.md)       | Why `CLAUDE_PLUGIN_ROOT` works in manifests but not in skills, the three deniable shapes, the `cc-plugin-root` resolver, and why iter-78 was retired the same day |
| [layer3-stripped-path-guard.md](./layer3-stripped-path-guard.md) | The retired iter-78 guard: dead premise, false-positive-only behaviour, why it is kept unregistered as the iter-107 reference impl                                |

## Job orchestration and process discipline

| Spoke                                                            | Topic                                                                                                                              |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| [pueue-reminder.md](./pueue-reminder.md)                         | Pueue reminder detection patterns + exceptions                                                                                     |
| [pueue-local-guard.md](./pueue-local-guard.md)                   | Pueue commands must target the local daemon                                                                                        |
| [pueue-wrap-guard.md](./pueue-wrap-guard.md)                     | Auto-wrapping long-running commands with pueue; why it MUST stay the last PreToolUse entry (iter-61 audit)                         |
| [cargo-tty-guard.md](./cargo-tty-guard.md)                       | Cargo TTY suspension prevention (full guide: [/docs/cargo-tty-suspension-prevention.md](/docs/cargo-tty-suspension-prevention.md)) |
| [memory-efficiency-reminder.md](./memory-efficiency-reminder.md) | Memory-efficiency reminder + iter-98 silent-drop fix                                                                               |
| [mini-inngest-doctrine.md](./mini-inngest-doctrine.md)           | Mini-Inngest doctrine hook: nudge toward Mac Mini + Inngest for external/web-facing services; trigger heuristics, escape hatch     |

## Linters, type checkers and correctness

| Spoke                                                              | Topic                                                         |
| ------------------------------------------------------------------ | ------------------------------------------------------------- |
| [code-correctness-philosophy.md](./code-correctness-philosophy.md) | What is/isn't checked and why                                 |
| [ty-type-checker.md](./ty-type-checker.md)                         | ty configuration, gate files, silent-failure handling         |
| [tsc-type-check.md](./tsc-type-check.md)                           | tsc project-scoped type check (native TypeScript 7+ compiler) |
| [oxlint-check.md](./oxlint-check.md)                               | oxlint correctness + suspicious lint on JS/TS edits           |
| [biome-lint.md](./biome-lint.md)                                   | biome complementary-to-oxlint lint on JS/TS edits             |
| [lsp-configuration.md](./lsp-configuration.md)                     | LSP disabled-state config (process-storm history)             |
| [ssot-principles.md](./ssot-principles.md)                         | SSoT/DI reminder hook + ast-grep rules                        |

## Documentation, terminology and outbound content

| Spoke                                                                          | Topic                                                                                                                                                                                                       |
| ------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [vale-terminology-enforcement.md](./vale-terminology-enforcement.md)           | Vale architecture, hook chain, duplicate detection                                                                                                                                                          |
| [markdown-table-guard.md](./markdown-table-guard.md)                           | GFM table structural guard: per-edit detector + Stop-hook prettier gate + manual sweep; why pipe-escaping isn't auto-fixable                                                                                |
| [markdown-hard-wrap-reminder.md](./markdown-hard-wrap-reminder.md)             | The GFM surface split (a repo `.md` reflows, release/issue/PR bodies render `<br>`), why the reminder is net-new, the four hard-wrap boundaries and which guard owns each, and the badge-row false positive |
| [release-notes-extensiveness-guard.md](./release-notes-extensiveness-guard.md) | Release-notes extensiveness hard-block: interception points, thresholds, fail-open rules, escape hatch; doctrine SSoT link                                                                                  |
| [gmail-body-guard.md](./gmail-body-guard.md)                                   | Gmail draft body guard: blocks a `gmail draft` with a hard-wrapped body or raw markdown; wrap + literal-markdown heuristics, shared libs, escape hatch, fail-open                                           |
| [readme-pypi-links.md](./readme-pypi-links.md)                                 | PyPI badge/link consistency in READMEs                                                                                                                                                                      |
| [pushover-budget-reminder.md](./pushover-budget-reminder.md)                   | Pushover official limits SSoT (re-verified 2026-06-11: ttl, per-account quota) + detection                                                                                                                  |
| [invented-fallback-reminder.md](./invented-fallback-reminder.md)               | Official-values nudge on net-new invented fallback display values (`Unknown`/`N/A`/`?`); Bash inline coverage, scratch exemption, escape hatch                                                              |
| [headless-claude-p.md](./headless-claude-p.md)                                 | Headless `claude -p` doctrine and guard: `stream-json` needs `--verbose`, `CLAUDE_EFFORT=` is not an input, out-of-enum `--effort` is silently ignored, bare `-p` defaults to `high`                        |
