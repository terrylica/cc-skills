#!/usr/bin/env bun
/**
 * Failure roster for the bun unit suite (#143).
 *
 * bun's console output names a failing test but not its FILE (the path only heads
 * the inline error block, which scrolls away first), and its end-of-run summary
 * names nothing. bun's built-in JUnit reporter does record both: every
 * <testcase> carries `file=` and `line=`. This reads that report and prints one
 * line per failing test, so a tail of the log is enough to locate it.
 *
 * Token: `BUN-UNIT-FAIL`, deliberately distinct from the hook suite's
 * FILE-FAIL / FILE-PASS (db49c313), and never shaped like `^\s*N pass|fail`,
 * which tasks/release/preflight greps out of this suite's log.
 *
 * Usage: bun tasks/lib/bun-junit-failure-roster.ts <junit.xml>
 * Exit: 0 always — it reports; the caller owns the verdict (bun's exit code).
 */
import { existsSync, readFileSync } from "node:fs";

export interface FailingTestcase {
  file: string;
  line: string;
  name: string;
  classname: string;
}

const XML_ENTITIES: Record<string, string> = { "&lt;": "<", "&gt;": ">", "&quot;": '"', "&apos;": "'", "&amp;": "&" };

function decode(value: string): string {
  return value.replace(/&(lt|gt|quot|apos|amp);/g, (m) => XML_ENTITIES[m] ?? m);
}

function attribute(tag: string, name: string): string {
  const match = new RegExp(`\\s${name}="([^"]*)"`).exec(tag);
  return match ? decode(match[1]) : "";
}

/** Every <testcase> whose body holds a <failure> or <error>. Self-closing testcases passed. */
export function failingTestcases(xml: string): FailingTestcase[] {
  const failing: FailingTestcase[] = [];
  const testcase = /<testcase\b([^>]*?)(\/>|>([\s\S]*?)<\/testcase>)/g;
  for (const m of xml.matchAll(testcase)) {
    const body = m[3] ?? "";
    if (!/<(failure|error)\b/.test(body)) continue;
    const tag = m[1];
    failing.push({
      file: attribute(tag, "file"),
      line: attribute(tag, "line"),
      name: attribute(tag, "name"),
      classname: attribute(tag, "classname"),
    });
  }
  return failing;
}

export function formatRoster(failing: FailingTestcase[]): string[] {
  return failing.map((t) => {
    const where = t.line ? `${t.file}:${t.line}` : t.file;
    const title = t.classname ? `${t.classname} > ${t.name}` : t.name;
    return `BUN-UNIT-FAIL ${where} — ${title}`;
  });
}

if (import.meta.main) {
  const report = process.argv[2];
  if (!report || !existsSync(report)) {
    console.log("BUN-UNIT-ROSTER no JUnit report was written: bun failed before reporting (load or crash error), see the output above");
    process.exit(0);
  }
  const lines = formatRoster(failingTestcases(readFileSync(report, "utf8")));
  if (lines.length === 0) {
    console.log("BUN-UNIT-ROSTER the report lists no failing test: the failure is outside a test (load error, unhandled rejection), see the output above");
  } else {
    console.log(`BUN-UNIT-ROSTER ${lines.length} failing test(s):`);
    for (const line of lines) console.log(line);
  }
}
