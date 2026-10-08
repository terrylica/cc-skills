# Phase 3: Registration & Validation (Detailed)

## 3.1 Add to marketplace.json

Edit `.claude-plugin/marketplace.json` to add the new plugin entry:

```json
{
  "name": "$PLUGIN_NAME",
  "description": "TODO: Add description from ADR",
  "version": "$MARKETPLACE_VERSION",
  "source": "./plugins/$PLUGIN_NAME/",
  "category": "$PLUGIN_CATEGORY",
  "author": {
    "name": "terrylica",
    "url": "https://github.com/terrylica"
  },
  "keywords": [],
  "strict": false
}
```

**If hooks exist**, add the hooks field:

```json
"hooks": "./plugins/$PLUGIN_NAME/hooks/hooks.json"
```

## 3.2 Run Validation Script

```bash
node scripts/validate-plugins.mjs
```

Expected output:

```
📦 Registered plugins: N+1
📁 Plugin directories: N+1

✅ All plugins validated successfully!
```

## 3.3 Quality Audit

**MANDATORY Skill tool call: `itp:code-hardcode-audit`** -- activate NOW.

This skill checks for:

- Hardcoded values
- Magic numbers
- Duplicate constants
- Secrets

## 3.4 Silent Failure Audit

**MANDATORY**: Run silent failure audit on all hook entry points.

```bash
uv run plugins/plugin-dev/skills/plugin-validator/scripts/audit_silent_failures.py plugins/$PLUGIN_NAME/ --fix
```

This script validates:

- **Shellcheck**: Runs on all `hooks/*.sh` files
- **Silent bash commands**: `mkdir`, `cp`, `mv`, `rm` must use `if !` pattern
- **Silent Python exceptions**: `except: pass` must emit to stderr

**Critical Rule**: All hook entry points MUST emit to stderr on failure.

If violations are found, fix them before proceeding:

| Pattern                | Fix                                                              |
| ---------------------- | ---------------------------------------------------------------- |
| `mkdir -p "$DIR"`      | `if ! mkdir -p "$DIR" 2>&1; then echo "[plugin] Failed" >&2; fi` |
| `except OSError: pass` | `except OSError as e: print(f"[plugin] {e}", file=sys.stderr)`   |

## 3.5 Plugin Validation Agent

**Spawn Agent: `plugin-dev:plugin-validator`** -- validate plugin structure.

```
Task with subagent_type="plugin-dev:plugin-validator"
prompt: "Validate the plugin at plugins/$PLUGIN_NAME/ for correct structure, manifest, and component organization."
```

## Phase 3 Gate

**STOP. Verify before proceeding to Phase 4:**

- [ ] Plugin added to marketplace.json
- [ ] validate-plugins.mjs passes
- [ ] code-hardcode-audit passes
- [ ] silent-failure-audit passes (no errors)
- [ ] plugin-validator agent approves
