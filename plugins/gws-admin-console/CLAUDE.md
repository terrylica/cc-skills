# gws-admin-console — maintainer notes

**Hub**: [plugins/CLAUDE.md](../CLAUDE.md) | **Sibling**: [README.md](./README.md) | **Skill**: [admin-console](./skills/admin-console/SKILL.md)

A reusable harness for Google Workspace Admin console settings that no API reaches. It drives a signed-in Chrome profile through Microsoft's Playwright Extension (via the **chrome-profiles** plugin) and runs recipes: data-driven form operations with idempotent ensure and read-back verification.

## Layout

| Path                                | Role                                                                                                                                     |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `scripts/gws-admin-console.ts`      | CLI: `recipes`, `<recipe> <verb>`, `serve`, `stop`. JSON on stdout, progress on stderr                                                   |
| `scripts/lib/mcp.ts`                | Transports: one-run stdio session, or the long-lived bridge from `serve` (GET `/info` names its account; a mismatched bridge is refused) |
| `scripts/lib/page.ts`               | `PRELUDE` (page-side primitives), `buildStepCode`, `parseRunCodeResult`, `Driver` (step + screenshots)                                   |
| `scripts/lib/form.ts`               | `FormOp` data type, `applyOps`, `READ_FORM`, `PRESS_DIALOG_BUTTON`                                                                       |
| `scripts/lib/reauth.ts`             | `classifyPage`, the re-authentication gate, operator alerts                                                                              |
| `scripts/lib/args.ts`               | Declarative flag parser; the FlagSpec list is also the machine-readable CLI description                                                  |
| `scripts/recipes/*.ts` + `index.ts` | One module per recipe, registered in the index                                                                                           |
| `scripts/**/*.test.ts`              | Unit tests of the pure parts (run by `moon run repo:test`)                                                                               |

## Invariants

- **Public plugin: no tenant data.** No real domain, address, group, rule ID, screenshot or customer name in code, tests, docs or commit messages. Fixtures use example.com; captured live shapes are anonymised first. Each tenant's invocation is recorded in that tenant's own repository.
- **Never type a password or any credential.** Re-authentication is detected, the operator is alerted, the tab is polled and never reloaded.
- **Selectors by accessible role and visible label text**, never CSS classes or jsnames.
- **Every click is `bringToFront()` + `{ force: true }`**; `dispatchEvent` does not work on the console.
- **Never leave a half-filled form**: a failed step before Save screenshots, cancels and reloads.
- **Read back from a fresh page load** through the rule's Edit dialog, never from the view that just saved, and never from the lossy table text alone.
- **Page-side code is source text** run by `browser_run_code_unsafe`; arguments go in as a JSON literal only.
- **Server output stays out of repositories**: the MCP server runs in a private temp directory; screenshots go where `--screenshots` says or to `~/.local/state/gws-admin-console/failures/`.

## Recent changes

- 2026-10-19 — created, with the `gmail-default-routing` recipe. Measured the Select Groups picker (row click selects; close with "Close dialog"), the checkbox label structure, the lossy rules table, and the missing description field.
