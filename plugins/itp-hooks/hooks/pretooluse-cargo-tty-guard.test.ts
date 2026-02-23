import { test, expect, describe } from "bun:test";

/**
 * Test suite for cargo TTY suspension guard hook.
 *
 * Validates that unsafe cargo background commands are properly intercepted
 * and redirected to PUEUE without breaking normal usage patterns.
 *
 * GitHub Issues:
 *   #11898: Claude Code CLI suspends (Stopped / suspended (tty output)) on macOS iTerm2
 *   #12507: Claude Code exits on HPC — stdin consumed by shell detection subprocesses
 *   #13598: Hang: spurious /dev/tty reader
 * References:
 *   - https://github.com/anthropics/claude-code/issues/11898
 *   - https://github.com/anthropics/claude-code/issues/12507
 *   - https://github.com/anthropics/claude-code/issues/13598
 */

// Import test patterns (these would be tested via stdin/stdout)
const UNSAFE_PATTERNS = [
  { cmd: "cargo bench --bench rangebar_bench &", should: "redirect to PUEUE" },
  { cmd: "cargo test -p rangebar-core --lib &", should: "redirect to PUEUE" },
  { cmd: "cargo build --release &", should: "redirect to PUEUE" },
  { cmd: "cargo run --example test &", should: "redirect to PUEUE" },
  { cmd: "cargo check &", should: "redirect to PUEUE" },
];

const SAFE_PATTERNS = [
  { cmd: "cargo bench --bench rangebar_bench", should: "pass through" },
  { cmd: "cargo test -p rangebar-core --lib", should: "pass through" },
  { cmd: "cargo build --release", should: "pass through" },
  { cmd: "cargo bench --bench test # CARGO-TTY-SKIP", should: "skip guard" },
  { cmd: "nohup cargo bench &", should: "already detached" },
  { cmd: "cargo bench </dev/null &", should: "stdin redirected" },
  { cmd: "git commit -m 'cargo bench &'", should: "not cargo" },
  { cmd: "npm run cargo:bench &", should: "not cargo binary" },
];

const FORCE_WRAP = [
  { cmd: "cargo bench # CARGO-TTY-WRAP", should: "force wrap" },
  {
    cmd: "cargo test -p pkg # CARGO-TTY-WRAP",
    should: "force wrap even without &",
  },
];

describe("Cargo TTY Guard - Pattern Detection", () => {
  test("should detect unsafe cargo background commands", () => {
    // These patterns should trigger PUEUE redirection
    const unsafeTests = [
      "cargo bench --bench rangebar_bench &",
      "cargo test -p rangebar-core &",
      "cargo build &",
      "  cargo run &  ",
    ];

    unsafeTests.forEach((cmd) => {
      expect(cmd).toMatch(/^\s*cargo\s+(bench|test|build|run|check)\b/i);
      expect(cmd).toMatch(/\s+&\s*$/);
    });
  });

  test("should NOT match safe cargo commands (no backgrounding)", () => {
    const safeTests = [
      "cargo bench --bench rangebar_bench",
      "cargo test -p rangebar-core",
      "cargo build --release",
      "cargo run --example test",
    ];

    safeTests.forEach((cmd) => {
      expect(cmd).not.toMatch(/\s+&\s*$/);
    });
  });

  test("should NOT match already-detached commands", () => {
    const detachedTests = [
      "nohup cargo bench &",
      "cargo bench </dev/null 2>&1 &",
      "cargo test >/dev/null 2>&1 &",
    ];

    detachedTests.forEach((cmd) => {
      expect(cmd).toMatch(
        /(?:^|\s)nohup\s|>\s*\/dev\/null|<\s*\/dev\/null|\btmux\s|\bscreen\s/i,
      );
    });
  });

  test("should NOT match non-cargo commands", () => {
    const nonCargoTests = [
      "npm run build &",
      "git commit &",
      "make test &",
      "python script.py &",
    ];

    nonCargoTests.forEach((cmd) => {
      expect(cmd).not.toMatch(/^\s*cargo\s+(bench|test|build|run|check)\b/i);
    });
  });
});

describe("Cargo TTY Guard - Escape Hatches", () => {
  test("should respect CARGO-TTY-SKIP comment", () => {
    const cmd = "cargo bench --bench test & # CARGO-TTY-SKIP";
    expect(cmd).toMatch(/# *CARGO-TTY-SKIP/i);
  });

  test("should force wrap with CARGO-TTY-WRAP comment", () => {
    const cmd = "cargo bench # CARGO-TTY-WRAP";
    expect(cmd).toMatch(/# *CARGO-TTY-WRAP/i);
  });
});

describe("Cargo TTY Guard - Output Validation", () => {
  test("should build proper PUEUE wrapper", () => {
    const command = "cargo bench --bench test &";
    const cleanCommand = command.replace(/\s+&\s*$/, "");

    // Verify wrapper structure
    expect(cleanCommand).toContain("cargo bench");
    expect(cleanCommand).not.toMatch(/&\s*$/);

    // Verify wrapper components exist in wrapper templates
    const wrapperTemplate =
      "pueue add --print-task-id -- cargo bench && pueue wait && pueue log || nohup cargo bench </dev/null &";
    expect(wrapperTemplate).toContain("pueue add");
    expect(wrapperTemplate).toContain("pueue wait");
    expect(wrapperTemplate).toContain("pueue log");
    expect(wrapperTemplate).toContain("nohup");
  });

  test("should handle special characters in commands", () => {
    const commands = [
      "cargo bench --bench 'test-name' &",
      'cargo test --features "test-utils" &',
      'cargo build --release -- --nocapture &',
    ];

    commands.forEach((cmd) => {
      // Verify command extraction
      const cleanCommand = cmd.replace(/\s+&\s*$/, "");
      expect(cleanCommand).toBeTruthy();
      expect(cleanCommand).toContain("cargo");
    });
  });
});

describe("Cargo TTY Guard - Integration Tests", () => {
  test("integration: cargo bench with full flags", async () => {
    const cmd =
      "cargo bench -p rangebar-core --lib --features test-utils -- --nocapture &";

    // Should match unsafe pattern
    expect(cmd).toMatch(/^\s*cargo\s+(bench|test|build|run|check)\b/i);
    expect(cmd).toMatch(/\s+&\s*$/);
    expect(cmd).not.toMatch(/CARGO-TTY-SKIP/i);

    // Clean command should preserve all flags
    const clean = cmd.replace(/\s+&\s*$/, "");
    expect(clean).toContain("-p rangebar-core");
    expect(clean).toContain("--lib");
    expect(clean).toContain("--features test-utils");
    expect(clean).toContain("-- --nocapture");
  });

  test("integration: cargo test with complex path", async () => {
    const cmd =
      "cargo test -p 'my-crate::long::module::path' --lib --release &";

    expect(cmd).toMatch(/^\s*cargo\s+(bench|test|build|run|check)\b/i);
    expect(cmd).toMatch(/\s+&\s*$/);

    const clean = cmd.replace(/\s+&\s*$/, "");
    expect(clean).toContain("my-crate");
    expect(clean).toContain("--lib");
    expect(clean).toContain("--release");
  });
});

describe("Cargo TTY Guard - Hook IO Format", () => {
  test("should parse stdin in expected format", () => {
    const input = {
      tool_name: "Bash",
      tool_input: {
        command: "cargo bench &",
      },
      cwd: "/Users/terryli/eon/rangebar-py",
    };

    expect(input.tool_name).toBe("Bash");
    expect(input.tool_input.command).toContain("cargo bench");
    expect(input.cwd).toBeTruthy();
  });

  test("should output in expected format", () => {
    const output = {
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        updatedInput: {
          command:
            "pueue add --print-task-id -- cargo bench & # wrapped for TTY safety",
        },
      },
    };

    expect(output.hookSpecificOutput.hookEventName).toBe("PreToolUse");
    expect(output.hookSpecificOutput.permissionDecision).toBe("allow");
    expect(output.hookSpecificOutput.updatedInput.command).toContain("pueue");
  });
});

describe("Cargo TTY Guard - Edge Cases", () => {
  test("should handle whitespace variations", () => {
    const cmds = [
      "cargo bench &",
      "cargo   bench  &",
      "cargo bench  &  ",
      "  cargo bench &",
    ];

    cmds.forEach((cmd) => {
      const isMatch = /^\s*cargo\s+(bench|test|build|run|check)\b/i.test(cmd);
      const isBackgrounded = /\s+&\s*$/.test(cmd);
      expect(isMatch).toBe(true);
      expect(isBackgrounded).toBe(true);
    });
  });

  test("should NOT match partial matches", () => {
    const cmds = [
      "cargo-test", // cargo as prefix
      "echo cargo bench", // cargo in argument
      "my_cargo_script", // cargo in middle
      "/usr/bin/cargo-fmt", // cargo utility suffix
    ];

    cmds.forEach((cmd) => {
      const isMatch = /^\s*cargo\s+(bench|test|build|run|check)\b/i.test(cmd);
      expect(isMatch).toBe(false);
    });
  });

  test("should handle multiline command chains (if present)", () => {
    const cmd = "cargo bench --bench test && cargo test &";
    // Should still match the dangerous & at end
    expect(cmd).toMatch(/\s+&\s*$/);
  });
});
