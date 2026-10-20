import { describe, expect, test } from "bun:test";
import { UsageError } from "../lib/args.ts";
import type { FormState } from "../lib/form.ts";
import { candidates, diffRule, LABELS, observedFromForm, parseTable, planForm, sameMatch, type Spec, specFromFlags } from "./gmail-default-routing.ts";

const flags = {
  account: "admin@example.com",
  description: "Staff mail → shared inbox",
  match: "group:Staff-Mail@Example.com",
  "change-envelope-recipient": "Inbox@example.com",
  "add-original-to-header": true,
  scope: "non-recognized",
};

// Shape captured from the live console on 2026-10-19 (an "Edit setting" dialog), with names replaced.
const liveForm: FormState = {
  listboxes: ["Group membership", "Modify message"],
  checkboxes: [
    { label: "Add X-Gm-Original-To header", checked: true },
    { label: "Add X-Gm-Spam and X-Gm-Phishy headers", checked: false },
    { label: "Add custom headers", checked: false },
    { label: "Prepend custom subject", checked: false },
    { label: "Change route", checked: false },
    { label: "Also reroute spam", checked: false },
    { label: "Suppress bounces from this recipient", checked: false },
    { label: "Change envelope recipient", checked: true },
    { label: "Bypass spam filter for this message", checked: false },
    { label: "Remove attachments from message", checked: false },
    { label: "Add more recipients", checked: false },
  ],
  radios: [
    { label: "Replace recipient", checked: true },
    { label: "Replace username", checked: false },
    { label: "Replace domain", checked: false },
    { label: "Perform this action only on non-recognized addresses", checked: true },
    { label: "Perform this action on non-recognized and recognized addresses", checked: false },
  ],
  textboxes: [
    { label: "Email address:", value: "", visible: false },
    { label: "Enter new email address", value: "inbox@example.com", visible: true },
    { label: "Enter new username", value: "", visible: true },
  ],
  text: "Edit setting\nLearn more\n1. Specify envelope recipients to match\nSingle recipient\nPattern match\nGroup membership\nAll recipients\nStaff mail (routing to inbox@)(staff-mail@example.com)\nDelete\nSelect groups\n2. If the envelope recipient matches the above, do the following\nModify message\nReject message\nHeaders\n",
};

describe("specFromFlags", () => {
  test("parses and lower-cases addresses", () => {
    const s = specFromFlags(flags);
    expect(s.match).toEqual({ kind: "group", value: "staff-mail@example.com" });
    expect(s.changeEnvelopeRecipient).toBe("inbox@example.com");
    expect(s.addOriginalToHeader).toBe(true);
    expect(s.scope).toBe("non-recognized");
  });
  test("all, single and pattern", () => {
    expect(specFromFlags({ ...flags, match: "all" }).match).toEqual({ kind: "all" });
    expect(specFromFlags({ ...flags, match: "single:a@example.com" }).match).toEqual({ kind: "single", value: "a@example.com" });
    expect(specFromFlags({ ...flags, match: "pattern:^Sales-.*@example\\.com$" }).match).toEqual({ kind: "pattern", value: "^Sales-.*@example\\.com$" });
  });
  test.each([
    [{ match: undefined }, /--match is required/],
    [{ match: "team:a@example.com" }, /kind must be/],
    [{ match: "group:" }, /no value/],
    [{ match: "group:not-an-address" }, /not an email/],
    [{ match: "pattern:([" }, /not a valid regular expression/],
    [{ "change-envelope-recipient": "nope" }, /not an email/],
    [{ "change-envelope-recipient": undefined, "add-original-to-header": false }, /would do nothing/],
  ])("rejects %j", (patch, rx) => {
    expect(() => specFromFlags({ ...flags, ...patch })).toThrow(UsageError);
    expect(() => specFromFlags({ ...flags, ...patch })).toThrow(rx);
  });
});

describe("planForm", () => {
  test("group rule: select, pick, action, every checkbox set, envelope, scope", () => {
    const ops = planForm(specFromFlags(flags));
    expect(ops[0]).toEqual({ op: "select", option: "Group membership" });
    expect(ops[1]).toEqual({ op: "pick", link: "Select groups", picker: "Select Groups", search: "staff-mail", row: "staff-mail@example.com" });
    expect(ops[2]).toEqual({ op: "select", option: "Modify message" });
    const ticks = ops.filter((o) => o.op === "tick");
    expect(ticks.map((o) => (o.op === "tick" ? o.label : ""))).toEqual([...LABELS.modifyCheckboxes]);
    expect(ticks.filter((o) => o.op === "tick" && o.want).map((o) => (o.op === "tick" ? o.label : ""))).toEqual(["Add X-Gm-Original-To header", "Change envelope recipient"]);
    const i = ops.findIndex((o) => o.op === "tick" && o.label === "Change envelope recipient");
    expect(ops[i + 1]).toEqual({ op: "radio", label: "Replace recipient" });
    expect(ops[i + 2]).toEqual({ op: "fill", label: "Enter new email address", value: "inbox@example.com" });
    expect(ops.at(-1)).toEqual({ op: "radio", label: LABELS.scope["non-recognized"] });
  });
  test("single and pattern fill their field; all has no value step", () => {
    expect(planForm(specFromFlags({ ...flags, match: "single:a@example.com" }))[1]).toEqual({ op: "fill", label: "Email address:", value: "a@example.com" });
    expect(planForm(specFromFlags({ ...flags, match: "pattern:x.*" }))[1]).toEqual({ op: "fill", label: "Regexp Learn more", value: "x.*" });
    expect(planForm(specFromFlags({ ...flags, match: "all" }))[1]).toEqual({ op: "select", option: "Modify message" });
  });
  test("no envelope change → no Replace recipient step", () => {
    const ops = planForm(specFromFlags({ ...flags, "change-envelope-recipient": undefined }));
    expect(ops.some((o) => o.op === "radio" && o.label === "Replace recipient")).toBe(false);
  });
});

describe("observedFromForm + diffRule", () => {
  const spec: Spec = specFromFlags(flags);
  test("the live form shape reads back as the spec", () => {
    const o = observedFromForm(liveForm);
    expect(o).toEqual({
      matchKind: "group",
      matchValues: ["staff-mail@example.com"],
      action: "Modify message",
      checked: ["Add X-Gm-Original-To header", "Change envelope recipient"],
      replaceRecipient: true,
      envelopeRecipient: "inbox@example.com",
      scope: "non-recognized",
    });
    expect(diffRule(spec, o)).toEqual([]);
    expect(sameMatch(spec, o)).toBe(true);
  });
  test("reports each difference", () => {
    const o = observedFromForm({
      ...liveForm,
      checkboxes: liveForm.checkboxes.map((c) => (c.label === "Also reroute spam" ? { ...c, checked: true } : c)),
      radios: liveForm.radios.map((r) => (r.label.startsWith("Perform") ? { ...r, checked: !r.checked } : r)),
      textboxes: liveForm.textboxes.map((t) => (t.label === "Enter new email address" ? { ...t, value: "other@example.com" } : t)),
    });
    const fields = diffRule(spec, o).map((d) => d.field);
    expect(fields).toEqual(["checkboxes", "envelope.recipient", "scope"]);
  });
  test("a different group is a different rule", () => {
    const o = observedFromForm({ ...liveForm, text: liveForm.text.replace("staff-mail@example.com", "other@example.com") });
    expect(sameMatch(spec, o)).toBe(false);
  });
  test("two groups selected is not the one-group spec", () => {
    const o = observedFromForm({ ...liveForm, text: liveForm.text.replace("Delete\nSelect", "Delete\nOther(other@example.com)\nDelete\nSelect") });
    expect(o.matchValues).toEqual(["staff-mail@example.com", "other@example.com"]);
    expect(sameMatch(spec, o)).toBe(false);
  });
});

describe("parseTable + candidates", () => {
  // Live table text: the match column shows a fragment of the group's display name, never its address.
  const grid = {
    headers: ["Order", "Status", "Actions", "ID", "Match rules", "Consequences"],
    rows: [
      ["1", "Enabled", "Edit - Disable - Delete - Reorder", "a1b2c", "Group membership:\nrouting to inbox@", "Rewrite message"],
      ["2", "Enabled", "Edit - Disable - Delete - Reorder", "d3e4f", "Single recipient:\nx@example.com", "Rewrite message"],
      ["", "", "", "", "", ""],
    ],
  };
  test("keys cells by header and drops empty rows", () => {
    const rules = parseTable(grid);
    expect(rules).toHaveLength(2);
    expect(rules[0]!.cells.ID).toBe("a1b2c");
    expect(rules[1]!.index).toBe(1);
  });
  test("narrows by match kind only", () => {
    const rules = parseTable(grid);
    expect(candidates(rules, specFromFlags(flags)).map((r) => r.cells.ID)).toEqual(["a1b2c"]);
    expect(candidates(rules, specFromFlags({ ...flags, match: "single:y@example.com" })).map((r) => r.cells.ID)).toEqual(["d3e4f"]);
    expect(candidates(rules, specFromFlags({ ...flags, match: "all" }))).toEqual([]);
  });
});
