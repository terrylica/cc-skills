#!/usr/bin/env bun
// web-forge — run console recipes (settings and mints that no API reaches) through a real Chrome.
//
//   web-forge recipes [--json]                      list recipes, verbs and flags (machine-readable with --json)
//   web-forge <recipe> <verb> [flags]               run a recipe; JSON result on stdout, progress on stderr
//   web-forge serve --account <email> [--port n]    keep one browser session open for successive runs
//   web-forge stop [--port n]                       stop a bridge started by serve
//
// Connection modes (--connect): extension (default) drives the --account's profile of your everyday Chrome through
// the Playwright Extension; cdp drives the persistent per-site forge profile (--site, default the recipe family).
//
// Exit codes: 0 ok · 1 failed or read-back mismatch · 2 usage · 3 exists but differs (no --update)
//             4 sign-in / re-authentication not completed in time
import { readFileSync } from "node:fs";
import { argvFromSpec, type FlagSpec, type Flags, helpText, parseFlags, UsageError } from "./lib/args.ts";
import { type AlertLevel, loginGate, ReauthTimeout } from "./lib/gate.ts";
import { type Connect, connect, serve, type Target } from "./lib/mcp.ts";
import { Driver, FAILURE_DIR } from "./lib/page.ts";
import { RECIPES } from "./recipes/index.ts";

const DEFAULT_PORT = 47811;
const log = (s: string) => console.error(s);

const EXIT_CODES = { 0: "ok", 1: "failed or read-back mismatch", 2: "usage", 3: "exists but differs (no --update)", 4: "sign-in / re-authentication not completed" };

/** Flags that choose the browser: shared by every recipe and by serve. */
export const CONNECT_FLAGS: FlagSpec[] = [
  { name: "account", type: "string", required: true, help: "The identity the run acts as; in extension mode it also picks the Chrome profile (chrome-profile.sh resolves it by email)" },
  { name: "connect", type: "string", choices: ["extension", "cdp"], default: "extension", env: "WEB_FORGE_CONNECT", help: "extension: the account's profile of your everyday Chrome (Playwright Extension); cdp: the persistent per-site forge profile on its own debug port" },
  { name: "site", type: "string", help: "cdp mode: the per-site profile under ~/.local/share/web-forge/ (default: the recipe family)" },
  { name: "port", type: "int", env: "WEB_FORGE_BRIDGE_PORT", help: "Reuse the bridge on 127.0.0.1:<port> when it serves the same target; otherwise a one-run session is opened" },
];

/** Flags every recipe accepts. */
export const COMMON_FLAGS: FlagSpec[] = [
  ...CONNECT_FLAGS,
  { name: "spec", type: "string", help: "A JSON file of flag names to values (the recipe spec); flags on the command line win" },
  { name: "screenshots", type: "string", help: `Save a PNG of the browser after every step into this directory (failures are always captured, by default under ${FAILURE_DIR.replace(process.env.HOME ?? "~", "~")})` },
  { name: "alert", type: "string", choices: ["none", "local", "emergency"], default: "local", help: "How to call the operator when the console asks to sign in or verify it's you: local notice, or a Pushover Emergency as well" },
  { name: "reauth-wait", type: "int", default: 600, help: "Seconds to wait for the operator to pass sign-in or re-authentication (the tab is polled, never reloaded)" },
];

/** Pure: the browser target the flags select. */
export function targetFrom(f: Flags, defaultSite?: string): Target {
  const mode = String(f.connect ?? "extension") as Connect;
  if (mode === "cdp") {
    const site = f.site ?? defaultSite;
    if (!site) throw new UsageError("--connect cdp needs --site <name>");
    return { mode, site: String(site) };
  }
  if (f.site !== undefined) throw new UsageError("--site applies to --connect cdp only");
  return { mode: "extension", account: String(f.account) };
}

/** Pure: lift `--spec <file>` out of argv and put the file's flags first, so the command line wins. */
export function expandSpec(argv: string[], specs: FlagSpec[], read: (path: string) => string): string[] {
  const i = argv.findIndex((a) => a === "--spec" || a.startsWith("--spec="));
  if (i < 0) return argv;
  const path = argv[i]!.startsWith("--spec=") ? argv[i]!.slice(7) : argv[i + 1];
  if (!path || path.startsWith("--")) throw new UsageError("--spec needs a file");
  const rest = [...argv.slice(0, i), ...argv.slice(argv[i]!.startsWith("--spec=") ? i + 1 : i + 2)];
  let json: unknown;
  try {
    json = JSON.parse(read(path));
  } catch (e) {
    throw new UsageError(`--spec ${path}: ${(e as Error).message}`);
  }
  return [...argvFromSpec(json, specs.filter((s) => s.name !== "spec")), ...rest];
}

function usage(): string {
  const lines = [
    "web-forge — run console recipes (settings and mints no API reaches) through a real Chrome",
    "",
    "usage:",
    "  web-forge recipes [--json]",
    "  web-forge <recipe> <verb> [flags]",
    "  web-forge serve --account <email> [--connect extension|cdp] [--site <name>] [--port <n>]",
    "  web-forge stop [--port <n>]",
    "",
    `exit: ${Object.entries(EXIT_CODES).map(([k, v]) => `${k} ${v}`).join(" · ")}`,
    "",
    "flags for every recipe:",
    helpText(COMMON_FLAGS),
  ];
  for (const r of Object.values(RECIPES)) lines.push("", `recipe ${r.name} [${r.family.name}] (${Object.keys(r.verbs).join(", ")}): ${r.summary}`, helpText(r.flags));
  return lines.join("\n");
}

function machineSpec() {
  return {
    command: "web-forge",
    commonFlags: COMMON_FLAGS,
    exitCodes: EXIT_CODES,
    recipes: Object.values(RECIPES).map((r) => ({ name: r.name, family: r.family.name, summary: r.summary, url: r.url, verbs: r.verbs, flags: r.flags })),
  };
}

async function main(argv: string[]): Promise<number> {
  const [cmd, ...rest] = argv;
  if (!cmd || cmd === "--help" || cmd === "-h" || cmd === "help" || cmd === "recipes") {
    console.log(rest.includes("--json") ? JSON.stringify(machineSpec(), null, 2) : usage());
    return 0;
  }
  if (cmd === "serve") {
    const specs = CONNECT_FLAGS.map((s) => (s.name === "port" ? { ...s, default: DEFAULT_PORT } : s));
    const f = parseFlags(rest, specs, process.env);
    await serve(targetFrom(f), Number(f.port));
    return -1; // keep running
  }
  if (cmd === "stop") {
    const f = parseFlags(rest, [{ ...CONNECT_FLAGS.find((s) => s.name === "port")!, default: DEFAULT_PORT }], process.env);
    const r = await fetch(`http://127.0.0.1:${f.port}/quit`).catch(() => null);
    console.log(JSON.stringify({ ok: !!r, stopped: !!r, port: f.port }));
    return r ? 0 : 1;
  }

  const recipe = RECIPES[cmd];
  if (!recipe) throw new UsageError(`unknown recipe "${cmd}" (web-forge recipes lists them)`);
  const [verb, ...flagArgv] = rest;
  if (!verb || verb.startsWith("--")) throw new UsageError(`${cmd}: give a verb (${Object.keys(recipe.verbs).join(", ")})`);
  if (!(verb in recipe.verbs)) throw new UsageError(`${cmd}: unknown verb "${verb}" (${Object.keys(recipe.verbs).join(", ")})`);
  const specs = [...recipe.flags, ...COMMON_FLAGS];
  if (flagArgv.includes("--help")) {
    console.log(`${recipe.name} ${verb}: ${recipe.verbs[verb]}\n${helpText(specs)}`);
    return 0;
  }
  const f: Flags = parseFlags(expandSpec(flagArgv, specs, (p) => readFileSync(p, "utf8")), specs, process.env);
  recipe.validate?.(f); // usage errors before any browser is touched
  const target = targetFrom(f, recipe.family.name);

  const browser = await connect(target, f.port ? Number(f.port) : undefined);
  log(`browser: ${browser.describe}`);
  const d = new Driver(browser, f.screenshots ? String(f.screenshots) : undefined, log);
  try {
    const gate = () => loginGate(d, recipe.family, { who: String(f.account), alert: f.alert as AlertLevel, waitSec: Number(f["reauth-wait"]), log });
    const { code, result } = await recipe.run(verb, f, d, gate);
    console.log(JSON.stringify(result, null, 2));
    return code;
  } catch (e) {
    const reauth = e instanceof ReauthTimeout;
    console.log(JSON.stringify({ ok: false, recipe: recipe.name, account: f.account, error: String((e as Error).message ?? e), reauth }, null, 2));
    return reauth ? 4 : 1;
  } finally {
    await browser.close();
  }
}

if (import.meta.main) {
  try {
    const code = await main(process.argv.slice(2));
    if (code >= 0) process.exit(code);
  } catch (e) {
    if (e instanceof UsageError) {
      console.error(`usage error: ${e.message}\n(run with --help for flags)`);
      console.log(JSON.stringify({ ok: false, usage: e.message }));
      process.exit(2);
    }
    console.error(String((e as Error).stack ?? e));
    console.log(JSON.stringify({ ok: false, error: String((e as Error).message ?? e) }));
    process.exit(1);
  }
}
