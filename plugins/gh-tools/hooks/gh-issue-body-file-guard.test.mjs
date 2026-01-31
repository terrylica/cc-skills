/**
 * Tests for gh-issue-body-file-guard.mjs
 *
 * Run with: bun test plugins/gh-tools/hooks/gh-issue-body-file-guard.test.mjs
 *
 * ADR: /docs/adr/2026-01-11-gh-issue-body-file-guard.md
 */

import { describe, expect, it } from "bun:test";
import { execSync } from "child_process";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const HOOK_PATH = join(__dirname, "gh-issue-body-file-guard.mjs");

/**
 * Run the hook with given input and return parsed result
 */
function runHook(input) {
  try {
    const inputJson = JSON.stringify(input);
    const stdout = execSync(`bun ${HOOK_PATH}`, {
      encoding: "utf-8",
      input: inputJson,
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();

    let parsed = null;
    if (stdout) {
      try {
        parsed = JSON.parse(stdout);
      } catch {
        // Not JSON output
      }
    }
    return { stdout, parsed, exitCode: 0 };
  } catch (err) {
    return {
      stdout: err.stdout?.toString() || "",
      parsed: null,
      exitCode: err.status || 1,
    };
  }
}

// ============================================================================
// BLOCKED: Inline --body usage
// ============================================================================

describe("gh-issue-body-file-guard: BLOCKED cases", () => {
  it("should DENY gh issue create with --body flag", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: {
        command: 'gh issue create --title "Bug report" --body "This is inline content"',
      },
    });
    expect(result.parsed).not.toBeNull();
    expect(result.parsed?.hookSpecificOutput?.permissionDecision).toBe("deny");
    expect(result.parsed?.hookSpecificOutput?.permissionDecisionReason).toContain(
      "[gh-issue-guard] BLOCKED"
    );
  });

  it("should DENY gh issue create with heredoc body", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: {
        command: `gh issue create --title "Bug" --body "$(cat <<'EOF'
Long content here
EOF
)"`,
      },
    });
    expect(result.parsed).not.toBeNull();
    expect(result.parsed?.hookSpecificOutput?.permissionDecision).toBe("deny");
  });

  it("should include required pattern in denial reason", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: {
        command: 'gh issue create --title "Test" --body "content"',
      },
    });
    expect(result.parsed?.hookSpecificOutput?.permissionDecisionReason).toContain(
      "--body-file"
    );
    expect(result.parsed?.hookSpecificOutput?.permissionDecisionReason).toContain(
      "Required pattern"
    );
  });
});

// ============================================================================
// ALLOWED: --body-file usage
// ============================================================================

describe("gh-issue-body-file-guard: ALLOWED cases", () => {
  it("should ALLOW gh issue create with --body-file", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: {
        command: 'gh issue create --title "Bug report" --body-file /tmp/issue.md',
      },
    });
    expect(result.stdout).toBe("");
    expect(result.exitCode).toBe(0);
  });

  it("should ALLOW gh issue create without --body (interactive mode)", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: {
        command: 'gh issue create --title "Bug report"',
      },
    });
    expect(result.stdout).toBe("");
    expect(result.exitCode).toBe(0);
  });

  it("should ALLOW gh issue create with just --title", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: {
        command: "gh issue create",
      },
    });
    expect(result.stdout).toBe("");
    expect(result.exitCode).toBe(0);
  });
});

// ============================================================================
// SKIP: Non-matching commands
// ============================================================================

describe("gh-issue-body-file-guard: SKIP cases", () => {
  it("should SKIP non-Bash tools", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: "/tmp/test.md",
        content: 'gh issue create --body "test"',
      },
    });
    expect(result.stdout).toBe("");
    expect(result.exitCode).toBe(0);
  });

  it("should SKIP gh pr create commands", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: {
        command: 'gh pr create --title "PR" --body "content"',
      },
    });
    expect(result.stdout).toBe("");
    expect(result.exitCode).toBe(0);
  });

  it("should SKIP gh issue view commands", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: {
        command: "gh issue view 123",
      },
    });
    expect(result.stdout).toBe("");
    expect(result.exitCode).toBe(0);
  });

  it("should SKIP gh issue list commands", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: {
        command: "gh issue list --state open",
      },
    });
    expect(result.stdout).toBe("");
    expect(result.exitCode).toBe(0);
  });

  it("should SKIP empty input", () => {
    const result = runHook({});
    expect(result.stdout).toBe("");
    expect(result.exitCode).toBe(0);
  });
});

// ============================================================================
// Edge cases
// ============================================================================

describe("gh-issue-body-file-guard: Edge cases", () => {
  it("should handle command with extra whitespace", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: {
        command: 'gh   issue   create --body "test"',
      },
    });
    expect(result.parsed?.hookSpecificOutput?.permissionDecision).toBe("deny");
  });

  it("should ALLOW when --body-file comes before --body in same command", () => {
    // --body-file takes precedence
    const result = runHook({
      tool_name: "Bash",
      tool_input: {
        command: 'gh issue create --body-file /tmp/f.md --title "Test"',
      },
    });
    expect(result.stdout).toBe("");
    expect(result.exitCode).toBe(0);
  });
});
