---
name: start
description: "Scaffold LOOP_CONTRACT.md in the current project and kick off a self-revising autonomous loop. TRIGGERS - autonomous-loop start, scaffold loop contract, begin self-revising loop, install LOOP_CONTRACT."
allowed-tools: Bash, Read, Write, AskUserQuestion, Skill
argument-hint: "[path-to-contract]"
disable-model-invocation: false
---

# autonomous-loop: Start

Scaffold `LOOP_CONTRACT.md` and start a self-revising `/loop` that reads the contract each firing.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Arguments

- Positional (optional): contract file path. Defaults to `./LOOP_CONTRACT.md`.

## Step 1: Preflight

Check whether a contract already exists at the target path.

```bash
CONTRACT_PATH="${1:-./LOOP_CONTRACT.md}"
if [ -f "$CONTRACT_PATH" ]; then
  echo "EXISTS — user should be asked whether to resume or overwrite"
else
  echo "ABSENT — safe to scaffold"
fi
```

If `EXISTS`: use `AskUserQuestion` to choose between `resume` (run `/autonomous-loop:status` instead of starting fresh) or `overwrite` (proceed with Step 2).

## Step 2: Collect contract inputs

Use `AskUserQuestion` to collect:

```
1. name        — short slug for this loop (e.g. "odb-research", "flaky-ci-watcher")
2. scope       — one-line Core Directive describing the long-horizon goal
3. location    — path for the contract file (default: ./LOOP_CONTRACT.md)
4. cadence     — typical wake-up cadence hint (continuous | event-driven | hourly | daily)
```

## Step 3: Scaffold the contract

Copy the plugin-shipped template and substitute placeholders. Use
`$CLAUDE_PLUGIN_ROOT` (set by Claude Code for every plugin skill) to
resolve the template — **do not use `$0`**, which is not set when a
SKILL.md is loaded as instructions rather than executed as a script.

```bash
# CLAUDE_PLUGIN_ROOT points at /…/plugins/<plugin-name> when invoked from
# a skill. Fall back to the marketplace cache path if unset (e.g., when a
# user invokes the skill's Bash manually outside the harness).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autonomous-loop}"
TEMPLATE="$PLUGIN_ROOT/templates/LOOP_CONTRACT.template.md"
if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: template missing at $TEMPLATE — reinstall the plugin" >&2
  exit 1
fi
cp "$TEMPLATE" "$CONTRACT_PATH"
```

Then inject user inputs via `sed` (or Edit the file via Claude's tools):

- `<SHORT_DESCRIPTIVE_NAME>` → user-provided `name`
- `<ISO_8601_UTC>` → `date -u +"%Y-%m-%dT%H:%M:%SZ"`
- `<RELATIVE_PATH_TO_LOOP_CONTRACT_MD>` → `$CONTRACT_PATH`
- `<CORE DIRECTIVE>` / `<PROJECT OR CAMPAIGN TITLE>` → user-provided `scope`

## Step 4: Emit pointer trigger

Print the snippet the user can feed to `/loop`:

```
/loop

Read and execute the latest autonomous work contract at:
  $CONTRACT_PATH

Follow its instructions verbatim. That file self-updates; this trigger stays fixed.
```

## Step 5: Offer to start the loop immediately

Use `AskUserQuestion` with two options:

- `Start now` — invoke the native `/loop` skill via `Skill(loop)` with the pointer trigger as input
- `Not yet` — user will invoke `/loop` manually (e.g. after committing the contract)

If `Start now`, call `Skill(loop)` with the pointer trigger snippet as `args`. Otherwise print "Contract scaffolded at `$CONTRACT_PATH`. Run `/loop` with the pointer trigger above whenever ready."

## Step 6: Suggest commit

Print a suggested first commit:

```bash
git add "$CONTRACT_PATH"
git commit -m "loop(bootstrap): scaffold LOOP_CONTRACT.md for $name"
```

## Anti-patterns

- Do NOT overwrite an existing contract without explicit user confirmation
- Do NOT write the contract to a dir outside the current working tree (sandbox bypass)
- Do NOT invoke `/loop` with the full Core Directive as prompt — always use the short pointer trigger pattern

## Troubleshooting

| Symptom                             | Fix                                                          |
| ----------------------------------- | ------------------------------------------------------------ |
| Template not found                  | `claude plugin reinstall autonomous-loop@cc-skills`          |
| `/loop` says "unknown skill"        | Claude Code version < 2.1.101; upgrade to get native `/loop` |
| Pointer trigger re-reads stale file | Ensure `$CONTRACT_PATH` is absolute or CWD-stable            |

## Post-Execution Reflection

0. **Locate yourself.** — Confirm this SKILL.md is the canonical file before any edit.
1. **What failed?** — Fix the instruction that caused it.
2. **What drifted?** — Update the template if it's out of sync with the latest idiom.
3. **Log it.** — Evolution-log entry with trigger, fix, evidence.
