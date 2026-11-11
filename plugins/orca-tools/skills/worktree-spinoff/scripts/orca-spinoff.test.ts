// Tests for orca-spinoff create: the real script against a throwaway git repo and a stub Orca CLI. No network, no real
// Orca. Covers the launch surface: a terminal (the default) and an Orca chat (--surface chat, Orca 1.4.255+).
import { afterEach, beforeEach, describe, expect, setDefaultTimeout, test } from "bun:test";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

setDefaultTimeout(30_000);

const SCRIPT = join(import.meta.dir, "orca-spinoff");
// Stock macOS bash 3.2 when present, so the portability claim is what is tested.
const BASH = existsSync("/bin/bash") ? "/bin/bash" : "bash";
const REPO_ID = "repo-1";
const TITLE = "Spin-off title for the test";

let dir: string;
let repo: string;
let orcaLog: string;

/**
 * A stub Orca CLI. `create.json` is what `worktree create` returns; `wc-help` is its --help text (with or without
 * --surface); `terminals.json` is `terminal list`; `read.json` is `terminal read`.
 */
function stubOrca(opts: { launch?: unknown; legacyHandle?: string; surfaceFlag?: boolean; terminals?: unknown[]; tail?: string } = {}) {
  const wt = join(dir, "wt", "my-task");
  const result: Record<string, unknown> = {
    worktree: { id: `${REPO_ID}::${wt}`, path: wt, branch: "refs/heads/me/my-task" },
  };
  if (opts.launch) result.launch = opts.launch;
  if (opts.legacyHandle) result.agentTerminalHandle = opts.legacyHandle;
  writeFileSync(join(dir, "create.json"), JSON.stringify({ ok: true, result }));
  writeFileSync(
    join(dir, "wc-help"),
    `Usage: orca worktree create --name <name> [--agent <id>] [--prompt <text>]${opts.surfaceFlag === false ? "" : " [--surface chat|terminal]"} [--json]\n`,
  );
  writeFileSync(join(dir, "terminals.json"), JSON.stringify({ ok: true, result: { terminals: opts.terminals ?? [] } }));
  writeFileSync(join(dir, "read.json"), JSON.stringify({ ok: true, result: { terminal: { tail: [opts.tail ?? ""] } } }));
  writeFileSync(
    join(dir, "repos.json"),
    JSON.stringify({ ok: true, result: { repos: [{ id: REPO_ID, path: repo, gitRemoteIdentity: { remoteUrl: "https://github.com/acme/widget.git", remoteName: "origin" } }] } }),
  );
  const p = join(dir, "orca");
  writeFileSync(
    p,
    `#!/bin/sh
echo "$*" >> "${orcaLog}"
case "$1 $2 $3" in
  "--help  ") echo "Commands: worktree create" ;;
  "worktree create --help") cat "${dir}/wc-help" ;;
  "repo list --json") cat "${dir}/repos.json" ;;
  "worktree list "*) printf '{"ok":true,"result":{"worktrees":[],"truncated":false}}\\n' ;;
  "worktree create "*) cat "${dir}/create.json" ;;
  "terminal list "*) cat "${dir}/terminals.json" ;;
  "terminal read "*) cat "${dir}/read.json" ;;
  *) printf '{"ok":true,"result":{}}\\n' ;;
esac
`,
  );
  chmodSync(p, 0o755);
  return p;
}

function run(args: string[], orca: string) {
  const r = Bun.spawnSync([BASH, SCRIPT, "create", "--name", "my-task", "--title", TITLE, ...args], {
    cwd: repo,
    env: { PATH: process.env.PATH ?? "/usr/bin:/bin", HOME: dir, TMPDIR: dir, ORCA_CLI: orca },
  });
  return { code: r.exitCode, out: r.stdout.toString(), err: r.stderr.toString() };
}
const calls = () => (existsSync(orcaLog) ? readFileSync(orcaLog, "utf8") : "");
/** The logged `worktree create` call: from its start to the next logged call (the prompt spans several lines). */
const createCall = () => {
  const c = calls();
  const i = c.indexOf("worktree create --repo");
  if (i < 0) return "";
  const j = c.indexOf("\nterminal ", i);
  return c.slice(i, j < 0 ? undefined : j);
};

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "orca-spinoff-"));
  repo = join(dir, "repo");
  mkdirSync(repo);
  const git = (...a: string[]) => Bun.spawnSync(["git", "-C", repo, ...a], { env: { ...process.env, HOME: dir } });
  git("init", "-q", "-b", "main");
  git("remote", "add", "origin", "https://github.com/acme/widget.git");
  orcaLog = join(dir, "orca.log");
});
afterEach(() => rmSync(dir, { recursive: true, force: true }));

describe("terminal surface (default)", () => {
  test("passes --surface terminal explicitly, so the user's Chat setting cannot turn it into a chat", () => {
    const orca = stubOrca({
      launch: { outcome: { kind: "terminal", handle: "term_a" }, prompt: { outcome: "handed-to-terminal" } },
      terminals: [{ handle: "term_a", title: "claude" }],
      tail: TITLE,
    });
    const r = run([], orca);
    expect(r.code).toBe(0);
    expect(createCall()).toContain("--surface terminal");
    const j = JSON.parse(r.out);
    expect(j).toMatchObject({ surface: "terminal", terminal: "term_a", chat_session: "", terminals: 1, prompt_seen: true });
    expect(r.err).not.toContain("warning");
  });
  test("an Orca without --surface: the flag is left out, and the older agentTerminalHandle is read", () => {
    const orca = stubOrca({ surfaceFlag: false, legacyHandle: "term_old", terminals: [{ handle: "term_old", title: "claude" }], tail: TITLE });
    const r = run([], orca);
    expect(r.code).toBe(0);
    expect(createCall()).not.toContain("--surface");
    expect(JSON.parse(r.out)).toMatchObject({ surface: "terminal", terminal: "term_old", prompt_seen: true });
  });
});

describe("chat surface (--surface chat)", () => {
  const chat = { outcome: { kind: "structured", sessionId: "chat-sess-1", handle: "agent_h1", tabId: "tab-9" }, prompt: { outcome: "journaled" } };
  test("reports the chat session, no terminal, and the prompt as delivered, without waiting for a terminal", () => {
    const orca = stubOrca({ launch: chat });
    const t0 = Date.now();
    const r = run(["--surface", "chat"], orca);
    expect(r.code).toBe(0);
    expect(Date.now() - t0).toBeLessThan(15_000); // the terminal read loop would take 90 s
    expect(createCall()).toContain("--surface chat");
    const j = JSON.parse(r.out);
    expect(j).toMatchObject({ surface: "chat", terminal: "", chat_session: "chat-sess-1", agent_handle: "agent_h1", prompt_outcome: "journaled", prompt_seen: true });
    expect(r.err).not.toContain("terminals in");
    expect(r.err).not.toContain("did not appear");
    expect(calls()).not.toContain("terminal read");
  });
  test("a chat whose prompt was not delivered is reported, not hidden", () => {
    const orca = stubOrca({ launch: { ...chat, prompt: { outcome: "not-delivered" } } });
    const r = run(["--surface", "chat"], orca);
    expect(r.code).toBe(0);
    expect(JSON.parse(r.out).prompt_seen).toBe(false);
    expect(r.err).toContain("not-delivered");
  });
  test("a chat started from the user's setting (no --surface chat) is still recognised from the result", () => {
    const orca = stubOrca({ launch: chat });
    const r = run([], orca);
    expect(r.code).toBe(0);
    expect(JSON.parse(r.out)).toMatchObject({ surface: "chat", chat_session: "chat-sess-1" });
    expect(r.err).toContain("asked for a terminal, Orca started a chat");
  });
  test("Orca falling back to a terminal is warned with its reason", () => {
    const orca = stubOrca({
      launch: { outcome: { kind: "terminal", handle: "term_b" }, prompt: { outcome: "handed-to-terminal" }, receipt: { detail: "agent has no chat support" } },
      terminals: [{ handle: "term_b", title: "claude" }],
      tail: TITLE,
    });
    const r = run(["--surface", "chat"], orca);
    expect(r.code).toBe(0);
    expect(r.err).toContain("asked for a chat, Orca started a terminal: agent has no chat support");
    expect(JSON.parse(r.out)).toMatchObject({ surface: "terminal", terminal: "term_b" });
  });
  test("an Orca without --surface refuses a chat before any change", () => {
    const r = run(["--surface", "chat"], stubOrca({ surfaceFlag: false }));
    expect(r.code).toBe(2);
    expect(createCall()).toBe("");
  });
  test("a bad --surface value is refused", () => {
    const r = run(["--surface", "window"], stubOrca());
    expect(r.code).toBe(2);
    expect(r.err).toContain("--surface must be terminal or chat");
  });
});
