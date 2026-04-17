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

| Item                             | Item ID                      | Category       | Used By                               |
| -------------------------------- | ---------------------------- | -------------- | ------------------------------------- |
| Cloudflare Global API Key        | `u34n7vav7t7mgbtn3ccsaw5mfi` | API credential | ccmax-monitor CF operations           |
| Tailscale API Key (eon tailnet)  | `7qpluad2eax23oraimkop7j2jy` | API credential | Tailscale ACL/device automation       |
| FXView MT5 Demo Account (401678) | `ulpysnzzs4vwow3xbcpnsrkqrm` | Login          | Demo feed parity testing              |
| SA Token: Claude Automation 3    | `f7zsfibfvzluw4ahe2qxv3ddee` | Token          | Write-enabled SA for vault operations |

## Items in Other Vaults (user-session required)

| Item                     | Vault    | Item ID                      | Purpose                           |
| ------------------------ | -------- | ---------------------------- | --------------------------------- |
| FXView Live MT5 (515385) | Employee | `o4iyxw62fk2mg5uuvt7g3tepxq` | Live trading account (real money) |
| FXView VPS credentials   | Employee | `uss55ntw57ew5d2bh7u7zsi6tq` | Broker VPS (deferred)             |
| AWS Dev Eon              | Employee | `oqd3lqxcyakfxs7pqrwh2tqxia` | AWS el-dev account                |
