#!/usr/bin/env bun
/**
 * pushover_headless_web_control.ts — headless control of the pushover.net
 * dashboard for the things the HTTP API cannot do (create/delete apps, mint API
 * tokens, add/remove custom sounds, edit app metadata/icons).
 *
 * Drives system Google Chrome via Playwright (`channel: "chrome"`, no browser
 * download). pushover.net login is a plain email/password form with no
 * anti-bot/CAPTCHA/2FA, so plain Playwright is sufficient.
 *
 * Credentials come from the environment (resolve via resolve_pushover_secret.sh):
 *   PO_EMAIL, PO_PW — login. PO_USER (optional) — the user key, excluded when
 *   scraping a newly-minted 30-char app token. Tokens are masked unless --reveal.
 *
 * Function-driven + enum-driven by design (mirrors wa-cli.ts / gmail-commander):
 * Command/ExitCode/EnvVar are enums and commands dispatch through an enum-keyed
 * Record<Command, Handler> table — adding a command forces a handler.
 *
 * Ported from pushover_headless_web_control.py (behaviour-preserving).
 */

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

const trimmed = (value: string | null): string => (value ?? "").trim();

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

export async function createApp(pg: Page, opts: Options, userKey: string): Promise<Json> {
  const name = requireFlag(opts.name, "create-app requires --name");
  const out: Json = { name };
  await pg.goto(`${BASE}/apps/build`, { waitUntil: "networkidle", timeout: 30000 });
  await pg.fill("#application_short_name", name);
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
  const candidates = await scrapeTokens(pg);
  if (userKey) {
    candidates.delete(userKey);
  }
  const token = [...candidates].toSorted()[0] ?? null;
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
    await pg.fill("#application_short_name", opts.newName);
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
  const nameField = await pg.$("#application_short_name");
  const descField = await pg.$("#application_description");
  out.name = nameField ? await nameField.inputValue() : null;
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
  for (let index = 1; index < argv.length; index += 1) {
    const arg = argv[index] ?? "";
    if (arg === "--reveal") {
      reveal = true;
    } else if (arg === "--headed") {
      headed = true;
    } else if (arg in VALUE_FLAGS) {
      collected[VALUE_FLAGS[arg] as string] = argv[index + 1] ?? "";
      index += 1;
    } else {
      throw new UsageError(`unknown flag "${arg}"`);
    }
  }
  const options: Options = {
    name: collected.name,
    newName: collected.newName,
    slug: collected.slug,
    file: collected.file,
    icon: collected.icon,
    desc: collected.desc ?? "",
    url: collected.url ?? "",
    reveal,
    headed,
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

Flags: --reveal (show full token), --headed (visible browser).
Env: PO_EMAIL, PO_PW (required), PO_USER (optional token disambiguation).
`;

/**
 * Launch system Chrome, hand a logged-in-capable page to `fn`, and always close
 * the browser. Shared by the CLI and by programmatic callers (e.g. batch create).
 */
export async function withDashboard<T>(
  headed: boolean,
  fn: (pg: Page) => Promise<T>,
): Promise<T> {
  let browser: Browser | undefined;
  try {
    browser = await chromium.launch({ channel: "chrome", headless: !headed });
    const context = await browser.newContext({ viewport: { width: 1100, height: 1700 } });
    const pg = await context.newPage();
    pg.on("dialog", (dialog) => void dialog.accept());
    return await fn(pg);
  } finally {
    await browser?.close();
  }
}

async function run(command: Command, options: Options): Promise<Json> {
  const creds = resolveCredentials();
  return withDashboard(options.headed, async (pg) => {
    const out = await login(pg, creds);
    if (out.logged_in) {
      Object.assign(out, await HANDLERS[command](pg, options, creds));
    }
    return out;
  });
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

main()
  .then((code) => process.exit(code))
  .catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`${message}\n`);
    process.exit(error instanceof UsageError ? ExitCode.Usage : ExitCode.Failure);
  });
