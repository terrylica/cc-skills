import { beforeAll, describe, expect, it } from "bun:test";
import { mkdtempSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  isOversizedFormat,
  OVERSIZE_GROWTH_RATIO,
  OVERSIZE_MIN_GROWTH_BYTES,
  tablePaddingGrowthUpperBound,
} from "./stop-markdown-lint.ts";

const HOOK_PATH = join(import.meta.dir, "stop-markdown-lint.ts");
const PRETTIER_AVAILABLE = Bun.which("prettier") !== null;

/** An unaligned table, the way a script or a person writes one before any formatter runs. */
function table(rows: string[][]): string {
  const [header, ...body] = rows;
  return [
    `| ${header.join(" | ")} |`,
    `|${header.map(() => "---").join("|")}|`,
    ...body.map((cells) => `| ${cells.join(" | ")} |`),
  ].join("\n");
}

function tableWithOneLongCell(rowCount: number, longCellLength: number): string {
  const rows = [["id", "name", "status", "notes"]];
  for (let i = 0; i < rowCount; i++) {
    rows.push([String(i), `item ${i}`, "open", i === 3 ? "n".repeat(longCellLength) : "short note"]);
  }
  return table(rows);
}

// 120 rows, one cell of 3,000 characters: about 8 KB that prettier pads to about 370 KB.
const WIDE_TABLE_DOC = `# Register\n\n${tableWithOneLongCell(120, 3000)}\n`;
// The same shape at a size where the padding is real but modest: about 3 KB becomes about 27 KB,
// a ratio far over the limit with a growth under the byte floor.
const MEDIUM_TABLE_DOC = `# Register\n\n${tableWithOneLongCell(40, 600)}\n`;
const SMALL_TABLE_DOC = "# Notes\n\n| a | b |\n|---|---|\n| 1 | two words |\n| 333 | x |\n\nText.\n";
const SMALL_TABLE_ALIGNED_ROW = "| 1   | two words |";
const NO_TABLE_DOC = "# Notes\n\nA paragraph with a pipe | in it and a rule below.\n\n---\n\nMore text.\n";

function prettierFormattedBytes(dir: string, name: string): number {
  const r = Bun.spawnSync(["prettier", "--prose-wrap", "preserve", name], { cwd: dir, stdout: "pipe", stderr: "pipe" });
  if (r.exitCode !== 0) throw new Error(`prettier ${name}: ${r.stderr.toString()}`);
  return r.stdout.length;
}

/** A scratch repository whose .md files are untracked, which is one of the sets the hook formats. */
function scratchRepo(files: Record<string, string>): string {
  const dir = realpathSync(mkdtempSync(join(tmpdir(), "stop-markdown-lint-")));
  const init = Bun.spawnSync(["git", "init", "-q", "-b", "main"], { cwd: dir, stdout: "pipe", stderr: "pipe" });
  if (init.exitCode !== 0) throw new Error(`git init: ${init.stderr.toString()}`);
  for (const [name, content] of Object.entries(files)) writeFileSync(join(dir, name), content);
  return dir;
}

/** Run the hook the way the Stop orchestrator does (a bun subprocess in the repository) and return its report. */
function runHook(cwd: string): string {
  const r = Bun.spawnSync(["bun", HOOK_PATH], { cwd, stdin: "ignore", stdout: "pipe", stderr: "pipe", timeout: 60_000 });
  if (r.exitCode !== 0) throw new Error(`hook exited ${r.exitCode}: ${r.stderr.toString()}`);
  return JSON.parse(r.stdout.toString()).additionalContext ?? "";
}

describe("isOversizedFormat", () => {
  it("is true for the measured case: 161,149 bytes that one run turned into 1,322,925", () => {
    expect(isOversizedFormat(161_149, 1_322_925)).toBe(true);
    expect(isOversizedFormat(318_000, 3_600_000)).toBe(true);
  });

  it("is false for a small file that multiplies but adds little", () => {
    expect(isOversizedFormat(62, 92)).toBe(false);
    expect(isOversizedFormat(1_000, 4_000)).toBe(false);
    expect(isOversizedFormat(10_322, 27_743)).toBe(false);
  });

  it("is false for a large file that adds many bytes but a modest fraction", () => {
    expect(isOversizedFormat(2_000_000, 2_100_000)).toBe(false);
    expect(isOversizedFormat(74_029, 101_537)).toBe(false);
  });

  it("needs both the ratio and the byte floor, each inclusive", () => {
    const original = OVERSIZE_MIN_GROWTH_BYTES;
    expect(isOversizedFormat(original, original * OVERSIZE_GROWTH_RATIO)).toBe(true);
    expect(isOversizedFormat(original, original * OVERSIZE_GROWTH_RATIO - 1)).toBe(false);
    expect(isOversizedFormat(original * 10, original * 10 + OVERSIZE_MIN_GROWTH_BYTES)).toBe(false);
  });
});

describe("tablePaddingGrowthUpperBound", () => {
  it("is zero without a table, even with pipes and a horizontal rule in the text", () => {
    expect(tablePaddingGrowthUpperBound(NO_TABLE_DOC)).toBe(0);
    expect(tablePaddingGrowthUpperBound("")).toBe(0);
  });

  it("keeps a small table under the byte floor, so it is never measured", () => {
    const bound = tablePaddingGrowthUpperBound(SMALL_TABLE_DOC);
    expect(bound).toBeGreaterThan(0);
    expect(bound).toBeLessThan(OVERSIZE_MIN_GROWTH_BYTES);
  });

  it("puts a table with one long cell over the byte floor, so it is measured", () => {
    expect(tablePaddingGrowthUpperBound(WIDE_TABLE_DOC)).toBeGreaterThanOrEqual(OVERSIZE_MIN_GROWTH_BYTES);
    expect(tablePaddingGrowthUpperBound(MEDIUM_TABLE_DOC)).toBeGreaterThanOrEqual(OVERSIZE_MIN_GROWTH_BYTES);
  });

  it("sees a table inside a blockquote, indented under a list item, and with CRLF line ends", () => {
    const quoted = "> | a | b |\n> |---|---|\n> | 1 | 2 |\n";
    const indented = "- item\n\n  | a | b |\n  | :-- | --: |\n  | 1 | 2 |\n";
    const crlf = "| a | b |\r\n|---|---|\r\n| 1 | 2 |\r\n";
    for (const text of [quoted, indented, crlf]) expect(tablePaddingGrowthUpperBound(text)).toBeGreaterThan(0);
  });

  it.skipIf(!PRETTIER_AVAILABLE)("is never below what prettier actually adds", () => {
    const wideChars = table([
      ["名前", "説明"],
      ["短い", "x"],
      ["y", "長い説明".repeat(40)],
    ]);
    const docs: Record<string, string> = {
      "wide.md": WIDE_TABLE_DOC,
      "medium.md": MEDIUM_TABLE_DOC,
      "small.md": SMALL_TABLE_DOC,
      "two.md": `${tableWithOneLongCell(30, 200)}\n\ntext\n\n${tableWithOneLongCell(10, 900)}\n`,
      "cjk.md": `${wideChars}\n`,
    };
    const dir = scratchRepo(docs);
    for (const [name, text] of Object.entries(docs)) {
      const growth = prettierFormattedBytes(dir, name) - Buffer.byteLength(text);
      expect(tablePaddingGrowthUpperBound(text)).toBeGreaterThanOrEqual(growth);
    }
  });
});

describe.skipIf(!PRETTIER_AVAILABLE)("hook process (spawned end-to-end)", () => {
  let dir = "";
  let report = "";

  beforeAll(() => {
    dir = scratchRepo({
      "wide.md": WIDE_TABLE_DOC,
      "medium.md": MEDIUM_TABLE_DOC,
      "small.md": SMALL_TABLE_DOC,
      "ignored.md": SMALL_TABLE_DOC,
      ".prettierignore": "ignored.md\n",
    });
    report = runHook(dir);
  }, 60_000);

  it("the fixture really would blow up: prettier alone grows it past both thresholds", () => {
    const original = Buffer.byteLength(WIDE_TABLE_DOC);
    const formatted = prettierFormattedBytes(dir, "wide.md");
    expect(formatted / original).toBeGreaterThan(OVERSIZE_GROWTH_RATIO * 5);
    expect(formatted - original).toBeGreaterThan(OVERSIZE_MIN_GROWTH_BYTES * 5);
  });

  it("leaves a wide-table file byte-identical", () => {
    expect(readFileSync(join(dir, "wide.md"), "utf8")).toBe(WIDE_TABLE_DOC);
  });

  it("reports the file, both sizes and .prettierignore as the permanent opt-out", () => {
    const line = report.split("\n").find((l) => l.startsWith("wide.md: SKIPPED auto-format")) ?? "";
    expect(line).toContain(`from ${Buffer.byteLength(WIDE_TABLE_DOC)} to `);
    expect(line).toContain("left unchanged");
    expect(line).toContain(".prettierignore");
  });

  it("still formats an ordinary file with a small table", () => {
    const formatted = readFileSync(join(dir, "small.md"), "utf8");
    expect(formatted).not.toBe(SMALL_TABLE_DOC);
    expect(formatted).toContain(SMALL_TABLE_ALIGNED_ROW);
    expect(report).not.toContain("small.md: SKIPPED");
  });

  it("still formats a measured file whose growth stays under the byte floor", () => {
    const formatted = readFileSync(join(dir, "medium.md"), "utf8");
    const growth = Buffer.byteLength(formatted) - Buffer.byteLength(MEDIUM_TABLE_DOC);
    expect(growth).toBeGreaterThan(0);
    expect(growth).toBeLessThan(OVERSIZE_MIN_GROWTH_BYTES);
    expect(report).not.toContain("medium.md: SKIPPED");
  });

  it("still skips a file listed in .prettierignore, and says so", () => {
    expect(readFileSync(join(dir, "ignored.md"), "utf8")).toBe(SMALL_TABLE_DOC);
    expect(report).toContain("skipped 1 file(s) per .prettierignore");
  });

  it("counts only the files it formatted", () => {
    expect(report).toContain("prettier: auto-formatted 2 file(s)");
  });
});
