// page.ts — run one page-side step through `browser_run_code_unsafe`, with a shared library of primitives.
//
// Every step is a function `async (page, args, H) => result` written as SOURCE TEXT: it is executed inside
// the MCP server, not here. `H` is the primitive library below (PRELUDE). Arguments travel as a JSON literal,
// never by string concatenation, so no value can break out of the code.
//
// Selectors are by ACCESSIBLE ROLE and LABEL TEXT, never by CSS class: Google's class names are minified and
// change between builds; the words on screen change far less often.
import { copyFileSync, existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { Browser } from "./mcp.ts";

/**
 * Page-side primitive library. Lessons baked in (measured on the Google Admin console, 2026-10-19):
 *  - In a background tab Playwright's actionability wait hangs, so every click is `bringToFront()` +
 *    `click({ force: true })`. Synthetic `dispatchEvent` clicks are ignored (jsaction wants real input).
 *  - A Material checkbox has no accessible name: its words sit in a sibling node. Find the label text, climb
 *    to the nearest ancestor that holds a `role=checkbox`, and use that one.
 *  - A Material listbox lists its options inline; open it with a click, then click the option.
 *  - While a nested picker dialog is open the outer dialog is aria-hidden: role queries must target the
 *    picker, and the picker must be closed before the outer dialog is visible to them again.
 */
export const PRELUDE = String.raw`(page) => {
  const T = 6000;
  const sleep = (ms) => page.waitForTimeout(ms);
  const click = async (loc) => { await loc.click({ force: true, timeout: T }); };
  const one = async (loc, what) => {
    const n = await loc.count();
    if (n !== 1) throw new Error(what + ': expected exactly 1 match, found ' + n);
    return loc;
  };
  const esc = (s) => s.replace(/[.*+?^${"$"}{}()|[\]\\]/g, '\\$&');
  const H = {
    sleep, click,
    async front() { await page.bringToFront(); },
    async state() {
      const url = page.url();
      let text = '';
      try { text = (await page.locator('body').innerText({ timeout: 3000 })).slice(0, 4000); } catch {}
      return { url, title: await page.title().catch(() => ''), text };
    },
    dialog(nameRx) { return page.getByRole('dialog', { name: nameRx }); },
    async button(scope, name) { await click(await one(scope.getByRole('button', { name, exact: true }), 'button "' + name + '"')); },
    async selected(listbox) {
      const o = listbox.getByRole('option', { selected: true });
      return (await o.count()) ? (await o.first().innerText()).trim() : null;
    },
    /** Select an option in the listbox that offers it. */
    async select(scope, option) {
      const lb = scope.getByRole('listbox').filter({ has: page.getByRole('option', { name: option, exact: true }) }).first();
      if ((await lb.count()) === 0) throw new Error('no listbox offers "' + option + '"');
      if ((await H.selected(lb)) === option) return 'unchanged';
      await click(lb);
      await sleep(500);
      await click(page.getByRole('option', { name: option, exact: true }).last());
      await sleep(800);
      const now = await H.selected(lb);
      if (now !== option) throw new Error('listbox shows "' + now + '" after choosing "' + option + '"');
      return 'selected';
    },
    checkboxFor(scope, label) {
      return scope.getByText(label, { exact: true }).locator('xpath=ancestor::*[.//*[@role="checkbox"]][1]').getByRole('checkbox');
    },
    /** Set a checkbox found by its visible label text. */
    async tick(scope, label, want = true) {
      const cb = await one(H.checkboxFor(scope, label), 'checkbox "' + label + '"');
      const is = (await cb.getAttribute('aria-checked')) === 'true';
      if (is === want) return 'unchanged';
      await click(cb);
      await sleep(500);
      const now = (await cb.getAttribute('aria-checked')) === 'true';
      if (now !== want) throw new Error('checkbox "' + label + '" did not change');
      return want ? 'ticked' : 'cleared';
    },
    /** Fill a text field found by its accessible name. */
    async fill(scope, label, value) {
      const tb = await one(scope.getByRole('textbox', { name: label, exact: true }), 'textbox "' + label + '"');
      if ((await tb.inputValue()) === value) return 'unchanged';
      await click(tb);
      await tb.fill(value, { force: true, timeout: T });
      await sleep(300);
      const now = await tb.inputValue();
      if (now !== value) throw new Error('textbox "' + label + '" holds "' + now + '"');
      return 'filled';
    },
    async radio(scope, label) {
      const r = await one(scope.getByRole('radio', { name: label, exact: true }), 'radio "' + label + '"');
      if ((await r.getAttribute('aria-checked')) === 'true') return 'unchanged';
      await click(r);
      await sleep(400);
      if ((await r.getAttribute('aria-checked')) !== 'true') throw new Error('radio "' + label + '" did not take');
      return 'chosen';
    },
    /**
     * Pick a row in a searchable picker dialog. Measured: a click on the ROW selects it at once (it appears in
     * the outer dialog); the picker is multi-select, has no confirm button, and stays open until its own
     * "Close dialog" button is pressed.
     */
    async pick(scope, { link, picker, search, row }) {
      await click(await one(scope.getByText(link, { exact: true }), 'link "' + link + '"'));
      await sleep(1500);
      const d = page.getByRole('dialog').filter({ has: page.getByRole('heading', { name: picker }) }).last();
      if ((await d.count()) === 0) throw new Error('picker "' + picker + '" did not open');
      const box = d.getByRole('textbox').first();
      await click(box);
      await box.fill('', { force: true });
      await box.pressSequentially(search, { delay: 30 });
      await sleep(2500);
      // hasText matches textContent, where a <br> leaves no space ("Name (x)name@example.com"): bound the
      // address by any character that cannot be part of one.
      const rx = new RegExp('(^|[^A-Za-z0-9._%+-])' + esc(row) + '($|[^A-Za-z0-9._%+-])', 'i');
      const rows = d.getByRole('row').filter({ hasText: rx });
      const n = await rows.count();
      if (n !== 1) throw new Error('picker "' + picker + '": ' + n + ' rows match "' + row + '"');
      await click(rows.first());
      await sleep(1200);
      await click(d.getByRole('button', { name: 'Close dialog' }));
      await sleep(1000);
      return 'picked';
    },
    /** Everything a form shows: listbox choices, checkboxes, text fields, radios, and its text. */
    async readForm(scope) {
      const listboxes = [];
      const lbs = scope.getByRole('listbox');
      for (let i = 0; i < await lbs.count(); i++) listboxes.push(await H.selected(lbs.nth(i)));
      const raw = await scope.evaluate((root) => {
        const vis = (e) => !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length);
        const labelOf = (e) => {
          for (let p = e.parentElement; p && p !== root; p = p.parentElement) {
            const t = (p.innerText || '').trim();
            if (t) return t.split('\n')[0].trim();
          }
          return '';
        };
        return {
          checkboxes: [...root.querySelectorAll('[role=checkbox]')].map((e) => ({ label: labelOf(e), checked: e.getAttribute('aria-checked') === 'true' })),
          radios: [...root.querySelectorAll('[role=radio]')].map((e) => ({ label: e.getAttribute('aria-label') || labelOf(e), checked: e.getAttribute('aria-checked') === 'true' })),
          textboxes: [...root.querySelectorAll('input:not([type=hidden]), textarea')].map((e) => ({ label: e.getAttribute('aria-label') || '', value: e.value, visible: vis(e) })),
        };
      });
      return { listboxes, ...raw, text: (await scope.innerText()).slice(0, 6000) };
    },
    /** A data grid as {headers, rows}; header cells may be aria-hidden, so read innerText. */
    async readGrid(scope) {
      const grid = scope.getByRole('grid').filter({ has: page.getByRole('columnheader') }).first();
      if ((await grid.count()) === 0) return { headers: [], rows: [] };
      return grid.evaluate((g) => {
        const headers = [...g.querySelectorAll('[role=columnheader]')].map((c) => (c.innerText || '').trim());
        const rows = [...g.querySelectorAll('[role=row]')]
          .filter((r) => !r.querySelector('[role=columnheader]'))
          .map((r) => [...r.children].map((c) => (c.innerText || '').trim())); // cells may carry no role
        return { headers, rows };
      });
    },
  };
  return H;
}`;

export type StepFn = string; // source of `async (page, args, H) => any`

export interface StepOutcome<T = unknown> {
  ok: boolean;
  value?: T;
  error?: string;
}

/** Parse the text `browser_run_code_unsafe` returns: "### Result\n<json>\n### Ran ..." or "### Error\n...". */
export function parseRunCodeResult(text: string, isError = false): StepOutcome {
  const err = text.match(/### Error\s*\n([\s\S]*?)(?:\n### |$)/);
  if (err || isError) return { ok: false, error: (err?.[1] ?? text).trim().slice(0, 2000) };
  const m = text.match(/### Result\s*\n([\s\S]*?)(?:\n### |$)/);
  if (!m) return { ok: false, error: `unrecognised tool output: ${text.slice(0, 300)}` };
  let v: unknown = JSON.parse(m[1]!.trim());
  // The step returns JSON.stringify(result); the server JSON-encodes that string once more.
  if (typeof v === "string") {
    try {
      v = JSON.parse(v);
    } catch {
      /* a plain string result */
    }
  }
  return { ok: true, value: v };
}

export function buildStepCode(fn: StepFn, args: unknown): string {
  return `async (page) => {
  const ARGS = ${JSON.stringify(args ?? null)};
  const H = (${PRELUDE})(page);
  await page.bringToFront();
  const r = await (${fn})(page, ARGS, H);
  return JSON.stringify(r === undefined ? null : r);
}`;
}

export class Driver {
  private n = 0;
  constructor(
    readonly browser: Browser,
    private shotsDir?: string,
    private log: (s: string) => void = (s) => console.error(s),
  ) {
    if (shotsDir) mkdirSync(shotsDir, { recursive: true });
  }

  async step<T = unknown>(name: string, fn: StepFn, args?: unknown, opts: { shoot?: boolean; timeoutMs?: number; quiet?: boolean } = {}): Promise<T> {
    if (!opts.quiet) this.log(`· ${name}`);
    const r = await this.browser.call("browser_run_code_unsafe", { code: buildStepCode(fn, args) }, opts.timeoutMs ?? 120_000);
    const out = parseRunCodeResult(r.text, r.isError);
    if (opts.shoot !== false) await this.shoot(name, !out.ok);
    if (!out.ok) throw new StepError(name, out.error ?? "unknown error");
    return out.value as T;
  }

  async navigate(url: string): Promise<void> {
    this.log(`· navigate ${url}`);
    const r = await this.browser.call("browser_navigate", { url }, 90_000);
    if (r.isError) throw new StepError("navigate", r.text.slice(0, 500));
  }

  /** Save a PNG of the viewport when --screenshots is set, and always on failure (to ~/.local/state/gws-admin-console/failures when no dir is given: never inside a repository). */
  async shoot(name: string, failed = false): Promise<string | null> {
    if (!this.shotsDir && !failed) return null;
    this.n += 1;
    const file = `${String(this.n).padStart(2, "0")}-${name.replace(/[^a-z0-9]+/gi, "-").toLowerCase()}${failed ? "-FAILED" : ""}.png`;
    const tmp = join(this.browser.workDir, ".playwright-mcp", file);
    try {
      const r = await this.browser.call("browser_take_screenshot", { type: "png", filename: tmp, scale: "css" }, 30_000);
      if (r.isError || !existsSync(tmp)) return null;
      const dir = this.shotsDir ?? join(homedir(), ".local", "state", "gws-admin-console", "failures");
      mkdirSync(dir, { recursive: true });
      const dest = join(dir, file);
      copyFileSync(tmp, dest);
      this.log(`  screenshot ${dest}`);
      return dest;
    } catch {
      return null;
    }
  }
}

export class StepError extends Error {
  constructor(
    readonly step: string,
    detail: string,
  ) {
    super(`step "${step}" failed: ${detail}`);
  }
}
