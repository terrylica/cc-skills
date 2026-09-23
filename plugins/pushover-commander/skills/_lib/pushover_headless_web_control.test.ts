/**
 * pushover_headless_web_control.test.ts — browser selection and import safety.
 *
 * Two defects, both measured 2026-09-22:
 *
 *   1. The dashboard was driven with `channel: "chrome"`, i.e. a SECOND instance of the
 *      operator's own Google Chrome.app on a throwaway profile. That second instance
 *      collided with the operator's Chrome in macOS LaunchServices: links stopped opening
 *      and every Chrome had to be force-quit. The default is now Playwright's
 *      "Google Chrome for Testing.app", a different bundle id, and falling back to system
 *      Chrome is never silent.
 *
 *   2. The module called main() at import, so `import { login } from "./pushover_headless_web_control.ts"`
 *      ran the CLI: it parsed the IMPORTER's argv, and process.exit()ed the importer.
 *      batch_create_pushover_apps.ts imports it and so ran a second CLI as a side effect.
 *
 * No test here launches a browser or reaches the network. Every child process runs with the
 * pushover.net credentials REMOVED from its environment, so even a regression that reached
 * the login step would stop at "login needs PO_EMAIL and PO_PW" before a browser exists.
 */
import { afterAll, describe, expect, spyOn, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import {
  BrowserChoice,
  type BrowserLauncher,
  BrowserUnavailableError,
  CFT_INSTALL_COMMAND,
  defaultPlaywrightCacheRoot,
  planBrowserLaunch,
  resolveChromeForTestingExecutable,
  withDashboard,
} from "./pushover_headless_web_control.ts";

const LIB_DIR = import.meta.dir;
const WEB_CONTROL = join(LIB_DIR, "pushover_headless_web_control.ts");

const createdRoots: string[] = [];
afterAll(() => {
  // Only the directories this file created — never a glob.
  for (const root of createdRoots) {
    rmSync(root, { recursive: true, force: true });
  }
});

/** A fresh, empty stand-in for ~/Library/Caches/ms-playwright. */
function tempCacheRoot(): string {
  const root = mkdtempSync(join(tmpdir(), "po-cft-cache-"));
  createdRoots.push(root);
  return root;
}

const CFT_TAIL = ["Google Chrome for Testing.app", "Contents", "MacOS", "Google Chrome for Testing"] as const;

/** Lay down a Chrome for Testing executable exactly where `playwright install chromium` puts one. Never executed. */
function installFakeCft(root: string, revisionDir: string, platformDir = "chrome-mac-arm64"): string {
  const executable = join(root, revisionDir, platformDir, ...CFT_TAIL);
  mkdirSync(join(executable, ".."), { recursive: true });
  writeFileSync(executable, "#!/bin/sh\nexit 0\n");
  return executable;
}

describe("resolveChromeForTestingExecutable — which Chrome for Testing", () => {
  test("picks the NUMERICALLY highest revision: chromium-1243 beats chromium-999", () => {
    const root = tempCacheRoot();
    installFakeCft(root, "chromium-999");
    const newest = installFakeCft(root, "chromium-1243");
    installFakeCft(root, "chromium-1234");
    // A string sort puts "chromium-999" last and would pick it; that is the bug this guards.
    expect(resolveChromeForTestingExecutable(root)).toBe(newest);
  });

  test("skips chromium_headless_shell-* even when it carries a higher revision and a CFT-shaped layout", () => {
    const root = tempCacheRoot();
    const real = installFakeCft(root, "chromium-1243");
    installFakeCft(root, "chromium_headless_shell-9999");
    installFakeCft(root, "chromium-tip-of-tree-9998");
    expect(resolveChromeForTestingExecutable(root)).toBe(real);
  });

  test("a headless shell alone is NOT a Chrome for Testing", () => {
    const root = tempCacheRoot();
    installFakeCft(root, "chromium_headless_shell-1243");
    expect(resolveChromeForTestingExecutable(root)).toBeNull();
  });

  test("a higher revision with no executable (half-finished download) does not hide a working lower one", () => {
    const root = tempCacheRoot();
    const working = installFakeCft(root, "chromium-1234");
    mkdirSync(join(root, "chromium-1243", "chrome-mac-arm64"), { recursive: true });
    expect(resolveChromeForTestingExecutable(root)).toBe(working);
  });

  test("recognises the Intel `chrome-mac` platform directory too", () => {
    const root = tempCacheRoot();
    const intel = installFakeCft(root, "chromium-1243", "chrome-mac");
    expect(resolveChromeForTestingExecutable(root)).toBe(intel);
  });

  test("an empty cache root resolves to null", () => {
    expect(resolveChromeForTestingExecutable(tempCacheRoot())).toBeNull();
  });

  test("a cache root that does not exist resolves to null rather than throwing", () => {
    expect(resolveChromeForTestingExecutable(join(tempCacheRoot(), "never-created"))).toBeNull();
  });
});

describe("defaultPlaywrightCacheRoot — look where `playwright install` wrote", () => {
  test("defaults to ~/Library/Caches/ms-playwright", () => {
    expect(defaultPlaywrightCacheRoot({})).toBe(join(homedir(), "Library", "Caches", "ms-playwright"));
  });

  test("honours PLAYWRIGHT_BROWSERS_PATH", () => {
    expect(defaultPlaywrightCacheRoot({ PLAYWRIGHT_BROWSERS_PATH: "/opt/pw-browsers" })).toBe("/opt/pw-browsers");
  });

  test('ignores PLAYWRIGHT_BROWSERS_PATH=0, which is Playwright\'s "inside node_modules" sentinel, not a path', () => {
    expect(defaultPlaywrightCacheRoot({ PLAYWRIGHT_BROWSERS_PATH: "0" })).toBe(
      join(homedir(), "Library", "Caches", "ms-playwright"),
    );
  });
});

/** A warn sink that records what it was given. */
function collect(): { sink: (text: string) => void; lines: string[] } {
  const lines: string[] = [];
  return { sink: (text) => void lines.push(text), lines };
}

describe("planBrowserLaunch — never the operator's Chrome by accident", () => {
  test("default + Chrome for Testing installed → launches it by executablePath, silently", () => {
    const root = tempCacheRoot();
    const exe = installFakeCft(root, "chromium-1243");
    const { sink, lines } = collect();
    const plan = planBrowserLaunch({ env: {}, cacheRoot: root, warn: sink });
    expect(plan.launched).toBe(BrowserChoice.ChromeForTesting);
    expect(plan.explicit).toBe(false);
    expect(plan.launchOptions).toEqual({ executablePath: exe });
    expect(lines).toEqual([]);
  });

  test("EXPLICIT --browser cft with none installed FAILS, naming the install command", () => {
    const run = () =>
      planBrowserLaunch({ flag: BrowserChoice.ChromeForTesting, env: {}, cacheRoot: tempCacheRoot(), warn: () => {} });
    expect(run).toThrow(BrowserUnavailableError);
    expect(run).toThrow("--browser cft");
    expect(run).toThrow("bunx playwright-core install chromium");
  });

  test("EXPLICIT PUSHOVER_WEB_BROWSER=cft with none installed FAILS too — env is as explicit as the flag", () => {
    const run = () =>
      planBrowserLaunch({ env: { PUSHOVER_WEB_BROWSER: "cft" }, cacheRoot: tempCacheRoot(), warn: () => {} });
    expect(run).toThrow(BrowserUnavailableError);
    expect(run).toThrow("PUSHOVER_WEB_BROWSER=cft");
  });

  test("DEFAULT with none installed falls back to system Chrome and WARNS — never silently", () => {
    const { sink, lines } = collect();
    const plan = planBrowserLaunch({ env: {}, cacheRoot: tempCacheRoot(), warn: sink });
    expect(plan.launched).toBe(BrowserChoice.SystemChrome);
    expect(plan.launchOptions).toEqual({ channel: "chrome" });
    expect(lines).toHaveLength(1);
    const warning = lines[0] ?? "";
    expect(warning).toContain("LaunchServices");
    expect(warning).toContain(CFT_INSTALL_COMMAND);
    expect(warning).toContain("bunx playwright-core install chromium");
    expect(plan.warning).toBe(warning);
  });

  test("the fallback warning goes to STDERR when no sink is injected", () => {
    const write = spyOn(process.stderr, "write").mockImplementation(() => true);
    try {
      planBrowserLaunch({ env: {}, cacheRoot: tempCacheRoot() });
      const written = write.mock.calls.map((call) => String(call[0])).join("");
      expect(written).toContain("LaunchServices");
      expect(written).toContain("bunx playwright-core install chromium");
    } finally {
      write.mockRestore();
    }
  });

  test("explicit chrome is honoured without a warning, even with Chrome for Testing installed", () => {
    const root = tempCacheRoot();
    installFakeCft(root, "chromium-1243");
    const { sink, lines } = collect();
    const plan = planBrowserLaunch({ flag: BrowserChoice.SystemChrome, env: {}, cacheRoot: root, warn: sink });
    expect(plan.launched).toBe(BrowserChoice.SystemChrome);
    expect(plan.explicit).toBe(true);
    expect(plan.launchOptions).toEqual({ channel: "chrome" });
    expect(lines).toEqual([]);
  });

  test("--browser beats PUSHOVER_WEB_BROWSER", () => {
    const root = tempCacheRoot();
    const exe = installFakeCft(root, "chromium-1243");
    const plan = planBrowserLaunch({
      flag: BrowserChoice.ChromeForTesting,
      env: { PUSHOVER_WEB_BROWSER: "chrome" },
      cacheRoot: root,
      warn: () => {},
    });
    expect(plan.launchOptions).toEqual({ executablePath: exe });
  });

  test("an unknown PUSHOVER_WEB_BROWSER value is a usage error, not a silent default", () => {
    expect(() =>
      planBrowserLaunch({ env: { PUSHOVER_WEB_BROWSER: "firefox" }, cacheRoot: tempCacheRoot(), warn: () => {} }),
    ).toThrow("PUSHOVER_WEB_BROWSER must be one of: cft, chrome");
  });

  test("an EMPTY PUSHOVER_WEB_BROWSER is unset, so the default (and its fallback warning) applies", () => {
    const { sink, lines } = collect();
    const plan = planBrowserLaunch({ env: { PUSHOVER_WEB_BROWSER: "" }, cacheRoot: tempCacheRoot(), warn: sink });
    expect(plan.explicit).toBe(false);
    expect(lines).toHaveLength(1);
  });
});

/** A stand-in for playwright's `chromium` that records launch options and never starts a process. */
function fakeLauncher(): { launcher: BrowserLauncher; launches: unknown[]; closed: () => number } {
  const launches: unknown[] = [];
  let closes = 0;
  const page = { on: () => page };
  const browser = {
    newContext: async () => ({ newPage: async () => page }),
    close: async () => {
      closes += 1;
    },
  };
  const launcher = {
    launch: async (options: unknown) => {
      launches.push(options);
      return browser;
    },
  } as unknown as BrowserLauncher;
  return { launcher, launches, closed: () => closes };
}

describe("withDashboard — launches exactly what the plan says", () => {
  test("a Chrome for Testing plan launches by executablePath — no `channel: \"chrome\"`", async () => {
    const root = tempCacheRoot();
    const exe = installFakeCft(root, "chromium-1243");
    const plan = planBrowserLaunch({ env: {}, cacheRoot: root, warn: () => {} });
    const { launcher, launches, closed } = fakeLauncher();
    const result = await withDashboard(false, async () => "done", plan, launcher);
    expect(result).toBe("done");
    expect(launches).toEqual([{ executablePath: exe, headless: true }]);
    expect(closed()).toBe(1);
  });

  test("an explicit system-Chrome plan launches channel chrome, headed when asked", async () => {
    const plan = planBrowserLaunch({ flag: BrowserChoice.SystemChrome, env: {}, cacheRoot: tempCacheRoot() });
    const { launcher, launches } = fakeLauncher();
    await withDashboard(true, async () => null, plan, launcher);
    expect(launches).toEqual([{ channel: "chrome", headless: false }]);
  });

  test("the browser is closed even when the callback throws", async () => {
    const plan = planBrowserLaunch({ flag: BrowserChoice.SystemChrome, env: {}, cacheRoot: tempCacheRoot() });
    const { launcher, closed } = fakeLauncher();
    const failing = withDashboard(
      false,
      async () => {
        throw new Error("boom");
      },
      plan,
      launcher,
    );
    await expect(failing).rejects.toThrow("boom");
    expect(closed()).toBe(1);
  });
});

// ---------- subprocess tests: the real CLI and the real import path ----------

/** The parent env minus anything that could let a child log in or pick a browser for us. */
function scrubbedEnv(extra: Record<string, string> = {}): Record<string, string> {
  const env: Record<string, string> = {};
  const withheld = new Set(["PO_EMAIL", "PO_PW", "PO_USER", "PUSHOVER_WEB_BROWSER", "PLAYWRIGHT_BROWSERS_PATH", "CREATE_PLAN"]);
  for (const [key, value] of Object.entries(process.env)) {
    if (value !== undefined && !withheld.has(key)) {
      env[key] = value;
    }
  }
  return { ...env, ...extra };
}

function runBun(args: string[], extraEnv: Record<string, string> = {}): { code: number; stdout: string; stderr: string } {
  const child = Bun.spawnSync([process.execPath, ...args], {
    cwd: LIB_DIR,
    env: scrubbedEnv(extraEnv),
    stdout: "pipe",
    stderr: "pipe",
  });
  return { code: child.exitCode ?? -1, stdout: child.stdout.toString(), stderr: child.stderr.toString() };
}

describe("importing a _lib module never runs its CLI", () => {
  const MARKER = "IMPORTER-STILL-ALIVE";
  // The pause gives an unguarded main() time to reach process.exit() before the marker prints.
  const importer = (file: string) =>
    `await import(${JSON.stringify(join(LIB_DIR, file))}); await Bun.sleep(300); console.log(${JSON.stringify(MARKER)});`;

  for (const file of [
    "pushover_headless_web_control.ts",
    "batch_create_pushover_apps.ts",
    "pushover_core.ts",
    "pushover_inbox.ts",
  ]) {
    test(`import ${file} → no CLI, no exit, no output`, () => {
      const { code, stdout, stderr } = runBun(["-e", importer(file)]);
      expect(stderr).toBe("");
      expect(stdout.trim()).toBe(MARKER);
      expect(code).toBe(0);
    });
  }
});

describe("the CLI still runs when executed directly", () => {
  test("--help documents --browser and exits 0", () => {
    const { code, stdout } = runBun([WEB_CONTROL, "--help"]);
    expect(code).toBe(0);
    expect(stdout).toContain("--browser cft|chrome");
    expect(stdout).toContain("PUSHOVER_WEB_BROWSER");
  });

  test("--browser with an unknown value exits 2 (usage) before anything else happens", () => {
    const { code, stderr } = runBun([WEB_CONTROL, "apps", "--browser", "safari"]);
    expect(code).toBe(2);
    expect(stderr).toContain("--browser must be one of: cft, chrome");
  });

  test("explicit --browser cft with none installed exits 1 with the install command — before credentials", () => {
    const { code, stderr } = runBun([WEB_CONTROL, "apps", "--browser", "cft"], {
      PLAYWRIGHT_BROWSERS_PATH: tempCacheRoot(),
    });
    expect(stderr).toContain("Chrome for Testing was requested (--browser cft)");
    expect(stderr).toContain("bunx playwright-core install chromium");
    expect(stderr).not.toContain("login needs");
    expect(code).toBe(1);
  });

  test("default with none installed prints the LaunchServices warning on stderr before reading credentials", () => {
    // No credentials in the child, so it stops at login with exit 2 — after the warning, before any browser.
    const { code, stdout, stderr } = runBun([WEB_CONTROL, "apps"], { PLAYWRIGHT_BROWSERS_PATH: tempCacheRoot() });
    expect(stderr).toContain("LaunchServices");
    expect(stderr).toContain("bunx playwright-core install chromium");
    expect(stderr).toContain("login needs PO_EMAIL and PO_PW");
    expect(stderr.indexOf("LaunchServices")).toBeLessThan(stderr.indexOf("login needs"));
    expect(stdout).toBe("");
    expect(code).toBe(2);
  });
});
