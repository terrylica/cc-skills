# mise-hygiene-guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md). Hook: [`pretooluse-mise-hygiene-guard.ts`](../hooks/pretooluse-mise-hygiene-guard.ts), subhook `mise-hygiene-guard` of the [PreToolUse Write/Edit orchestrator](./pretooluse-write-edit-orchestrator.md) (timeout 3000 ms).

## Scope

A Write or Edit of a file named exactly `mise.toml` or `.mise.toml`. `mise.local.toml` and `.mise.local.toml` are ignored, since that is where secrets belong. Skipped in plan mode ([plan-mode-detection.md](./plan-mode-detection.md)). The new text checked is `content` for Write and `new_string` for Edit.

## Policies

1. **Secrets** (Write or Edit): denies when a line assigns a quoted literal to a secret-looking key — `api_key`, `secret_key`, `access_token`, `auth_token`, `password`/`passwd`/`pwd`, `private_key`, `credential(s)`, `gh_token`, `github_token`, `npm_token`, `aws_access_key`/`aws_secret_key`, `database_password`/`db_pwd`, `encryption_key`, `signing_key` (case-insensitive, `_`/`-` optional). A line that reads the value from elsewhere is exempt: Tera `{{ read_file(…) }}`, `{{ env.X }}`, `{{ get_env(…) }}`, `{{ op_read(…) }}`, `{{ cache(…) }}`, an `op://` URI, or `doppler secrets`. The deny reason points to `.mise.local.toml` (gitignored) or a template reference.
2. **Size** (Write only, because an Edit carries only a fragment): denies a `mise.toml` over 100 lines and suggests a hub-and-spoke layout — `[env]`, `[tools]` and `[task_config]` in the root, `[tasks.*]` moved to `tasks/*.toml` listed in `[task_config].includes`.

There is no escape-hatch marker.

## Code

The classifier is `classifyMiseHygieneGuardForOrchestrator`; tests are in [`pretooluse-mise-hygiene-guard.test.ts`](../hooks/pretooluse-mise-hygiene-guard.test.ts). The file also runs standalone (`bun pretooluse-mise-hygiene-guard.ts < payload.json`) through its `import.meta.main` guard.
