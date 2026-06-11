/**
 * Tests for posttooluse-invented-fallback-reminder.ts
 *
 * Run with: bun test plugins/itp-hooks/hooks/posttooluse-invented-fallback-reminder.test.ts
 *
 * Pins the official-values policy nudge (operator directive 2026-06-11):
 * net-new invented fallback display values (Unknown / N/A / ${x:-?}) in code
 * files trigger a Claude-visible reminder; tests, comments, pre-existing
 * occurrences, legitimate defaults, and the escape hatch stay silent.
 */

import { describe, expect, it } from "bun:test";
import { detectNetNewInventedFallback } from "./posttooluse-invented-fallback-reminder.ts";

function write(filePath: string, content: string) {
  return { tool_name: "Write", tool_input: { file_path: filePath, content } };
}
function edit(filePath: string, old_string: string, new_string: string) {
  return { tool_name: "Edit", tool_input: { file_path: filePath, old_string, new_string } };
}

describe("FIRES: net-new invented fallbacks in code files", () => {
  it("shell parameter-expansion Unknown default", () => {
    const r = detectNetNewInventedFallback(write("/a/render.sh", `model="\${model_raw:-Unknown}"`));
    expect(r.matched).toBe(true);
    expect(r.rule).toBe("shell-parameter-expansion-default");
  });

  it("shell ? placeholder default", () => {
    const r = detectNetNewInventedFallback(write("/a/render.sh", `iter="\${loop_iter:-?}"`));
    expect(r.matched).toBe(true);
  });

  it("TS nullish N/A fallback", () => {
    const r = detectNetNewInventedFallback(write("/a/render.ts", 'const cost = payload.cost ?? "N/A";'));
    expect(r.matched).toBe(true);
    expect(r.rule).toBe("nullish-or-logical-or-fallback");
  });

  it("JS logical-or Unknown fallback", () => {
    const r = detectNetNewInventedFallback(write("/a/render.mjs", 'const name = model || "Unknown";'));
    expect(r.matched).toBe(true);
  });

  it("python or-Unknown fallback", () => {
    const r = detectNetNewInventedFallback(write("/a/render.py", 'label = value or "Unknown"'));
    expect(r.matched).toBe(true);
    expect(r.rule).toBe("python-or-fallback");
  });

  it("python dict.get N/A fallback", () => {
    const r = detectNetNewInventedFallback(write("/a/render.py", 'v = d.get("cost", "N/A")'));
    expect(r.matched).toBe(true);
    expect(r.rule).toBe("python-dict-get-fallback");
  });

  it("jq alternative-operator Unknown fallback inside a shell line", () => {
    const r = detectNetNewInventedFallback(
      write("/a/render.sh", `model=$(echo "$input" | jq -r '.model.display_name // "Unknown"')`),
    );
    expect(r.matched).toBe(true);
  });

  it("Edit introducing a NEW fallback fires", () => {
    const r = detectNetNewInventedFallback(
      edit("/a/render.sh", 'x="$value"', `x="\${value:-Unknown}"`),
    );
    expect(r.matched).toBe(true);
  });
});

describe("SILENT: exemptions and legitimate shapes", () => {
  it("test files are exempt", () => {
    const r = detectNetNewInventedFallback(write("/a/tests/render.test.ts", 'const x = y ?? "Unknown";'));
    expect(r.matched).toBe(false);
  });

  it("fixture paths are exempt", () => {
    const r = detectNetNewInventedFallback(write("/a/fixtures/case1.py", 'v = d.get("x", "N/A")'));
    expect(r.matched).toBe(false);
  });

  it("non-code files are exempt", () => {
    const r = detectNetNewInventedFallback(write("/a/notes.md", 'fallback ?? "Unknown"'));
    expect(r.matched).toBe(false);
  });

  it("comment lines never count", () => {
    const r = detectNetNewInventedFallback(
      write("/a/render.sh", `# the old code used \${x:-Unknown} — removed 2026-06-11`),
    );
    expect(r.matched).toBe(false);
  });

  it("legitimate empty-string default stays silent", () => {
    const r = detectNetNewInventedFallback(write("/a/render.ts", 'const x = y ?? "";'));
    expect(r.matched).toBe(false);
  });

  it("official boolean default stays silent (jq // false)", () => {
    const r = detectNetNewInventedFallback(
      write("/a/render.sh", `t=$(echo "$j" | jq -r '.thinking.enabled // false')`),
    );
    expect(r.matched).toBe(false);
  });

  it("bare Unknown in a string without a fallback operator stays silent", () => {
    const r = detectNetNewInventedFallback(write("/a/render.py", 'print("Unknown error occurred")'));
    expect(r.matched).toBe(false);
  });

  it("Edit touching a PRE-EXISTING fallback does not nag (net-new only)", () => {
    const r = detectNetNewInventedFallback(
      edit("/a/render.sh", `x="\${value:-Unknown}" # old`, `x="\${value:-Unknown}" # reflowed`),
    );
    expect(r.matched).toBe(false);
  });

  it("escape hatch silences the nudge", () => {
    const r = detectNetNewInventedFallback(
      write("/a/render.sh", `x="\${value:-Unknown}" # INVENTED-FALLBACK-OK diagnostic legend below`),
    );
    expect(r.matched).toBe(false);
  });
});
