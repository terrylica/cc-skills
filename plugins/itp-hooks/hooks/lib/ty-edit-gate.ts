/**
 * Per-session "a .py file was edited" gate shared by the two ty hooks.
 *
 * `posttooluse-ty-type-check.ts` touches `<dir>/<session_id>.edited` after an eligible
 * Python edit; `stop-ty-project-check.ts` runs the project-wide check only when ITS OWN
 * session's gate exists, and then removes only that file. The directory is shared by
 * every Claude Code session on the machine, so neither hook may ever read or delete
 * another session's gate: the previous Stop hook ran when ANY gate existed and then
 * `rm -rf`'d the whole directory, so one session's exit both ran a check for edits it
 * never made and erased every other session's pending check.
 *
 * `session_id` is a common input field on every hook event, Stop included
 * (https://code.claude.com/docs/en/hooks, "Common input fields").
 */

import { join } from "node:path";

/** Default location. `CLAUDE_TY_EDIT_GATE_DIR` overrides it so tests never touch the live directory. */
export const DEFAULT_TY_EDIT_GATE_DIRECTORY = "/tmp/.claude-ty-edits";

export function resolveTyEditGateDirectory(): string {
  return process.env.CLAUDE_TY_EDIT_GATE_DIR || DEFAULT_TY_EDIT_GATE_DIRECTORY;
}

/**
 * A session id is used as a file name, so accept only a plain token. Anything else
 * (empty, a path separator, `.`/`..`) yields null: there is no gate for it.
 */
const SAFE_SESSION_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;

export function resolveTySessionId(payloadSessionId: unknown): string | null {
  const candidate =
    typeof payloadSessionId === "string" && payloadSessionId !== ""
      ? payloadSessionId
      : process.env.CLAUDE_SESSION_ID ?? "";
  return SAFE_SESSION_ID_PATTERN.test(candidate) ? candidate : null;
}

/** Path of the given session's gate file, or null when the session id is missing or unsafe. */
export function tyEditGateFilePathForSession(
  payloadSessionId: unknown,
  gateDirectory: string = resolveTyEditGateDirectory(),
): string | null {
  const sessionId = resolveTySessionId(payloadSessionId);
  return sessionId === null ? null : join(gateDirectory, `${sessionId}.edited`);
}
