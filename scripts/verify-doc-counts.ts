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
 * Rules sweep every CLAUDE.md rather than one hardcoded path, and a broad residue detector catches
 * a claim reworded out of every known shape even when other sites still match — see the comments
 * on `claudeMdFiles` and `CLAIM_FAMILIES` for why each of those exists and what it costs.
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
    return execFileSync("git", ["rev-parse", "--show-toplevel"], {
      encoding: "utf8",
    }).trim();
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
    (name) =>
      !name.startsWith(".") && statSync(p("plugins", name)).isDirectory(),
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
  pluginsWithClaudeMd: plugins.filter((name) =>
    existsSync(p("plugins", name, "CLAUDE.md")),
  ).length,
  adrs: adrs.length,
  designSpecs: adrsWithDesignSpec(adrs).length,
  clis: cliCount(),
};

/**
 * Every CLAUDE.md in the repo, which is the scope every rule below is checked against.
 *
 * Rules are NOT pinned to one file. The first version of this gate hardcoded `file: "CLAUDE.md"`
 * per rule, and that shape produced its own defect: docs/CLAUDE.md asserted the same design-spec
 * numbers twice and the gate never looked at them, so a hand-correction there went unchecked — the
 * exact manual increment this gate exists to forbid. Sweeping the whole hierarchy means a claim
 * added to a FOURTH CLAUDE.md tomorrow is covered the day it lands, with no rule edit.
 * (Finding the scope this way immediately turned up a third site, docs/design/CLAUDE.md, that was
 * still stale at "33 of 58" and that nobody had listed.)
 *
 * Scope is CLAUDE.md files PLUS the root README.md — deliberately not all markdown. CHANGELOG.md,
 * docs/adr/*.md and published release notes quote PAST states on purpose; "correcting" a historical
 * number there would be vandalism. A CLAUDE.md describes the present by definition, so present-tense
 * counts in one are always fair game.
 *
 * The root README.md was added to that scope on 2026-09-05, after the gate passed clean while
 * README.md advertised "42 plugins" in four places — the badge at :5, the install one-liner's
 * comment at :66, and the directory tree at :471 and :472 — against a real 41. That is the EXACT
 * stale value named in this file's own header as the reason the gate was written, and it survived
 * because the sweep could not see the file. A gate that reports PASS while the repo's most-read
 * public page states the number it was built to police is worse than no gate: it certifies the
 * drift. README.md is present-tense and describes the repo as it is now, so it belongs in scope for
 * the same reason a CLAUDE.md does. Per-plugin READMEs are NOT included; several legitimately
 * describe their own subtree rather than the marketplace, so sweeping them would produce false
 * positives, and no observed drift has come from them.
 */
function claudeMdFiles(dir = ROOT, out: string[] = []): string[] {
  const SKIP = new Set([
    "node_modules",
    ".git",
    ".build",
    "worktrees",
    "dist",
    ".venv",
  ]);
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (SKIP.has(entry.name)) continue;
      claudeMdFiles(join(dir, entry.name), out);
    } else if (entry.name === "CLAUDE.md") {
      out.push(join(dir, entry.name));
    }
  }
  return out;
}

const DOC_FILES = [...claudeMdFiles(), p("README.md")].filter((f) =>
  existsSync(f),
);

// ── The claims ────────────────────────────────────────────────────────────────────────────────
type Rule = {
  label: string;
  /** Global regex; every capture group is a number that must equal the matching `expect` entry. */
  pattern: RegExp;
  expect: { value: number; what: string }[];
};

const N = (value: number, what: string) => ({ value, what });

const SPEC_COVERAGE = [
  N(truth.designSpecs, "ADRs with a design spec"),
  N(truth.adrs, "ADRs in docs/adr/"),
];

const RULES: Rule[] = [
  {
    label: "hub tagline plugin count",
    pattern: /\*\*(\d+) plugins\*\*/g,
    expect: [N(truth.plugins, "plugin directories")],
  },
  {
    label: "plugin CLAUDE.md coverage",
    pattern: /Plugin CLAUDE\.md Files \((\d+)\/(\d+)\)/g,
    expect: [
      N(truth.pluginsWithClaudeMd, "plugins with a CLAUDE.md"),
      N(truth.plugins, "plugin directories"),
    ],
  },
  {
    label: "marketplace.json registry comment",
    pattern: /SSoT, (\d+) plugins/g,
    expect: [N(truth.plugins, "plugin directories")],
  },
  {
    label: "directory-tree plugin count",
    pattern: /(\d+) marketplace plugins/g,
    expect: [N(truth.plugins, "plugin directories")],
  },
  {
    label: "reuse-registry plugin count",
    pattern: /across the (\d+) plugins/g,
    expect: [N(truth.plugins, "plugin directories")],
  },
  // The three shapes below are README.md's, and they are the reason README.md was added to the
  // sweep. Adding the FILE alone changed nothing: of README's four "42 plugins" sites, only
  // ":472 42 marketplace plugins" matched an existing rule, so re-introducing the stale value at
  // any of the other three still passed. Measured, not assumed — reverting the install-one-liner
  // comment to "42" was checked against the widened gate and it still exited 0. Scope and coverage
  // are different things, and widening the first without the second produces a gate that looks
  // broader while checking exactly as much as before.
  {
    label: "README shields.io plugin badge",
    pattern: /badge\/plugins-(\d+)-/g,
    expect: [N(truth.plugins, "plugin directories")],
  },
  {
    label: "README install one-liner plugin count",
    pattern: /Install all (\d+) plugins/g,
    expect: [N(truth.plugins, "plugin directories")],
  },
  {
    label: "README directory-tree registry comment",
    pattern: /Plugin registry \((\d+) plugins\)/g,
    expect: [N(truth.plugins, "plugin directories")],
  },
  {
    label: "Python CLI count",
    pattern: /(\d+) CLIs across/g,
    expect: [N(truth.clis, "argparse CLIs in cli_spec.json")],
  },
  // The design-spec claim appears in two distinct SHAPES, so it gets two precise rules rather than
  // one loose pattern that could over-fire on unrelated prose. Shape 1 ("…ADRs have one") is used
  // in three files today — root CLAUDE.md's directory tree, docs/CLAUDE.md's directory tree, and
  // docs/design/CLAUDE.md's opening line. Shape 2 ("…ADRs have a design spec") is the prose
  // sentence in docs/CLAUDE.md. Because rules sweep the whole hierarchy, shape 1's three sites are
  // covered by one rule and any fourth site is covered automatically.
  {
    label: "design-spec coverage (shape: 'N of M ADRs have one')",
    pattern: /(\d+) of (\d+) ADRs (?:has|have) one/g,
    expect: SPEC_COVERAGE,
  },
  {
    label: "design-spec coverage (shape: 'N of M ADRs have a design spec')",
    pattern: /(\d+) of (\d+) ADRs (?:has|have) a design spec/g,
    expect: SPEC_COVERAGE,
  },
  {
    label: "All Plugins heading",
    pattern: /^## All Plugins \((\d+)\)/gm,
    expect: [N(truth.plugins, "plugin directories")],
  },
];

// ── Check ─────────────────────────────────────────────────────────────────────────────────────
const lineOf = (text: string, index: number) =>
  text.slice(0, index).split("\n").length;

const drift: string[] = [];
const inconclusive: string[] = [];
let located = 0;
let compared = 0;

const rel = (path: string) => path.slice(ROOT.length + 1);
const texts = new Map(
  DOC_FILES.map((path) => [path, readFileSync(path, "utf8")]),
);

/** Where the precise rules actually looked, so the residue check below can find what they missed. */
const covered = new Map<string, [number, number][]>();

for (const rule of RULES) {
  let hits = 0;

  for (const [path, text] of texts) {
    for (const m of text.matchAll(rule.pattern)) {
      hits += 1;
      located += 1;
      const start = m.index ?? 0;
      if (!covered.has(path)) covered.set(path, []);
      covered.get(path)!.push([start, start + m[0].length]);
      const line = lineOf(text, m.index ?? 0);
      rule.expect.forEach((exp, i) => {
        compared += 1;
        const claimed = Number(m[i + 1]);
        if (claimed !== exp.value) {
          drift.push(
            `${rel(path)}:${line}  ${rule.label} — claims ${claimed}, actual ${exp.value} (${exp.what})\n` +
              `      matched text: ${JSON.stringify(m[0])}`,
          );
        }
      });
    }
  }

  // Zero hits ACROSS THE WHOLE HIERARCHY means the rule checked nothing at all.
  if (hits === 0) {
    inconclusive.push(
      `no match for "${rule.label}" in any of the ${DOC_FILES.length} CLAUDE.md files — ` +
        `pattern ${rule.pattern} found nothing. Either the claim was deleted or it was reworded; ` +
        `update the pattern, do not delete the rule.`,
    );
  }
}

/**
 * ── Residue check: the hole that hierarchy-wide sweeping would otherwise open ───────────────────
 * A rule is INCONCLUSIVE only when it matches nowhere. With one rule covering three sites, someone
 * could reword ONE of them, leave the other two matching, and the gate would pass while the
 * reworded site drifted unchecked — a quieter version of the very gap this sweep was added to fix.
 *
 * So: a deliberately BROAD detector finds anything shaped like a claim in this family, and every
 * broad hit must overlap a span some precise rule actually matched. Anything left over is a claim
 * written in a shape no rule recognises, and is reported rather than ignored. The broad pattern is
 * tuned to the measured corpus — plural "ADRs", no punctuation in the gap — which today finds
 * exactly the four real claim sites and does NOT fire on the version-then-"ADR" prose in
 * plugins/gh-tools/skills/gh-fine-grained-pat/CLAUDE.md:95. Broad enough to catch a rewording,
 * narrow enough not to cry wolf.
 */
const CLAIM_FAMILIES: { label: string; broad: RegExp }[] = [
  { label: "ADR / design-spec coverage", broad: /\d+[^.,()\n]{0,24}\bADRs\b/g },
];

for (const family of CLAIM_FAMILIES) {
  for (const [path, text] of texts) {
    const spans = covered.get(path) ?? [];
    for (const m of text.matchAll(family.broad)) {
      const start = m.index ?? 0;
      const end = start + m[0].length;
      const overlapped = spans.some(([s, e]) => s < end && start < e);
      if (!overlapped) {
        inconclusive.push(
          `${rel(path)}:${lineOf(text, start)} states a "${family.label}" claim that no rule checks: ` +
            `${JSON.stringify(m[0])}. It was reworded out of every known shape — add or widen a rule.`,
        );
      }
    }
  }
}

// The ground truth itself must be plausible. A zero here means the repo layout moved and every
// comparison above was against nothing — a pass would be meaningless.
for (const [key, value] of Object.entries(truth)) {
  if (key !== "designSpecs" && value === 0) {
    inconclusive.push(
      `ground truth "${key}" computed as 0 — the repo layout moved; this gate is blind`,
    );
  }
}

// Likewise the scan surface. If the walker stopped finding CLAUDE.md files, every rule above would
// report zero hits for a reason that has nothing to do with the docs.
for (const required of [
  "CLAUDE.md",
  "plugins/CLAUDE.md",
  "docs/CLAUDE.md",
  "README.md",
]) {
  if (!DOC_FILES.includes(p(required))) {
    inconclusive.push(
      `${required} was not picked up by the doc sweep — the walker is broken or the file moved`,
    );
  }
}

// ── Report ────────────────────────────────────────────────────────────────────────────────────
const summary =
  `${RULES.length} rules · ${DOC_FILES.length} doc files swept (CLAUDE.md + root README.md) · ${located} claims located · ` +
  `${compared} numbers compared (plugins=${truth.plugins}, with CLAUDE.md=${truth.pluginsWithClaudeMd}, ` +
  `ADRs=${truth.adrs}, design specs=${truth.designSpecs}, Python CLIs=${truth.clis})`;

if (inconclusive.length > 0) {
  console.error(
    "✗ INCONCLUSIVE — this gate could not check what it claims to check\n",
  );
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
  console.error(
    "\n  True counts — write these verbatim, never increment by hand:\n",
  );
  console.error(
    `    ${String(truth.plugins).padStart(3)}  plugin directories under plugins/`,
  );
  console.error(
    `    ${String(truth.pluginsWithClaudeMd).padStart(3)}  of those carrying a CLAUDE.md`,
  );
  console.error(`    ${String(truth.adrs).padStart(3)}  ADRs in docs/adr/`);
  console.error(
    `    ${String(truth.designSpecs).padStart(3)}  of those ADRs with a design spec in docs/design/`,
  );
  console.error(
    `    ${String(truth.clis).padStart(3)}  Python argparse CLIs in cli_spec.json`,
  );
  console.error(`\n  ${summary}`);
  process.exit(1);
}

console.log(`✓ documentation counts match the filesystem — ${summary}`);
