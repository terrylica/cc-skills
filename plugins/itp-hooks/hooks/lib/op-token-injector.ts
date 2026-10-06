/**
 * 1Password Service Account Token Injector
 *
 * Automatically prepends OP_SERVICE_ACCOUNT_TOKEN to Bash commands targeting
 * the "Claude Automation" 1Password vault. This avoids biometric (Touch ID)
 * prompts when running `op` CLI commands.
 *
 * Only injects for commands matching known Claude Automation vault patterns.
 * Fail-open: if no token source is configured, returns the command unchanged and
 * `op` falls back to the 1Password app as it would without this hook.
 *
 * Token source — the user's choice, read from the hook's environment, in this order
 * (and NO default path; until 2026-10 a hard-coded plaintext file under ~/.claude
 * was read whether or not the user had asked for it):
 *   1. OP_SERVICE_ACCOUNT_TOKEN already in the environment → nothing to inject; the
 *      Bash tool inherits it.
 *   2. OP_SA_TOKEN_CMD — a command whose stdout is the token, e.g.
 *      `vault get op-service-account token`. Split on whitespace and emitted as
 *      single-quoted words inside `$(…)`, so the shell runs it as a plain argv with no
 *      expansion.
 *   3. OP_SA_TOKEN_FILE — a token file the user names (chmod 600).
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

/** Quote one word for POSIX sh: everything literal inside single quotes. */
export function shSingleQuote(word: string): string {
  return `'${word.replaceAll("'", `'\\''`)}'`;
}

type Env = Record<string, string | undefined>;

/**
 * Shell text that, evaluated at execution time, yields the token — or null when the
 * user configured no source (or a named file is missing/empty). Never the token value.
 */
export async function opTokenSubstitution(env: Env = Bun.env): Promise<string | null> {
  const cmd = env.OP_SA_TOKEN_CMD?.trim();
  if (cmd) {
    return `$(${cmd.split(/\s+/).map(shSingleQuote).join(" ")})`;
  }
  const file = env.OP_SA_TOKEN_FILE?.trim();
  if (file) {
    const tokenFile = Bun.file(file);
    if (!(await tokenFile.exists())) {
      return null;
    }
    // Read only to keep the old fail-open check (missing/empty → leave command alone).
    if (!(await tokenFile.text()).trim()) {
      return null;
    }
    return `$(cat ${shSingleQuote(file)})`;
  }
  return null;
}

/**
 * If the command targets the "Claude Automation" vault, prepend
 * OP_SERVICE_ACCOUNT_TOKEN="$(…)" to avoid biometric prompts.
 *
 * Returns the original command unchanged if:
 * - Command doesn't target Claude Automation vault
 * - Token is already set in the command, or already in the environment
 * - No token source is configured, or the named file is missing/empty (fail-open)
 */
export async function maybeInjectOpToken(command: string, env: Env = Bun.env): Promise<string> {
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

  // Already exported: the Bash tool inherits it, so there is nothing to add.
  if (env.OP_SERVICE_ACCOUNT_TOKEN?.trim()) {
    return command;
  }

  try {
    const substitution = await opTokenSubstitution(env);
    if (!substitution) {
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
    // Only the command (or file path) that PRODUCES the token goes into the command
    // string; the shell resolves it at execution time. Do not "simplify" this into
    // resolving the token here and interpolating it.
    return `OP_SERVICE_ACCOUNT_TOKEN="${substitution}" ${command}`;
  } catch {
    // Fail-open: any error reading the configuration, allow original command
    return command;
  }
}
