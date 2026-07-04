/**
 * Tests for posttooluse-python-preference-nudge.ts
 *
 * Run with: bun test plugins/itp-hooks/hooks/posttooluse-python-preference-nudge.test.ts
 *
 * Strategy: the allow/deny LOGIC is tested through the pure functions
 * (`isPythonFileExplicitlyAllowed`, `evaluatePythonPreferenceNudgeIgnoringTempScratch`)
 * with fixtures placed under a real temp directory — those functions do NOT
 * apply the temp-scratch exemption, so temp fixtures are fine. The temp-scratch
 * exemption itself is pinned through the classifier on a /tmp path.
 */

import { afterAll, beforeAll, describe, expect, it } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  buildPythonPreferenceReminderMessage,
  classifyPythonPreferenceNudgeForPostToolUseOrchestrator,
  evaluatePythonPreferenceNudgeIgnoringTempScratch,
  isPythonFileExplicitlyAllowed,
} from "./posttooluse-python-preference-nudge.ts";

let root: string;

beforeAll(() => {
  // A self-contained fixture tree with a .git marker so the ancestor walk
  // stops at this synthetic "repo root" instead of climbing to $HOME.
  root = mkdtempSync(join(tmpdir(), "pyallow-"));
  mkdirSync(join(root, ".git"), { recursive: true });
  mkdirSync(join(root, "sub"), { recursive: true });

  // The .py files under test.
  writeFileSync(join(root, "allowed.py"), "x = 1\n");
  writeFileSync(join(root, "blank_reason.py"), "x = 1\n");
  writeFileSync(join(root, "unlisted.py"), "x = 1\n");
  writeFileSync(join(root, "sub", "nested.py"), "x = 1\n");
  writeFileSync(join(root, "bad_toml.py"), "x = 1\n");

  // Root allowlist: one valid entry, one blank-reason entry, plus a nested
  // entry whose path is relative to THIS file's directory (the repo root).
  writeFileSync(
    join(root, "python-allowlist.toml"),
    [
      "[[allow]]",
      'path   = "allowed.py"',
      'reason = "numba JIT kernel; SOTA-native lane"',
      'issue  = "eon/mono#1"',
      "",
      "[[allow]]",
      'path   = "blank_reason.py"',
      'reason = "   "',
      "",
      "[[allow]]",
      'path   = "sub/nested.py"',
      'reason = "pandas ETL; migration tracked"',
      "",
    ].join("\n"),
  );
});

afterAll(() => {
  rmSync(root, { recursive: true, force: true });
});

describe("isPythonFileExplicitlyAllowed", () => {
  it("returns true for a file listed with a non-empty reason", () => {
    expect(isPythonFileExplicitlyAllowed(join(root, "allowed.py"))).toBe(true);
  });

  it("returns false for a .py file not listed at all", () => {
    expect(isPythonFileExplicitlyAllowed(join(root, "unlisted.py"))).toBe(false);
  });

  it("returns false when the entry's reason is blank/whitespace", () => {
    expect(isPythonFileExplicitlyAllowed(join(root, "blank_reason.py"))).toBe(false);
  });

  it("resolves an entry path relative to a parent-directory allowlist (nested)", () => {
    expect(isPythonFileExplicitlyAllowed(join(root, "sub", "nested.py"))).toBe(true);
  });

  it("treats a malformed allowlist as zero entries (no blanket silence)", () => {
    const badRoot = mkdtempSync(join(tmpdir(), "pyallow-bad-"));
    mkdirSync(join(badRoot, ".git"), { recursive: true });
    writeFileSync(join(badRoot, "bad.py"), "x = 1\n");
    writeFileSync(join(badRoot, "python-allowlist.toml"), "this is = = not valid toml [[[\n");
    expect(isPythonFileExplicitlyAllowed(join(badRoot, "bad.py"))).toBe(false);
    rmSync(badRoot, { recursive: true, force: true });
  });
});

describe("evaluatePythonPreferenceNudgeIgnoringTempScratch", () => {
  it("nudges on an unlisted .py Write", () => {
    const r = evaluatePythonPreferenceNudgeIgnoringTempScratch("Write", join(root, "unlisted.py"));
    expect(r.shouldNudge).toBe(true);
  });

  it("does not nudge on an allowed .py Edit", () => {
    const r = evaluatePythonPreferenceNudgeIgnoringTempScratch("Edit", join(root, "allowed.py"));
    expect(r.shouldNudge).toBe(false);
  });

  it("does not nudge on a non-.py file", () => {
    const r = evaluatePythonPreferenceNudgeIgnoringTempScratch("Write", join(root, "main.ts"));
    expect(r.shouldNudge).toBe(false);
  });

  it("does not nudge on a non-edit tool (Bash)", () => {
    const r = evaluatePythonPreferenceNudgeIgnoringTempScratch("Bash", join(root, "unlisted.py"));
    expect(r.shouldNudge).toBe(false);
  });

  it("does not nudge on vendored/venv .py files", () => {
    const r = evaluatePythonPreferenceNudgeIgnoringTempScratch(
      "Write",
      join(root, ".venv", "lib", "site-packages", "foo.py"),
    );
    expect(r.shouldNudge).toBe(false);
  });
});

describe("classifyPythonPreferenceNudgeForPostToolUseOrchestrator", () => {
  it("emits additional_context for an unlisted non-temp .py file", async () => {
    const decision = await classifyPythonPreferenceNudgeForPostToolUseOrchestrator({
      tool_name: "Write",
      tool_input: { file_path: "/Users/nonexistent-project/greenfield_script.py" },
    });
    expect(decision.kind).toBe("additional_context");
    if (decision.kind === "additional_context") {
      expect(decision.message).toContain("[PY-PREFER]");
      expect(decision.message).toContain("python-allowlist.toml");
    }
  });

  it("is a noop for an allowed .py file", async () => {
    const decision = await classifyPythonPreferenceNudgeForPostToolUseOrchestrator({
      tool_name: "Write",
      tool_input: { file_path: join(root, "allowed.py") },
    });
    expect(decision.kind).toBe("noop");
  });

  it("is a noop for ephemeral temp-scratch .py (the one implicit exemption)", async () => {
    const decision = await classifyPythonPreferenceNudgeForPostToolUseOrchestrator({
      tool_name: "Write",
      tool_input: { file_path: "/tmp/throwaway_scratch.py" },
    });
    expect(decision.kind).toBe("noop");
  });

  it("is a noop for a non-.py edit", async () => {
    const decision = await classifyPythonPreferenceNudgeForPostToolUseOrchestrator({
      tool_name: "Edit",
      tool_input: { file_path: "/Users/nonexistent-project/app.ts" },
    });
    expect(decision.kind).toBe("noop");
  });
});

describe("buildPythonPreferenceReminderMessage", () => {
  it("includes the file path and a copy-pasteable [[allow]] block", () => {
    const msg = buildPythonPreferenceReminderMessage("scripts/foo.py");
    expect(msg).toContain("scripts/foo.py");
    expect(msg).toContain("[[allow]]");
    expect(msg).toContain("reason =");
  });
});
