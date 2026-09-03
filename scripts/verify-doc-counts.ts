#!/usr/bin/env bun
/**
 * verify-doc-counts — the counts this repo's own docs assert must match the filesystem.
 *
 * ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
 * Root CLAUDE.md is the first file every agent and every new contributor reads. On 2026-09-03 an
 * audit found it claiming "33 of 58 ADRs have one" for design specs, a plugin count of 42 against a
 * real 41, and 35 Python CLIs against a real 37. A hub that miscounts trains every reader to
 * distrust it, and a distrusted hub is worse than no hub — readers stop believing the parts that
 * are true. These numbers are hand-maintained and nothing enforced them, which is exactly the
 * failure mode `~/.claude/tools/verify-decision-index-counts.sh` was written for in the neighbouring
 * repo; this is that gate's shape, applied here.
 *
 * ── THE RULE ────────────────────────────────────────────────────────────────────────────────────
 * Write what the gate prints. NEVER increment a number by hand — incrementing is how the drift got
 * in, because the person editing is concentrating on the thing they added, not on the tally.
 *
 * ── WHY IT CANNOT PASS VACUOUSLY ────────────────────────────────────────────────────────────────
 * Every claim is found by PATTERN, never by line number, because line numbers drift — that is the
 * very failure this gate exists to prevent. But a pattern that stops matching (someone reworded a
 * heading) would silently reduce the gate to checking nothing and still exit 0. This repo has been
 * bitten by "examined nothing, reported PASS" repeatedly, so: a rule whose pattern matches ZERO
 * times is reported as INCONCLUSIVE and exits non-zero, and the ground truth itself is
 * sanity-checked (zero plugins or zero ADRs means the layout moved, not that the docs are right).
 * The number of claims located and checked is always printed.
 *
 * ── DELIBERATELY NOT CHECKED HERE ───────────────────────────────────────────────────────────────
 * marketplace.json's registered count vs the plugins/ directory count is ALREADY enforced by
 * scripts/validate-plugins.mjs (unregistered directories AND orphaned entries, both fatal in
 * --strict), which `moon run repo:lint` runs. A second implementation would be two things to keep
 * in agreement instead of one. Not duplicated on purpose.
 *
 * Exit: 0 = every claim agrees · 1 = drift · 2 = inconclusive (a pattern found nothing to check).
 */

import { readdirSync, readFileSync, existsSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { execFileSync } from "node:child_process";

// ── Repo root ─────────────────────────────────────────────────────────────────────────────────
function repoRoot(): string {
  try {
    return execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
  } catch {
    return process.cwd();
  }
}
const ROOT = repoRoot();
const p = (...parts: string[]) => resolve(ROOT, ...parts);

// ── Ground truth, derived from the filesystem ─────────────────────────────────────────────────
const ADR_NAME = /^\d{4}-\d{2}-\d{2}-.+\.md$/;

function pluginDirs(): string[] {
  // Same definition validate-plugins.mjs uses: a non-hidden directory under plugins/.
  return readdirSync(p("plugins")).filter(
    (name) => !name.startsWith(".") && statSync(p("plugins", name)).isDirectory(),
  );
}

function adrBasenames(): string[] {
  return readdirSync(p("docs", "adr"))
    .filter((f) => ADR_NAME.test(f))
    .map((f) => f.replace(/\.md$/, ""));
}

/**
 * An ADR "has a design spec" when docs/design/ carries either <adr-basename>/ containing at least
 * one .md (the shipped layout — 33 of them hold a spec.md) or a flat <adr-basename>.md. Counting
 * only `docs/design/*.md` is what produced the wrong "1 of 58": that glob sees the directory's own
 * CLAUDE.md and nothing else, because every real spec lives one level down.
 */
function adrsWithDesignSpec(adrs: string[]): string[] {
  return adrs.filter((base) => {
    const flat = p("docs", "design", `${base}.md`);
    if (existsSync(flat)) return true;
    const dir = p("docs", "design", base);
    if (!existsSync(dir) || !statSync(dir).isDirectory()) return false;
    return readdirSync(dir).some((f) => f.endsWith(".md"));
  });
}

/**
 * The Python CLI surface. Read from cli_spec.json rather than re-walking every skill's scripts/
 * with a second AST parser: `moon run repo:cli-spec-check` already proves that file matches disk
 * (scripts/cli_spec.py --check plus scripts/test_cli_spec.py's completeness invariant), and it is
 * in the same `repo:check` gate as this task. Re-deriving it here would be a second parser to keep
 * in agreement with the first.
 */
function cliCount(): number {
  const spec = JSON.parse(readFileSync(p("cli_spec.json"), "utf8"));
  return Object.keys(spec.commands ?? {}).length;
}

const plugins = pluginDirs();
const adrs = adrBasenames();
const truth = {
  plugins: plugins.length,
  pluginsWithClaudeMd: plugins.filter((name) => existsSync(p("plugins", name, "CLAUDE.md"))).length,
  adrs: adrs.length,
  designSpecs: adrsWithDesignSpec(adrs).length,
  clis: cliCount(),
};

// ── The claims ────────────────────────────────────────────────────────────────────────────────
type Rule = {
  label: string;
  file: string;
  /** Global regex; every capture group is a number that must equal the matching `expect` entry. */
  pattern: RegExp;
  expect: { value: number; what: string }[];
};

const N = (value: number, what: string) => ({ value, what });

const RULES: Rule[] = [
  {
    label: "hub tagline plugin count",
    file: "CLAUDE.md",
    pattern: /\*\*(\d+) plugins\*\*/g,
    expect: [N(truth.plugins, "plugin directories")],
  },
  {
    label: "plugin CLAUDE.md coverage",
    file: "CLAUDE.md",
    pattern: /Plugin CLAUDE\.md Files \((\d+)\/(\d+)\)/g,
    expect: [N(truth.pluginsWithClaudeMd, "plugins with a CLAUDE.md"), N(truth.plugins, "plugin directories")],
  },
  {
    label: "marketplace.json registry comment",
    file: "CLAUDE.md",
    pattern: /SSoT, (\d+) plugins/g,
    expect: [N(truth.plugins, "plugin directories")],
  },
  {
    label: "directory-tree plugin count",
    file: "CLAUDE.md",
    pattern: /(\d+) marketplace plugins/g,
    expect: [N(truth.plugins, "plugin directories")],
  },
  {
    label: "reuse-registry plugin count",
    file: "CLAUDE.md",
    pattern: /across the (\d+) plugins/g,
    expect: [N(truth.plugins, "plugin directories")],
  },
  {
    label: "Python CLI count",
    file: "CLAUDE.md",
    pattern: /(\d+) CLIs across/g,
    expect: [N(truth.clis, "argparse CLIs in cli_spec.json")],
  },
  {
    label: "design-spec coverage",
    file: "CLAUDE.md",
    pattern: /(\d+) of (\d+) ADRs (?:has|have) one/g,
    expect: [N(truth.designSpecs, "ADRs with a design spec"), N(truth.adrs, "ADRs in docs/adr/")],
  },
  {
    label: "All Plugins heading",
    file: "plugins/CLAUDE.md",
    pattern: /^## All Plugins \((\d+)\)/gm,
    expect: [N(truth.plugins, "plugin directories")],
  },
];

// ── Check ─────────────────────────────────────────────────────────────────────────────────────
const lineOf = (text: string, index: number) => text.slice(0, index).split("\n").length;

const drift: string[] = [];
const inconclusive: string[] = [];
let located = 0;
let compared = 0;

for (const rule of RULES) {
  const path = p(rule.file);
  if (!existsSync(path)) {
    inconclusive.push(`${rule.file} does not exist — cannot check "${rule.label}"`);
    continue;
  }
  const text = readFileSync(path, "utf8");
  const matches = [...text.matchAll(rule.pattern)];

  if (matches.length === 0) {
    inconclusive.push(
      `no match for "${rule.label}" in ${rule.file} — pattern ${rule.pattern} found nothing. ` +
        `Either the claim was deleted or it was reworded; update the pattern, do not delete the rule.`,
    );
    continue;
  }

  for (const m of matches) {
    located += 1;
    const line = lineOf(text, m.index ?? 0);
    rule.expect.forEach((exp, i) => {
      compared += 1;
      const claimed = Number(m[i + 1]);
      if (claimed !== exp.value) {
        drift.push(
          `${rule.file}:${line}  ${rule.label} — claims ${claimed}, actual ${exp.value} (${exp.what})\n` +
            `      matched text: ${JSON.stringify(m[0])}`,
        );
      }
    });
  }
}

// The ground truth itself must be plausible. A zero here means the repo layout moved and every
// comparison above was against nothing — a pass would be meaningless.
for (const [key, value] of Object.entries(truth)) {
  if (key !== "designSpecs" && value === 0) {
    inconclusive.push(`ground truth "${key}" computed as 0 — the repo layout moved; this gate is blind`);
  }
}

// ── Report ────────────────────────────────────────────────────────────────────────────────────
const summary =
  `${RULES.length} rules · ${located} claims located · ${compared} numbers compared ` +
  `(plugins=${truth.plugins}, with CLAUDE.md=${truth.pluginsWithClaudeMd}, ADRs=${truth.adrs}, ` +
  `design specs=${truth.designSpecs}, Python CLIs=${truth.clis})`;

if (inconclusive.length > 0) {
  console.error("✗ INCONCLUSIVE — this gate could not check what it claims to check\n");
  for (const msg of inconclusive) console.error(`    ${msg}`);
  console.error(`\n  ${summary}`);
  console.error(
    "\n  A gate that examines nothing must never report PASS. Fix the pattern in\n" +
      "  scripts/verify-doc-counts.ts so it matches the current wording, then re-run.",
  );
  process.exit(2);
}

if (drift.length > 0) {
  console.error("✗ documentation counts disagree with the filesystem\n");
  for (const msg of drift) console.error(`    ${msg}`);
  console.error("\n  True counts — write these verbatim, never increment by hand:\n");
  console.error(`    ${String(truth.plugins).padStart(3)}  plugin directories under plugins/`);
  console.error(`    ${String(truth.pluginsWithClaudeMd).padStart(3)}  of those carrying a CLAUDE.md`);
  console.error(`    ${String(truth.adrs).padStart(3)}  ADRs in docs/adr/`);
  console.error(`    ${String(truth.designSpecs).padStart(3)}  of those ADRs with a design spec in docs/design/`);
  console.error(`    ${String(truth.clis).padStart(3)}  Python argparse CLIs in cli_spec.json`);
  console.error(`\n  ${summary}`);
  process.exit(1);
}

console.log(`✓ documentation counts match the filesystem — ${summary}`);
