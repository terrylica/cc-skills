# chrome-profiles — maintainer notes

**Hub**: [plugins/CLAUDE.md](../CLAUDE.md) | **Sibling**: [README.md](./README.md)

The SSoT for driving a browser from Claude Code on macOS: the route ladder, choosing a Chrome profile by account email, and zero-click control of a signed-in profile through Microsoft's Playwright Extension. Other plugins that drive a browser link here rather than restating Chrome-136, debug-port or profile rules.

## Invariants

- **No personal data, ever.** This plugin is public. No real email address, account name, profile folder name, token, client or organisation appears in code, docs, tests or commit messages. Use `you@example.com`. Accounts are arguments; tokens live in the user's Keychain (or `vault`).
- **Resolve by email at run time.** Never store or document a `Profile N` folder name as configuration; `chrome-profile.sh` refuses zero or multiple matches.
- **Nothing launches the everyday Chrome with debug flags.** `open` only hands a URL to the running Chrome. Only `chrome-debug-port-control.sh` launches Chrome, and only on a separate `--user-data-dir`.
- **Secrets never touch argv, a chat, or stdout.** `setup` reads the token from the profile's Local Storage (`extension-token-from-profile.ts`: a private 0700 copy, deleted after; the token leaves the reader only on fd 3, stdout carries a status line) and falls back to a hidden dialog; it stores it with `security -i` (hex on stdin).
- **Registered MCP commands use a stable path** (the marketplace checkout), never the versioned plugin cache.
- **Every run closes what it opened; nothing closes what it cannot name.** `tabs close` acts only on exact ids or a bounded URL match and never empties a window by default; `mcp-drive.ts` sweeps only tabs that appeared during its own run.
- **No route waits on a person.** `playwright-mcp` refuses without a token rather than opening the extension's connect page; the only automated press is the extension's own _Generate new token_ (`rotate-token`), scoped to the window titled with that email.
