#!/usr/bin/env bun
/**
 * Tests for the HTML measure guard and its detector (text on an HTML page follows the browser window).
 * The FLAGGED / ALLOWED vectors are the reference for any build-time copy of the rule in another repository,
 * so the implementations stay in step.
 */

import { describe, expect, it } from "bun:test";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { PreToolUseInput } from "./pretooluse-helpers.ts";
import { runGuardMainInProcess } from "./pretooluse-helpers.ts";
import {
  findTextMeasureViolations,
  netNewTextMeasureViolations,
} from "./lib/html-text-measure-detector.ts";
import {
  classifyHtmlMeasureGuardForOrchestrator,
  main,
  publishedPageFindings,
} from "./pretooluse-html-measure-guard.ts";

const FLAGGED = [
  "p,li{max-width:72em}",
  ".cap{margin:0;max-width:60ch}",
  "article{max-width:min(100%,70ch)}",
  "p{width:66ch}",
  "body{margin:0;max-width:1560px}",
  "main{{max-width:1180px}}",
  ".inner{margin:0 auto; max-width:1000px}",
  "<body style='max-width:1200px;margin:auto'>",
  "p.note{white-space:pre-line}",
  '<div style="white-space:pre-wrap">text</div>',
];
const ALLOWED = [
  "@media (max-width:640px){x{font-size:1em}}",
  "@media (max-width:40em){p{margin:0}}",
  "img{max-width:100%}",
  "figure.narrow img{max-width:min(100%,1100px)}",
  ".tip{max-width:320px}",
  "td.d{min-width:22em}",
  "pre{white-space:pre} textarea.code{white-space:pre}",
  "<!-- HTML-MEASURE-OK: outside page archived verbatim --><style>p{max-width:40em}</style>",
];
const CAPPED_PAGE = "<!doctype html><style>body{margin:0 auto;max-width:1560px} p,li{max-width:72em}</style><p>x</p>";
const CLEAN_PAGE = "<!doctype html><style>body{margin:0 auto;padding:18px} img{max-width:100%}</style><p>x</p>";

describe("detector", () => {
  for (const css of FLAGGED) it(`flags ${css}`, () => expect(findTextMeasureViolations(css).length).toBeGreaterThan(0));
  for (const css of ALLOWED) it(`allows ${css}`, () => expect(findTextMeasureViolations(css)).toEqual([]));
  it("counts only net-new findings", () => {
    expect(netNewTextMeasureViolations("p{max-width:72em}", "p{max-width:72em} h1{color:red}")).toEqual([]);
    expect(netNewTextMeasureViolations("p{color:red}", "p{max-width:72em}")).toEqual(["max-width:72em"]);
  });
});

function edit(tool: "Write" | "Edit", tool_input: Record<string, unknown>, extra: Record<string, unknown> = {}) {
  return classifyHtmlMeasureGuardForOrchestrator({ tool_name: tool, tool_input, ...extra } as unknown as PreToolUseInput);
}

describe("Write|Edit surface", () => {
  const dir = mkdtempSync(join(tmpdir(), "html-measure-"));

  it("CONTROL: denies writing a capped page", async () => {
    expect((await edit("Write", { file_path: join(dir, "new.html"), content: CAPPED_PAGE })).kind).toBe("deny");
  });
  it("denies a capped stylesheet inside a page builder's source", async () => {
    const src = 'CSS = """\nbody{font:16px sans-serif;max-width:1180px;margin:0 auto}\n"""\n';
    expect((await edit("Write", { file_path: join(dir, "build.py"), content: src })).kind).toBe("deny");
  });
  it("allows a clean page and non-page files", async () => {
    expect((await edit("Write", { file_path: join(dir, "ok.html"), content: CLEAN_PAGE })).kind).toBe("allow");
    expect((await edit("Write", { file_path: join(dir, "notes.md"), content: "p{max-width:72em}" })).kind).toBe("allow");
  });
  it("Edit: flags a cap the edit adds, judged on the whole file (selector outside new_string)", async () => {
    const f = join(dir, "page.html");
    writeFileSync(f, "<style>main{margin:0 auto;padding:2px}</style>");
    const d = await edit("Edit", { file_path: f, old_string: "padding:2px", new_string: "padding:2px;max-width:1180px" });
    expect(d.kind).toBe("deny");
  });
  it("Edit: an existing cap does not block an unrelated edit", async () => {
    const f = join(dir, "legacy.html");
    writeFileSync(f, "<style>p{max-width:72em} h1{color:red}</style>");
    expect((await edit("Edit", { file_path: f, old_string: "color:red", new_string: "color:blue" })).kind).toBe("allow");
  });
  it("honours HTML-MEASURE-OK in the proposed text or on disk", async () => {
    expect((await edit("Write", { file_path: join(dir, "arch.html"), content: `<!-- HTML-MEASURE-OK -->${CAPPED_PAGE}` })).kind).toBe("allow");
    const f = join(dir, "archived.html");
    writeFileSync(f, "<!-- HTML-MEASURE-OK: verbatim outside page --><style>h1{color:red}</style>");
    expect((await edit("Edit", { file_path: f, old_string: "color:red", new_string: "color:red;max-width:40em" })).kind).toBe("allow");
  });
  it("allows everything in plan mode", async () => {
    expect((await edit("Write", { file_path: join(dir, "plan.html"), content: CAPPED_PAGE }, { permission_mode: "plan" })).kind).toBe("allow");
  });
});

describe("Bash surface", () => {
  const dir = mkdtempSync(join(tmpdir(), "html-measure-bash-"));
  writeFileSync(join(dir, "capped.html"), CAPPED_PAGE);
  writeFileSync(join(dir, "clean.html"), CLEAN_PAGE);
  mkdirSync(join(dir, "site", "sub"), { recursive: true });
  writeFileSync(join(dir, "site", "index.html"), CLEAN_PAGE);
  writeFileSync(join(dir, "site", "sub", "page.html"), CAPPED_PAGE);

  it("finds the capped page an orca share would publish (relative to cwd, with flags)", () => {
    expect(publishedPageFindings("orca artifacts share capped.html --json", dir)).toHaveLength(1);
    expect(publishedPageFindings(`orca artifacts update --json "${join(dir, "capped.html")}"`, undefined)).toHaveLength(1);
    expect(publishedPageFindings("orca artifacts share clean.html --json", dir)).toEqual([]);
  });
  it("finds a capped page inside a wrangler pages deploy directory", () => {
    const bad = publishedPageFindings("npx -y wrangler@4 pages deploy site --project-name x", dir);
    expect(bad.map((b) => b[0])).toEqual(["sub/page.html"]);
  });
  it("skips paths that do not exist here (a remote ssh path)", () => {
    expect(publishedPageFindings("ssh mac 'orca artifacts share /Users/x/remote.html'", dir)).toEqual([]);
  });

  async function decide(command: string) {
    const out = await runGuardMainInProcess(main, { tool_name: "Bash", tool_input: { command }, cwd: dir } as unknown as PreToolUseInput);
    return JSON.stringify(out);
  }
  it("CONTROL: main() denies publishing a capped page", async () => {
    expect(await decide("orca artifacts share capped.html --json")).toContain('"deny"');
  });
  it("main() allows a clean page, an escape, and unrelated commands", async () => {
    expect(await decide("orca artifacts share clean.html --json")).not.toContain('"deny"');
    expect(await decide("orca artifacts share capped.html --json # HTML-MEASURE-OK: verbatim archive")).not.toContain('"deny"');
    expect(await decide("ls -la")).not.toContain('"deny"');
  });
});
