import { describe, expect, it } from "bun:test";
import {
  buildTableReminder,
  detectBrokenTables,
  hasTableErrors,
  isDelimiterRow,
  splitRowIntoCells,
} from "../lib/markdown-table-detector.ts";

/** Convenience: the set of error codes detected in `content`. */
function errorCodes(content: string): string[] {
  return detectBrokenTables(content)
    .filter((iss) => iss.severity === "error")
    .map((iss) => iss.code);
}

describe("splitRowIntoCells — GFM unescaped-pipe counting", () => {
  it("counts a clean 2-column row as 2 cells", () => {
    expect(splitRowIntoCells("| a | b |").length).toBe(2);
  });
  it("treats raw pipes inside a code span as delimiters (the bug)", () => {
    // GFM splits on unescaped pipes even inside backticks.
    expect(splitRowIntoCells("| `a | b | c` | d |").length).toBe(4);
  });
  it("does NOT split on backslash-escaped pipes", () => {
    expect(splitRowIntoCells("| `a \\| b \\| c` | d |").length).toBe(2);
  });
});

describe("isDelimiterRow", () => {
  it("accepts dashes with optional alignment colons and pipes", () => {
    expect(isDelimiterRow("| --- | :--: |")).toBe(true);
    expect(isDelimiterRow("|:--|--:|")).toBe(true);
  });
  it("rejects a bare --- (setext underline / thematic break, no pipe)", () => {
    expect(isDelimiterRow("---")).toBe(false);
  });
});

describe("FIRES: render-breaking errors", () => {
  it("column-overflow: unescaped pipe in a code span (the real gh-fine-grained-pat bug)", () => {
    const content = `## Selector map

| Step | Selector |
| ---- | -------- |
| Expiration open | \`button\` name \`/days \\( | No expiration | Custom | Expiration/i\` |
| Name | input[name] |
`;
    const codes = errorCodes(content);
    expect(codes).toContain("column-overflow");
    const issue = detectBrokenTables(content).find((iss) => iss.code === "column-overflow");
    expect(issue?.line).toBe(5);
    expect(issue?.cells).toBe(5);
    expect(issue?.expected).toBe(2);
  });

  it("header-mismatch: separator column count ≠ header", () => {
    const content = `| a | b |
| --- | --- | --- |
| 1 | 2 | 3 |
`;
    expect(errorCodes(content)).toContain("header-mismatch");
  });

  it("indented-table: ≥4 leading spaces → code block", () => {
    const content = `text

    | a | b |
    | - | - |
    | 1 | 2 |
`;
    expect(errorCodes(content)).toContain("indented-table");
  });

  it("alignment-colon-in-row: a :--: token pasted into a data row", () => {
    const content = `| a | b |
| - | - |
| :--: | :--: |
| 1 | 2 |
`;
    expect(errorCodes(content)).toContain("alignment-colon-in-row");
  });

  it("hasTableErrors is true when any error is present", () => {
    const content = "| a | b |\n| - | - |\n| 1 | 2 | 3 |\n";
    expect(hasTableErrors(detectBrokenTables(content))).toBe(true);
  });
});

describe("DOES NOT FIRE: valid / non-table / fenced content", () => {
  it("a correctly escaped \\| table is clean (the File-map table pattern)", () => {
    const content = `| File | Role |
| ---- | ---- |
| pat.mjs | CLI: \`login \\| doctor \\| create\`. |
`;
    expect(detectBrokenTables(content)).toHaveLength(0);
  });

  it("a broken table INSIDE a fenced code block is ignored", () => {
    const content = `Example:

\`\`\`markdown
| a | b |
| - | - |
| x | y | z | w |
\`\`\`
`;
    expect(detectBrokenTables(content)).toHaveLength(0);
  });

  it("a tilde-fenced broken table is ignored", () => {
    const content = `~~~
| a | b |
| - | - |
| x | y | z |
~~~
`;
    expect(detectBrokenTables(content)).toHaveLength(0);
  });

  it("prose containing a shell pipe is not a table", () => {
    const content = "Run `cat a | grep b` to filter the output.\n";
    expect(detectBrokenTables(content)).toHaveLength(0);
  });

  it("a setext H2 underline after a line with a pipe is not a table", () => {
    const content = "Some text with a | pipe\n---\n\nbody\n";
    expect(detectBrokenTables(content)).toHaveLength(0);
  });

  it("a wide-but-consistent table is clean", () => {
    const content = `| a | b | c | d |
| - | - | - | - |
| 1 | 2 | 3 | 4 |
`;
    expect(detectBrokenTables(content)).toHaveLength(0);
  });
});

describe("info-class issues (auto-fixed by the formatter) are not errors", () => {
  it("short-row is info, not error", () => {
    const content = "| a | b | c |\n| - | - | - |\n| 1 | 2 |\n";
    const issues = detectBrokenTables(content);
    expect(issues.some((iss) => iss.code === "short-row" && iss.severity === "info")).toBe(true);
    expect(hasTableErrors(issues)).toBe(false);
  });

  it("missing-blank-line before a table is info, not error", () => {
    const content = "paragraph text\n| a | b |\n| - | - |\n| 1 | 2 |\n";
    const issues = detectBrokenTables(content);
    expect(issues.some((iss) => iss.code === "missing-blank-line")).toBe(true);
    expect(hasTableErrors(issues)).toBe(false);
  });
});

describe("buildTableReminder", () => {
  it("lists errors with line numbers and the MD-TABLE-OK escape hatch", () => {
    const content = "| a | b |\n| - | - |\n| 1 | 2 | 3 |\n";
    const reminder = buildTableReminder("/repo/plugins/x/CLAUDE.md", detectBrokenTables(content));
    expect(reminder).toContain("[MD-TABLE-GUARD]");
    expect(reminder).toContain("x/CLAUDE.md");
    expect(reminder).toContain("L3");
    expect(reminder).toContain("MD-TABLE-OK");
  });
});
