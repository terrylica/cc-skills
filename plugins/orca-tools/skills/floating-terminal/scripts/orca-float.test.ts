// Tests for orca-float: run the real script against a stub Orca CLI that records every call and executes the launcher
// the way Orca's floating terminal would. Nothing here touches a real Orca. The logged path (`script`, a real TTY) is
// exercised live, not here: a test runner has no TTY, so these tests use --no-log.
import { afterEach, beforeEach, describe, expect, setDefaultTimeout, test } from "bun:test";
import { chmodSync, existsSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

setDefaultTimeout(30_000);
const SCRIPT = join(import.meta.dir, "orca-float");
const BASH = existsSync("/bin/bash") ? "/bin/bash" : "bash";

let dir: string;
let stub: string;
let calls: string;

// A stub Orca: identifies itself in --help, runs `terminal create --command` in the background (as the floating
// terminal's shell would), reports the floating workspace from `terminal show`, and appends every call to $calls.
function writeStub(worktreeId = "global-floating-terminal") {
  writeFileSync(
    stub,
    `#!/bin/bash
echo "$*" >> "${calls}"
case "$1 $2" in
  "--help "*) echo "worktree create  terminal create"; exit 0 ;;
  "terminal create")
    shift 2; c=""; while [ $# -gt 0 ]; do [ "$1" = --command ] && c=$2; shift; done
    ( bash -c "$c" >/dev/null 2>&1 & )
    echo '{"ok":true,"result":{"terminal":{"handle":"term_stub-1"}}}' ;;
  "terminal show") echo '{"ok":true,"result":{"terminal":{"handle":"term_stub-1","worktreeId":"${worktreeId}"}}}' ;;
  "terminal close") echo '{"ok":true}' ;;
  *) echo '{"ok":true}' ;;
esac
`,
  );
  chmodSync(stub, 0o755);
}

function run(args: string[], env: Record<string, string> = {}) {
  const p = Bun.spawnSync([BASH, SCRIPT, ...args], {
    env: { PATH: process.env.PATH ?? "", HOME: dir, TMPDIR: dir, ORCA_CLI: stub, ...env },
    cwd: dir,
  });
  const out = p.stdout.toString();
  return { code: p.exitCode, json: out.trim() ? JSON.parse(out) : null, err: p.stderr.toString() };
}
const callLog = () => (existsSync(calls) ? readFileSync(calls, "utf8") : "");

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "orca-float-test-"));
  stub = join(dir, "orca");
  calls = join(dir, "calls.log");
  writeStub();
});
afterEach(() => rmSync(dir, { recursive: true, force: true }));

describe("run", () => {
  test("returns the command's REAL exit code, not Orca's", () => {
    const r = run(["run", "--no-log", "--timeout", "10", "--", "exit 7"]);
    expect(r.code).toBe(1);
    expect(r.json.ok).toBe(false);
    expect(r.json.state).toBe("finished");
    expect(r.json.exit_code).toBe(7);
  });

  test("success closes ITS OWN tab, by handle, never --all", () => {
    const r = run(["run", "--no-log", "--timeout", "10", "--", "true"]);
    expect(r.code).toBe(0);
    expect(r.json).toMatchObject({ ok: true, exit_code: 0, tab_closed: true, handle: "term_stub-1" });
    const log = callLog();
    expect(log).toContain("terminal close --terminal term_stub-1 --tab");
    expect(log).not.toContain("--all");
  });

  test("failure keeps the tab open for the person to read", () => {
    const r = run(["run", "--no-log", "--timeout", "10", "--", "false"]);
    expect(r.json.tab_closed).toBe(false);
    expect(callLog()).not.toContain("terminal close");
  });

  test("--keep keeps the tab even on success", () => {
    const r = run(["run", "--no-log", "--keep", "--timeout", "10", "--", "true"]);
    expect(r.json.tab_closed).toBe(false);
  });

  test("creates the tab in the floating workspace", () => {
    run(["run", "--no-log", "--timeout", "10", "--", "true"]);
    expect(callLog()).toContain("terminal create --worktree id:global-floating-terminal");
  });

  test("a command that never finishes times out", () => {
    const r = run(["run", "--no-log", "--timeout", "2", "--", "sleep 20"]);
    expect(r.code).toBe(1);
    expect(r.json.state).toBe("timeout");
    expect(r.json.exit_code).toBeNull();
  });

  test("--dry-run shows the launcher and creates nothing", () => {
    const r = run(["run", "--dry-run", "--cwd", dir, "--", "printf", "%s", "a b"]);
    expect(r.code).toBe(0);
    expect(r.json.dry_run).toBe(true);
    expect(r.json.command).toBe("printf %s 'a b'");
    expect(r.json.launch).toContain("script -q");
    expect(callLog()).toBe("");
  });
});

describe("doctor", () => {
  test("ok when the probe lands in the floating workspace, and the probe is closed", () => {
    const r = run(["doctor"]);
    expect(r.json).toMatchObject({ ok: true, floating: true });
    expect(callLog()).toContain("terminal close --terminal term_stub-1 --tab");
  });

  test("fails when the tab lands anywhere else", () => {
    writeStub("some-worktree");
    const r = run(["doctor"]);
    expect(r.code).toBe(1);
    expect(r.json).toMatchObject({ ok: false, floating: false, landed_in: "some-worktree" });
  });
});

describe("finding the CLI", () => {
  test("Linux names the CLI orca-ide; it is found on PATH without ORCA_CLI", () => {
    renameSync(stub, join(dir, "orca-ide"));
    const r = run(["doctor"], { ORCA_CLI: "", PATH: `${dir}:/usr/bin:/bin` });
    expect(r.json).toMatchObject({ ok: true, orca: join(dir, "orca-ide") });
  });
});

describe("Orca refuses", () => {
  test("no Orca running for this user: Orca's own error, no traceback, exit 1", () => {
    writeFileSync(stub, readFileSync(stub, "utf8").replace(`echo '{"ok":true,"result":{"terminal":{"handle":"term_stub-1"}}}' ;;`, `echo '{"ok":false,"error":{"code":"runtime_unavailable","message":"no runtime"}}'; exit 1 ;;`));
    const r = run(["doctor"]);
    expect(r.code).toBe(1);
    expect(r.json.ok).toBe(false);
    expect(r.err).toContain("runtime_unavailable");
    expect(r.err).not.toContain("Traceback");
  });
});

describe("refusals", () => {
  test("no Orca CLI → exit 3 with a JSON error", () => {
    const r = run(["doctor"], { ORCA_CLI: join(dir, "not-orca") });
    expect(r.code).toBe(3);
    expect(r.json.ok).toBe(false);
  });

  test("a non-numeric --timeout is a usage error", () => {
    expect(run(["run", "--timeout", "soon", "--", "true"]).code).toBe(2);
  });

  test("run without a command is a usage error", () => {
    expect(run(["run", "--no-log"]).code).toBe(2);
  });
});
