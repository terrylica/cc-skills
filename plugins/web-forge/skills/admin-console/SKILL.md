---
name: admin-console
description: Drive console-only Google Workspace Admin settings (admin.google.com) that no API or GAM can reach, through a signed-in Chrome profile chosen by admin email — recipes as data, idempotent ensure, read-back verification after Save, JSON result, a screenshot per step. First recipe gmail-default-routing (Gmail › Default routing rules: match a group, single address, pattern or everyone; change the envelope recipient, add X-Gm-Original-To). Handles the "verify it's you" re-authentication gate without ever typing a password. TRIGGERS - admin console, admin.google.com, Google Admin setting with no API, Gmail default routing, routing rule, change envelope recipient, X-Gm-Original-To, GAM cannot, Cloud Identity Policy API missing setting, verify it's you admin.
allowed-tools: Bash, Read
---

# admin-console — a harness for console-only Google Admin settings

> **Self-Evolving Skill**: This skill improves through use. When Google changes a console page, a step fails, or a control needs a new trick, fix the primitive in `scripts/lib/page.ts` or the recipe in `scripts/recipes/google-admin/`, add a unit test where the part is pure, and record the lesson here immediately. Only update for real, reproducible issues, and never add a real tenant, address, group or screenshot.

Some Google Workspace settings exist only in the Admin console: Gmail **Default routing** is absent from the Cloud Identity Policy API's supported settings, and GAM cannot set it. This skill drives those pages through your own signed-in Chrome profile, the same way every time, and proves the result by reading it back. It is the Google Admin recipe family of the web-forge recipe runner: the browser connection, step runner, screenshots, re-authentication gate and secret handling are web-forge's own, shared with every other recipe; the method behind them is the [dashboard-forge](../dashboard-forge/SKILL.md) skill.

Use an API whenever one exists. Reach for this only when the setting is console-only.

## Prerequisites

- The **chrome-profiles** plugin, with the admin account's Chrome profile set up for zero-click control: `chrome-profile.sh setup <admin-email>`, then `chrome-profile.sh doctor`. The default connection mode (`--connect extension`) reaches the browser through `chrome-profile.sh playwright-mcp <admin-email>`. `--connect cdp [--site <name>]` uses a persistent web-forge profile instead (default site `google-admin`; a human signs in there once). Google binds sessions to the profile's device key, so a copied cookie jar does not sign a cdp profile in (dashboard-forge Vendor Quirks, 2026-08-13).
- The account must be a Workspace administrator with rights to the page.

```bash
WF="$(cc-plugin-root web-forge)/scripts/web-forge.ts"
bun "$WF" --help            # human-readable flags
bun "$WF" recipes --json    # machine-readable: every recipe, verb, flag and exit code
```

## Run a recipe

```bash
# 1. Keep one browser session (one tab) open across runs. Optional but recommended: a re-auth prompt
#    passed in that tab stays passed for the next run. Runs in the foreground: background it.
bun "$WF" serve --account admin@example.com --port 47811 &

# 2. Plan only: navigate, fill the dialog, read the form back, then CANCEL. Nothing is saved.
bun "$WF" gmail-default-routing ensure --account admin@example.com --port 47811 \
  --description "Staff mail → shared inbox" --match group:staff-mail@example.com \
  --change-envelope-recipient inbox@example.com --add-original-to-header --scope non-recognized \
  --dry-run --screenshots ./shots

# 3. The same command without --dry-run creates the rule and verifies it; with --verify it only reads back.
bun "$WF" stop --port 47811
```

Without `--port` (or `WEB_FORGE_BRIDGE_PORT`) each run opens its own session; in extension mode Microsoft's extension then attaches to a **fresh tab**, which stays open afterwards. A bridge that serves a different target (another account, or another cdp site) is refused, so a run cannot drive the wrong identity. Any flag set can also come from a JSON file kept in the tenant's own repository: `--spec routing.json` (`{"account": "…", "match": "group:…", "add-original-to-header": true}`); flags on the command line win.

**Output:** one JSON object on stdout (`ok`, `action`, `spec`, `rule`, `observed`, `diff`, `steps`); progress and screenshot paths on stderr. **Exit codes:** 0 ok · 1 failed or read-back mismatch · 2 usage · 3 rule exists but differs and `--update` was not given · 4 sign-in or re-authentication not completed in time.

### `gmail-default-routing ensure`

| Flag                                                                   | Meaning                                                                                        |
| ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `--match group:<email>` · `single:<email>` · `pattern:<regex>` · `all` | Envelope recipients to match                                                                   |
| `--change-envelope-recipient <email>`                                  | Tick "Change envelope recipient", choose "Replace recipient", enter the address                |
| `--add-original-to-header`                                             | Tick "Add X-Gm-Original-To header"                                                             |
| `--scope non-recognized` (default) · `all`                             | Only addresses with no mailbox, or recognized ones too                                         |
| `--description <text>`                                                 | Your label, returned in the JSON only: **the Default routing dialog has no description field** |
| `--dry-run` · `--verify` · `--update`                                  | Plan and cancel · read back only · change an existing rule that differs                        |

Every other "Modify message" checkbox is set **clear**: the rule matches the spec exactly or it is reported as different.

**Idempotency.** A rule's identity is its **match** (kind + value), because Google stores no description. The rules table is lossy (a group rule reads "Group membership:" plus a fragment of the group's display name, never its address, and every modify action reads "Rewrite message"), so the table only narrows by match kind; the harness then opens each candidate's **Edit setting** dialog, reads the full form, and cancels. Same match and same form: nothing is done (`unchanged`). Same match, different form: the differences are reported and nothing changes unless `--update` is given. Two rules with the same match: `ambiguous`, resolve by hand.

**Read-back.** After Save the page is reloaded, the rule is found again and its Edit dialog is read and compared field by field. A mismatch exits 1. This is still the same console: an end-to-end mail test (or Email Log Search) is the independent confirmation.

## Re-authentication policy ("verify it's you")

The Admin console periodically sends an administrator to accounts.google.com for a fresh password before admin pages. The shared gate (`scripts/lib/gate.ts`), with this family's classifier (`scripts/recipes/google-admin/family.ts`):

1. **Detects** it (host `accounts.google.com` with "Verify it's you", "Enter your password" or "To continue, first verify"; any other accounts.google.com page counts as sign-in).
2. **Never types a password** or any credential. There is no flag to make it.
3. **Alerts** the operator: `--alert local` (default) posts a desktop notice through `~/.claude/tools/notify` when present; `--alert emergency` also sends a Pushover Emergency (priority 2, retry 60 s, expire 600 s) through the pushover-commander plugin with the HTTP(S) proxy variables removed. The core is called with `--no-wait`, so it returns once Pushover accepted the page instead of polling for the acknowledgement; the log then reads `emergency alert sent`, and a real failure names its exit code, signal or spawn error. Use `emergency` for crown-level admin steps.
4. **Polls the tab without reloading it** (every 5 s, up to `--reauth-wait`, default 600 s), because a reload discards what the operator is typing. When the tab reaches admin.google.com the run continues.
5. On timeout it exits 4. If the check was passed in a **different** tab of the same profile, this tab does not notice: just re-run, the command is idempotent.

## Lessons baked into the primitives (measured 2026-10-19)

- **Background tabs.** Playwright's normal click waits for "visible, enabled and stable" and hangs in a background tab, or hits the MCP's short action timeout. Every step calls `page.bringToFront()` and clicks with `{ force: true }`. Synthetic `dispatchEvent` clicks are ignored by the console (jsaction wants real input events).
- **Listboxes** (Material): click the listbox, then the `option` by name, then confirm the listbox's selected option.
- **Checkboxes** have no accessible name: the words are a sibling. Find the label text, climb to the **nearest ancestor that contains a `role=checkbox`**, use that checkbox. (Its direct parent holds only the text.)
- **Text fields** are textareas with an `aria-label` ("Enter new email address", "Email address:", "Regexp Learn more").
- **The "Select Groups" picker — the answer.** Type the address into "Search Groups", then click the matching **row**: the click selects the group at once (it appears in the outer dialog as "Name(email)" with a Delete link). There is **no checkbox and no confirm button**; the picker is multi-select and stays open, so close it with its **"Close dialog"** (X) button. While it is open the outer dialog is aria-hidden, so role queries for the outer dialog find nothing. A row click that "did nothing" earlier was in fact a selection hidden behind the still-open picker: look at a screenshot, not just the accessibility tree.
- **Row text matching:** Playwright's `hasText` matches `textContent`, where a `<br>` leaves no space ("Name (x)<name@example.com>"), so an address is bounded by any character that cannot belong to one, not by whitespace.
- **Save** closes the dialog, toasts "Default routing settings updated", and the table shows the new rule (Order, Status Enabled, Actions "Edit - Disable - Delete - Reorder", a short ID). No page-level save step.
- **Failure path:** any failed step saves a screenshot (with `--screenshots`, or under `~/.local/state/web-forge/failures/`), presses **Cancel**, and reloads the page, so a half-filled rule is never saved.

## Debug visually

Pass `--screenshots <dir>` to save one PNG per step (failures are always saved, by default under `~/.local/state/web-forge/failures/`) (navigation, dialog open, every selection, Save, read-back), then read them. The console is complicated; the accessibility tree alone misled us once (above). Keep screenshots out of repositories: they show tenant data.

## Add a recipe

1. Explore the page by hand through a bridge (`serve`), taking screenshots after every action. Write down accessible roles and visible label text, never CSS classes.
2. Create `scripts/recipes/google-admin/<name>.ts` (another console: a new `scripts/recipes/<family>/` with a `family.ts` classifier) exporting: `URL`, the dialog name regex, `LABELS`, `FLAGS` (a `FlagSpec[]`), and **pure** functions `specFromFlags`, `planForm(spec) → FormOp[]`, `observedFromForm(FormState)`, `diffRule`, plus `run(verb, flags, driver, gate)`. Reuse `applyOps`, `READ_FORM`, `PRESS_DIALOG_BUTTON`, `Driver.extractToVault` (for any secret the page reveals) and the primitives in `scripts/lib/page.ts` (`select`, `tick`, `fill`, `radio`, `pick`, `readForm`, `readGrid`). Add a primitive there only when a new control type needs one.
3. Register it in `scripts/recipes/index.ts` with its `family`; `--help` and `recipes --json` pick it up.
4. Unit-test the pure parts with a FormState **captured from the live page and anonymised** (example.com). Live steps are tested only by a live `--dry-run`, then the real run, then `--verify`.
5. Record each project's invocation in that project's repository, never here: this plugin is public.

## Known fragility

Google changes the console without notice. Selectors use accessible roles and the words on screen, so a reworded label ("Change envelope recipient") or a restructured dialog breaks a recipe loudly (a step fails, a screenshot is saved, the dialog is cancelled) rather than silently. The English UI is assumed. Tested live: create, `--dry-run`, `--verify`, `unchanged`, `differs`. Not yet exercised live: `--connect cdp`, `--update`, `single`/`pattern`/`all` matches, and the re-authentication wait (classification is unit-tested).

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the read-back agree with what the screenshots show?** If `observed` and the Edit dialog disagree, fix `readForm` or the recipe's `observedFromForm` and add the captured (anonymised) shape as a test fixture.
2. **Did a step need a retry, a different click, or a longer wait?** Fold it into the primitive and the "Lessons" section, with the date.
3. **Did any tenant data reach this public plugin** (a domain, address, rule ID or screenshot in a file, test or commit)? Remove it before pushing.

Only update if the issue is real and reproducible — not speculative.
