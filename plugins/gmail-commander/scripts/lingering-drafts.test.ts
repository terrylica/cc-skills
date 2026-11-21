// Tests for the lingering-draft checks. The fixtures mirror the 2026-11-21 incident: a batch of new
// emails to one person was re-ranked and redrafted, and an earlier cover draft stayed in the Drafts
// folder next to its replacement because each new message sits in its own thread.
//
// Run: bun test plugins/gmail-commander/scripts/lingering-drafts.test.ts
import { describe as group, expect, test } from "bun:test";
import { addresses, auditDrafts, findLingering, listDraftMeta, subjectKey, type DraftMeta } from "./lingering-drafts.ts";
import { draftIdsIn, parseAuditArgs } from "./gmail-drafts-audit.ts";

const FROM = "Sam Doe <sam@example.org>";
const TO = "Alex <alex@example.net>";
const CC = "boss@example.net";
let n = 0;
const draft = (subject: string, over: Partial<DraftMeta> = {}): DraftMeta => ({
  id: `r${1000000000000 + ++n}`,
  threadId: `t${n}`,
  from: FROM,
  to: TO,
  cc: CC,
  subject,
  date: n * 1000,
  ...over,
});

group("subjectKey", () => {
  test("a re-ranked tally does not make a different email", () => {
    expect(subjectKey("⣿⣶⣿ The agreement: please reply")).toBe(subjectKey("⣶⣴⣿ The agreement: please reply"));
  });
  test("reply prefixes, case and spacing are ignored", () => {
    expect(subjectKey("Re: RE:  The   Agreement")).toBe("the agreement");
    expect(subjectKey("⣿ Fwd: The agreement")).toBe("the agreement");
  });
  test("a changed wording is a different subject", () => {
    expect(subjectKey("Consent: please approve")).not.toBe(subjectKey("Consent: adopted; please put it in the forms"));
  });
});

test("addresses reads names, angle brackets and lists", () => {
  expect([...addresses('"Doe, Sam" <Sam@Example.org>, b@c.io; d@e.io')]).toEqual(["sam@example.org", "b@c.io", "d@e.io"]);
});

group("findLingering", () => {
  test("REGRESSION 2026-11-21: an earlier cover in another thread is superseded", () => {
    const old = draft("Our first contact: the ranked list");
    const created = draft("Our first contact: the ranked list");
    const found = findLingering(created, [old]);
    expect(found.superseded.map((d) => d.id)).toEqual([old.id]);
    expect(found.related).toEqual([]);
  });
  test("the same email with a new tally is superseded", () => {
    const old = draft("⣿⣴⣶ The passkey, two minutes");
    expect(findLingering(draft("⣶⣿⣿ The passkey, two minutes"), [old]).superseded).toHaveLength(1);
  });
  test("other drafts to the same person are related, not superseded", () => {
    const other = draft("For information: a new page");
    const found = findLingering(draft("The passkey"), [other]);
    expect(found.superseded).toEqual([]);
    expect(found.related.map((d) => d.id)).toEqual([other.id]);
  });
  test("REVIEW 2026-11-21: a shared CC alone ties nothing (the owner copied on everything)", () => {
    const toVendor = draft("Re: Invoice", { to: "vendor@else.io" });
    const sameSubjectToVendor = draft("Invoice", { to: "vendor@else.io" });
    expect(findLingering(draft("Invoice"), [toVendor, sameSubjectToVendor])).toEqual({ superseded: [], related: [] });
  });
  test("REVIEW 2026-11-21: a reply is never superseded by a new message of the same subject", () => {
    const reply = draft("Re: Invoice");
    const found = findLingering(draft("Invoice"), [reply]);
    expect(found.superseded).toEqual([]);
    expect(found.related.map((d) => d.id)).toEqual([reply.id]);
  });
  test("a shared To address is enough, whatever the Cc", () => {
    const other = draft("The passkey", { to: `${TO}, extra@else.io`, cc: "" });
    expect(findLingering(draft("The passkey"), [other]).superseded).toHaveLength(1);
  });
  test("another sender, or nobody in common, is left alone", () => {
    const otherSender = draft("The passkey", { from: "Other <o@example.org>" });
    const otherPeople = draft("The passkey", { to: "x@y.io", cc: "" });
    expect(findLingering(draft("The passkey"), [otherSender, otherPeople])).toEqual({ superseded: [], related: [] });
  });
  test("drafts in the same thread are left to the one-draft-per-thread check", () => {
    const created = draft("Re: hello");
    const sameThread = draft("Re: hello", { threadId: created.threadId });
    expect(findLingering(created, [sameThread])).toEqual({ superseded: [], related: [] });
  });
  test("the new draft itself is never a finding", () => {
    const created = draft("x");
    expect(findLingering(created, [created])).toEqual({ superseded: [], related: [] });
  });
  test("an empty subject never supersedes", () => {
    expect(findLingering(draft(""), [draft("")]).superseded).toEqual([]);
  });
});

group("auditDrafts", () => {
  test("without a keep list only exact repeats are flagged, and the newest survives", () => {
    const a = draft("⣿ The roster");
    const b = draft("⣶ The roster");
    const c = draft("Something else");
    const got = auditDrafts([a, b, c]);
    expect(got.superseded.map((s) => [s.draft.id, s.by.id])).toEqual([[a.id, b.id]]);
    expect(got.outOfPlay).toEqual([]);
  });
  test("with a keep list, other drafts to the same people are out of play; unrelated mail is untouched", () => {
    const cover = draft("Cover");
    const staleFyi = draft("FYI, withdrawn");
    const unrelated = draft("Lunch", { to: "friend@else.io", cc: "" });
    const fromSomeoneElse = draft("Hi", { from: "x@y.io" });
    const got = auditDrafts([cover, staleFyi, unrelated, fromSomeoneElse], new Set([cover.id]));
    expect(got.outOfPlay.map((d) => d.id)).toEqual([staleFyi.id]);
    expect(got.superseded).toEqual([]);
  });
  test("a kept draft is never flagged, even when a newer copy exists", () => {
    const kept = draft("The roster");
    const newer = draft("The roster");
    const got = auditDrafts([kept, newer], new Set([kept.id]));
    expect(got.superseded).toEqual([]);
    expect(got.outOfPlay.map((d) => d.id)).toEqual([newer.id]);
  });
  test("REVIEW 2026-11-21: a draft sharing only the Cc with a kept draft is not out of play", () => {
    const kept = draft("Cover");
    const toVendor = draft("Quote", { to: "vendor@else.io" });
    expect(auditDrafts([kept, toVendor], new Set([kept.id])).outOfPlay).toEqual([]);
  });
  test("kept ids missing from the folder are reported", () => {
    expect(auditDrafts([draft("a")], new Set(["r999999999999999"])).missingKept).toEqual(["r999999999999999"]);
  });
});

test("listDraftMeta pages the list and reads each draft's headers", async () => {
  const calls: string[] = [];
  const api = async (path: string): Promise<Record<string, unknown>> => {
    calls.push(path);
    if (path === "drafts?maxResults=100") return { drafts: [{ id: "r1" }], nextPageToken: "p2" };
    if (path === "drafts?maxResults=100&pageToken=p2") return { drafts: [{ id: "r2" }] };
    const id = path.split("/")[1]!.split("?")[0]!;
    return {
      id,
      message: { threadId: `t-${id}`, internalDate: "5000", payload: { headers: [{ name: "Subject", value: `S ${id}` }, { name: "To", value: TO }, { name: "From", value: FROM }] } },
    };
  };
  const got = await listDraftMeta(api);
  expect(got.map((d) => [d.id, d.subject, d.threadId, d.date, d.cc])).toEqual([
    ["r1", "S r1", "t-r1", 5000, ""],
    ["r2", "S r2", "t-r2", 5000, ""],
  ]);
  expect(calls.filter((c) => c.startsWith("drafts/")).every((c) => c.includes("format=metadata"))).toBe(true);
});

test("REVIEW 2026-11-21: a Drafts folder larger than the cap is an error, never a clean pass", async () => {
  let page = 0;
  const api = async (path: string): Promise<Record<string, unknown>> => {
    if (path.startsWith("drafts?")) {
      page++;
      return { drafts: Array.from({ length: 100 }, (_, i) => ({ id: `r${page}-${i}` })), nextPageToken: `p${page + 1}` };
    }
    return { id: "x", message: {} };
  };
  await expect(listDraftMeta(api)).rejects.toThrow("more than 500 drafts");
});

group("gmail-drafts-audit arguments", () => {
  test("keep ids come from flags (comma lists) and files", () => {
    expect(parseAuditArgs(["--account", "a", "--keep", "r111111111111,r-222222222222", "--keep", "r333333333333", "--prune"])).toEqual({
      account: "a",
      keep: ["r111111111111", "r-222222222222", "r333333333333"],
      keepFiles: [],
      prune: true,
    });
  });
  test("a flag without its value is refused", () => {
    expect(() => parseAuditArgs(["--account", "a", "--keep"])).toThrow("--keep needs a value");
  });
  test("draft ids are found in a manifest; message ids are not", () => {
    const manifest = JSON.stringify([{ draft: "r-1234567890123456789", message: "0123456789abcdef" }, { draft: "r9876543210987654321" }]);
    expect(draftIdsIn(manifest)).toEqual(["r-1234567890123456789", "r9876543210987654321"]);
  });
});
