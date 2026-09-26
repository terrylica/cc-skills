---
name: health
description: "Gmail Commander health check - the local Gmail CLI, its credentials and token cache, the buildBot() contract the deployment imports, and a check that no retired local bot or digest job remains. TRIGGERS - gmail health, email bot status, gmail diagnostics, gmail bot check."
allowed-tools: Bash
model: haiku
---

# Gmail Commander Health Check

Run diagnostics for everything this plugin owns on this machine. The Telegram bot and the scheduled digest run in a **private Restate deployment on an always-on Mac mini**, so their liveness is not checked here — see step 6.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Check All Subsystems

```bash
PLUGIN="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander"

echo "=== 1. Gmail CLI Binary + Lockfile ==="
ls -la "$PLUGIN/scripts/gmail-cli/gmail" 2>/dev/null && echo "OK binary" || echo "MISSING — run: cd scripts/gmail-cli && bun install --frozen-lockfile && bun run build"
ls "$PLUGIN/scripts/gmail-cli/bun.lock" >/dev/null 2>&1 && echo "OK lockfile" || echo "MISSING lockfile — the build is not reproducible"

echo ""
echo "=== 2. Environment Variables (interactive CLI) ==="
echo "GMAIL_OP_UUID: ${GMAIL_OP_UUID:+SET}"
echo "OP_SERVICE_ACCOUNT_TOKEN: ${OP_SERVICE_ACCOUNT_TOKEN:+SET} (optional)"

echo ""
echo "=== 3. 1Password CLI ==="
op account list 2>&1 | head -3

echo ""
echo "=== 4. Token Cache (names only, never contents) ==="
ls ~/.claude/tools/gmail-tokens/ 2>/dev/null | grep -E '\.json$' || echo "No cached tokens — first CLI run will open a browser for consent"

echo ""
echo "=== 5. buildBot() contract (what the deployment imports) ==="
if [ -d "$PLUGIN/node_modules" ]; then
  (cd "$PLUGIN" && bun -e 'const m = await import("./scripts/bot.ts"); console.log(typeof m.buildBot === "function" ? "OK buildBot exported" : "FAIL buildBot missing")' 2>&1 | tail -1)
else
  echo "SKIPPED — plugin node_modules not installed (grep instead):"
  grep -c "export async function buildBot" "$PLUGIN/scripts/bot.ts" 2>/dev/null || echo "FAIL buildBot export not found"
fi

echo ""
echo "=== 6. Deployed bot and digest ==="
echo "Not checkable from here. Send /status to the bot in Telegram; if it does not answer, follow the private deployment's runbook."

echo ""
echo "=== 7. Retired local jobs (expected: none) ==="
launchctl list | grep -F gmail-commander || echo "none loaded"
ls ~/Library/LaunchAgents 2>/dev/null | grep -F gmail-commander || echo "no plists"
pgrep -fl "gmail-commander/scripts/bot.ts" || echo "no local bot process"
```

## Interpreting step 7

Any hit in step 7 is a leftover from the laptop jobs retired on 2026-09-24, or a standalone `bot.ts` someone started by hand. A local poller competes with the deployed bot for the same Telegram token and produces `409 Conflict` on both. **Report it to the operator; do not load, unload or kill it yourself.**

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If the underlying tool's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
