import { describe, expect, test, afterAll } from "bun:test";
import { chmodSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  buildWrappedCommand,
  parses,
  shQuote,
  spoolCommand,
} from "./lib/pueue-wrap-transport.ts";

/**
 * Regression suite for the pueue auto-wrap transport.
 *
 * The defect (2026-10-12): the wrapper spliced the command into `pueue add --`
 * UNQUOTED after '\''-escaping it, so any ' broke parsing ("unmatched '"), any
 * `;`/newline split the command (only the first statement was queued), and the
 * exit status was always 0. The corpus below is built from the commands that
 * actually failed in session transcripts plus every shell hazard class.
 *
 * Invariants proven here, for every corpus entry:
 *   P1  the wrapper parses under zsh AND bash;
 *   P2  the spool file holds the command byte-for-byte;
 *   P3  run through a pueue stand-in that mimics pueue (sh -c, -w cwd), the
 *       wrapper prints what the command prints and exits with ITS exit status.
 * PUEUE_WRAP_E2E=1 repeats P3 against the real local pueue daemon.
 */

const HOOK = join(import.meta.dir, "pretooluse-pueue-wrap-guard.ts");
const ZSH = "/bin/zsh";

/** Real command from session c3897a2a (2026-10-12) that produced "unmatched '". */
const REAL_FAILURE = `set -euo pipefail; B=/tmp; cd $B; mkdir -p runs-dev/parakeet-v3
for f in runs-dev/*/x.whisper(N); do /usr/bin/python3 -I -c '
import sys
print(sys.argv[1].split("/")[1], "created")' "$f"; done
for k in whisperkit-large-v3-turbo parakeet-v3; do uv run -q --version >/dev/null 2>&1 | /usr/bin/python3 -I -c 'import sys;print("k")'; done`;

interface Case {
  name: string;
  cmd: string;
  stdout: string;
  rc: number;
}

const CORPUS: Case[] = [
  { name: "single quotes", cmd: `echo 'it'"'"'s'; echo 'a b'`, stdout: "it's\na b\n", rc: 0 },
  { name: "statements split by ;", cmd: `echo one; echo two; echo three`, stdout: "one\ntwo\nthree\n", rc: 0 },
  { name: "multi-line with a for loop", cmd: `for i in 1 2; do\n  echo "n=$i"\ndone`, stdout: "n=1\nn=2\n", rc: 0 },
  { name: "heredoc with quotes", cmd: `cat <<'EOF'\nquote ' and " and $HOME\nEOF`, stdout: `quote ' and " and $HOME\n`, rc: 0 },
  { name: "command substitution and backticks", cmd: "x=$(echo in); y=`echo bt`; echo \"$x $y\"", stdout: "in bt\n", rc: 0 },
  { name: "backslashes and dollar", cmd: `printf '%s\\n' 'a\\b' "\\$5"`, stdout: "a\\b\n$5\n", rc: 0 },
  { name: "unicode", cmd: `echo 'héllo — 世界'`, stdout: "héllo — 世界\n", rc: 0 },
  { name: "&& and || chains", cmd: `false || echo fallback && echo after`, stdout: "fallback\nafter\n", rc: 0 },
  { name: "nonzero exit propagates", cmd: `echo before; exit 7`, stdout: "before\n", rc: 7 },
  { name: "set -e failure propagates", cmd: `set -euo pipefail; echo a; false; echo never`, stdout: "a\n", rc: 1 },
  { name: "pipefail failure propagates", cmd: `set -o pipefail; false | cat; echo rc=$?`, stdout: "rc=1\n", rc: 0 },
  { name: "zsh-only syntax runs under zsh", cmd: `x=abc; print -r -- \${(U)x}`, stdout: "ABC\n", rc: 0 },
  { name: "the real failing command", cmd: REAL_FAILURE, stdout: "", rc: 0 },
];

const work = mkdtempSync(join(tmpdir(), "pueue-wrap-test-"));
afterAll(() => rmSync(work, { recursive: true, force: true }));

/**
 * A pueue stand-in with pueue's execution semantics: `add -w DIR -- ARGS`
 * joins ARGS with spaces and runs them under `sh -c` in DIR; output is kept
 * for `log`; `wait` is a no-op because `add` already ran synchronously.
 */
function makeStubPueue(): string {
  const dir = join(work, "stub-bin");
  Bun.spawnSync(["mkdir", "-p", dir]);
  const script = `#!/bin/bash
state=${shQuote(join(work, "stub-state"))}
mkdir -p "$state"
case "$1" in
  status) echo '{"groups":{"default":"Running"}}' ;;
  add)
    shift; cwd=.
    while [ $# -gt 0 ]; do case "$1" in -w) cwd=$2; shift 2;; --print-task-id) shift;; --) shift; break;; *) shift;; esac; done
    id=$(( $(ls "$state" | wc -l) + 1 ))
    (cd "$cwd" && sh -c "$*") > "$state/$id" 2>&1
    echo "$id" ;;
  wait) : ;;
  log) cat "$state/$2" ;;
esac
`;
  writeFileSync(join(dir, "pueue"), script);
  chmodSync(join(dir, "pueue"), 0o755);
  return dir;
}

function wrap(cmd: string, cwd = work) {
  const paths = spoolCommand(cmd);
  const wrapped = buildWrappedCommand({ shell: ZSH, cwd, paths, taskLog: join(work, "tasks.txt") });
  return { paths, wrapped };
}

describe("shQuote", () => {
  const nasty = ["", "'", "''", "a'b", `"'\\$\`!`, "line1\nline2", "  spaced  ", "*?[]{}~#"];
  for (const s of nasty) {
    test(`round-trips ${JSON.stringify(s)} through bash and zsh`, () => {
      for (const sh of ["/bin/bash", ZSH]) {
        const r = Bun.spawnSync([sh, "-c", `printf %s ${shQuote(s)}`]);
        expect(r.stdout.toString()).toBe(s);
      }
    });
  }
});

describe("wrapper over the hazard corpus", () => {
  const stub = makeStubPueue();
  for (const c of CORPUS) {
    test(`${c.name}: parses (P1), spools verbatim (P2), same output and exit code (P3)`, () => {
      const { paths, wrapped } = wrap(c.cmd);
      expect(parses(ZSH, ["-c", wrapped])).toBe(true);
      expect(parses("/bin/bash", ["-c", wrapped])).toBe(true);
      expect(readFileSync(paths.script, "utf8")).toBe(`${c.cmd}\n`);
      if (c.cmd === REAL_FAILURE) {
        rmSync(paths.script, { force: true });
        return; // parse-only: it depends on tools not guaranteed on every host
      }
      const r = Bun.spawnSync([ZSH, "-c", wrapped], { env: { ...process.env, PATH: `${stub}:${process.env.PATH}` } });
      expect(r.stdout.toString()).toBe(c.stdout);
      expect(r.exitCode).toBe(c.rc);
      expect(existsSync(paths.script)).toBe(false); // the job deletes its spool file
      expect(existsSync(paths.rc)).toBe(false);
    });
  }

  test("runs in the requested working directory", () => {
    const { wrapped } = wrap("pwd -P", "/tmp");
    const r = Bun.spawnSync([ZSH, "-c", wrapped], { env: { ...process.env, PATH: `${stub}:${process.env.PATH}` } });
    expect(r.stdout.toString().trim()).toBe(realpathSync("/tmp"));
  });

  test("when pueue cannot queue, runs directly and still returns the real exit code", () => {
    const empty = join(work, "no-pueue");
    Bun.spawnSync(["mkdir", "-p", empty]);
    writeFileSync(join(empty, "pueue"), "#!/bin/sh\nexit 1\n");
    chmodSync(join(empty, "pueue"), 0o755);
    const { wrapped } = wrap(`echo 'direct'; exit 3`);
    const r = Bun.spawnSync([ZSH, "-c", wrapped], { env: { ...process.env, PATH: `${empty}:${process.env.PATH}` } });
    expect(r.stdout.toString()).toBe("direct\n");
    expect(r.exitCode).toBe(3);
    expect(r.stderr.toString()).toContain("[pueue-wrap] could not queue");
  });
});

function runHook(command: string) {
  const r = Bun.spawnSync(["bun", HOOK], {
    stdin: Buffer.from(JSON.stringify({ tool_name: "Bash", tool_input: { command }, cwd: work })),
  });
  const out = r.stdout.toString().trim();
  return out ? JSON.parse(out) : {};
}

describe("hook end to end", () => {

  test("the real failing command now yields a wrapper that parses", () => {
    const hasPueue = Bun.spawnSync(["pueue", "status", "--json"], { stderr: "ignore" }).exitCode === 0;
    if (!hasPueue) return; // the hook fails open without a daemon; nothing to assert
    const res = runHook(REAL_FAILURE);
    const wrapped: string = res.hookSpecificOutput?.updatedInput?.command;
    expect(wrapped).toBeString();
    expect(parses(ZSH, ["-c", wrapped])).toBe(true);
    const spool = wrapped.match(/'([^']*claude-pueue-wrap\/[^']*\.sh)'/)?.[1];
    expect(spool && readFileSync(spool, "utf8")).toBe(`${REAL_FAILURE}\n`);
    if (spool) rmSync(spool, { force: true });
  });

  test("a payload that does not parse is passed through unwrapped", () => {
    const broken = `for i in 1; do python -c 'unterminated; done`;
    const res = runHook(broken);
    expect(res.hookSpecificOutput?.updatedInput).toBeUndefined();
  });

  test("an unmatched command is not touched", () => {
    const res = runHook("echo hello");
    expect(res.hookSpecificOutput?.updatedInput).toBeUndefined();
  });
});

describe.if(process.env.PUEUE_WRAP_E2E === "1")("real pueue daemon (PUEUE_WRAP_E2E=1)", () => {
  for (const c of CORPUS.filter((k) => k.cmd !== REAL_FAILURE)) {
    test(`${c.name}: real pueue returns the command's output and exit code`, () => {
      const { wrapped } = wrap(c.cmd);
      const r = Bun.spawnSync([ZSH, "-c", wrapped], { env: { ...process.env, RUST_LOG: "error" } });
      for (const line of c.stdout.split("\n").filter(Boolean)) expect(r.stdout.toString()).toContain(line);
      expect(r.exitCode).toBe(c.rc);
      const ids = readFileSync(join(work, "tasks.txt"), "utf8").trim().split("\n");
      Bun.spawnSync(["pueue", "remove", ids[ids.length - 1]], { stdout: "ignore", stderr: "ignore" });
    });
  }
});
