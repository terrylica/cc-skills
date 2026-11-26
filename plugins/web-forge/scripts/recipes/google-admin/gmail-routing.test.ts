import { describe, expect, test } from "bun:test";
import { UsageError } from "../../lib/args.ts";
import type { FormState } from "../../lib/form.ts";
import { candidates, diffRule, observedFromForm, orgUnitFromText, planForm, refusal, specFromFlags } from "./gmail-routing.ts";

const flags = {
  account: "admin@example.com",
  "org-unit": "example.com",
  description: "old@example.net redirected to new@ (2026-11-26)",
  messages: "outbound",
  "account-types": "users",
  "envelope-recipient": "single:Old@Example.net",
  "change-envelope-recipient": "New@example.com",
  "add-original-to-header": true,
};

// Shape captured from the live console on 2026-11-26 (an "Add setting" dialog filled by this recipe, read back
// before Cancel), with the addresses replaced.
const liveForm: FormState = {
  listboxes: ["Modify message", "Apply address lists to correspondents", "Single email address"],
  checkboxes: [
    ["Inbound messages", false],
    ["Outbound messages", true],
    ["Internal outbound messages", false],
    ["Internal inbound messages", false],
    ["Active user accounts", true],
    ["Group accounts", false],
    ["All inactive and unrecognized accounts", false],
    ["Archived accounts with assigned delegate", false],
    ["Add X-Gm-Original-To header", true],
    ["Add X-Gm-Spam and X-Gm-Phishy headers", false],
    ["Add custom headers", false],
    ["Prepend custom subject", false],
    ["Change route", false],
    ["Also reroute spam", false],
    ["Suppress bounces from this recipient", false],
    ["Change envelope recipient", true],
    ["Bypass spam filter for this message", false],
    ["Remove attachments from message", false],
    ["Add more recipients", false],
    ["Require secure transport (TLS)", false],
    ["Notify sender when mail is quarantined (onward delivery only)", false],
    ["Use address lists to bypass or control application of this setting", false],
    ["Only affect specific envelope senders", false],
    ["Only affect specific envelope recipients", true],
  ].map(([label, checked]) => ({ label: label as string, checked: checked as boolean })),
  radios: [
    { label: "Replace recipient", checked: true },
    { label: "Replace username", checked: false },
    { label: "Replace domain", checked: false },
    { label: "Bypass this setting for specific addresses / domains", checked: false },
    { label: "Only apply this setting for specific addresses / domains", checked: false },
  ],
  textboxes: [
    { label: "Routing", value: "old@example.net redirected to new@ (2026-11-26)", visible: true },
    { label: "Enter new subject prefix", value: "", visible: false },
    { label: "Enter new email address", value: "new@example.com", visible: true },
    { label: "Enter new username", value: "", visible: true },
    { label: "Enter new domain", value: "", visible: true },
    { label: "Custom message (optional)", value: "", visible: false },
    { label: "Custom message: Archived users with assigned delegates (optional)", value: "", visible: false },
    { label: "Email address:", value: "", visible: false },
    { label: "Regexp Learn more", value: "", visible: false },
    { label: "Email address:", value: "old@example.net", visible: true },
    { label: "Regexp Learn more", value: "", visible: false },
  ],
  text: "Add setting\nLearn more\nRouting\n1. Email messages to affect\nInbound messages\nOutbound messages\n",
};

describe("specFromFlags", () => {
  test("parses lists and lower-cases addresses", () => {
    const s = specFromFlags(flags);
    expect(s.messages).toEqual(["outbound"]);
    expect(s.accountTypes).toEqual(["users"]);
    expect(s.envelopeRecipient).toEqual({ kind: "single", value: "old@example.net" });
    expect(s.changeEnvelopeRecipient).toBe("new@example.com");
    expect(s.orgUnit).toBe("example.com");
  });
  test("account types default to active users", () => {
    expect(specFromFlags({ ...flags, "account-types": undefined }).accountTypes).toEqual(["users"]);
  });
  test.each([
    [{ description: "" }, /--description is required/],
    [{ messages: "" }, /--messages is required/],
    [{ messages: "outbound,sideways" }, /must be one of/],
    [{ "account-types": "robots" }, /must be one of/],
    [{ "envelope-recipient": "pattern:.*" }, /use single:<email>/],
    [{ "envelope-recipient": "single:not-an-address" }, /use single:<email>/],
    [{ "change-envelope-recipient": "nobody" }, /not an email address/],
    [{ "change-envelope-recipient": undefined, "add-original-to-header": false }, /would do nothing/],
  ])("refuses %j", (over, rx) => {
    expect(() => specFromFlags({ ...flags, ...over })).toThrow(UsageError);
    expect(() => specFromFlags({ ...flags, ...over })).toThrow(rx);
  });
});

describe("planForm", () => {
  const ops = planForm(specFromFlags(flags));
  test("starts with the description and sets every message-type box", () => {
    expect(ops[0]).toEqual({ op: "fill", label: "Routing", value: flags.description });
    expect(ops.filter((o) => o.op === "tick" && o.label.endsWith("messages")).map((o) => o.op === "tick" && o.want)).toEqual([false, true, false, false]);
  });
  test("replaces the recipient right after ticking Change envelope recipient", () => {
    const i = ops.findIndex((o) => o.op === "tick" && o.label === "Change envelope recipient");
    expect(ops[i]).toEqual({ op: "tick", label: "Change envelope recipient", want: true });
    expect(ops[i + 1]).toEqual({ op: "radio", label: "Replace recipient" });
    expect(ops[i + 2]).toEqual({ op: "fill", label: "Enter new email address", value: "new@example.com" });
  });
  test("ends with the envelope filter: senders clear, recipients ticked, then kind and address", () => {
    expect(ops.slice(-4)).toEqual([
      { op: "tick", label: "Only affect specific envelope senders", want: false },
      { op: "tick", label: "Only affect specific envelope recipients", want: true },
      { op: "select", option: "Single email address" },
      { op: "fill", label: "Email address:", value: "old@example.net" },
    ]);
  });
  test("without an envelope recipient the filter box is cleared and nothing is filled", () => {
    const o = planForm(specFromFlags({ ...flags, "envelope-recipient": undefined }));
    expect(o.at(-1)).toEqual({ op: "tick", label: "Only affect specific envelope recipients", want: false });
  });
});

describe("observedFromForm + diffRule", () => {
  test("the live form reads as the spec, with no difference", () => {
    const o = observedFromForm(liveForm);
    expect(o.envelopeFilter).toEqual({ kind: "Single email address", value: "old@example.net" });
    expect(diffRule(specFromFlags(flags), o)).toEqual([]);
  });
  test("the recipients' address is the LAST 'Email address:' field (the senders' one comes first, hidden)", () => {
    const swapped = { ...liveForm, textboxes: liveForm.textboxes.map((t, i) => (i === 7 ? { ...t, value: "decoy@example.org" } : t)) };
    expect(observedFromForm(swapped).envelopeFilter?.value).toBe("old@example.net");
  });
  test("any extra ticked box is a difference", () => {
    const extra = { ...liveForm, checkboxes: liveForm.checkboxes.map((c) => (c.label === "Inbound messages" || c.label === "Only affect specific envelope senders" ? { ...c, checked: true } : c)) };
    const fields = diffRule(specFromFlags(flags), observedFromForm(extra)).map((d) => d.field);
    expect(fields).toContain("messages");
    expect(fields).toContain("envelopeSenders");
  });
  test("a different replacement address is a difference", () => {
    const other = { ...liveForm, textboxes: liveForm.textboxes.map((t) => (t.label === "Enter new email address" ? { ...t, value: "else@example.com" } : t)) };
    expect(diffRule(specFromFlags(flags), observedFromForm(other)).map((d) => d.field)).toEqual(["envelope.recipient"]);
  });
});

describe("candidates and org unit", () => {
  test("matches the Description column exactly", () => {
    const rules = [
      { index: 0, cells: { Description: "Default delegation rule" } },
      { index: 1, cells: { Description: flags.description } },
      { index: 2, cells: { Description: `${flags.description} (old)` } },
    ];
    expect(candidates(rules, specFromFlags(flags)).map((r) => r.index)).toEqual([1]);
  });
  test("reads the org unit line", () => {
    expect(orgUnitFromText("Gmail\nShowing settings for users in example.com\nRouting")).toBe("example.com");
    expect(orgUnitFromText("no such line")).toBeNull();
  });
});

describe("refusal", () => {
  const spec = specFromFlags(flags);
  const o = observedFromForm(liveForm);
  test("the spec's own enabled rule is accepted", () => {
    expect(refusal(spec, { Description: flags.description, Status: "Enabled" }, o)).toBeNull();
  });
  test("a dialog showing another rule's description is never treated as the spec's rule", () => {
    const other = { ...o, description: "Default delegation rule" };
    expect(refusal(spec, { Description: flags.description, Status: "Enabled" }, other)?.action).toBe("row-mismatch");
  });
  test("a disabled rule does not verify, even when its dialog matches", () => {
    expect(refusal(spec, { Description: flags.description, Status: "Disabled" }, o)?.action).toBe("disabled");
    expect(refusal(spec, { Description: flags.description }, o)?.action).toBe("disabled");
  });
});
