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
 * touches the operator's queue, and skips when pueue is not installed.
 */

import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
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
});
