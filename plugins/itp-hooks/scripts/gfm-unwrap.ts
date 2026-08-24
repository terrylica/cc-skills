#!/usr/bin/env bun
/**
 * gfm-unwrap — repair hard-wrapped prose before it is published to GitHub.
 *
 * The `github-hard-wrap-guard` PreToolUse hook denies a `gh` command whose body
 * is hard-wrapped, because GFM renders every newline inside a paragraph as an
 * HTML `<br>`. This is the tool that guard tells you to run.
 *
 * Usage:
 *   bun scripts/gfm-unwrap.ts <file>              # rewrite the file in place
 *   bun scripts/gfm-unwrap.ts --check <file>      # exit 1 if it needs unwrapping
 *   bun scripts/gfm-unwrap.ts --stdout <file>     # write the result to stdout
 *   cat body.md | bun scripts/gfm-unwrap.ts -     # stdin to stdout
 *
 * Resolve the path without hardcoding a version:
 *   bun "$(cc-plugin-root itp-hooks)/scripts/gfm-unwrap.ts" body.md
 *
 * Exit codes: 0 clean or repaired · 1 --check found wraps · 2 usage or I/O
 * error · 3 the content-preservation invariant failed (a bug in this tool —
 * NOTHING is written in that case).
 */

import { detectHardWraps } from "../hooks/lib/hard-wrap-detector.ts";
import { unwrapGfmParagraphsDetailed } from "../hooks/lib/gfm-unwrap.ts";

const USAGE = [
  "gfm-unwrap — join hard-wrapped GFM paragraphs so GitHub can reflow them.",
  "",
  "  bun gfm-unwrap.ts <file>            rewrite in place",
  "  bun gfm-unwrap.ts --check <file>    exit 1 if the file needs unwrapping",
  "  bun gfm-unwrap.ts --stdout <file>   print the result, leave the file alone",
  "  cat body.md | bun gfm-unwrap.ts -   read stdin, print to stdout",
].join("\n");

function fail(message: string, code: number): never {
  process.stderr.write(`${message}\n`);
  process.exit(code);
}

async function readInput(path: string): Promise<string> {
  if (path === "-") return await Bun.stdin.text();
  const file = Bun.file(path);
  if (!(await file.exists())) fail(`gfm-unwrap: no such file: ${path}`, 2);
  return await file.text();
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  if (args.length === 0 || args.includes("--help") || args.includes("-h")) {
    process.stdout.write(`${USAGE}\n`);
    process.exit(args.length === 0 ? 2 : 0);
  }

  const checkOnly = args.includes("--check");
  const toStdout = args.includes("--stdout");
  const paths = args.filter((a) => !a.startsWith("--"));
  if (paths.length !== 1) fail(`gfm-unwrap: expected exactly one file\n\n${USAGE}`, 2);

  const path = paths[0];
  const before = await readInput(path);

  let result: { text: string; joinsPerformed: number };
  try {
    result = unwrapGfmParagraphsDetailed(before);
  } catch (err) {
    // The invariant tripped. Write nothing — a body that changed content is
    // worse than a body that is merely ugly.
    fail(`${err instanceof Error ? err.message : String(err)}`, 3);
  }

  if (checkOnly) {
    const wraps = detectHardWraps(before);
    if (wraps.length === 0) {
      process.stderr.write(`gfm-unwrap: ${path} is clean\n`);
      process.exit(0);
    }
    process.stderr.write(
      [
        `gfm-unwrap: ${path} has ${wraps.length} hard-wrapped line(s); ${result.joinsPerformed} join(s) would be made.`,
        ...wraps.slice(0, 5).map((w) => `  L${w.line}: ${w.width} cols → "${w.nextPreview}"`),
      ].join("\n") + "\n",
    );
    process.exit(1);
  }

  if (toStdout || path === "-") {
    process.stdout.write(result.text);
    process.stderr.write(`gfm-unwrap: ${result.joinsPerformed} join(s)\n`);
    return;
  }

  if (result.joinsPerformed === 0) {
    process.stderr.write(`gfm-unwrap: ${path} already flat, unchanged\n`);
    return;
  }

  await Bun.write(path, result.text);
  process.stderr.write(`gfm-unwrap: ${path} — ${result.joinsPerformed} join(s) applied\n`);
}

main().catch((err) => {
  fail(`gfm-unwrap: ${err instanceof Error ? err.message : String(err)}`, 2);
});
