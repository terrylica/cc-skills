/**
 * Fold census events into outcome counts and timing statistics, and read the two extra timing sources: the
 * orchestrators' sub-hook timing files (hooks/lib/orchestrator-subhook-timing.ts) and Claude Code debug logs.
 */
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { hookIdFromCommand } from "./command.ts";
import type { CensusEvent } from "./transcripts.ts";

export interface TagCounts {
  deny: number;
  context: number;
  decisionBlock: number;
  sessions: number;
}

export interface DenySample {
  tag: string;
  ts?: string | undefined;
  sessionId?: string | undefined;
  toolUseId?: string | undefined;
  file?: string | undefined;
}

export interface Outcomes {
  window: { since: string; until: string };
  totals: Record<string, number>;
  byTag: Record<string, TagCounts>;
  asks: Record<string, { accept: number; reject: number }>;
  timeouts: Record<string, { count: number; timeoutMs: number[] }>;
  subhookTimeouts: Record<string, number>;
  errors: Record<string, number>;
  denyByDay: Record<string, number>;
  sessionsWithHookEvents: number;
  samples: DenySample[];
}

export class OutcomeAccumulator {
  private readonly byTag = new Map<string, TagCounts & { sessionSet: Set<string> }>();
  private readonly totals: Record<string, number> = {};
  private readonly asks: Outcomes["asks"] = {};
  private readonly timeouts: Outcomes["timeouts"] = {};
  private readonly subhookTimeouts: Record<string, number> = {};
  private readonly errors: Record<string, number> = {};
  private readonly denyByDay: Record<string, number> = {};
  private readonly sessions = new Set<string>();
  private readonly samplesByTag = new Map<string, DenySample[]>();

  constructor(private readonly samplesPerTag: number) {}

  add(e: CensusEvent): void {
    if (e.kind === "duration") return;
    this.totals[e.kind] = (this.totals[e.kind] ?? 0) + 1;
    if (e.sessionId) this.sessions.add(e.sessionId);
    if ((e.kind === "deny" || e.kind === "context" || e.kind === "decision-block") && e.tag) {
      const tag = e.tag;
      const row = this.byTag.get(tag) ?? { deny: 0, context: 0, decisionBlock: 0, sessions: 0, sessionSet: new Set<string>() };
      if (e.kind === "deny") row.deny++;
      else if (e.kind === "context") row.context++;
      else row.decisionBlock++;
      if (e.sessionId) row.sessionSet.add(e.sessionId);
      this.byTag.set(tag, row);
    }
    if (e.kind === "deny") {
      const day = e.ts?.slice(0, 10);
      if (day) this.denyByDay[day] = (this.denyByDay[day] ?? 0) + 1;
      const list = e.tag ? (this.samplesByTag.get(e.tag) ?? []) : [];
      if (e.tag && list.length < this.samplesPerTag) {
        list.push({ tag: e.tag, ts: e.ts, sessionId: e.sessionId, toolUseId: e.toolUseId, file: e.file });
        this.samplesByTag.set(e.tag, list);
      }
    } else if (e.kind === "ask") {
      const row = this.asks[e.event] ?? { accept: 0, reject: 0 };
      if (e.outcome === "accept") row.accept++;
      else row.reject++;
      this.asks[e.event] = row;
    } else if (e.kind === "timeout" && e.hookId) {
      const row = this.timeouts[e.hookId] ?? { count: 0, timeoutMs: [] };
      row.count++;
      if (e.timeoutMs !== undefined && !row.timeoutMs.includes(e.timeoutMs)) row.timeoutMs.push(e.timeoutMs);
      this.timeouts[e.hookId] = row;
    } else if (e.kind === "subhook-timeout" && e.hookId) {
      this.subhookTimeouts[e.hookId] = (this.subhookTimeouts[e.hookId] ?? 0) + 1;
    } else if (e.kind === "error" && e.hookId) {
      this.errors[e.hookId] = (this.errors[e.hookId] ?? 0) + 1;
    }
  }

  result(window: Outcomes["window"]): Outcomes {
    const byTag: Record<string, TagCounts> = {};
    const ordered = [...this.byTag.entries()].toSorted((a, b) => b[1].deny - a[1].deny || b[1].context - a[1].context);
    for (const [tag, row] of ordered) {
      byTag[tag] = { deny: row.deny, context: row.context, decisionBlock: row.decisionBlock, sessions: row.sessionSet.size };
    }
    return {
      window,
      totals: this.totals,
      byTag,
      asks: this.asks,
      timeouts: this.timeouts,
      subhookTimeouts: this.subhookTimeouts,
      errors: this.errors,
      denyByDay: Object.fromEntries(Object.entries(this.denyByDay).toSorted(([a], [b]) => a.localeCompare(b))),
      sessionsWithHookEvents: this.sessions.size,
      samples: [...this.samplesByTag.values()].flat(),
    };
  }
}

export interface Stat {
  count: number;
  p50: number;
  p95: number;
  max: number;
  total: number;
}

export function stat(values: number[]): Stat {
  const v = values.toSorted((a, b) => a - b);
  const at = (q: number) => v[Math.min(v.length - 1, Math.max(0, Math.ceil(q * v.length) - 1))] ?? 0;
  const total = v.reduce((s, x) => s + x, 0);
  return { count: v.length, p50: at(0.5), p95: at(0.95), max: v.at(-1) ?? 0, total: Math.round(total) };
}

export interface Timing {
  window: { since: string; until: string };
  sources: Record<string, number>;
  perHook: Record<string, Stat & { event: string }>;
  perSubhook: Record<string, Stat & { orchestrator: string; verdicts: Record<string, number> }>;
  perEventCall: Record<string, Stat>;
  perSession: Stat;
  notes: string[];
}

export class TimingAccumulator {
  private readonly hook = new Map<string, { event: string; ms: number[] }>();
  private readonly sub = new Map<string, { orchestrator: string; ms: number[]; verdicts: Record<string, number> }>();
  private readonly call = new Map<string, { event: string; session: string | undefined; max: number }>();
  readonly sources: Record<string, number> = { transcript: 0, subhookTiming: 0, debugLog: 0 };

  addHook(event: string, hookId: string, ms: number, sessionId?: string, toolUseId?: string): void {
    const key = `${event} ${hookId}`;
    const row = this.hook.get(key) ?? { event, ms: [] };
    row.ms.push(ms);
    this.hook.set(key, row);
    if (toolUseId) {
      const ck = `${event}|${toolUseId}`;
      const c = this.call.get(ck) ?? { event, session: sessionId, max: 0 };
      c.max = Math.max(c.max, ms);
      this.call.set(ck, c);
    }
  }

  addEvent(e: CensusEvent): void {
    if (e.kind !== "duration" || e.ms === undefined || !e.hookId) return;
    this.sources.transcript = (this.sources.transcript ?? 0) + 1;
    this.addHook(e.event, e.hookId, e.ms, e.sessionId, e.toolUseId);
  }

  addSubhook(orchestrator: string, subhook: string, ms: number, verdict: string): void {
    const row = this.sub.get(subhook) ?? { orchestrator, ms: [], verdicts: {} };
    row.ms.push(ms);
    row.verdicts[verdict] = (row.verdicts[verdict] ?? 0) + 1;
    this.sub.set(subhook, row);
    this.sources.subhookTiming = (this.sources.subhookTiming ?? 0) + 1;
  }

  result(window: Timing["window"], notes: string[]): Timing {
    // Each stat sorts a copy of its samples, so compute it once per row and sort the rows by the result.
    const byP95 = <T extends { p95: number }>(rows: [string, T][]) => rows.toSorted((a, b) => b[1].p95 - a[1].p95);
    const perHook: Timing["perHook"] = Object.fromEntries(byP95([...this.hook].map(([k, v]) => [k, { event: v.event, ...stat(v.ms) }])));
    const perSubhook: Timing["perSubhook"] = Object.fromEntries(
      byP95([...this.sub].map(([k, v]) => [k, { orchestrator: v.orchestrator, verdicts: v.verdicts, ...stat(v.ms) }])),
    );
    const byEvent = new Map<string, number[]>();
    const bySession = new Map<string, number>();
    for (const c of this.call.values()) {
      const values = byEvent.get(c.event);
      if (values) values.push(c.max);
      else byEvent.set(c.event, [c.max]);
      if (c.session) bySession.set(c.session, (bySession.get(c.session) ?? 0) + c.max);
    }
    const perEventCall: Timing["perEventCall"] = {};
    for (const [ev, values] of byEvent) perEventCall[ev] = stat(values);
    return { window, sources: this.sources, perHook, perSubhook, perEventCall, perSession: stat([...bySession.values()]), notes };
  }
}

/** Fold the orchestrators' timing-<date>.jsonl files whose date is inside the window. */
export function readSubhookTimingFiles(dir: string, since: string, until: string, acc: TimingAccumulator): number {
  if (!existsSync(dir)) return 0;
  let lines = 0;
  for (const f of readdirSync(dir).filter((n) => /^timing-\d{4}-\d{2}-\d{2}\.jsonl$/.test(n))) {
    const day = f.slice(7, 17);
    if (day < since.slice(0, 10) || day > until.slice(0, 10)) continue;
    for (const raw of readFileSync(join(dir, f), "utf8").split("\n")) {
      if (!raw) continue;
      try {
        const r = JSON.parse(raw) as Record<string, unknown>;
        if (typeof r.elapsedMs === "number" && typeof r.subhook === "string" && typeof r.orchestrator === "string" && typeof r.verdict === "string") {
          acc.addSubhook(r.orchestrator, r.subhook, r.elapsedMs, r.verdict);
          lines++;
        }
      } catch {
        // skip a torn line
      }
    }
  }
  return lines;
}

const DEBUG_HOOK_LINE = /^(\S+) \[DEBUG\] Hooks: (\w+)(?::[^\s[]*)? \[(.+?)\](?: \(plugin [^)]*\))? finished with status (-?\d+) \((\d+)ms\)/;

/** Per-hook times for every hook, silent ones included, from Claude Code debug logs (`--debug-file`). */
export function readDebugLogs(dir: string, sinceMs: number, untilMs: number, acc: TimingAccumulator): number {
  if (!existsSync(dir)) return 0;
  let count = 0;
  for (const f of readdirSync(dir).filter((n) => n.endsWith(".txt"))) {
    let text: string;
    try {
      text = readFileSync(join(dir, f), "utf8");
    } catch {
      continue;
    }
    for (const raw of text.split("\n")) {
      const m = raw.match(DEBUG_HOOK_LINE);
      if (!m) continue;
      const ts = Date.parse(m[1] ?? "");
      if (Number.isFinite(ts) && (ts < sinceMs || ts >= untilMs)) continue;
      if (!m[2] || !m[3]) continue;
      acc.addHook(m[2], hookIdFromCommand(m[3]), Number(m[5]));
      acc.sources.debugLog = (acc.sources.debugLog ?? 0) + 1;
      count++;
    }
  }
  return count;
}
