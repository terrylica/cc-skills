// gmail-routing — Admin console › Apps › Google Workspace › Gmail › Routing › "Routing" (the per-org-unit
// setting that can act on OUTBOUND mail, unlike Default routing, which sees only mail addressed to the domain).
//
// No API writes this setting: the Cloud Identity Policy API's supported settings list Gmail "Routing > Manage
// address lists" but not routing rules, and its create/patch/delete endpoints cover only rules and detectors.
// The recipe is split like gmail-default-routing.ts:
//   • PURE (unit-tested): spec from flags → FormOps → expected form; table rows → candidates; form → observed
//     rule; expected vs observed → diff.
//   • LIVE: navigate, gate re-authentication, check the org unit, read the "Routing" table, open a dialog (and
//     its "Show options"), replay the ops, read the form back, Save, reload, read back again.
//
// Identity: unlike Default routing, this dialog HAS a description field (its textbox is named "Routing"), and the
// table shows it in a "Description" column, so a rule is identified by its description.
//
// Measured on the live console 2026-11-26 (an "Add setting" dialog at the top org unit): the four message-type
// checkboxes; the action listbox (Modify / Reject / Quarantine message); four account-type checkboxes with
// "Active user accounts" ticked by default; the same "Modify message" checkboxes as Default routing plus "Require
// secure transport (TLS)"; and, behind the "Show options" LINK, "A. Address lists" and "B. Envelope filter"
// ("Only affect specific envelope senders" / "... recipients", each opening a listbox "Single email address |
// Pattern match | Group membership (only received mail)" and a textbox "Email address:").
import type { FlagSpec, Flags } from "../../lib/args.ts";
import { UsageError } from "../../lib/args.ts";
import { applyOps, type FormOp, type FormState, PRESS_DIALOG_BUTTON, READ_FORM } from "../../lib/form.ts";
import type { Driver } from "../../lib/page.ts";
import { LABELS as DEFAULT_ROUTING, type Difference, parseTable, type RunResult, type TableRule } from "./gmail-default-routing.ts";

export const URL = "https://admin.google.com/ac/apps/gmail/routing";
export const DIALOG = "^(Add|Edit) setting$";
/** The page holds several settings (Outbound gateway, Routing, Non-Gmail mailbox …); this one is the form named "Routing". */
export const SECTION = "Routing";

export const LABELS = {
  description: "Routing",
  messages: { inbound: "Inbound messages", outbound: "Outbound messages", "internal-outbound": "Internal outbound messages", "internal-inbound": "Internal inbound messages" },
  action: "Modify message",
  accountTypes: { users: "Active user accounts", groups: "Group accounts", inactive: "All inactive and unrecognized accounts", "archived-delegate": "Archived accounts with assigned delegate" },
  originalTo: DEFAULT_ROUTING.originalTo,
  changeEnvelope: DEFAULT_ROUTING.changeEnvelope,
  replaceRecipient: DEFAULT_ROUTING.replaceRecipient,
  envelopeField: DEFAULT_ROUTING.envelopeField,
  /** Every "Modify message" checkbox, in screen order. Those the spec does not ask for must stay clear. */
  modifyCheckboxes: [...DEFAULT_ROUTING.modifyCheckboxes, "Require secure transport (TLS)"],
  showOptions: "Show options",
  addressLists: "Use address lists to bypass or control application of this setting",
  envelopeSenders: "Only affect specific envelope senders",
  envelopeRecipients: "Only affect specific envelope recipients",
  envelopeKind: { single: "Single email address" },
  envelopeValue: "Email address:",
  orgUnitPrefix: "Showing settings for users in ",
} as const;

export type MessageKind = keyof typeof LABELS.messages;
export type AccountType = keyof typeof LABELS.accountTypes;

export interface Spec {
  description: string;
  orgUnit?: string;
  messages: MessageKind[];
  accountTypes: AccountType[];
  /** Only these envelope recipients are affected (Google: "Only affect specific envelope recipients"). */
  envelopeRecipient?: { kind: "single"; value: string };
  changeEnvelopeRecipient?: string;
  addOriginalToHeader: boolean;
}

export const FLAGS: FlagSpec[] = [
  { name: "description", type: "string", help: "The rule's description (Google stores it; it identifies the rule)" },
  { name: "org-unit", type: "string", help: "Refuse unless the page shows settings for this org unit (the page opens at the top unit); no navigation is done" },
  { name: "messages", type: "string", help: "Comma list of messages to affect: inbound, outbound, internal-outbound, internal-inbound" },
  { name: "account-types", type: "string", default: "users", help: "Comma list: users, groups, inactive, archived-delegate" },
  { name: "envelope-recipient", type: "string", help: "Only affect this envelope recipient: single:<email>" },
  { name: "change-envelope-recipient", type: "string", help: "Replace the envelope recipient with this address" },
  { name: "add-original-to-header", type: "bool", help: "Tick 'Add X-Gm-Original-To header'" },
  { name: "dry-run", type: "bool", help: "Navigate, fill and read the form back, then CANCEL: nothing is saved" },
  { name: "verify", type: "bool", help: "Read back only: exit 0 when a rule with this description exists and matches the spec, 1 otherwise" },
  { name: "update", type: "bool", help: "When a rule with this description exists but differs, change it to the spec (default: report and exit 3)" },
];

const EMAIL = /^[^\s@()]+@[^\s@()]+\.[^\s@()]+$/;

function list<K extends string>(raw: unknown, allowed: readonly K[], flag: string): K[] {
  const items = String(raw ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  for (const i of items) if (!allowed.includes(i as K)) throw new UsageError(`--${flag} "${i}": must be one of ${allowed.join(", ")}`);
  return [...new Set(items)] as K[];
}

/** Pure: flags → Spec. Throws UsageError with a clear reason. */
export function specFromFlags(f: Flags): Spec {
  const description = String(f.description ?? "").trim();
  if (!description) throw new UsageError("--description is required (it is how the rule is found again)");
  const messages = list(f.messages, Object.keys(LABELS.messages) as MessageKind[], "messages");
  if (!messages.length) throw new UsageError("--messages is required (inbound, outbound, internal-outbound, internal-inbound)");
  const accountTypes = list(f["account-types"] ?? "users", Object.keys(LABELS.accountTypes) as AccountType[], "account-types");
  if (!accountTypes.length) throw new UsageError("--account-types needs at least one type");
  let envelopeRecipient: Spec["envelopeRecipient"];
  if (f["envelope-recipient"] !== undefined) {
    const raw = String(f["envelope-recipient"]);
    const value = raw.startsWith("single:") ? raw.slice("single:".length) : "";
    if (!EMAIL.test(value)) throw new UsageError(`--envelope-recipient "${raw}": use single:<email> (pattern and group are not measured yet)`);
    envelopeRecipient = { kind: "single", value: value.toLowerCase() };
  }
  const env = f["change-envelope-recipient"] === undefined ? undefined : String(f["change-envelope-recipient"]);
  if (env !== undefined && !EMAIL.test(env)) throw new UsageError(`--change-envelope-recipient "${env}" is not an email address`);
  const addOriginalToHeader = f["add-original-to-header"] === true;
  if (!env && !addOriginalToHeader) throw new UsageError("the rule would do nothing: give --change-envelope-recipient and/or --add-original-to-header");
  const orgUnit = f["org-unit"] === undefined ? undefined : String(f["org-unit"]);
  return { description, orgUnit, messages, accountTypes, envelopeRecipient, changeEnvelopeRecipient: env?.toLowerCase(), addOriginalToHeader };
}

function wantedModify(spec: Spec): Set<string> {
  const s = new Set<string>();
  if (spec.addOriginalToHeader) s.add(LABELS.originalTo);
  if (spec.changeEnvelopeRecipient) s.add(LABELS.changeEnvelope);
  return s;
}

/** Pure: Spec → the ordered form operations that produce it in the dialog ("Show options" already open). */
export function planForm(spec: Spec): FormOp[] {
  const ops: FormOp[] = [{ op: "fill", label: LABELS.description, value: spec.description }];
  for (const [kind, label] of Object.entries(LABELS.messages)) ops.push({ op: "tick", label, want: spec.messages.includes(kind as MessageKind) });
  ops.push({ op: "select", option: LABELS.action });
  for (const [kind, label] of Object.entries(LABELS.accountTypes)) ops.push({ op: "tick", label, want: spec.accountTypes.includes(kind as AccountType) });
  const want = wantedModify(spec);
  for (const label of LABELS.modifyCheckboxes) {
    ops.push({ op: "tick", label, want: want.has(label) });
    if (label === LABELS.changeEnvelope && spec.changeEnvelopeRecipient) {
      ops.push({ op: "radio", label: LABELS.replaceRecipient });
      ops.push({ op: "fill", label: LABELS.envelopeField, value: spec.changeEnvelopeRecipient });
    }
  }
  ops.push({ op: "tick", label: LABELS.addressLists, want: false });
  ops.push({ op: "tick", label: LABELS.envelopeSenders, want: false });
  ops.push({ op: "tick", label: LABELS.envelopeRecipients, want: !!spec.envelopeRecipient });
  if (spec.envelopeRecipient) {
    ops.push({ op: "select", option: LABELS.envelopeKind[spec.envelopeRecipient.kind] });
    ops.push({ op: "fill", label: LABELS.envelopeValue, value: spec.envelopeRecipient.value });
  }
  return ops;
}

export interface Observed {
  description: string | null;
  messages: MessageKind[];
  action: string | null;
  accountTypes: AccountType[];
  modify: string[];
  replaceRecipient: boolean;
  envelopeRecipient: string | null;
  addressLists: boolean;
  envelopeSenders: boolean;
  envelopeFilter: { kind: string | null; value: string } | null;
}

/** Pure: a dialog's FormState → what rule it describes. */
export function observedFromForm(f: FormState): Observed {
  const checked = (label: string) => f.checkboxes.some((c) => c.label === label && c.checked);
  const tb = (label: string) => f.textboxes.find((t) => t.label === label)?.value ?? "";
  const keysTicked = <K extends string>(m: Record<K, string>) => (Object.entries(m) as [K, string][]).filter(([, l]) => checked(l)).map(([k]) => k);
  const modifyLabels = new Set<string>(LABELS.modifyCheckboxes);
  const modify = f.checkboxes.filter((c) => c.checked && modifyLabels.has(c.label)).map((c) => c.label);
  const changes = modify.includes(LABELS.changeEnvelope);
  const kinds = new Set(["Single email address", "Pattern match", "Group membership (only received mail)"]);
  const envelopeKind = f.listboxes.find((l) => l !== null && kinds.has(l)) ?? null;
  // The description textbox carries no aria-label (its name comes from a label element), so fall back to the
  // first visible text field that is none of the named ones.
  const named = new Set<string>([LABELS.envelopeField, "Enter new username", "Enter new domain", LABELS.envelopeValue]);
  const desc = f.textboxes.find((t) => t.label === LABELS.description) ?? f.textboxes.find((t) => t.visible && !named.has(t.label));
  return {
    description: desc ? desc.value : null,
    messages: keysTicked(LABELS.messages),
    action: f.listboxes[0] ?? null,
    accountTypes: keysTicked(LABELS.accountTypes),
    modify,
    replaceRecipient: changes && f.radios.some((r) => r.label === LABELS.replaceRecipient && r.checked),
    envelopeRecipient: changes ? tb(LABELS.envelopeField).toLowerCase() || null : null,
    addressLists: checked(LABELS.addressLists),
    envelopeSenders: checked(LABELS.envelopeSenders),
    // Two "Email address:" fields exist, senders' then recipients' (measured 2026-11-26: the senders' one stays
    // in the DOM, hidden, while its box is clear), so the recipients' value is the LAST one.
    envelopeFilter: checked(LABELS.envelopeRecipients) ? { kind: envelopeKind, value: (f.textboxes.findLast((t) => t.label === LABELS.envelopeValue)?.value ?? "").toLowerCase() } : null,
  };
}

/** Pure: every way the observed rule differs from the spec (empty = identical). */
export function diffRule(spec: Spec, o: Observed): Difference[] {
  const d: Difference[] = [];
  const push = (field: string, want: unknown, got: unknown) => {
    if (JSON.stringify(want) !== JSON.stringify(got)) d.push({ field, want, got });
  };
  push("description", spec.description, o.description);
  push("messages", spec.messages.toSorted(), o.messages.toSorted());
  push("action", LABELS.action, o.action);
  push("accountTypes", spec.accountTypes.toSorted(), o.accountTypes.toSorted());
  push("modify", [...wantedModify(spec)].toSorted(), o.modify.toSorted());
  if (spec.changeEnvelopeRecipient) {
    push("envelope.replaceRecipient", true, o.replaceRecipient);
    push("envelope.recipient", spec.changeEnvelopeRecipient, o.envelopeRecipient);
  }
  push("addressLists", false, o.addressLists);
  push("envelopeSenders", false, o.envelopeSenders);
  push("envelopeFilter", spec.envelopeRecipient ? { kind: LABELS.envelopeKind[spec.envelopeRecipient.kind], value: spec.envelopeRecipient.value } : null, o.envelopeFilter);
  return d;
}

/** Pure: the table rows whose Description is the spec's (identity is then confirmed in the Edit dialog by refusal()). */
export function candidates(rules: TableRule[], spec: Spec): TableRule[] {
  return rules.filter((r) => (r.cells.Description ?? "").trim() === spec.description);
}

/**
 * Pure: why a found rule cannot count as the spec's, or null. The dialog that opened must carry the spec's
 * description (else it is another rule and is never updated), and the table row must read Enabled: a disabled
 * rule's dialog still matches, but it routes nothing.
 */
export function refusal(spec: Spec, cells: Record<string, string>, o: Observed): { action: "row-mismatch" | "disabled"; reason: string } | null {
  if (o.description !== spec.description) return { action: "row-mismatch", reason: `the dialog opened for this row shows the description ${JSON.stringify(o.description)}, not the spec's; nothing was changed` };
  const status = (cells.Status ?? "").trim();
  if (status !== "Enabled") return { action: "disabled", reason: `the rule's status reads ${JSON.stringify(status)}, not "Enabled"; enable it in the console (this recipe does not toggle status)` };
  return null;
}

/** Pure: the org unit named on the page ("Showing settings for users in <unit>"), or null. */
export function orgUnitFromText(text: string): string | null {
  const line = text.split("\n").find((l) => l.trim().startsWith(LABELS.orgUnitPrefix));
  return line ? line.trim().slice(LABELS.orgUnitPrefix.length).trim() || null : null;
}

// ── live ─────────────────────────────────────────────────────────────────────────────────────────────────

const PAGE_TEXT = `async (page, args, H) => (await page.getByRole('main').innerText()).slice(0, 20000)`;

const READ_TABLE = `async (page, args, H) => H.readGrid(page.getByRole('form', { name: args.section, exact: true }))`;

/** Open "Show options" inside the open dialog when it is offered (an Edit dialog of a rule with options shows "Hide options"). */
const SHOW_OPTIONS = `async (page, args, H) => {
  const dlg = H.dialog(new RegExp(args.dialog));
  const show = dlg.getByRole('link', { name: args.link, exact: true });
  if (await show.count()) { await H.click(show.first()); await H.sleep(1200); return 'shown'; }
  return 'already shown';
}`;

const OPEN_ADD = `async (page, args, H) => {
  const form = page.getByRole('form', { name: args.section, exact: true });
  if ((await form.count()) !== 1) throw new Error('setting section "' + args.section + '" not found');
  for (const name of ['Add another rule', 'Configure', 'Add']) {
    const b = form.getByRole('button', { name, exact: true });
    if (await b.count()) { await H.click(b.first()); await H.sleep(1500); break; }
  }
  if ((await H.dialog(/^Add setting$/).count()) !== 1) throw new Error('the Add setting dialog did not open');
  return 'open';
}`;

/** Open the Edit dialog of the ONE row whose Description cell is exactly args.description (never by position:
 *  the table read and the accessibility tree count rows differently, so an index can point at a neighbour). */
const OPEN_EDIT = `async (page, args, H) => {
  const form = page.getByRole('form', { name: args.section, exact: true });
  const grid = form.getByRole('grid').filter({ has: page.getByRole('columnheader') }).first();
  const rows = grid.getByRole('row').filter({ has: page.getByRole('gridcell', { name: args.description, exact: true }) });
  const n = await rows.count();
  if (n !== 1) throw new Error(n + ' rows have the description ' + JSON.stringify(args.description));
  await H.click(rows.first().getByRole('link', { name: 'Edit', exact: true }));
  await H.sleep(1500);
  if ((await H.dialog(new RegExp(args.dialog)).count()) !== 1) throw new Error('no setting dialog opened for ' + JSON.stringify(args.description));
  return 'open';
}`;

async function openDialog(d: Driver, how: "add" | "edit", description = ""): Promise<void> {
  if (how === "add") await d.step("open Add setting", OPEN_ADD, { section: SECTION });
  else await d.step("open rule dialog", OPEN_EDIT, { section: SECTION, description, dialog: DIALOG });
  await d.step("show options", SHOW_OPTIONS, { dialog: DIALOG, link: LABELS.showOptions });
}

async function readTable(d: Driver): Promise<TableRule[]> {
  return parseTable(await d.step<{ headers: string[]; rows: string[][] }>("read rules table", READ_TABLE, { section: SECTION }));
}

export async function cancel(d: Driver): Promise<void> {
  await d.step("cancel dialog", PRESS_DIALOG_BUTTON, { dialog: DIALOG, button: "Cancel" }, { shoot: false }).catch(() => {});
}

async function readRule(d: Driver, row: TableRule): Promise<{ observed: Observed; form: FormState }> {
  await openDialog(d, "edit", row.cells.Description ?? "");
  try {
    const form = await d.step<FormState>("read rule dialog", READ_FORM, { dialog: DIALOG });
    return { observed: observedFromForm(form), form };
  } finally {
    await cancel(d);
  }
}

export async function run(verb: string, f: Flags, d: Driver, gate: () => Promise<void>): Promise<RunResult> {
  if (verb !== "ensure") throw new UsageError(`gmail-routing has one verb, ensure (got "${verb}")`);
  const spec = specFromFlags(f);
  const base: Record<string, unknown> = { recipe: "gmail-routing", account: f.account, spec };
  const open = async () => {
    await d.navigate(URL);
    await gate();
    await Bun.sleep(2500);
    const ou = orgUnitFromText(await d.step<string>("read page", PAGE_TEXT, {}, { shoot: false }));
    base.orgUnit = ou;
    if (spec.orgUnit && ou !== spec.orgUnit) throw new Error(`the page shows org unit "${ou}", not "${spec.orgUnit}"`);
  };

  await open();
  const rules = await readTable(d);
  const found = candidates(rules, spec);
  if (found.length > 1) return { code: 1, result: { ...base, ok: false, action: "ambiguous", reason: `${found.length} rules have the description ${JSON.stringify(spec.description)}; resolve by hand`, rules: found.map((x) => x.cells) } };

  if (found.length === 1) {
    const row = found[0]!;
    const { observed } = await readRule(d, row);
    const no = refusal(spec, row.cells, observed);
    if (no) return { code: 1, result: { ...base, ok: false, ...no, rule: row.cells, observed } };
    const diff = diffRule(spec, observed);
    if (diff.length === 0) return { code: 0, result: { ...base, ok: true, action: f.verify ? "verified" : "unchanged", rule: row.cells, observed, diff } };
    if (f.verify) return { code: 1, result: { ...base, ok: false, action: "differs", rule: row.cells, observed, diff } };
    if (!f.update) return { code: 3, result: { ...base, ok: false, action: "differs", hint: "re-run with --update to change it to the spec", rule: row.cells, observed, diff } };
    await openDialog(d, "edit", spec.description);
    return fillAndSave(d, f, spec, base, "updated", open);
  }

  if (f.verify) return { code: 1, result: { ...base, ok: false, action: "missing", table: rules.map((r) => r.cells) } };
  await openDialog(d, "add");
  return fillAndSave(d, f, spec, base, "created", open);
}

async function fillAndSave(d: Driver, f: Flags, spec: Spec, base: Record<string, unknown>, action: "created" | "updated", open: () => Promise<void>): Promise<RunResult> {
  let saved = false;
  try {
    const steps = await applyOps(d, DIALOG, planForm(spec));
    const form = await d.step<FormState>("read form before save", READ_FORM, { dialog: DIALOG });
    const before = observedFromForm(form);
    const preDiff = diffRule(spec, before);
    if (preDiff.length) {
      await d.shoot("fill-mismatch", true);
      await cancel(d);
      return { code: 1, result: { ...base, ok: false, action: "fill-mismatch", reason: "the filled form does not match the spec; nothing was saved", diff: preDiff, observed: before, form } };
    }
    if (f["dry-run"]) {
      await cancel(d);
      return { code: 0, result: { ...base, ok: true, action: action === "created" ? "would-create" : "would-update", steps, observed: before, form } };
    }
    const r = await d.step<{ closed: boolean; alerts?: string[]; text?: string }>("save", PRESS_DIALOG_BUTTON, { dialog: DIALOG, button: "Save" });
    if (!r.closed) throw new Error(`Save did not close the dialog: ${JSON.stringify(r).slice(0, 600)}`);
    saved = true;
    // Read back from a fresh page load, never from the view that just saved.
    await Bun.sleep(3000);
    await open();
    const found = candidates(await readTable(d), spec);
    if (found.length !== 1) return { code: 1, result: { ...base, ok: false, action, verified: false, reason: `after Save, ${found.length} rules have the description` } };
    const row = found[0]!;
    const { observed } = await readRule(d, row);
    const no = refusal(spec, row.cells, observed);
    if (no) return { code: 1, result: { ...base, ok: false, action, verified: false, ...no, rule: row.cells, observed } };
    const diff = diffRule(spec, observed);
    return { code: diff.length ? 1 : 0, result: { ...base, ok: diff.length === 0, action, verified: diff.length === 0, rule: row.cells, observed, diff, steps } };
  } catch (e) {
    if (!saved) {
      // Never leave a half-filled rule: cancel, then reload so the page holds no pending state.
      await d.shoot("failure", true);
      await cancel(d);
      await d.navigate(URL).catch(() => {});
    }
    throw e;
  }
}
