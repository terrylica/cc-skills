#!/usr/bin/env bun
// # PROCESS-STORM-OK
/**
 * Tests for shell-script-safety-detector-status-loss-and-masked-substitution-iter119.ts
 *
 * Comprehensive coverage of both RULE 1 (STATUS-LOSS-AFTER-IF) and RULE 2 (MASKED-COMMAND-SUBSTITUTION),
 * including all empirical facts A-H from the requirements (explicit named cases).
 *
 * Key test strategies:
 *   - Rule 1: Test both positive (should flag) and negative (must NOT flag) cases
 *   - Rule 2: Test declaration keywords + command subs, with arithmetic exception
 *   - Escape hatch: File-wide SHELL-SAFETY-OK marker suppresses both rules
 *   - File detection: Extension-based (.sh/.bash/.zsh) + shebang-based
 */

import { describe, it, expect } from "bun:test";
import {
  detectShellStatusLossDefects,
  detectShellMaskedCommandSubstitutionDefects,
  detectAllShellSafetyDefects,
  isShellScript,
} from "./shell-script-safety-detector-status-loss-and-masked-substitution-iter119.ts";

// ============================================================================
// File Detection Tests
// ============================================================================

describe("isShellScript", () => {
  it("detects .sh files as shell scripts", () => {
    expect(isShellScript("/path/to/script.sh", "echo hello")).toBe(true);
  });

  it("detects .bash files as shell scripts", () => {
    expect(isShellScript("/path/to/script.bash", "echo hello")).toBe(true);
  });

  it("detects .zsh files as shell scripts", () => {
    expect(isShellScript("/path/to/script.zsh", "echo hello")).toBe(true);
  });

  it("detects bash shebang in extensionless files", () => {
    expect(isShellScript("/path/to/myscript", "#!/usr/bin/env bash\necho hello")).toBe(true);
  });

  it("detects sh shebang in extensionless files", () => {
    expect(isShellScript("/path/to/myscript", "#!/bin/sh\necho hello")).toBe(true);
  });

  it("detects zsh shebang in extensionless files", () => {
    expect(isShellScript("/path/to/myscript", "#!/usr/bin/zsh\necho hello")).toBe(true);
  });

  it("skips .bak files (test counter-examples)", () => {
    expect(isShellScript("/path/to/script.sh.bak", "echo hello")).toBe(false);
  });

  it("skips /fixtures/ directories", () => {
    expect(isShellScript("/path/to/fixtures/script.sh", "echo hello")).toBe(false);
  });

  it("skips /tests/fixtures/ directories", () => {
    expect(isShellScript("/path/to/tests/fixtures/script.sh", "echo hello")).toBe(false);
  });

  it("rejects non-shell extensions", () => {
    expect(isShellScript("/path/to/script.py", "echo hello")).toBe(false);
  });
});

// ============================================================================
// RULE 1: STATUS-LOSS-AFTER-IF Tests
// ============================================================================

describe("detectShellStatusLossDefects — RULE 1: STATUS-LOSS-AFTER-IF", () => {
  // ─────────────────────────────────────────────────────────────
  // POSITIVE CASES (should flag)
  // ─────────────────────────────────────────────────────────────

  it("flags $? after fi with no else (RULE 1 positive: fact A)", () => {
    const script = `#!/bin/bash
if [[ -f /tmp/file ]]; then
  echo "exists"
fi
rc=$?
echo "result: $rc"`;
    const defects = detectShellStatusLossDefects("/test.sh", script);
    expect(defects).toHaveLength(1);
    expect(defects[0]?.rule).toBe("STATUS-LOSS-AFTER-IF");
    expect(defects[0]?.lineNumber).toBe(5);
  });

  it("flags $? used inside string after fi with no else", () => {
    const script = `#!/bin/bash
if cmd1; then
  true
fi
log "failed (exit $?)"`;
    const defects = detectShellStatusLossDefects("/test.sh", script);
    expect(defects.length).toBeGreaterThan(0);
    expect(defects[0]?.rule).toBe("STATUS-LOSS-AFTER-IF");
  });

  it("flags $? in test expression after fi with no else", () => {
    const script = `#!/bin/bash
if test -z "$1"; then
  echo "empty"
fi
if [[ $? -eq 0 ]]; then
  echo "ok"
fi`;
    const defects = detectShellStatusLossDefects("/test.sh", script);
    expect(defects.length).toBeGreaterThan(0);
  });

  it("flags multiple $? usages across different if blocks", () => {
    const script = `#!/bin/bash
if cmd1; then
  x=1
fi
rc=$?

if cmd2; then
  y=2
fi
another=$?`;
    const defects = detectShellStatusLossDefects("/test.sh", script);
    expect(defects.length).toBe(2);
  });

  // ─────────────────────────────────────────────────────────────
  // NEGATIVE CASES (must NOT flag)
  // ─────────────────────────────────────────────────────────────

  it("does NOT flag $? INSIDE an else branch (RULE 1 negative: fact B)", () => {
    const script = `#!/bin/bash
if cmd; then
  echo "success"
else
  rc=$?
  echo "failed: $rc"
fi`;
    const defects = detectShellStatusLossDefects("/test.sh", script);
    expect(defects).toHaveLength(0);
  });

  it("does NOT flag `local rc=$?` due to early expansion (RULE 1 negative: fact C)", () => {
    const script = `#!/bin/bash
if cmd; then
  true
else
  x=1
fi
local rc=$?`;
    const defects = detectShellStatusLossDefects("/test.sh", script);
    // This is actually a RULE 2 issue (masked substitution), not RULE 1
    // So RULE 1 should return empty because the if has an else clause
    const rule1Only = defects.filter((d) => d.rule === "STATUS-LOSS-AFTER-IF");
    expect(rule1Only).toHaveLength(0);
  });

  it("does NOT flag $? after done (RULE 1 negative: fact G)", () => {
    const script = `#!/bin/bash
for file in *; do
  process "$file"
done
rc=$?`;
    const defects = detectShellStatusLossDefects("/test.sh", script);
    expect(defects).toHaveLength(0);
  });

  it("does NOT flag $? after esac (RULE 1 negative: fact G)", () => {
    const script = `#!/bin/bash
case "$1" in
  a) echo "a" ;;
  b) echo "b" ;;
esac
status=$?`;
    const defects = detectShellStatusLossDefects("/test.sh", script);
    expect(defects).toHaveLength(0);
  });

  it("does NOT flag $? after closing brace } (RULE 1 negative: fact H)", () => {
    const script = `#!/bin/bash
{
  cmd1
  cmd2
}
result=$?`;
    const defects = detectShellStatusLossDefects("/test.sh", script);
    expect(defects).toHaveLength(0);
  });

  it("does NOT flag $? when if block HAS elif", () => {
    const script = `#!/bin/bash
if [[ $x == 1 ]]; then
  echo "one"
elif [[ $x == 2 ]]; then
  echo "two"
fi
rc=$?`;
    const defects = detectShellStatusLossDefects("/test.sh", script);
    expect(defects).toHaveLength(0);
  });

  it("does NOT flag $? when if block HAS else", () => {
    const script = `#!/bin/bash
if [[ -f file ]]; then
  cat file
else
  echo "not found"
fi
status=$?`;
    const defects = detectShellStatusLossDefects("/test.sh", script);
    expect(defects).toHaveLength(0);
  });

  it("does NOT flag when if-fi are nested (inner if without else)", () => {
    const script = `#!/bin/bash
if outer; then
  if inner; then
    echo "yes"
  fi
  rc=$?
fi`;
    const defects = detectShellStatusLossDefects("/test.sh", script);
    // The inner if has NO else, so the first $? after its fi SHOULD be flagged
    // This is expected behavior - the inner if block loses status
    expect(defects.length).toBeGreaterThan(0);
    expect(defects[0]?.lineNumber).toBe(6);
  });

  it("handles multi-line if/fi correctly", () => {
    const script = `#!/bin/bash
if \\
  test -z "$1"; then
  echo "arg required"
fi
rc=$?`;
    const defects = detectShellStatusLossDefects("/test.sh", script);
    expect(defects.length).toBeGreaterThan(0);
  });
});

// ============================================================================
// RULE 2: MASKED-COMMAND-SUBSTITUTION Tests
// ============================================================================

describe("detectShellMaskedCommandSubstitutionDefects — RULE 2: MASKED-COMMAND-SUBSTITUTION", () => {
  // ─────────────────────────────────────────────────────────────
  // POSITIVE CASES (should flag)
  // ─────────────────────────────────────────────────────────────

  it("flags local with command substitution (RULE 2 positive: fact D)", () => {
    const script = `#!/bin/bash
local out=$(cmd)`;
    const defects = detectShellMaskedCommandSubstitutionDefects("/test.sh", script);
    expect(defects).toHaveLength(1);
    expect(defects[0]?.rule).toBe("MASKED-COMMAND-SUBSTITUTION");
    expect(defects[0]?.lineNumber).toBe(2);
  });

  it("flags export with command substitution", () => {
    const script = `#!/bin/bash
export VAR=$(some_command)`;
    const defects = detectShellMaskedCommandSubstitutionDefects("/test.sh", script);
    expect(defects).toHaveLength(1);
    expect(defects[0]?.rule).toBe("MASKED-COMMAND-SUBSTITUTION");
  });

  it("flags readonly with command substitution", () => {
    const script = `#!/bin/bash
readonly VERSION=$(git describe --tags)`;
    const defects = detectShellMaskedCommandSubstitutionDefects("/test.sh", script);
    expect(defects).toHaveLength(1);
  });

  it("flags declare with command substitution", () => {
    const script = `#!/bin/bash
declare out=$(some_cmd)`;
    const defects = detectShellMaskedCommandSubstitutionDefects("/test.sh", script);
    expect(defects).toHaveLength(1);
  });

  it("flags typeset with command substitution", () => {
    const script = `#!/bin/bash
typeset result=$(echo hello)`;
    const defects = detectShellMaskedCommandSubstitutionDefects("/test.sh", script);
    expect(defects).toHaveLength(1);
  });

  it("flags backtick command substitution with local", () => {
    const script = `#!/bin/bash
local out=\`cmd\``;
    const defects = detectShellMaskedCommandSubstitutionDefects("/test.sh", script);
    expect(defects).toHaveLength(1);
    expect(defects[0]?.statement).toContain("out=");
  });

  it("flags multiple masked substitutions", () => {
    const script = `#!/bin/bash
local a=$(cmd1)
export b=$(cmd2)
readonly c=\`cmd3\``;
    const defects = detectShellMaskedCommandSubstitutionDefects("/test.sh", script);
    expect(defects).toHaveLength(3);
  });

  // ─────────────────────────────────────────────────────────────
  // NEGATIVE CASES (must NOT flag)
  // ─────────────────────────────────────────────────────────────

  it("does NOT flag arithmetic expansion `$((n-1))` (RULE 2 negative: fact E)", () => {
    const script = `#!/bin/bash
local i=$((n - 1))
local j=$((count + 1))`;
    const defects = detectShellMaskedCommandSubstitutionDefects("/test.sh", script);
    expect(defects).toHaveLength(0);
  });

  it("does NOT flag plain assignment without declaration keyword", () => {
    const script = `#!/bin/bash
out=$(cmd)
VAR=\`another_cmd\``;
    const defects = detectShellMaskedCommandSubstitutionDefects("/test.sh", script);
    expect(defects).toHaveLength(0);
  });

  it("does NOT flag local without command substitution", () => {
    const script = `#!/bin/bash
local x=5
local name="Alice"
local file=/tmp/test`;
    const defects = detectShellMaskedCommandSubstitutionDefects("/test.sh", script);
    expect(defects).toHaveLength(0);
  });

  it("does NOT flag export without command substitution", () => {
    const script = `#!/bin/bash
export PATH=/usr/bin:/bin
export LANG=en_US.UTF-8`;
    const defects = detectShellMaskedCommandSubstitutionDefects("/test.sh", script);
    expect(defects).toHaveLength(0);
  });

  it("does NOT flag plain comments without code", () => {
    const script = `#!/bin/bash
# Just a comment
# Another comment
echo "safe"`;
    const defects = detectShellMaskedCommandSubstitutionDefects("/test.sh", script);
    expect(defects).toHaveLength(0);
  });
});

// ============================================================================
// Combined Detection Tests
// ============================================================================

describe("detectAllShellSafetyDefects — combined rules", () => {
  it("detects both RULE 1 and RULE 2 defects in one file", () => {
    const script = `#!/bin/bash
if cmd; then
  echo "ok"
else
  echo "fail"
fi
local result=$(cmd)`;
    const defects = detectAllShellSafetyDefects("/test.sh", script);
    // RULE 1 should not fire because if/else is present
    // RULE 2 should fire for the local with command substitution
    expect(defects.length).toBeGreaterThanOrEqual(1);
    expect(defects.some((d) => d.rule === "MASKED-COMMAND-SUBSTITUTION")).toBe(true);
  });

  it("sorts defects by line number", () => {
    const script = `#!/bin/bash
local a=$(cmd1)
if test -z "$x"; then
  echo "empty"
fi
rc=$?`;
    const defects = detectAllShellSafetyDefects("/test.sh", script);
    for (let i = 1; i < defects.length; i++) {
      expect(defects[i]!.lineNumber).toBeGreaterThanOrEqual(defects[i - 1]!.lineNumber);
    }
  });
});

// ============================================================================
// Escape Hatch Tests
// ============================================================================

describe("Escape hatch SHELL-SAFETY-OK", () => {
  it("suppresses RULE 1 with file-wide SHELL-SAFETY-OK marker", () => {
    const script = `#!/bin/bash
# SHELL-SAFETY-OK: Counter-example for documentation
if cmd; then
  true
fi
rc=$?`;
    const defects = detectShellStatusLossDefects("/test.sh", script);
    expect(defects).toHaveLength(0);
  });

  it("suppresses RULE 2 with file-wide SHELL-SAFETY-OK marker", () => {
    const script = `#!/bin/bash
# SHELL-SAFETY-OK: Intentional for testing purposes
local out=$(cmd)`;
    const defects = detectShellMaskedCommandSubstitutionDefects("/test.sh", script);
    expect(defects).toHaveLength(0);
  });

  it("suppresses both rules with file-wide marker", () => {
    const script = `#!/bin/bash
# SHELL-SAFETY-OK: Teaching code with deliberate patterns
if cmd; then
  x=1
fi
rc=$?
local a=$(cmd)`;
    const defects = detectAllShellSafetyDefects("/test.sh", script);
    expect(defects).toHaveLength(0);
  });

  it("requires reason text after colon (minimum 8 chars)", () => {
    const script = `#!/bin/bash
# SHELL-SAFETY-OK: short
if cmd; then
  true
fi
rc=$?`;
    // "short" is only 5 chars, so escape hatch should NOT work
    const defects = detectShellStatusLossDefects("/test.sh", script);
    expect(defects.length).toBeGreaterThan(0);
  });

  it("accepts reason text with 8+ characters", () => {
    const script = `#!/bin/bash
# SHELL-SAFETY-OK: counter-example
if cmd; then
  true
fi
rc=$?`;
    // "counter-example" is 15 chars, so escape hatch should work
    const defects = detectShellStatusLossDefects("/test.sh", script);
    expect(defects).toHaveLength(0);
  });
});

// ============================================================================
// Edge Cases and Real-World Scenarios
// ============================================================================

describe("Edge cases and real-world scenarios", () => {
  it("handles nested if-else-fi structures", () => {
    const script = `#!/bin/bash
if [[ -f file1 ]]; then
  if [[ -f file2 ]]; then
    echo "both exist"
  else
    echo "only file1"
  fi
else
  echo "file1 missing"
fi
status=$?`;
    const defects = detectShellStatusLossDefects("/test.sh", script);
    // Should NOT flag because outer if has else
    expect(defects).toHaveLength(0);
  });

  it("correctly handles inline fi", () => {
    const script = `#!/bin/bash
if test -z "$x"; then echo "empty"; else echo "not"; fi
rc=$?`;
    const defects = detectShellStatusLossDefects("/test.sh", script);
    // Should not flag because the inline if/fi has an else
    expect(defects).toHaveLength(0);
  });

  it("handles scripts without shebang if extension is .sh", () => {
    const script = `if cmd; then
  x=1
fi
rc=$?`;
    const defects = detectShellStatusLossDefects("/script.sh", script);
    expect(defects.length).toBeGreaterThan(0);
  });

  it("handles empty scripts", () => {
    const defects1 = detectShellStatusLossDefects("/test.sh", "");
    const defects2 = detectShellMaskedCommandSubstitutionDefects("/test.sh", "");
    expect(defects1).toHaveLength(0);
    expect(defects2).toHaveLength(0);
  });

  it("handles scripts with only comments", () => {
    const script = `#!/bin/bash
# This is a comment
# Another comment
# yet another`;
    const defects = detectAllShellSafetyDefects("/test.sh", script);
    expect(defects).toHaveLength(0);
  });

  it("distinguishes elif from else in defect checking", () => {
    const script = `#!/bin/bash
if [[ $x == 1 ]]; then
  echo "one"
elif [[ $x == 2 ]]; then
  echo "two"
fi
rc=$?`;
    const defects = detectShellStatusLossDefects("/test.sh", script);
    expect(defects).toHaveLength(0);
  });
});

// ============================================================================
// Defect Metadata Tests
// ============================================================================

describe("Defect metadata (explanation and corrected form)", () => {
  it("provides clear explanation for STATUS-LOSS-AFTER-IF", () => {
    const script = `#!/bin/bash
if cmd; then
  true
fi
rc=$?`;
    const defects = detectShellStatusLossDefects("/test.sh", script);
    expect(defects[0]).toBeDefined();
    if (defects[0]) {
      expect(defects[0].explanation).toContain("$?");
      expect(defects[0].explanation).toContain("failure");
    }
  });

  it("provides clear explanation for MASKED-COMMAND-SUBSTITUTION", () => {
    const script = `#!/bin/bash
local x=$(cmd)`;
    const defects = detectShellMaskedCommandSubstitutionDefects("/test.sh", script);
    expect(defects[0]).toBeDefined();
    if (defects[0]) {
      expect(defects[0].explanation).toContain("exit status");
      expect(defects[0].explanation).toContain("defeats");
    }
  });

  it("includes corrected form in defect", () => {
    const script = `#!/bin/bash
local out=$(cmd)`;
    const defects = detectShellMaskedCommandSubstitutionDefects("/test.sh", script);
    expect(defects[0]?.correctedForm).toContain("local");
    expect(defects[0]?.correctedForm).toContain("=");
  });

  it("line numbers are 1-indexed for human readability", () => {
    const script = `#!/bin/bash
local x=$(cmd)`;
    const defects = detectShellMaskedCommandSubstitutionDefects("/test.sh", script);
    expect(defects[0]?.lineNumber).toBe(2);
  });
});

// ══════════════════════════════════════════════════════════════════════════
//  Regression cases from the 2026-08-02 corpus validation
// ══════════════════════════════════════════════════════════════════════════
//
// Every case below is a defect the detector shipped with and that a 364-script
// corpus scan or a hand-written case list caught. They are grouped here, rather
// than folded into the suites above, so the reason each exists stays legible.

describe("regression: false NEGATIVES the first implementation missed", () => {
  it("flags the single-line `if …; then …; fi` form (if and fi on ONE line)", () => {
    // The original line-based depth scan saw `fi`, `continue`d, and so never noticed
    // the `if` on the same line -- concluding "no matching if" and declining to flag
    // the most common spelling of the bug.
    const script = `#!/bin/bash\nif cmd; then exit 0; fi\nrc=$?\necho "$rc"\n`;
    expect(detectShellStatusLossDefects("/t.sh", script).length).toBe(1);
  });

  it("flags `local out=$(cmd) || true` — the `||` tests local's status, never cmd's", () => {
    // A prior "fix" skipped any line containing || or &&, which suppressed this
    // genuine defect. `local` always returns 0, so the handler can never fire.
    const script = `#!/bin/bash\nf(){\n  local out=$(cmd) || true\n}\n`;
    expect(detectShellMaskedCommandSubstitutionDefects("/t.sh", script).length).toBe(1);
  });

  it("flags `local out=$(cmd1 && cmd2)` — && inside the substitution is not a fallback", () => {
    const script = `#!/bin/bash\nf(){\n  local out=$(cmd1 && cmd2)\n}\n`;
    expect(detectShellMaskedCommandSubstitutionDefects("/t.sh", script).length).toBe(1);
  });

  it("flags declarations carrying flags: `local -r`, `declare -a`", () => {
    const readonlyLocal = `#!/bin/bash\nf(){\n  local -r out=$(cmd)\n}\n`;
    const declaredArray = `#!/bin/bash\nf(){\n  declare -a out=$(cmd)\n}\n`;
    expect(detectShellMaskedCommandSubstitutionDefects("/t.sh", readonlyLocal).length).toBe(1);
    expect(detectShellMaskedCommandSubstitutionDefects("/t.sh", declaredArray).length).toBe(1);
  });
});

describe("regression: false POSITIVES that would have blocked correct code", () => {
  it("does NOT flag a heredoc body — it is printed data, not executed code", () => {
    // Real instances live in devops-tools/session-chronicle, which print a retrieval
    // template for a human to copy. Flagging them would block edits to clean files.
    const script = `#!/bin/bash\ncat <<'EOF'\nexport AWS_ACCESS_KEY_ID=$(op read "op://x/y")\nEOF\n`;
    expect(detectAllShellSafetyDefects("/t.sh", script).length).toBe(0);
  });

  it("does NOT flag `$?` bound to a command earlier on the SAME line", () => {
    // install-workspace-launcher:258. The nearest preceding code line ends in `fi`,
    // but this `$?` is wl_phase_fetch's status, not the dead `fi`'s.
    const script = [
      "#!/bin/bash",
      "ec=0",
      "if [ $ec -eq 0 ]; then wl_phase_bootstrap || ec=$?; fi",
      "if [ $ec -eq 0 ]; then wl_phase_fetch || ec=$?; fi",
      "",
    ].join("\n");
    expect(detectShellStatusLossDefects("/t.sh", script).length).toBe(0);
  });

  it("does NOT flag `local x=\"$(cmd || fallback)\"` — failure already handled inside", () => {
    // Five such lines in cns-remote-client. The substitution's status is the
    // fallback's (0) by construction, so there is nothing left for `local` to mask.
    const script = `#!/bin/bash\nf(){\n  local dir="$(pwd 2>/dev/null || echo '/unknown')"\n}\n`;
    expect(detectShellMaskedCommandSubstitutionDefects("/t.sh", script).length).toBe(0);
  });

  it("does NOT police vendored upstream code", () => {
    const script = `#!/bin/bash\nexport D="$(dirname $(xcrun --find docc))"\n`;
    const vendored = "/repo/.build/checkouts/swift-collections/Utils/generate-docs.sh";
    expect(isShellScript(vendored, script)).toBe(false);
    expect(detectAllShellSafetyDefects(vendored, script).length).toBe(0);
    // …but the identical script IS policed when we authored it.
    expect(detectAllShellSafetyDefects("/repo/bin/generate-docs.sh", script).length).toBe(1);
  });

  it("does NOT treat `fi` inside a word (fifo, notify, config) as a terminator", () => {
    const script = `#!/bin/bash\nnotify\nrc=$?\n`;
    expect(detectShellStatusLossDefects("/t.sh", script).length).toBe(0);
  });

  it("does NOT flag an else-bearing if, at any nesting depth", () => {
    // An `else` on a NESTED if must not exempt the outer one, and vice versa.
    const outerHasElse = `#!/bin/bash\nif a; then\n  b\nelse\n  c\nfi\nrc=$?\n`;
    const onlyInnerHasElse = `#!/bin/bash\nif a; then\n  if b; then\n    c\n  else\n    d\n  fi\nfi\nrc=$?\n`;
    expect(detectShellStatusLossDefects("/t.sh", outerHasElse).length).toBe(0);
    expect(detectShellStatusLossDefects("/t.sh", onlyInnerHasElse).length).toBe(1);
  });
});
