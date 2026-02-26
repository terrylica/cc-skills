# Troubleshooting

| Issue                  | Cause                     | Solution                                 |
| ---------------------- | ------------------------- | ---------------------------------------- |
| Not a marketplace dir  | Missing marketplace.json  | Run from marketplace root directory      |
| Plugin already exists  | Directory or entry exists | Choose a different plugin name           |
| validate-plugins fails | Missing marketplace entry | Ensure plugin added to marketplace.json  |
| semantic-release fails | Missing GITHUB_TOKEN      | Check token with `echo $GITHUB_TOKEN`    |
| ADR creation fails     | docs/adr/ doesn't exist   | Create directory: `mkdir -p docs/adr`    |
| TodoWrite not executed | Skipped mandatory step    | Start from Phase 0 and execute TodoWrite |
