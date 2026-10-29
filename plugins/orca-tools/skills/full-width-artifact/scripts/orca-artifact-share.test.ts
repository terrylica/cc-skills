#!/usr/bin/env bun
/**
 * Tests for orca-artifact-share: its copy of the text-measure rule agrees with itp-hooks' detector on the
 * shared vectors, Markdown renders to a full-width page, uploaded HTML is repaired, and a hard line break in
 * prose is caught. No network and no Orca: publishing and --check are exercised by hand (see SKILL.md).
 */
import { describe, expect, it } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { findTextMeasureViolations } from "../../../../itp-hooks/hooks/lib/html-text-measure-detector.ts";
import { ALLOWED, FLAGGED } from "../../../../itp-hooks/hooks/lib/html-text-measure-vectors.ts";
import { hardenHtml, lint, MARKER, measureViolations, outPathFor, wrapPage } from "./orca-artifact-share";

const SCRIPT = join(import.meta.dir, "orca-artifact-share");
const ESCAPE = "HTML-MEASURE-OK";

describe("rule copy agrees with the itp-hooks detector", () => {
  for (const v of [...FLAGGED, ...ALLOWED].filter((x) => !x.includes(ESCAPE))) {
    it(v, () => expect(measureViolations(v).length > 0).toBe(findTextMeasureViolations(v).length > 0));
  }
  it("a published page cannot opt out with the escape marker", () => {
    expect(measureViolations("<!-- HTML-MEASURE-OK --><style>body{max-width:820px}</style>").length).toBeGreaterThan(0);
  });
});

describe("lint", () => {
  it("rejects Orca's Markdown template (the measured 2026-10-29 cause)", () => {
    const orcaTemplate = "<style>body{font-family:system-ui;max-width:820px;margin:40px auto;padding:0 24px}</style><p>x</p>";
    expect(lint(orcaTemplate).join("\n")).toContain("max-width:820px");
  });
  it("accepts its own page, and flags a hard line break in a paragraph", () => {
    expect(lint(wrapPage("<p>one long paragraph</p>", "t"))).toEqual([]);
    expect(lint(wrapPage("<p>line one<br>line two</p>", "t")).join("\n")).toContain("hard line break");
  });
  it("its own stylesheet passes the original detector too", () => {
    expect(findTextMeasureViolations(wrapPage("<p>x</p><pre>code</pre>", "t"))).toEqual([]);
  });
});

describe("uploaded HTML is repaired", () => {
  const capped =
    "<!doctype html><html><head><style>body{margin:0 auto;max-width:1560px} p,li{max-width:72em} p.n{white-space:pre-line} img{max-width:100%} .tip{max-width:320px}</style></head><body style='max-width:1200px'><p>x</p></body></html>";
  const fixed = hardenHtml(capped);
  it("removes every fixed text width and adds the marker", () => {
    expect(lint(fixed)).toEqual([]);
    expect(findTextMeasureViolations(fixed)).toEqual([]);
    expect(fixed).toContain(MARKER);
  });
  it("leaves media and tooltips alone, and is idempotent", () => {
    expect(fixed).toContain("img{max-width:100%}");
    expect(fixed).toContain(".tip{max-width:320px}");
    expect(hardenHtml(fixed)).toBe(fixed);
  });
});

describe("Markdown renders to a full-width page (needs pandoc)", () => {
  const hasPandoc = spawnSync("pandoc", ["--version"]).status === 0;
  const dir = mkdtempSync(join(tmpdir(), "orca-artifact-"));
  const md = join(dir, "report.md");
  writeFileSync(md, "# Report title\n\nA paragraph that is one long line and must reflow to the window.\n\n| a | b |\n| --- | --- |\n| 1 | 2 |\n");
  it.skipIf(!hasPandoc)("--dry-run writes a clean page at a stable path named after the source", () => {
    const env = { ...process.env, ORCA_ARTIFACT_DIR: join(dir, "out") };
    const run = () => JSON.parse(spawnSync("bun", [SCRIPT, md, "--dry-run"], { encoding: "utf8", env }).stdout);
    const first = run();
    expect(first.ok).toBe(true);
    expect(basename(first.html)).toBe("report.html");
    expect(run().html).toBe(first.html);
    const page = readFileSync(first.html, "utf8");
    expect(lint(page)).toEqual([]);
    expect(page).toContain("<title>Report title</title>");
    expect(page).toContain('<div class="table-scroll"><table>');
  });
  it("outPathFor keeps the hash out of the file name", () => {
    expect(basename(outPathFor(md))).toBe("report.html");
  });
});
