// Tests for orca-closeout: run the real script against a throwaway Claude config dir, a stub Orca CLI and, for every
// close, a fake `claude` agent process. Nothing here touches a real session or a real Orca terminal.
import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { appendFileSync, chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const SCRIPT = join(import.meta.dir, "orca-closeout");
// Stock macOS bash 3.2 when present, so the portability claim is what is tested.
const BASH = existsSync("/bin/bash") ? "/bin/bash" : "bash";
const SID = "0f0f0f0f-1111-4222-8333-444444444444";
const HANDLE = "term_test-handle";
const TAB = "tab-test-1";

let dir: string;
let transcript: string;
let orcaLog: string;

/** A stub Orca CLI. `waitSeconds` delays `terminal wait --for tui-idle`, like an agent still finishing its turn. */
function stubOrca(tabId: string, waitSeconds = 0): string {
  const p = join(dir, "orca");
  writeFileSync(
    p,
    `#!/bin/sh
echo "$*" >> "${orcaLog}"
case "$1 $2" in
  "terminal --help") printf 'orca terminal\n\nUsage: orca terminal <command> [options]\n\nCommands:\n  close              Close one terminal, its whole tab, or every terminal in a workspace\n' ;;
  "terminal show") printf '{"ok":true,"result":{"terminal":{"handle":"${HANDLE}","tabId":"${tabId}"}}}\\n' ;;
  "terminal wait") sleep ${waitSeconds}; printf '{"ok":true}\\n' ;;
  "terminal rename") printf '{"ok":true}\\n' ;;
  "terminal close") printf '{"ok":true}\\n' ;;
esac
`,
  );
  chmodSync(p, 0o755);
  return p;
}

function baseEnv(extra: Record<string, string | undefined> = {}): Record<string, string> {
  const e: Record<string, string | undefined> = {
    PATH: process.env.PATH ?? "/usr/bin:/bin",
    HOME: dir,
    TMPDIR: dir,
    CLAUDE_CONFIG_DIR: join(dir, "config"),
    CLAUDE_CODE_SESSION_ID: SID,
    ...extra,
  };
  for (const k of Object.keys(e)) if (e[k] === undefined) delete e[k];
  return e as Record<string, string>;
}

/** Run with no `claude` ancestor at all: double-forked into its own session, so the agent cannot be identified. */
async function runDetached(args: string[], env: Record<string, string | undefined> = {}) {
  const res = join(dir, "detached.json");
  const py = `import json, os, subprocess, sys
res, argv = sys.argv[1], sys.argv[2:]
if os.fork() == 0:
    os.setsid()
    if os.fork() == 0:
        r = subprocess.run(argv, capture_output=True, text=True)
        open(res + ".tmp", "w").write(json.dumps({"code": r.returncode, "out": r.stdout, "err": r.stderr}))
        os.rename(res + ".tmp", res)
    os._exit(0)
os.wait()`;
  Bun.spawnSync(["python3", "-c", py, res, BASH, SCRIPT, ...args], { env: baseEnv(env), cwd: dir });
  await until(() => existsSync(res), 15000);
  return JSON.parse(readFileSync(res, "utf8")) as { code: number; out: string; err: string };
}

function run(args: string[], env: Record<string, string | undefined> = {}) {
  const r = Bun.spawnSync([BASH, SCRIPT, ...args], { env: baseEnv(env), cwd: dir });
  return { code: r.exitCode, out: r.stdout.toString(), err: r.stderr.toString() };
}

/**
 * Run the script the way Claude Code does: from a Bash-tool shell (marked by sourcing a shell snapshot) whose parent is
 * a program named `claude`. `background` leaves another such shell running, like a background command; `linger` keeps
 * the fake agent alive afterwards, so the closer can re-check it.
 */
function runAsAgent(args: string[], opts: { background?: number; linger?: number; env?: Record<string, string | undefined> } = {}) {
  const bin = join(dir, "bin");
  mkdirSync(bin, { recursive: true });
  const fake = join(bin, "claude");
  const argFile = join(dir, "args");
  writeFileSync(argFile, `${args.join("\n")}\n`);
  writeFileSync(
    fake,
    `#!${BASH}
${opts.background ? `${BASH} -c ': shell-snapshots/snapshot-test; sleep ${opts.background}; true' &\nsleep 0.3` : ""}
${BASH} -c ': shell-snapshots/snapshot-test; args=(); while IFS= read -r a; do args+=("$a"); done < "$1"; ${BASH} "$2" "\${args[@]}"' x '${argFile}' '${SCRIPT}'
rc=$?
${opts.linger ? `sleep ${opts.linger} >/dev/null 2>&1 &` : ""}
exit $rc
`,
  );
  chmodSync(fake, 0o755);
  const r = Bun.spawnSync([fake], { env: baseEnv(opts.env ?? {}), cwd: dir });
  return { code: r.exitCode, out: r.stdout.toString(), err: r.stderr.toString() };
}

const orcaEnv = (orca: string, tab = TAB): Record<string, string | undefined> => ({ ORCA_CLI: orca, ORCA_TERMINAL_HANDLE: HANDLE, ORCA_TAB_ID: tab });
const lines = () => readFileSync(transcript, "utf8").split("\n").filter(Boolean);
const orcaCalls = () => (existsSync(orcaLog) ? readFileSync(orcaLog, "utf8") : "");
const closerLog = () => {
  const p = join(dir, `orca-closeout-${HANDLE}.log`);
  return existsSync(p) ? readFileSync(p, "utf8") : "";
};
async function until(cond: () => boolean, ms = 8000) {
  for (let t = 0; t < ms && !cond(); t += 100) await Bun.sleep(100);
  return cond();
}

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "orca-closeout-"));
  const proj = join(dir, "config", "projects", "-tmp-start");
  mkdirSync(proj, { recursive: true });
  transcript = join(proj, `${SID}.jsonl`);
  writeFileSync(
    transcript,
    `${JSON.stringify({ type: "user", cwd: "/tmp/start", sessionId: SID })}\n${JSON.stringify({ type: "assistant", cwd: "/tmp/elsewhere" })}\n`,
  );
  orcaLog = join(dir, "orca.log");
});
afterEach(() => rmSync(dir, { recursive: true, force: true }));

describe("show", () => {
  test("reports the session, no title yet, and a resume command from the starting folder", () => {
    const r = run([]);
    expect(r.code).toBe(0);
    const j = JSON.parse(r.out);
    expect(j.session).toBe(SID);
    expect(j.title).toBeNull();
    expect(j.resume).toBe(`cd /tmp/start && claude --resume ${SID}`);
  });
  test("refuses outside a Claude Code session", () => {
    expect(run([], { CLAUDE_CODE_SESSION_ID: undefined }).code).toBe(2);
  });
});

describe("--title", () => {
  test("appends the same two records Claude Code's /rename writes", () => {
    const r = run(["--title", "Area: what was done"]);
    expect(r.code).toBe(0);
    const tail = lines().slice(-2).map((l) => JSON.parse(l));
    expect(tail[0]).toEqual({ type: "custom-title", customTitle: "Area: what was done", sessionId: SID });
    expect(tail[1]).toEqual({ type: "agent-name", agentName: "Area: what was done", sessionId: SID });
    expect(JSON.parse(r.out).named).toBe(true);
    expect(JSON.parse(run([]).out).title).toBe("Area: what was done");
  });
  test("never glues onto a partial last line", () => {
    writeFileSync(transcript, readFileSync(transcript, "utf8").trimEnd());
    expect(run(["--title", "x"]).code).toBe(0);
    for (const l of lines()) expect(() => JSON.parse(l)).not.toThrow();
  });
  test("removes control characters as Claude Code does, and collapses whitespace as Orca does", () => {
    run(["--title", "  a\tb\u0007c   d  "]);
    expect(JSON.parse(lines().at(-2)!).customTitle).toBe("abc d");
  });
  test("refuses 97+ units (Orca's limit) unless --allow-long, and 201+ characters always", () => {
    const before = readFileSync(transcript, "utf8");
    expect(run(["--title", "x".repeat(97)]).code).toBe(2);
    expect(readFileSync(transcript, "utf8")).toBe(before);
    expect(run(["--title", "x".repeat(96)]).code).toBe(0);
    expect(run(["--title", "y".repeat(150), "--allow-long"]).code).toBe(0);
    expect(run(["--title", "z".repeat(201), "--allow-long"]).code).toBe(2);
  });
  test("counts characters outside the basic plane as Orca does (two units each)", () => {
    expect(run(["--title", "\u{1F680}".repeat(49)]).code).toBe(2); // 49 code points, 98 UTF-16 units
  });
  test("--dry-run writes nothing", () => {
    const before = readFileSync(transcript, "utf8");
    expect(run(["--title", "t", "--dry-run"]).code).toBe(0);
    expect(readFileSync(transcript, "utf8")).toBe(before);
  });
  test("labels this Orca tab by its explicit handle", () => {
    const r = run(["--title", "Long title", "--tab-title", "Short"], orcaEnv(stubOrca(TAB)));
    expect(r.code).toBe(0);
    expect(orcaCalls()).toContain(`terminal rename --terminal ${HANDLE} --title Short --json`);
  });
});

describe("--close refuses before changing anything", () => {
  const cases: Array<[string, Record<string, string | undefined>, string, boolean]> = [
    ["outside an Orca terminal", { ORCA_TERMINAL_HANDLE: undefined }, TAB, true],
    ["without ORCA_TAB_ID", { ORCA_TAB_ID: "" }, TAB, true],
    ["when the handle is another session's tab", {}, "someone-elses-tab", true],
    ["when no agent process can be identified (fails closed)", {}, TAB, false],
  ];
  for (const [why, override, tabSeen, viaAgent] of cases) {
    test(why, async () => {
      const env = { ...orcaEnv(stubOrca(tabSeen)), ...override };
      const before = readFileSync(transcript, "utf8");
      const r = viaAgent ? runAsAgent(["--title", "t", "--close"], { env }) : await runDetached(["--title", "t", "--close"], env);
      expect(r.code).toBe(2);
      expect(readFileSync(transcript, "utf8")).toBe(before);
      expect(orcaCalls()).not.toContain("terminal close");
    });
  }
  test("while a background command is running, unless --force", () => {
    const busy = runAsAgent(["--close", "--min-wait", "0"], { background: 3, env: orcaEnv(stubOrca(TAB)) });
    expect(busy.code).toBe(2);
    expect(busy.err).toContain("still running");
  }, 20000);
});

describe("--close", () => {
  test("closes only its own tab, by handle, after Orca reports the agent idle", async () => {
    const r = runAsAgent(["--close", "--min-wait", "0"], { env: orcaEnv(stubOrca(TAB, 1)), linger: 6 });
    expect(r.code).toBe(0);
    expect(JSON.parse(r.out).close_scheduled).toBe(true);
    expect(await until(() => orcaCalls().includes("terminal close"))).toBe(true);
    const calls = orcaCalls();
    expect(calls).toContain(`terminal wait --terminal ${HANDLE} --for tui-idle`);
    expect(calls.indexOf("terminal wait")).toBeLessThan(calls.indexOf("terminal close"));
    expect(calls).toContain(`terminal close --terminal ${HANDLE} --tab --json`);
    expect(calls).not.toContain("--all");
  }, 20000);
  test("cancels if the user types a new prompt before the agent goes idle", async () => {
    const r = runAsAgent(["--close", "--min-wait", "0"], { env: orcaEnv(stubOrca(TAB, 2)), linger: 6 });
    expect(r.code).toBe(0);
    appendFileSync(transcript, `${JSON.stringify({ type: "user", message: { role: "user", content: "wait, one more thing" } })}\n`);
    expect(await until(() => closerLog().includes("new prompt"))).toBe(true);
    expect(orcaCalls()).not.toContain("terminal close");
  }, 20000);
  test("re-checks at close time: a background command started meanwhile cancels the close", async () => {
    const orca = stubOrca(TAB, 2);
    const bin = join(dir, "bin");
    mkdirSync(bin, { recursive: true });
    const fake = join(bin, "claude");
    writeFileSync(
      fake,
      `#!${BASH}
${BASH} -c ': shell-snapshots/snapshot-test; ${BASH} "$1" --close --min-wait 0' x '${SCRIPT}'
${BASH} -c ': shell-snapshots/snapshot-test; sleep 6; true' &
wait
`,
    );
    chmodSync(fake, 0o755);
    const proc = Bun.spawn([fake], { env: baseEnv(orcaEnv(orca)), cwd: dir, stdout: "ignore", stderr: "ignore" });
    expect(await until(() => closerLog().includes("still running"))).toBe(true);
    expect(orcaCalls()).not.toContain("terminal close");
    proc.kill();
  }, 20000);
});
