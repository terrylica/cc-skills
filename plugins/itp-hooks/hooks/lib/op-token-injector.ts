/**
 * 1Password Service Account Token Injector
 *
 * Automatically prepends OP_SERVICE_ACCOUNT_TOKEN to Bash commands targeting
 * the "Claude Automation" 1Password vault. This avoids biometric (Touch ID)
 * prompts when running `op` CLI commands.
 *
 * Only injects for commands matching known Claude Automation vault patterns.
 * Fail-open: if token file is missing or unreadable, returns command unchanged.
 *
 * Token: ~/.claude/.secrets/op-service-account-token (chmod 600)
 * Vault: Claude Automation (read + write via service account)
 *
 * Called from pretooluse-pueue-wrap-guard.ts (must be last PreToolUse hook
 * due to GitHub #15897 updatedInput aggregation bug).
 *
 * GitHub Issue: https://github.com/anthropics/claude-code/issues/15897
 */

/** Matches `op` CLI commands targeting the Claude Automation vault */
export const OP_CLAUDE_AUTOMATION_PATTERNS: RegExp[] = [
  // op item get/list/create ... --vault "Claude Automation"
  /\bop\s+(?:item|document|vault)\s+\S+.*--vault\s+["']?Claude Automation["']?/,
  // op read "op://Claude Automation/..."
  /\bop\s+read\s+["']op:\/\/Claude Automation\//,
  // op run --vault "Claude Automation" ...
  /\bop\s+run\s+.*--vault\s+["']?Claude Automation["']?/,
  // op inject with Claude Automation vault reference
  /\bop\s+inject\b.*Claude Automation/,
];

/** Detects if OP_SERVICE_ACCOUNT_TOKEN is already set in the command */
const ALREADY_HAS_OP_TOKEN = /\bOP_SERVICE_ACCOUNT_TOKEN\s*=/;

/** Token file path — service account with access to Claude Automation vault only */
export const OP_TOKEN_PATH = `${Bun.env.HOME || ""}/.claude/.secrets/op-service-account-token`;

/**
 * If the command targets the "Claude Automation" vault, prepend
 * OP_SERVICE_ACCOUNT_TOKEN=<token> to avoid biometric prompts.
 *
 * Returns the original command unchanged if:
 * - Command doesn't target Claude Automation vault
 * - Token file doesn't exist or is empty (fail-open)
 * - Token is already set in the command
 */
export async function maybeInjectOpToken(command: string): Promise<string> {
  // Skip if token already present
  if (ALREADY_HAS_OP_TOKEN.test(command)) {
    return command;
  }

  // Check if command targets Claude Automation vault
  const targetsClaudeAutomation = OP_CLAUDE_AUTOMATION_PATTERNS.some((p) =>
    p.test(command),
  );
  if (!targetsClaudeAutomation) {
    return command;
  }

  // Read token file (fail-open on any error)
  try {
    const tokenFile = Bun.file(OP_TOKEN_PATH);
    if (!(await tokenFile.exists())) {
      return command;
    }
    const token = (await tokenFile.text()).trim();
    if (!token) {
      return command;
    }

    // Prepend a command SUBSTITUTION — never the token itself.
    //
    // Claude Code records the rewritten command in the session transcript and in
    // background-task output files, so interpolating the literal here wrote the token
    // to disk in plaintext on EVERY `op` call against the Claude Automation vault.
    // Measured 2026-09-05: 91 files held this token verbatim — 58 under
    // ~/.claude/projects and 33 under /private/tmp/claude-501 — and this line is how
    // they got there. It was not a leak by an agent; it was a leak by design.
    //
    // The token is still READ above so the fail-open semantics are unchanged (missing
    // file, unreadable file and empty file all return the command untouched, exactly as
    // before). Only the VALUE is kept out of the command string; the path goes in
    // instead, and the shell resolves it at execution time.
    //
    // Do not "simplify" this back to `${token}`. The value is already in scope on the
    // line above, which is precisely what makes the regression easy and invisible.
    return `OP_SERVICE_ACCOUNT_TOKEN="$(cat '${OP_TOKEN_PATH}')" ${command}`;
  } catch {
    // Fail-open: any error reading token, allow original command
    return command;
  }
}
