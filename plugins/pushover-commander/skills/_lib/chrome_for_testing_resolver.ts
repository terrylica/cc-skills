/**
 * chrome_for_testing_resolver.ts — where is Playwright's "Google Chrome for Testing.app"?
 *
 * Pure filesystem logic with `node:` imports only, deliberately free of playwright-core.
 * Two callers need it and only one of them drives a browser:
 *
 *   - pushover_headless_web_control.ts launches the resolved executable (the cft default).
 *   - pushover_core.ts `doctor` reports whether it is installed. The doctor is what you run
 *     when something is broken, so it must not itself need Playwright to answer "is the
 *     browser on disk?" — and `po send` must not pay for loading Playwright either.
 *
 * Why Chrome for Testing rather than the operator's own Google Chrome. `channel: "chrome"`
 * starts a SECOND instance of /Applications/Google Chrome.app on a throwaway profile, and
 * both instances carry the same bundle id (com.google.Chrome). On 2026-09-22 such a second
 * instance collided with the operator's running Chrome in macOS LaunchServices: links
 * stopped opening anywhere and every Chrome had to be force-quit. Playwright's
 * "Google Chrome for Testing.app" is a different bundle (com.google.chrome.for.testing),
 * so LaunchServices never confuses the two.
 */

import { readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import process from "node:process";

export type EnvLike = Readonly<Record<string, string | undefined>>;

/** Playwright's own cache-location override, honoured so we look where `playwright install` wrote. */
export const PLAYWRIGHT_BROWSERS_PATH_ENV = "PLAYWRIGHT_BROWSERS_PATH";

/** `chromium-<N>` only. `chromium_headless_shell-<N>` and `chromium-tip-of-tree-<N>` deliberately do not match. */
const CFT_REVISION_DIR = /^chromium-(\d+)$/;
/** `chrome-mac` (Intel) and `chrome-mac-arm64` (Apple silicon) — whichever the install wrote. */
export const CFT_PLATFORM_DIR_PREFIX = "chrome-mac";
export const CFT_EXECUTABLE_IN_PLATFORM_DIR = [
  "Google Chrome for Testing.app",
  "Contents",
  "MacOS",
  "Google Chrome for Testing",
] as const;

/**
 * The one-time install that makes the cft default work. Runs this plugin's OWN pinned
 * playwright-core (bunx prefers the local node_modules/.bin), which honours
 * PLAYWRIGHT_BROWSERS_PATH exactly as defaultPlaywrightCacheRoot() does.
 */
export const CFT_INSTALL_COMMAND = `cd "${import.meta.dir}" && bunx playwright-core install chromium`;

/** Where Playwright keeps downloaded browsers on macOS, honouring its own PLAYWRIGHT_BROWSERS_PATH override. */
export function defaultPlaywrightCacheRoot(env: EnvLike = process.env): string {
  const override = env[PLAYWRIGHT_BROWSERS_PATH_ENV] ?? "";
  // "0" is Playwright's sentinel for "inside node_modules/playwright-core", not a directory name.
  if (override !== "" && override !== "0") {
    return resolve(override);
  }
  return join(homedir(), "Library", "Caches", "ms-playwright");
}

function listDirectory(path: string): string[] {
  try {
    return readdirSync(path);
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code === "ENOENT" || code === "ENOTDIR") {
      return [];
    }
    throw error;
  }
}

const isFile = (path: string): boolean => statSync(path, { throwIfNoEntry: false })?.isFile() ?? false;

/** Numeric revision of a `chromium-<N>` directory name, or null for anything else. */
function chromiumRevision(name: string): number | null {
  const digits = name.match(CFT_REVISION_DIR)?.[1];
  return digits === undefined ? null : Number.parseInt(digits, 10);
}

/**
 * Absolute path of the newest installed Chrome for Testing executable under `cacheRoot`,
 * or null when none is installed.
 *
 * "Newest" is the NUMERICALLY highest `chromium-<N>` revision (chromium-1243 beats
 * chromium-999, which a string sort gets backwards) that actually contains the
 * executable, so a half-finished download in a higher revision does not hide a
 * working lower one. Headless-shell directories never match: they hold a different
 * binary with no .app bundle.
 */
export function resolveChromeForTestingExecutable(cacheRoot: string = defaultPlaywrightCacheRoot()): string | null {
  const revisions = listDirectory(cacheRoot)
    .map((name) => ({ dir: join(cacheRoot, name), revision: chromiumRevision(name) }))
    .filter((entry): entry is { dir: string; revision: number } => entry.revision !== null)
    .toSorted((a, b) => b.revision - a.revision);
  const candidates = revisions.flatMap(({ dir }) =>
    listDirectory(dir)
      .filter((name) => name.startsWith(CFT_PLATFORM_DIR_PREFIX))
      .toSorted()
      .map((platformDir) => join(dir, platformDir, ...CFT_EXECUTABLE_IN_PLATFORM_DIR)),
  );
  return candidates.find(isFile) ?? null;
}
