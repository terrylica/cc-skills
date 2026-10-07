---
name: mailbox-consolidation
description: "Consolidate several legacy email addresses (consumer @gmail.com accounts and mailboxes in other Google Workspace tenants) into one shared Workspace hub inbox: pick the right forwarding mechanism per source, migrate the history without a gap, keep spam checks from silently swallowing copies, and prove each path end to end. Use when setting up or debugging forwarding into a shared inbox, when 'forwarding is on but mail does not arrive', or before a Gmail history import. TRIGGERS - consolidate mailboxes, forward to shared inbox, gmail forwarding not working, routing rule also deliver to, additional recipient, mail not copied, data migration gmail, final delta import, forwarding verification code, do not deliver spam to this recipient, email log search."
allowed-tools: Read, Bash, Grep, Glob, AskUserQuestion
---

# Mailbox consolidation into one Workspace hub

> **Self-Evolving Skill**: This skill improves through use. If a step is wrong, Google changed behaviour, or a workaround was needed, fix this file immediately. Only record real, reproducible findings, and **never add a real address, domain, tenant, rule ID or customer detail**: this plugin is public.

The setup: one **hub** mailbox in a Google Workspace tenant (a shared front-desk inbox) receives everything that used to go to several **sources**. Each source keeps its own copy. Staff reply from the hub using "send mail as" for each source, so families or customers see no change.

Each source type gets a different mechanism, and each mechanism fails silently in its own way. The rules below were all measured, not taken from documentation.

## 1. Survey first: read the live state, never the plan

Before changing anything, read each mailbox's actual settings through the Gmail API. Reading needs only `gmail.settings.basic` or `gmail.readonly`, and it can be done for consumer accounts too.

```text
GET users/me/settings/autoForwarding        → {"enabled": false} means nothing is forwarded, whatever the docs say
GET users/me/settings/forwardingAddresses   → is the hub even listed, and is it "accepted" or "pending"?
GET users/me/settings/filters               → filters that archive, delete or forward
```

Then prove where the hub's mail actually came from, using **metadata only** (no bodies). The `Delivered-To` chain tells the three routes apart:

| Route                                | `Delivered-To` on the hub's copy | `To:` header |
| ------------------------------------ | -------------------------------- | ------------ |
| History import (Data migration)      | hub **and** source               | source       |
| Consumer-Gmail auto-forwarding       | hub **and** source               | source       |
| Admin routing rule "Also deliver to" | hub only                         | source       |

Imported and forwarded copies look alike, so use dates. If the newest source-addressed message in the hub is older than mail the source received since, **forwarding is off** and only the import ever ran.

Practicalities:

- The `gmail.metadata` scope rejects the `q=` search parameter, so list by label or page through, then filter on `internalDate`.
- `messages.get` in a loop hits the per-user "Total Query Cost" quota (403) within seconds. Sleep about 150–250 ms per call.

## 2. Pick the mechanism per source

| Source                                  | Mechanism                                                                                                                                                        | Automatable?                                                                                                                                                                                                                           |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Consumer `@gmail.com`**               | Gmail → Settings → Forwarding and POP/IMAP → add the hub → a confirmation code arrives **in the hub** (in its subject) → choose "keep Gmail's copy in the Inbox" | **No API.** `forwardingAddresses.create` and `updateAutoForwarding` need a service account with domain-wide delegation, which only Workspace has. One manual UI pass; a browser profile signed in to both mailboxes can read the code. |
| **Mailbox in another Workspace tenant** | Admin console → Apps → Gmail → **Routing** rule: Inbound + Internal-receiving, envelope recipient = the source, **Also deliver to** the hub                      | Admin UI. User-level forwarding is often refused by the tenant ("Invalid forwarding address", with no verification flow offered). Prefer the routing rule: it works on Google's servers and survives password changes.                 |
| **Address in the hub's own tenant**     | An alias on the hub, or a routing rule                                                                                                                           | Directory API or Admin UI.                                                                                                                                                                                                             |

Opening the Admin console triggers a **password re-check** even in an already signed-in profile. A person, or a vault-backed form filler, has to complete it. Never type a password through an agent's browser tools, because the value would land in the transcript.

## 3. The trap that silently drops copies: spam

**Routing rules:** every additional recipient added under "Also deliver to" defaults to **"Do not deliver spam to this recipient"** and **"Suppress bounces from this recipient"**. When the source tenant classes a message as spam, the source still receives it, but **no copy goes to the hub and nobody gets a bounce**. A new outside sender with an odd subject (exactly what a test email looks like) is often scored "blatant spam", so the very first real test fails while internal tests pass.

Fix: rule → Edit → the additional recipient → **Advanced**:

- [ ] uncheck **Do not deliver spam to this recipient**
- [x] check **Add X-Gm-Spam and X-Gm-Phishy headers**, so the hub knows the source's verdict (`X-Gm-Spam: 0/1`)
- leave **Bypass spam filter for this message** off unless you mean it, because it also stops filtering the source's own copy.

Google also says some blatant spam is dropped at delivery whatever the settings ([control delivery by content](https://support.google.com/a/answer/1346936)).

**Consumer forwarding:** Gmail never forwards what the source classed as spam ([Gmail Help](https://support.google.com/mail/answer/10957)). Someone still has to check the source's Spam folder now and then.

**Hub side:** the hub runs its own spam check on every copy. Once the source has already filtered, a second check only adds false positives. Hub filters via API (`settings.filters.create`, action `removeLabelIds: ["SPAM"]`, which is "Never send to Spam" in the UI):

- `criteria.query: "deliveredto:<consumer-source>"` matches forwarded copies.
- `criteria.to: "<routed-source>"` matches routed copies, which carry only the hub in `Delivered-To`. It misses mail where the source was only Bcc'd.

Snapshot the hub's settings into a baseline file and diff them on a schedule. Settings drift is otherwise invisible.

## 4. History: forward first, then the final import

- The Admin **Data migration** / Data import for a Gmail source is a **snapshot**: only Exchange sources get mail that arrives during the migration ([Google](https://knowledge.workspace.google.com/admin/migrate/about-migrating-email-with-the-new-data-migration-service)). The user-level "Import mail and contacts" offers 30 days of new mail, but under the user's own control.
- **Sequence with no gap:** initial import → **switch forwarding on** → final delta import from the same source → compare message counts. Expect the hub to sit slightly below the source, because spam and trash are excluded by default. Re-running the migration skips messages it already copied.
- A routing rule only carries mail from the moment it is active. The routed source's **history needs its own import**. Say so explicitly; it is easy to forget once "forwarding works".
- Each consumer source needs its owner's consent for the import. Google emails an approval request that is valid for about 24 hours.
- Forwarding does **not** count as account activity. A consumer source that staff stop signing into can still be closed for inactivity.

## 5. Proving it, and diagnosing a "not working"

1. **Test from an outside consumer account** to the source. A test sent from the hub to the source is unreliable: Gmail merges the returning copy into the hub's Sent item (same Message-ID). Internal tests also skip the spam scoring that catches outside senders.
2. Look for the test in the hub **including Spam and Trash** (`includeSpamTrash=true`). Also check the copy's `X-Gm-Spam` header: a pass with `X-Gm-Spam: 0` proves the route but **not** the spam path.
3. If it is missing, open **Email Log Search** in the source tenant's Admin console and click into the message. The details page states the matched rules and whether it was "Marked spam" (and how strongly). On lower editions, a custom search needs a **date range**. It may also say "Message ID cannot be empty", but sender plus date range still returns results.
4. Rule out a configuration change with the **Reports API** (`admin.reports.audit.readonly`, `applications/admin`). Routing edits appear as `CHANGE_GMAIL_SETTING` / `UNIFIED_MAIL_ROUTING`, carrying the rule's description and ID. The same API is a cheap test of whether an account is an administrator: it returns 200 only for admins.
5. If **everything** stops at once (all sources, all senders), check the hub's domain before any setting: an expired registration put on `clientHold` returns NXDOMAIN, and every copy bounces.

## 6. Record as you go

Record each source's mechanism, rule ID, the date it went live and the test that proved it, in the project's own private records, never in this public skill. When a status turns out to be only partly true (for example "routed copies arrive", true only for non-spam), correct that record in the same change as the fix.

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did a mechanism behave differently from the table above?** For example, Google added an API for consumer forwarding, a routing default changed, or an import began carrying new mail. Fix the table, and note the date and what was measured.
2. **Did a test pass for the wrong reason?** For example, an internal sender, a self-send, or `X-Gm-Spam: 0` on a path meant to cover spam. Add it to section 5.
3. **Did anything project-specific land in this file?** That means an address, a domain, a rule ID or a customer name. Remove it; it belongs in the project's private records.
