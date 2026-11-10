// passwordless — Admin console › Security › Authentication › Passwordless.
//
// "Allow users to skip passwords at sign-in by using passkeys" is off as Google ships it and is console-only: the
// Cloud Identity Policy API exposes only its sibling settings/security.passkeys_restriction (measured 2026-11-10 on
// a tenant's full policies.list), and Google's supported-settings page lists no passwordless setting type. Users
// then see "Skip password when possible isn't allowed for this account".
//
//   • inspect: read-only; report the page's checkboxes, buttons and text, so a recipe step can be written from what
//     is really on screen (Lessons: never trust the accessibility tree alone, take screenshots).
//   • ensure --allow-skip on|off: set the checkbox for the top organizational unit, Save, reload, read back.
import type { FlagSpec, Flags } from "../../lib/args.ts";
import { UsageError } from "../../lib/args.ts";
import type { Driver } from "../../lib/page.ts";

// The numeric path segment is Google's id for the Passwordless settings page, not a tenant: it is printed in the public
// help article "Allow users to skip passwords at sign-in" and is the same for every Workspace tenant (a tenant's own
// customer id has the form C0…). ac/security/passwordless is a 404.
export const URL =
  "https://admin.google.com/ac/managedsettings/352555445522/passwordless";
/** The checkbox's aria-label on the live page (Google's help page words it differently; measured 2026-11-10). */
export const LABEL =
  "Allow users to skip their password and authenticate with a passkey";
/** The setting row's edit button, which turns the read-only summary (ON/OFF) into the form. */
export const EDIT = "Edit Skip passwords";

export const FLAGS: FlagSpec[] = [
  {
    name: "allow-skip",
    type: "string",
    choices: ["on", "off"],
    help: `ensure: the wanted state of "${LABEL}"`,
  },
  {
    name: "dry-run",
    type: "bool",
    help: "ensure: tick or clear the box and read it back, then leave without saving",
  },
  {
    name: "verify",
    type: "bool",
    help: "ensure: read back only: exit 0 when the box is already in the wanted state",
  },
];

/** Pure: flags → wanted state for ensure. */
export function wantFromFlags(f: Flags): boolean {
  const v = f["allow-skip"];
  if (v !== "on" && v !== "off")
    throw new UsageError("--allow-skip on|off is required for ensure");
  return v === "on";
}

/** Read-only page survey: every checkbox (with its nearby text), button and the main text. */
const INSPECT = `async (page, args, H) => {
  const main = page.getByRole('main');
  const form = await H.readForm(main);
  const buttons = await main.getByRole('button').evaluateAll((els) => els.map((e) => (e.getAttribute('aria-label') || e.textContent || '').trim()).filter(Boolean).slice(0, 60));
  const text = ((await main.textContent()) || '').replace(/\\s+/g, ' ').slice(0, 3000);
  return { url: page.url(), form, buttons, text };
}`;

/** Summary view (no edit open): the label is followed by ON or OFF; the page shows the top unit by default. */
const READ_SUMMARY = `async (page, args, H) => {
  const text = ((await page.getByRole('main').textContent()) || '').replace(/\\s+/g, ' ');
  const at = text.indexOf(args.label);
  if (at < 0) throw new Error('the label "' + args.label + '" is not on the page');
  const m = text.slice(at + args.label.length, at + args.label.length + 12).match(/^\\s*(ON|OFF)/);
  if (!m) throw new Error('no ON/OFF after the label: ' + JSON.stringify(text.slice(at, at + 120)));
  const unit = (text.match(/Showing settings for users in (.+?)(?:Passwordless|$)/) || [])[1]?.trim() || null;
  return { checked: m[1] === 'ON', unit };
}`;

// The edit panel's SAVE and CANCEL sit outside role=main (measured 2026-11-10), so they are found page-wide.
/** Open the edit form and set the native checkbox (role checkbox, named by aria-label) to args.want. */
const SET_BOX = `async (page, args, H) => {
  const main = page.getByRole('main');
  await H.click(main.getByRole('button', { name: args.edit, exact: true }).first());
  await H.sleep(1500);
  const cb = main.getByRole('checkbox', { name: args.label, exact: true });
  if ((await cb.count()) !== 1) throw new Error('found ' + (await cb.count()) + ' checkboxes named "' + args.label + '"');
  if ((await cb.isChecked()) !== args.want) { await H.click(cb); await H.sleep(800); }
  return { checked: await cb.isChecked() };
}`;

const SAVE = `async (page, args, H) => {
  // The SAVE control in the edit panel's footer is not exposed as role=button (measured 2026-11-10): fall back to its
  // visible text, last match (the footer is drawn after the form).
  let save = page.getByRole('button', { name: /^save$/i });
  if (!(await save.count())) save = page.getByText(/^\\s*save\\s*$/i);
  let target = null;
  for (let i = (await save.count()) - 1; i >= 0; i--) if (await save.nth(i).isVisible()) { target = save.nth(i); break; }
  if (!target) throw new Error('no visible Save control after editing');
  await H.click(target); await H.sleep(3500);
  return { saved: true };
}`;

const LEAVE = `async (page, args, H) => {
  let b = page.getByRole('button', { name: /^cancel$/i });
  if (!(await b.count())) b = page.getByText(/^\\s*cancel\\s*$/i);
  for (let i = (await b.count()) - 1; i >= 0; i--) if (await b.nth(i).isVisible()) { await H.click(b.nth(i)); await H.sleep(1000); break; }
  return 'left';
}`;

export async function run(
  verb: string,
  f: Flags,
  d: Driver,
  gate: () => Promise<void>,
): Promise<{ code: number; result: Record<string, unknown> }> {
  const base = { recipe: "passwordless", account: f.account };
  const open = async () => {
    await d.navigate(URL);
    await gate();
    await Bun.sleep(2500);
  };
  if (verb === "inspect") {
    await open();
    return {
      code: 0,
      result: {
        ...base,
        ok: true,
        action: "inspected",
        page: await d.step("inspect page", INSPECT),
      },
    };
  }
  if (verb !== "ensure")
    throw new UsageError(`passwordless verbs: inspect, ensure (got "${verb}")`);
  const want = wantFromFlags(f);
  await open();
  const before = await d.step<{ checked: boolean; unit: string | null }>(
    "read summary",
    READ_SUMMARY,
    { label: LABEL },
  );
  const at = { unit: before.unit };
  if (before.checked === want)
    return {
      code: 0,
      result: {
        ...base,
        ...at,
        ok: true,
        action: f.verify ? "verified" : "unchanged",
        want,
        observed: before.checked,
      },
    };
  if (f.verify)
    return {
      code: 1,
      result: {
        ...base,
        ...at,
        ok: false,
        action: "differs",
        want,
        observed: before.checked,
      },
    };
  const filled = await d.step<{ checked: boolean }>(
    "edit and set checkbox",
    SET_BOX,
    { label: LABEL, edit: EDIT, want },
  );
  if (filled.checked !== want)
    throw new Error(`the checkbox did not change (still ${filled.checked})`);
  if (f["dry-run"]) {
    await d.step("leave without saving", LEAVE, {});
    return {
      code: 0,
      result: {
        ...base,
        ...at,
        ok: true,
        action: "would-change",
        want,
        observed: before.checked,
      },
    };
  }
  await d.step("save", SAVE);
  // Read back from a fresh page load, never from the view that just saved.
  await Bun.sleep(3000);
  await open();
  const after = await d.step<{ checked: boolean; unit: string | null }>(
    "read summary after reload",
    READ_SUMMARY,
    { label: LABEL },
  );
  const ok = after.checked === want;
  return {
    code: ok ? 0 : 1,
    result: {
      ...base,
      ...at,
      ok,
      action: "changed",
      verified: ok,
      want,
      before: before.checked,
      after: after.checked,
    },
  };
}
