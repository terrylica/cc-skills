// form.ts — form operations as DATA. A recipe turns its spec into a list of FormOps (a pure, unit-tested
// function); `applyOps` replays them one step at a time against a dialog, so every op gets its own log line
// and, with --screenshots, its own PNG.
import type { Driver } from "./page.ts";

export type FormOp =
  | { op: "select"; option: string }
  | { op: "pick"; link: string; picker: string; search: string; row: string }
  | { op: "fill"; label: string; value: string }
  | { op: "tick"; label: string; want: boolean }
  | { op: "radio"; label: string };

export function describeOp(o: FormOp): string {
  switch (o.op) {
    case "select":
      return `select "${o.option}"`;
    case "pick":
      return `pick "${o.row}" in "${o.picker}"`;
    case "fill":
      return `fill "${o.label}" = "${o.value}"`;
    case "tick":
      return `${o.want ? "tick" : "clear"} "${o.label}"`;
    case "radio":
      return `choose "${o.label}"`;
  }
}

/** Page-side: run one FormOp inside the dialog whose accessible name matches args.dialog (a regex source). */
const APPLY_ONE = `async (page, args, H) => {
  const scope = H.dialog(new RegExp(args.dialog));
  if ((await scope.count()) !== 1) throw new Error('dialog /' + args.dialog + '/ is not open');
  const o = args.op;
  if (o.op === 'select') return H.select(scope, o.option);
  if (o.op === 'pick') {
    const already = await scope.getByText(o.row, { exact: false }).count();
    if (already) return 'unchanged';
    return H.pick(scope, o);
  }
  if (o.op === 'fill') return H.fill(scope, o.label, o.value);
  if (o.op === 'tick') return H.tick(scope, o.label, o.want);
  if (o.op === 'radio') return H.radio(scope, o.label);
  throw new Error('unknown op ' + o.op);
}`;

export async function applyOps(d: Driver, dialog: string, ops: FormOp[]): Promise<string[]> {
  const done: string[] = [];
  for (const op of ops) {
    const r = await d.step<string>(describeOp(op), APPLY_ONE, { dialog, op });
    done.push(`${describeOp(op)}: ${r}`);
  }
  return done;
}

/** Page-side: read the whole form state of a dialog. */
export const READ_FORM = `async (page, args, H) => {
  const scope = H.dialog(new RegExp(args.dialog));
  if ((await scope.count()) !== 1) throw new Error('dialog /' + args.dialog + '/ is not open');
  return H.readForm(scope);
}`;

export interface FormState {
  listboxes: (string | null)[];
  checkboxes: { label: string; checked: boolean }[];
  radios: { label: string; checked: boolean }[];
  textboxes: { label: string; value: string; visible: boolean }[];
  text: string;
}

/** Page-side: press a dialog button (Save / Cancel), then report whether the dialog closed and any alert text. */
export const PRESS_DIALOG_BUTTON = `async (page, args, H) => {
  const scope = H.dialog(new RegExp(args.dialog));
  if ((await scope.count()) === 0) return { closed: true, pressed: false };
  await H.button(scope, args.button);
  for (let i = 0; i < 20; i++) {
    await H.sleep(500);
    if ((await scope.count()) === 0) return { closed: true, pressed: true };
  }
  const alerts = await page.getByRole('alert').allInnerTexts().catch(() => []);
  return { closed: false, pressed: true, alerts, text: (await scope.innerText()).slice(0, 1500) };
}`;
