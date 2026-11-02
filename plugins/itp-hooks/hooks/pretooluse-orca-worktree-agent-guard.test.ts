/**
 * Tests for pretooluse-orca-worktree-agent-guard. They spawn the real hook and speak its stdin/stdout protocol, so a
 * wrong tool_name gate, an escape hatch checked in the wrong order or a throw that fails open are caught too.
 * The first deny case is the command that left an idle shell in Orca's sidebar on 2026-11-01, verbatim apart from
 * the comment text. Mentions in echo, grep and commit messages must stay allowed: a guard that fires on prose is
 * disabled, and a disabled guard is worse than none.
 */

import { describe, expect, it } from "bun:test";
import { createsWithoutAgent } from "./pretooluse-orca-worktree-agent-guard.ts";

const HOOK_PATH = new URL("./pretooluse-orca-worktree-agent-guard.ts", import.meta.url).pathname;

async function runHook(command: string, toolName = "Bash"): Promise<{ decision: string; reason: string }> {
  const proc = Bun.spawn(["bun", HOOK_PATH], { stdin: "pipe", stdout: "pipe", stderr: "pipe" });
  proc.stdin.write(JSON.stringify({ tool_name: toolName, tool_input: { command } }));
  await proc.stdin.end();
  const stdout = await new Response(proc.stdout).text();
  await proc.exited;
  const out = stdout.trim() ? JSON.parse(stdout) : {};
  const h = out.hookSpecificOutput ?? {};
  return { decision: h.permissionDecision ?? "allow", reason: h.permissionDecisionReason ?? "" };
}

describe("orca worktree agent guard", () => {
  it("denies the 2026-11-01 command: a worktree created without an agent", async () => {
    const r = await runHook(
      'cd ~/eon/quant/shunshi-wang-888 && orca worktree create --repo path:/home/tca/eon/quant/shunshi-wang-888 --name s503 --base-branch main --setup run --comment "Section 503" --json',
    );
    expect(r.decision).toBe("deny");
    expect(r.reason).toContain(".claude/worktrees");
  });

  it("allows a create that launches its agent", async () => {
    expect((await runHook('orca worktree create --name s504 --agent claude --prompt "read HANDOFF.md" --json')).decision).toBe(
      "allow",
    );
    expect((await runHook("orca worktree create --name s504 --agent=claude --json")).decision).toBe("allow");
  });

  it("allows help, mentions and the escape hatch", async () => {
    for (const c of [
      "orca worktree create --help",
      'echo "orca worktree create --name x"',
      "rg -n 'orca worktree create' docs/",
      'git commit -m "docs: never orca worktree create without --agent"',
      "# orca worktree create --name x",
      "orca worktree create --name x --json  # ORCA-NO-AGENT-OK: an automation fills the terminal later",
      "orca worktree list --json",
    ]) {
      expect((await runHook(c)).decision).toBe("allow");
    }
  });

  it("allows any tool other than Bash", async () => {
    expect((await runHook("orca worktree create --name x", "Write")).decision).toBe("allow");
  });

  it("finds the one invocation without an agent among several", () => {
    const c = "orca worktree create --name a --agent claude && orca worktree create --name b; echo orca worktree create";
    expect(createsWithoutAgent(c)).toEqual(["orca worktree create --name b"]);
  });

  it("requires a reason of at least 10 characters for the escape hatch", async () => {
    expect((await runHook("orca worktree create --name x  # ORCA-NO-AGENT-OK: short")).decision).toBe("deny");
  });
});
