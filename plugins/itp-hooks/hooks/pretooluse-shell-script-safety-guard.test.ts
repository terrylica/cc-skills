#!/usr/bin/env bun
/**
 * Tool-name cohort consistency for the shell-script-safety subhook.
 *
 * This guard was the ONLY one of the eleven classifiers in the edit-time orchestrator's cohort
 * without a MultiEdit short-circuit. iter-102 widened the tool-name GATE to accept MultiEdit but
 * left per-classifier PAYLOAD adaptation to iter-103, so its ten siblings each return ALLOW for
 * MultiEdit straight after the gate — a MultiEdit carries `edits[]`, not `content`/`new_string`.
 *
 * The omission was harmless only because the orchestrator's fastpath never forwards MultiEdit.
 * That fastpath looks like an obvious one-line bug and was recommended to me as one; opening it
 * would have activated this guard alone, against a payload it cannot read, while the other ten
 * stayed correctly inert. These tests pin the CONSISTENCY, not the capability.
 */

import { describe, expect, it } from "bun:test";
import type { PreToolUseInput } from "./pretooluse-helpers.ts";
import { classifyShellScriptSafetyGuardForOrchestrator } from "./pretooluse-shell-script-safety-guard.ts";

const DEFECTIVE_SCRIPT = [
  "#!/usr/bin/env bash",
  "set -euo pipefail",
  "run() {",
  "  local status=$(some_command)",
  "  echo \"$status\"",
  "}",
  "",
].join("\n");

describe("the plan-mode check must read .inPlanMode, not the context object", () => {
  // `isPlanMode` returns a PlanModeContext object, never a boolean. `if (isPlanMode(input))` is
  // therefore ALWAYS true, and this guard returned ALLOW on every invocation for its entire life —
  // enforcing nothing, while appearing in the registry as an active CRITICAL-policy guard.
  it("does NOT allow merely because a context object was returned", async () => {
    const decision = await classifyShellScriptSafetyGuardForOrchestrator({
      tool_name: "Write",
      tool_input: { file_path: "/tmp/not-a-plan.sh", content: DEFECTIVE_SCRIPT },
    } as unknown as PreToolUseInput);

    expect(decision.kind).toBe("deny");
  });

  it("DOES allow when the session really is in plan mode", async () => {
    // The other direction, so the fix cannot be "delete the plan-mode check".
    const decision = await classifyShellScriptSafetyGuardForOrchestrator({
      tool_name: "Write",
      permission_mode: "plan",
      tool_input: { file_path: "/tmp/planned.sh", content: DEFECTIVE_SCRIPT },
    } as unknown as PreToolUseInput);

    expect(decision.kind).toBe("allow");
  });
});

describe("MultiEdit is inert until iter-103 payload adaptation lands", () => {
  it("returns allow for a MultiEdit payload rather than reading undefined fields", async () => {
    const decision = await classifyShellScriptSafetyGuardForOrchestrator({
      tool_name: "MultiEdit",
      tool_input: {
        file_path: "/tmp/example-multiedit.sh",
        edits: [{ old_string: "x", new_string: DEFECTIVE_SCRIPT }],
      },
    } as unknown as PreToolUseInput);

    expect(decision.kind).toBe("allow");
  });

  it("stays inert even if a future extractor supplies `content` for a MultiEdit", async () => {
    // THIS is what makes the short-circuit load-bearing rather than decoration. Without it, the
    // case above passes for the wrong reason — the `!newFileContent` check already allows any
    // payload lacking `content`, so removing the short-circuit changes nothing today and the
    // mutation survives. The moment iter-103 folds `edits[].new_string` into a content field, that
    // accidental protection disappears and this guard would silently begin evaluating MultiEdit
    // with Edit-branch semantics it was never adapted for. Pin the intent, not the side effect.
    const decision = await classifyShellScriptSafetyGuardForOrchestrator({
      tool_name: "MultiEdit",
      tool_input: {
        file_path: "/tmp/example-multiedit.sh",
        content: DEFECTIVE_SCRIPT,
        edits: [{ old_string: "x", new_string: DEFECTIVE_SCRIPT }],
      },
    } as unknown as PreToolUseInput);

    expect(decision.kind).toBe("allow");
  });

  it("DENIES the same defect when it arrives as a Write", async () => {
    // The control, and it is the whole point. Without it the test above would pass just as happily
    // on a guard that had stopped detecting anything at all — which is the failure mode a
    // short-circuit test is most likely to hide.
    const decision = await classifyShellScriptSafetyGuardForOrchestrator({
      tool_name: "Write",
      tool_input: { file_path: "/tmp/example-write.sh", content: DEFECTIVE_SCRIPT },
    } as unknown as PreToolUseInput);

    expect(decision.kind).toBe("deny");
  });
});
