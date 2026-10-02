#!/usr/bin/env bun
/**
 * Unit tests for the shell-script-safety subhook classifier.
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
