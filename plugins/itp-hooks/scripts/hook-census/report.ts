/** REPORT.md and labels.toml from the census JSON. Payload-free: tags, ids, counts and milliseconds only. */
import type { Outcomes, Stat, Timing } from "./aggregate.ts";
import type { Inventory } from "./inventory.ts";
import type { RulesReport } from "./rules.ts";

const ms = (n: number) => `${Math.round(n)} ms`;
const statCells = (s: Stat) => `${s.count} | ${ms(s.p50)} | ${ms(s.p95)} | ${ms(s.max)}`;

export interface ReportInput {
  generated: string;
  run: { wallMs: number; maxRssMb: number; files: number; lines: number };
  inventory: Inventory;
  outcomes: Outcomes;
  timing: Timing;
  rules?: RulesReport | undefined;
  top: number;
}

export function renderReport(r: ReportInput): string {
  const L: string[] = [];
  const inv = r.inventory;
  L.push(`# Hook census, ${r.generated.slice(0, 10)}`, "");
  L.push(
    `Window ${r.outcomes.window.since.slice(0, 10)} to ${r.outcomes.window.until.slice(0, 10)}. Scanned ${r.run.files} transcript files (${r.run.lines} lines) in ${Math.round(r.run.wallMs / 1000)} s, peak RSS ${r.run.maxRssMb} MB as the process reads it (\`/usr/bin/time -l\` reports more). Every figure is a tag, id, count or duration; no command, file content or prompt text is kept.`,
    "",
  );

  L.push("## Inventory", "");
  L.push(
    `${inv.totals.registrations} registrations reach a session from ${inv.settingsFiles.length} settings file(s) and ${inv.plugins.filter((p) => p.registrations > 0).length} plugins with hooks (of ${inv.plugins.length} enabled); the orchestrators add ${inv.totals.subhooks} in-process sub-hooks.`,
    "",
  );
  L.push("| Event | Registrations |", "| --- | --- |");
  for (const [ev, n] of Object.entries(inv.totals.byEvent).toSorted((a, b) => b[1] - a[1])) L.push(`| ${ev} | ${n} |`);
  L.push("", "| Source | Registrations |", "| --- | --- |");
  for (const [src, n] of Object.entries(inv.totals.bySource).toSorted((a, b) => b[1] - a[1])) L.push(`| ${src} | ${n} |`);
  const orch = inv.handlers.filter((h) => h.subhooks);
  if (orch.length > 0) {
    L.push("", "| Orchestrator | Event | Sub-hooks | Timeouts (ms) |", "| --- | --- | --- | --- |");
    for (const h of orch) {
      const t = [...new Set((h.subhooks ?? []).map((s) => s.timeoutMs))].join(", ");
      L.push(`| ${h.hookId} | ${h.event} | ${h.subhooks?.length ?? 0} | ${t} |`);
    }
  }
  if (inv.launcherDiff) {
    const d = inv.launcherDiff;
    L.push("", `Launcher diff (first two config roots): ${d.onlyInFirst.length} hook registrations only in the first, ${d.onlyInSecond.length} only in the second.`);
  }
  if (inv.warnings.length > 0) L.push("", "Warnings:", ...inv.warnings.map((w) => `- ${w}`));

  const o = r.outcomes;
  L.push("", "## Outcomes", "");
  L.push(
    `${o.totals.deny ?? 0} denies, ${o.totals.context ?? 0} context injections, ${o.totals["decision-block"] ?? 0} PostToolUse/Stop decision blocks (context, not a stop), ${o.totals.timeout ?? 0} hook timeouts, ${o.totals["subhook-timeout"] ?? 0} sub-hook timeouts, ${o.totals.error ?? 0} hook errors, in ${o.sessionsWithHookEvents} sessions.`,
    "",
  );
  L.push(`| Guard tag | Denies | Contexts | Decision blocks | Sessions |`, "| --- | --- | --- | --- | --- |");
  for (const [tag, c] of Object.entries(o.byTag).slice(0, r.top)) L.push(`| \`${tag}\` | ${c.deny} | ${c.context} | ${c.decisionBlock} | ${c.sessions} |`);
  if (Object.keys(o.asks).length > 0) {
    L.push("", "Asks answered by the person:", ...Object.entries(o.asks).map(([ev, a]) => `- ${ev}: ${a.accept} accepted, ${a.reject} rejected`));
  }
  if (Object.keys(o.timeouts).length > 0) {
    L.push("", "Hook timeouts (Claude Code cancelled the hook):", ...Object.entries(o.timeouts).map(([id, t]) => `- \`${id}\`: ${t.count} (limit ${t.timeoutMs.join("/")} ms)`));
  }
  if (Object.keys(o.subhookTimeouts).length > 0) {
    L.push("", "Sub-hook timeouts (the orchestrator gave up, fail-open):", ...Object.entries(o.subhookTimeouts).map(([id, n]) => `- \`${id}\`: ${n}`));
  }

  const t = r.timing;
  L.push("", "## Timing", "");
  L.push(`Sources: ${Object.entries(t.sources).map(([k, v]) => `${k} ${v}`).join(", ")}.`, ...t.notes.map((n) => `- ${n}`), "");
  if (Object.keys(t.perEventCall).length > 0) {
    L.push("Slowest hook per tool call, by event:", "", "| Event | Calls | p50 | p95 | max |", "| --- | --- | --- | --- | --- |");
    for (const [ev, s] of Object.entries(t.perEventCall)) L.push(`| ${ev} | ${statCells(s)} |`);
    L.push("", `Per session, summed: ${statCells(t.perSession)} (sessions | p50 | p95 | max).`, "");
  }
  L.push("Slowest hooks by p95:", "", "| Hook | Runs | p50 | p95 | max |", "| --- | --- | --- | --- | --- |");
  for (const [k, s] of Object.entries(t.perHook).slice(0, r.top)) L.push(`| \`${k}\` | ${statCells(s)} |`);
  if (Object.keys(t.perSubhook).length > 0) {
    L.push("", "Slowest orchestrator sub-hooks by p95:", "", "| Sub-hook | Orchestrator | Runs | p50 | p95 | max | Verdicts |", "| --- | --- | --- | --- | --- | --- | --- |");
    for (const [k, s] of Object.entries(t.perSubhook).slice(0, r.top)) {
      const v = Object.entries(s.verdicts).map(([a, b]) => `${a} ${b}`).join(", ");
      L.push(`| \`${k}\` | ${s.orchestrator} | ${statCells(s)} | ${v} |`);
    }
  }

  if (r.rules) {
    const rr = r.rules;
    L.push("", "## Standing rules", "");
    L.push(`${rr.rules} rules in \`${rr.file}\`; ${rr.problems} problem(s). Missing from the file: ${rr.coverage.missing.length === 0 ? "none" : rr.coverage.missing.join("; ")}.`, "");
    L.push("| Rule | Honest status | Enforcers (mode, registered) | Denies | Contexts | Problems |", "| --- | --- | --- | --- | --- | --- |");
    for (const c of rr.checks) {
      const enf = c.enforcers.map((e) => `${e.enforcer.split("/").pop()} (${e.mode}, ${e.registered})`).join("; ");
      L.push(`| ${c.id} | ${c.honestStatus} | ${enf} | ${c.outcomes.deny} | ${c.outcomes.context} | ${c.problems.join("; ")} |`);
    }
  }
  return `${L.join("\n")}\n`;
}

/** One entry per sampled deny for the operator to mark true or false; only ids and times, never the deny text. */
export function renderLabels(o: Outcomes): string {
  const q = JSON.stringify;
  const L = [
    "# Sampled hook denies to label. Open the transcript at `file`, find `tool_use_id`, and set label to",
    '# "true" (the guard was right to block) or "false" (a false block). Leave "" when unsure.',
  ];
  for (const s of o.samples) {
    L.push("", "[[deny]]", `tag = ${q(s.tag)}`);
    if (s.ts) L.push(`ts = ${q(s.ts)}`);
    if (s.sessionId) L.push(`session = ${q(s.sessionId)}`);
    if (s.toolUseId) L.push(`tool_use_id = ${q(s.toolUseId)}`);
    if (s.file) L.push(`file = ${q(s.file)}`);
    L.push('label = ""');
  }
  return `${L.join("\n")}\n`;
}
