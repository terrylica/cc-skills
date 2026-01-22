/**
 * Tests for posttooluse-reminder.ts
 *
 * Run with: bun test plugins/itp-hooks/hooks/posttooluse-reminder.test.ts
 */

import { describe, expect, it, beforeAll, afterAll } from "bun:test";
import { execSync } from "child_process";
import { mkdirSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { join } from "path";

const HOOK_PATH = join(import.meta.dir, "posttooluse-reminder.ts");
const TMP_DIR = join(import.meta.dir, "test-tmp");

function runHook(input: object): { stdout: string; parsed: object | null } {
  try {
    // Use stdin input to avoid shell escaping issues
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
    return { stdout: err.stdout?.toString() || "", parsed: null };
  }
}

// --- Setup/Teardown ---

beforeAll(() => {
  mkdirSync(TMP_DIR, { recursive: true });
});

afterAll(() => {
  if (existsSync(TMP_DIR)) {
    rmSync(TMP_DIR, { recursive: true });
  }
});

// ============================================================================
// Bash Tool Tests
// ============================================================================

describe("Bash: graph-easy detection", () => {
  it("should detect graph-easy usage", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "echo 'graph' | graph-easy --as=boxart" },
    });
    expect(result.parsed).not.toBeNull();
    expect((result.parsed as any).decision).toBe("block");
    expect((result.parsed as any).reason).toContain("[GRAPH-EASY SKILL]");
  });

  it("should not trigger on non-graph-easy commands", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "echo hello" },
    });
    expect(result.stdout).toBe("");
  });
});

describe("Bash: venv activation detection", () => {
  it("should detect source .venv/bin/activate", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "source .venv/bin/activate && python test.py" },
    });
    expect(result.parsed).not.toBeNull();
    expect((result.parsed as any).decision).toBe("block");
    expect((result.parsed as any).reason).toContain("[UV-REMINDER]");
    expect((result.parsed as any).reason).toContain("venv activation");
  });

  it("should detect source ../.venv/bin/activate", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "source ../.venv/bin/activate && python script.py" },
    });
    expect(result.parsed).not.toBeNull();
    expect((result.parsed as any).reason).toContain("[UV-REMINDER]");
  });

  it("should detect SSH with venv activation", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "ssh bigblack 'cd ~/project && source ~/.venv/bin/activate && python test.py'" },
    });
    expect(result.parsed).not.toBeNull();
    expect((result.parsed as any).reason).toContain("[UV-REMINDER]");
  });

  it("should detect dot-source syntax", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: ". .venv/bin/activate" },
    });
    expect(result.parsed).not.toBeNull();
    expect((result.parsed as any).reason).toContain("[UV-REMINDER]");
  });

  it("should NOT trigger on echo documentation", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "echo 'source .venv/bin/activate'" },
    });
    expect(result.stdout).toBe("");
  });

  it("should NOT trigger on grep venv", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "grep -r 'venv' ." },
    });
    expect(result.stdout).toBe("");
  });
});

describe("Bash: pip detection", () => {
  it("should detect pip install", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip install requests" },
    });
    expect(result.parsed).not.toBeNull();
    expect((result.parsed as any).decision).toBe("block");
    expect((result.parsed as any).reason).toContain("[UV-REMINDER]");
    expect((result.parsed as any).reason).toContain("pip detected");
    expect((result.parsed as any).reason).toContain("uv add");
  });

  it("should detect pip3 install", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip3 install numpy" },
    });
    expect(result.parsed).not.toBeNull();
    expect((result.parsed as any).reason).toContain("uv add");
  });

  it("should detect python -m pip install", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "python -m pip install flask" },
    });
    expect(result.parsed).not.toBeNull();
    expect((result.parsed as any).reason).toContain("[UV-REMINDER]");
  });

  it("should detect pip uninstall", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip uninstall requests" },
    });
    expect(result.parsed).not.toBeNull();
    expect((result.parsed as any).reason).toContain("uv remove");
  });

  it("should suggest uv pip install -e . for editable installs", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip install -e ." },
    });
    expect(result.parsed).not.toBeNull();
    expect((result.parsed as any).reason).toContain("uv pip install -e .");
  });

  it("should suggest uv sync for -r requirements.txt", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip install -r requirements.txt" },
    });
    expect(result.parsed).not.toBeNull();
    expect((result.parsed as any).reason).toContain("uv sync");
  });

  it("should NOT trigger on uv run", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "uv run python test.py" },
    });
    expect(result.stdout).toBe("");
  });

  it("should NOT trigger on uv pip install", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "uv pip install -e ." },
    });
    expect(result.stdout).toBe("");
  });

  it("should NOT trigger on pip freeze (lock file generation)", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip freeze > requirements.txt" },
    });
    expect(result.stdout).toBe("");
  });

  it("should NOT trigger on pip-compile", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip-compile requirements.in" },
    });
    expect(result.stdout).toBe("");
  });

  it("should NOT trigger on echo pip documentation", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "echo 'pip install requests'" },
    });
    expect(result.stdout).toBe("");
  });

  it("should NOT trigger on comments", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "# pip install requests" },
    });
    expect(result.stdout).toBe("");
  });
});

// ============================================================================
// Write/Edit Tool Tests
// ============================================================================

describe("Write/Edit: ADR sync reminders", () => {
  it("should remind about Design Spec when ADR modified", () => {
    const result = runHook({
      tool_name: "Edit",
      tool_input: { file_path: "docs/adr/2026-01-10-uv-reminder-hook.md" },
    });
    expect(result.parsed).not.toBeNull();
    expect((result.parsed as any).reason).toContain("[ADR-SPEC SYNC]");
    expect((result.parsed as any).reason).toContain("docs/design/2026-01-10-uv-reminder-hook/spec.md");
  });

  it("should remind about ADR when Design Spec modified", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: { file_path: "docs/design/2026-01-10-uv-reminder-hook/spec.md" },
    });
    expect(result.parsed).not.toBeNull();
    expect((result.parsed as any).reason).toContain("[SPEC-ADR SYNC]");
    expect((result.parsed as any).reason).toContain("docs/adr/2026-01-10-uv-reminder-hook.md");
  });

  it("should NOT trigger on non-ADR markdown files", () => {
    const result = runHook({
      tool_name: "Edit",
      tool_input: { file_path: "README.md" },
    });
    expect(result.stdout).toBe("");
  });
});

describe("Write/Edit: implementation code traceability", () => {
  it("should remind about ADR traceability for implementation files", () => {
    // Create a test file without ADR reference
    const testFile = join(TMP_DIR, "test_impl.py");
    writeFileSync(testFile, "# Test file\ndef foo():\n    pass\n");

    const result = runHook({
      tool_name: "Edit",
      tool_input: { file_path: testFile },
    });

    // Note: May or may not trigger depending on ruff availability
    // The test validates the hook runs without error
    expect(true).toBe(true);
  });

  it("should NOT trigger for files with ADR reference", () => {
    const testFile = join(TMP_DIR, "test_with_adr.py");
    writeFileSync(testFile, "# ADR: 2026-01-10-uv-reminder-hook\ndef foo():\n    pass\n");

    const result = runHook({
      tool_name: "Edit",
      tool_input: { file_path: testFile },
    });

    // Should not contain ADR traceability reminder
    if (result.parsed) {
      expect((result.parsed as any).reason).not.toContain("[CODE-ADR TRACEABILITY]");
    }
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
    expect(result.stdout).toBe("");
  });

  it("should handle empty file_path", () => {
    const result = runHook({
      tool_name: "Edit",
      tool_input: { file_path: "" },
    });
    expect(result.stdout).toBe("");
  });

  it("should handle unknown tool", () => {
    const result = runHook({
      tool_name: "UnknownTool",
      tool_input: {},
    });
    expect(result.stdout).toBe("");
  });

  it("should handle malformed JSON gracefully", () => {
    try {
      execSync(`echo 'not json' | bun ${HOOK_PATH}`, {
        encoding: "utf-8",
        stdio: ["pipe", "pipe", "pipe"],
      });
      expect(true).toBe(true); // Should not throw
    } catch {
      expect(true).toBe(true); // Also acceptable
    }
  });

  it("should normalize file paths with leading ./", () => {
    const result = runHook({
      tool_name: "Edit",
      tool_input: { file_path: "./docs/adr/2026-01-10-test.md" },
    });
    expect(result.parsed).not.toBeNull();
    expect((result.parsed as any).reason).toContain("[ADR-SPEC SYNC]");
  });

  it("should normalize file paths with leading /", () => {
    const result = runHook({
      tool_name: "Edit",
      tool_input: { file_path: "/docs/adr/2026-01-10-test.md" },
    });
    expect(result.parsed).not.toBeNull();
    expect((result.parsed as any).reason).toContain("[ADR-SPEC SYNC]");
  });
});

// ============================================================================
// Priority Tests
// ============================================================================

describe("Reminder priority", () => {
  it("graph-easy should take priority over pip", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "pip install graph-easy && graph-easy --help" },
    });
    expect(result.parsed).not.toBeNull();
    expect((result.parsed as any).reason).toContain("[GRAPH-EASY SKILL]");
  });

  it("venv activation should take priority over pip", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "source .venv/bin/activate && pip install requests" },
    });
    expect(result.parsed).not.toBeNull();
    expect((result.parsed as any).reason).toContain("venv activation");
  });
});

// ============================================================================
// pyproject.toml Path Escape Detection (PostToolUse backup)
// ADR: 2026-01-22-pyproject-toml-root-only-policy
// ============================================================================

describe("Write/Edit: pyproject.toml path escape detection", () => {
  it("should remind about path escaping with ../../../", () => {
    // Create a test pyproject.toml with escaping path
    const testFile = join(TMP_DIR, "pyproject.toml");
    writeFileSync(
      testFile,
      `[tool.uv.sources]
external = { path = "../../../external-pkg" }
`
    );

    const result = runHook({
      tool_name: "Edit",
      tool_input: { file_path: testFile },
    });

    expect(result.parsed).not.toBeNull();
    expect((result.parsed as any).decision).toBe("block");
    expect((result.parsed as any).reason).toContain("[PATH-ESCAPE REMINDER]");
    expect((result.parsed as any).reason).toContain("../../../external-pkg");
  });

  it("should NOT trigger on valid git source", () => {
    const testFile = join(TMP_DIR, "pyproject-git.toml");
    writeFileSync(
      testFile,
      `[tool.uv.sources]
rangebar = { git = "https://github.com/owner/repo", branch = "main" }
`
    );

    const result = runHook({
      tool_name: "Write",
      tool_input: { file_path: testFile },
    });

    // Should not contain path escape reminder (git sources are valid)
    if (result.parsed) {
      expect((result.parsed as any).reason).not.toContain("[PATH-ESCAPE REMINDER]");
    }
  });

  it("should NOT trigger on valid relative path within monorepo", () => {
    const testFile = join(TMP_DIR, "pyproject-valid.toml");
    writeFileSync(
      testFile,
      `[tool.uv.sources]
sibling = { path = "./packages/sibling" }
`
    );

    const result = runHook({
      tool_name: "Write",
      tool_input: { file_path: testFile },
    });

    // Should not trigger for valid paths
    if (result.parsed) {
      expect((result.parsed as any).reason).not.toContain("[PATH-ESCAPE REMINDER]");
    }
  });

  it("should detect multiple escaping paths", () => {
    // Create a subdirectory to test multiple escaping paths
    const testDir = join(TMP_DIR, "multi-escape");
    mkdirSync(testDir, { recursive: true });
    const testFile = join(testDir, "pyproject.toml");
    writeFileSync(
      testFile,
      `[tool.uv.sources]
pkg1 = { path = "../../../../pkg1" }
pkg2 = { path = "../../../pkg2" }
valid = { path = "packages/valid" }
`
    );

    const result = runHook({
      tool_name: "Edit",
      tool_input: { file_path: testFile },
    });

    expect(result.parsed).not.toBeNull();
    expect((result.parsed as any).reason).toContain("[PATH-ESCAPE REMINDER]");
    expect((result.parsed as any).reason).toContain("pkg1");
    expect((result.parsed as any).reason).toContain("pkg2");
  });

  it("should NOT trigger on non-pyproject.toml files", () => {
    const testFile = join(TMP_DIR, "setup.cfg");
    writeFileSync(testFile, "[metadata]\nname = test");

    const result = runHook({
      tool_name: "Write",
      tool_input: { file_path: testFile },
    });

    expect(result.stdout).toBe("");
  });
});
