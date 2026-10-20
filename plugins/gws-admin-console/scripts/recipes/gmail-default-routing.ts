// gmail-default-routing — Admin console › Apps › Google Workspace › Gmail › Default routing.
//
// No API covers this setting (it is absent from the Cloud Identity Policy API's supported settings, and GAM
// cannot set it), so the console is the only way. The recipe is split in two:
//   • PURE (unit-tested): spec from flags → FormOps → expected form; table rows → candidates; form → observed
//     rule; expected vs observed → diff.
//   • LIVE: navigate, gate re-authentication, read the table, open a dialog, replay the ops, read the form back,
//     Save, reload, read back again.
//
// Identity: the Default routing dialog has NO description field (measured 2026-10-19: the dialog's only text
// fields are the match value and the action values). A rule is therefore identified by its MATCH (kind + value).
// --description is carried in the JSON result for the caller's own records; Google never stores it.
import type { FlagSpec, Flags } from "../lib/args.ts";
import { UsageError } from "../lib/args.ts";
import { applyOps, type FormOp, type FormState, PRESS_DIALOG_BUTTON, READ_FORM } from "../lib/form.ts";
import type { Driver } from "../lib/page.ts";

export const URL = "https://admin.google.com/ac/apps/gmail/defaultrouting";
/** Accessible names of the rule dialog when adding and when editing. */
export const DIALOG = "^(Add|Edit) setting$";

export const LABELS = {
  match: { single: "Single recipient", pattern: "Pattern match", group: "Group membership", all: "All recipients" },
  singleField: "Email address:",
  patternField: "Regexp Learn more",
  groupLink: "Select groups",
  groupPicker: "Select Groups",
  action: "Modify message",
  originalTo: "Add X-Gm-Original-To header",
  changeEnvelope: "Change envelope recipient",
  replaceRecipient: "Replace recipient",
  envelopeField: "Enter new email address",
  scope: {
    "non-recognized": "Perform this action only on non-recognized addresses",
    all: "Perform this action on non-recognized and recognized addresses",
  },
  /** Every "Modify message" checkbox, in screen order. Those the spec does not ask for must stay clear. */
  modifyCheckboxes: [
    "Add X-Gm-Original-To header",
    "Add X-Gm-Spam and X-Gm-Phishy headers",
    "Add custom headers",
    "Prepend custom subject",
    "Change route",
    "Change envelope recipient",
    "Bypass spam filter for this message",
    "Remove attachments from message",
    "Add more recipients",
  ],
} as const;

export type MatchKind = keyof typeof LABELS.match;
export type Match = { kind: "group" | "single" | "pattern"; value: string } | { kind: "all" };
export type Scope = keyof typeof LABELS.scope;

export interface Spec {
  description: string;
  match: Match;
  changeEnvelopeRecipient?: string;
  addOriginalToHeader: boolean;
  scope: Scope;
}

export const FLAGS: FlagSpec[] = [
  { name: "account", type: "string", required: true, help: "Admin account whose Chrome profile drives the console (chrome-profile.sh resolves it by email)" },
  { name: "description", type: "string", help: "Your label for the rule. Google's Default routing has no description field, so it only appears in this tool's JSON result", default: "" },
  { name: "match", type: "string", help: "Envelope recipients to match: group:<email> | single:<email> | pattern:<regex> | all" },
  { name: "change-envelope-recipient", type: "string", help: "Replace the envelope recipient with this address" },
  { name: "add-original-to-header", type: "bool", help: "Tick 'Add X-Gm-Original-To header'" },
  { name: "scope", type: "string", choices: ["non-recognized", "all"], default: "non-recognized", help: "non-recognized: only addresses with no mailbox; all: recognized ones too" },
  { name: "dry-run", type: "bool", help: "Navigate, fill and read the form back, then CANCEL: nothing is saved" },
  { name: "verify", type: "bool", help: "Read back only: exit 0 when a rule matching the spec exists, 1 otherwise" },
  { name: "update", type: "bool", help: "When a rule with the same match exists but differs, change it to the spec (default: report and exit 3)" },
];

const EMAIL = /^[^\s@()]+@[^\s@()]+\.[^\s@()]+$/;

/** Pure: flags → Spec. Throws UsageError with a clear reason. */
export function specFromFlags(f: Flags): Spec {
  const m = String(f.match ?? "");
  if (!m) throw new UsageError("--match is required (group:<email> | single:<email> | pattern:<regex> | all)");
  let match: Match;
  if (m === "all") match = { kind: "all" };
  else {
    const i = m.indexOf(":");
    const kind = i > 0 ? m.slice(0, i) : "";
    const value = i > 0 ? m.slice(i + 1) : "";
    if (kind !== "group" && kind !== "single" && kind !== "pattern") throw new UsageError(`--match "${m}": the kind must be group, single, pattern or all`);
    if (!value) throw new UsageError(`--match "${m}": no value after "${kind}:"`);
    if (kind !== "pattern" && !EMAIL.test(value)) throw new UsageError(`--match "${m}": "${value}" is not an email address`);
    if (kind === "pattern") {
      try {
        RegExp(value);
      } catch (e) {
        throw new UsageError(`--match "${m}": not a valid regular expression (${(e as Error).message})`);
      }
    }
    match = { kind, value: kind === "pattern" ? value : value.toLowerCase() };
  }
  const env = f["change-envelope-recipient"] === undefined ? undefined : String(f["change-envelope-recipient"]);
  if (env !== undefined && !EMAIL.test(env)) throw new UsageError(`--change-envelope-recipient "${env}" is not an email address`);
  const addOriginalToHeader = f["add-original-to-header"] === true;
  if (!env && !addOriginalToHeader) throw new UsageError("the rule would do nothing: give --change-envelope-recipient and/or --add-original-to-header");
  const scope = String(f.scope ?? "non-recognized") as Scope;
  if (!(scope in LABELS.scope)) throw new UsageError(`--scope must be non-recognized or all`);
  return { description: String(f.description ?? ""), match, changeEnvelopeRecipient: env?.toLowerCase(), addOriginalToHeader, scope };
}

/** Pure: Spec → the ordered form operations that produce it in the dialog. */
export function planForm(spec: Spec): FormOp[] {
  const ops: FormOp[] = [{ op: "select", option: LABELS.match[spec.match.kind] }];
  if (spec.match.kind === "group") ops.push({ op: "pick", link: LABELS.groupLink, picker: LABELS.groupPicker, search: spec.match.value.split("@")[0]!, row: spec.match.value });
  if (spec.match.kind === "single") ops.push({ op: "fill", label: LABELS.singleField, value: spec.match.value });
  if (spec.match.kind === "pattern") ops.push({ op: "fill", label: LABELS.patternField, value: spec.match.value });
  ops.push({ op: "select", option: LABELS.action });
  const want = wantedCheckboxes(spec);
  for (const label of LABELS.modifyCheckboxes) {
    ops.push({ op: "tick", label, want: want.has(label) });
    if (label === LABELS.changeEnvelope && spec.changeEnvelopeRecipient) {
      ops.push({ op: "radio", label: LABELS.replaceRecipient });
      ops.push({ op: "fill", label: LABELS.envelopeField, value: spec.changeEnvelopeRecipient });
    }
  }
  ops.push({ op: "radio", label: LABELS.scope[spec.scope] });
  return ops;
}

function wantedCheckboxes(spec: Spec): Set<string> {
  const s = new Set<string>();
  if (spec.addOriginalToHeader) s.add(LABELS.originalTo);
  if (spec.changeEnvelopeRecipient) s.add(LABELS.changeEnvelope);
  return s;
}

export interface Observed {
  matchKind: MatchKind | null;
  matchValues: string[];
  action: string | null;
  checked: string[];
  replaceRecipient: boolean;
  envelopeRecipient: string | null;
  scope: Scope | null;
}

/** Pure: a dialog's FormState → what rule it describes. */
export function observedFromForm(f: FormState): Observed {
  const kindLabel = f.listboxes[0] ?? null;
  const matchKind = (Object.entries(LABELS.match).find(([, l]) => l === kindLabel)?.[0] as MatchKind | undefined) ?? null;
  const tb = (label: string) => f.textboxes.find((t) => t.label === label)?.value ?? "";
  let matchValues: string[] = [];
  if (matchKind === "group") {
    // Each selected group shows as "Name(email)" followed by its "Delete" link.
    const sec = f.text.split(/\n\s*2\.\s/)[0] ?? f.text;
    matchValues = [...sec.matchAll(/\(([^\s()]+@[^\s()]+)\)\s*\n\s*Delete/g)].map((m) => m[1]!.toLowerCase());
  } else if (matchKind === "single") matchValues = tb(LABELS.singleField) ? [tb(LABELS.singleField).toLowerCase()] : [];
  else if (matchKind === "pattern") matchValues = tb(LABELS.patternField) ? [tb(LABELS.patternField)] : [];
  const checked = f.checkboxes.filter((c) => c.checked).map((c) => c.label);
  const radio = (label: string) => f.radios.some((r) => r.label === label && r.checked);
  const scope = (Object.entries(LABELS.scope).find(([, l]) => radio(l))?.[0] as Scope | undefined) ?? null;
  const changes = checked.includes(LABELS.changeEnvelope);
  return {
    matchKind,
    matchValues,
    action: f.listboxes[1] ?? null,
    checked,
    replaceRecipient: changes && radio(LABELS.replaceRecipient),
    envelopeRecipient: changes ? tb(LABELS.envelopeField).toLowerCase() || null : null,
    scope,
  };
}

export interface Difference {
  field: string;
  want: unknown;
  got: unknown;
}

/** Pure: every way the observed rule differs from the spec (empty = identical). */
export function diffRule(spec: Spec, o: Observed): Difference[] {
  const d: Difference[] = [];
  const push = (field: string, want: unknown, got: unknown) => {
    if (JSON.stringify(want) !== JSON.stringify(got)) d.push({ field, want, got });
  };
  push("match.kind", spec.match.kind, o.matchKind);
  push("match.values", spec.match.kind === "all" ? [] : [spec.match.value], o.matchValues.toSorted());
  push("action", LABELS.action, o.action);
  const want = [...wantedCheckboxes(spec)].toSorted();
  // Strict: ANY ticked box counts, including sub-options such as "Also reroute spam" under Change route.
  const got = o.checked.toSorted();
  push("checkboxes", want, got);
  if (spec.changeEnvelopeRecipient) {
    push("envelope.replaceRecipient", true, o.replaceRecipient);
    push("envelope.recipient", spec.changeEnvelopeRecipient, o.envelopeRecipient);
  }
  push("scope", spec.scope, o.scope);
  return d;
}

export interface TableRule {
  index: number;
  cells: Record<string, string>;
}

/** Pure: grid → rules keyed by column header. */
export function parseTable(grid: { headers: string[]; rows: string[][] }): TableRule[] {
  return grid.rows
    .filter((r) => r.some((c) => c.trim()))
    .map((r, index) => ({ index, cells: Object.fromEntries(grid.headers.map((h, i) => [h || `col${i}`, r[i] ?? ""])) }));
}

/**
 * Pure: the table rows that MIGHT be the spec's rule. The table is lossy (measured 2026-10-19: a group rule
 * reads "Group membership:" plus a fragment of the group's display name, never its address, and every Modify
 * action reads "Rewrite message"), so it can only narrow by match KIND; identity is settled by reading each
 * candidate's Edit dialog.
 */
export function candidates(rules: TableRule[], spec: Spec): TableRule[] {
  const kind = LABELS.match[spec.match.kind].toLowerCase();
  return rules.filter((r) => {
    const text = (r.cells["Match rules"] ?? Object.values(r.cells).join(" ")).toLowerCase().trim();
    return text.startsWith(kind);
  });
}

/** Pure: does an observed rule have the spec's match (kind and value)? */
export function sameMatch(spec: Spec, o: Observed): boolean {
  if (o.matchKind !== spec.match.kind) return false;
  if (spec.match.kind === "all") return true;
  return o.matchValues.length === 1 && o.matchValues[0] === (spec.match.kind === "pattern" ? spec.match.value : spec.match.value.toLowerCase());
}

// ── live ─────────────────────────────────────────────────────────────────────────────────────────────────

const READ_TABLE = `async (page, args, H) => H.readGrid(page.getByRole('main'))`;

const OPEN_ADD = `async (page, args, H) => {
  const main = page.getByRole('main');
  for (const name of ['Configure', 'Add another rule', 'Add setting', 'Add']) {
    const b = main.getByRole('button', { name, exact: true });
    if (await b.count()) { await H.click(b.first()); await H.sleep(1500); break; }
  }
  if ((await H.dialog(/^Add setting$/).count()) !== 1) throw new Error('the Add setting dialog did not open');
  return 'open';
}`;

/** Open the edit dialog of the table row at args.index: its Edit control, or else the row itself. */
const OPEN_EDIT = `async (page, args, H) => {
  const grid = page.getByRole('main').getByRole('grid').filter({ has: page.getByRole('columnheader') }).first();
  const rows = grid.getByRole('row').filter({ hasNot: page.getByRole('columnheader') });
  const row = rows.nth(args.index);
  const edit = row.getByRole('button', { name: /^edit/i }).or(row.getByRole('link', { name: /^edit/i }));
  if (await edit.count()) await H.click(edit.first()); else await H.click(row);
  await H.sleep(1500);
  if ((await H.dialog(new RegExp(args.dialog)).count()) !== 1) throw new Error('no setting dialog opened for row ' + args.index);
  return 'open';
}`;

export interface RunResult {
  code: number;
  result: Record<string, unknown>;
}

async function readTable(d: Driver): Promise<TableRule[]> {
  return parseTable(await d.step<{ headers: string[]; rows: string[][] }>("read rules table", READ_TABLE));
}

async function readRule(d: Driver, row: TableRule): Promise<Observed> {
  await d.step("open rule dialog", OPEN_EDIT, { index: row.index, dialog: DIALOG });
  try {
    return observedFromForm(await d.step<FormState>("read rule dialog", READ_FORM, { dialog: DIALOG }));
  } finally {
    await cancel(d);
  }
}

/** Open each candidate's dialog and keep those whose match is the spec's. */
async function findRule(d: Driver, rules: TableRule[], spec: Spec): Promise<{ row: TableRule; observed: Observed }[]> {
  const out: { row: TableRule; observed: Observed }[] = [];
  for (const row of candidates(rules, spec)) {
    const observed = await readRule(d, row);
    if (sameMatch(spec, observed)) out.push({ row, observed });
  }
  return out;
}

export async function cancel(d: Driver): Promise<void> {
  await d.step("cancel dialog", PRESS_DIALOG_BUTTON, { dialog: DIALOG, button: "Cancel" }, { shoot: false }).catch(() => {});
}

export async function run(verb: string, f: Flags, d: Driver, gate: () => Promise<void>): Promise<RunResult> {
  if (verb !== "ensure") throw new UsageError(`gmail-default-routing has one verb, ensure (got "${verb}")`);
  const spec = specFromFlags(f);
  const base = { recipe: "gmail-default-routing", account: f.account, spec };
  const open = async () => {
    await d.navigate(URL);
    await gate();
    await Bun.sleep(1500);
  };

  await open();
  const rules = await readTable(d);
  const found = await findRule(d, rules, spec);
  if (found.length > 1) return { code: 1, result: { ...base, ok: false, action: "ambiguous", reason: `${found.length} rules have the match ${JSON.stringify(spec.match)}; resolve by hand`, rules: found.map((x) => x.row.cells) } };

  if (found.length === 1) {
    const { row, observed } = found[0]!;
    const diff = diffRule(spec, observed);
    if (diff.length === 0) return { code: 0, result: { ...base, ok: true, action: f.verify ? "verified" : "unchanged", rule: row.cells, observed, diff } };
    if (f.verify) return { code: 1, result: { ...base, ok: false, action: "differs", rule: row.cells, observed, diff } };
    if (!f.update) return { code: 3, result: { ...base, ok: false, action: "differs", hint: "re-run with --update to change it to the spec", rule: row.cells, observed, diff } };
    await d.step("open rule dialog", OPEN_EDIT, { index: row.index, dialog: DIALOG });
    return fillAndSave(d, f, spec, base, "updated", open);
  }

  if (f.verify) return { code: 1, result: { ...base, ok: false, action: "missing", table: rules.map((r) => r.cells) } };
  await d.step("open Add setting", OPEN_ADD);
  return fillAndSave(d, f, spec, base, "created", open);
}

async function fillAndSave(d: Driver, f: Flags, spec: Spec, base: Record<string, unknown>, action: "created" | "updated", open: () => Promise<void>): Promise<RunResult> {
  let saved = false;
  try {
    const steps = await applyOps(d, DIALOG, planForm(spec));
    const before = observedFromForm(await d.step<FormState>("read form before save", READ_FORM, { dialog: DIALOG }));
    const preDiff = diffRule(spec, before);
    if (preDiff.length) throw new Error(`the filled form does not match the spec: ${JSON.stringify(preDiff)}`);
    if (f["dry-run"]) {
      await cancel(d);
      return { code: 0, result: { ...base, ok: true, action: action === "created" ? "would-create" : "would-update", steps, observed: before } };
    }
    const r = await d.step<{ closed: boolean; alerts?: string[]; text?: string }>("save", PRESS_DIALOG_BUTTON, { dialog: DIALOG, button: "Save" });
    if (!r.closed) throw new Error(`Save did not close the dialog: ${JSON.stringify(r).slice(0, 600)}`);
    saved = true;
    // Read back from a fresh page load, never from the view that just saved.
    await Bun.sleep(3000);
    await open();
    const found = await findRule(d, await readTable(d), spec);
    if (found.length !== 1) return { code: 1, result: { ...base, ok: false, action, verified: false, reason: `after Save, ${found.length} rules have the spec's match` } };
    const { row, observed } = found[0]!;
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
