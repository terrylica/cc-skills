// mcp-drive.test.ts — the cmd transport: the server command is taken verbatim after "--", a server that exits or
// cannot start ends the run at once (it used to wait out the 180 s request timeout).
import { describe, expect, test } from "bun:test";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const here = import.meta.dir;
const drive = join(here, "mcp-drive.ts");
const fake = join(here, "fixtures", "fake-mcp-server.ts");

function steps(list: unknown[]): string {
  const p = join(mkdtempSync(join(tmpdir(), "mcp-drive-test-")), "steps.json");
  writeFileSync(p, JSON.stringify(list));
  return p;
}
function run(args: string[]) {
  const t0 = Date.now();
  const r = Bun.spawnSync(["bun", drive, ...args], { env: { ...process.env, MCP_DRIVE_NO_SWEEP: "1" } });
  return { code: r.exitCode, out: r.stdout.toString(), err: r.stderr.toString(), ms: Date.now() - t0 };
}

describe("mcp-drive cmd mode", () => {
  test("runs the steps against the command given after --", () => {
    const r = run(["cmd", steps([{ tool: "one" }, { tool: "two", quiet: true }]), "--", "bun", fake]);
    expect(r.code).toBe(0);
    expect(r.out).toContain("[0] one: ok\necho:one");
    expect(r.out).toContain("[1] two: ok (8 chars, suppressed)");
  });
  test("a tool error ends the run with exit 1", () => {
    const r = run(["cmd", steps([{ tool: "fail" }, { tool: "never" }]), "--", "bun", fake]);
    expect(r.code).toBe(1);
    expect(r.out).toContain("[0] fail: ERROR");
    expect(r.out).not.toContain("never");
  });
  test("a server command that exits fails fast", () => {
    const r = run(["cmd", steps([{ tool: "one" }]), "--", "false"]);
    expect(r.code).toBe(1);
    expect(r.ms).toBeLessThan(15_000);
  });
  test("a server command that cannot start fails fast", () => {
    const r = run(["cmd", steps([{ tool: "one" }]), "--", "no-such-command-mcp-drive-test"]);
    expect(r.code).toBe(1);
    expect(r.err).toContain("could not start");
    expect(r.ms).toBeLessThan(15_000);
  });
  test("cmd without -- or without a command is a usage error", () => {
    expect(run(["cmd", steps([])]).code).toBe(2);
    expect(run(["cmd", steps([]), "--"]).code).toBe(2);
  });
});
