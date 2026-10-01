# chrome-profiles

Let Claude Code drive your **everyday Google Chrome on macOS** — the right signed-in profile, with no clicks — and pick a lighter route whenever a real browser is not needed.

## Quick start

```bash
claude plugin marketplace add terrylica/cc-skills
claude plugin install chrome-profiles@cc-skills

CP=~/.claude/plugins/marketplaces/cc-skills/plugins/chrome-profiles/scripts/chrome-profile.sh
bash "$CP" setup you@example.com      # per account: extension, token, MCP server
bash "$CP" setup-main                 # optional: one server that sees every profile
# restart Claude Code, then:
bash "$CP" doctor you@example.com
```

`setup` opens the Chrome Web Store page for Microsoft's Playwright Extension in that profile (you click _Add to Chrome_), opens the extension's status page, asks for its token in a hidden macOS dialog, stores it in your login Keychain, and registers a Claude Code MCP server pinned to that account.

## What is inside

| Path                                               | Purpose                                                                                  |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `skills/browser-automation/SKILL.md`               | When to use a browser at all, which route, and the rules that keep it safe               |
| `skills/browser-automation/references/doctrine.md` | The mechanics and measurements behind each rule                                          |
| `scripts/chrome-profile.sh`                        | `setup`, `setup-main`, `doctor`, `resolve`, `open`, `extension-status`, `playwright-mcp` |
| `scripts/chrome-debug-port-control.sh`             | `up` / `status` / `down` for a separate profile on a debug port                          |
| `scripts/fill-secret.mjs` | Types a Keychain or vault secret into one field of a page on a debug-port profile; the value never reaches the AI |

Requires macOS, Google Chrome 144+, Node 22+ (for `npx` and the built-in WebSocket that `fill-secret.mjs` uses) and Python 3. Nothing personal is stored in this plugin: accounts are typed in when you run it, and tokens live in your Keychain.
