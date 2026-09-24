/**
 * Regression: validateHookCommandHygiene() check (c) — no hook that can receive AskUserQuestion may
 * emit updatedInput, directly or via allowWithInput. For that tool updatedInput carries the user's
 * answers, so a rewrite suppresses the dialog and the question returns unanswered (86 of 86 calls,
 * 2026-09-12 to 2026-09-24). The decisive fixture is the ORIGINAL premise annotator from cc-skills
 * 909d0625, which never spelled `updatedInput` itself and would slip past a naive grep.
 */
import { afterAll, describe, expect, it } from "bun:test";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  hookMatcherCoversTool,
  scriptEmitsUpdatedInput,
  validateHookCommandHygiene,
} from "./validate-plugins.mjs";

const REPO_ROOT = join(import.meta.dir, "..");
const WORK = mkdtempSync(join(tmpdir(), "vp-auq-updatedinput-"));
afterAll(() => rmSync(WORK, { recursive: true, force: true }));

function fixture(name: string, matcher: string | undefined, script: string): string {
  const root = join(WORK, name);
  const hooksDir = join(root, "plugins", "p", "hooks");
  mkdirSync(hooksDir, { recursive: true });
  writeFileSync(join(hooksDir, "h.ts"), script);
  const entry: Record<string, unknown> = {
    // biome-ignore lint/suspicious/noTemplateCurlyInString: a literal hooks.json command, expanded by Claude Code, not JS
    hooks: [{ type: "command", command: "env -u AI_AGENT -u CLAUDECODE bun ${CLAUDE_PLUGIN_ROOT}/hooks/h.ts" }],
  };
  if (matcher !== undefined) entry.matcher = matcher;
  writeFileSync(join(hooksDir, "hooks.json"), JSON.stringify({ hooks: { PreToolUse: [entry] } }));
  return root;
}

async function flagged(root: string): Promise<boolean> {
  const { errors } = await validateHookCommandHygiene(root);
  return errors.some((e: string) => e.includes("AskUserQuestion") && e.includes("updatedInput"));
}

describe("validate-plugins check (c): no updatedInput for AskUserQuestion", () => {
  it("flags the ORIGINAL premise annotator (909d0625), which only calls allowWithInput", async () => {
    const original = execFileSync(
      "git",
      ["show", "909d0625:plugins/itp-hooks/hooks/pretooluse-pr-premise-annotator.ts"],
      { cwd: REPO_ROOT, encoding: "utf8" },
    );
    expect(await flagged(fixture("original-annotator", "AskUserQuestion", original))).toBe(true);
  });

  it("flags a hand-rolled updatedInput under a wildcard matcher", async () => {
    const script = `console.log(JSON.stringify({hookSpecificOutput:{permissionDecision:"allow",updatedInput:{}}}));`;
    expect(await flagged(fixture("hand-rolled", undefined, script))).toBe(true);
  });

  it("does not flag the fixed annotator, which only mentions updatedInput in comments", async () => {
    const fixed = execFileSync("git", ["show", "HEAD:plugins/itp-hooks/hooks/pretooluse-pr-premise-annotator.ts"], {
      cwd: REPO_ROOT,
      encoding: "utf8",
    });
    expect(await flagged(fixture("fixed-annotator", "AskUserQuestion", fixed))).toBe(false);
  });

  it("does not flag allowWithInput in a Bash-only hook", async () => {
    const script = `import { allowWithInput } from "./x"; allowWithInput("h", "Bash", { command: "ls" });`;
    expect(await flagged(fixture("bash-only", "Bash", script))).toBe(false);
  });

  it("matcher coverage follows Claude Code's anchored-regex semantics", () => {
    expect(hookMatcherCoversTool(undefined, "AskUserQuestion")).toBe(true);
    expect(hookMatcherCoversTool("*", "AskUserQuestion")).toBe(true);
    expect(hookMatcherCoversTool("Bash|AskUserQuestion", "AskUserQuestion")).toBe(true);
    expect(hookMatcherCoversTool("Bash", "AskUserQuestion")).toBe(false);
    expect(hookMatcherCoversTool("Ask", "AskUserQuestion")).toBe(false);
  });

  it("strips comments before looking", () => {
    const path = join(WORK, "comment-only.ts");
    writeFileSync(path, "// updatedInput is forbidden here\n/* allowWithInput( */\nconsole.log('{}');\n");
    expect(scriptEmitsUpdatedInput(path)).toBe(false);
  });
});
