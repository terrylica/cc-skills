#!/usr/bin/env bun
/**
 * Unit tests for process storm pattern detection.
 * Run with: bun test process-storm-patterns.test.mjs
 */

import { describe, test, expect } from "bun:test";
import { detectPatterns, PATTERNS, ESCAPE_HATCH, DEFAULT_CONFIG } from "./process-storm-patterns.mjs";

describe("Fork Bomb Patterns", () => {
  test("detects classic fork bomb :(){ :|:& };:", () => {
    const content = ':(){ :|:& };:';
    const findings = detectPatterns(content, DEFAULT_CONFIG.categories);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].category).toBe("fork_bomb");
    expect(findings[0].severity).toBe("critical");
  });

  test("detects while true with background spawn", () => {
    const content = 'while true; do ./script.sh & done';
    const findings = detectPatterns(content, DEFAULT_CONFIG.categories);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].category).toBe("fork_bomb");
  });
});

describe("gh Recursion Patterns", () => {
  test("detects gh auth token", () => {
    const content = 'TOKEN=$(gh auth token)';
    const findings = detectPatterns(content, DEFAULT_CONFIG.categories);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].category).toBe("gh_recursion");
    expect(findings[0].severity).toBe("critical");
  });

  test("detects gh api user", () => {
    const content = 'gh api user --jq .login';
    const findings = detectPatterns(content, DEFAULT_CONFIG.categories);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].category).toBe("gh_recursion");
  });

  test("detects GH_TOKEN=$(gh auth ...)", () => {
    const content = 'GH_TOKEN=$(gh auth token 2>/dev/null)';
    const findings = detectPatterns(content, DEFAULT_CONFIG.categories);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].category).toBe("gh_recursion");
  });
});

describe("mise Fork Patterns", () => {
  test("detects eval mise activate", () => {
    const content = 'eval "$(mise activate zsh)"';
    const findings = detectPatterns(content, DEFAULT_CONFIG.categories);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].category).toBe("mise_fork");
    expect(findings[0].severity).toBe("high");
  });
});

describe("Python Storm Patterns", () => {
  test("detects subprocess with shell=True", () => {
    const content = 'subprocess.run(cmd, shell=True)';
    const findings = detectPatterns(content, DEFAULT_CONFIG.categories);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].category).toBe("python_storm");
  });

  test("detects os.system()", () => {
    const content = 'os.system("ls -la")';
    const findings = detectPatterns(content, DEFAULT_CONFIG.categories);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].category).toBe("python_storm");
  });
});

describe("Escape Hatch", () => {
  test("allows content with PROCESS-STORM-OK comment", () => {
    const content = 'gh auth token  # PROCESS-STORM-OK';
    const findings = detectPatterns(content, DEFAULT_CONFIG.categories);
    expect(findings.length).toBe(0);
  });

  test("allows content with escape hatch on separate line", () => {
    const content = `# PROCESS-STORM-OK - intentional use
gh auth token`;
    const findings = detectPatterns(content, DEFAULT_CONFIG.categories);
    expect(findings.length).toBe(0);
  });
});

describe("Safe Patterns (No False Positives)", () => {
  test("allows regular gh commands", () => {
    const content = 'gh pr list';
    const findings = detectPatterns(content, DEFAULT_CONFIG.categories);
    expect(findings.length).toBe(0);
  });

  test("allows subprocess without shell=True", () => {
    const content = 'subprocess.run(["ls", "-la"])';
    const findings = detectPatterns(content, DEFAULT_CONFIG.categories);
    expect(findings.length).toBe(0);
  });

  test("allows normal for loops", () => {
    const content = 'for i in range(10): print(i)';
    const findings = detectPatterns(content, DEFAULT_CONFIG.categories);
    expect(findings.length).toBe(0);
  });
});
