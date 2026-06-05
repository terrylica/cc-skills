# Private config setup (per-user secrets)

`pushover-commander` is public + generic. Your Pushover account, 1Password item,
and app tokens never live in this repo — they live privately under your own
`~/.claude`. This is the dotfiles model: public tool, private secrets.

## One-time setup

1. **Create a 1Password item** holding your Pushover secrets, with these fields:

   | field            | value                                                              |
   | ---------------- | ------------------------------------------------------------------ |
   | `login_email`    | your pushover.net account email (for headless web-control login)   |
   | `login_password` | your pushover.net account password                                 |
   | `user_key`       | your Pushover user key                                             |
   | `device`         | (optional) a default device name                                   |
   | `api_token_main` | (optional) production app token for `send-notification --app main` |
   | `api_token_test` | (optional) test app token (the default for `send-notification`)    |

2. **Copy the template** to your private, gitignored location and fill it in:

   ```bash
   mkdir -p ~/.claude/pushover-commander.private
   cp "${CLAUDE_PLUGIN_ROOT}/skills/_lib/pushover-commander.local.env.example" \
      ~/.claude/pushover-commander.private/pushover-commander.local.env
   chmod 600 ~/.claude/pushover-commander.private/pushover-commander.local.env
   ```

   Edit it and set at minimum:

   ```bash
   export PUSHOVER_OP_VAULT="Your 1Password Vault"
   export PUSHOVER_OP_ITEM="Your Pushover Item Name Or ID"
   ```

3. **Verify** it resolves (should print your user key, no error):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/resolve_pushover_secret.sh" user_key
   ```

## How resolution works

`resolve_pushover_secret.sh <field>`:

1. sources `~/.claude/pushover-commander.private/pushover-commander.local.env`
   (override path with `PUSHOVER_COMMANDER_PRIVATE_CONFIG`);
2. reads `op://$PUSHOVER_OP_VAULT/$PUSHOVER_OP_ITEM/<field>` via the 1Password CLI
   (using a Service Account token at `$PUSHOVER_OP_SA_TOKEN_FILE` if present, for
   non-interactive reads);
3. falls back to the macOS Keychain service `$PUSHOVER_KEYCHAIN_SERVICE`
   (default `pushover-commander`);
4. **fails loud** with a clear message if nothing is configured — never silently.

## No 1Password? Keychain-only

```bash
security add-generic-password -s pushover-commander -a user_key -w "<your user key>"
# repeat for login_email, login_password, api_token_test, ...
```

Then leave `PUSHOVER_OP_*` unset; the resolver uses the Keychain directly.

## Forking this plugin

Nothing here is specific to any one user. Create your own 1Password item (or
Keychain entries) + your own private `.local.env`, and every skill works against
your account. The repo stays secret-free.
