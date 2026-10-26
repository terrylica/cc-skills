import { afterEach, describe, expect, test } from "bun:test";
import { applyFooter, FOOTER_RE, localTimestamp, sessionFooter } from "./session-footer.ts";

const SID = "00000000-0000-4000-8000-000000000000";
const prevSid = process.env.CLAUDE_CODE_SESSION_ID;
afterEach(() => {
  if (prevSid === undefined) {
    delete process.env.CLAUDE_CODE_SESSION_ID;
  } else {
    process.env.CLAUDE_CODE_SESSION_ID = prevSid;
  }
});

describe("sessionFooter", () => {
  test("includes marker, session id, context and timestamp", () => {
    process.env.CLAUDE_CODE_SESSION_ID = SID;
    const f = sessionFooter("example project", new Date("2026-10-26T02:14:00Z"));
    expect(f.startsWith("\n\n------\n")).toBe(true);
    expect(f).toContain("via Claude Code");
    expect(f).toContain(`session ${SID}`);
    expect(f).toContain("example project");
  });

  test("omits the session token when no session id is set", () => {
    delete process.env.CLAUDE_CODE_SESSION_ID;
    const f = sessionFooter("ctx");
    expect(f).not.toContain("session ");
    expect(f).toContain("via Claude Code");
    expect(f).toContain("ctx");
  });

  test("context label is opt-in — omitted entirely when not supplied (no cwd leak)", () => {
    process.env.CLAUDE_CODE_SESSION_ID = SID;
    const f = sessionFooter(undefined, new Date("2026-10-26T02:14:00Z"));
    expect(f).toContain("via Claude Code");
    expect(f).toContain(`session ${SID}`);
    // exactly three fields: marker | session | timestamp — no context segment
    expect(f.trim().split("\n").at(-1)?.split(" | ").length).toBe(3);
  });
});

describe("applyFooter", () => {
  test("appends a footer to a plain message (the no-exception default)", () => {
    process.env.CLAUDE_CODE_SESSION_ID = SID;
    const out = applyFooter("hello", { context: "ctx" });
    expect(out.startsWith("hello\n\n------\n")).toBe(true);
    expect(FOOTER_RE.test(`\n${out}`)).toBe(true);
  });

  test("--no-footer (noFooter) leaves the message untouched", () => {
    process.env.CLAUDE_CODE_SESSION_ID = SID;
    expect(applyFooter("hello", { noFooter: true, context: "ctx" })).toBe("hello");
  });

  test("is idempotent: never double-stamps an already-footed message", () => {
    process.env.CLAUDE_CODE_SESSION_ID = SID;
    const once = applyFooter("hello", { context: "ctx" });
    const twice = applyFooter(once, { context: "ctx" });
    expect(twice).toBe(once);
  });

  test("preserves a draft-park 'Parked by Claude Code' footer without re-stamping", () => {
    process.env.CLAUDE_CODE_SESSION_ID = SID;
    const parked = `body text\n\n------\nParked by Claude Code | session ${SID} | proj | 2026-10-25 19:14 PDT`;
    const out = applyFooter(parked, { context: "ctx" });
    expect(out).toBe(parked);
    expect(out).toContain("Parked by Claude Code");
    expect(out).not.toContain("via Claude Code | session");
  });
});

describe("localTimestamp", () => {
  test("renders YYYY-MM-DD HH:MM with a timezone abbreviation", () => {
    const ts = localTimestamp(new Date("2026-10-26T02:14:00Z"));
    expect(ts).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2} \S+$/);
  });
});
