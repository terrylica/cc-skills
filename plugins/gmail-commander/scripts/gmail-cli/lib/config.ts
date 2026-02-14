/**
 * Configuration constants and environment variable handling
 *
 * Uses mise environment variables for agnostic, multi-account Gmail access.
 * Shows self-guiding errors when configuration is missing.
 */

import { homedir } from "node:os";
import { join } from "node:path";

// Environment variable names
const ENV_GMAIL_OP_UUID = "GMAIL_OP_UUID";
const ENV_GMAIL_OP_VAULT = "GMAIL_OP_VAULT";

/**
 * Get 1Password UUID from environment
 * Exits with self-guiding error if not configured
 */
export function getOpUuid(): string {
  const uuid = process.env[ENV_GMAIL_OP_UUID];

  if (!uuid) {
    printSetupError();
    process.exit(1);
  }

  return uuid;
}

/**
 * Get 1Password vault from environment (default: Employee)
 */
export function getOpVault(): string {
  return process.env[ENV_GMAIL_OP_VAULT] ?? "Employee";
}

/**
 * Get token storage path for a given 1Password UUID
 * Tokens stored centrally at ~/.claude/tools/gmail-tokens/<uuid>.json
 */
export function getTokenPath(uuid?: string): string {
  const actualUuid = uuid ?? getOpUuid();
  const tokensDir = join(homedir(), ".claude", "tools", "gmail-tokens");
  return join(tokensDir, `${actualUuid}.json`);
}

/**
 * Get tokens directory path
 */
export function getTokensDir(): string {
  return join(homedir(), ".claude", "tools", "gmail-tokens");
}

// Gmail API scopes - readonly + compose for draft creation
export const SCOPES = [
  "https://www.googleapis.com/auth/gmail.readonly",
  "https://www.googleapis.com/auth/gmail.compose",
] as const;

// OAuth callback server configuration
export const AUTH_TIMEOUT_MS = 120_000;
export const EPHEMERAL_PORT_START = 49152;
export const EPHEMERAL_PORT_RANGE = 16383;

/**
 * Print self-guiding setup error
 */
function printSetupError(): void {
  const message = `
╔══════════════════════════════════════════════════════════════╗
║                  GMAIL TOOL - SETUP REQUIRED                 ║
╚══════════════════════════════════════════════════════════════╝

Missing: ${ENV_GMAIL_OP_UUID} environment variable

━━━ QUICK FIX ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Ask Claude Code: "Help me set up Gmail access"
  - OR -
Run: /gmail-commander:setup

━━━ MANUAL SETUP ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Find your 1Password UUID:
   op item list --vault Employee | grep -i gmail

2. Add to .mise.local.toml:
   [env]
   GMAIL_OP_UUID = "<your-uuid>"

3. Reload: cd . && mise trust

━━━ NEED OAUTH CREDENTIALS? ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

See: ~/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/
     skills/gmail-access/references/gmail-api-setup.md
`;
  console.error(message);
}
