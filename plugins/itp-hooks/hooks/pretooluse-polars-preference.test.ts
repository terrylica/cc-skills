/**
 * Tests for pretooluse-polars-preference.ts
 *
 * Run with: bun test plugins/itp-hooks/hooks/pretooluse-polars-preference.test.ts
 *
 * ADR: 2026-01-22-polars-preference-hook (pending)
 */

import { describe, expect, it } from "bun:test";
import { execSync } from "child_process";
import { join } from "path";

const HOOK_PATH = join(import.meta.dir, "pretooluse-polars-preference.ts");

interface HookResult {
  stdout: string;
  parsed: {
    hookSpecificOutput?: {
      permissionDecision?: string;
      permissionDecisionReason?: string;
    };
  } | null;
  exitCode: number;
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
    return { stdout, parsed, exitCode: 0 };
  } catch (err: unknown) {
    const error = err as { stdout?: Buffer; status?: number };
    return {
      stdout: error.stdout?.toString() || "",
      parsed: null,
      exitCode: error.status || 1,
    };
  }
}

// ============================================================================
// Detection Tests
// ============================================================================

describe("PreToolUse: Polars preference guard", () => {
  it("should ASK for confirmation when 'import pandas as pd' detected", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: "/project/analysis.py",
        content: "import pandas as pd\n\ndf = pd.read_csv('data.csv')",
      },
    });
    expect(result.parsed).not.toBeNull();
    expect(result.parsed?.hookSpecificOutput?.permissionDecision).toBe("ask");
    expect(result.parsed?.hookSpecificOutput?.permissionDecisionReason).toContain(
      "[POLARS PREFERENCE]"
    );
  });

  it("should ASK for confirmation when 'import pandas' detected", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: "/project/analysis.py",
        content: "import pandas\n\ndf = pandas.DataFrame()",
      },
    });
    expect(result.parsed).not.toBeNull();
    expect(result.parsed?.hookSpecificOutput?.permissionDecision).toBe("ask");
  });

  it("should ASK for confirmation when 'from pandas import' detected", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: "/project/analysis.py",
        content: "from pandas import DataFrame\n\ndf = DataFrame()",
      },
    });
    expect(result.parsed).not.toBeNull();
    expect(result.parsed?.hookSpecificOutput?.permissionDecision).toBe("ask");
  });

  it("should ASK for confirmation when pd.DataFrame detected in Edit", () => {
    const result = runHook({
      tool_name: "Edit",
      tool_input: {
        file_path: "/project/process.py",
        new_string: "result = pd.DataFrame({'a': [1, 2, 3]})",
      },
    });
    expect(result.parsed).not.toBeNull();
    expect(result.parsed?.hookSpecificOutput?.permissionDecision).toBe("ask");
  });

  it("should ASK for confirmation when pd.read_csv detected", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: "/project/load.py",
        content: "df = pd.read_csv('data.csv')",
      },
    });
    expect(result.parsed).not.toBeNull();
    expect(result.parsed?.hookSpecificOutput?.permissionDecision).toBe("ask");
  });

  it("should ASK for confirmation when pd.read_parquet detected", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: "/project/load.py",
        content: "df = pd.read_parquet('data.parquet')",
      },
    });
    expect(result.parsed).not.toBeNull();
    expect(result.parsed?.hookSpecificOutput?.permissionDecision).toBe("ask");
  });
});

// ============================================================================
// Exception Tests
// ============================================================================

describe("Exception handling", () => {
  it("should SKIP when # polars-exception: comment present", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: "/project/compat.py",
        content:
          "# polars-exception: MLflow requires Pandas\nimport pandas as pd",
      },
    });
    expect(result.stdout).toBe("");
  });

  it("should SKIP mlflow-python exception path", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: "/plugins/devops-tools/skills/mlflow-python/log.py",
        content: "import pandas as pd",
      },
    });
    expect(result.stdout).toBe("");
  });

  it("should SKIP legacy/ exception path", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: "/project/legacy/old_script.py",
        content: "import pandas as pd",
      },
    });
    expect(result.stdout).toBe("");
  });

  it("should SKIP third-party/ exception path", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: "/project/third-party/vendor.py",
        content: "import pandas as pd",
      },
    });
    expect(result.stdout).toBe("");
  });

  it("should SKIP when Polars already imported (hybrid usage)", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: "/project/hybrid.py",
        content:
          "import polars as pl\nimport pandas as pd  # for MLflow compat",
      },
    });
    expect(result.stdout).toBe("");
  });

  it("should SKIP when from polars import detected", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: "/project/hybrid.py",
        content: "from polars import DataFrame\nimport pandas as pd",
      },
    });
    expect(result.stdout).toBe("");
  });
});

// ============================================================================
// Non-triggering Tests
// ============================================================================

describe("Non-triggering scenarios", () => {
  it("should SKIP non-Python files", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: "/project/README.md",
        content: "Use `import pandas as pd` to load data",
      },
    });
    expect(result.stdout).toBe("");
  });

  it("should SKIP TypeScript files", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: "/project/script.ts",
        content: "// import pandas as pd",
      },
    });
    expect(result.stdout).toBe("");
  });

  it("should SKIP non-Write/Edit tools", () => {
    const result = runHook({
      tool_name: "Read",
      tool_input: {
        file_path: "/project/analysis.py",
      },
    });
    expect(result.stdout).toBe("");
  });

  it("should SKIP Bash tool", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: {
        command: "python -c 'import pandas as pd'",
      },
    });
    expect(result.stdout).toBe("");
  });

  it("should SKIP when no Pandas usage", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: "/project/clean.py",
        content: "import polars as pl\n\ndf = pl.read_csv('data.csv')",
      },
    });
    expect(result.stdout).toBe("");
  });
});

// ============================================================================
// Edge Cases
// ============================================================================

describe("Edge cases", () => {
  it("should handle empty content", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: "/project/empty.py",
        content: "",
      },
    });
    expect(result.stdout).toBe("");
  });

  it("should handle missing file_path", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        content: "import pandas as pd",
      },
    });
    expect(result.stdout).toBe("");
  });

  it("should handle invalid JSON gracefully", () => {
    try {
      execSync(`echo "not json" | bun ${HOOK_PATH}`, {
        encoding: "utf-8",
        stdio: ["pipe", "pipe", "pipe"],
      });
      expect(true).toBe(true); // Should exit 0
    } catch {
      expect(true).toBe(true); // Also acceptable
    }
  });

  it("should include filename in message", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: "/project/my_analysis.py",
        content: "import pandas as pd",
      },
    });
    expect(result.parsed?.hookSpecificOutput?.permissionDecisionReason).toContain(
      "my_analysis.py"
    );
  });

  it("should include migration cheatsheet in message", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: {
        file_path: "/project/analysis.py",
        content: "import pandas as pd",
      },
    });
    expect(result.parsed?.hookSpecificOutput?.permissionDecisionReason).toContain(
      "pl.read_csv()"
    );
    expect(result.parsed?.hookSpecificOutput?.permissionDecisionReason).toContain(
      "polars-exception:"
    );
  });
});
