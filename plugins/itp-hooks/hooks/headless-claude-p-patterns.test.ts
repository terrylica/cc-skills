/**
 * headless `claude -p` guard — BOTH directions.
 *
 *   bun test plugins/itp-hooks/hooks/headless-claude-p-patterns.test.ts
 *
 * A guard counts only after it is observed FIRING on input it must refuse AND observed STAYING SILENT
 * on input it must pass. The silent direction gets MORE cases here than the firing direction, on
 * purpose: this hook runs on every Bash command on the machine, so a false positive blocks unrelated
 * work — including writing the very documentation that explains the guard. A guard people have to
 * fight is a guard they turn off.
 */
import { describe, expect, test } from "bun:test";
import {
  explainViolations,
  findClaudeInvocations,
  findHeadlessViolations,
  isHeadlessClaudeInvocation,
  VALID_EFFORT_LEVELS,
} from "./headless-claude-p-patterns.ts";

const kinds = (cmd: string): string[] => findHeadlessViolations(cmd).map((v) => v.kind);

describe("MUST FIRE — provably broken invocations", () => {
  test("stream-json without --verbose (emits nothing at all)", () => {
    expect(kinds(`claude -p "hi" --output-format stream-json --model claude-opus-5`))
      .toEqual(["stream-json-without-verbose"]);
  });

  test("stream-json without --verbose, equals form", () => {
    expect(kinds(`ccmax-claude -p "hi" --output-format=stream-json`))
      .toEqual(["stream-json-without-verbose"]);
  });

  test("CLAUDE_EFFORT env var — reads as reasoning control, is a no-op", () => {
    expect(kinds(`CLAUDE_EFFORT=xhigh claude -p "hi" --output-format json`))
      .toEqual(["claude-effort-env-var"]);
  });

  test("CLAUDE_EFFORT set earlier in a compound command still misleads", () => {
    expect(kinds(`export CLAUDE_EFFORT=max && claude -p "hi" --output-format json`))
      .toContain("claude-effort-env-var");
  });

  test("invalid --effort level (accepted with exit 0, silently ignored)", () => {
    const v = findHeadlessViolations(`claude -p "hi" --effort hight`);
    expect(v.map((x) => x.kind)).toEqual(["invalid-effort-level"]);
    expect(v[0]?.detail).toBe("hight");
  });

  test("several problems at once are all reported", () => {
    expect(kinds(`CLAUDE_EFFORT=max claude -p "hi" --output-format stream-json --effort nope`).toSorted())
      .toEqual(["claude-effort-env-var", "invalid-effort-level", "stream-json-without-verbose"]);
  });

  test("fires behind timeout/env/nohup wrappers", () => {
    expect(kinds(`timeout 300 claude -p "hi" --output-format stream-json`))
      .toEqual(["stream-json-without-verbose"]);
    expect(kinds(`env FOO=1 ccmax-claude --print "hi" --output-format stream-json`))
      .toEqual(["stream-json-without-verbose"]);
  });

  test("fires on an absolute path to the binary", () => {
    expect(kinds(`/Users/x/.local/bin/claude -p "hi" --output-format stream-json`))
      .toEqual(["stream-json-without-verbose"]);
  });

  test("fires on the second command of a pipeline", () => {
    expect(kinds(`cat prompt.txt && claude -p "hi" --output-format stream-json`))
      .toEqual(["stream-json-without-verbose"]);
  });
});

describe("MUST STAY SILENT — correct or unrelated commands", () => {
  test.each([
    [`claude -p "hi" --output-format stream-json --verbose`, "stream-json WITH --verbose"],
    [`claude -p "hi" --output-format json --model claude-opus-5`, "plain json"],
    [`claude -p "hi"`, "bare headless call — defaults to high, often correct"],
    ...VALID_EFFORT_LEVELS.map((l) => [`claude -p "hi" --effort ${l}`, `valid effort ${l}`] as const),
    [`claude -p "hi" --effort=max`, "equals form of a valid level"],
    [`claude`, "interactive, no -p"],
    [`claude --help`, "help"],
    [`claude --resume abc --output-format stream-json`, "no -p, so the --verbose rule does not apply"],
    [`ls -p /tmp`, "-p on an unrelated binary"],
    [`grep -p claude file.txt`, "grep, not claude"],
  ])("passes: %s (%s)", (cmd) => {
    expect(findHeadlessViolations(cmd as string)).toEqual([]);
  });

  test("does NOT fire on text ABOUT claude -p (docs, echo, heredocs)", () => {
    // This is the false positive that would make the guard intolerable: it must be possible to write
    // and grep the documentation that describes the very command being guarded.
    const docish = [
      `echo "run claude -p 'x' --output-format stream-json to stream"`,
      `grep -n "claude -p" docs/headless-claude-p.md`,
      `rg 'CLAUDE_EFFORT=xhigh' ~/.claude`,
      `cat <<'EOF' > notes.md\nclaude -p "hi" --output-format stream-json\nEOF`,
    ];
    for (const cmd of docish) expect(findHeadlessViolations(cmd)).toEqual([]);
  });

  test("does not fire on --print-task-id style flags", () => {
    expect(isHeadlessClaudeInvocation(`claude --print-task-id --output-format stream-json`)).toBe(false);
  });
});

describe("invocation detection", () => {
  test("finds one invocation per command position", () => {
    expect(findClaudeInvocations(`claude -p a && ccmax-claude -p b`)).toHaveLength(2);
  });
  test("finds none when claude is only an argument", () => {
    expect(findClaudeInvocations(`echo claude -p`)).toHaveLength(0);
  });
});

describe("the explanation", () => {
  test("names the fix, points at the SSoT, and offers the escape hatch", () => {
    const msg = explainViolations(findHeadlessViolations(`claude -p "x" --output-format stream-json`));
    expect(msg).toContain("--verbose");
    expect(msg).toContain("headless-claude-p.md");
    expect(msg).toContain("HEADLESS-P-OK");
  });

  test("quotes the offending effort level back", () => {
    expect(explainViolations(findHeadlessViolations(`claude -p "x" --effort hight`))).toContain("hight");
  });
});
