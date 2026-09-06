# Runbook — Rotating the compromised 1Password service-account token (2026-09-05)

**Status**: active incident. **Credential**: the 1Password service-account token for the **Claude Automation** vault, stored at `~/.claude/.secrets/op-service-account-token`. **Classification**: compromised — the value exists in plaintext in 91 files on this machine (58 under `~/.claude/projects`, 33 under `/private/tmp/claude-501`), both of which are retained locations.

This runbook assumes you are under time pressure. Work top to bottom. Do not skip §0 — running §3 before §1 is live re-creates the incident with the new token.

Throughout: **never print, echo, interpolate or render the token value.** Every check below is `grep -l` / `grep -c` / a boolean test / an exit code. Nothing in this document contains a secret, and nothing you run from it should produce one on your terminal.

---

## 0. Ordering — read this before doing anything

The steps are ordered by a hard dependency, not by convenience. Two constraints fix the sequence, and both are load-bearing.

**Constraint A — the injector fix must be LIVE before the new token is minted.** The root cause of this incident is a PreToolUse hook that rewrote matching Bash commands to `OP_SERVICE_ACCOUNT_TOKEN='<literal token>' <command>`. Claude Code records the _rewritten_ command in the session transcript and in background-task output files, so every `op` call against the Claude Automation vault wrote the token to disk. The fix — emitting `OP_SERVICE_ACCOUNT_TOKEN="$(cat '<path>')"` instead, so the shell resolves the value at execution time and only the path is ever recorded — is committed in this repo at `plugins/itp-hooks/hooks/lib/op-token-injector.ts`. The **running** copy is the marketplace clone at `~/.claude/plugins/marketplaces/cc-skills/plugins/itp-hooks/hooks/lib/op-token-injector.ts`, and as of 2026-09-05 that clone **does not have the fix**. If you mint a new token while the old hook is live, the very first `op` command against the vault writes the new token to a transcript and you are back where you started, one rotation poorer.

**Constraint B — the credential file is destroyed LAST.** See §5. The leak audit derives its search pattern _from the token file_. Delete the file first and you have destroyed the only means of locating its own plaintext copies by literal match.

**Constraint C — the old token is revoked LAST, after every consumer is updated and verified.** Revoke-last means a consumer you missed fails loudly while the old token still works, which is a recoverable annoyance. Revoke-first means it fails after the only working credential is already gone, during an incident, with no way to distinguish "I missed a consumer" from "the new token is wrong".

So: **confirm the fix is live (§1) → inventory consumers (§2) → mint and distribute the new token (§3) → verify (§4) → revoke the old token (§4.4) → purge plaintext copies, deleting the source file last (§5).**

### 0.1 Confirm the running clone has the fix

```bash
set -euo pipefail
REPO=~/eon/cc-skills/plugins/itp-hooks/hooks/lib/op-token-injector.ts
CLONE=~/.claude/plugins/marketplaces/cc-skills/plugins/itp-hooks/hooks/lib/op-token-injector.ts
diff -q "$CLONE" "$REPO" >/dev/null 2>&1 && echo "FIX_IS_LIVE" || echo "FIX_NOT_LIVE"
```

`FIX_IS_LIVE` means the clone matches the repo and you may proceed to §2. A second, narrower check that does not depend on the two files being byte-identical (the clone may legitimately lag on unrelated commits):

```bash
grep -c 'OP_SERVICE_ACCOUNT_TOKEN="\$(cat' "$CLONE"
```

`1` means the clone emits the command-substitution form and the leak is closed. `0` means it still interpolates the literal.

To make the fix live, update the marketplace clone the normal way — release the repo change and let Claude Code refresh the clone, or pull it directly if that is faster under pressure. Re-run the check above; do not proceed on the assumption that a pull worked.

### 0.2 Interim mitigation while the fix is not live

**Do not run any `op` command that matches the injector's patterns until §0.1 reports the fix is live.** The patterns that trigger injection are, from the hook source:

- `op item|document|vault <verb> ... --vault "Claude Automation"`
- `op read "op://Claude Automation/..."`
- `op run --vault "Claude Automation" ...`
- `op inject ... Claude Automation`

Anything matching those writes the token to a transcript. `op` calls against _other_ vaults do not match and are unaffected. If you have an urgent need for a Claude Automation secret before the fix ships, read it through a path the hook does not rewrite — set the env var yourself from the file in the same command (`OP_SERVICE_ACCOUNT_TOKEN="$(cat ~/.claude/.secrets/op-service-account-token)" op ...`), which the hook skips because it detects the variable is already set, and which never puts the value in argv.

---

## 1. Blast radius — what reads this token

Derived 2026-09-05 by `grep -rl` over `~/.claude`, `~/eon`, `~/own`, `~/vj`, excluding `node_modules`, `.git`, worktrees, `.venv`, `/projects/` and third-party session-transcript archives. **118 files** mention `OP_SERVICE_ACCOUNT_TOKEN` or `op-service-account-token` after that filtering. Most are not consumers. The breakdown that matters:

### 1.1 Real runtime consumers — these break when the token changes

| Consumer                                                         | Repo / location                                                                    | Notes                                                                                                                                                                                                  |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `op-token-injector.ts`                                           | `~/.claude/plugins/marketplaces/cc-skills/plugins/itp-hooks/hooks/lib/`            | **The live hook.** Reads the token file on every matching Bash command. This is the incident's root cause and the highest-traffic consumer.                                                            |
| `pretooluse-pueue-wrap-guard.ts`                                 | same clone, `hooks/`                                                               | Calls the injector; must remain the last PreToolUse entry in `hooks.json`.                                                                                                                             |
| `hlf-monitor.mjs`                                                | `~/.claude/tools/lark-automation/`                                                 | **Runs under launchd** — `com.terryli.lark-hlf-monitor`. The only launchd job in the blast radius.                                                                                                     |
| `main.swift`                                                     | `~/.claude/automation/gmail-token-refresher/`                                      | Gmail OAuth token refresher. No launchd job of its own found in `~/Library/LaunchAgents`.                                                                                                              |
| `resolve_pushover_secret.sh`                                     | `~/eon/cc-skills/plugins/pushover-commander/skills/_lib/`                          | Credential resolver for the Pushover plugin.                                                                                                                                                           |
| `pushover-notify.sh`, `pushover-quota.sh`                        | `~/eon/cc-skills/plugins/pushover-commander/skills/verbatim-audit-notify/scripts/` | Send + quota paths.                                                                                                                                                                                    |
| `tg-cli.ts`                                                      | `~/eon/cc-skills/plugins/tlg/scripts/`                                             | Telegram CLI. Note the `tlg` **vault** scope was already migrated off the Claude Automation 1Password vault on 2026-08-09; confirm whether this reference is still reached before treating it as live. |
| `publish_static.sh`                                              | `~/eon/cc-skills/plugins/devops-tools/skills/cloudflare-workers-publish/scripts/`  | Cloudflare Workers publish path.                                                                                                                                                                       |
| `resolve_credential.sh`                                          | `~/eon/claude-sys/.claude/skills/nh20t-modem-controller/scripts/`                  | Home-network modem controller.                                                                                                                                                                         |
| `gmail-commander-bot`, `gmail-watcher`, `gmail-commander-digest` | `~/own/amonic/bin/`                                                                | Three Gmail binaries. No matching launchd jobs found.                                                                                                                                                  |
| `build.ts`                                                       | `~/vj/cpc/legal/build/`                                                                  | CPC legal site build.                                                                                                                                                                                  |
| `publish-to-pypi.sh`                                             | `~/eon/atr-adaptive-laguerre/scripts/`, `~/eon/crypto-kline-vision-data/scripts/`  | PyPI publish scripts (two repos).                                                                                                                                                                      |
| `publish_findings.sh`                                            | `~/eon/opendeviationbar-patterns/scripts/`                                         |                                                                                                                                                                                                        |
| `load_secrets_from_1password.sh`                                 | `~/eon/voip/voip-hk-spike/scripts/`                                                |                                                                                                                                                                                                        |

### 1.2 Not consumers — do not chase these

- **Marketplace-clone duplicates.** Everything under `~/.claude/plugins/marketplaces/cc-skills/` is a copy of `~/eon/cc-skills/`. Fix the repo; the clone follows. The one exception is the injector itself, which is _the running copy_ and is therefore listed above as a real consumer.
- **Worktree and mirror duplicates.** `~/eon/ccmax-monitor/.claude/worktrees/*`, `~/eon/ccmax-monitor-partner-mirror/`, and `~/eon/claude-sys-m3max-apfs-logd-wedge-chronicle/` (a duplicate of `~/eon/claude-sys/`) all echo their originals.
- **Documentation and registries.** `docs/1password-credential-registry.md`, various `CLAUDE.md`, `PITFALLS.md`, `SKILL.md`, `LESSONS.md`, and the `.toml` research documents under `ccmax-monitor/docs/` and `claude-sys/`. These describe the credential; they do not read it. They may need a _text_ update after rotation (item IDs, rotation dates) but nothing breaks if you skip them.
- **Tests and examples.** `test-posttooluse-1password-pattern-reminder-...sh`, `pushover-commander.local.env.example`.
- **Third-party session transcripts.** `~/eon/bruntwork/MDNasim/session-transcripts-2026-04-14/` — another operator's exported sessions. Out of scope for rotation; in scope for §5 if they contain this token.

### 1.3 launchd

Only one launchd job is in the blast radius: **`com.terryli.lark-hlf-monitor`** (`~/Library/LaunchAgents/com.terryli.lark-hlf-monitor.plist` → `~/.claude/tools/lark-automation/hlf-monitor.mjs`). No plist in `~/Library/LaunchAgents` references the token or the env var directly; the dependency is via the script. Restart it after §3 so it picks up the new value:

```bash
launchctl kickstart -k gui/$(id -u)/com.terryli.lark-hlf-monitor
```

---

## 2. Pre-rotation snapshot

Record the current leak count so §4.2 has something to compare against. This reads the pattern from the file and never renders it.

```bash
set -uo pipefail          # NOT -e: a zero-match grep exits 1, and zero can be the pass condition
TOKEN_FILE=~/.claude/.secrets/op-service-account-token
grep -rlF -f <(grep -v '^$' "$TOKEN_FILE") ~/.claude/projects /private/tmp/claude-501 2>/dev/null | wc -l || true
```

**Why every audit block here uses `set -uo pipefail` and not `-e`.** `grep` exits **1** when it finds nothing — and finding nothing is the PASS condition in §4.2 and §5. Under `set -e` with `pipefail`, a clean result therefore terminates the block before the count is printed, so the operator sees no confirmation at exactly the moment this runbook tells them to confirm one. In §5 that silence sits immediately before an irreversible `rm -P`. Verified: the `-e` form on a zero-match run exits non-zero with no count line emitted. The `|| true` makes the intent explicit even without `-e`.

Expected: **91** (58 + 33). If you get a wildly larger number, check that `grep -v '^$'` actually stripped blank lines — **an empty pattern line makes `grep -f` match every file**, which looks like a catastrophic leak and is not one.

---

## 3. Rotation

### 3.1 Minting requires the 1Password web console. There is no CLI path

State this plainly because it is the step people waste time on: **`op` cannot mint a service-account token.** The `op service-account create` family requires an already-authenticated _user_ session with owner privileges and, on this account's plan, service-account creation and rotation are web-console operations. A service account also cannot mint or rotate itself — that is the whole point of the privilege boundary. Do not go looking for a flag that does this; open the browser.

1. Sign in to the 1Password web console as the account owner.
2. **Developer → Service Accounts** (or **Integrations → Service Accounts**, depending on the console version).
3. Find the existing service account for the Claude Automation vault. **Do not delete or rotate it yet.**
4. Create a **new** service account — or a new token on the existing one if the console offers token rotation with an overlap window. Scope it to the **Claude Automation vault only**, with the same read/write permissions the current one has. Do not widen the scope while you are here; a compromised-credential rotation is the worst moment to also change the blast radius.
5. The console shows the new token **exactly once**. Do not paste it into a terminal, a chat, an editor buffer, or this file. Copy it to the clipboard and go straight to §3.2.

> A note on this vault specifically: the Claude Automation 1Password vault **has another owner**. Several scopes have already been migrated off it into self-custody for exactly that reason (`ccmax-groups`, `cpc-smlatcpc`, `cpc-honeywell`, `tlg`, and others record this in their scope descriptions). If the Claude Automation vault no longer needs to hold anything that this machine reads, the strategically correct fix is to finish that migration rather than to rotate a token into the same shared vault. That is a larger decision than this runbook — but flag it, because rotating is not the same as fixing.

### 3.2 Store the new token via the `vault` CLI, not a flat file

`vault` is present at `~/.local/bin/vault` and is the self-custody credential manager (SOPS/age + Keychain + iCloud). It supports a stdin path whose entire purpose is this situation — its own help text says the value "never touches argv/transcript":

```bash
vault set --stdin <scope> <dot.path>
```

There is **no existing vault scope for the 1Password service account** (checked 2026-09-05 — no scope matching `op`/`1pass`/`onep`). Create one:

```bash
set -euo pipefail
vault new-scope onepassword-claude-automation "1Password service-account token for the shared 'Claude Automation' vault. ROTATED 2026-09-05 after the op-token-injector PreToolUse hook was found writing the previous value verbatim into 91 Claude Code transcript and background-task files. The vault has a second owner; migrating consumers off it entirely is the preferred long-term fix."
```

Then paste the token into the stdin prompt without it appearing in argv or shell history. The pattern already used in this fleet (from the `github-notify` scope description) is `<producer> | vault set --stdin <scope> <path>`; here the producer is your clipboard, so:

```bash
pbpaste | vault set --stdin onepassword-claude-automation token
```

Immediately clear the clipboard: `pbcopy </dev/null`.

**Feasibility caveat, stated honestly.** The injector hook reads a _file_, not a vault scope — `OP_TOKEN_PATH` is hardcoded to `~/.claude/.secrets/op-service-account-token`, and the hook runs on every Bash tool call, where a SOPS decrypt plus a possible Touch-ID prompt is not viable latency. So a flat file at that path is still required for the hook to function _today_. The realistic target state is: **vault is the SSoT, the flat file is a derived cache.** Write both, with vault first so the authoritative copy exists before the cache:

```bash
set -euo pipefail
umask 077
vault get onepassword-claude-automation token > ~/.claude/.secrets/op-service-account-token.new
chmod 600 ~/.claude/.secrets/op-service-account-token.new
```

Note this writes the value to a file by redirection — it is never rendered to the terminal. **Do not** run `vault get ...` without a redirect.

Leave the `.new` file in place for now; §3.3 swaps it in. Making the hook itself read from vault with a cached decrypt is a follow-up change, not part of this rotation.

### 3.3 Swap in the new value and update consumers

The old file is still needed by §5's audit, so **move it aside, do not delete it**:

```bash
set -euo pipefail
cd ~/.claude/.secrets
cp -p op-service-account-token op-service-account-token.OLD-2026-09-05
chmod 600 op-service-account-token.OLD-2026-09-05
mv op-service-account-token.new op-service-account-token
```

Every consumer in §1.1 that reads the file at `~/.claude/.secrets/op-service-account-token` now picks up the new value with no further change — that is the benefit of the shared path. Consumers that hold their own copy of the value (check each; the `grep -c` counts in §1.1 tell you which reference the _path_ rather than embedding a value) must be updated individually.

Restart the one launchd job:

```bash
launchctl kickstart -k gui/$(id -u)/com.terryli.lark-hlf-monitor
```

---

## 4. Verification

### 4.1 The new token works

Run one read-only `op` command against the vault. It must exit 0. Do not use a command that prints a secret — `item list` prints item names and IDs, not values:

```bash
set -uo pipefail          # NOT -e: see the note below, this block must survive a failure
rc=0
OP_SERVICE_ACCOUNT_TOKEN="$(cat ~/.claude/.secrets/op-service-account-token)" \
  op item list --vault "Claude Automation" >/tmp/op-verify.log 2>&1 || rc=$?
echo "op exit code: $rc"
```

`rc=0` is the pass condition. Read the exit code directly — **never through a pipe**, because a pipe returns the last command's status, not `op`'s. If `rc` is non-zero, inspect `/tmp/op-verify.log` (it contains an error message, not a secret) and delete it when done.

**Why this block deliberately omits `-e`, and why the `|| rc=$?` is load-bearing.** An earlier draft of this very section used `set -euo pipefail` with a bare `rc=$?` on the following line. Under `-e` the shell terminates at the failing `op` line, so `echo "op exit code: $rc"` never executes and the operator sees **completely empty output** — indistinguishable from a check that never ran. Verified by running the identical construct against a failing command: script exit 1, stdout empty. A verification step that prints nothing on failure is worse than no verification step, because silence reads as "nothing to report". The `|| rc=$?` form captures the status without letting `-e` fire; keeping `-u` and `pipefail` costs nothing.

Setting the variable explicitly here also means the injector hook skips the command, so this verification does not itself depend on §0.1 having landed.

### 4.2 The new token is NOT on disk in plaintext

This is the check that proves the fix worked. It must return **0**.

```bash
set -uo pipefail          # NOT -e: a zero-match grep exits 1, and zero can be the pass condition
TOKEN_FILE=~/.claude/.secrets/op-service-account-token
grep -rlF -f <(grep -v '^$' "$TOKEN_FILE") ~/.claude/projects /private/tmp/claude-501 2>/dev/null | wc -l || true
```

**Expected: `0`.** Any non-zero result means the injector fix is not actually live, or another code path is writing the value — stop and find it before continuing, because rotating again without finding it just burns another token.

Run this again after a deliberate `op` call against the vault (§4.1 counts), so you are testing the _post-fix_ write path and not merely a token that has not been used yet.

### 4.3 Every consumer still works

Exercise the §1.1 consumers you actually depend on. At minimum: the Lark monitor (check its log after the kickstart), the Pushover send path, and any publish script you are likely to run this week. A consumer that fails here fails while the old token is **still valid**, which is exactly the safety margin §0 Constraint C bought you — fix it now.

### 4.4 Revoke the old token — last, and only now

Only after §4.1, §4.2 and §4.3 all pass:

1. Return to the 1Password web console.
2. Revoke or delete the **old** service account / token.
3. Re-run §4.3's spot checks. Anything that breaks now was reading the old token from a copy you did not find — locate it via §1's grep and point it at the file path.

---

## 5. 🔴 The sequencing rule learned today — delete the credential file LAST

**The leak audit reads its search pattern FROM the credential file. Destroy the file first and you have destroyed the only means of locating its own copies by literal match.**

This is not a stylistic preference. The 91 plaintext copies are located by matching the literal 860-byte string. That string exists in exactly one place you control and can read safely — the file. There is no hash, no fingerprint and no prefix recorded anywhere else that would let you find the copies afterward. If you `rm` the old token file and _then_ go looking for its copies, you are reduced to grepping for `op_`-shaped prefixes across two retained directories and eyeballing the results, which is both unreliable and, because it surfaces candidate secrets on your terminal, actively dangerous.

Therefore, the correct order for the cleanup phase is:

1. Rotate and verify (§3, §4) — the old token is now **revoked and worthless**, but the file still exists.
2. Use `op-service-account-token.OLD-2026-09-05` as the pattern source to find every plaintext copy:

   ```bash
   set -uo pipefail          # NOT -e: grep exits 1 on zero matches, which is the PASS condition here
   OLD=~/.claude/.secrets/op-service-account-token.OLD-2026-09-05
   grep -rlF -f <(grep -v '^$' "$OLD") ~/.claude/projects /private/tmp/claude-501 2>/dev/null > /tmp/leaked-files.txt || true
   wc -l < /tmp/leaked-files.txt
   ```

   Expected: 91. `/tmp/leaked-files.txt` contains **paths only** — no values — and is safe to read.

3. Purge those files (see §6 — this is a separate decision, not an automatic `rm`).
4. Re-run step 2. It must return 0.
5. **Only now** delete the old token file:

   ```bash
   rm -P ~/.claude/.secrets/op-service-account-token.OLD-2026-09-05
   ```

   and delete `/tmp/leaked-files.txt`.

If you find yourself at step 5 before step 4 has returned 0, you are about to lose your search key. Stop.

---

## 6. What this does NOT fix

**Rotation makes the 91 plaintext copies worthless. It does not make them absent.** These are two different problems and finishing this runbook only solves the first.

What remains open after a successful rotation:

- **91 files still contain a real-looking 1Password service-account token in plaintext**, across `~/.claude/projects` (58) and `/private/tmp/claude-501` (33). Both locations retain. Anything that reads, syncs, backs up or exfiltrates those directories still gets a credential-shaped string. It no longer authenticates, but it is still a credential in a transcript, and it will still trip any secret scanner that looks at those paths — correctly.
- **Purging them is a separate operation with its own risks.** `~/.claude/projects` holds session transcripts that are the substrate for per-session auto-memory and the MemPalace semantic index; deleting or rewriting files there has consequences beyond this incident. Decide deliberately whether to redact in place, delete whole transcripts, or leave them and rely on the rotation. Do not let an agent bulk-`rm` them as a cleanup afterthought.
- **Backups and syncs may already hold copies.** Time Machine, iCloud, any transcript-export tooling, and the `~/eon/bruntwork/MDNasim/session-transcripts-*` archive pattern all mean copies may exist outside the two directories audited here. Rotation is what actually protects you from those, because you will not reliably purge them.
- **The structural cause is unaddressed.** The hook no longer writes the value, but the design still has a long-lived, high-privilege, flat-file credential read on every Bash tool call. The durable fix is to move the Claude Automation dependency into self-custody (`vault`), as several scopes have already done, and to shrink what this token can reach. Rotating a token into a vault that has a second owner buys time, not safety.
- **The credential registry and docs still describe the old token.** `docs/1password-credential-registry.md` and the various `CLAUDE.md` / `PITFALLS.md` entries listed in §1.2 should get a dated rotation note. Nothing breaks if you skip this; the next person's mental model does.

---

## Appendix — commands used to derive §1, for re-auditing later

```bash
# Files that reference the token file PATH (candidate real consumers)
grep -rl --binary-files=without-match 'op-service-account-token' ~/.claude ~/eon ~/own ~/vj 2>/dev/null \
  | grep -v -e '/node_modules/' -e '/\.git/' -e '/projects/' -e 'worktrees/' -e '/\.venv/' -e 'session-transcripts'

# Files that reference the ENV VAR name (superset; includes docs and tests)
grep -rl --binary-files=without-match -e 'OP_SERVICE_ACCOUNT_TOKEN' -e 'op-service-account-token' \
  ~/.claude ~/eon ~/own ~/vj 2>/dev/null | grep -v -e '/node_modules/' -e '/\.git/' -e '/projects/' \
  -e 'worktrees/' -e '/\.venv/' -e 'session-transcripts' | wc -l    # 118 on 2026-09-05

# launchd jobs in the blast radius
grep -rl --binary-files=without-match 'hlf-monitor' ~/Library/LaunchAgents
```

Both searches match on **names**, never on the value. Keep it that way when you re-run them.
