// Tests for orca-closeout: run the real script against a throwaway Claude config dir, a stub Orca CLI and, for every
// close, a fake `claude` agent process. Nothing here touches a real session or a real Orca terminal.
import { afterEach, beforeEach, describe, expect, setDefaultTimeout, test } from "bun:test";

// Every test here spawns the real bash + python script (and many let its watcher linger), so its
// wall-clock time stretches with machine load; bun's 5 s default failed the gate at load ~15.
setDefaultTimeout(30_000);
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

const WT = "repo-1::/tmp/start";

/** Orca's sidebar rows (`worktree ps`): this tab's row, plus optionally another session's tab in the same workspace. */
function setRows(state: string, opts: { workingMode?: string; otherTab?: boolean; comment?: string; status?: string } = {}) {
  const agents = [{ paneKey: `${TAB}:leaf-1`, state, workingMode: opts.workingMode ?? null, mainAgent: { state: "done" } }];
  if (opts.otherTab) agents.push({ paneKey: "other-tab:leaf-9", state: "done", workingMode: null, mainAgent: { state: "done" } });
  const wt = { worktreeId: WT, comment: opts.comment ?? "old comment", workspaceStatus: opts.status ?? "todo", agents };
  writeFileSync(join(dir, "ps.json"), `${JSON.stringify({ ok: true, result: { worktrees: [wt], truncated: false } })}\n`);
}

/** Orca's per-tab agent status record, as its hook listener persists it. */
function setStatus(subagents: Array<{ id: string; state: string }>, extra: Record<string, unknown> = {}, sid = SID) {
  const p = join(dir, "orca-data", "agent-hooks");
  mkdirSync(p, { recursive: true });
  const entry = { tabId: TAB, paneKey: `${TAB}:leaf-1`, providerSession: { id: sid }, payload: { subagents }, ...extra };
  writeFileSync(join(p, "last-status.json"), JSON.stringify({ version: 1, entries: { [`${TAB}:leaf-1`]: entry } }));
}

/**
 * A stub Orca CLI. `waitSeconds` delays `terminal wait --for tui-idle`, like an agent still finishing its turn.
 * Behaviour can be changed while a watcher runs, through files in the test dir: `hang-<cmd>-<sub>` makes that command
 * hang (`hang(...)`), `show-tab` replaces the tab id that `terminal show` reports, `wait-fails` makes `terminal wait`
 * exit 1.
 */
function stubOrca(tabId: string, waitSeconds = 0): string {
  const p = join(dir, "orca");
  if (!existsSync(join(dir, "ps.json"))) setRows("done");
  writeFileSync(
    p,
    `#!/bin/sh
echo "$*" >> "${orcaLog}"
[ -f "${dir}/hang-$1-$2" ] && sleep 30
case "$1 $2" in
  "terminal --help") printf 'orca terminal\n\nUsage: orca terminal <command> [options]\n\nCommands:\n  close              Close one terminal, its whole tab, or every terminal in a workspace\n' ;;
  "terminal show") t=${tabId}; [ -f "${dir}/show-tab" ] && t=$(cat "${dir}/show-tab"); printf '{"ok":true,"result":{"terminal":{"handle":"${HANDLE}","tabId":"%s","title":"auto title"}}}\\n' "$t" ;;
  "terminal wait") [ -f "${dir}/wait-fails" ] && exit 1; sleep ${waitSeconds}; printf '{"ok":true}\\n' ;;
  "terminal rename") printf '{"ok":true}\\n' ;;
  "terminal close") printf '{"ok":true}\\n' ;;
  "worktree ps") cat "${dir}/ps.json" ;;
  "worktree set") printf '{"ok":true}\\n' ;;
esac
`,
  );
  chmodSync(p, 0o755);
  return p;
}

/** Make `orca <cmd> <sub>` hang (until the script's call timeout kills it). */
const hang = (cmd: string, sub: string) => writeFileSync(join(dir, `hang-${cmd}-${sub}`), "");
/** Short call timeouts, so a hanging stub is cut off in a second. */
const FAST = { ORCA_CLOSEOUT_CALL_TIMEOUT: "1" };

function baseEnv(extra: Record<string, string | undefined> = {}): Record<string, string> {
  const e: Record<string, string | undefined> = {
    PATH: process.env.PATH ?? "/usr/bin:/bin",
    HOME: dir,
    TMPDIR: dir,
    CLAUDE_CONFIG_DIR: join(dir, "config"),
    CLAUDE_CODE_SESSION_ID: SID,
    ORCA_USER_DATA_PATH: join(dir, "orca-data"),
    ORCA_CLOSEOUT_POLL: "1",
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

/**
 * Run with no `claude` ancestor, synchronously: double-forked away from the test runner, so a real Claude Code session
 * running these tests (and the work it has running) is never mistaken for the script's own agent.
 */
function run(args: string[], env: Record<string, string | undefined> = {}) {
  const res = join(dir, "isolated.json");
  rmSync(res, { force: true });
  const py = `import json, os, subprocess, sys, time
res, argv = sys.argv[1], sys.argv[2:]
if os.fork() == 0:
    os.setsid()
    if os.fork() == 0:
        r = subprocess.run(argv, capture_output=True, text=True)
        open(res + ".tmp", "w").write(json.dumps({"code": r.returncode, "out": r.stdout, "err": r.stderr}))
        os.rename(res + ".tmp", res)
    os._exit(0)
os.wait()
for _ in range(300):
    if os.path.exists(res): break
    time.sleep(0.05)`;
  Bun.spawnSync(["python3", "-c", py, res, BASH, SCRIPT, ...args], { env: baseEnv(env), cwd: dir });
  return JSON.parse(readFileSync(res, "utf8")) as { code: number; out: string; err: string };
}

/**
 * Run the script the way Claude Code does: from a Bash-tool shell (marked by sourcing a shell snapshot) whose parent is
 * a program named `claude`. `background` leaves another such shell running, like a background command; `linger` keeps
 * the fake agent alive afterwards, so the closer can re-check it.
 */
function runAsAgent(
  args: string[],
  opts: { background?: number; linger?: number; env?: Record<string, string | undefined>; script?: string } = {},
) {
  const script = opts.script ?? SCRIPT;
  const bin = join(dir, "bin");
  mkdirSync(bin, { recursive: true });
  const fake = join(bin, "claude");
  const argFile = join(dir, "args");
  const res = join(dir, "agent-run");
  for (const f of [`${res}.out`, `${res}.err`, `${res}.rc`]) rmSync(f, { force: true });
  writeFileSync(argFile, args.map((a) => `${a}\n`).join(""));
  // With `linger`, the fake agent itself stays alive afterwards (as a real session does), so the watcher can keep
  // checking it; the result is read from files the agent writes before it lingers.
  writeFileSync(
    fake,
    `#!${BASH}
${opts.background ? `${BASH} -c ': shell-snapshots/snapshot-test; sleep ${opts.background}; true' &\nsleep 0.3` : ""}
${BASH} -c ': shell-snapshots/snapshot-test; args=(); while IFS= read -r a; do args+=("$a"); done < "$1"; ${BASH} "$2" "\${args[@]}"' x '${argFile}' '${script}' >'${res}.out' 2>'${res}.err'
echo $? >'${res}.rc'
${opts.linger ? `sleep ${opts.linger} >/dev/null 2>&1` : ""}
exit 0
`,
  );
  chmodSync(fake, 0o755);
  if (opts.linger) {
    Bun.spawn([fake], { env: baseEnv(opts.env ?? {}), cwd: dir, stdout: "ignore", stderr: "ignore" });
    const t0 = Date.now();
    while (!existsSync(`${res}.rc`) && Date.now() - t0 < 15000) Bun.sleepSync(50);
  } else {
    Bun.spawnSync([fake], { env: baseEnv(opts.env ?? {}), cwd: dir });
  }
  const rc = existsSync(`${res}.rc`) ? Number(readFileSync(`${res}.rc`, "utf8").trim()) : -1;
  return { code: rc, out: readFileSync(`${res}.out`, "utf8"), err: readFileSync(`${res}.err`, "utf8") };
}

const orcaEnv = (orca: string, tab = TAB): Record<string, string | undefined> => ({
  ORCA_CLI: orca,
  ORCA_TERMINAL_HANDLE: HANDLE,
  ORCA_TAB_ID: tab,
  ORCA_WORKTREE_ID: WT,
});
/** Transcript records: a background command launched, and (optionally) its completion notification. */
const launch = (id: string) => JSON.stringify({ type: "user", toolUseResult: { backgroundTaskId: id } });
const notified = (id: string) =>
  JSON.stringify({ type: "user", message: { role: "user", content: `<task-notification>\n<task-id>${id}</task-id>\n<status>completed</status>\n</task-notification>` } });
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
  test("when Orca's status record for this tab belongs to another session (fails closed)", () => {
    setStatus([], {}, "aaaaaaaa-0000-4000-8000-000000000000");
    const r = runAsAgent(["--title", "t", "--close"], { env: orcaEnv(stubOrca(TAB)) });
    expect(r.code).toBe(2);
    expect(r.err).toContain("orca_status=other-session");
    expect(orcaCalls()).not.toContain("terminal close");
  });
  test("when Orca's status record is unreadable, unless --force", () => {
    mkdirSync(join(dir, "orca-data", "agent-hooks"), { recursive: true });
    writeFileSync(join(dir, "orca-data", "agent-hooks", "last-status.json"), "{not json");
    expect(runAsAgent(["--close"], { env: orcaEnv(stubOrca(TAB)) }).code).toBe(2);
    expect(runAsAgent(["--close", "--force", "--dry-run"], { env: orcaEnv(stubOrca(TAB)) }).code).toBe(0);
  });
});

describe("running work is reported by every form", () => {
  test("a background command launched with no completion notification", () => {
    appendFileSync(transcript, `${launch("bgtask01")}\n`);
    const j = JSON.parse(run([]).out);
    expect(j.running_count).toBe(1);
    expect(j.running[0]).toMatchObject({ kind: "background-command", id: "bgtask01", source: "transcript" });
  });
  test("is cleared by its task notification, or by a TaskStop result", () => {
    appendFileSync(transcript, `${launch("bgtask01")}\n${notified("bgtask01")}\n${launch("bgtask02")}\n`);
    appendFileSync(transcript, `${JSON.stringify({ type: "user", toolUseResult: { task_id: "bgtask02", task_type: "local_bash" } })}\n`);
    expect(JSON.parse(run([]).out).running_count).toBe(0);
  });
  test("a working subagent or teammate in Orca's status record; idle and done ones are finished", () => {
    setStatus([
      { id: "a-1", state: "working" },
      { id: "a-2", state: "idle" },
      { id: "a-3", state: "done" },
    ]);
    const j = JSON.parse(run([], { ORCA_TAB_ID: TAB }).out);
    expect(j.running.map((r: { id: string }) => r.id)).toEqual(["a-1"]);
    expect(j.checks.orca_status).toBe("ok");
  });
  test("a background shell or monitor, and a pending task wake-up, from Orca's status record", () => {
    setStatus([], { claudeRunningNonAgentTask: true, claudeTaskWakeupPending: "notification" });
    const kinds = JSON.parse(run([], { ORCA_TAB_ID: TAB }).out).running.map((r: { kind: string }) => r.kind);
    expect(kinds).toEqual(["background-task", "wakeup"]);
  });
  test("a session-only cron without a CronDelete, and a ScheduleWakeup not yet due", () => {
    const now = new Date().toISOString();
    appendFileSync(
      transcript,
      `${JSON.stringify({ type: "assistant", timestamp: now, message: { content: [{ type: "tool_use", id: "tu1", name: "CronCreate", input: { cron: "*/5 * * * *", prompt: "check", recurring: true } }] } })}\n` +
        `${JSON.stringify({ type: "user", timestamp: now, toolUseResult: { id: "cron-abc1" }, message: { content: [{ type: "tool_result", tool_use_id: "tu1", content: "ok" }] } })}\n` +
        `${JSON.stringify({ type: "assistant", timestamp: now, message: { content: [{ type: "tool_use", id: "tu2", name: "ScheduleWakeup", input: { delaySeconds: 1200 } }] } })}\n`,
    );
    const j = JSON.parse(run([]).out);
    expect(j.running.map((r: { kind: string }) => r.kind).toSorted()).toEqual(["cron", "wakeup"]);
    appendFileSync(
      transcript,
      `${JSON.stringify({ type: "assistant", message: { content: [{ type: "tool_use", id: "tu3", name: "CronDelete", input: { id: "cron-abc1" } }, { type: "tool_use", id: "tu4", name: "ScheduleWakeup", input: { stop: true } }] } })}\n`,
    );
    expect(JSON.parse(run([]).out).running_count).toBe(0);
  });
  test("a one-shot cron is finished once its prompt has arrived as a user turn", () => {
    // A one-shot fires once and deletes itself, so no CronDelete follows; its
    // prompt being delivered is the record that it ran.
    const now = new Date().toISOString();
    const prompt = "Run the final post-deploy check and report.";
    appendFileSync(
      transcript,
      `${JSON.stringify({ type: "assistant", timestamp: now, message: { content: [{ type: "tool_use", id: "tu5", name: "CronCreate", input: { cron: "52 15 30 10 *", prompt, recurring: false } }] } })}\n` +
        `${JSON.stringify({ type: "user", timestamp: now, toolUseResult: { id: "2d97c865", recurring: false }, message: { content: [{ type: "tool_result", tool_use_id: "tu5", content: "Scheduled one-shot task 2d97c865" }] } })}\n`,
    );
    expect(JSON.parse(run([]).out).running.map((r: { id: string }) => r.id)).toEqual(["2d97c865"]);
    appendFileSync(transcript, `${JSON.stringify({ type: "user", timestamp: now, message: { role: "user", content: prompt } })}\n`);
    expect(JSON.parse(run([]).out).running_count).toBe(0);
  });
  test("api-request-blob copies of earlier tool calls are not new events", () => {
    // Claude Code stores a copy of each API request, which replays earlier
    // tool_use and tool_result blocks. Read as events, a replayed CronCreate
    // was counted a second time (keyed by its tool-use id, since the copy has
    // no result), and a replayed ScheduleWakeup could undo a later stop.
    const now = new Date().toISOString();
    const create = { type: "tool_use", id: "tu6", name: "CronCreate", input: { cron: "*/5 * * * *", prompt: "check", recurring: true } };
    const result = { type: "tool_result", tool_use_id: "tu6", content: "Scheduled recurring task cron-def2" };
    appendFileSync(
      transcript,
      `${JSON.stringify({ type: "assistant", timestamp: now, message: { content: [create] } })}\n` +
        `${JSON.stringify({ type: "user", timestamp: now, toolUseResult: { id: "cron-def2" }, message: { content: [result] } })}\n` +
        `${JSON.stringify({ type: "assistant", timestamp: now, message: { content: [{ type: "tool_use", id: "tu7", name: "CronDelete", input: { id: "cron-def2" } }] } })}\n` +
        `${JSON.stringify({ type: "api-request-blob", message: { content: [create, { type: "tool_use", id: "tu8", name: "ScheduleWakeup", input: { delaySeconds: 1200 } }] } })}\n` +
        `${JSON.stringify({ type: "api-request-blob", message: { content: [result] } })}\n`,
    );
    expect(JSON.parse(run([]).out).running_count).toBe(0);
  });
});

describe("naming while work is running", () => {
  test("names the session, marks the tab and the workspace, and a watcher removes the markers once it settles", async () => {
    setStatus([{ id: "a-1", state: "working" }]);
    setRows("working", { workingMode: "monitoring", comment: "old comment", status: "todo" });
    const r = runAsAgent(["--title", "Area: done", "--tab-title", "Short"], { env: orcaEnv(stubOrca(TAB)), linger: 8 });
    expect(r.code).toBe(0);
    const j = JSON.parse(r.out);
    expect(j.named).toBe(true);
    expect(j.marked).toEqual({ tab: true, workspace: true });
    expect(j.close_scheduled).toBe(false);
    expect(lines().slice(-2).map((l) => JSON.parse(l).type)).toEqual(["custom-title", "agent-name"]);
    expect(orcaCalls()).toContain(`terminal rename --terminal ${HANDLE} --title [running] Short --json`);
    expect(orcaCalls()).toContain(`worktree set --worktree id:${WT} --workspace-status in-progress --comment Running: 1 subagent | old comment --json`);
    // The work finishes: the watcher restores the plain label and the old comment and status, and closes nothing.
    setStatus([{ id: "a-1", state: "done" }]);
    setRows("done");
    expect(await until(() => closerLog().includes("markers removed"), 12000)).toBe(true);
    expect(orcaCalls()).toContain(`terminal rename --terminal ${HANDLE} --title Short --json`);
    expect(orcaCalls()).toContain(`worktree set --worktree id:${WT} --comment old comment --workspace-status todo --json`);
    expect(orcaCalls()).not.toContain("terminal close");
  });
  test("never adds a comment to a workspace that had none (Orca cannot clear one), and resets an unlabelled tab", async () => {
    setStatus([{ id: "a-1", state: "working" }]);
    setRows("working", { comment: "", status: "todo" });
    const j = JSON.parse(runAsAgent(["--title", "t"], { env: orcaEnv(stubOrca(TAB)), linger: 8 }).out);
    expect(j.marked).toEqual({ tab: true, workspace: true });
    expect(orcaCalls()).toContain(`worktree set --worktree id:${WT} --workspace-status in-progress --json`);
    setStatus([{ id: "a-1", state: "done" }]);
    setRows("done", { comment: "", status: "in-progress" });
    expect(await until(() => closerLog().includes("markers removed"), 12000)).toBe(true);
    expect(orcaCalls()).not.toContain("--comment");
    expect(orcaCalls()).toContain(`worktree set --worktree id:${WT} --workspace-status todo --json`);
  });
  test("a tab without a label of ours is marked from its current title, and reset by omitting --title", async () => {
    setStatus([{ id: "a-1", state: "working" }]);
    setRows("working");
    runAsAgent(["--close", "--min-wait", "0"], { env: orcaEnv(stubOrca(TAB)), linger: 10 });
    expect(orcaCalls()).toContain(`terminal rename --terminal ${HANDLE} --title [running] auto title --json`);
    setStatus([{ id: "a-1", state: "done" }]);
    setRows("done");
    expect(await until(() => orcaCalls().includes("terminal close"), 12000)).toBe(true);
    // `orca terminal rename --help`: "Omit --title or pass an empty string to reset to the auto-generated title."
    // Never `--title ""`, and never the old "auto title" frozen as a custom one.
    const restores = orcaCalls().split("\n").filter((l) => l.startsWith("terminal rename") && !l.includes("[running]"));
    expect(restores).toEqual([`terminal rename --terminal ${HANDLE} --json`]);
  });
  test("does not mark the workspace when another session's tab shares it", () => {
    setStatus([{ id: "a-1", state: "working" }]);
    setRows("working", { otherTab: true });
    const j = JSON.parse(runAsAgent(["--title", "t"], { env: orcaEnv(stubOrca(TAB)), linger: 2 }).out);
    expect(j.marked).toEqual({ tab: true, workspace: false });
    expect(orcaCalls()).not.toContain("worktree set");
  });
  test("with nothing running, nothing is marked and no watcher starts", () => {
    const j = JSON.parse(runAsAgent(["--title", "t", "--tab-title", "Short"], { env: orcaEnv(stubOrca(TAB)) }).out);
    expect(j.marked).toEqual({ tab: false, workspace: false });
    expect(j.watcher_pid).toBeNull();
    expect(orcaCalls()).toContain("--title Short --json");
  });
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
  test("waits for a running subagent: closes only after Orca shows it finished and the row settled", async () => {
    setStatus([{ id: "a-1", state: "working" }]);
    setRows("working", { workingMode: undefined });
    const r = runAsAgent(["--close", "--min-wait", "0"], { env: orcaEnv(stubOrca(TAB)), linger: 12 });
    expect(r.code).toBe(0);
    const j = JSON.parse(r.out);
    expect(j.close_deferred).toBe(true);
    expect(j.marked.tab).toBe(true);
    await Bun.sleep(3000);
    expect(orcaCalls()).not.toContain("terminal close");
    setStatus([{ id: "a-1", state: "done" }]);
    setRows("done");
    expect(await until(() => orcaCalls().includes("terminal close"), 12000)).toBe(true);
    expect(closerLog()).toContain("settled");
    // The markers come off before the tab closes, so a close that fails leaves no "[running]" behind.
    const calls = orcaCalls();
    expect(calls.lastIndexOf(`worktree set --worktree id:${WT} --comment old comment --workspace-status todo --json`)).toBeLessThan(
      calls.indexOf("terminal close"),
    );
    expect(closerLog()).toContain("markers removed");
  });
  test("the row held open by child work after the turn ended (Orca's monitoring) also defers the close", async () => {
    setRows("working", { workingMode: "monitoring" });
    const r = runAsAgent(["--close", "--min-wait", "0", "--settle-timeout", "3"], { env: orcaEnv(stubOrca(TAB)), linger: 10 });
    expect(r.code).toBe(0);
    expect(await until(() => closerLog().includes("gave up"), 12000)).toBe(true);
    expect(orcaCalls()).not.toContain("terminal close");
  });
  test("gives up after --settle-timeout: the tab stays open, the markers are removed, and the workspace gets its unread dot", async () => {
    setStatus([{ id: "a-1", state: "working" }]);
    setRows("working");
    const r = runAsAgent(["--close", "--min-wait", "0", "--settle-timeout", "3"], { env: orcaEnv(stubOrca(TAB)), linger: 10 });
    expect(JSON.parse(r.out).marked).toEqual({ tab: true, workspace: true });
    expect(await until(() => closerLog().includes("markers removed"), 12000)).toBe(true);
    expect(closerLog()).toContain("gave up");
    expect(closerLog()).toContain("subagent a-1 working");
    const calls = orcaCalls();
    expect(calls).toContain(`worktree set --worktree id:${WT} --unread --json`);
    expect(calls).toContain(`terminal rename --terminal ${HANDLE} --json`);
    expect(calls).toContain(`worktree set --worktree id:${WT} --comment old comment --workspace-status todo --json`);
    expect(calls).not.toContain("terminal close");
  });
  test("--force closes when the turn ends even with a subagent running", async () => {
    setStatus([{ id: "a-1", state: "working" }]);
    const r = runAsAgent(["--close", "--min-wait", "0", "--force"], { env: orcaEnv(stubOrca(TAB)), linger: 8 });
    expect(r.code).toBe(0);
    expect(JSON.parse(r.out).marked).toEqual({ tab: false, workspace: false });
    expect(await until(() => orcaCalls().includes("terminal close"), 12000)).toBe(true);
    expect(closerLog()).toContain("--force");
  });
  test("a task notification arriving while it waits is not mistaken for a typed prompt", async () => {
    appendFileSync(transcript, `${launch("bgtask09")}\n`);
    const r = runAsAgent(["--close", "--min-wait", "0"], { env: orcaEnv(stubOrca(TAB)), linger: 10 });
    expect(JSON.parse(r.out).close_deferred).toBe(true);
    appendFileSync(transcript, `${notified("bgtask09")}\n`);
    expect(await until(() => orcaCalls().includes("terminal close"), 12000)).toBe(true);
    expect(closerLog()).not.toContain("new prompt");
  });
  test("works when the script is run by a relative path (the watcher changes directory before it starts)", async () => {
    writeFileSync(join(dir, "orca-closeout"), readFileSync(SCRIPT));
    chmodSync(join(dir, "orca-closeout"), 0o755);
    const r = runAsAgent(["--close", "--min-wait", "0"], { env: orcaEnv(stubOrca(TAB)), linger: 8, script: "./orca-closeout" });
    expect(r.code).toBe(0);
    expect(await until(() => orcaCalls().includes("terminal close"), 12000)).toBe(true);
    expect(closerLog()).toContain("watcher started");
  });
  test("stops without closing when the agent process is gone", async () => {
    const r = runAsAgent(["--close", "--min-wait", "1"], { env: orcaEnv(stubOrca(TAB)) });
    expect(r.code).toBe(0);
    expect(await until(() => closerLog().includes("process"), 12000)).toBe(true);
    expect(closerLog()).toContain("is gone");
    expect(orcaCalls()).not.toContain("terminal close");
  });
  test("re-checks at close time: a background command started meanwhile defers the close until it ends", async () => {
    const orca = stubOrca(TAB, 1);
    const bin = join(dir, "bin");
    mkdirSync(bin, { recursive: true });
    const fake = join(bin, "claude");
    writeFileSync(
      fake,
      `#!${BASH}
${BASH} -c ': shell-snapshots/snapshot-test; ${BASH} "$1" --close --min-wait 0' x '${SCRIPT}'
${BASH} -c ': shell-snapshots/snapshot-test; sleep 6; true' &
wait
sleep 6
`,
    );
    chmodSync(fake, 0o755);
    const t0 = Date.now();
    const proc = Bun.spawn([fake], { env: baseEnv(orcaEnv(orca)), cwd: dir, stdout: "ignore", stderr: "ignore" });
    expect(await until(() => orcaCalls().includes("terminal close"), 15000)).toBe(true);
    expect(Date.now() - t0).toBeGreaterThan(5500);
    expect(closerLog()).toContain("settled");
    proc.kill();
  });
});

describe("every subprocess call has a timeout; a timeout is never read as settled", () => {
  test("a hung `orca terminal show` refuses --close (exit 2) instead of hanging", () => {
    const orca = stubOrca(TAB);
    hang("terminal", "show");
    const t0 = Date.now();
    const r = runAsAgent(["--title", "t", "--close"], { env: { ...orcaEnv(orca), ...FAST } });
    expect(r.code).toBe(2);
    expect(Date.now() - t0).toBeLessThan(15000);
    expect(r.err).toContain("timed out");
    expect(orcaCalls()).not.toContain("terminal close");
  });
  test("a hung `orca worktree ps` in the watcher keeps the tab open until --settle-timeout", async () => {
    const orca = stubOrca(TAB);
    const r = runAsAgent(["--close", "--min-wait", "0", "--settle-timeout", "3"], { env: { ...orcaEnv(orca), ...FAST }, linger: 12 });
    expect(r.code).toBe(0);
    hang("worktree", "ps");
    expect(await until(() => closerLog().includes("gave up"), 15000)).toBe(true);
    expect(closerLog()).toContain("orca_rows unreadable");
    expect(orcaCalls()).not.toContain("terminal close");
  });
  test("a hung lsof reads as a running background command, not a finished one", () => {
    const out = join(dir, "claude-501", "proj", SID, "tasks");
    mkdirSync(out, { recursive: true });
    writeFileSync(join(out, "bgtask05.output"), "");
    appendFileSync(transcript, `${launch("bgtask05")}\n`);
    expect(JSON.parse(run([]).out).running[0].state).toBe("finished, result not yet delivered");
    const bin = join(dir, "hangbin");
    mkdirSync(bin, { recursive: true });
    writeFileSync(join(bin, "lsof"), "#!/bin/sh\nsleep 30\n");
    chmodSync(join(bin, "lsof"), 0o755);
    const r = run([], { ...FAST, PATH: `${bin}:${process.env.PATH ?? "/usr/bin:/bin"}` });
    expect(JSON.parse(r.out).running[0]).toMatchObject({ id: "bgtask05", state: "running" });
  });
  test("a hung ps makes the process check unreadable, so --close refuses", () => {
    const orca = stubOrca(TAB);
    const bin = join(dir, "hangbin");
    mkdirSync(bin, { recursive: true });
    writeFileSync(join(bin, "ps"), "#!/bin/sh\nsleep 30\n");
    chmodSync(join(bin, "ps"), 0o755);
    const env = { ...orcaEnv(orca), ...FAST, PATH: `${bin}:${process.env.PATH ?? "/usr/bin:/bin"}` };
    expect(JSON.parse(run([], env).out).checks.process).toBe("unreadable");
    const r = runAsAgent(["--close"], { env });
    expect(r.code).toBe(2);
    expect(r.err).toContain("process=unreadable");
  });
});

describe("the markers are removed on every way the watcher ends", () => {
  test("the agent process is gone", async () => {
    setStatus([{ id: "a-1", state: "working" }]);
    setRows("working");
    const r = runAsAgent(["--title", "t", "--close", "--min-wait", "1"], { env: orcaEnv(stubOrca(TAB)) });
    expect(JSON.parse(r.out).marked).toEqual({ tab: true, workspace: true });
    expect(await until(() => closerLog().includes("markers removed"), 12000)).toBe(true);
    expect(closerLog()).toContain("is gone");
    expect(orcaCalls()).toContain(`terminal rename --terminal ${HANDLE} --title t --json`);
    expect(orcaCalls()).toContain(`worktree set --worktree id:${WT} --comment old comment --workspace-status todo --json`);
    expect(orcaCalls()).not.toContain("terminal close");
  });
  test("the terminal is no longer this session's tab", async () => {
    setStatus([{ id: "a-1", state: "working" }]);
    setRows("working");
    runAsAgent(["--title", "t", "--close", "--min-wait", "0"], { env: orcaEnv(stubOrca(TAB)), linger: 10 });
    writeFileSync(join(dir, "show-tab"), "someone-elses-tab");
    expect(await until(() => closerLog().includes("markers removed"), 12000)).toBe(true);
    expect(closerLog()).toContain("no longer this session tab");
    expect(orcaCalls()).toContain(`terminal rename --terminal ${HANDLE} --title t --json`);
    expect(orcaCalls()).not.toContain("terminal close");
  });
  test("Orca never reports the turn idle: no close, and the markers still come off once the work settles", async () => {
    setStatus([{ id: "a-1", state: "working" }]);
    setRows("working");
    writeFileSync(join(dir, "wait-fails"), "");
    runAsAgent(["--title", "t", "--close", "--min-wait", "0"], { env: orcaEnv(stubOrca(TAB)), linger: 10 });
    expect(await until(() => closerLog().includes("did not become idle"), 12000)).toBe(true);
    setStatus([{ id: "a-1", state: "done" }]);
    setRows("done");
    expect(await until(() => closerLog().includes("markers removed"), 12000)).toBe(true);
    expect(orcaCalls()).not.toContain("terminal close");
  });
});

describe("restoring what was there before", () => {
  test("a workspace with neither status nor comment is not marked (neither could be cleared again)", () => {
    setStatus([{ id: "a-1", state: "working" }]);
    setRows("working", { comment: "", status: "" });
    const j = JSON.parse(runAsAgent(["--title", "t"], { env: orcaEnv(stubOrca(TAB)), linger: 2 }).out);
    expect(j.marked).toEqual({ tab: true, workspace: false });
    expect(orcaCalls()).not.toContain("worktree set");
  });
  test("a workspace with a comment but no status gets only the comment prefix", () => {
    setStatus([{ id: "a-1", state: "working" }]);
    setRows("working", { comment: "notes", status: "" });
    runAsAgent(["--title", "t"], { env: orcaEnv(stubOrca(TAB)), linger: 2 });
    expect(orcaCalls()).toContain(`worktree set --worktree id:${WT} --comment Running: 1 subagent | notes --json`);
    expect(orcaCalls()).not.toContain("--workspace-status");
  });
  test("a second run while the first one's markers are on restores the true originals, never nesting", async () => {
    // What the first run left: its state file, and Orca showing its markers.
    writeFileSync(
      join(dir, `orca-closeout-${HANDLE}.state.json`),
      JSON.stringify({ tab_marked: true, tab_label: "first", worktree: { id: WT, comment: "old comment", status: "todo" } }),
    );
    setStatus([{ id: "a-1", state: "working" }]);
    setRows("working", { comment: "Running: 1 subagent | old comment", status: "in-progress" });
    runAsAgent(["--title", "second"], { env: orcaEnv(stubOrca(TAB)), linger: 10 });
    const calls = orcaCalls();
    expect(calls).toContain(`worktree set --worktree id:${WT} --workspace-status in-progress --comment Running: 1 subagent | old comment --json`);
    expect(calls).not.toContain("Running: 1 subagent | Running:");
    setStatus([{ id: "a-1", state: "done" }]);
    setRows("done", { comment: "Running: 1 subagent | old comment", status: "in-progress" });
    expect(await until(() => closerLog().includes("markers removed"), 12000)).toBe(true);
    expect(orcaCalls()).toContain(`worktree set --worktree id:${WT} --comment old comment --workspace-status todo --json`);
  });
  test("a leftover Running prefix with no state file is stripped, not nested", () => {
    setStatus([{ id: "a-1", state: "working" }]);
    setRows("working", { comment: "Running: 2 subagents | Running: 1 subagent | old comment", status: "todo" });
    runAsAgent(["--title", "t"], { env: orcaEnv(stubOrca(TAB)), linger: 2 });
    expect(orcaCalls()).toContain(`--comment Running: 1 subagent | old comment --json`);
    expect(orcaCalls()).not.toContain("Running: 1 subagent | Running:");
  });
});

describe("transcript reading", () => {
  test("the agent start time is read without the locale: a launch from before it is ignored even under fr_FR", () => {
    appendFileSync(transcript, `${JSON.stringify({ type: "user", timestamp: "2000-01-01T00:00:00Z", toolUseResult: { backgroundTaskId: "old01" } })}\n`);
    expect(JSON.parse(run([]).out).running_count).toBe(1); // no agent, so no start time to compare with
    const j = JSON.parse(runAsAgent([], { env: { LC_ALL: "fr_FR.UTF-8", LANG: "fr_FR.UTF-8", LC_TIME: "fr_FR.UTF-8" } }).out);
    expect(j.checks.process).toBe("ok");
    expect(j.running_count).toBe(0);
  });
  test("a typed prompt with an image (list content) cancels the close", async () => {
    const r = runAsAgent(["--close", "--min-wait", "0"], { env: orcaEnv(stubOrca(TAB, 2)), linger: 6 });
    expect(r.code).toBe(0);
    const content = [
      { type: "text", text: "what is this?" },
      { type: "image", source: { type: "base64", media_type: "image/png", data: "iVBORw0KGgo=" } },
    ];
    appendFileSync(transcript, `${JSON.stringify({ type: "user", message: { role: "user", content } })}\n`);
    expect(await until(() => closerLog().includes("new prompt"))).toBe(true);
    expect(orcaCalls()).not.toContain("terminal close");
  }, 20000);
  test("a tool result and a list-form task notification are not prompts", async () => {
    appendFileSync(transcript, `${launch("bgtask10")}\n`);
    const r = runAsAgent(["--close", "--min-wait", "0"], { env: orcaEnv(stubOrca(TAB)), linger: 10 });
    expect(JSON.parse(r.out).close_deferred).toBe(true);
    appendFileSync(
      transcript,
      `${JSON.stringify({ type: "user", message: { role: "user", content: [{ type: "tool_result", tool_use_id: "tu9", content: "ok" }] } })}\n` +
        `${JSON.stringify({ type: "user", message: { role: "user", content: [{ type: "text", text: "<task-notification>\n<task-id>bgtask10</task-id>\n</task-notification>" }] } })}\n`,
    );
    expect(await until(() => orcaCalls().includes("terminal close"), 12000)).toBe(true);
    expect(closerLog()).not.toContain("new prompt");
  });
});
