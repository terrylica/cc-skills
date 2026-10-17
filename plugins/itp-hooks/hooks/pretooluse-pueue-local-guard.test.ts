/**
 * Tests for pretooluse-pueue-local-guard.ts.
 *
 * Run with: bun test plugins/itp-hooks/hooks/pretooluse-pueue-local-guard.test.ts
 *
 * Two false positives from 2026-10-17 (a Linux host): a read-only `grep` whose PATTERN contained
 * `pueue add` and whose path was under `/home/` was denied, and every genuinely local `pueue add`
 * naming a file in the local `/home/<user>` was denied because the guard assumed a macOS host.
 * The true positive it exists for stays: a `pueue add` naming a home directory that does not
 * exist on this machine.
 */

import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import { localPueueAddArguments, remoteIndicatorsIn } from "./pretooluse-pueue-local-guard.ts";

const HOOK_PATH = join(import.meta.dir, "pretooluse-pueue-local-guard.ts");
const NOT_A_LOCAL_HOME = "/home/no-such-user-zz9";

async function decisionOf(command: string): Promise<string> {
  const proc = Bun.spawn(["bun", HOOK_PATH], { stdin: "pipe", stdout: "pipe", stderr: "pipe" });
  proc.stdin.write(JSON.stringify({ tool_name: "Bash", tool_input: { command } }));
  proc.stdin.end();
  const out = await new Response(proc.stdout).text();
  await proc.exited;
  return JSON.parse(out.trim()).hookSpecificOutput.permissionDecision;
}

describe("only real `pueue add` invocations are inspected", () => {
  test.each([
    [`grep -rln 'TASK_ID=\\$(pueue add' ~/.claude/plugins ${NOT_A_LOCAL_HOME}/x`],
    [`git commit -m "pueue add -- python ${NOT_A_LOCAL_HOME}/x.py"`],
    [`cat > /tmp/run.sh <<'EOF'\npueue add -- python ${NOT_A_LOCAL_HOME}/x.py\nEOF`],
    [`echo pueue add ${NOT_A_LOCAL_HOME}  # a mention, not a submission`],
    [`ssh host 'pueue add -- python ${NOT_A_LOCAL_HOME}/x.py'`],
  ])("no invocation: %s", (command) => {
    expect(remoteIndicatorsIn(command)).toEqual([]);
  });

  test("a real invocation is found, including after cd and inside bash -c", () => {
    expect(localPueueAddArguments("cd /tmp && pueue add -g g -- python x.py")).toHaveLength(1);
    expect(localPueueAddArguments("bash -c 'pueue add -- python x.py'")).toHaveLength(1);
  });
});

describe("remote-context indicators respect THIS machine", () => {
  test("TRUE POSITIVE: a /home/<user> that does not exist here is remote", async () => {
    expect(remoteIndicatorsIn(`pueue add -- python ${NOT_A_LOCAL_HOME}/sweep.py`)).toContain(
      "/home/ path not on this machine",
    );
    expect(await decisionOf(`pueue add -w ${NOT_A_LOCAL_HOME}/proj -- python sweep.py`)).toBe("deny");
  });

  test("TRUE POSITIVE: remote temp scripts are remote", () => {
    expect(remoteIndicatorsIn("pueue add -- bash /tmp/gen3_run.sh")).toContain("/tmp/gen*");
  });

  const localHome = homedir();
  test.if(localHome.startsWith("/home/") && existsSync(localHome))(
    "a local /home/<user> path (Linux host) is local",
    async () => {
      const command = `pueue add -g analysis -w "${localHome}/eon" -- python ${localHome}/eon/x.py`;
      expect(remoteIndicatorsIn(command)).toEqual([]);
      expect(await decisionOf(command)).toBe("allow");
    },
  );

  test.if(existsSync(join(localHome, ".local", "bin")))("~/.local/bin/ is local when this machine has it", () => {
    expect(remoteIndicatorsIn("pueue add -- ~/.local/bin/tool --run")).toEqual([]);
  });

  test("the PUEUE-LOCAL-OK escape hatch still allows", async () => {
    expect(await decisionOf(`pueue add -- python ${NOT_A_LOCAL_HOME}/x.py # PUEUE-LOCAL-OK`)).toBe("allow");
  });
});
