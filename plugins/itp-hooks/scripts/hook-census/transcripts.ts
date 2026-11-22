/**
 * Hook outcomes from Claude Code session transcripts, one file at a time, payload-free.
 *
 * Reads <projects>/**\/*.jsonl and *.jsonl.br (Brotli, decompressed in-process with node:zlib, no child process),
 * keeps only files modified on or after --since, skips any line that cannot be a hook record before parsing it, and
 * turns each hook record into a small event: kind, event, tool, a guard tag or hook id, milliseconds, ids and time.
 * Tags are the guard's own leading `[TAG]` (capped), never the text after it; commands become a file name.
 *
 * Record shapes (Claude Code 2.1.119 to 2.1.325, measured 2026-11-16):
 *  - type "user" + permissionDecision {decision:"reject", source:"hook"}: a PreToolUse deny; the tool result reads
 *    "PreToolUse:<Tool> hook error: <reason>".
 *  - permissionDecision with reasonCode "hook:<Event>" and a user source: an ask the person answered.
 *  - type "attachment": hook_success / hook_non_blocking_error (command, durationMs), hook_cancelled (timeout),
 *    hook_additional_context (content[]), hook_blocking_error (mostly PostToolUse context, not a block).
 *  - type "system", subtype "stop_hook_summary": every Stop hook with durationMs.
 */
import { createReadStream, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { createBrotliDecompress } from "node:zlib";
import { hookIdFromCommand } from "./command.ts";

export type CensusEventKind = "deny" | "ask" | "context" | "decision-block" | "timeout" | "subhook-timeout" | "error" | "duration";

export interface CensusEvent {
  kind: CensusEventKind;
  event: string;
  tool?: string | undefined;
  tag?: string | undefined;
  hookId?: string | undefined;
  ms?: number | undefined;
  timeoutMs?: number | undefined;
  outcome?: "accept" | "reject" | undefined;
  sessionId?: string | undefined;
  toolUseId?: string | undefined;
  ts?: string | undefined;
  file?: string | undefined;
}

const TAG_MAX = 80;
const LINE_HINTS = ['"type":"hook_', '"source":"hook"', '"reasonCode":"hook:', '"subtype":"stop_hook_summary"'];

/** The id every prompt hook is timed under: its prompt is payload, and the inventory never lists one by text. */
export const PROMPT_HOOK_ID = "prompt-hook";

/** The guard tag at the head of a hook message: `[TAG]`, a sub-hook name, or a script name; never the text after it. */
export function extractTags(text: string): string[] {
  const head = text.trimStart();
  const subhooks = [...head.matchAll(/\[orchestrator-subhook: ([^\]\n]{1,80})\]/g)].map((m) => m[1] ?? "");
  if (subhooks.length > 0) return subhooks;
  const editOrch = /^\[pretooluse-edit-time-orchestrator\] ([\w.-]{1,80}) → (DENY|ASK)/.exec(head);
  if (editOrch?.[1]) return [editOrch[1]];
  const bracket = /^\[([^\]\n]{1,200})\]/.exec(head);
  if (bracket?.[1]) {
    const inner = bracket[1];
    if (/[/\s]/.test(inner) && /\.(sh|ts|mjs|js|py)\b/.test(inner)) return [hookIdFromCommand(inner)];
    return [`[${inner.slice(0, TAG_MAX)}]`];
  }
  // Leading plain words only: the first word holding anything else (a path, an address, a quote) ends the tag,
  // because what follows is often the guard echoing the command it refused.
  const words: string[] = [];
  for (const w of head.replace(/^[^A-Za-z0-9]+/, "").split(/\s+/).slice(0, 4)) {
    if (/^\d+[:,.]?$/.test(w)) words.push(w.replace(/\d+/, "N"));
    else if (/^[A-Za-z][A-Za-z-]*[:,.]?$/.test(w)) words.push(w);
    else break;
  }
  return [`untagged:${words.join(" ").slice(0, 40)}`];
}

/** "[name] timed out after Nms" lines inside hook output: orchestrator sub-hook timeouts. */
function subhookTimeouts(text: string): { name: string; ms: number }[] {
  return [...text.matchAll(/\[([\w.-]{1,80})\] timed out after (\d+)ms/g)].map((m) => ({ name: m[1] ?? "", ms: Number(m[2]) }));
}

type Rec = Record<string, unknown>;

function str(v: unknown): string | undefined {
  return typeof v === "string" ? v : undefined;
}

function num(v: unknown): number | undefined {
  return typeof v === "number" && Number.isFinite(v) ? v : undefined;
}

function toolResultText(rec: Rec): string {
  const content = (rec.message as Rec | undefined)?.content;
  const first = Array.isArray(content) ? (content[0] as Rec | undefined) : undefined;
  const c = first?.content;
  if (typeof c === "string") return c;
  if (Array.isArray(c)) return c.map((x) => (typeof (x as Rec)?.text === "string" ? (x as Rec).text : "")).join("");
  return typeof rec.toolUseResult === "string" ? rec.toolUseResult.replace(/^Error: /, "") : "";
}

export function classifyRecord(rec: Rec, file?: string): CensusEvent[] {
  const base = { sessionId: str(rec.sessionId) ?? str(rec.session_id), ts: str(rec.timestamp), file };
  const out: CensusEvent[] = [];
  const pd = rec.permissionDecision as Rec | undefined;
  if (rec.type === "user" && pd) {
    const reasonCode = str(pd.reasonCode) ?? "";
    if (pd.decision === "reject" && pd.source === "hook") {
      const text = toolResultText(rec);
      const m = /^(\w+):(\w+) hook error: ([\s\S]*)$/.exec(text);
      const toolUseId = str(((rec.message as Rec | undefined)?.content as Rec[] | undefined)?.[0]?.tool_use_id);
      out.push({ ...base, kind: "deny", event: m?.[1] ?? "PreToolUse", tool: m?.[2], tag: extractTags(m?.[3] ?? text)[0], toolUseId });
    } else if (reasonCode.startsWith("hook:") && pd.source !== "hook") {
      out.push({ ...base, kind: "ask", event: reasonCode.slice(5), outcome: pd.decision === "accept" ? "accept" : "reject" });
    }
    return out;
  }
  if (rec.type === "system" && rec.subtype === "stop_hook_summary") {
    for (const info of Array.isArray(rec.hookInfos) ? (rec.hookInfos as Rec[]) : []) {
      const cmd = str(info.command);
      const ms = num(info.durationMs);
      // A prompt hook's entry carries promptText, and its command holds the prompt with the user's words in it.
      const hookId = "promptText" in info ? PROMPT_HOOK_ID : cmd ? hookIdFromCommand(cmd) : undefined;
      if (hookId && ms !== undefined) out.push({ ...base, kind: "duration", event: "Stop", hookId, ms, toolUseId: str(rec.toolUseID) });
    }
    return out;
  }
  if (rec.type !== "attachment") return out;
  const a = rec.attachment as Rec | undefined;
  if (!a) return out;
  const type = str(a.type) ?? "";
  if (!type.startsWith("hook_")) return out;
  const event = str(a.hookEvent) ?? str(a.hookName)?.split(":")[0];
  if (!event) return out;
  const toolUseId = str(a.toolUseID);
  const cmd = str(a.command) ?? str((a.blockingError as Rec | undefined)?.command);
  const hookId = cmd ? hookIdFromCommand(cmd) : undefined;
  const ms = num(a.durationMs);
  const common = { ...base, event, toolUseId };
  if (type === "hook_success" || type === "hook_non_blocking_error") {
    if (hookId && ms !== undefined) out.push({ ...common, kind: "duration", hookId, ms });
    if (type === "hook_non_blocking_error") out.push({ ...common, kind: "error", hookId, ms });
  } else if (type === "hook_cancelled") {
    out.push({ ...common, kind: "timeout", hookId, ms, timeoutMs: num(a.timeoutMs) });
  } else if (type === "hook_additional_context") {
    const texts = Array.isArray(a.content) ? a.content.filter((x): x is string => typeof x === "string") : [];
    for (const t of texts) {
      for (const tag of extractTags(t)) out.push({ ...common, kind: "context", tag });
      for (const st of subhookTimeouts(t)) out.push({ ...common, kind: "subhook-timeout", hookId: st.name, timeoutMs: st.ms });
    }
  } else if (type === "hook_blocking_error") {
    const t = str((a.blockingError as Rec | undefined)?.blockingError) ?? "";
    for (const tag of extractTags(t)) out.push({ ...common, kind: "decision-block", tag, hookId });
    for (const st of subhookTimeouts(t)) out.push({ ...common, kind: "subhook-timeout", hookId: st.name, timeoutMs: st.ms });
  }
  return out;
}

export interface TranscriptFile {
  path: string;
  mtimeMs: number;
  compressed: boolean;
}

/** Every *.jsonl and *.jsonl.br under the projects directory (subagent transcripts included), newest first. */
export function listTranscriptFiles(projectsDir: string, sinceMs: number): TranscriptFile[] {
  const out: TranscriptFile[] = [];
  const walk = (dir: string, depth: number): void => {
    let entries: import("node:fs").Dirent[];
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const p = join(dir, e.name);
      if (e.isDirectory()) {
        if (depth < 4) walk(p, depth + 1);
        continue;
      }
      const compressed = e.name.endsWith(".jsonl.br");
      if (!compressed && !e.name.endsWith(".jsonl")) continue;
      try {
        const mtimeMs = statSync(p).mtimeMs;
        if (mtimeMs >= sinceMs) out.push({ path: p, mtimeMs, compressed });
      } catch {
        // vanished between listing and stat
      }
    }
  };
  walk(projectsDir, 0);
  return out.toSorted((x, y) => y.mtimeMs - x.mtimeMs);
}

export interface ScanStats {
  files: number;
  lines: number;
  parsed: number;
  badLines: number;
  unreadable: number;
}

/** Stream one transcript and call onEvent for each hook event inside [sinceMs, untilMs). */
export async function scanTranscript(
  file: TranscriptFile,
  sinceMs: number,
  untilMs: number,
  onEvent: (e: CensusEvent) => void,
  stats: ScanStats,
): Promise<void> {
  stats.files++;
  const raw = createReadStream(file.path);
  const stream = file.compressed ? raw.pipe(createBrotliDecompress()) : raw;
  const rl = createInterface({ input: stream, crlfDelay: Number.POSITIVE_INFINITY });
  try {
    for await (const line of rl) {
      stats.lines++;
      if (!LINE_HINTS.some((h) => line.includes(h))) continue;
      let rec: Rec;
      try {
        rec = JSON.parse(line) as Rec;
      } catch {
        stats.badLines++;
        continue;
      }
      stats.parsed++;
      const ts = typeof rec.timestamp === "string" ? Date.parse(rec.timestamp) : Number.NaN;
      if (Number.isFinite(ts) && (ts < sinceMs || ts >= untilMs)) continue;
      for (const e of classifyRecord(rec, file.path)) onEvent(e);
    }
  } catch {
    stats.unreadable++;
  } finally {
    rl.close();
    raw.destroy();
  }
}
