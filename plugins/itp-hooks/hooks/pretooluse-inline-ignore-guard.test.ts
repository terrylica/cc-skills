import { describe, test, expect } from "bun:test";
import { resolve } from "path";

const HOOK_PATH = resolve(__dirname, "pretooluse-inline-ignore-guard.ts");

interface HookOutput {
  hookSpecificOutput?: {
    hookEventName: string;
    permissionDecision: string;
    permissionDecisionReason?: string;
  };
}

async function runHook(input: object): Promise<{ exitCode: number; output: HookOutput | null }> {
  const proc = Bun.spawn(["bun", HOOK_PATH], {
    stdin: new Blob([JSON.stringify(input)]),
    stdout: "pipe",
    stderr: "pipe",
  });

  const stdout = await new Response(proc.stdout).text();
  const exitCode = await proc.exited;

  let output: HookOutput | null = null;
  try {
    output = JSON.parse(stdout.trim());
  } catch {
    // No JSON output = allow
  }

  return { exitCode, output };
}

function writeInput(filePath: string, content: string) {
  return {
    tool_name: "Write",
    tool_input: { file_path: filePath, content },
    session_id: "test-session",
  };
}

function editInput(filePath: string, oldString: string, newString: string) {
  return {
    tool_name: "Edit",
    tool_input: { file_path: filePath, old_string: oldString, new_string: newString },
    session_id: "test-session",
  };
}

// ============================================================================
// Python: DENY cases
// ============================================================================

describe("Python inline ignores — DENY", () => {
  test("denies # noqa in .py Write", async () => {
    const { output } = await runHook(writeInput("/tmp/test.py", "import os  # noqa\n"));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("deny");
    expect(output?.hookSpecificOutput?.permissionDecisionReason).toContain("INLINE-IGNORE-GUARD");
  });

  test("denies # noqa: E501 in .py Write", async () => {
    const { output } = await runHook(writeInput("/tmp/test.py", "x = 1  # noqa: E501\n"));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("deny");
  });

  test("denies # type: ignore in .py Write", async () => {
    const { output } = await runHook(writeInput("/tmp/test.py", "x: int = foo()  # type: ignore\n"));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("deny");
  });

  test("denies # type: ignore[xxx] in .py Write", async () => {
    const { output } = await runHook(writeInput("/tmp/test.py", "x = foo()  # type: ignore[assignment]\n"));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("deny");
  });

  test("denies # ty: ignore in .py Write", async () => {
    const { output } = await runHook(writeInput("/tmp/test.py", "x = foo()  # ty: ignore\n"));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("deny");
  });

  test("denies # ty: ignore[xxx] in .pyi Write", async () => {
    const { output } = await runHook(writeInput("/tmp/test.pyi", "x = foo()  # ty: ignore[unresolved-import]\n"));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("deny");
  });

  test("denies net-new # noqa in Edit", async () => {
    const { output } = await runHook(editInput(
      "/tmp/test.py",
      "import os\n",
      "import os  # noqa: F401\n",
    ));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("deny");
  });
});

// ============================================================================
// JS/TS: DENY cases
// ============================================================================

describe("JS/TS inline ignores — DENY", () => {
  test("denies // eslint-disable-next-line in .ts Write", async () => {
    const { output } = await runHook(writeInput("/tmp/test.ts", "// eslint-disable-next-line no-unused-vars\nconst x = 1;\n"));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("deny");
  });

  test("denies // eslint-disable-line in .js Write", async () => {
    const { output } = await runHook(writeInput("/tmp/test.js", "const x = 1; // eslint-disable-line\n"));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("deny");
  });

  test("denies // biome-ignore in .tsx Write", async () => {
    const { output } = await runHook(writeInput("/tmp/test.tsx", "// biome-ignore lint/style/noUnusedVariables\n"));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("deny");
  });

  test("denies // oxlint-ignore in .mjs Write", async () => {
    const { output } = await runHook(writeInput("/tmp/test.mjs", "// oxlint-ignore no-unused-vars\n"));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("deny");
  });

  test("denies /* eslint-disable */ in .jsx Write", async () => {
    const { output } = await runHook(writeInput("/tmp/test.jsx", "/* eslint-disable */\nconst x = 1;\n"));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("deny");
  });
});

// ============================================================================
// ALLOW cases
// ============================================================================

describe("ALLOW cases", () => {
  test("allows clean Python code", async () => {
    const { output } = await runHook(writeInput("/tmp/test.py", "import os\nprint(os.getcwd())\n"));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("allow");
  });

  test("allows clean TypeScript code", async () => {
    const { output } = await runHook(writeInput("/tmp/test.ts", "const x = 1;\nconsole.log(x);\n"));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("allow");
  });

  test("allows unsupported extension (.rs)", async () => {
    const { output } = await runHook(writeInput("/tmp/test.rs", "// noqa should not trigger for Rust\n"));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("allow");
  });

  test("allows unsupported extension (.go)", async () => {
    const { output } = await runHook(writeInput("/tmp/test.go", "// nolint:unused\n"));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("allow");
  });

  test("allows INLINE-IGNORE-OK escape hatch (Python)", async () => {
    const { output } = await runHook(writeInput("/tmp/test.py", "import pysbd  # type: ignore[import]  # INLINE-IGNORE-OK\n"));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("allow");
  });

  test("allows INLINE-IGNORE-OK escape hatch (JS)", async () => {
    const { output } = await runHook(writeInput("/tmp/test.ts", "// eslint-disable-next-line no-any // INLINE-IGNORE-OK\n"));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("allow");
  });

  test("allows Edit with pre-existing # noqa (no net-new)", async () => {
    const { output } = await runHook(editInput(
      "/tmp/test.py",
      "import os  # noqa: F401\n",
      "import os  # noqa: F401  # updated comment\n",
    ));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("allow");
  });

  test("allows Edit that removes an inline ignore", async () => {
    const { output } = await runHook(editInput(
      "/tmp/test.py",
      "import os  # noqa: F401\n",
      "import os\n",
    ));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("allow");
  });

  test("allows non-Write/Edit tools", async () => {
    const { output } = await runHook({
      tool_name: "Bash",
      tool_input: { command: "echo '# noqa'" },
      session_id: "test-session",
    });
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("allow");
  });

  test("allows plan mode", async () => {
    const { output } = await runHook({
      tool_name: "Write",
      tool_input: { file_path: "/tmp/test.py", content: "x = 1  # noqa\n" },
      session_id: "test-session",
      permission_mode: "plan",
    });
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("allow");
  });

  test("allows empty content", async () => {
    const { output } = await runHook(writeInput("/tmp/test.py", ""));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("allow");
  });

  test("allows config files (.json, .toml)", async () => {
    const { output } = await runHook(writeInput("/tmp/ruff.toml", '# noqa not relevant in toml\n'));
    expect(output?.hookSpecificOutput?.permissionDecision).toBe("allow");
  });
});

// ============================================================================
// Deny message content
// ============================================================================

describe("deny message content", () => {
  test("includes 3-tier hierarchy in deny message", async () => {
    const { output } = await runHook(writeInput("/tmp/test.py", "x = 1  # noqa\n"));
    const reason = output?.hookSpecificOutput?.permissionDecisionReason || "";
    expect(reason).toContain("FIX THE ERROR");
    expect(reason).toContain("CONFIG-LEVEL IGNORE");
    expect(reason).toContain("NEVER");
    expect(reason).toContain("ruff.toml");
  });

  test("includes JS config guidance for .ts files", async () => {
    const { output } = await runHook(writeInput("/tmp/test.ts", "// eslint-disable-next-line\n"));
    const reason = output?.hookSpecificOutput?.permissionDecisionReason || "";
    expect(reason).toContain("oxlint");
    expect(reason).toContain("biome");
  });

  test("shows sample lines in deny message", async () => {
    const { output } = await runHook(writeInput("/tmp/test.py", "x = 1  # noqa: E501\ny = 2\n"));
    const reason = output?.hookSpecificOutput?.permissionDecisionReason || "";
    expect(reason).toContain("Line 1");
    expect(reason).toContain("# noqa: E501");
  });
});
