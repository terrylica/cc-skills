# mise Plugin

> User-global mise workflow commands — run release pipelines, check environment status, and discover tasks across any repo.

## Commands

| Command                  | Purpose                                                          | Flags                      |
| ------------------------ | ---------------------------------------------------------------- | -------------------------- |
| `/mise:run-full-release` | Run the current repo's mise release pipeline                     | `--dry`, `--status`        |
| `/mise:show-env-status`  | Show mise environment: tools, env vars, tasks, release readiness | —                          |
| `/mise:list-repo-tasks`  | List mise tasks grouped by namespace with dependencies           | `[namespace]`              |
| `/mise:sred-commit`      | Create a git commit with SR&ED (CRA tax credit) trailers         | `[commit message summary]` |

## Command Naming Convention

All mise plugin commands use **3-4 hyphenated words** for maximum readability:

| Pattern                 | Example            | Structure               |
| ----------------------- | ------------------ | ----------------------- |
| `verb-qualifier-object` | `run-full-release` | action + scope + target |
| `verb-object-context`   | `show-env-status`  | action + what + domain  |
| `verb-scope-object`     | `list-repo-tasks`  | action + where + what   |

## Self-Bootstrapping Release

When `/mise:run-full-release` is invoked in a repo **without** mise release tasks, it conducts a thorough audit:

1. **Detect ecosystem**: Python, Rust, Node, mixed (via `pyproject.toml`, `Cargo.toml`, `package.json`)
2. **Detect packaging**: PyPI, npm, crates.io, GitHub Releases only
3. **Detect credentials**: `GH_TOKEN`, `UV_PUBLISH_TOKEN`, 1Password items
4. **Detect build needs**: cross-compilation, platform wheels, sdist, Docker
5. **Scaffold** `.mise/tasks/release/` customized to the repo's needs
6. **Ensure SSoT**: all credentials in `[env]`, all tools in `[tools]`

### Reference Templates

- `docs/RELEASE.md` — 4-phase release workflow guide
- cc-skills' `.mise/tasks/release/` — working template (preflight, version, sync, verify, full, dry, status)

## What This Plugin Does NOT Do

This plugin **runs** existing mise tasks. It does not teach how to author mise configurations. For authoring patterns:

- `mise-tasks` skill — task orchestration with `[tasks]`, dependencies, DAGs
- `mise-configuration` skill — environment SSoT with `[env]`, `[tools]`, templates

## Future Skills

The `skills/` directory is reserved for patterns that emerge across 5+ repos:

- `release-task-bootstrap` — scaffold standard 4-phase release DAG
- `dev-quality-pipeline` — scaffold fmt/lint/test/typecheck tasks
- `mise-configuration` — migration from current location
- `mise-tasks` — migration from current location
