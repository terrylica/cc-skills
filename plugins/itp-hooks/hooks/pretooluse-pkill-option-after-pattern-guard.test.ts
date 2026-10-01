/**
 * Tests for pretooluse-pkill-option-after-pattern-guard.
 *
 * These SPAWN THE REAL HOOK and speak the real stdin/stdout protocol, so they catch wiring mistakes
 * (wrong tool_name gate, escape hatch checked in the wrong order, a throw that fails open) that a
 * test re-running the detector alone cannot. Precedent: pretooluse-chrome-debug-port-guard.test.ts.
 *
 * The first deny-case is the 2026-09-27 incident command VERBATIM. The allow-cases matter as much:
 * `pkill`/`pgrep` appear constantly in commit messages, docs and heredocs about this very incident,
 * and `-n` is everywhere (`head -n`, `echo -n`), so a guard that fires on mentions or on a sibling
 * command gets disabled — and a disabled guard is worse than none.
 */

import { describe, expect, it } from "bun:test";

const HOOK_PATH = new URL(
  "./pretooluse-pkill-option-after-pattern-guard.ts",
  import.meta.url,
).pathname;

async function runHook(
  command: string,
  toolName = "Bash",
): Promise<{ decision: string; reason: string; exitCode: number }> {
  const proc = Bun.spawn(["bun", HOOK_PATH], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });
  proc.stdin.write(
    JSON.stringify({ tool_name: toolName, tool_input: { command } }),
  );
  await proc.stdin.end();

  const [stdout, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    proc.exited,
  ]);

  const parsed = JSON.parse(stdout);
  return {
    decision: parsed.hookSpecificOutput.permissionDecision,
    reason: parsed.hookSpecificOutput.permissionDecisionReason ?? "",
    exitCode,
  };
}

const INCIDENT_COMMAND =
  "cd apps/workspace && (PORT=5198 bun server.ts --build build-preview >/tmp/cpc-redact/s5198.log 2>&1 &) ; " +
  "sleep 2; curl -s localhost:5198/health | head -c 120; echo; cd ../.. && timeout --foreground 300 " +
  "bun docs/design/tools/scenario-queue.ts --base http://127.0.0.1:5198 2>&1 | grep -v '^PASS' | " +
  "grep -v '^\\s*at ' | tail -8; pkill -f 'bun server.ts --build build-preview' -n 2>/dev/null; true";

describe("denies an option after the pattern", () => {
  it("denies the 2026-09-27 incident command verbatim, and suggests the fixed order", async () => {
    const r = await runHook(INCIDENT_COMMAND);
    expect(r.decision).toBe("deny");
    expect(r.reason).toContain("pkill -f 'bun server.ts --build build-preview' -n");
    expect(r.reason).toContain("pkill -f -n 'bun server.ts --build build-preview'");
  });

  it("denies an option that takes a value, and moves the value with it", async () => {
    const r = await runHook('pkill -f "bun server.ts" -P $$ 2>/dev/null');
    expect(r.decision).toBe("deny");
    expect(r.reason).toContain('pkill -f -P $$ "bun server.ts"');
  });

  it("denies pgrep inside a command substitution that feeds kill", async () => {
    const r = await runHook("kill $(pgrep -f foo -n)");
    expect(r.decision).toBe("deny");
    expect(r.reason).toContain("pgrep -f -n foo");
  });

  it("denies inside a substitution nested in double quotes", async () => {
    const r = await runHook('echo "$(pgrep -f "foo bar" -n)"');
    expect(r.decision).toBe("deny");
  });

  it("denies a trailing signal and moves it to argv[1], the only place BSD pkill reads one", async () => {
    const r = await runHook("pkill -f foo -9");
    expect(r.decision).toBe("deny");
    expect(r.reason).toContain("pkill -9 -f foo");
  });

  it("denies inside bash -c, including the /usr/bin/env form CLAUDE.md recommends", async () => {
    const r = await runHook("/usr/bin/env bash -c 'pkill -f foo -n'");
    expect(r.decision).toBe("deny");
    expect(r.reason).toContain("shell -c script");
  });

  it("denies inside an ssh remote command (the Mac Mini is macOS too)", async () => {
    const r = await runHook("ssh -p 22 mini 'pkill -f foo -n'");
    expect(r.decision).toBe("deny");
  });

  it("denies inside a heredoc fed to a shell", async () => {
    const r = await runHook("bash <<'EOF'\npkill -f foo -n\nEOF");
    expect(r.decision).toBe("deny");
  });

  it("denies behind sudo, timeout and xargs wrappers", async () => {
    for (const cmd of [
      "sudo pkill -f foo -n",
      "timeout --foreground 5 pkill -f foo -n",
      "echo foo | xargs -n 1 pkill -f bar -n",
    ]) {
      const r = await runHook(cmd);
      expect(r.decision).toBe("deny");
    }
  });

  it("denies a trailing -- too: after a pattern it is itself a pattern matching every --flag", async () => {
    const r = await runHook("pkill -f foo --");
    expect(r.decision).toBe("deny");
  });
});

describe("allows correct and unrelated commands", () => {
  it("allows the corrected incident command", async () => {
    const r = await runHook(
      "pkill -n -f 'bun server.ts --build build-preview' 2>/dev/null; true",
    );
    expect(r.decision).toBe("allow");
  });

  it("allows a pattern that begins with '-' when written after --", async () => {
    const r = await runHook("pkill -f -- '-n'");
    expect(r.decision).toBe("allow");
  });

  it("allows -n that belongs to a different command in the pipeline", async () => {
    for (const cmd of [
      "pgrep -f foo | head -n 1",
      "pkill -f foo && echo -n done",
      "pgrep -lf foo; sort -n /tmp/x",
    ]) {
      const r = await runHook(cmd);
      expect(r.decision).toBe("allow");
    }
  });

  it("allows leading signals and options that take values", async () => {
    for (const cmd of [
      "pkill -TERM -f foo",
      "pkill -9 -f foo",
      "pkill -KILL -x foo",
      "pgrep -P 123 -l",
      "pkill -u terryli -f foo",
    ]) {
      const r = await runHook(cmd);
      expect(r.decision).toBe("allow");
    }
  });

  it("allows redirections after the pattern: they are not arguments", async () => {
    const r = await runHook("pgrep -fl foo 2>&1 >/dev/null");
    expect(r.decision).toBe("allow");
  });

  it("allows text that only MENTIONS the bad command", async () => {
    for (const cmd of [
      'git commit -m "fix: pkill -f foo -n killed every process with -n in argv"',
      "grep -n 'pkill -f foo -n' notes.md",
      "cat <<'EOF' > incident.md\npkill -f 'bun server.ts' -n\nEOF",
      "python3 - <<'PY'\n# pkill -f foo -n\nprint(1)\nPY",
      "echo 'pkill -f foo -n'  # pkill -f foo -n",
    ]) {
      const r = await runHook(cmd);
      expect(r.decision).toBe("allow");
    }
  });

  it("allows the escape hatch with a reason, and refuses it without one", async () => {
    const withReason = await runHook(
      "pkill -f foo -n  # PKILL-OPTION-ORDER-OK: fixture for this guard's own manual test",
    );
    expect(withReason.decision).toBe("allow");

    const bare = await runHook("pkill -f foo -n  # PKILL-OPTION-ORDER-OK");
    expect(bare.decision).toBe("deny");
  });

  it("ignores non-Bash tools", async () => {
    const r = await runHook("pkill -f foo -n", "Write");
    expect(r.decision).toBe("allow");
  });
});
