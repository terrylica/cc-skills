/**
 * Decision emission of the PreToolUse Write/Edit orchestrator.
 *
 * Regression for the exit-2-on-ask bug: the orchestrator set exit code 2 for ask as well as deny,
 * and per code.claude.com/docs/en/hooks "exit 2 blocks whether or not you print JSON", so an ask
 * hard-blocked instead of prompting. Both decisions now go out as one PreToolUse JSON line on
 * stdout with exit 0.
 *
 * No registered subhook returns ask today (vale-claude-md-guard can, but its enforcement mode is
 * "deny"), so the ask cases inject a fake registry through the exported `main(registry)`, run in
 * a real bun subprocess so the exit code and stdout are exactly what Claude Code would see.
 */
import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import type { PreToolUseSubhookRegistryEntry } from "./lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts";
import {
  buildPermissionDecisionResponse,
  runEditTimeSubhookRegistry,
} from "./pretooluse-write-edit-orchestrator.ts";
import type { PreToolUseInput } from "./pretooluse-helpers.ts";

const HOOKS_DIR = new URL(".", import.meta.url).pathname;
const ORCHESTRATOR = join(
  HOOKS_DIR,
  "pretooluse-write-edit-orchestrator.ts",
);

const WRITE_PAYLOAD = JSON.stringify({
  tool_name: "Write",
  tool_input: { file_path: "/tmp/orchestrator-decisions-test/notes.txt", content: "hello\n" },
});

interface HookRun {
  exitCode: number;
  stdout: string;
  stderr: string;
}

async function runProcess(cmd: string[], stdin: string): Promise<HookRun> {
  const proc = Bun.spawn(cmd, { stdin: new Blob([stdin]), stdout: "pipe", stderr: "pipe" });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  return { exitCode, stdout, stderr };
}

/**
 * Run the orchestrator's real `main()` in its own bun process with a registry of fake subhooks,
 * each returning the given decision kind.
 */
function runWithFakeRegistry(kinds: Array<"allow" | "deny" | "ask">, stdin = WRITE_PAYLOAD): Promise<HookRun> {
  const registrySource = kinds
    .map(
      (kind, i) =>
        `{ name: "fake-${kind}-${i}", timeoutMs: 2000, description: "test", classify: async () => ({ kind: "${kind}", reason: "fake ${kind} reason ${i}" }) }`,
    )
    .join(",\n");
  const script = `import { main } from ${JSON.stringify(ORCHESTRATOR)};\nawait main([${registrySource}]);\n`;
  return runProcess([process.execPath, "-e", script], stdin);
}

function parseSingleDecision(stdout: string): Record<string, unknown> {
  const lines = stdout.trim().split("\n");
  expect(lines).toHaveLength(1);
  const parsed = JSON.parse(lines[0]) as { hookSpecificOutput: Record<string, unknown> };
  return parsed.hookSpecificOutput;
}

describe("Write/Edit orchestrator decision emission (subprocess)", () => {
  test("ask from a subhook exits 0 with permissionDecision ask on stdout", async () => {
    const run = await runWithFakeRegistry(["allow", "ask", "allow"]);
    expect(run.exitCode).toBe(0);
    const hso = parseSingleDecision(run.stdout);
    expect(hso.hookEventName).toBe("PreToolUse");
    expect(hso.permissionDecision).toBe("ask");
    expect(String(hso.permissionDecisionReason)).toContain("fake-ask-1 → ASK");
    expect(String(hso.permissionDecisionReason)).toContain("fake ask reason 1");
  });

  test("deny from a subhook still denies, as JSON with exit 0", async () => {
    const run = await runWithFakeRegistry(["allow", "deny"]);
    expect(run.exitCode).toBe(0);
    const hso = parseSingleDecision(run.stdout);
    expect(hso.permissionDecision).toBe("deny");
    expect(String(hso.permissionDecisionReason)).toContain("fake deny reason 1");
  });

  test("a deny after an ask wins (deny > ask)", async () => {
    const run = await runWithFakeRegistry(["ask", "deny"]);
    expect(run.exitCode).toBe(0);
    const hso = parseSingleDecision(run.stdout);
    expect(hso.permissionDecision).toBe("deny");
    expect(String(hso.permissionDecisionReason)).toContain("fake-deny-1");
  });

  test("all-allow registry emits allow with exit 0", async () => {
    const run = await runWithFakeRegistry(["allow", "allow"]);
    expect(run.exitCode).toBe(0);
    expect(parseSingleDecision(run.stdout).permissionDecision).toBe("allow");
  });

  test("the real orchestrator file denies a real violation with exit 0, never exit 2", async () => {
    // version-guard: a hardcoded version in a non-exempt markdown file.
    const payload = JSON.stringify({
      tool_name: "Write",
      tool_input: { file_path: "/home/foo/README.md", content: "# Title\n\nVersion: 9.9.9\n" },
    });
    const run = await runProcess([process.execPath, ORCHESTRATOR], payload);
    expect(run.exitCode).toBe(0);
    const hso = parseSingleDecision(run.stdout);
    expect(hso.permissionDecision).toBe("deny");
    expect(String(hso.permissionDecisionReason)).toContain("version-guard → DENY");
  });
});

function entry(name: string, kind: "allow" | "deny" | "ask"): PreToolUseSubhookRegistryEntry {
  return {
    name,
    timeoutMs: 2000,
    description: "test",
    classify: async () => ({ kind, reason: `${name} reason` }),
  };
}

describe("runEditTimeSubhookRegistry precedence (in-process)", () => {
  const input = JSON.parse(WRITE_PAYLOAD) as PreToolUseInput;

  test("the first ask is held, a later ask does not replace it", async () => {
    const verdict = await runEditTimeSubhookRegistry(input, [entry("a1", "ask"), entry("a2", "ask"), entry("ok", "allow")]);
    expect(verdict).toEqual({ kind: "ask", subhookName: "a1", reason: "a1 reason" });
  });

  test("a deny anywhere beats an earlier ask and stops the run", async () => {
    let ranAfterDeny = false;
    const after: PreToolUseSubhookRegistryEntry = {
      name: "after",
      timeoutMs: 2000,
      description: "test",
      classify: async () => {
        ranAfterDeny = true;
        return { kind: "allow" };
      },
    };
    const verdict = await runEditTimeSubhookRegistry(input, [entry("a", "ask"), entry("d", "deny"), after]);
    expect(verdict).toEqual({ kind: "deny", subhookName: "d", reason: "d reason" });
    expect(ranAfterDeny).toBe(false);
  });

  test("a throwing subhook fails open and does not mask a later ask", async () => {
    const thrower: PreToolUseSubhookRegistryEntry = {
      name: "boom",
      timeoutMs: 2000,
      description: "test",
      classify: async () => {
        throw new Error("boom");
      },
    };
    const verdict = await runEditTimeSubhookRegistry(input, [thrower, entry("a", "ask")]);
    expect(verdict?.kind).toBe("ask");
  });

  test("all allow → null", async () => {
    expect(await runEditTimeSubhookRegistry(input, [entry("x", "allow")])).toBeNull();
  });

  test("response shape is the documented PreToolUse hookSpecificOutput", () => {
    expect(buildPermissionDecisionResponse({ kind: "ask", subhookName: "s", reason: "r" })).toEqual({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: "[pretooluse-edit-time-orchestrator] s → ASK\nr",
      },
    });
  });
});
