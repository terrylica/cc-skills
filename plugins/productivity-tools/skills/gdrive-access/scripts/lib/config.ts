/**
 * Configuration constants and environment variable handling
 *
 * Uses mise environment variables for agnostic, multi-account Google Drive access.
 * Shows self-guiding errors when configuration is missing.
 */

import { homedir } from "node:os";
import { join } from "node:path";

// Environment variable names
const ENV_GDRIVE_OP_UUID = "GDRIVE_OP_UUID";
const ENV_GDRIVE_OP_VAULT = "GDRIVE_OP_VAULT";

/**
 * Get 1Password UUID from environment
 * Exits with self-guiding error if not configured
 */
export function getOpUuid(): string {
  const uuid = process.env[ENV_GDRIVE_OP_UUID];

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
  return process.env[ENV_GDRIVE_OP_VAULT] ?? "Employee";
}

/**
 * Get token storage path for a given 1Password UUID
 * Tokens stored centrally at ~/.claude/tools/gdrive-tokens/<uuid>.json
 */
export function getTokenPath(uuid?: string): string {
  const actualUuid = uuid ?? getOpUuid();
  const tokensDir = join(homedir(), ".claude", "tools", "gdrive-tokens");
  return join(tokensDir, `${actualUuid}.json`);
}

/**
 * Get tokens directory path
 */
export function getTokensDir(): string {
  return join(homedir(), ".claude", "tools", "gdrive-tokens");
}

// Google Drive API scopes - readonly for file access
export const SCOPES = [
  "https://www.googleapis.com/auth/drive.readonly",
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
║                 GDRIVE TOOL - SETUP REQUIRED                 ║
╚══════════════════════════════════════════════════════════════╝

Missing: ${ENV_GDRIVE_OP_UUID} environment variable

━━━ QUICK FIX ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Ask Claude Code: "Help me set up Google Drive access"
  - OR -
Run: /gdrive-tools:setup

━━━ MANUAL SETUP ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Find your 1Password UUID:
   op item list --vault Employee | grep -i drive

2. Add to .mise.local.toml:
   [env]
   GDRIVE_OP_UUID = "<your-uuid>"

3. Reload: cd . && mise trust

━━━ NEED OAUTH CREDENTIALS? ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

See: ~/.claude/plugins/marketplaces/cc-skills/plugins/gdrive-tools/
     skills/gdrive-access/references/gdrive-api-setup.md
`;
  console.error(message);
}
