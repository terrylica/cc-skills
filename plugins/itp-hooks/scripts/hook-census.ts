#!/usr/bin/env bun
/**
 * hook-census — what the Claude Code hooks on this machine are, what they did, and what they cost.
 *
 *   bun hook-census.ts spec                         machine-readable command and flag list
 *   bun hook-census.ts inventory [flags]            every handler a session loads, sub-hooks expanded
 *   bun hook-census.ts outcomes  [flags]            denies, asks, contexts, timeouts per guard, from transcripts
 *   bun hook-census.ts timing    [flags]            p50/p95 per hook, sub-hook and event, and per session
 *   bun hook-census.ts rules --rules FILE [flags]   validate the standing-rules file and join its outcomes
 *   bun hook-census.ts report    [flags]            all of the above to <out>/{*.json,REPORT.md,labels.toml}
 *   bun hook-census.ts window --until DATE | --close   open or close the orchestrators' sub-hook timing window
 *
 * Read-only except `report` (writes its own output directory) and `window` (writes one flag file). Payload-free:
 * outputs hold tags, ids, counts and milliseconds, never commands, tool input or prompts. One process, one
 * transcript at a time. Spoke: plugins/itp-hooks/docs/hook-census.md.
 */
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, join } from "node:path";
import { parseArgs } from "node:util";
import { hookCensusDir } from "../hooks/lib/orchestrator-subhook-timing.ts";
import { OutcomeAccumulator, readDebugLogs, readSubhookTimingFiles, TimingAccumulator } from "./hook-census/aggregate.ts";
import { buildInventory, statusAliases } from "./hook-census/inventory.ts";
import { renderLabels, renderReport } from "./hook-census/report.ts";
import { boldBulletsInSection, checkRules, headingsInSection } from "./hook-census/rules.ts";
import { listTranscriptFiles, type ScanStats, scanTranscript } from "./hook-census/transcripts.ts";

const FLAGS = {
  "config-root": { type: "string", multiple: true, help: "settings root(s); first one is the session's (default: $CLAUDE_CONFIG_DIR, ~/.claude)" },
  project: { type: "string", help: "also read <dir>/.claude/settings*.json" },
  "plugin-dir": { type: "string", multiple: true, help: "module-style plugin directories (default: $CLAUDE_CODE_PLUGIN_DIRS)" },
  "projects-dir": { type: "string", help: "transcript root (default: <first config root>/projects)" },
  since: { type: "string", help: "ISO date or date-time, inclusive (default: 30 days ago)" },
  until: { type: "string", help: "ISO date or date-time, exclusive (default: now)" },
  "census-dir": { type: "string", help: "timing window and timing files (default: $ITP_HOOKS_HOOK_CENSUS_DIR or ~/.claude/state/hook-census)" },
  "debug-dir": { type: "string", multiple: true, help: "Claude Code debug-log directories (default: <first config root>/debug and $CLAUDE_CODE_DEBUG_LOGS_DIR)" },
  rules: { type: "string", help: "standing-rules TOML file" },
  "hub-file": { type: "string", multiple: true, help: "Markdown file whose ### headings under --hub-section are rules" },
  "hub-section": { type: "string", help: "## section holding the rule headings (default: Behavioral Policies)" },
  "exclude-heading": { type: "string", help: "regex of hub headings that are not rules (pointers to another file)" },
  "bullet-file": { type: "string", multiple: true, help: "Markdown file whose bold bullet lead-ins under --bullet-section are rules" },
  "bullet-section": { type: "string", help: "## section holding the bullet rules (default: Rules)" },
  "marker-registry": { type: "string", help: "escape-hatch marker registry (default: this plugin's hooks/lib/escape-hatch-marker-registry-iter111.ts)" },
  samples: { type: "string", help: "denies sampled per guard for labelling (default: 10)" },
  "gc-every": { type: "string", help: "force a garbage collection after this many transcripts, bounding peak memory (default: 50)" },
  top: { type: "string", help: "rows per table in REPORT.md (default: 30)" },
  out: { type: "string", help: "report output directory (default: <census dir>/<today>)" },
  "until-date": { type: "string", help: "window: close date (ISO)" },
  close: { type: "boolean", help: "window: remove the flag file" },
} as const;

const SPEC = {
  name: "hook-census",
  description: "Inventory, outcomes and timing of Claude Code hooks, and a standing-rules check; payload-free",
  commands: {
    spec: "this JSON",
    inventory: ["config-root", "project", "plugin-dir"],
    outcomes: ["projects-dir", "since", "until", "samples", "config-root", "gc-every"],
    timing: ["projects-dir", "since", "until", "census-dir", "debug-dir", "config-root", "gc-every"],
    rules: ["rules", "hub-file", "hub-section", "exclude-heading", "bullet-file", "bullet-section", "marker-registry", "config-root", "project", "plugin-dir"],
    report: ["all of the above", "out", "top"],
    window: ["until-date", "close", "census-dir"],
  },
  flags: Object.fromEntries(Object.entries(FLAGS).map(([k, v]) => [`--${k}`, { type: v.type, multiple: "multiple" in v, help: v.help }])),
};

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: Object.fromEntries(Object.entries(FLAGS).map(([k, v]) => [k, { type: v.type, ...("multiple" in v ? { multiple: true } : {}) }])),
});
const cmd = positionals[0] ?? "spec";
const v = values as Record<string, string | string[] | boolean | undefined>;
const list = (k: string): string[] => (Array.isArray(v[k]) ? (v[k] as string[]) : []);
const one = (k: string): string | undefined => (typeof v[k] === "string" ? (v[k] as string) : undefined);

const configRoots = list("config-root").length > 0 ? list("config-root") : [process.env.CLAUDE_CONFIG_DIR, join(homedir(), ".claude")].filter((x): x is string => !!x);
const firstRoot = configRoots[0] ?? join(homedir(), ".claude");
const pluginDirs = list("plugin-dir").length > 0 ? list("plugin-dir") : (process.env.CLAUDE_CODE_PLUGIN_DIRS ?? "").split(delimiter).filter(Boolean);
const now = Date.now();
const sinceMs = one("since") ? Date.parse(one("since") ?? "") : now - 30 * 86_400_000;
const untilMs = one("until") ? Date.parse(one("until") ?? "") : now;
if (!Number.isFinite(sinceMs) || !Number.isFinite(untilMs)) throw new Error("--since/--until must be ISO dates");
const window = { since: new Date(sinceMs).toISOString(), until: new Date(untilMs).toISOString() };
const censusDir = one("census-dir") ?? hookCensusDir();
const projectsDir = one("projects-dir") ?? join(firstRoot, "projects");
const markerRegistry = one("marker-registry") ?? join(import.meta.dir, "..", "hooks", "lib", "escape-hatch-marker-registry-iter111.ts");

function inventory() {
  return buildInventory({ configRoots, projectDir: one("project"), pluginDirs });
}

async function scan(withOutcomes: boolean, withTiming: boolean) {
  const gcEvery = Number(one("gc-every") ?? 50);
  if (!Number.isInteger(gcEvery) || gcEvery < 1) throw new Error("--gc-every must be a positive integer");
  const aliases = statusAliases(inventory());
  const outcomes = new OutcomeAccumulator(Number(one("samples") ?? 10));
  const timing = new TimingAccumulator();
  const stats: ScanStats = { files: 0, lines: 0, parsed: 0, badLines: 0, unreadable: 0 };
  for (const file of listTranscriptFiles(projectsDir, sinceMs)) {
    await scanTranscript(
      file,
      sinceMs,
      untilMs,
      (e) => {
        if (e.hookId) e.hookId = aliases.get(e.hookId) ?? e.hookId;
        if (withOutcomes) outcomes.add(e);
        if (withTiming) timing.addEvent(e);
      },
      stats,
    );
    // Parsing leaves most of each transcript as garbage; collecting every 50 files took a 30-day peak from 780 to 650 MB.
    if (stats.files % gcEvery === 0) Bun.gc(true);
  }
  const notes: string[] = [];
  if (withTiming) {
    const sub = readSubhookTimingFiles(censusDir, window.since, window.until, timing);
    const debugDirs = list("debug-dir").length > 0 ? list("debug-dir") : [join(firstRoot, "debug"), process.env.CLAUDE_CODE_DEBUG_LOGS_DIR].filter((x): x is string => !!x);
    let debug = 0;
    for (const d of debugDirs) debug += readDebugLogs(d, sinceMs, untilMs, timing);
    if (sub === 0) notes.push("No sub-hook timing lines in the window: open one with `hook-census window --until-date <date>`.");
    if (debug === 0) notes.push("No debug-log hook lines: transcript durations cover only hooks that printed output, plus every Stop hook.");
  }
  return { outcomes: outcomes.result(window), timing: timing.result(window, notes), stats };
}

function expectedRules(): string[] {
  const exclude = one("exclude-heading") ? new RegExp(one("exclude-heading") ?? "") : null;
  const out: string[] = [];
  for (const f of list("hub-file")) {
    for (const h of headingsInSection(readFileSync(f, "utf8"), one("hub-section") ?? "Behavioral Policies")) {
      if (!exclude?.test(h)) out.push(h);
    }
  }
  for (const f of list("bullet-file")) out.push(...boldBulletsInSection(readFileSync(f, "utf8"), one("bullet-section") ?? "Rules"));
  return out;
}

const print = (o: unknown) => console.log(JSON.stringify(o, null, 1));

async function main(): Promise<void> {
  const started = performance.now();
  if (cmd === "spec") return print(SPEC);
  if (cmd === "inventory") return print(inventory());
  if (cmd === "outcomes") {
    const r = await scan(true, false);
    return print({ ...r.outcomes, scan: r.stats });
  }
  if (cmd === "timing") {
    const r = await scan(false, true);
    return print({ ...r.timing, scan: r.stats });
  }
  if (cmd === "rules") {
    const file = one("rules");
    if (!file) throw new Error("rules needs --rules FILE");
    return print(checkRules({ file, expected: expectedRules(), inventory: inventory(), markerRegistry }));
  }
  if (cmd === "window") {
    mkdirSync(censusDir, { recursive: true });
    const flag = join(censusDir, "timing-window.json");
    if (v.close === true) {
      rmSync(flag, { force: true });
      return print({ window: "closed", flag });
    }
    const until = one("until-date");
    if (!until || !Number.isFinite(Date.parse(until))) throw new Error("window needs --until-date <ISO date> or --close");
    writeFileSync(flag, `${JSON.stringify({ until: new Date(Date.parse(until)).toISOString(), opened: new Date().toISOString() })}\n`);
    return print({ window: "open", until, flag });
  }
  if (cmd === "report") {
    const inv = inventory();
    const r = await scan(true, true);
    const file = one("rules");
    const rules = file ? checkRules({ file, expected: expectedRules(), inventory: inv, outcomes: r.outcomes, markerRegistry }) : undefined;
    const out = one("out") ?? join(censusDir, new Date().toISOString().slice(0, 10));
    mkdirSync(out, { recursive: true });
    const run = { wallMs: Math.round(performance.now() - started), maxRssMb: Math.round(process.resourceUsage().maxRSS / 1024), files: r.stats.files, lines: r.stats.lines };
    const write = (name: string, body: unknown) => writeFileSync(join(out, name), typeof body === "string" ? body : `${JSON.stringify(body, null, 1)}\n`);
    write("inventory.json", inv);
    write("outcomes.json", { ...r.outcomes, scan: r.stats });
    write("timing.json", r.timing);
    if (rules) write("rules.json", rules);
    write("labels.toml", renderLabels(r.outcomes));
    write("REPORT.md", renderReport({ generated: new Date().toISOString(), run, inventory: inv, outcomes: r.outcomes, timing: r.timing, rules, top: Number(one("top") ?? 30) }));
    return print({ out, run, problems: rules?.problems });
  }
  throw new Error(`unknown command ${cmd}; see \`hook-census spec\``);
}

await main();
