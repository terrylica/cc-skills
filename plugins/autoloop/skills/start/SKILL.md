---
name: start
description: Scaffold LOOP_CONTRACT.md in the current project and kick off a self-revising autonomous loop.
allowed-tools: Bash, Read, Write, AskUserQuestion, Skill
argument-hint: "[path-to-contract]"
disable-model-invocation: false
---

# autoloop: Start

Scaffold `LOOP_CONTRACT.md` and start a self-revising `/loop` that reads the contract each firing.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Arguments

- Positional (optional): contract file path. Defaults to `./LOOP_CONTRACT.md`.

## Step 1: Ensure hooks are installed

Install BOTH autoloop hooks into `~/.claude/settings.json` if not already present. Idempotent.

- **PostToolUse → `heartbeat-tick.sh`** — ticks heartbeat on every tool invocation, detects cwd drift.
- **SessionStart → `session-bind.sh`** — authoritatively binds `owner_session_id` from stdin payload (replaces broken `$CLAUDE_SESSION_ID` env-var capture; ref [anthropics/claude-code#47018](https://github.com/anthropics/claude-code/issues/47018)).
- **PreToolUse(ScheduleWakeup) → `pacing-veto.sh`** — denies pacing-disguised wakers (delays in the 300–1199s cache-miss zone, or any >270s with token-budget/cache-warm/self-pacing/cooldown/rest in the reason text). Forces Tier 0 (in-turn) when no real external blocker exists.

```bash
# Source the hook install library
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autoloop}"
source "$PLUGIN_ROOT/scripts/hook-install-lib.sh"

# Wave 5 A4: strip macOS quarantine xattrs in case this is the first run
# after `claude plugin marketplace add`. No-op on Linux / clean trees.
strip_plugin_quarantine_xattrs "$PLUGIN_ROOT" >/dev/null 2>&1 || true

# Wave 5 A8: explicit "auto-setup-on-start". If neither hook is installed,
# announce that we're running first-time setup before the install_all_hooks
# call so the user understands the side effect. If both are already
# installed, stay quiet — there's nothing to surface.
SETTINGS_PATH="$HOME/.claude/settings.json"
if [ "$(is_hook_installed "$SETTINGS_PATH" 2>/dev/null)" != "yes" ] || \
   [ "$(is_session_bind_installed "$SETTINGS_PATH" 2>/dev/null)" != "yes" ]; then
  echo "Installing autoloop hooks into ~/.claude/settings.json (one-time setup)..."
fi

# Install all four autoloop hooks (idempotent). DO NOT swallow stderr —
# install_all_hooks emits actionable diagnostics on failure (malformed JSON,
# write errors, missing hook scripts) that the user needs to see. If install
# fails, abort the bootstrap rather than continuing into a half-bootstrapped
# state where the loop appears registered but session-bind / heartbeat /
# pacing-veto / empty-firing-detector never run.
if ! install_all_hooks; then
  echo "ERROR: Failed to install autoloop hooks." >&2
  echo "  The bootstrap cannot continue safely — a registered loop without" >&2
  echo "  its hooks installed is what /autoloop:tinker calls F2_missing_hooks." >&2
  echo "  Inspect: jq . $SETTINGS_PATH ; ls $PLUGIN_ROOT/hooks/" >&2
  exit 1
fi

# Wave 6 anti-fragility (v12.52.0+): runtime self-test the just-installed
# hooks. Without this, a hook can be registered in settings.json yet crash
# on real invocation due to: missing shebang, broken shellcheck disable,
# stale path to a sibling lib, syntax error from a botched edit, missing
# dependency. The self-test catches those by feeding each hook a synthetic
# Claude Code event payload in a sandbox HOME and asserting exit 0.
if ! run_hook_runtime_selftest "$PLUGIN_ROOT" 2>&1; then
  echo "ERROR: Autoloop hook runtime self-test failed." >&2
  echo "  Hooks were registered in settings.json but at least one crashes" >&2
  echo "  on invocation. Inspect the FAIL line(s) above." >&2
  echo "  Recover: /autoloop:tinker will redo the install with diagnostics." >&2
  exit 1
fi
```

Result: every Claude session opening in a registered loop's contract dir will (1) bind to the loop on SessionStart, then (2) tick heartbeat with cwd-drift detection on every tool invocation.

## Step 2: Preflight (v2 layout — `.autoloop/<slug>--<hash>/CONTRACT.md`)

Wave 3 introduced a new on-disk layout: contracts live under
`<project_cwd>/.autoloop/<campaign-slug>--<short-hash>/CONTRACT.md` with a
sibling `state/` directory. This makes multi-campaign coexistence in one cwd
first-class and lets any AI agent ID the right contract by directory name.

**Migration is automatic on first `/autoloop:start` in any directory that
contains a legacy `<cwd>/LOOP_CONTRACT.md`:**

```bash
PROJECT_CWD="${1:-$(pwd -P)}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autoloop}"
source "$PLUGIN_ROOT/scripts/registry-lib.sh"
source "$PLUGIN_ROOT/scripts/state-lib.sh"

# Returns "noop" if nothing to migrate, or two lines starting with
# "migrated_to_loop_id:" / "migrated_to_path:" on success.
MIGRATION_OUTPUT=$(migrate_legacy_contract "$PROJECT_CWD" "${CLAUDE_SESSION_ID:-$$-$(date +%s)}")
if [ "$MIGRATION_OUTPUT" != "noop" ]; then
  echo "$MIGRATION_OUTPUT"
  echo "Legacy LOOP_CONTRACT.md migrated to .autoloop/ subdir; resuming with new layout."
fi
```

**Then check whether ANY v2 contract already exists for this project:**

```bash
existing=$(compgen -G "$PROJECT_CWD/.autoloop/*--[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]/CONTRACT.md" 2>/dev/null || true)
if [ -n "$existing" ]; then
  echo "v2 contract(s) present:"
  echo "$existing"
  # Ask the user: resume an existing campaign, start a new one alongside, or stop?
fi
```

Use `AskUserQuestion` to choose: **resume existing**, **start new campaign alongside** (creates a second `.autoloop/<slug>--<hash>/`), or **stop**.

## Step 3: Collect contract inputs

Use `AskUserQuestion` to collect:

```
1. name        — short slug for this loop (e.g. "odb-research", "flaky-ci-watcher")
2. scope       — one-line Core Directive describing the long-horizon goal
3. cadence     — typical wake-up cadence hint (continuous | event-driven | hourly | daily)
```

The contract path is **derived deterministically** from `name` + a stable
short_hash, so the user does not pick a path:

```bash
SLUG=$(slugify "$NAME_INPUT")
SHORT_HASH=$(compute_short_hash "${CLAUDE_SESSION_ID:-$$-$(date +%s)}" "$(date -u +%s)")
CONTRACT_DIR="$PROJECT_CWD/.autoloop/${SLUG}--${SHORT_HASH}"
CONTRACT_PATH="$CONTRACT_DIR/CONTRACT.md"
mkdir -p "$CONTRACT_DIR/state/revision-log"
```

If `$CONTRACT_DIR` already exists, append a numeric suffix to short_hash or
ask the user to pick a different `name`.

## Step 4: Scaffold the contract

Copy the plugin-shipped template and substitute placeholders. Use
`$CLAUDE_PLUGIN_ROOT` (set by Claude Code for every plugin skill) to
resolve the template — **do not use `$0`**, which is not set when a
SKILL.md is loaded as instructions rather than executed as a script.

```bash
# CLAUDE_PLUGIN_ROOT points at /…/plugins/<plugin-name> when invoked from
# a skill. Fall back to the marketplace cache path if unset (e.g., when a
# user invokes the skill's Bash manually outside the harness).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autoloop}"
TEMPLATE="$PLUGIN_ROOT/templates/LOOP_CONTRACT.template.md"
if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: template missing at $TEMPLATE — reinstall the plugin" >&2
  exit 1
fi
cp "$TEMPLATE" "$CONTRACT_PATH"

# Also copy the PROVENANCE.md template (Wave 3) — sits alongside CONTRACT.md
PROV_TEMPLATE="$PLUGIN_ROOT/templates/PROVENANCE.template.md"
if [ -f "$PROV_TEMPLATE" ]; then
  cp "$PROV_TEMPLATE" "$CONTRACT_DIR/PROVENANCE.md"
fi
```

Then inject user inputs via `sed` (or Edit the file via Claude's tools):

- `<SHORT_DESCRIPTIVE_NAME>` → user-provided `name`
- `<ISO_8601_UTC>` → `date -u +"%Y-%m-%dT%H:%M:%SZ"` (always `-u`; bare `date` returns local time and silently mismatches the contract's UTC fields)
- `<RELATIVE_PATH_TO_LOOP_CONTRACT_MD>` → `$CONTRACT_PATH` (now under `.autoloop/<slug>--<hash>/CONTRACT.md`)
- `<CORE DIRECTIVE>` / `<PROJECT OR CAMPAIGN TITLE>` → user-provided `scope`

After the template is in place, call `init_contract_frontmatter_v2` to stamp
all v2 birth-record fields (loop_id, campaign_slug, created_at_utc, etc.):

```bash
NEW_LOOP_ID=$(derive_loop_id "$CONTRACT_PATH")
init_contract_frontmatter_v2 "$CONTRACT_PATH" "$NEW_LOOP_ID" "$CONTRACT_DIR/state"
```

## Step 5: Register loop in machine registry

After deriving the loop ID in Step 2/3, register this loop in the machine-level registry.

> **`owner_session_id` is set to `pending-bind` here.** The SessionStart hook (`hooks/session-bind.sh`) replaces it atomically on the next session start, because `$CLAUDE_SESSION_ID` env var is **not populated** in skill Bash subprocesses ([anthropics/claude-code#47018](https://github.com/anthropics/claude-code/issues/47018)). Capturing it inline would always store empty/garbage — the hook is the only correct binding site.

```bash
# Source the registry library
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autoloop}"
source "$PLUGIN_ROOT/scripts/registry-lib.sh"

# Derive loop_id from contract path (if not already done)
loop_id=$(derive_loop_id "$CONTRACT_PATH")

# Create entry JSON with all required fields. owner_session_id="pending-bind"
# is the canonical placeholder; the SessionStart hook replaces it atomically
# on the next session start. bound_cwd starts empty; heartbeat-tick records
# it on the first tick and detects drift thereafter.
#
# state_dir resolution: ALWAYS go through `state_dir_path "$loop_id"
# "$CONTRACT_PATH"` instead of hand-rolling `<dir>/.loop-state/<id>/`.
# Wave 3 introduced the v2 layout (.autoloop/<slug>--<hash>/state/) and
# `state_dir_path` returns the correct path for both v1 and v2 contracts.
# Hand-rolling .loop-state would register a v1 path against a v2 contract
# and the heartbeat-tick hook would write to a directory the contract
# doesn't recognize.
entry=$(jq -n \
  --arg loop_id "$loop_id" \
  --arg contract_path "$(realpath "$CONTRACT_PATH")" \
  --arg state_dir "$(state_dir_path "$loop_id" "$CONTRACT_PATH")" \
  --arg owner_session_id "pending-bind" \
  --arg bound_cwd "" \
  --arg owner_pid "$$" \
  --arg owner_start_time_us "$(date +%s%N | cut -c1-16)" \
  --arg launchd_label "com.user.claude.loop.$loop_id" \
  --arg started_at_us "$(date +%s%N | cut -c1-16)" \
  --arg expected_cadence_seconds "$cadence_seconds" \
  --arg generation "0" \
  '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, owner_session_id: $owner_session_id, bound_cwd: $bound_cwd, owner_pid: $owner_pid, owner_start_time_us: $owner_start_time_us, launchd_label: $launchd_label, started_at_us: $started_at_us, expected_cadence_seconds: $expected_cadence_seconds, generation: $generation}')

# Register in machine registry (atomic, serialized write)
if ! register_loop "$entry"; then
  echo "WARNING: Failed to register loop in machine registry (may already exist)" >&2
fi
```

## Step 6: Generate and load launchd plist

After registering the loop, generate the launchd plist and load it:

```bash
# Source the launchd library
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autoloop}"
source "$PLUGIN_ROOT/scripts/launchd-lib.sh"
source "$PLUGIN_ROOT/scripts/state-lib.sh"

# Derive loop_id and state_dir
loop_id=$(derive_loop_id "$CONTRACT_PATH")
state_dir=$(state_dir_path "$loop_id" "$CONTRACT_PATH")

# Stub waker script path (Phase 9 will ship the actual script)
waker_script="$PLUGIN_ROOT/scripts/waker.sh"

# Calculate polling interval (default 150 seconds = half of typical cadence)
interval_seconds="${cadence_seconds:-300}"
interval_seconds=$((interval_seconds / 2))
if [ "$interval_seconds" -lt 60 ]; then
  interval_seconds=60
fi

# Generate plist. The Wave-6 anti-fragility wave hardened generate_plist to
# refuse a plist pointing at a missing waker_script (turned silent failure
# into loud failure).
if ! generate_plist "$loop_id" "$state_dir" "$waker_script" "$interval_seconds"; then
  echo "ERROR: Failed to generate launchd plist" >&2
  echo "  The bootstrap cannot continue safely; recover with /autoloop:tinker" >&2
  exit 1
fi

# Load plist (bootstraps on macOS; skipped gracefully on non-macOS).
# DO NOT swallow stderr — load_plist's diagnostic output (FDA permission,
# label collision, malformed plist, MDM block) is the only signal the user
# has when launchctl rejects the plist.
if ! load_plist "$loop_id" "$state_dir"; then
  echo "ERROR: Failed to load launchd plist" >&2
  echo "  The loop is registered but will not fire; recover with /autoloop:tinker" >&2
  exit 1
fi

# Wave-6 anti-fragility: post-bootstrap launchctl assertion.
# load_plist returning 0 only means the bootstrap call succeeded; verify
# the label actually appears in `launchctl list` so we never ship a
# half-loaded state. Skipped on non-macOS.
if [ "$(uname -s)" = "Darwin" ]; then
  label="com.user.claude.loop.${loop_id}"
  if ! launchctl list "$label" >/dev/null 2>&1; then
    echo "ERROR: launchctl list does not show '$label' after bootstrap" >&2
    echo "  This is a half-loaded plist state. Recover with /autoloop:tinker" >&2
    exit 1
  fi
fi
```

## Step 7: Emit pointer trigger (updated from Step 7)

Print the snippet the user can feed to `/loop`:

```
/loop

Read and execute the latest autonomous work contract at:
  $CONTRACT_PATH

Follow its instructions verbatim. That file self-updates; this trigger stays fixed.
```

## Step 8: Offer to start the loop immediately

Use `AskUserQuestion` with two options:

- `Start now` — invoke the native `/loop` skill via `Skill(loop)` with the pointer trigger as input
- `Not yet` — user will invoke `/loop` manually (e.g. after committing the contract)

If `Start now`, call `Skill(loop)` with the pointer trigger snippet as `args`. Otherwise print "Contract scaffolded at `$CONTRACT_PATH`. Run `/loop` with the pointer trigger above whenever ready."

## Step 9: Suggest commit

Print a suggested first commit:

```bash
git add "$CONTRACT_PATH"
git commit -m "loop(bootstrap): scaffold LOOP_CONTRACT.md for $name"
```

## Step 10: Print bind-verification block (Wave 6)

After Step 9, print the explicit verification block below. This is the
last user-visible signal before /autoloop:start exits. Do NOT skip it —
the silent pending-bind failure mode that motivated Wave 6 was caused
in part by /autoloop:start exiting cleanly even when the loop was not
actually firing autonomously.

```
🔧 Loop registered: $loop_id ($display_name)
   project_root:  $project_root              # = .created_at_cwd; bind hooks match cwd against this
   contract:      $CONTRACT_PATH

📡 Autonomous-fire requirement
   The launchd waker can only fire /loop on this loop AFTER the
   SessionStart hook has bound owner_session_id. The hook fires when
   you open Claude Code with cwd anywhere in the path hierarchy:

       $project_root  ⊆  cwd  ⊆  $(dirname "$CONTRACT_PATH")

   Until that bind happens, the registry shows owner_session_id =
   "pending-bind" and the waker logs "dead+fresh anomaly" instead of
   firing. Run /autoloop:muster to verify state.

✅ Verify within 30s of your next session start
   /autoloop:muster
       expect: STATUS=ACTIVE  (not PENDING-BIND or PENDING-BIND-STUCK)

   If PENDING-BIND-STUCK after 5min:
     • cd "$project_root" && claude        # opens a session that the hook can bind
     • /autoloop:tinker $loop_id           # patches owner_session_id from THIS session
     • heal-self.sh runs hourly and will auto-bind to a live session
       whose JSONL mtime is <5min — a third safety net
```

Echo this block verbatim with the variables expanded. Don't paraphrase
or shorten — the troubleshooting hint paths are load-bearing for
operators encountering pending-bind for the first time.

## Anti-patterns

- Do NOT overwrite an existing contract without explicit user confirmation
- Do NOT write the contract to a dir outside the current working tree (sandbox bypass)
- Do NOT invoke `/loop` with the full Core Directive as prompt — always use the short pointer trigger pattern

## Troubleshooting

| Symptom                             | Fix                                                          |
| ----------------------------------- | ------------------------------------------------------------ |
| Template not found                  | `claude plugin reinstall autoloop@cc-skills`                 |
| `/loop` says "unknown skill"        | Claude Code version < 2.1.101; upgrade to get native `/loop` |
| Pointer trigger re-reads stale file | Ensure `$CONTRACT_PATH` is absolute or CWD-stable            |

## Post-Execution Reflection

0. **Locate yourself.** — Confirm this SKILL.md is the canonical file before any edit.
1. **What failed?** — Fix the instruction that caused it.
2. **What drifted?** — Update the template if it's out of sync with the latest idiom.
3. **Log it.** — Evolution-log entry with trigger, fix, evidence.
