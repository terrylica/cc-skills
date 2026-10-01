# chrome-profiles — maintainer notes

**Hub**: [plugins/CLAUDE.md](../CLAUDE.md) | **Sibling**: [README.md](./README.md)

The SSoT for driving a browser from Claude Code on macOS: the route ladder, choosing a Chrome profile by account email, and zero-click control of a signed-in profile through Microsoft's Playwright Extension. Other plugins that drive a browser link here rather than restating Chrome-136, debug-port or profile rules.

## Invariants

- **No personal data, ever.** This plugin is public. No real email address, account name, profile folder name, token, client or organisation appears in code, docs, tests or commit messages. Use `you@example.com`. Accounts are arguments; tokens live in the user's Keychain (or `vault`).
- **Resolve by email at run time.** Never store or document a `Profile N` folder name as configuration; `chrome-profile.sh` refuses zero or multiple matches.
- **Nothing launches the everyday Chrome with debug flags.** `open` only hands a URL to the running Chrome. Only `chrome-debug-port-control.sh` launches Chrome, and only on a separate `--user-data-dir`.
- **Secrets never touch argv, a chat, or stdout.** `setup` reads the token through a hidden dialog and stores it with `security -i` (hex on stdin).
- **Registered MCP commands use a stable path** (the marketplace checkout), never the versioned plugin cache.

## Recent changes

- 2026-09-30 — created. Moved from a private skill and tools, with `setup` / `setup-main` added so a fresh Mac can reach no-click automation with one command per account.
