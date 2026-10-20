// reauth.ts — the Admin console's "verify it's you" gate.
//
// Google asks an administrator for a FRESH password on accounts.google.com before admin pages, every so often.
// Policy (baked in, not optional): the harness DETECTS this, NEVER types a password or any credential, alerts
// the operator, and polls the tab WITHOUT reloading it (a reload would discard what the operator is typing)
// until the admin page is back or the wait runs out.
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { Driver } from "./page.ts";

export type PageKind = "admin" | "reauth" | "signin" | "other";

/** Pure: classify a page by its URL and visible text. */
export function classifyPage(url: string, text: string): PageKind {
  let host = "";
  try {
    host = new URL(url).hostname;
  } catch {
    return "other";
  }
  if (host === "accounts.google.com") {
    if (/verify it'?s you|verify it’s you|enter your password|confirm it'?s you|to continue, first verify/i.test(text)) return "reauth";
    return "signin";
  }
  if (host === "admin.google.com") return "admin";
  return "other";
}

export type AlertLevel = "none" | "local" | "emergency";

export function alertOperator(level: AlertLevel, title: string, message: string, log: (s: string) => void): void {
  log(`ALERT ${title}: ${message}`);
  if (level === "none") return;
  const notify = process.env.GWS_ADMIN_NOTIFY ?? join(homedir(), ".claude", "tools", "notify");
  if (existsSync(notify)) spawnSync(notify, [title, message], { stdio: "ignore", timeout: 15_000 });
  else process.stderr.write("\x07");
  if (level !== "emergency") return;
  // Pushover Emergency (priority 2, repeats until acknowledged) through the pushover-commander plugin.
  // Proxies are stripped: the fleet's HTTPS proxy does not pass api.pushover.net.
  let core = process.env.GWS_ADMIN_PUSHOVER_CORE ?? "";
  if (!core) {
    try {
      core = join(execFileSync("cc-plugin-root", ["pushover-commander"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim(), "skills", "_lib", "pushover_core.ts");
    } catch {
      core = "";
    }
  }
  if (!core || !existsSync(core)) {
    log("emergency alert unavailable (pushover-commander not installed): local notice only");
    return;
  }
  const env = { ...process.env };
  delete env.HTTPS_PROXY;
  delete env.HTTP_PROXY;
  delete env.https_proxy;
  delete env.http_proxy;
  const r = spawnSync("bun", [core, "emergency", "--title", title, "--message", message, "--retry", "60", "--expire", "600"], { env, stdio: "ignore", timeout: 60_000 });
  if (r.status !== 0) log(`emergency alert failed (exit ${r.status}): local notice was still sent`);
}

const READ_STATE = `async (page, args, H) => H.state()`;

/**
 * Make sure the tab shows an admin page. If Google wants re-authentication, alert once and poll without
 * reloading. Returns the final page kind; throws on timeout.
 */
export async function adminGate(d: Driver, opts: { account: string; alert: AlertLevel; waitSec: number; log: (s: string) => void }): Promise<void> {
  let s = await d.step<{ url: string; text: string }>("read page state", READ_STATE, null, { shoot: false });
  let kind = classifyPage(s.url, s.text);
  if (kind === "admin") return;
  if (kind === "other") throw new Error(`expected admin.google.com, the tab is on ${new URL(s.url).hostname}`);
  await d.shoot(`reauth-${kind}`);
  alertOperator(
    opts.alert,
    "Admin console needs you",
    `${opts.account}: Google asks to ${kind === "reauth" ? "verify it's you (password)" : "sign in"} before the Admin console. Complete it in the Chrome tab that is now in front. The harness never types a password; it waits ${opts.waitSec}s.`,
    opts.log,
  );
  const deadline = Date.now() + opts.waitSec * 1000;
  while (Date.now() < deadline) {
    await Bun.sleep(5000);
    s = await d.step("poll page state", READ_STATE, null, { shoot: false, quiet: true });
    kind = classifyPage(s.url, s.text);
    if (kind === "admin") {
      opts.log("re-authentication passed; continuing");
      return;
    }
  }
  throw new ReauthTimeout(`still on ${kind} after ${opts.waitSec}s: pass the check (in this tab, or another tab of the same profile) and re-run; the command is idempotent`);
}

export class ReauthTimeout extends Error {}
