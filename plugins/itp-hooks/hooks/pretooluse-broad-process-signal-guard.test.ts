/**
 * Tests for pretooluse-broad-process-signal-guard (kill guard v2).
 *
 * These SPAWN THE REAL HOOK and speak the real stdin/stdout protocol, so wiring mistakes (wrong
 * tool gate, escape checked in the wrong order, a throw that fails open) show up here. The allow
 * cases matter as much as the deny cases: kill/pkill appear constantly in commit messages, docs and
 * heredocs about the 2026-09-27 incident, and `kill -1 <pid>` (SIGHUP) and `kill -0 <pid>` (probe)
 * are everyday forms. A guard that fires on those gets disabled, and a disabled guard is worse
 * than none.
 */

import { describe, expect, it } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const HOOK_PATH = new URL("./pretooluse-broad-process-signal-guard.ts", import.meta.url).pathname;

async function runHook(
  toolName: string,
  toolInput: Record<string, unknown>,
): Promise<{ decision: string; reason: string }> {
  const proc = Bun.spawn(["bun", HOOK_PATH], { stdin: "pipe", stdout: "pipe", stderr: "pipe" });
  proc.stdin.write(JSON.stringify({ tool_name: toolName, tool_input: toolInput }));
  await proc.stdin.end();
  const [stdout] = await Promise.all([new Response(proc.stdout).text(), proc.exited]);
  const parsed = JSON.parse(stdout);
  return {
    decision: parsed.hookSpecificOutput.permissionDecision,
    reason: parsed.hookSpecificOutput.permissionDecisionReason ?? "",
  };
}

const bash = (command: string) => runHook("Bash", { command });

describe("Bash: denies signals that are broad by construction", () => {
  const cases: [string, string][] = [
    ["kill -9 -1", "every process"],
    ["kill -- -1", "every process"],
    ["kill -1 -1", "every process"],
    ["kill -TERM 0", "process group"],
    ["pkill node", "shared by many"],
    ["pkill -f claude", "shared by many"],
    ["pkill -9 -f /usr/local/bin/python3.14", "shared by many"],
    ['sudo killall -9 "Google Chrome"', "shared by many"],
    ["killall bun", "shared by many"],
    ["killall -u <user>", "every process of that user"],
    ["pkill -u <user>", "every process of that user"],
    ["pkill -f vite", "literal characters"],
    ["pkill -f '.*'", "literal characters"],
    ["kill $(pgrep -f python3)", "shared by many"],
    ["kill -9 `pgrep node`", "shared by many"],
    ["ssh gpu-host 'pkill -f node'", "ssh remote command"],
    ["bash -c 'kill -9 -1'", "shell -c script"],
    ["cd /tmp && killall -m '^Code'", "literal characters"],
  ];
  for (const [command, expected] of cases) {
    it(`denies: ${command}`, async () => {
      const r = await bash(command);
      expect(r.decision).toBe("deny");
      expect(r.reason).toContain(expected);
      expect(r.reason).toContain('kill "$pid"');
    });
  }
});

describe("Bash: allows targeted signals and mere mentions", () => {
  const cases = [
    "kill 1234",
    "kill -1 1234",
    'kill -0 "$pid" && echo alive',
    'kill -9 "$pid"',
    "bun server.ts & pid=$!; sleep 1; kill $pid",
    "kill -l",
    "pkill -f 'bun server.ts --port 5198'",
    'pkill -f "$PATTERN"',
    "pgrep node",
    "pgrep -fl claude | head -n 5",
    "killall Dock",
    "killall -KILL SystemUIServer",
    'git commit -m "never run pkill node or kill -9 -1"',
    "echo 'kill -9 -1'",
    "cat <<'EOF'\npkill node\nkill -9 -1\nEOF",
    "# pkill node\ntrue",
    "pkill node # BROAD-PROCESS-SIGNAL-OK: dedicated throwaway VM, nothing else runs",
  ];
  for (const command of cases) {
    it(`allows: ${JSON.stringify(command)}`, async () => {
      expect((await bash(command)).decision).toBe("allow");
    });
  }
});

describe("Write / Edit of shell scripts", () => {
  it("denies the v1 incident line written into a .sh file (v1's documented gap)", async () => {
    const r = await runHook("Write", {
      file_path: "/tmp/cleanup.sh",
      content: "#!/bin/bash\nset -euo pipefail\npkill -f 'bun server.ts --build build-preview' -n\n",
    });
    expect(r.decision).toBe("deny");
    expect(r.reason).toContain("pkill -f -n 'bun server.ts --build build-preview'");
  });

  it("denies a broad killall in a script identified only by its shebang", async () => {
    const r = await runHook("Write", {
      file_path: "/tmp/bin/stop-everything",
      content: "#!/usr/bin/env bash\nkillall node\n",
    });
    expect(r.decision).toBe("deny");
    expect(r.reason).toContain("in the script /tmp/bin/stop-everything");
  });

  it("uses the on-disk shebang for an Edit of an extensionless script", async () => {
    const dir = mkdtempSync(join(tmpdir(), "broad-signal-"));
    const path = join(dir, "runner");
    writeFileSync(path, "#!/bin/zsh\necho hi\n");
    try {
      const r = await runHook("Edit", { file_path: path, old_string: "echo hi", new_string: "kill -9 -1" });
      expect(r.decision).toBe("deny");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("allows a targeted kill in a script", async () => {
    const r = await runHook("Edit", { file_path: "/tmp/x.sh", old_string: "a", new_string: 'kill "$pid"' });
    expect(r.decision).toBe("allow");
  });

  it("ignores non-shell files that mention broad kills", async () => {
    for (const [file_path, content] of [
      ["/tmp/notes.md", "Never run `pkill node` or `kill -9 -1`."],
      ["/tmp/tool.py", "import subprocess\n# pkill node\n"],
      ["/tmp/guard.ts", 'const bad = "killall bun";\n'],
    ]) {
      expect((await runHook("Write", { file_path, content })).decision).toBe("allow");
    }
  });

  it("honours each escape for the check it names", async () => {
    const r = await runHook("Write", {
      file_path: "/tmp/ci.sh",
      content: "#!/bin/sh\n# BROAD-PROCESS-SIGNAL-OK: disposable CI container, nothing else runs\npkill node\n",
    });
    expect(r.decision).toBe("allow");
  });
});

describe("other tools", () => {
  it("allows Read without inspecting it", async () => {
    expect((await runHook("Read", { file_path: "/tmp/x.sh" })).decision).toBe("allow");
  });
});
