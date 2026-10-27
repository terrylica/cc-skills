#!/usr/bin/env bun
// chrome-tabs.ts — list and close tabs of the RUNNING everyday Google Chrome, across every window and
// every profile, through Chrome's own AppleScript dictionary (driven as JXA by osascript).
//
//   bun chrome-tabs.ts list [--json] [--url-match <regex>]
//   bun chrome-tabs.ts close --id <tabId> [--id <tabId> ...] [--url-match <regex>] [--dry-run]
//   bun chrome-tabs.ts close --url-match <regex> [--max <n>] [--dry-run]
//   (or: chrome-profile.sh tabs …, which execs this file)
//
// WHY THIS ROUTE. The Playwright Extension server only sees the tabs of its own session, and
// chrome-devtools-mcp --autoConnect costs an "Allow remote debugging?" click per connection. Chrome's
// AppleScript support sees every tab in every profile and closes one by its permanent id, with no
// extension, no debug port and no dialog (measured 2026-10-27: 19 tabs left behind by automation runs
// closed by exact id, the operator's own 4 untouched). It needs the macOS Automation grant for the host
// app (Orca, Terminal, iTerm…) to control Google Chrome, and a call made from inside the logged-in desktop
// session. OVER SSH IT IS REFUSED before any Apple event is sent: measured 2026-10-27 on two Macs, `running()`
// answered but `windows()` hung, and macOS put an "sshd-keygen-wrapper wants to control Google Chrome" prompt
// on the screen of whoever sat at that Mac. CHROME_TABS_ALLOW_SSH=1 overrides, for a Mac you are sitting at.
//
// SAFETY RULES (each one is a measured failure):
//   - Close only by exact tab id, or by a URL regex whose match count is at most --max (default 1).
//     Window position is never a selector: AppleScript does not say which profile a window belongs to,
//     and indices shift as tabs close.
//   - Ids are compared as STRINGS. JXA returns numbers and argv holds strings; a strict compare of the two
//     silently matched nothing (2026-10-27).
//   - Refuse to close every tab of a window unless --allow-window-close: closing a profile's last tab
//     closes its window.
//   - Never launch Chrome. `Application(...).running()` is checked first, because touching the app object
//     of a stopped Chrome would start it.
//
// Exit codes: 0 ok · 2 usage or refused · 3 Chrome not running · 4 not in the desktop session (ssh, -600, or no
//             answer within 15 s) · 5 -1743 (Automation permission missing) · 1 anything else.
import { spawnSync } from "node:child_process";

export type Tab = { windowId: string; tabId: string; url: string; title: string };

export class TabsError extends Error {
  constructor(message: string, readonly exitCode: number) { super(message); }
}

// One JXA program, two verbs. It returns JSON so nothing is parsed out of prose.
const JXA = `
function run(argv) {
  const c = Application("Google Chrome");
  if (!c.running()) return JSON.stringify({ notRunning: true });
  const verb = argv[0];
  const tabs = [];
  c.windows().forEach(w => w.tabs().forEach(t => tabs.push({
    windowId: String(w.id()), tabId: String(t.id()), url: String(t.url()), title: String(t.title()) })));
  if (verb === "list") return JSON.stringify({ tabs });
  if (verb === "close") {
    const want = JSON.parse(argv[1]).map(String);
    const closed = [];
    // Look each id up in the window that holds it, then close it BY ID: indices shift as tabs close.
    c.windows().forEach(w => {
      const here = w.tabs.id().map(String);
      want.filter(id => here.includes(id)).forEach(id => {
        const t = w.tabs.byId(Number(id)); const u = String(t.url()); t.close(); closed.push({ tabId: id, url: u });
      });
    });
    return JSON.stringify({ closed });
  }
  return JSON.stringify({ error: "unknown verb " + verb });
}`;

export type Runner = (args: string[]) => { status: number | null; stdout: string; stderr: string };

export const OVER_SSH = "refusing over ssh: an Apple event from an ssh session hangs and makes macOS show an Automation prompt on that Mac's screen. Run it from a terminal on the Mac's desktop (Orca, Terminal), or set CHROME_TABS_ALLOW_SSH=1 if you are sitting at that Mac.";

export function overSsh(env: Record<string, string | undefined> = process.env): boolean {
  return !!(env.SSH_CONNECTION || env.SSH_CLIENT || env.SSH_TTY) && env.CHROME_TABS_ALLOW_SSH !== "1";
}

const osascript: Runner = (args) => {
  if (overSsh()) throw new TabsError(OVER_SSH, 4);
  const r = spawnSync("osascript", ["-l", "JavaScript", "-e", JXA, ...args], { encoding: "utf8", timeout: 15_000 });
  // A hung Apple event is killed by the timeout and leaves stderr empty; say so instead of "osascript failed: ".
  if (r.error && (r.error as NodeJS.ErrnoException).code === "ETIMEDOUT") return { status: 124, stdout: "", stderr: "TIMEOUT" };
  return { status: r.status, stdout: r.stdout ?? "", stderr: r.stderr ?? String(r.error ?? "") };
};

export function classify(stderr: string): TabsError {
  if (stderr === "TIMEOUT") {
    return new TabsError("osascript did not answer within 15 s: this is not the Mac's desktop session, or macOS is showing an Automation prompt that someone must answer (System Settings → Privacy & Security → Automation).", 4);
  }
  if (/-600\b/.test(stderr)) {
    return new TabsError("osascript -600: not running inside the logged-in desktop session (ssh, launchd or a tmux server started from ssh). Run it from a terminal on the Mac's desktop, e.g. an Orca or Terminal tab.", 4);
  }
  if (/-1743\b/.test(stderr)) {
    return new TabsError("osascript -1743: this app may not control Google Chrome. Allow it in System Settings → Privacy & Security → Automation, then retry.", 5);
  }
  return new TabsError(`osascript failed: ${stderr.trim().slice(0, 300)}`, 1);
}

function call(run: Runner, args: string[]): any {
  const r = run(args);
  if (r.status !== 0) throw classify(r.stderr);
  const out = JSON.parse(r.stdout.trim() || "{}");
  if (out.notRunning) throw new TabsError("Google Chrome is not running (nothing was started).", 3);
  if (out.error) throw new TabsError(out.error, 1);
  return out;
}

export function listTabs(run: Runner = osascript): Tab[] {
  return call(run, ["list"]).tabs as Tab[];
}

export type ClosePlan = { close: Tab[]; refused?: string };

// Pure: decides what to close from a tab list and the selectors. Tested without Chrome.
export function planClose(tabs: Tab[], o: { ids: string[]; urlMatch?: RegExp; max: number; allowWindowClose: boolean }): ClosePlan {
  if (o.ids.length === 0 && !o.urlMatch) return { close: [], refused: "refusing: give --id <tabId> (exact) or --url-match <regex>" };
  const ids = new Set(o.ids.map(String));
  const pick = tabs.filter((t) => (ids.size === 0 || ids.has(String(t.tabId))) && (!o.urlMatch || o.urlMatch.test(t.url)));
  const missing = [...ids].filter((id) => !tabs.some((t) => t.tabId === id));
  if (missing.length) return { close: [], refused: `refusing: no open tab has id ${missing.join(", ")} (list again; ids are per Chrome run)` };
  if (ids.size === 0 && pick.length > o.max) return { close: [], refused: `refusing: --url-match matches ${pick.length} tabs, more than --max ${o.max}; pass exact --id values or raise --max` };
  if (!o.allowWindowClose) {
    for (const w of new Set(pick.map((t) => t.windowId))) {
      const inWin = tabs.filter((t) => t.windowId === w).length;
      if (pick.filter((t) => t.windowId === w).length === inWin) return { close: [], refused: `refusing: that would close every tab of window ${w}, which closes the window; pass --allow-window-close` };
    }
  }
  return { close: pick };
}

// The host of an http(s) URL, lower-cased; "" for anything else (chrome://, about:blank).
export function hostOf(url: string): string {
  return (url.match(/^https?:\/\/([^/?#:]+)/i)?.[1] ?? "").toLowerCase();
}

// Every host named by an http(s) URL anywhere in a text (mcp-drive passes its whole steps.json, so URLs
// inside a run_code body count too). Ports are dropped, matching hostOf.
export function stepHosts(text: string): Set<string> {
  return new Set([...text.matchAll(/https?:\/\/([^/\s"'`\\?#:]+)/gi)].map((m) => m[1].toLowerCase()));
}

// The Playwright Extension's connect page. A run that reaches it without a valid token leaves it open,
// waiting for a click; mcp-drive's sweep closes one that appeared during its run.
export const CONNECT_PAGE = /^chrome-extension:\/\/mmlmfjhmonkocbjadbfplnigmagldckm\/connect\.html/i;

export function closeTabs(ids: string[], run: Runner = osascript): { tabId: string; url: string }[] {
  if (ids.length === 0) return [];
  return call(run, ["close", JSON.stringify(ids.map(String))]).closed;
}

function main(argv: string[]): number {
  const [verb, ...rest] = argv;
  const ids: string[] = [];
  let urlMatch: RegExp | undefined, json = false, dry = false, max = 1, allowWindowClose = false;
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    const next = () => { const v = rest[++i]; if (v === undefined) throw new TabsError(`${a} needs a value`, 2); return v; };
    if (a === "--id") ids.push(next());
    else if (a === "--url-match") urlMatch = new RegExp(next(), "i");
    else if (a === "--max") max = Number(next());
    else if (a === "--json") json = true;
    else if (a === "--dry-run") dry = true;
    else if (a === "--allow-window-close") allowWindowClose = true;
    else throw new TabsError(`unknown argument ${a}`, 2);
  }
  if (verb === "list") {
    const tabs = listTabs().filter((t) => !urlMatch || urlMatch.test(t.url));
    if (json) console.log(JSON.stringify(tabs, null, 1));
    else for (const t of tabs) console.log(`${t.windowId}\t${t.tabId}\t${t.url.slice(0, 110)}\t${t.title.slice(0, 50)}`);
    return 0;
  }
  if (verb === "close") {
    const plan = planClose(listTabs(), { ids, urlMatch, max, allowWindowClose });
    if (plan.refused) { console.error(plan.refused); return 2; }
    if (dry) { for (const t of plan.close) console.log(`would close ${t.tabId}\t${t.url.slice(0, 110)}`); return 0; }
    const closed = closeTabs(plan.close.map((t) => t.tabId));
    for (const t of closed) console.log(`closed ${t.tabId}\t${t.url.slice(0, 110)}`);
    if (closed.length !== plan.close.length) { console.error(`closed ${closed.length} of ${plan.close.length}`); return 1; }
    return 0;
  }
  console.error("usage: chrome-tabs.ts list [--json] [--url-match <re>] | close (--id <id>…|--url-match <re> [--max n]) [--dry-run] [--allow-window-close]");
  return 2;
}

if (import.meta.main) {
  try { process.exit(main(process.argv.slice(2))); }
  catch (e) {
    if (e instanceof TabsError) { console.error(`chrome-tabs: ${e.message}`); process.exit(e.exitCode); }
    console.error(`chrome-tabs: ${e}`); process.exit(1);
  }
}
