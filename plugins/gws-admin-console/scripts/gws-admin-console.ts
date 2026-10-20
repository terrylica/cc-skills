#!/usr/bin/env bun
// gws-admin-console — drive console-only Google Admin settings through a signed-in Chrome profile.
//
//   gws-admin-console recipes [--json]                     list recipes, verbs and flags (machine-readable with --json)
//   gws-admin-console <recipe> <verb> [flags]              run a recipe; JSON result on stdout, progress on stderr
//   gws-admin-console serve --account <email> [--port n]   keep one browser session open for successive runs
//   gws-admin-console stop [--port n]                      stop a bridge started by serve
//
// Exit codes: 0 ok · 1 failed or read-back mismatch · 2 usage · 3 rule exists but differs (no --update)
//             4 re-authentication not completed in time
import { type FlagSpec, type Flags, helpText, parseFlags, UsageError } from "./lib/args.ts";
import { connect, serve } from "./lib/mcp.ts";
import { Driver } from "./lib/page.ts";
import { adminGate, type AlertLevel, ReauthTimeout } from "./lib/reauth.ts";
import { RECIPES } from "./recipes/index.ts";

const DEFAULT_PORT = 47811;
const log = (s: string) => console.error(s);

/** Flags every recipe accepts. */
export const COMMON_FLAGS: FlagSpec[] = [
  { name: "port", type: "int", env: "GWS_ADMIN_BRIDGE_PORT", help: "Reuse the bridge on 127.0.0.1:<port> when it serves --account; otherwise a one-run session is opened" },
  { name: "screenshots", type: "string", help: "Save a PNG of the browser after every step into this directory (failures are always captured, by default under ~/.local/state/gws-admin-console/failures)" },
  { name: "alert", type: "string", choices: ["none", "local", "emergency"], default: "local", help: "How to call the operator when Google asks to verify it's you: local notice, or a Pushover Emergency as well" },
  { name: "reauth-wait", type: "int", default: 600, help: "Seconds to wait for the operator to pass re-authentication (the tab is polled, never reloaded)" },
];

function usage(): string {
  const lines = [
    "gws-admin-console — drive console-only Google Admin settings through a signed-in Chrome profile",
    "",
    "usage:",
    "  gws-admin-console recipes [--json]",
    "  gws-admin-console <recipe> <verb> [flags]",
    "  gws-admin-console serve --account <email> [--port <n>]",
    "  gws-admin-console stop [--port <n>]",
    "",
    "exit: 0 ok · 1 failed or read-back mismatch · 2 usage · 3 exists but differs (no --update) · 4 re-auth not completed",
    "",
    "flags for every recipe:",
    helpText(COMMON_FLAGS),
  ];
  for (const r of Object.values(RECIPES)) lines.push("", `recipe ${r.name} (${Object.keys(r.verbs).join(", ")}): ${r.summary}`, helpText(r.flags));
  return lines.join("\n");
}

function machineSpec() {
  return {
    command: "gws-admin-console",
    commonFlags: COMMON_FLAGS,
    exitCodes: { 0: "ok", 1: "failed or read-back mismatch", 2: "usage", 3: "exists but differs (no --update)", 4: "re-authentication not completed" },
    recipes: Object.values(RECIPES).map((r) => ({ name: r.name, summary: r.summary, url: r.url, verbs: r.verbs, flags: r.flags })),
  };
}

async function main(argv: string[]): Promise<number> {
  const [cmd, ...rest] = argv;
  if (!cmd || cmd === "--help" || cmd === "-h" || cmd === "help") {
    if (rest.includes("--json")) console.log(JSON.stringify(machineSpec(), null, 2));
    else console.log(usage());
    return 0;
  }
  if (cmd === "recipes") {
    console.log(rest.includes("--json") ? JSON.stringify(machineSpec(), null, 2) : usage());
    return 0;
  }
  if (cmd === "serve") {
    const f = parseFlags(rest, [{ name: "account", type: "string", required: true, help: "" }, { ...COMMON_FLAGS[0]!, default: DEFAULT_PORT }], process.env);
    await serve(String(f.account), Number(f.port));
    return -1; // keep running
  }
  if (cmd === "stop") {
    const f = parseFlags(rest, [{ ...COMMON_FLAGS[0]!, default: DEFAULT_PORT }], process.env);
    const r = await fetch(`http://127.0.0.1:${f.port}/quit`).catch(() => null);
    console.log(JSON.stringify({ ok: !!r, stopped: !!r, port: f.port }));
    return r ? 0 : 1;
  }

  const recipe = RECIPES[cmd];
  if (!recipe) throw new UsageError(`unknown recipe "${cmd}" (gws-admin-console recipes lists them)`);
  const [verb, ...flagArgv] = rest;
  if (!verb || verb.startsWith("--")) throw new UsageError(`${cmd}: give a verb (${Object.keys(recipe.verbs).join(", ")})`);
  if (!(verb in recipe.verbs)) throw new UsageError(`${cmd}: unknown verb "${verb}" (${Object.keys(recipe.verbs).join(", ")})`);
  if (flagArgv.includes("--help")) {
    console.log(`${recipe.name} ${verb}: ${recipe.verbs[verb]}\n${helpText([...recipe.flags, ...COMMON_FLAGS])}`);
    return 0;
  }
  const f: Flags = parseFlags(flagArgv, [...recipe.flags, ...COMMON_FLAGS], process.env);
  recipe.validate?.(f); // usage errors before any browser is touched

  const browser = await connect(String(f.account), f.port ? Number(f.port) : undefined);
  log(`browser: ${browser.describe}`);
  const d = new Driver(browser, f.screenshots ? String(f.screenshots) : undefined, log);
  try {
    const gate = () => adminGate(d, { account: String(f.account), alert: f.alert as AlertLevel, waitSec: Number(f["reauth-wait"]), log });
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
