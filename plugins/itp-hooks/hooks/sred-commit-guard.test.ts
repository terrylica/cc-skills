import { describe, expect, it } from "bun:test";
import { extractCommitMessage } from "./sred-commit-guard.ts";

/**
 * Characterization tests for extractCommitMessage — locks the six extraction
 * `method`s after routing the low-level shell parsing through the shared
 * shell-arg-extractor lib (2026-07-22). Previously this parser had no unit test.
 */
describe("extractCommitMessage", () => {
  it("heredoc: extracts body and strips edge newlines", () => {
    const cmd = `git commit -m "$(cat <<'EOF'\nfeat(x): y\n\nSRED-Type: experimental-development\nEOF\n)"`;
    expect(extractCommitMessage(cmd)).toEqual({
      found: true,
      message: "feat(x): y\n\nSRED-Type: experimental-development",
      method: "heredoc",
    });
  });

  it("heredoc-bypass: heredoc syntax present but unparseable", () => {
    const cmd = `git commit -m "$(cat <<EOF\nunterminated body with no closing delimiter`;
    expect(extractCommitMessage(cmd)).toEqual({ found: false, message: "", method: "heredoc-bypass" });
  });

  it("file: -F <file> allows through without reading", () => {
    expect(extractCommitMessage("git commit -F /tmp/msg.txt")).toEqual({
      found: false,
      message: "",
      method: "file",
    });
  });

  it("file: --file=<path> allows through", () => {
    expect(extractCommitMessage("git commit --file=/tmp/msg.txt")).toEqual({
      found: false,
      message: "",
      method: "file",
    });
  });

  it("double-quote: reconstructs escaped newlines and quotes", () => {
    const cmd = `git commit -m "feat(x): y\\n\\nSRED-Type: experimental-development"`;
    const r = extractCommitMessage(cmd);
    expect(r.method).toBe("double-quote");
    expect(r.found).toBe(true);
    expect(r.message).toBe("feat(x): y\n\nSRED-Type: experimental-development");
  });

  it("double-quote: real newlines pass through unchanged", () => {
    const cmd = `git commit -m "feat(x): y\n\nSRED-Type: experimental-development"`;
    const r = extractCommitMessage(cmd);
    expect(r.method).toBe("double-quote");
    expect(r.message).toBe("feat(x): y\n\nSRED-Type: experimental-development");
  });

  it("single-quote: literal content with \\n reconstruction", () => {
    const cmd = `git commit -m 'feat(x): y\\n\\nSRED-Type: experimental-development'`;
    const r = extractCommitMessage(cmd);
    expect(r.method).toBe("single-quote");
    expect(r.message).toBe("feat(x): y\n\nSRED-Type: experimental-development");
  });

  it("none: editor mode (no -m/-F)", () => {
    expect(extractCommitMessage("git commit --amend")).toEqual({ found: false, message: "", method: "none" });
  });
});
