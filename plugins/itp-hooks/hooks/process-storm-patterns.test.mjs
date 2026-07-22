#!/usr/bin/env bun
/**
 * Unit tests for process storm pattern detection.
 * Run with: bun test process-storm-patterns.test.mjs
 *
 * GitHub Issue: https://github.com/anthropics/claude-code/issues/13439
 *
 * PROCESS-STORM-OK: this test file necessarily contains the very fixture
 * strings the guard matches (token captures, credential.helper recursion), so
 * it self-exempts from the process-storm PreToolUse guard.
 */

import { describe, test, expect } from "bun:test";
// Iter-111: dropped unused `ESCAPE_HATCH` import — the @deprecated raw-regex
// export was preserved across iter-109 / iter-110 for backward compatibility
// but had no actual test consumer (the suite exercises the helper indirectly
// through `detectPatterns`, which delegates to the iter-107 canonical helper).
import { detectPatterns, PATTERNS, DEFAULT_CONFIG } from "./process-storm-patterns.mjs";

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

// PROCESS-STORM-OK: the fixtures in this block intentionally contain the
// token-capture / credential-helper strings the guard matches.
describe("gh token capture is NOT a storm (issue #91)", () => {
  // Capturing a token into a variable is a one-shot read, not recursion. The
  // former gh_recursion capture patterns only produced false positives; the
  // real recursion vector is covered by credential_storm (asserted below).
  test("does NOT flag TOKEN=$(gh auth token) capture", () => {
    const findings = detectPatterns("TOKEN=$(gh auth token)", DEFAULT_CONFIG.categories);
    expect(findings.length).toBe(0);
  });

  test("does NOT flag the canonical multi-identity push", () => {
    const content = 'export GH_TOKEN="$(gh auth token)" && git push origin main';
    const findings = detectPatterns(content, DEFAULT_CONFIG.categories);
    expect(findings.length).toBe(0);
  });

  test("does NOT flag GITHUB_TOKEN=$(gh auth ...) capture", () => {
    const findings = detectPatterns("GITHUB_TOKEN=$(gh auth token 2>/dev/null)", DEFAULT_CONFIG.categories);
    expect(findings.length).toBe(0);
  });

  test("does NOT flag a heredoc/doc that merely mentions $(gh auth token)", () => {
    const content = "cat <<EOF\nRun: export GH_TOKEN=$(gh auth token)\nEOF";
    const findings = detectPatterns(content, DEFAULT_CONFIG.categories);
    expect(findings.length).toBe(0);
  });

  test("does NOT flag direct gh api (safe from Bash tool)", () => {
    const findings = detectPatterns("gh api user --jq .login", DEFAULT_CONFIG.categories);
    expect(findings.length).toBe(0);
  });

  test("STILL flags real credential-helper recursion (credential_storm)", () => {
    const content = "git config credential.helper '!gh auth token'";
    const findings = detectPatterns(content, DEFAULT_CONFIG.categories);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].category).toBe("credential_storm");
    expect(findings[0].severity).toBe("critical");
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
