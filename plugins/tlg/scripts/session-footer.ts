// session-footer.ts — provenance footer appended to every composed Telegram send.
//
// Project policy: every COMPOSED send — `send`, a `send-file` caption, and a `draft` —
// carries a session-reference footer, for all recipients, so the Telegram history doubles
// as a provenance trail. `forward` is exempt (it relays existing messages, composing no new
// text). `--no-footer` (opts.noFooter) opts out for a message whose provenance must not
// travel (e.g. an external/sensitive chat, or relaying a one-time code); `--context` adds
// an optional label.
//
// Format:
//   ------
//   via Claude Code | session <uuid> | <context> | <timestamp>
//
// The context label is OPT-IN: it is included only when `--context` is passed. It never
// defaults to the working-directory name, which would disclose a project or client folder
// name to every recipient. The session id and timestamp carry the reference on their own.
//
// Idempotent: content that already contains a Claude Code footer — e.g. text piped from a
// draft tool whose marker reads "Parked by Claude Code …" — is NOT re-stamped, so its own
// marker survives.

import process from "node:process";

export const FOOTER_RULE = "------";

// Matches an existing Claude Code provenance footer under any marker wording so we never
// double-stamp. Anchored to the rule line to avoid matching prose that merely mentions it.
export const FOOTER_RE = /\n------\n(?:Parked by|Sent via|via) Claude Code \| session /;

// British Columbia's own abbreviation (2026-11-08). Since 1 Nov 2026 BC keeps UTC-7 all year and the
// province names it "Pacific Time", abbreviated PCT (BC government, "No falling back with B.C.'s new time
// zone code, Pacific Time: PCT"). tzdb 2026f labels the same offset MST for America/Vancouver and has not
// adopted PCT (tz list thread "British Columbia (BC) announced PCT abbreviation for Pacific Time"), and
// Apple's ICU still prints PDT. Keyed on the ZONE and the instant, never a blanket MST rewrite: Arizona,
// America/Edmonton, Fort_Nelson, Dawson_Creek and Creston really are MST, and BC's PST/PDT before the
// change were correct then.
const BC_ZONES = new Set(["America/Vancouver", "Canada/Pacific"]);
/** 2026-11-01 02:00 PDT = 09:00 UTC, the first instant of BC's permanent UTC-7. */
export const BC_PCT_FROM_MS = Date.UTC(2026, 10, 1, 9, 0, 0);

/** The short zone name for `d` in `zone`: ICU's, except "PCT" for British Columbia from 2026-11-01. */
export function zoneAbbrev(d: Date, zone: string): string {
  if (BC_ZONES.has(zone) && d.getTime() >= BC_PCT_FROM_MS) {
    return "PCT";
  }
  return (
    new Intl.DateTimeFormat("en-US", { timeZone: zone, timeZoneName: "short" })
      .formatToParts(d)
      .find((p) => p.type === "timeZoneName")?.value ?? ""
  );
}

/** Local wall-clock stamp, e.g. "2026-11-08 19:14 PCT". `zone` defaults to the process's own zone. */
export function localTimestamp(
  d: Date = new Date(),
  zone: string = Intl.DateTimeFormat().resolvedOptions().timeZone,
): string {
  const date = d.toLocaleDateString("en-CA", { timeZone: zone }); // YYYY-MM-DD
  const time = d.toLocaleTimeString("en-US", { timeZone: zone, hour: "2-digit", minute: "2-digit", hour12: false });
  return `${date} ${time} ${zoneAbbrev(d, zone)}`.trim();
}

/** The footer block to append. `context` is an opt-in label; omitted when not supplied. */
export function sessionFooter(context?: string, now: Date = new Date()): string {
  const sid = process.env.CLAUDE_CODE_SESSION_ID?.trim();
  const ctx = (context ?? "").trim();
  const parts = ["via Claude Code"];
  if (sid) {
    parts.push(`session ${sid}`);
  }
  if (ctx) {
    parts.push(ctx);
  }
  parts.push(localTimestamp(now));
  return `\n\n${FOOTER_RULE}\n${parts.join(" | ")}`;
}

export interface FooterOptions {
  readonly noFooter?: boolean | undefined;
  readonly context?: string | undefined;
  readonly now?: Date | undefined;
}

/** Append the session footer unless opted out (noFooter) or one is already present. */
export function applyFooter(message: string, opts: FooterOptions = {}): string {
  if (opts.noFooter) {
    return message;
  }
  if (FOOTER_RE.test(`\n${message}`)) {
    return message;
  }
  return message + sessionFooter(opts.context, opts.now);
}
