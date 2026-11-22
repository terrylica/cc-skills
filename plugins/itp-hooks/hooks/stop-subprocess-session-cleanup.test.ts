/**
 * Tests for stop-subprocess-session-cleanup.ts: the Stop hook must never signal a process
 * because it holds the controlling-terminal alias /dev/tty open.
 *
 * Run with: bun test plugins/itp-hooks/hooks/stop-subprocess-session-cleanup.test.ts
 *
 * The hook used to run `fuser -k /dev/tty` (and `/dev/tty.lock`) at the end of every turn. With
 * psmisc's fuser (Linux) that SIGKILLs every process of the user that has /dev/tty open — editors,
 * pagers, ssh and sudo prompts in the user's OTHER terminals — not only the agent's own subtree.
 *
 * Strategy: run the real hook end to end with a PATH shim named `fuser` placed first on PATH. The
 * shim records its argv and, when called with `-k`, behaves like psmisc's fuser but contained: it
 * kills only a stand-in process that this test started in its own pseudo-terminal and that holds
 * /dev/tty open (the editor in another terminal). The real fuser is never reachable from the hook
 * in this test, so even a regression cannot kill anything outside the test. `pueue` is shimmed to
 * report "no daemon" and the orphan cleanup runs in its dry-run mode, so the hook touches nothing
 * real either.
 */

import { afterAll, beforeAll, describe, expect, it } from "bun:test";
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const HOOK = join(import.meta.dir, "stop-subprocess-session-cleanup.ts");

let dir: string;
let shimDir: string;
let fuserLog: string;
let standinPidFile: string;
let scriptProc: ReturnType<typeof Bun.spawn> | null = null;
let standinPid: number | null = null;

function isAlive(pid: number): boolean {
  // `ps -p` rather than signal 0: a killed child that its parent has not reaped yet still answers
  // signal 0. The stat column is empty for a gone pid and starts with Z for a zombie.
  const r = Bun.spawnSync(["ps", "-p", String(pid), "-o", "stat="], { stdout: "pipe", stderr: "ignore" });
  const stat = r.stdout.toString().trim();
  return stat !== "" && !stat.startsWith("Z");
}

function hookEnv(): Record<string, string> {
  return {
    ...process.env,
    PATH: `${shimDir}:${process.env.PATH ?? "/usr/bin:/bin"}`,
    FUSER_SHIM_LOG: fuserLog,
    FUSER_SHIM_STANDIN_PIDFILE: standinPidFile,
    CLAUDE_SESSION_ID: `stop-cleanup-test-${process.pid}`,
    ITP_ORPHAN_CLEANUP_DRY_RUN: "1",
  } as Record<string, string>;
}

/** The pseudo-terminal launcher for this platform: BSD `script` (macOS) or util-linux `script`. */
function scriptArgv(file: string): string[] {
  return process.platform === "darwin"
    ? ["script", "-q", "/dev/null", "/bin/sh", file]
    : ["script", "-q", "-e", "-c", `/bin/sh ${file}`, "/dev/null"];
}

async function waitFor(cond: () => boolean, ms: number): Promise<boolean> {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    if (cond()) return true;
    await Bun.sleep(50);
  }
  return cond();
}

beforeAll(async () => {
  dir = mkdtempSync(join(tmpdir(), "stop-tty-"));
  shimDir = join(dir, "bin");
  fuserLog = join(dir, "fuser-argv.log");
  standinPidFile = join(dir, "standin.pid");
  Bun.spawnSync(["mkdir", "-p", shimDir]);

  // Contained stand-in for psmisc fuser: record argv; on -k, kill only the test's stand-in.
  const fuserShim = join(shimDir, "fuser");
  writeFileSync(
    fuserShim,
    [
      "#!/bin/sh",
      'printf "%s\\n" "$*" >> "$FUSER_SHIM_LOG"',
      'case " $* " in *" -k "*) [ -s "$FUSER_SHIM_STANDIN_PIDFILE" ] && kill -9 "$(cat "$FUSER_SHIM_STANDIN_PIDFILE")" ;; esac',
      "exit 0",
      "",
    ].join("\n"),
  );
  chmodSync(fuserShim, 0o755);
  // No pueue daemon: the hook's pueue step returns before it can touch a real queue.
  const pueueShim = join(shimDir, "pueue");
  writeFileSync(pueueShim, "#!/bin/sh\nexit 1\n");
  chmodSync(pueueShim, 0o755);

  // The stand-in: its own pseudo-terminal (so /dev/tty resolves), opens /dev/tty, records its pid,
  // then waits. Its argv names only the script file, so nothing in the hook can match it by argv.
  const standin = join(dir, "editor-in-another-terminal.sh");
  writeFileSync(
    standin,
    `exec 3</dev/tty || exit 9\necho $$ > ${standinPidFile}\nexec sleep 60\n`,
  );
  // stdin is /dev/null: Bun's "pipe" is a socket, and BSD script then exits at once with
  // "tcgetattr/ioctl: Operation not supported on socket" (measured on macOS 26).
  scriptProc = Bun.spawn(scriptArgv(standin), { stdin: "ignore", stdout: "ignore", stderr: "ignore" });
  if (await waitFor(() => existsSync(standinPidFile) && readFileSync(standinPidFile, "utf8").trim() !== "", 3000)) {
    standinPid = Number(readFileSync(standinPidFile, "utf8").trim());
  }
});

afterAll(() => {
  if (standinPid !== null) {
    try { process.kill(standinPid, "SIGKILL"); } catch { /* already gone */ }
  }
  if (scriptProc) {
    try { scriptProc.kill("SIGKILL"); } catch { /* already gone */ }
  }
  rmSync(dir, { recursive: true, force: true });
});

describe("stop-subprocess-session-cleanup never kills /dev/tty holders", () => {
  it("source: no executable code calls fuser", () => {
    // Comments may explain the history; executable lines may not name fuser or the lock path.
    const offending = readFileSync(HOOK, "utf8")
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .split("\n")
      .filter((line) => !/^\s*\/\//.test(line))
      .filter((line) => /\bfuser\b/.test(line) || line.includes("/dev/tty.lock"));
    expect(offending).toEqual([]);
  });

  it("the shim, not the real fuser, is what a bash -c in the hook would find", () => {
    // Safety precondition for the next test: if this failed, a regressed hook could reach the
    // real fuser, so the end-to-end run below must not happen.
    const r = Bun.spawnSync(["bash", "-c", "command -v fuser"], { env: hookEnv(), stdout: "pipe" });
    expect(r.stdout.toString().trim()).toBe(join(shimDir, "fuser"));
  });

  it(
    "a full hook run calls no fuser and an unrelated process holding /dev/tty survives",
    () => {
      const shimFound = Bun.spawnSync(["bash", "-c", "command -v fuser"], { env: hookEnv(), stdout: "pipe" });
      if (shimFound.stdout.toString().trim() !== join(shimDir, "fuser")) {
        throw new Error("refusing to run the hook: the fuser shim is not first on PATH");
      }
      // On macOS the BSD `script` stand-in is measured to work, so its absence is a test bug. On
      // other systems a missing or different `script` degrades this test to the argv assertion.
      const victim = standinPid;
      if (victim === null && process.platform === "darwin") {
        throw new Error("stand-in did not open /dev/tty in its pseudo-terminal");
      }
      if (victim === null) console.warn("no /dev/tty stand-in on this host; asserting on fuser argv only");
      if (victim !== null) expect(isAlive(victim)).toBe(true);

      const run = Bun.spawnSync([process.execPath, HOOK], {
        env: hookEnv(),
        stdin: new TextEncoder().encode("{}"),
        stdout: "pipe",
        stderr: "pipe",
      });
      expect(run.exitCode).toBe(0);

      if (victim !== null) expect(isAlive(victim)).toBe(true);
      const calls = existsSync(fuserLog) ? readFileSync(fuserLog, "utf8").trim() : "";
      expect(calls).toBe("");
      // The hook no longer claims to clear TTY references it never owned.
      expect(run.stderr.toString()).not.toContain("TTY references cleared");
    },
    30_000,
  );
});
