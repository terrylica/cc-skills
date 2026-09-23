#!/usr/bin/env bun
/**
 * pushover_headless_web_control.ts — headless control of the pushover.net
 * dashboard for the things the HTTP API cannot do (create/delete apps, mint API
 * tokens, add/remove custom sounds, edit app metadata/icons).
 *
 * Drives Playwright's "Google Chrome for Testing.app" by default (`--browser cft`),
 * NOT the operator's own Google Chrome — see planBrowserLaunch() for why. System
 * Chrome (`channel: "chrome"`) is available with `--browser chrome`, and is used as
 * a loudly-announced fallback only when no Chrome for Testing is installed and the
 * caller did not explicitly ask for one. pushover.net login is a plain
 * email/password form with no anti-bot/CAPTCHA/2FA, so plain Playwright suffices.
 *
 * Credentials come from the environment (resolve via resolve_pushover_secret.sh):
 *   PO_EMAIL, PO_PW — login. PO_USER (optional) — the user key, excluded when
 *   scraping a newly-minted 30-char app token. Tokens are masked unless --reveal.
 *
 * Importable: the CLI runs only under `import.meta.main`, so another script can
 * import login/createApp/editApp/withDashboard without executing this CLI.
 *
 * Function-driven + enum-driven by design (mirrors wa-cli.ts / gmail-commander):
 * Command/ExitCode/EnvVar are enums and commands dispatch through an enum-keyed
 * Record<Command, Handler> table — adding a command forces a handler.
 *
 * Ported from pushover_headless_web_control.py (behaviour-preserving).
 */

import { readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import process from "node:process";
import { chromium, type Browser, type Page } from "playwright-core";

enum Command {
  Apps = "apps",
  DumpApps = "dump-apps",
  CreateApp = "create-app",
  DeleteApp = "delete-app",
  EditApp = "edit-app",
  ListSounds = "list-sounds",
  AddSound = "add-sound",
  RemoveSound = "remove-sound",
}

enum ExitCode {
  Ok = 0,
  Failure = 1,
  Usage = 2,
}

enum EnvVar {
  Email = "PO_EMAIL",
  Password = "PO_PW",
  UserKey = "PO_USER",
  /** Browser selection when --browser is absent: "cft" or "chrome". */
  Browser = "PUSHOVER_WEB_BROWSER",
  /** Playwright's own cache-location override, honoured so we look where `playwright install` wrote. */
  PlaywrightBrowsersPath = "PLAYWRIGHT_BROWSERS_PATH",
}

/** Which browser binary drives the dashboard. The string values are the --browser / env spellings. */
export enum BrowserChoice {
  /** Playwright's "Google Chrome for Testing.app" (bundle id com.google.chrome.for.testing). The default. */
  ChromeForTesting = "cft",
  /** The operator's own /Applications/Google Chrome.app (bundle id com.google.Chrome), via channel "chrome". */
  SystemChrome = "chrome",
}

const BASE = "https://pushover.net";
/** A Pushover API token is exactly 30 alphanumerics. */
const TOKEN_GLOBAL = /[A-Za-z0-9]{30}/g;
const TOKEN_EXACT = /^[A-Za-z0-9]{30}$/;
/** "/apps/<slug>" with no further path segment (an app landing page). */
const APP_SLUG_HREF = /^\/apps\/[^/]+$/;

type Json = Record<string, unknown>;

/** Caller-fixable input problem → exit code 2. */
class UsageError extends Error {}

export interface Options {
  readonly name?: string;
  readonly newName?: string;
  readonly slug?: string;
  readonly file?: string;
  readonly icon?: string;
  readonly desc: string;
  readonly url: string;
  readonly reveal: boolean;
  readonly headed: boolean;
  /** Explicit --browser choice. Absent means "PUSHOVER_WEB_BROWSER, else the cft default". */
  readonly browser?: BrowserChoice;
}

export interface Credentials {
  readonly email: string;
  readonly password: string;
  readonly userKey: string;
}

/** Build a fully-populated Options from a partial — handy for programmatic callers. */
export function blankOptions(overrides: Partial<Options> = {}): Options {
  return { desc: "", url: "", reveal: false, headed: true, ...overrides };
}

export function resolveCredentials(): Credentials {
  const email = process.env[EnvVar.Email] ?? "";
  const password = process.env[EnvVar.Password] ?? "";
  if (email === "" || password === "") {
    throw new UsageError(
      `login needs ${EnvVar.Email} and ${EnvVar.Password} in the environment ` +
        "(resolve via resolve_pushover_secret.sh).",
    );
  }
  return { email, password, userKey: process.env[EnvVar.UserKey] ?? "" };
}

// ---------- browser selection ----------
//
// Why the default is NOT the operator's own Google Chrome. `channel: "chrome"` starts a
// SECOND instance of /Applications/Google Chrome.app on a throwaway profile, and both
// instances carry the same bundle id (com.google.Chrome). On 2026-09-22 such a second
// instance collided with the operator's running Chrome in macOS LaunchServices: links
// stopped opening anywhere and every Chrome had to be force-quit. Playwright's
// "Google Chrome for Testing.app" is a different bundle (com.google.chrome.for.testing),
// so LaunchServices never confuses the two.

/** `chromium-<N>` only. `chromium_headless_shell-<N>` and `chromium-tip-of-tree-<N>` deliberately do not match. */
const CFT_REVISION_DIR = /^chromium-(\d+)$/;
/** `chrome-mac` (Intel) and `chrome-mac-arm64` (Apple silicon) — whichever the install wrote. */
const CFT_PLATFORM_DIR_PREFIX = "chrome-mac";
const CFT_EXECUTABLE_IN_PLATFORM_DIR = [
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

/** Thrown when Chrome for Testing was explicitly requested but is not installed. Exit code 1. */
export class BrowserUnavailableError extends Error {}

type EnvLike = Readonly<Record<string, string | undefined>>;

/** Where Playwright keeps downloaded browsers on macOS, honouring its own PLAYWRIGHT_BROWSERS_PATH override. */
export function defaultPlaywrightCacheRoot(env: EnvLike = process.env): string {
  const override = env[EnvVar.PlaywrightBrowsersPath] ?? "";
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

/** Parse a --browser / PUSHOVER_WEB_BROWSER value; `source` names where it came from in the error. */
export function parseBrowserChoice(value: string, source: string): BrowserChoice {
  const match = Object.values(BrowserChoice).find((candidate) => candidate === value);
  if (match === undefined) {
    throw new UsageError(`${source} must be one of: ${Object.values(BrowserChoice).join(", ")} (got "${value}")`);
  }
  return match;
}

export interface BrowserPlanInput {
  /** The parsed --browser flag, when given. It beats the environment. */
  readonly flag?: BrowserChoice | undefined;
  /** Defaults to process.env. Read for PUSHOVER_WEB_BROWSER and PLAYWRIGHT_BROWSERS_PATH. */
  readonly env?: EnvLike;
  /** Defaults to defaultPlaywrightCacheRoot(env). Injected by tests. */
  readonly cacheRoot?: string;
  /** Where the fallback warning goes. Defaults to stderr. */
  readonly warn?: (text: string) => void;
}

export interface BrowserLaunchPlan {
  /** What the caller asked for, or the cft default when they asked for nothing. */
  readonly requested: BrowserChoice;
  /** True when the choice came from --browser or PUSHOVER_WEB_BROWSER rather than the default. */
  readonly explicit: boolean;
  /** What will actually be launched. Differs from `requested` only on the announced fallback. */
  readonly launched: BrowserChoice;
  readonly launchOptions: { readonly executablePath: string } | { readonly channel: "chrome" };
  /** The text sent to `warn`, or null when nothing needed saying. */
  readonly warning: string | null;
}

function fallbackWarning(cacheRoot: string): string {
  const bar = "!".repeat(96);
  return [
    bar,
    'WARNING: Chrome for Testing is NOT installed, so this run FALLS BACK to your own Google Chrome (channel "chrome").',
    `  Looked for: ${join(cacheRoot, "chromium-<N>", `${CFT_PLATFORM_DIR_PREFIX}*`, CFT_EXECUTABLE_IN_PLATFORM_DIR[0])}`,
    "  RISK: a second Google Chrome instance on a separate profile can collide with your running Chrome in",
    "  macOS LaunchServices: links stop opening and every Chrome may have to be force-quit (seen 2026-09-22).",
    `  FIX, once: ${CFT_INSTALL_COMMAND}`,
    `  To drive system Chrome deliberately and silence this: --browser ${BrowserChoice.SystemChrome} (or ${EnvVar.Browser}=${BrowserChoice.SystemChrome}).`,
    bar,
    "",
  ].join("\n");
}

/**
 * Decide which browser to launch. Precedence: --browser, then PUSHOVER_WEB_BROWSER, then cft.
 *
 *   - chrome (explicit)           → channel "chrome", no warning: the caller chose it.
 *   - cft, installed              → executablePath of the newest Chrome for Testing.
 *   - cft EXPLICIT, not installed → BrowserUnavailableError naming the install command.
 *   - cft DEFAULT, not installed  → channel "chrome", with a loud warning to `warn`.
 *     Never silent: substituting a riskier browser without saying so is how the
 *     LaunchServices collision would recur unnoticed.
 */
export function planBrowserLaunch(input: BrowserPlanInput = {}): BrowserLaunchPlan {
  const env = input.env ?? process.env;
  const cacheRoot = input.cacheRoot ?? defaultPlaywrightCacheRoot(env);
  const warn = input.warn ?? ((text: string) => void process.stderr.write(text));
  const envValue = env[EnvVar.Browser] ?? "";

  let requested: BrowserChoice = BrowserChoice.ChromeForTesting;
  let source: string | null = null;
  if (input.flag !== undefined) {
    requested = input.flag;
    source = `--browser ${input.flag}`;
  } else if (envValue !== "") {
    requested = parseBrowserChoice(envValue, EnvVar.Browser);
    source = `${EnvVar.Browser}=${envValue}`;
  }
  const explicit = source !== null;

  if (requested === BrowserChoice.SystemChrome) {
    return { requested, explicit, launched: requested, launchOptions: { channel: "chrome" }, warning: null };
  }
  const executablePath = resolveChromeForTestingExecutable(cacheRoot);
  if (executablePath !== null) {
    return { requested, explicit, launched: requested, launchOptions: { executablePath }, warning: null };
  }
  if (source !== null) {
    throw new BrowserUnavailableError(
      `Chrome for Testing was requested (${source}) but none is installed under ${cacheRoot} ` +
        `(looked for chromium-<N>/${CFT_PLATFORM_DIR_PREFIX}*/${CFT_EXECUTABLE_IN_PLATFORM_DIR[0]}). ` +
        `Install it once: ${CFT_INSTALL_COMMAND} — or pass --browser ${BrowserChoice.SystemChrome} to drive your own ` +
        "Google Chrome, accepting the LaunchServices collision risk.",
    );
  }
  const warning = fallbackWarning(cacheRoot);
  warn(warning);
  return {
    requested,
    explicit,
    launched: BrowserChoice.SystemChrome,
    launchOptions: { channel: "chrome" },
    warning,
  };
}

const trimmed =(value: string | null): string => (value ?? "").trim();

export async function login(pg: Page, creds: Credentials): Promise<Json> {
  const out: Json = {};
  await pg.goto(`${BASE}/login`, { waitUntil: "domcontentloaded", timeout: 45000 });
  for (const selector of ['input[name="email"]', 'input[type="email"]', 'input[type="text"]']) {
    const el = await pg.$(selector);
    if (el) {
      await el.fill(creds.email);
      break;
    }
  }
  const pwField = await pg.$('input[type="password"]');
  if (pwField) {
    await pwField.fill(creds.password);
  }
  for (const selector of ['button[type="submit"]', 'input[type="submit"]', 'button:has-text("Login")']) {
    const el = await pg.$(selector);
    if (el) {
      await el.click();
      break;
    }
  }
  try {
    await pg.waitForLoadState("networkidle", { timeout: 30000 });
  } catch (error) {
    out.networkidle_timeout = (error instanceof Error ? error.message : String(error)).slice(0, 120);
  }
  out.url = pg.url();
  out.logged_in = !pg.url().includes("/login");
  return out;
}

/** Collect distinct, non-empty link texts for every "/apps/..." anchor. */
async function listApps(pg: Page): Promise<string[]> {
  await pg.goto(`${BASE}/`, { waitUntil: "networkidle", timeout: 30000 });
  const names = new Set<string>();
  for (const a of await pg.$$('a[href^="/apps/"]')) {
    const text = trimmed(await a.textContent());
    if (text !== "") {
      names.add(text);
    }
  }
  return [...names].toSorted();
}

async function findAppHref(pg: Page, name: string): Promise<string | null> {
  await pg.goto(`${BASE}/`, { waitUntil: "networkidle", timeout: 30000 });
  for (const a of await pg.$$('a[href^="/apps/"]')) {
    if (trimmed(await a.textContent()) === name) {
      return a.getAttribute("href");
    }
  }
  return null;
}

/** All 30-char token candidates on the page (body text + every input value). */
async function scrapeTokens(pg: Page): Promise<Set<string>> {
  const candidates = new Set<string>(((await pg.innerText("body")).match(TOKEN_GLOBAL)) ?? []);
  const values = await pg.$$eval("input", (els) =>
    els.map((e) => (e as HTMLInputElement).value || ""),
  );
  for (const value of values) {
    for (const match of value.match(TOKEN_GLOBAL) ?? []) {
      candidates.add(match);
    }
  }
  return candidates;
}

const maskToken = (token: string): string => `${token.slice(0, 4)}...${token.slice(-4)}`;

/**
 * The application-name field, which pushover.net RENAMED.
 *
 * Measured live 2026-09-20 on /apps/build: the field is
 * `<input id="application_name" name="application[name]">`. This script hard-coded
 * `#application_short_name`, so every create-app and edit-app call died with
 * `fill: Timeout 30000ms exceeded — waiting for locator('#application_short_name')`.
 *
 * Both spellings are tried, newest first, because the edit and build forms have
 * drifted apart before and a single hard-coded id is exactly what broke. If NEITHER
 * is present the helper throws with the page URL rather than letting a later step
 * submit a form whose name field was never filled — a create that silently posts an
 * empty name would mint a garbage app, which is worse than a clean failure.
 */
const APP_NAME_FIELD_SELECTORS = ["#application_name", "#application_short_name"] as const;

async function fillApplicationName(pg: Page, value: string): Promise<string> {
  for (const selector of APP_NAME_FIELD_SELECTORS) {
    const el = await pg.$(selector);
    if (el) {
      await el.fill(value);
      return selector;
    }
  }
  throw new Error(
    `no application-name field found on ${pg.url()} — tried ${APP_NAME_FIELD_SELECTORS.join(", ")}. ` +
      "pushover.net has changed the form again; re-probe the page's inputs before editing this list.",
  );
}

async function readApplicationName(pg: Page): Promise<string | null> {
  for (const selector of APP_NAME_FIELD_SELECTORS) {
    const el = await pg.$(selector);
    if (el) return await el.inputValue();
  }
  return null;
}

export async function createApp(pg: Page, opts: Options, userKey: string): Promise<Json> {
  const name = requireFlag(opts.name, "create-app requires --name");
  const out: Json = { name };
  await pg.goto(`${BASE}/apps/build`, { waitUntil: "networkidle", timeout: 30000 });
  out.name_field_used = await fillApplicationName(pg, name);
  if (opts.desc) {
    await pg.fill("#application_description", opts.desc);
  }
  if (opts.url) {
    await pg.fill("#application_url", opts.url);
  }
  await pg.check("#application_terms_of_service");
  await pg.click('input[name="commit"]');
  await pg.waitForLoadState("networkidle", { timeout: 30000 });
  out.app_url = pg.url();

  // Reliable extraction: a successful create lands on the app's page
  // (/apps/<slug>). Read the 30-char token from THAT page's input fields
  // (excluding the user key) — exactly how dumpApps() scrapes per-app tokens.
  // The old `scrapeTokens()+toSorted()[0]` guessed the alphabetically-first
  // 30-char string in the whole body, which on the post-create page can be a
  // CSRF/nonce/asset hash → an invalid "minted-but-dead" token (the documented
  // failure mode). Only fall back to the body scrape if no app page was reached.
  let token: string | null = null;
  const slug = pg.url().match(/\/apps\/([^/?#]+)$/)?.[1];
  if (slug && !["build", "new"].includes(slug)) {
    out.new_slug = slug;
    const values = await pg.$$eval("input", (els) =>
      els.map((e) => (e as HTMLInputElement).value || ""),
    );
    token = values.find((v) => TOKEN_EXACT.test(v) && v !== userKey) ?? null;
  }
  if (token === null) {
    const candidates = await scrapeTokens(pg);
    if (userKey) {
      candidates.delete(userKey);
    }
    token = [...candidates][0] ?? null;
  }

  out.created = token !== null;
  out.token = token === null ? null : opts.reveal ? token : maskToken(token);
  return out;
}

async function deleteApp(pg: Page, opts: Options): Promise<Json> {
  const out: Json = {};
  let slug = opts.slug;
  if (!slug) {
    const href = await findAppHref(pg, requireFlag(opts.name, "delete-app requires --name or --slug"));
    out.app_href = href;
    if (!href) {
      out.error = "app not found by name";
      return out;
    }
    slug = href.split("/").at(-1);
  }
  out.slug = slug;
  await pg.goto(`${BASE}/apps/edit/${slug}`, { waitUntil: "networkidle", timeout: 30000 });
  const control = await pg.$('a[href^="/apps/destroy/"]');
  out.delete_control = Boolean(control);
  if (control) {
    await control.click(); // Rails data-method=post; confirm() auto-accepted via dialog handler
    await pg.waitForLoadState("networkidle", { timeout: 20000 });
  }
  const names = await listApps(pg);
  out.deleted = opts.name ? !names.includes(opts.name) : !names.join(",").includes(slug ?? "");
  return out;
}

async function listSounds(pg: Page): Promise<string[]> {
  await pg.goto(`${BASE}/sounds`, { waitUntil: "networkidle", timeout: 30000 });
  const names = new Set<string>();
  for (const a of await pg.$$('a[href^="/sounds/edit/"]')) {
    names.add((await a.getAttribute("href") ?? "").split("/").at(-1) ?? "");
  }
  return [...names].toSorted();
}

async function addSound(pg: Page, opts: Options): Promise<Json> {
  const name = requireFlag(opts.name, "add-sound requires --name and --file");
  const file = requireFlag(opts.file, "add-sound requires --name and --file");
  const out: Json = { name, file };
  await pg.goto(`${BASE}/sounds/build`, { waitUntil: "networkidle", timeout: 30000 });
  await pg.fill("#sound_name", name);
  if (opts.desc) {
    await pg.fill("#sound_description", opts.desc);
  }
  await pg.setInputFiles("#sound_sound_data_file", file);
  await pg.click('input[name="commit"]');
  await pg.waitForLoadState("networkidle", { timeout: 60000 });
  out.url_after = pg.url();
  const sounds = await listSounds(pg);
  out.added = sounds.includes(name);
  if (!out.added) {
    const body = await pg.innerText("body");
    out.error_hints = body
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => ["error", "must", "size", "too", "invalid"].some((k) => line.toLowerCase().includes(k)))
      .slice(0, 5);
  }
  return out;
}

async function removeSound(pg: Page, opts: Options): Promise<Json> {
  const name = requireFlag(opts.name, "remove-sound requires --name");
  const out: Json = { name };
  await pg.goto(`${BASE}/sounds/edit/${name}`, { waitUntil: "networkidle", timeout: 30000 });
  const control = (await pg.$('a[href^="/sounds/destroy/"]')) ?? (await pg.$('a:has-text("Delete")'));
  out.delete_control = Boolean(control);
  if (control) {
    await control.click(); // Rails data-method=post; confirm() auto-accepted
    await pg.waitForLoadState("networkidle", { timeout: 20000 });
  }
  out.removed = !(await listSounds(pg)).includes(name);
  return out;
}

/** Inventory every app: name, slug, 30-char API token, description. */
async function dumpApps(pg: Page, userKey: string): Promise<Json[]> {
  await pg.goto(`${BASE}/`, { waitUntil: "networkidle", timeout: 30000 });
  const seen = new Set<string>();
  const apps: Array<{ name: string; slug: string; token?: string | null; description?: string }> = [];
  for (const a of await pg.$$('a[href^="/apps/"]')) {
    const href = (await a.getAttribute("href")) ?? "";
    const name = trimmed(await a.textContent());
    if (name && APP_SLUG_HREF.test(href) && !name.includes("Create an")) {
      const slug = href.split("/").at(-1) ?? "";
      if (!seen.has(slug) && slug !== "build" && slug !== "new") {
        seen.add(slug);
        apps.push({ name, slug });
      }
    }
  }
  for (const app of apps) {
    await pg.goto(`${BASE}/apps/${app.slug}`, { waitUntil: "networkidle", timeout: 30000 });
    const values = await pg.$$eval("input", (els) => els.map((e) => (e as HTMLInputElement).value || ""));
    const token = values.find((v) => TOKEN_EXACT.test(v) && v !== userKey) ?? null;
    app.token = token;
    await pg.goto(`${BASE}/apps/edit/${app.slug}`, { waitUntil: "networkidle", timeout: 30000 });
    const descField = await pg.$("#application_description");
    app.description = descField ? await descField.inputValue() : "";
  }
  return apps;
}

/** Rename / set description (<=500) / url / upload icon. Slug changes on rename. */
export async function editApp(pg: Page, opts: Options): Promise<Json> {
  let slug = opts.slug;
  if (!slug && opts.name) {
    const href = await findAppHref(pg, opts.name);
    slug = href ? href.split("/").at(-1) : undefined;
  }
  slug = requireFlag(slug, "edit-app requires --slug or --name");
  const out: Json = { slug };
  await pg.goto(`${BASE}/apps/edit/${slug}`, { waitUntil: "networkidle", timeout: 30000 });
  if (opts.newName !== undefined) {
    out.name_field_used = await fillApplicationName(pg, opts.newName);
  }
  if (opts.desc) {
    await pg.fill("#application_description", opts.desc.slice(0, 500));
  }
  if (opts.url) {
    await pg.fill("#application_url", opts.url);
  }
  if (opts.icon) {
    await pg.setInputFiles("#application_icon", opts.icon);
  }
  await pg.click('input[name="commit"]');
  await pg.waitForLoadState("networkidle", { timeout: 60000 });
  const newSlug = pg.url().includes("/apps/") ? (pg.url().split("/").at(-1) ?? slug) : slug;
  out.new_slug = newSlug;
  await pg.goto(`${BASE}/apps/edit/${newSlug}`, { waitUntil: "networkidle", timeout: 30000 });
  const descField = await pg.$("#application_description");
  out.name = await readApplicationName(pg);
  out.desc_len = descField ? (await descField.inputValue()).length : 0;
  return out;
}

type Handler = (pg: Page, opts: Options, creds: Credentials) => Promise<Json>;

/** Enum-keyed dispatch table — adding a Command forces a handler here. */
const HANDLERS: Record<Command, Handler> = {
  [Command.Apps]: async (pg) => ({ apps: await listApps(pg) }),
  [Command.DumpApps]: async (pg, _opts, creds) => ({ apps_detail: await dumpApps(pg, creds.userKey) }),
  [Command.CreateApp]: (pg, opts, creds) => createApp(pg, opts, creds.userKey),
  [Command.DeleteApp]: (pg, opts) => deleteApp(pg, opts),
  [Command.EditApp]: (pg, opts) => editApp(pg, opts),
  [Command.ListSounds]: async (pg) => ({ sounds: await listSounds(pg) }),
  [Command.AddSound]: (pg, opts) => addSound(pg, opts),
  [Command.RemoveSound]: (pg, opts) => removeSound(pg, opts),
};

function requireFlag<T>(value: T | undefined | null, message: string): T {
  if (value === undefined || value === null || value === "") {
    throw new UsageError(message);
  }
  return value;
}

function parseCommand(value: string | undefined): Command {
  const fallback = Command.Apps;
  if (value === undefined) {
    return fallback;
  }
  for (const candidate of Object.values(Command)) {
    if (candidate === value) {
      return candidate;
    }
  }
  throw new UsageError(
    `unknown command "${value}" — use one of: ${Object.values(Command).join(", ")}`,
  );
}

const VALUE_FLAGS: Record<string, keyof Options> = {
  "--name": "name",
  "--new-name": "newName",
  "--slug": "slug",
  "--file": "file",
  "--icon": "icon",
  "--desc": "desc",
  "--url": "url",
};

function parseArgs(argv: readonly string[]): { command: Command; options: Options } {
  const command = parseCommand(argv[0]);
  const collected: Record<string, string> = {};
  let reveal = false;
  let headed = false;
  let browser: BrowserChoice | undefined;
  for (let index = 1; index < argv.length; index += 1) {
    const arg = argv[index] ?? "";
    if (arg === "--reveal") {
      reveal = true;
    } else if (arg === "--headed") {
      headed = true;
    } else if (arg === "--browser") {
      const value = argv[index + 1] ?? "";
      if (value === "") {
        throw new UsageError(`--browser needs a value: ${Object.values(BrowserChoice).join(" or ")}`);
      }
      browser = parseBrowserChoice(value, "--browser");
      index += 1;
    } else if (arg in VALUE_FLAGS) {
      collected[VALUE_FLAGS[arg] as string] = argv[index + 1] ?? "";
      index += 1;
    } else {
      throw new UsageError(`unknown flag "${arg}"`);
    }
  }
  const options: Options = {
    ...(collected.name ? { name: collected.name } : {}),
    ...(collected.newName ? { newName: collected.newName } : {}),
    ...(collected.slug ? { slug: collected.slug } : {}),
    ...(collected.file ? { file: collected.file } : {}),
    ...(collected.icon ? { icon: collected.icon } : {}),
    desc: collected.desc ?? "",
    url: collected.url ?? "",
    reveal,
    headed,
    ...(browser === undefined ? {} : { browser }),
  };
  return { command, options };
}

const USAGE = `pushover_headless_web_control.ts — headless pushover.net dashboard control

Usage: bun pushover_headless_web_control.ts <command> [flags]

Commands:
  apps                                  list application names (default)
  dump-apps                             inventory apps: name, slug, token, description
  create-app --name N [--desc D] [--url U] [--reveal]   create app, return API token
  delete-app (--name N | --slug S)      delete app, verify gone
  edit-app  (--slug S | --name N) [--new-name N] [--desc D] [--url U] [--icon PATH]
  list-sounds                           list custom sound names
  add-sound    --name N --file PATH [--desc D]   upload a custom sound
  remove-sound --name N                 delete a custom sound

Flags: --reveal (show full token), --headed (visible browser),
       --browser cft|chrome (default cft = Playwright's Google Chrome for Testing;
       chrome = your own Google Chrome, which can collide with it in macOS LaunchServices).
Env: PO_EMAIL, PO_PW (required), PO_USER (optional token disambiguation),
     PUSHOVER_WEB_BROWSER (cft|chrome, used when --browser is absent),
     PLAYWRIGHT_BROWSERS_PATH (where Chrome for Testing is installed, as Playwright reads it).
With no Chrome for Testing installed and no explicit choice, falls back to system Chrome
with a loud stderr warning; an explicit cft with none installed exits 1.
Install Chrome for Testing once: ${CFT_INSTALL_COMMAND}
`;

/** The one Playwright call withDashboard makes; injectable so tests can see what would launch. */
export type BrowserLauncher = Pick<typeof chromium, "launch">;

/**
 * Launch the planned browser, hand a logged-in-capable page to `fn`, and always
 * close the browser. Shared by the CLI and by programmatic callers (e.g. batch
 * create). `plan` defaults to planBrowserLaunch(), i.e. PUSHOVER_WEB_BROWSER or cft.
 */
export async function withDashboard<T>(
  headed: boolean,
  fn: (pg: Page) => Promise<T>,
  plan: BrowserLaunchPlan = planBrowserLaunch(),
  launcher: BrowserLauncher = chromium,
): Promise<T> {
  let browser: Browser | undefined;
  try {
    browser = await launcher.launch({ ...plan.launchOptions, headless: !headed });
    const context = await browser.newContext({ viewport: { width: 1100, height: 1700 } });
    const pg = await context.newPage();
    pg.on("dialog", (dialog) => void dialog.accept());
    return await fn(pg);
  } finally {
    await browser?.close();
  }
}

async function run(command: Command, options: Options): Promise<Json> {
  // Browser first: it is local, cheap and needs no secret, so a missing Chrome for
  // Testing fails (or is announced) before any credential is read or browser started.
  const plan = planBrowserLaunch({ flag: options.browser });
  const creds = resolveCredentials();
  return withDashboard(
    options.headed,
    async (pg) => {
      const out = await login(pg, creds);
      if (out.logged_in) {
        Object.assign(out, await HANDLERS[command](pg, options, creds));
      }
      return out;
    },
    plan,
  );
}

async function main(): Promise<ExitCode> {
  const argv = process.argv.slice(2);
  const first = argv[0];
  if (first === "-h" || first === "--help") {
    process.stdout.write(USAGE);
    return ExitCode.Ok;
  }
  const { command, options } = parseArgs(argv);
  const out = await run(command, options);
  process.stdout.write(`${JSON.stringify(out, null, 2)}\n`);
  return ExitCode.Ok;
}

// CLI entry ONLY when this file is the program. Without the guard, merely importing
// the exported helpers (batch_create_pushover_apps.ts does) ran this CLI as a side
// effect: it parsed the importer's argv, logged in, and then process.exit()ed the
// importer from underneath it.
if (import.meta.main) {
  main()
    .then((code) => process.exit(code))
    .catch((error: unknown) => {
      const message = error instanceof Error ? error.message : String(error);
      process.stderr.write(`${message}\n`);
      process.exit(error instanceof UsageError ? ExitCode.Usage : ExitCode.Failure);
    });
}
