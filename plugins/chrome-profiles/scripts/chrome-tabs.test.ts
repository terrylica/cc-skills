// Tests for chrome-tabs.ts. The unit tests need no Chrome. The live test opens two tabs carrying a one-time
// marker in the running Chrome, closes exactly those by id and proves the count is restored; it runs only
// with CHROME_TABS_LIVE=1, from a terminal on the Mac's desktop.
import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { CONNECT_PAGE, type Runner, type Tab, classify, overSsh, closeTabs, hostOf, listTabs, planClose, stepHosts } from "./chrome-tabs.ts";

const T = (windowId: string, tabId: string, url: string): Tab => ({ windowId, tabId, url, title: "" });
const tabs = [T("1", "11", "https://a.example/x"), T("1", "12", "https://b.example/"), T("2", "21", "https://a.example/y")];
const base = { ids: [] as string[], max: 1, allowWindowClose: false };
const notRunning: Runner = () => ({ status: 0, stdout: '{"notRunning":true}', stderr: "" });
const mustNotRun: Runner = () => { throw new Error("must not run"); };

describe("planClose", () => {
  test("refuses with no selector", () => expect(planClose(tabs, base).refused).toMatch(/--id/));
  test("closes an exact id given as a string", () => expect(planClose(tabs, { ...base, ids: ["11"] }).close.map((t) => t.tabId)).toEqual(["11"]));
  test("refuses an id that is not open", () => expect(planClose(tabs, { ...base, ids: ["99"] }).refused).toMatch(/no open tab has id 99/));
  test("refuses a url match wider than --max", () => expect(planClose(tabs, { ...base, urlMatch: /a\.example/ }).refused).toMatch(/matches 2 tabs/));
  test("allows a url match within --max", () => expect(planClose(tabs, { ...base, urlMatch: /a\.example/, max: 2, allowWindowClose: true }).close).toHaveLength(2));
  test("refuses to empty a window", () => expect(planClose(tabs, { ...base, ids: ["21"] }).refused).toMatch(/closes the window/));
  test("--allow-window-close lifts that", () => expect(planClose(tabs, { ...base, ids: ["21"], allowWindowClose: true }).close).toHaveLength(1));
  test("id and url match must both hold", () => expect(planClose(tabs, { ...base, ids: ["12"], urlMatch: /a\.example/ }).close).toHaveLength(0));
});

describe("hosts (mcp-drive leftover sweep)", () => {
  test("hostOf drops path, port and case", () => expect(hostOf("https://Employers.Indeed.com:443/x?y")).toBe("employers.indeed.com"));
  test("CONNECT_PAGE matches only the Playwright Extension's connect page", () => {
    expect(CONNECT_PAGE.test("chrome-extension://mmlmfjhmonkocbjadbfplnigmagldckm/connect.html?mcpRelayUrl=x")).toBe(true);
    expect(CONNECT_PAGE.test("chrome-extension://mmlmfjhmonkocbjadbfplnigmagldckm/status.html")).toBe(false);
  });
  test("hostOf ignores non-http", () => expect(hostOf("chrome://newtab/")).toBe(""));
  test("stepHosts reads URLs inside a run_code body", () => {
    const steps = JSON.stringify([{ tool: "browser_run_code_unsafe", args: { code: "async (page) => { await page.goto('https://a.example/p?q=1'); }" } }, { tool: "browser_navigate", args: { url: "https://b.example:8443/" } }]);
    expect([...stepHosts(steps)].toSorted()).toEqual(["a.example", "b.example"]);
  });
});

describe("errors", () => {
  test("-600 names the desktop session", () => expect(classify("execution error: Error: (-600)").exitCode).toBe(4));
  test("a hung osascript is named, not reported as an empty failure", () => expect(classify("TIMEOUT").exitCode).toBe(4));
  test("ssh sessions are refused before any Apple event", () => {
    expect(overSsh({ SSH_CONNECTION: "1.2.3.4 5 6.7.8.9 22" })).toBe(true);
    expect(overSsh({ SSH_CONNECTION: "x", CHROME_TABS_ALLOW_SSH: "1" })).toBe(false);
    expect(overSsh({})).toBe(false);
  });
  test("-1743 names the Automation grant", () => expect(classify("Not authorized to send Apple events (-1743)").exitCode).toBe(5));
  test("Chrome not running is exit 3 and never launches it", () => {
    expect(() => listTabs(notRunning)).toThrow(/not running/);
  });
  test("close with no ids does not call osascript", () => {
    expect(closeTabs([], mustNotRun)).toEqual([]);
  });
});

test.skipIf(process.env.CHROME_TABS_LIVE !== "1")("live: open two marked tabs, close exactly them by id", async () => {
  const nonce = `cc-tabs-test-${Date.now()}`;
  const before = listTabs();
  spawnSync("open", ["-g", "-a", "Google Chrome", `https://example.com/?${nonce}-a`, `https://example.com/?${nonce}-b`]);
  let mine: Tab[] = [];
  for (let i = 0; i < 20 && mine.length < 2; i++) {
    await Bun.sleep(500);
    mine = listTabs().filter((t) => t.url.includes(nonce));
  }
  expect(mine).toHaveLength(2);
  const plan = planClose(listTabs(), { ids: mine.map((t) => t.tabId), max: 1, allowWindowClose: false });
  expect(plan.refused).toBeUndefined();
  expect(closeTabs(plan.close.map((t) => t.tabId))).toHaveLength(2);
  await Bun.sleep(500);
  const after = listTabs();
  expect(after.filter((t) => t.url.includes(nonce))).toHaveLength(0);
  expect(after.map((t) => t.tabId).toSorted()).toEqual(before.map((t) => t.tabId).toSorted());
}, 30_000);
