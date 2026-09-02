# Private config setup (per-user secrets)

`pushover-commander` is public + generic. Your Pushover account, 1Password item,
and app tokens never live in this repo — they live privately under your own
`~/.claude`. This is the dotfiles model: public tool, private secrets.

## One-time setup

Pick **one** store for your secrets. The resolver tries three, in this order, and takes the first hit — a self-custody `vault` scope, then 1Password, then the macOS Keychain. Self-custody is first because it is offline and operator-controlled; 1Password is last resort.

### Option A — self-custody `vault` (preferred)

```bash
vault new-scope pushover-dashboard "pushover.net dashboard credentials"
vault set pushover-dashboard login_email
vault set pushover-dashboard login_password
vault set pushover-dashboard user_key
```

Override the scope name with `PUSHOVER_VAULT_SCOPE` if you want a different one. Leave `PUSHOVER_OP_*` unset. You still need the private `.local.env` from step 2 below if you want to set any of the optional overrides, but it can be empty otherwise.

### Option B — 1Password

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
   ROOT="$(cc-plugin-root pushover-commander)"
   cp "$ROOT/skills/_lib/pushover-commander.local.env.example" \
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
   bash "$(cc-plugin-root pushover-commander)/skills/_lib/resolve_pushover_secret.sh" user_key
   ```

## How resolution works

`resolve_pushover_secret.sh <field>`:

1. sources `~/.claude/pushover-commander.private/pushover-commander.local.env` (override path with `PUSHOVER_COMMANDER_PRIVATE_CONFIG`);
2. reads `vault get $PUSHOVER_VAULT_SCOPE <field>` from the self-custody vault (default scope `pushover-dashboard`), skipped silently if `vault` is not installed;
3. reads `op://$PUSHOVER_OP_VAULT/$PUSHOVER_OP_ITEM/<field>` via the 1Password CLI (using a Service Account token at `$PUSHOVER_OP_SA_TOKEN_FILE` if present, for non-interactive reads), skipped unless BOTH vars are set;
4. falls back to the macOS Keychain service `$PUSHOVER_KEYCHAIN_SERVICE` (default `pushover-commander`);
5. **fails loud** if nothing resolves — and the message reports the state of each of the three legs separately, so "not configured" is distinguishable from "configured but empty". That distinction is not cosmetic: this resolver once reported a secret missing for two weeks when the 1Password leg had been deliberately switched off and the Keychain leg had never received the two login fields a migration note claimed it had. Neither store held them, and one undifferentiated error message said so in a way that read as "the secret does not exist".

## No 1Password? Keychain-only

```bash
security add-generic-password -s pushover-commander -a user_key -w "<your user key>"
# repeat for login_email, login_password, api_token_test, ...
```

Then leave `PUSHOVER_OP_*` unset; the resolver uses the Keychain directly.

⚠️ If you move secrets between stores, **verify the destination field by field** rather than trusting the note you wrote about the move. `security find-generic-password -s pushover-commander -a <field> -w >/dev/null` per field, and check the fields you did NOT expect to be there too — a partial migration whose note claims completeness is worse than no migration, because the note stops anyone looking.

## Forking this plugin

Nothing here is specific to any one user. Create your own vault scope, 1Password item, or Keychain entries, plus your own private `.local.env`, and every skill works against your account. The repo stays secret-free.
