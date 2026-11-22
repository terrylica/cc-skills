/**
 * The standing-rules file: validate it against the instruction files it classifies and the hooks that really run,
 * then join each rule with the outcome counts of its enforcers.
 *
 * Escape tokens may be written as a list of parts (["SHELL-SAFETY", "-OK"]) and are joined only in memory, because
 * some hooks disarm themselves for a whole file when a full token appears anywhere in it.
 */
import { existsSync, readFileSync } from "node:fs";
import { basename, join } from "node:path";
import type { Outcomes } from "./aggregate.ts";
import type { Inventory } from "./inventory.ts";

export const CATEGORIES = ["authority-irreversible", "repository-contract", "operating-preference", "domain-methodology"] as const;
export const ORIGINS = ["operator-policy", "observed-mistake"] as const;
export const STATUSES = ["undecided", "keep", "narrow", "reconsider", "retire"] as const;
export const MODES = ["block", "remind", "code-check"] as const;

export interface Enforcement {
  enforcer: string;
  event?: string;
  mode: (typeof MODES)[number];
  inspects?: string;
  escape?: string | string[];
  tags?: string[];
}

export interface Rule {
  id: string;
  title: string;
  hub_section: string;
  category: string;
  origin: string;
  status: string;
  scope?: string;
  consequence?: string;
  enforcement?: Enforcement[];
  known_gaps?: string[];
  rationale_ref?: string[];
  incidents?: string[];
  tests?: string[];
}

export interface RuleCheck {
  id: string;
  problems: string[];
  enforcers: { enforcer: string; mode: string; exists: boolean; registered: "yes" | "no" | "not-a-hook" }[];
  honestStatus: "blocked-by-guard" | "reminder-only" | "code-check-only" | "no-enforcer";
  outcomes: { deny: number; context: number; decisionBlock: number };
}

export interface RulesReport {
  file: string;
  rules: number;
  coverage: { expected: string[]; missing: string[]; unknown: string[] };
  checks: RuleCheck[];
  problems: number;
}

function expandHome(p: string): string {
  return p.startsWith("~/") ? join(process.env.HOME ?? "", p.slice(2)) : p;
}

/** `### ` headings inside one `## <section>` of a Markdown file. */
export function headingsInSection(markdown: string, section: string): string[] {
  const lines = markdown.split("\n");
  const start = lines.findIndex((l) => l.startsWith("## ") && l.slice(3).trim().startsWith(section));
  if (start < 0) return [];
  const out: string[] = [];
  for (const l of lines.slice(start + 1)) {
    if (l.startsWith("## ")) break;
    if (l.startsWith("### ")) out.push(l.slice(4).trim());
  }
  return out;
}

/** Bold lead-ins of bullets (`- **Title** …`) inside one `## <section>`. */
export function boldBulletsInSection(markdown: string, section: string): string[] {
  const lines = markdown.split("\n");
  const start = lines.findIndex((l) => l.startsWith("## ") && l.slice(3).trim().startsWith(section));
  if (start < 0) return [];
  const out: string[] = [];
  for (const l of lines.slice(start + 1)) {
    if (l.startsWith("## ")) break;
    const m = l.match(/^- \*\*(.+?)\*\*/);
    if (m?.[1]) out.push(m[1].replace(/:$/, "").trim());
  }
  return out;
}

function hookKeys(inventory: Inventory): Set<string> {
  const keys = new Set<string>();
  for (const h of inventory.handlers) {
    keys.add(h.hookId.replace(/\.(ts|mjs|js|sh|py)$/, ""));
    for (const s of h.subhooks ?? []) keys.add(s.name);
  }
  return keys;
}

function isRegistered(enforcerPath: string, keys: Set<string>): boolean {
  const stem = basename(enforcerPath).replace(/\.(ts|mjs|js|sh|py)$/, "");
  const short = stem.replace(/^(pretooluse|posttooluse|stop|sessionstart|userpromptsubmit)-/, "");
  return keys.has(stem) || keys.has(short) || keys.has(short.replace(/-for-orchestrator$/, ""));
}

export interface RulesOptions {
  file: string;
  expected: string[];
  inventory: Inventory;
  outcomes?: Outcomes | undefined;
  /** Escape-hatch marker registry: a token declared there counts even when the enforcer imports it as a constant. */
  markerRegistry?: string | undefined;
}

export function checkRules(opts: RulesOptions): RulesReport {
  const parsed = Bun.TOML.parse(readFileSync(opts.file, "utf8")) as { rule?: Rule[] };
  const rules = parsed.rule ?? [];
  const keys = hookKeys(opts.inventory);
  const sections = new Set(rules.map((r) => r.hub_section));
  const coverage = {
    expected: opts.expected,
    missing: opts.expected.filter((t) => !sections.has(t)),
    unknown: opts.expected.length > 0 ? [...sections].filter((s) => !opts.expected.includes(s)) : [],
  };
  const ids = new Set<string>();
  const registryText = opts.markerRegistry && existsSync(opts.markerRegistry) ? readFileSync(opts.markerRegistry, "utf8") : "";
  const checks: RuleCheck[] = rules.map((r) => {
    const problems: string[] = [];
    for (const field of ["id", "title", "hub_section", "category", "origin", "status"] as const) {
      if (typeof r[field] !== "string" || r[field] === "") problems.push(`missing ${field}`);
    }
    if (ids.has(r.id)) problems.push(`duplicate id ${r.id}`);
    ids.add(r.id);
    if (!(CATEGORIES as readonly string[]).includes(r.category)) problems.push(`category "${r.category}" not in ${CATEGORIES.join("|")}`);
    if (!(ORIGINS as readonly string[]).includes(r.origin)) problems.push(`origin "${r.origin}" not in ${ORIGINS.join("|")}`);
    if (!(STATUSES as readonly string[]).includes(r.status)) problems.push(`status "${r.status}" not in ${STATUSES.join("|")}`);
    const enforcers: RuleCheck["enforcers"] = [];
    const outcomes = { deny: 0, context: 0, decisionBlock: 0 };
    for (const e of r.enforcement ?? []) {
      if (!(MODES as readonly string[]).includes(e.mode)) problems.push(`mode "${e.mode}" not in ${MODES.join("|")}`);
      const path = expandHome(e.enforcer);
      const exists = existsSync(path);
      if (!exists) problems.push(`enforcer not found: ${e.enforcer}`);
      const registered = e.mode === "code-check" ? "not-a-hook" : isRegistered(path, keys) ? "yes" : "no";
      if (registered === "no") problems.push(`enforcer not registered in any loaded hook: ${basename(path)}`);
      if (e.escape && exists) {
        const token = Array.isArray(e.escape) ? e.escape.join("") : e.escape;
        const bare = token.replace(/[:=].*$/, "").trim();
        if (!readFileSync(path, "utf8").includes(bare) && !registryText.includes(`"${bare}"`)) {
          problems.push(`escape token not found in ${basename(path)} or the marker registry`);
        }
      }
      enforcers.push({ enforcer: e.enforcer, mode: e.mode, exists, registered });
      for (const tag of e.tags ?? []) {
        const row = opts.outcomes?.byTag[tag];
        if (!row) continue;
        outcomes.deny += row.deny;
        outcomes.context += row.context;
        outcomes.decisionBlock += row.decisionBlock;
      }
    }
    for (const ref of r.rationale_ref ?? []) {
      const [file, frag] = ref.split("#");
      const path = expandHome(file ?? "");
      if (!existsSync(path)) problems.push(`rationale file not found: ${file}`);
      else if (frag && !readFileSync(path, "utf8").includes(frag)) problems.push(`rationale anchor "${frag}" not found in ${file}`);
    }
    const live = enforcers.filter((x) => x.exists && x.registered !== "no");
    const honestStatus: RuleCheck["honestStatus"] = live.some((x) => x.mode === "block")
      ? "blocked-by-guard"
      : live.some((x) => x.mode === "remind")
        ? "reminder-only"
        : live.some((x) => x.mode === "code-check")
          ? "code-check-only"
          : "no-enforcer";
    return { id: r.id, problems, enforcers, honestStatus, outcomes };
  });
  const problems = checks.reduce((n, c) => n + c.problems.length, 0) + coverage.missing.length + coverage.unknown.length;
  return { file: opts.file, rules: rules.length, coverage, checks, problems };
}
