// Unit tests for the operator alert in gate.ts. No test here sends a real Pushover message: the core is always a
// stub script passed through WEB_FORGE_PUSHOVER_CORE, which records what it was given and behaves as told.
//
// Regression (2026-10-19): `--alert emergency` printed "emergency alert failed (exit null)" for a page that had
// reached the phone. The core polled the receipt for up to --expire (600 s) under a 60 s spawn timeout, so the
// timeout's SIGTERM killed every unacknowledged page's poll and status came back null.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { alertOperator, describeChildOutcome, sendEmergency } from "./gate.ts";

let dir = "";
let stub = "";
let record = "";
const saved: Record<string, string | undefined> = {};

// The stub behaves like the real core under each failure mode: STUB_MODE=ok|fail|hang-unless-no-wait.
const STUB = `
import { writeFileSync } from "node:fs";
const argv = process.argv.slice(2);
writeFileSync(process.env.STUB_RECORD!, JSON.stringify({ argv, proxy: process.env.HTTPS_PROXY ?? null, proxyLower: process.env.http_proxy ?? null }));
const mode = process.env.STUB_MODE;
if (mode === "fail") { console.error("po: send failed: {\\"token\\":\\"invalid\\"}"); process.exit(3); }
if (mode === "hang-unless-no-wait" && !argv.includes("--no-wait")) await new Promise(() => setInterval(() => {}, 1000));
console.log(JSON.stringify({ status: 1, request: "r", receipt: "x" }));
`;

beforeAll(() => {
  dir = mkdtempSync(join(tmpdir(), "web-forge-gate-"));
  stub = join(dir, "pushover_core_stub.ts");
  record = join(dir, "record.json");
  writeFileSync(stub, STUB);
  for (const k of ["STUB_RECORD", "STUB_MODE", "HTTPS_PROXY", "http_proxy", "WEB_FORGE_NOTIFY", "WEB_FORGE_PUSHOVER_CORE"]) saved[k] = process.env[k];
  process.env.STUB_RECORD = record;
  process.env.WEB_FORGE_NOTIFY = "/usr/bin/true";
  process.env.WEB_FORGE_PUSHOVER_CORE = stub;
});

afterAll(() => {
  for (const [k, v] of Object.entries(saved)) {
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
  rmSync(dir, { recursive: true, force: true });
});

const run = (mode: string, timeoutMs = 10_000): string[] => {
  process.env.STUB_MODE = mode;
  const lines: string[] = [];
  alertOperator("emergency", "Console needs you", "verify it's you", (s) => lines.push(s), { emergencyTimeoutMs: timeoutMs });
  return lines;
};

describe("emergency alert", () => {
  test("REGRESSION: the core is told not to wait for the ack, so a delivered page is reported as sent", () => {
    // Under the old call this stub hangs like an unacknowledged receipt poll and the timeout killed it.
    const lines = run("hang-unless-no-wait", 5_000);
    expect(JSON.parse(readFileSync(record, "utf8")).argv).toContain("--no-wait");
    expect(lines.at(-1)).toStartWith("emergency alert sent");
    expect(lines.join("\n")).not.toContain("failed");
  });

  test("HTTP(S) proxy variables are removed from the child's environment", () => {
    process.env.HTTPS_PROXY = "http://127.0.0.1:9";
    process.env.http_proxy = "http://127.0.0.1:9";
    try {
      run("ok");
    } finally {
      delete process.env.HTTPS_PROXY;
      delete process.env.http_proxy;
    }
    const seen = JSON.parse(readFileSync(record, "utf8"));
    expect(seen.proxy).toBeNull();
    expect(seen.proxyLower).toBeNull();
  });

  test("a non-zero exit is reported with its code and the core's last error line", () => {
    const last = run("fail").at(-1)!;
    expect(last).toContain("emergency alert failed (exit 3: po: send failed:");
    expect(last).not.toContain("null");
  });

  test("a child killed by the timeout says so, never 'exit null'", () => {
    const sleeper = join(dir, "sleeper.ts");
    writeFileSync(sleeper, "await new Promise(() => setInterval(() => {}, 1000));\n");
    const killed = sendEmergency(sleeper, "t", "m", 300);
    expect(killed).toBe("timed out after 0.3s and was killed (SIGTERM)");
  });

  test("a core that cannot be found is reported as unavailable, not as a failure", () => {
    process.env.WEB_FORGE_PUSHOVER_CORE = join(dir, "missing.ts");
    try {
      expect(run("ok").at(-1)).toBe("emergency alert unavailable (pushover-commander not installed): local notice only");
    } finally {
      process.env.WEB_FORGE_PUSHOVER_CORE = stub;
    }
  });
});

describe("describeChildOutcome", () => {
  test("exit code, signal, spawn error and timeout each read differently", () => {
    expect(describeChildOutcome({ status: 2, signal: null }, 1000)).toBe("exit 2");
    expect(describeChildOutcome({ status: null, signal: "SIGKILL" }, 1000)).toBe("killed by SIGKILL");
    const enoent = Object.assign(new Error("spawnSync bun ENOENT"), { code: "ENOENT" });
    expect(describeChildOutcome({ status: null, signal: null, error: enoent }, 1000)).toBe("could not run: ENOENT spawnSync bun ENOENT");
    const timedOut = Object.assign(new Error("spawnSync bun ETIMEDOUT"), { code: "ETIMEDOUT" });
    expect(describeChildOutcome({ status: null, signal: "SIGTERM", error: timedOut }, 60_000)).toBe("timed out after 60s and was killed (SIGTERM)");
  });
});
