# Example specs (illustrative — not auto-run)

These templates demonstrate additional token shapes. The empirical campaign
(`test/campaign.mjs`) only scans the top-level `specs/*.json`, so nothing here is
created automatically.

| Spec                          | Shows                                                                                                |
| ----------------------------- | ---------------------------------------------------------------------------------------------------- |
| `all-repositories-admin.json` | `repositoryAccess.mode: "all"` + `Administration` write. Broad — prefer a scoped token.              |
| `org-owned.json`              | An **org-owned** token: set `owner` to an org you administer (the org must allow fine-grained PATs). |
| `dependabot-secrets.json`     | Secrets-management permissions (`Dependabot secrets`, `Secrets`, `Secret scanning alerts`).          |

## Before relying on one

1. Edit the placeholders (`owner`, `repos`).
2. **Confirm each permission's detail-page noun** if you want campaign-style
   verification: create the token once, read its settings page, and add the
   label→noun mapping to `test/campaign.mjs` (`NOUN`). The detail page uses
   friendly nouns (e.g. `Webhooks` → `repository hooks`), not the UI labels —
   see the skill's `CLAUDE.md`.
3. Create it:

   ```bash
   node scripts/pat.mjs create specs/examples/<name>.json --vault <scope>:<dot.path>
   ```
