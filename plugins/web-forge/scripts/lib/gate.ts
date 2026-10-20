// gate.ts — the login / re-authentication gate every recipe passes before it touches a console.
//
// Consoles periodically send a signed-in user back to a sign-in or "verify it's you" page. Policy (baked in, not
// optional): the harness DETECTS this through the recipe family's classifier, NEVER types a password or any
// credential, alerts the operator, and polls the tab WITHOUT reloading it (a reload would discard what the operator
// is typing) until the console is back or the wait runs out.
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { Driver } from "./page.ts";

/** ready: the console itself · reauth: a fresh-password prompt · signin: any other sign-in page · other: elsewhere. */
export type PageKind = "ready" | "reauth" | "signin" | "other";

/** A recipe family: one vendor console, and how to tell its pages apart. */
export interface Family {
  name: string;
  /** Human name of the console, used in alerts. */
  console: string;
  /** Pure: classify a page by its URL and visible text. */
  classify(url: string, text: string): PageKind;
}

export type AlertLevel = "none" | "local" | "emergency";

/** How long the emergency send may take. The core returns once Pushover accepted the message (`--no-wait`). */
export const EMERGENCY_SEND_TIMEOUT_MS = 60_000;

/** The parts of a spawnSync result that say how a child ended. */
export interface ChildOutcome {
  status: number | null;
  signal: NodeJS.Signals | null;
  error?: Error | undefined;
}

/**
 * Say how a child process ended, in words. Never "exit null": a null status means the child was killed by a
 * signal (a timeout kill is SIGTERM) or never started (the spawn error says why), and the message must say which.
 */
export function describeChildOutcome(r: ChildOutcome, timeoutMs: number): string {
  const code = (r.error as NodeJS.ErrnoException | undefined)?.code;
  if (code === "ETIMEDOUT") return `timed out after ${timeoutMs / 1000}s and was killed (${r.signal ?? "SIGTERM"})`;
  if (r.error) return `could not run: ${code ? `${code} ` : ""}${r.error.message}`;
  if (r.signal) return `killed by ${r.signal}`;
  return `exit ${r.status}`;
}

/**
 * Send the Pushover Emergency through the pushover-commander core and return null on success or a description
 * of the failure.
 *
 * `--no-wait` is essential. Without it the core polls the receipt until the operator acknowledges or `--expire`
 * (600 s) runs out, while this call has a 60 s timeout: every unacknowledged page was delivered, then the poll was
 * killed by SIGTERM, status came back null, and the harness reported "emergency alert failed (exit null)" for an
 * alert that had reached the phone. Waiting for the ack is also wrong here on its own terms: spawnSync blocks, and
 * the gate must be polling the tab while the operator verifies.
 *
 * The child runs under this process's own bun (`process.execPath`), so a PATH without bun cannot break it.
 */
export function sendEmergency(core: string, title: string, message: string, timeoutMs = EMERGENCY_SEND_TIMEOUT_MS): string | null {
  // Proxies are stripped: the fleet's HTTPS proxy does not pass api.pushover.net.
  const env = { ...process.env };
  delete env.HTTPS_PROXY;
  delete env.HTTP_PROXY;
  delete env.https_proxy;
  delete env.http_proxy;
  const r = spawnSync(process.execPath, [core, "emergency", "--title", title, "--message", message, "--retry", "60", "--expire", "600", "--no-wait"], {
    env,
    stdio: ["ignore", "ignore", "pipe"],
    encoding: "utf8",
    timeout: timeoutMs,
  });
  if (r.status === 0 && !r.error) return null;
  const detail = (r.stderr ?? "").trim().split("\n").filter(Boolean).at(-1);
  return `${describeChildOutcome(r, timeoutMs)}${detail ? `: ${detail.slice(0, 300)}` : ""}`;
}

export function alertOperator(level: AlertLevel, title: string, message: string, log: (s: string) => void, opts: { emergencyTimeoutMs?: number } = {}): void {
  log(`ALERT ${title}: ${message}`);
  if (level === "none") return;
  const notify = process.env.WEB_FORGE_NOTIFY ?? join(homedir(), ".claude", "tools", "notify");
  if (existsSync(notify)) spawnSync(notify, [title, message], { stdio: "ignore", timeout: 15_000 });
  else process.stderr.write("\x07");
  if (level !== "emergency") return;
  // Pushover Emergency (priority 2, repeats until acknowledged) through the pushover-commander plugin.
  let core = process.env.WEB_FORGE_PUSHOVER_CORE ?? "";
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
  const failure = sendEmergency(core, title, message, opts.emergencyTimeoutMs);
  log(failure ? `emergency alert failed (${failure}): local notice was still sent` : "emergency alert sent (Pushover accepted it; it repeats until acknowledged)");
}

const READ_STATE = `async (page, args, H) => H.state()`;

/**
 * Make sure the tab shows the family's console. If it asks for sign-in or re-authentication, alert once and poll
 * without reloading. Throws ReauthTimeout when the wait runs out.
 */
export async function loginGate(d: Driver, family: Family, opts: { who: string; alert: AlertLevel; waitSec: number; log: (s: string) => void }): Promise<void> {
  let s = await d.step<{ url: string; text: string }>("read page state", READ_STATE, null, { shoot: false });
  let kind = family.classify(s.url, s.text);
  if (kind === "ready") return;
  if (kind === "other") throw new Error(`expected the ${family.console}, the tab is on ${new URL(s.url).hostname}`);
  await d.shoot(`reauth-${kind}`);
  alertOperator(
    opts.alert,
    `${family.console} needs you`,
    `${opts.who}: ${kind === "reauth" ? "asked to verify it's you (password)" : "asked to sign in"} before the ${family.console}. Complete it in the Chrome tab that is now in front. The harness never types a password; it waits ${opts.waitSec}s.`,
    opts.log,
  );
  const deadline = Date.now() + opts.waitSec * 1000;
  while (Date.now() < deadline) {
    await Bun.sleep(5000);
    s = await d.step("poll page state", READ_STATE, null, { shoot: false, quiet: true });
    kind = family.classify(s.url, s.text);
    if (kind === "ready") {
      opts.log("sign-in passed; continuing");
      return;
    }
  }
  throw new ReauthTimeout(`still on ${kind} after ${opts.waitSec}s: pass the check (in this tab, or another tab of the same profile) and re-run; the command is idempotent`);
}

export class ReauthTimeout extends Error {}
