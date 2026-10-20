# gws-admin-console

Drive Google Workspace Admin console settings that have **no API** (and that GAM cannot set) through your own signed-in Chrome profile, with recipes that are idempotent and verified by reading the setting back.

- **Recipes as data.** A recipe turns flags into a list of form operations (select, pick, tick, fill, choose), replays them, reads the whole form back before saving, saves, reloads, and compares again. JSON result on stdout; distinct exit codes for "differs" and "re-authentication pending".
- **First recipe:** `gmail-default-routing ensure` — Gmail › Default routing rules (match a group, a single address, a pattern or all recipients; change the envelope recipient; add the X-Gm-Original-To header; recognized or non-recognized addresses).
- **Safe by default:** `--dry-run` fills the dialog and cancels; a failed step cancels and reloads; the "verify it's you" prompt is detected and handed to a human, never answered by the tool.
- **Debuggable:** `--screenshots <dir>` saves a PNG after every step; failures are always captured.

Requires the [chrome-profiles](../chrome-profiles/README.md) plugin with the admin account's profile set up (`chrome-profile.sh setup you@example.com`).

```bash
GAC="$(cc-plugin-root gws-admin-console)/scripts/gws-admin-console.ts"
bun "$GAC" recipes --json
bun "$GAC" gmail-default-routing ensure --account admin@example.com \
  --match group:team@example.com --change-envelope-recipient inbox@example.com \
  --add-original-to-header --dry-run --screenshots ./shots
```

Full usage, the re-authentication policy and how to add a recipe: [skills/admin-console/SKILL.md](./skills/admin-console/SKILL.md).
