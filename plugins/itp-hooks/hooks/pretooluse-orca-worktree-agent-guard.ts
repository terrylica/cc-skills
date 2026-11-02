#!/usr/bin/env bun
/**
 * PreToolUse hook: Orca worktree agent guard.
 *
 * Rule (operator, 2026-11-01, every device): a worktree gets an Orca sidebar entry only when it gets a session.
 * Denies `orca worktree create` without `--agent`: such a worktree appears in Orca's sidebar with an idle shell and
 * no session. For a session's own isolated work, use a Claude Code worktree under `<repo>/.claude/worktrees/<name>`
 * (the EnterWorktree tool, `git worktree add` there, or a subagent's `isolation: worktree`); Orca lists those as
 * non-Orca worktrees, hidden by default. Create an Orca worktree only together with its agent
 * (`orca worktree create --agent claude --prompt …`, the orca-tools worktree-spinoff skill).
 *
 * Allowed: `--agent` present (also `--agent=<id>`), `--help`, mentions in echo/printf/grep/comments/commit and
 * PR text, and the escape hatch `ORCA-NO-AGENT-OK: <reason of at least 10 characters>`.
 *
 * Fail-open: any parse or logic error allows the command.
 * Spoke: plugins/itp-hooks/docs/orca-worktree-agent-guard.md
 */

import {
  type EscapeHatchMarkerDetectionConfiguration,
  hasFileWideEscapeHatchMarkerInContent,
} from "./lib/escape-hatch-marker-detection-iter107.ts";
import { allow, deny, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";

const HOOK_NAME = "pretooluse-orca-worktree-agent-guard";

const ORCA_NO_AGENT_ESCAPE_HATCH: Pick<
  EscapeHatchMarkerDetectionConfiguration,
  "markerNameTokenIncludingSuffix" | "requireMinimumReasonCharacterCountAfterColonOrZeroForOptional"
> = {
  markerNameTokenIncludingSuffix: "ORCA-NO-AGENT-OK",
  requireMinimumReasonCharacterCountAfterColonOrZeroForOptional: 10,
};

/** One shell command per segment: split on newlines and the control operators ; && || | &. */
function segments(command: string): string[] {
  return command.split(/\n|;|&&|\|\||\||&/).map((s) => s.trim()).filter(Boolean);
}

/** A segment that only mentions the command (documentation, search, commit or PR text) is not an invocation. */
function isMention(segment: string): boolean {
  return (
    /^#/.test(segment) ||
    /^(echo|printf|grep|egrep|fgrep|rg|ag|ack|cat|less|head|tail|sed|awk)\b/.test(segment) ||
    /\bgit\s+(commit|tag)\b/.test(segment) ||
    /\bgh\s+(issue|pr|release)\s+(create|edit|comment)\b/.test(segment)
  );
}

/** The `orca worktree create` invocations that carry no `--agent`. */
export function createsWithoutAgent(command: string): string[] {
  const out: string[] = [];
  for (const seg of segments(command)) {
    if (!/(^|[\s/])orca\s+worktree\s+create\b/.test(seg) || isMention(seg)) continue;
    if (/(^|\s)--help\b/.test(seg)) continue;
    if (/(^|\s)--agent(=|\s+)\S/.test(seg)) continue;
    out.push(seg);
  }
  return out;
}

export function explain(found: readonly string[]): string {
  return [
    "[ORCA WORKTREE AGENT GUARD] Blocked: `orca worktree create` without `--agent`.",
    ...found.map((s) => `  ${s}`),
    "Rule (operator, 2026-11-01): a worktree gets an Orca sidebar entry only when it gets a session; " +
      "a worktree created without an agent sits in Orca's sidebar with an idle shell.",
    "Instead:\n" +
      "  - this session's own isolated work: a Claude Code worktree under <repo>/.claude/worktrees/<name> " +
      "(the EnterWorktree tool, or `git worktree add .claude/worktrees/<name> -b <branch> origin/main`), " +
      "hidden in Orca by default;\n" +
      "  - a parallel sub-task: a subagent with isolation: worktree;\n" +
      "  - a separate session to watch: `orca worktree create --agent claude --prompt \"<handoff>\" …` " +
      "(the orca-tools worktree-spinoff skill).",
    "Spoke: plugins/itp-hooks/docs/orca-worktree-agent-guard.md\n" +
      "Override with ORCA-NO-AGENT-OK: <reason of at least 10 characters>",
  ].join("\n\n");
}

export async function main(): Promise<void> {
  const input = await parseStdinOrAllow("ORCA-WORKTREE-AGENT-GUARD");
  if (!input) return;
  const { tool_name, tool_input = {} } = input;
  if (tool_name !== "Bash") {
    allow();
    return;
  }
  const command = tool_input.command || "";
  if (!command.includes("orca") || hasFileWideEscapeHatchMarkerInContent(command, ORCA_NO_AGENT_ESCAPE_HATCH)) {
    allow();
    return;
  }
  const found = createsWithoutAgent(command);
  if (found.length === 0) {
    allow();
    return;
  }
  deny(explain(found));
}

if (import.meta.main) {
  main().catch((err) => {
    trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err));
    allow();
  });
}
