# 1Password Credential Registry

SSoT for all 1Password items Claude Code uses programmatically via `op` CLI.

## Service Account Tokens

| Token                                            | Vault             | Permissions                    | Item ID                      | Expires    |
| ------------------------------------------------ | ----------------- | ------------------------------ | ---------------------------- | ---------- |
| **Claude Automation 3** (primary, write-enabled) | Claude Automation | read/write items, ACL, devices | `f7zsfibfvzluw4ahe2qxv3ddee` | 2026-07-13 |

**Retrieval**: `op item get f7zsfibfvzluw4ahe2qxv3ddee --vault ggk4orq7rmcm7jinsb4ahygv7e --fields credential --reveal`

**Usage (write operations)**: `OP_SERVICE_ACCOUNT_TOKEN="$(op item get f7zsfibfvzluw4ahe2qxv3ddee --vault ggk4orq7rmcm7jinsb4ahygv7e --fields credential --reveal)" op item create ...`

## Vault Directory

| Vault Name            | Vault ID                     | Purpose                                              |
| --------------------- | ---------------------------- | ---------------------------------------------------- |
| **Claude Automation** | `ggk4orq7rmcm7jinsb4ahygv7e` | SA-accessible credentials for Claude Code automation |
| **Employee**          | _(user-session only)_        | Personal credentials; SA cannot access               |

## Credential Items (Claude Automation vault)

| Item                             | Item ID                      | Category       | Used By                                           |
| -------------------------------- | ---------------------------- | -------------- | ------------------------------------------------- |
| Cloudflare Global API Key        | `u34n7vav7t7mgbtn3ccsaw5mfi` | API credential | ccmax-monitor CF operations                       |
| Tailscale API Key (eon tailnet)  | `7qpluad2eax23oraimkop7j2jy` | API credential | Tailscale ACL/device automation                   |
| Pushover - cc-skills             | `dg5ng7vgj6dmmtc2vavo5kfko4` | API credential | Observability fleet (verbatim+UUID notifications) |
| FXView MT5 Demo Account (401678) | `ulpysnzzs4vwow3xbcpnsrkqrm` | Login          | Demo feed parity testing                          |
| SA Token: Claude Automation 3    | `f7zsfibfvzluw4ahe2qxv3ddee` | Token          | Write-enabled SA for vault operations             |

### Pushover credential fields (`dg5ng7vgj6dmmtc2vavo5kfko4`)

Multi-field item — retrieve specific fields:

```bash
# Application API token (used as `token=` in Pushover POST)
op read "op://Claude Automation/dg5ng7vgj6dmmtc2vavo5kfko4/credential"

# User key (recipient identifier, used as `user=`)
op read "op://Claude Automation/dg5ng7vgj6dmmtc2vavo5kfko4/user_key"

# POMail address (for email-routed notifications)
op read "op://Claude Automation/dg5ng7vgj6dmmtc2vavo5kfko4/pomail_address"
```

**API limits** ([pushover.net/api](https://pushover.net/api)): 1024 UTF-8 chars body, 250 title, 512 URL, 100 URL title. Free quota: 10,000 msgs/month per account (post-May-2026 per-account model).

**Proxy gotcha**: outbound `HTTPS_PROXY` (Claude Code OAuth proxy at `127.0.0.1:52205`) intercepts Pushover. Bypass with `curl --noproxy '*'` or `NO_PROXY=api.pushover.net` for sender scripts.

## Items in Other Vaults (user-session required)

| Item                     | Vault    | Item ID                      | Purpose                           |
| ------------------------ | -------- | ---------------------------- | --------------------------------- |
| FXView Live MT5 (515385) | Employee | `o4iyxw62fk2mg5uuvt7g3tepxq` | Live trading account (real money) |
| FXView VPS credentials   | Employee | `uss55ntw57ew5d2bh7u7zsi6tq` | Broker VPS (deferred)             |
| AWS Dev Eon              | Employee | `oqd3lqxcyakfxs7pqrwh2tqxia` | AWS el-dev account                |
