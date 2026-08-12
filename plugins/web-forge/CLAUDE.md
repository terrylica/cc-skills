# CLAUDE.md — web-forge

> Supervised dashboard automation for operations with NO public API, plus the declarative
> Cloudflare Access wall built on top of it. Canonicalized 2026-07-23 after the rule of two:
> the gh-fine-grained-pat harness (April) drove a second vendor's dashboards unchanged
> (project-a: Cloudflare scoped-token forge + GitHub OAuth-app forge + Access wall, one
> supervised session).

## Structure

| Path                      | Role                                                                                                                                                                                                                                                                                                                             |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/browser-forge.mjs`   | **The shared harness (SSoT for NEW forges).** Per-SITE persistent Chrome profiles + CDP attach + `waitForLogin` + `assertIdentity` preflight + `dismissConsent` + screenshot breadcrumbs/purge + SCS-vault stdin sinks + generic API caller. node ONLY (Bun `connectOverCDP` times out).                                         |
| `skills/dashboard-forge/` | The METHOD skill — step-and-shoot doctrine, secrets discipline, Vendor Quirks drift log. Read it before writing any new forge.                                                                                                                                                                                                   |
| `skills/cf-access-wall/`  | Declarative JSON spec (Schema 2020-12) → idempotent Access provisioning + GitHub OAuth-app forge. Spec instances live in project repos, never here.                                                                                                                                                                              |
| `skills/azure-provision/` | Azure service-principal bootstrap when `az login` is Conditional-Access blocked (error 530035) but the portal is not. **Zero selectors**: the portal's own Graph token carries `Application.ReadWrite.All`, so the browser contributes a TOKEN, not clicks. Then RG + Cognitive Services via ARM, key+endpoint vaulted together. |

## Invariants (do not regress)

1. **node, not bun**, for anything touching `connectOverCDP`.
2. **Specific-PID teardown** via lsof on the CDP port — never `pkill -f` (process-storm policy,
   `~/.claude/CLAUDE.md`).
3. **Secrets**: DOM-extract → `vault set --stdin`. NEVER screenshot a secret-reveal page (a shot
   read back by the agent leaks the value into conversation context). `purgeShots()` at end of
   every run.
4. **Identity preflight** (`assertIdentity`) before creating any account-owned resource — the
   browser-world mirror of the GitHub-Owner-Per-Path doctrine.
5. **Hybrid rule**: browser-automate only the credential mint; everything after goes through the
   vendor's real API as a GET-before-POST idempotent bootstrap.
6. Profile dirs under `~/.local/share/web-forge/` hold live login sessions — sensitive, never
   committed, credential-equivalent.
7. **Never confirm a mutation from the same console's default list view.** Promoted from a
   vendor quirk to an invariant on 2026-08-12 under the rule of two: Azure Portal's "Owned
   applications" denied an app registration it had just created, and Google Admin's Groups list
   rendered "your organization doesn't have any groups yet" after a group was created. Both were
   convincing and both were false. Confirm from a DIFFERENT system — ideally one that would fail
   on a non-existent object, so the confirmation is a real test rather than a second opinion.
8. **A borrowed session is not an owned one.** Driving a browser a human already authenticated
   (AppleScript + `execute javascript`) is legitimate where a passkey or step-up must not be
   automated — you type inside a door somebody else opened, and never touch the credential. It
   has no sandbox: it can see every other tab. Never quit or restart the operator's browser.

## Boundary with gh-fine-grained-pat (gh-tools)

That skill keeps its own battle-tested harness copy + GitHub-specific machinery (autosudo /
webauthn / multi-account gated blobs). NEW forges use `lib/browser-forge.mjs`. Migrating the PAT
skill onto this lib is a deliberate future pass with its own testing — never a casual DRY edit.

## Privacy split (operator doctrine, 2026-07-23)

Agnostic/universal → this plugin (cc-skills, public repo): harness, method, schema, example
specs with placeholder values ONLY. Personal/secret → NEVER here: real spec instances (team
emails) live in each project's repo; credentials live in the SCS vault; login sessions live in
the local profile dirs; anything inherently personal belongs in `~/.claude` per the user-memory
hub policy.
