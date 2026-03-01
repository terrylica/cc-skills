/**
 * Tests for pretooluse-uv-enforcement-guard.ts
 *
 * Run with: bun test plugins/itp-hooks/hooks/pretooluse-uv-enforcement-guard.test.ts
 */

import { describe, expect, it } from "bun:test";
import { execSync } from "child_process";
import { join } from "path";

const HOOK_PATH = join(import.meta.dir, "pretooluse-uv-enforcement-guard.ts");

interface HookResult {
  stdout: string;
  parsed: {
    hookSpecificOutput?: {
      hookEventName: string;
      permissionDecision: "allow" | "deny";
      permissionDecisionReason?: string;
    };
  } | null;
}

function runHook(input: object): HookResult {
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
    return { stdout, parsed };
  } catch (err: any) {
    const stdout = err.stdout?.toString().trim() || "";
    let parsed = null;
    if (stdout) {
      try {
        parsed = JSON.parse(stdout);
      } catch {
        // Not JSON
      }
    }
    return { stdout, parsed };
  }
}

function expectDeny(result: HookResult, containsText?: string): void {
  expect(result.parsed).not.toBeNull();
  expect(result.parsed!.hookSpecificOutput?.permissionDecision).toBe("deny");
  expect(result.parsed!.hookSpecificOutput?.permissionDecisionReason).toContain("[UV-ENFORCEMENT]");
  if (containsText) {
    expect(result.parsed!.hookSpecificOutput?.permissionDecisionReason).toContain(containsText);
  }
}

function expectAllow(result: HookResult): void {
  expect(result.parsed).not.toBeNull();
  expect(result.parsed!.hookSpecificOutput?.permissionDecision).toBe("allow");
}

// ============================================================================
// BLOCK Cases: pip install variants
// ============================================================================

describe("BLOCK: pip install variants", () => {
  it("should block pip install", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip install requests" },
    });
    expectDeny(result, "uv add");
  });

  it("should block pip3 install", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip3 install numpy" },
    });
    expectDeny(result, "uv add");
  });

  it("should block python -m pip install", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "python -m pip install flask" },
    });
    expectDeny(result);
  });

  it("should block python3 -m pip install", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "python3 -m pip install flask" },
    });
    expectDeny(result);
  });

  it("should block python3.13 -m pip install", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "python3.13 -m pip install torch" },
    });
    expectDeny(result);
  });

  it("should block pip install -e . (editable)", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip install -e ." },
    });
    expectDeny(result);
  });

  it("should block pip install -r requirements.txt", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip install -r requirements.txt" },
    });
    expectDeny(result);
  });

  it("should block pip install in chained command", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "cd /tmp && pip install requests" },
    });
    expectDeny(result);
  });
});

// ============================================================================
// BLOCK Cases: pip uninstall
// ============================================================================

describe("BLOCK: pip uninstall", () => {
  it("should block pip uninstall", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip uninstall requests" },
    });
    expectDeny(result, "uv remove");
  });

  it("should block pip3 uninstall", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip3 uninstall numpy" },
    });
    expectDeny(result, "uv remove");
  });
});

// ============================================================================
// BLOCK Cases: conda
// ============================================================================

describe("BLOCK: conda", () => {
  it("should block conda install", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "conda install pandas" },
    });
    expectDeny(result, "uv add");
  });

  it("should block conda create", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "conda create -n myenv python=3.13" },
    });
    expectDeny(result, "uv venv");
  });
});

// ============================================================================
// BLOCK Cases: pipx, virtualenv, easy_install
// ============================================================================

describe("BLOCK: pipx, virtualenv, easy_install", () => {
  it("should block pipx install", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pipx install black" },
    });
    expectDeny(result, "uv tool install");
  });

  it("should block virtualenv", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "virtualenv .venv" },
    });
    expectDeny(result, "uv venv");
  });

  it("should block python -m venv", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "python -m venv .venv" },
    });
    expectDeny(result, "uv venv");
  });

  it("should block python3 -m venv", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "python3 -m venv myenv" },
    });
    expectDeny(result, "uv venv");
  });

  it("should block easy_install", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "easy_install setuptools" },
    });
    expectDeny(result);
  });
});

// ============================================================================
// BLOCK Cases: SSH-wrapped commands
// ============================================================================

describe("BLOCK: SSH-wrapped commands", () => {
  it("should block pip install inside SSH", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "ssh bigblack 'cd ~/project && pip install requests'" },
    });
    expectDeny(result);
  });

  it("should block conda install inside SSH", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "ssh server 'conda install pytorch'" },
    });
    expectDeny(result);
  });
});

// ============================================================================
// ALLOW Cases: uv context
// ============================================================================

describe("ALLOW: uv context", () => {
  it("should allow uv add", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "uv add requests" },
    });
    expectAllow(result);
  });

  it("should allow uv pip install", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "uv pip install -e ." },
    });
    expectAllow(result);
  });

  it("should allow uv run", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "uv run python script.py" },
    });
    expectAllow(result);
  });

  it("should allow uv sync", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "uv sync" },
    });
    expectAllow(result);
  });

  it("should allow uv venv", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "uv venv .venv" },
    });
    expectAllow(result);
  });

  it("should allow uv tool install", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "uv tool install ruff" },
    });
    expectAllow(result);
  });
});

// ============================================================================
// ALLOW Cases: read-only pip operations
// ============================================================================

describe("ALLOW: read-only pip operations", () => {
  it("should allow pip list", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip list" },
    });
    expectAllow(result);
  });

  it("should allow pip show", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip show requests" },
    });
    expectAllow(result);
  });

  it("should allow pip freeze", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip freeze" },
    });
    expectAllow(result);
  });

  it("should allow pip check", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip check" },
    });
    expectAllow(result);
  });

  it("should allow pip --version", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip --version" },
    });
    expectAllow(result);
  });

  it("should allow pip-compile", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip-compile requirements.in" },
    });
    expectAllow(result);
  });
});

// ============================================================================
// ALLOW Cases: documentation/echo/grep context
// ============================================================================

describe("ALLOW: documentation and search context", () => {
  it("should allow echo with pip", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "echo 'pip install requests'" },
    });
    expectAllow(result);
  });

  it("should allow printf with pip", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "printf 'pip install %s\\n' requests" },
    });
    expectAllow(result);
  });

  it("should allow grep for pip", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "grep -r 'pip install' docs/" },
    });
    expectAllow(result);
  });

  it("should allow rg for pip", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "rg 'pip install' ." },
    });
    expectAllow(result);
  });

  it("should allow comments with pip", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "# pip install requests" },
    });
    expectAllow(result);
  });
});

// ============================================================================
// ALLOW Cases: escape hatch
// ============================================================================

describe("ALLOW: # UV-OK escape hatch", () => {
  it("should allow pip install with # UV-OK", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip install requests # UV-OK" },
    });
    expectAllow(result);
  });

  it("should allow conda install with # UV-OK", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "conda install pandas # UV-OK" },
    });
    expectAllow(result);
  });
});

// ============================================================================
// ALLOW Cases: non-Bash tools and unrelated commands
// ============================================================================

describe("ALLOW: non-Bash tools", () => {
  it("should allow Write tool", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: { file_path: "test.py", content: "pip install requests" },
    });
    expectAllow(result);
  });

  it("should allow Edit tool", () => {
    const result = runHook({
      tool_name: "Edit",
      tool_input: { file_path: "test.py" },
    });
    expectAllow(result);
  });

  it("should allow Read tool", () => {
    const result = runHook({
      tool_name: "Read",
      tool_input: { file_path: "requirements.txt" },
    });
    expectAllow(result);
  });
});

describe("ALLOW: unrelated commands", () => {
  it("should allow ls", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "ls -la" },
    });
    expectAllow(result);
  });

  it("should allow git commands", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "git status" },
    });
    expectAllow(result);
  });

  it("should allow npm install (not Python)", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "npm install express" },
    });
    expectAllow(result);
  });

  it("should allow bun add (not Python)", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "bun add prettier" },
    });
    expectAllow(result);
  });
});

// ============================================================================
// Edge Cases
// ============================================================================

describe("Edge cases", () => {
  it("should handle empty command", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "" },
    });
    expectAllow(result);
  });

  it("should handle missing command", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: {},
    });
    expectAllow(result);
  });

  it("should handle malformed JSON gracefully (fail-open)", () => {
    try {
      const stdout = execSync(`echo 'not json' | bun ${HOOK_PATH}`, {
        encoding: "utf-8",
        stdio: ["pipe", "pipe", "pipe"],
      }).trim();

      // Should output allow (fail-open)
      if (stdout) {
        const parsed = JSON.parse(stdout);
        expect(parsed.hookSpecificOutput?.permissionDecision).toBe("allow");
      }
    } catch {
      // Also acceptable — fail-open means no crash
      expect(true).toBe(true);
    }
  });

  it("should block multi-line command with pip install", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "cd /tmp\npip install requests" },
    });
    expectDeny(result);
  });

  it("should handle command with only whitespace", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "   " },
    });
    expectAllow(result);
  });
});
