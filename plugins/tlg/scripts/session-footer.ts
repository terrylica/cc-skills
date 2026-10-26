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

/** Local wall-clock stamp, e.g. "2026-10-25 19:14 PDT". */
export function localTimestamp(d: Date = new Date()): string {
  const date = d.toLocaleDateString("en-CA"); // YYYY-MM-DD
  const time = d.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", hour12: false });
  const tz = d.toLocaleTimeString("en-US", { timeZoneName: "short" }).split(" ").pop() ?? "";
  return `${date} ${time} ${tz}`.trim();
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
