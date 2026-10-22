/**
 * Tests for pretooluse-pueue-wrap-guard.ts and the shared wrapper in lib/pueue-safe-wrap.ts.
 *
 * Run with: bun test plugins/itp-hooks/hooks/pretooluse-pueue-wrap-guard.test.ts
 *
 * The false positives come from a 2026-10-17 session on a Linux host with zsh as the login shell:
 * commands that only WROTE a loop into a file, or ran it inside `bash -c '…'`, were rewritten into
 * `TASK_ID=$(pueue add -- …` with the command pasted unquoted, and zsh rejected the result
 * ("unmatched '", "parse error near `TASK_ID=$(pueue add'"). The end-to-end block runs the generated
 * wrapper against a PRIVATE pueue daemon (own config and socket) through a PATH shim, so it never
 * touches the operator's queue, and skips when pueue is not installed. The hazard corpus (quoting,
 * multi-statement, unicode, backslashes, set -e/pipefail, zsh-only syntax) runs against a pueue
 * stand-in by default; `PUEUE_WRAP_E2E=1` also runs it through that private daemon.
 */

import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { buildWrappedCommand, commandLineForPatternMatching, shouldWrap } from "./pretooluse-pueue-wrap-guard.ts";
import { buildSafeWrapper, cargoCommandNeedsPueueIsolation } from "./pretooluse-cargo-tty-guard.ts";
import { buildPueueWrapper, parsesUnder, shellSingleQuote, taskShell, wrapIsSafe } from "./lib/pueue-safe-wrap.ts";

describe("shouldWrap: what is long-running", () => {
  test.each([
    ['for f in a b; do python run.py "$f"; done'],
    ["for s in x y; do uv run scripts/sweep.py --sym $s; done"],
    ["./populate_cache.sh --all"],
    ["python train.py --phase 2"],
    ["ls # PUEUE-WRAP"],
    // Multi-line loops: the body is judged by the program each command runs.
    ['while read sym; do\n  ./populate_cache.sh "$sym"\ndone < symbols.txt'],
    ['for f in a b\ndo\n  uv run x.py "$f"\ndone'],
    // An option before a SCRIPT is still a script run, not a snippet.
    ['for f in a b; do python3 -u run.py "$f"; done'],
  ])("wraps %s", (command) => {
    expect(shouldWrap(command)).toBe(true);
  });

  test.each([
    // A loop being WRITTEN to a file is data, not a job.
    ["cat > /tmp/run.sh <<'EOF'\nfor f in a b; do python run.py \"$f\"; done\nEOF"],
    // Inside quotes the loop belongs to another shell; the outer command is `bash -c ''`.
    ["bash -c 'for f in a b; do python run.py $f; done'"],
    // An inline snippet per item is not a batch job.
    ["for f in *.json; do python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \"$f\"; done"],
    ["for f in a b; do uv run --with numpy python -c 'print(1)'; done"],
    // Short options before -c are still an inline snippet (2026-10-18: `python3 -I -c` was queued).
    ['for d in a b; do [ -f "x/$d" ] && python3 -I -c "import csv,sys; print(1)" "x/$d"; done'],
    ["for f in a b; do python3 -u -B -c 'print(1)' \"$f\"; done"],
    // Read-only loops.
    ["for f in *.py; do grep -l cache \"$f\"; done"],
    ["grep -rn 'for x in y; do python' ."],
    ["git commit -m 'populate_cache: loop over symbols'"],
    ["for f in a b; do python run.py; done # PUEUE-SKIP"],
    ["pueue add -- python populate_cache.py"],
  ])("does not wrap %s", (command) => {
    expect(shouldWrap(command)).toBe(false);
  });

  test("the command line used for matching drops data heredocs and quoted spans", () => {
    const visible = commandLineForPatternMatching("cat > f <<'EOF'\npython populate_cache.py\nEOF\necho 'populate_cache'");
    expect(visible).not.toContain("populate");
  });

  test("a heredoc fed to a shell is still visible: it IS a script", () => {
    expect(shouldWrap("bash <<'EOF'\n./populate_cache.sh\nEOF")).toBe(true);
  });
});

describe("the wrapper never breaks the command's quoting", () => {
  const tricky = [
    'for f in a b; do python run.py "$f"; done',
    "for f in a b; do echo \"it's $f\"; python x.py 'single quoted'; done",
    "python a.py && python b.py | tee /tmp/log # PUEUE-WRAP trailing comment",
    "python - <<'EOF'\nprint(\"heredoc inside the task\")\nEOF",
    "printf '%s\\n' \"$(date)\" `whoami`; python x.py",
  ];
  for (const command of tricky) {
    test(`parses under bash: ${command.slice(0, 50).replace(/\n/g, "⏎")}`, () => {
      const wrapped = buildWrappedCommand(command, "/tmp/dir with 'quote'");
      expect(parsesUnder("bash", wrapped)).toBe(true);
      expect(wrapIsSafe(command, wrapped).ok).toBe(true);
    });
    // Not vacuous: parsesUnder() answers true for a shell that is not installed.
    test.if(Bun.which("zsh") !== null)(`parses under zsh: ${command.slice(0, 50).replace(/\n/g, "⏎")}`, () => {
      expect(parsesUnder("zsh", buildWrappedCommand(command, "/tmp/dir with 'quote'"))).toBe(true);
    });
  }

  test("the command reaches pueue as ONE single-quoted argument", () => {
    const command = "for f in a b; do echo \"it's $f\"; done";
    const task = `${taskShell()} -c ${shellSingleQuote(command)}`;
    expect(buildWrappedCommand(command, "/w")).toContain(`-- ${shellSingleQuote(task)} 2>&1`);
  });

  test("an original that does not parse is never wrapped", () => {
    const broken = "for f in a b; do python x.py";
    expect(wrapIsSafe(broken, buildWrappedCommand(broken, "/w")).ok).toBe(false);
  });

  test("the task runs under the user's shell, not pueue's sh (dash on Linux)", () => {
    // `dash -n` accepts `${arr[@]}`, which dash then fails to run; under bash it runs.
    const bashism = 'arr=(a b); for f in "${arr[@]}"; do python x.py "$f"; done';
    const wrapped = buildPueueWrapper({ command: bashism, cwd: "/w", onQueueFailure: "fail", label: "t", shell: "bash" });
    expect(wrapped).toContain(`-- ${shellSingleQuote(`bash -c ${shellSingleQuote(bashism)}`)} 2>&1`);
    expect(wrapIsSafe(bashism, wrapped, ["bash"], "bash").ok).toBe(true);
  });

  test("a check that runs out of budget means no rewrite", () => {
    const command = "for f in a b; do python x.py; done";
    expect(wrapIsSafe(command, buildWrappedCommand(command, "/w"), ["bash"], "bash", 0).ok).toBe(false);
  });
});

describe("cargo TTY isolation (now applied by this hook)", () => {
  test.each([
    ["cargo bench --bench x &", true],
    ["cargo test -p core --lib &", true],
    ["cargo test -p pkg # CARGO-TTY-WRAP", true],
    ["cargo test -p core", false],
    ["cargo build --release", false],
    ["cargo bench & # CARGO-TTY-SKIP", false],
    ["nohup cargo bench &", false],
    ["cargo bench </dev/null &", false],
    ["git commit -m 'cargo bench &'", false],
  ] as const)("%s → %s", (command, expected) => {
    expect(cargoCommandNeedsPueueIsolation(command)).toBe(expected);
  });

  test("a chained cargo command stays inside the pueue task", () => {
    const wrapped = buildSafeWrapper("cargo test && cargo bench --bench 'x y' &", "/w");
    const task = `${taskShell()} -c ${shellSingleQuote("cargo test && cargo bench --bench 'x y'")}`;
    expect(wrapped).toContain(`-- ${shellSingleQuote(task)} 2>&1`);
    expect(parsesUnder("bash", wrapped)).toBe(true);
    if (Bun.which("zsh") !== null) expect(parsesUnder("zsh", wrapped)).toBe(true);
  });
});

// ── Hazard corpus (ported from the retired spool-file branch, cc-skills#38) ─────────────────────
//
// Every shell hazard class that broke an earlier wrapper, plus the real command that produced
// "unmatched '" on 2026-10-12. For each entry the wrapper must (1) parse under bash and zsh, (2)
// hand the task shell the command byte-for-byte, and (3) run through a pueue stand-in, print what
// the command prints and end with the command's own exit status. Each entry runs under every task
// shell in `shells` that is installed.

const ZSH_INSTALLED = Bun.which("zsh") !== null;

/** Real command (2026-10-12) that produced "unmatched '". `(N)` is zsh-only. */
const REAL_FAILURE = `set -euo pipefail; B=/tmp; cd $B; mkdir -p runs-dev/parakeet-v3
for f in runs-dev/*/x.whisper(N); do /usr/bin/python3 -I -c '
import sys
print(sys.argv[1].split("/")[1], "created")' "$f"; done
for k in whisperkit-large-v3-turbo parakeet-v3; do uv run -q --version >/dev/null 2>&1 | /usr/bin/python3 -I -c 'import sys;print("k")'; done`;

interface HazardCase {
  readonly name: string;
  readonly cmd: string;
  readonly stdout: string;
  readonly rc: number;
  /** Task shells the case is valid under. */
  readonly shells: readonly ("bash" | "zsh")[];
}

const BOTH = ["bash", "zsh"] as const;
const HAZARD_CORPUS: readonly HazardCase[] = [
  { name: "single quotes", cmd: `echo 'it'"'"'s'; echo 'a b'`, stdout: "it's\na b\n", rc: 0, shells: BOTH },
  { name: "statements split by ;", cmd: "echo one; echo two; echo three", stdout: "one\ntwo\nthree\n", rc: 0, shells: BOTH },
  { name: "multi-line for loop", cmd: 'for i in 1 2; do\n  echo "n=$i"\ndone', stdout: "n=1\nn=2\n", rc: 0, shells: BOTH },
  { name: "statements split by newline", cmd: "echo one\necho two\n\necho three", stdout: "one\ntwo\nthree\n", rc: 0, shells: BOTH },
  { name: "heredoc with quotes", cmd: `cat <<'EOF'\nquote ' and " and $HOME\nEOF`, stdout: `quote ' and " and $HOME\n`, rc: 0, shells: BOTH },
  { name: "command substitution and backticks", cmd: 'x=$(echo in); y=`echo bt`; echo "$x $y"', stdout: "in bt\n", rc: 0, shells: BOTH },
  { name: "backslashes and dollar", cmd: `printf '%s\\n' 'a\\b' "\\$5"`, stdout: "a\\b\n$5\n", rc: 0, shells: BOTH },
  { name: "unicode", cmd: "echo 'héllo — 世界'", stdout: "héllo — 世界\n", rc: 0, shells: BOTH },
  { name: "&& and || chains", cmd: "false || echo fallback && echo after", stdout: "fallback\nafter\n", rc: 0, shells: BOTH },
  { name: "trailing comment", cmd: "echo kept # a trailing comment with ' and ;", stdout: "kept\n", rc: 0, shells: BOTH },
  { name: "nonzero exit propagates", cmd: "echo before; exit 7", stdout: "before\n", rc: 7, shells: BOTH },
  { name: "set -e failure propagates", cmd: "set -euo pipefail; echo a; false; echo never", stdout: "a\n", rc: 1, shells: BOTH },
  { name: "pipefail is honoured", cmd: "set -o pipefail; false | cat; echo rc=$?", stdout: "rc=1\n", rc: 0, shells: BOTH },
  // biome-ignore lint/suspicious/noTemplateCurlyInString: zsh parameter expansion, not a JS template
  { name: "zsh-only syntax runs under zsh", cmd: "x=abc; print -r -- ${(U)x}", stdout: "ABC\n", rc: 0, shells: ["zsh"] },
];

/** [case, task shell] pairs whose shell is installed. */
const HAZARD_RUNS = HAZARD_CORPUS.flatMap((c) =>
  c.shells.filter((s) => s === "bash" || ZSH_INSTALLED).map((shell) => ({ c, shell })),
);

let hazardRoot = "";
let stubPath = "";
let failingPueuePath = "";
let recorderShell = "";

/**
 * A pueue stand-in with pueue 4's execution semantics: `add -w DIR -- ARGS` joins ARGS with spaces
 * and runs them under `sh -c` in DIR, and `status --json` reports the newest task's result the way
 * pueue 4.0.4 does. It also records the exact argument string it was handed (`<id>.argv`).
 */
function writeStubPueue(dir: string, state: string): void {
  mkdirSync(dir, { recursive: true });
  const script = `#!/bin/bash
state=${shellSingleQuote(state)}
mkdir -p "$state"
case "$1" in
  status)
    # Only the newest task: the wrapper asks right after its own task finished.
    printf '{"groups":{"default":{"status":"Running"}},"tasks":{%s}}\\n' "$(cat "$state/last.json" 2>/dev/null)" ;;
  add)
    shift; cwd=.
    while [ $# -gt 0 ]; do case "$1" in -w) cwd=$2; shift 2;; --print-task-id) shift;; --) shift; break;; *) shift;; esac; done
    id=$(( $(cat "$state/last-id" 2>/dev/null || echo 0) + 1 )); echo "$id" > "$state/last-id"
    printf '%s' "$*" > "$state/$id.argv"
    rc=0; (cd "$cwd" && sh -c "$*") > "$state/$id.log" 2>&1 || rc=$?
    if [ "$rc" = 0 ]; then r='"Success"'; else r="{\\"Failed\\":$rc}"; fi
    printf '"%s":{"status":{"Done":{"result":%s}}}' "$id" "$r" > "$state/last.json"
    echo "$id" ;;
  wait) : ;;
  log) cat "$state/$2.log" ;;
esac
`;
  writeFileSync(join(dir, "pueue"), script);
  chmodSync(join(dir, "pueue"), 0o755);
}

function hazardWrapper(command: string, shell: string, cwd = hazardRoot): string {
  return buildPueueWrapper({ command, cwd, onQueueFailure: "run-directly", label: "pueue-wrap", shell, taskLog: join(hazardRoot, "tasks.txt") });
}

function runUnder(outer: string, wrapped: string, path: string, env: Record<string, string> = {}) {
  const r = Bun.spawnSync([outer, "-c", wrapped], { env: { ...process.env, ...env, PATH: path }, timeout: 30_000 });
  return { stdout: r.stdout.toString(), stderr: r.stderr.toString(), exitCode: r.exitCode ?? -1 };
}

const OUTER_SHELLS = ZSH_INSTALLED ? ["bash", "zsh"] : ["bash"];

describe("hazard corpus: the wrapper carries every command intact", () => {
  beforeAll(() => {
    hazardRoot = mkdtempSync(join(tmpdir(), "pueue-wrap-hazard-"));
    writeStubPueue(join(hazardRoot, "stub-bin"), join(hazardRoot, "stub-state"));
    stubPath = `${join(hazardRoot, "stub-bin")}:${process.env.PATH ?? ""}`;
    const failing = join(hazardRoot, "failing-bin");
    mkdirSync(failing);
    writeFileSync(join(failing, "pueue"), "#!/bin/sh\nexit 1\n");
    chmodSync(join(failing, "pueue"), 0o755);
    failingPueuePath = `${failing}:${process.env.PATH ?? ""}`;
    // Stands in for the task shell: writes the script it was given with -c, byte for byte.
    recorderShell = join(hazardRoot, "record-shell");
    writeFileSync(recorderShell, '#!/bin/sh\nprintf %s "$2" > "$RECORD_TO"\n');
    chmodSync(recorderShell, 0o755);
  });
  afterAll(() => rmSync(hazardRoot, { recursive: true, force: true }));

  test.each(["", "'", "''", "a'b", "\"'\\$`!", "line1\nline2", "  spaced  ", "*?[]{}~#", "héllo — 世界", "a\\nb\\\\c"])(
    "shellSingleQuote round-trips %j through every outer shell",
    (text) => {
      for (const shell of OUTER_SHELLS) {
        const r = Bun.spawnSync([shell, "-c", `printf %s ${shellSingleQuote(text)}`]);
        expect(r.stdout.toString()).toBe(text);
      }
    },
  );

  for (const { c, shell } of HAZARD_RUNS) {
    test(`${c.name} [${shell}]: the wrapper parses and passes the safety check`, () => {
      const wrapped = hazardWrapper(c.cmd, shell);
      expect(parsesUnder("bash", wrapped)).toBe(true);
      if (ZSH_INSTALLED) expect(parsesUnder("zsh", wrapped)).toBe(true);
      expect(wrapIsSafe(c.cmd, wrapped, OUTER_SHELLS, shell)).toEqual({ ok: true, reason: "" });
    });

    test(`${c.name} [${shell}]: the task shell receives the command byte for byte`, () => {
      const record = join(hazardRoot, `record-${crypto.randomUUID()}`);
      for (const outer of OUTER_SHELLS) {
        const r = runUnder(outer, hazardWrapper(c.cmd, recorderShell), stubPath, { RECORD_TO: record });
        expect(r.exitCode).toBe(0);
        expect(readFileSync(record, "utf8")).toBe(c.cmd);
        rmSync(record);
      }
    });

    test(`${c.name} [${shell}]: same output, full statement list and the command's exit status`, () => {
      for (const outer of OUTER_SHELLS) {
        const r = runUnder(outer, hazardWrapper(c.cmd, shell), stubPath);
        expect(r.stdout).toBe(c.stdout);
        expect(r.exitCode).toBe(c.rc);
        const id = r.stderr.match(/queued as pueue task (\d+)/)?.[1];
        expect(id).toBeDefined();
        expect(readFileSync(join(hazardRoot, "stub-state", `${id}.argv`), "utf8")).toBe(`${shell} -c ${shellSingleQuote(c.cmd)}`);
      }
    });
  }

  test("runs in the requested working directory", () => {
    const r = runUnder("bash", hazardWrapper("pwd -P", "bash", "/tmp"), stubPath);
    expect(r.stdout.trim()).toBe(realpathSync("/tmp"));
  });

  test("when pueue cannot queue, the command runs directly and its exit code still comes back", () => {
    for (const outer of OUTER_SHELLS) {
      const r = runUnder(outer, hazardWrapper("echo 'direct'; exit 3", "bash"), failingPueuePath);
      expect(r.stdout).toBe("direct\n");
      expect(r.exitCode).toBe(3);
      expect(r.stderr).toContain("[pueue-wrap] pueue did not queue the command; running it directly");
    }
  });

  // The zsh-only `(N)` glob qualifier: safe to wrap when the task shell is zsh, and refused (left
  // unwrapped) when it is bash, because the original itself does not parse there.
  test.if(ZSH_INSTALLED)("the real 2026-10-12 failure is safe to wrap under zsh", () => {
    expect(wrapIsSafe(REAL_FAILURE, hazardWrapper(REAL_FAILURE, "zsh"), OUTER_SHELLS, "zsh").ok).toBe(true);
  });
  test("the real 2026-10-12 failure is not wrapped for a bash task shell", () => {
    expect(wrapIsSafe(REAL_FAILURE, hazardWrapper(REAL_FAILURE, "bash"), ["bash"], "bash").ok).toBe(false);
  });

  describe("the hook itself (pueue answered by the stand-in, so the operator's daemon is never asked)", () => {
    const HOOK = join(import.meta.dir, "pretooluse-pueue-wrap-guard.ts");

    function runHook(command: string, shell: string): { updated: string | undefined } {
      const r = Bun.spawnSync([process.execPath, HOOK], {
        stdin: Buffer.from(JSON.stringify({ tool_name: "Bash", tool_input: { command }, cwd: hazardRoot })),
        env: { ...process.env, PATH: stubPath, SHELL: shell, CLAUDE_SESSION_ID: `pueue-wrap-test-${process.pid}` },
        timeout: 10_000,
      });
      const out = r.stdout.toString().trim();
      return { updated: out ? JSON.parse(out).hookSpecificOutput?.updatedInput?.command : undefined };
    }

    test.if(ZSH_INSTALLED)("the real failing command is wrapped for a zsh user, intact", () => {
      const { updated } = runHook(REAL_FAILURE, Bun.which("zsh")!);
      expect(updated).toBeString();
      expect(updated).toContain(`-- ${shellSingleQuote(`zsh -c ${shellSingleQuote(REAL_FAILURE)}`)} 2>&1`);
      expect(parsesUnder("bash", updated!)).toBe(true);
      expect(parsesUnder("zsh", updated!)).toBe(true);
    });

    test("the real failing command is left unwrapped for a bash user", () => {
      expect(runHook(REAL_FAILURE, Bun.which("bash")!).updated).toBeUndefined();
    });

    test("a command that does not parse is passed through unwrapped", () => {
      expect(runHook("for i in 1; do python -c 'unterminated; done", Bun.which("bash")!).updated).toBeUndefined();
    });

    test("an unmatched command is not touched", () => {
      expect(runHook("echo hello", Bun.which("bash")!).updated).toBeUndefined();
    });
  });
});

// ── End to end, against a private pueue daemon ──────────────────────────────────────────────────

const REAL_PUEUE = Bun.which("pueue");
const REAL_PUEUED = Bun.which("pueued");
const e2e = REAL_PUEUE !== null && REAL_PUEUED !== null ? describe : describe.skip;

let root = "";
let shimPath = "";

e2e("the wrapper, run for real", () => {
  beforeAll(async () => {
    root = mkdtempSync(join(tmpdir(), "pueue-wrap-e2e-"));
    const config = join(root, "config.yml");
    mkdirSync(join(root, "data"));
    mkdirSync(join(root, "run"));
    writeFileSync(
      config,
      `shared:\n  pueue_directory: ${join(root, "data")}\n  runtime_directory: ${join(root, "run")}\n  use_unix_socket: true\n`,
    );
    const bin = join(root, "bin");
    mkdirSync(bin);
    writeFileSync(join(bin, "pueue"), `#!/bin/sh\nexec ${REAL_PUEUE} -c ${config} "$@"\n`);
    chmodSync(join(bin, "pueue"), 0o755);
    shimPath = `${bin}:${process.env.PATH ?? ""}`;
    Bun.spawnSync([REAL_PUEUED!, "-c", config, "-d"], { stdout: "ignore", stderr: "ignore" });
    for (let i = 0; i < 50; i += 1) {
      if (Bun.spawnSync(["pueue", "status"], { env: { ...process.env, PATH: shimPath } }).exitCode === 0) break;
      await Bun.sleep(100);
    }
  });

  afterAll(() => {
    Bun.spawnSync(["pueue", "shutdown"], { env: { ...process.env, PATH: shimPath }, stdout: "ignore", stderr: "ignore" });
    rmSync(root, { recursive: true, force: true });
  });

  function run(wrapped: string): { stdout: string; exitCode: number } {
    const r = Bun.spawnSync(["bash", "-c", wrapped], { env: { ...process.env, PATH: shimPath }, timeout: 30_000 });
    return { stdout: r.stdout.toString(), exitCode: r.exitCode ?? -1 };
  }

  test("a loop with quotes runs as written and its output comes back", () => {
    const r = run(buildPueueWrapper({ command: "for f in a b; do echo \"it's $f\"; done", cwd: root, onQueueFailure: "fail", label: "t" }));
    expect(r.stdout).toContain("it's a");
    expect(r.stdout).toContain("it's b");
    expect(r.exitCode).toBe(0);
  }, 30_000);

  test("the TASK's exit code is returned (pueue wait itself exits 0)", () => {
    const r = run(buildPueueWrapper({ command: "echo before; exit 3", cwd: root, onQueueFailure: "fail", label: "t" }));
    expect(r.stdout).toContain("before");
    expect(r.exitCode).toBe(3);
  }, 30_000);

  // The whole hazard corpus through the real daemon is slower (one queued task per case), so it is
  // opt-in: PUEUE_WRAP_E2E=1. It still uses this block's private daemon, never the operator's.
  for (const { c, shell } of HAZARD_RUNS) {
    test.if(process.env.PUEUE_WRAP_E2E === "1")(`hazard corpus, real pueue: ${c.name} [${shell}]`, () => {
      const r = run(buildPueueWrapper({ command: c.cmd, cwd: root, onQueueFailure: "fail", label: "t", shell }));
      for (const line of c.stdout.split("\n").filter(Boolean)) expect(r.stdout).toContain(line);
      expect(r.stdout).not.toContain("never"); // set -e stopped the script: nothing after `false` ran
      expect(r.exitCode).toBe(c.rc);
    }, 30_000);
  }

  test.if(process.env.PUEUE_WRAP_E2E === "1")("real pueue runs the task in the requested working directory", () => {
    const r = run(buildPueueWrapper({ command: "pwd -P", cwd: "/tmp", onQueueFailure: "fail", label: "t" }));
    expect(r.stdout).toContain(realpathSync("/tmp"));
    expect(r.exitCode).toBe(0);
  }, 30_000);
});
