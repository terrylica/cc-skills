// Tests of the parts both connection modes and both runtimes share: target selection, the MCP command per mode, the
// recipe spec file, and the DOM-to-vault step. No browser is started.
import { afterAll, describe, expect, test } from "bun:test";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { cdpUrl, mcpCommand, port, profileDir } from "../../lib/forge-chrome.mjs";
import { COMMON_FLAGS, expandSpec, targetFrom } from "../web-forge.ts";
import { argvFromSpec, type FlagSpec, parseFlags, UsageError } from "./args.ts";
import type { Browser, CallResult } from "./mcp.ts";
import { targetKey } from "./mcp.ts";
import { Driver, StepError } from "./page.ts";

describe("targets and connection modes", () => {
  test("extension is the default and is keyed by account, case-insensitively", () => {
    const t = targetFrom({ account: "Admin@Example.com" }, "google-admin");
    expect(t).toEqual({ mode: "extension", account: "Admin@Example.com" });
    expect(targetKey(t)).toBe("extension:admin@example.com");
  });
  test("cdp takes --site, else the recipe family", () => {
    expect(targetFrom({ account: "a@example.com", connect: "cdp" }, "google-admin")).toEqual({ mode: "cdp", site: "google-admin" });
    expect(targetKey(targetFrom({ account: "a@example.com", connect: "cdp", site: "gws-x" }, "google-admin"))).toBe("cdp:gws-x");
  });
  test("cdp with no site and no family is a usage error; --site without cdp is too", () => {
    expect(() => targetFrom({ account: "a@example.com", connect: "cdp" })).toThrow(UsageError);
    expect(() => targetFrom({ account: "a@example.com", site: "x" }, "f")).toThrow(/--site applies to --connect cdp only/);
  });
  test("the MCP command per mode", () => {
    process.env.CHROME_PROFILES_PROFILE_SH = "/fake/chrome-profile.sh";
    try {
      expect(mcpCommand("extension", { account: "a@example.com" })).toEqual(["bash", "/fake/chrome-profile.sh", "playwright-mcp", "a@example.com"]);
    } finally {
      delete process.env.CHROME_PROFILES_PROFILE_SH;
    }
    expect(mcpCommand("cdp", { site: "demo" })).toEqual(["npx", "-y", "@playwright/mcp@latest", "--cdp-endpoint", cdpUrl("demo")]);
    expect(() => mcpCommand("extension", {})).toThrow(/account/);
    expect(() => mcpCommand("cdp", {})).toThrow(/site/);
    expect(() => mcpCommand("nope", {})).toThrow(/unknown connection mode/);
  });
  test("per-site ports are stable, distinct per site, and loopback", () => {
    expect(port("demo")).toBe(port("demo"));
    expect(port("demo")).toBeGreaterThanOrEqual(9250);
    expect(port("demo")).toBeLessThan(9330);
    expect(cdpUrl("demo")).toBe(`http://127.0.0.1:${port("demo")}`);
    expect(profileDir("demo")).toMatch(/\.local\/share\/web-forge\/profile-demo$/);
  });
});

describe("recipe spec files", () => {
  const specs: FlagSpec[] = [
    { name: "match", type: "string", help: "" },
    { name: "dry-run", type: "bool", help: "" },
    { name: "reauth-wait", type: "int", help: "" },
  ];
  test("an object of flags becomes argv for the one parser", () => {
    const argv = argvFromSpec({ $schema: "x", match: "group:t@example.com", "dry-run": true, "reauth-wait": 30 }, specs);
    expect(argv).toEqual(["--match", "group:t@example.com", "--dry-run", "--reauth-wait", "30"]);
    expect(parseFlags(argv, specs)).toEqual({ match: "group:t@example.com", "dry-run": true, "reauth-wait": 30 });
  });
  test("false and null are omitted", () => {
    expect(argvFromSpec({ "dry-run": false, match: null }, specs)).toEqual([]);
  });
  test.each([
    [[1], /one JSON object/],
    [{ nope: 1 }, /unknown flag "nope"/],
    [{ "dry-run": "yes" }, /true or false/],
    [{ match: { a: 1 } }, /string or a number/],
  ])("rejects %j", (spec, rx) => {
    expect(() => argvFromSpec(spec, specs)).toThrow(rx);
  });
  test("--spec is lifted out of argv and the command line wins", () => {
    const files: Record<string, string> = { "s.json": JSON.stringify({ account: "a@example.com", screenshots: "/from/spec" }) };
    const argv = expandSpec(["--screenshots", "/from/cli", "--spec", "s.json"], COMMON_FLAGS, (p) => files[p]!);
    expect(argv).toEqual(["--account", "a@example.com", "--screenshots", "/from/spec", "--screenshots", "/from/cli"]);
    expect(parseFlags(argv, COMMON_FLAGS).screenshots).toBe("/from/cli");
    expect(expandSpec(["--spec=s.json"], COMMON_FLAGS, (p) => files[p]!)).toEqual(["--account", "a@example.com", "--screenshots", "/from/spec"]);
    expect(expandSpec(["--alert", "none"], COMMON_FLAGS, () => "")).toEqual(["--alert", "none"]);
  });
  test("a bad spec file is a usage error", () => {
    expect(() => expandSpec(["--spec", "x.json"], COMMON_FLAGS, () => "{not json")).toThrow(UsageError);
    expect(() => expandSpec(["--spec"], COMMON_FLAGS, () => "{}")).toThrow(/needs a file/);
    expect(() => expandSpec(["--spec", "x.json"], COMMON_FLAGS, () => JSON.stringify({ spec: "loop.json" }))).toThrow(/unknown flag "spec"/);
  });
});

describe("Driver.extractToVault", () => {
  const dir = mkdtempSync(join(tmpdir(), "web-forge-test-"));
  const sink = join(dir, "sink");
  const vault = join(dir, "vault");
  writeFileSync(vault, `#!/bin/bash\nset -euo pipefail\n[ "$1" = set ] && [ "$2" = --stdin ] || exit 9\nprintf '%s %s ' "$3" "$4" > "${sink}"\ncat >> "${sink}"\n`);
  chmodSync(vault, 0o755);
  afterAll(() => rmSync(dir, { recursive: true, force: true }));

  const fake = (reply: CallResult) => {
    const calls: string[] = [];
    const b: Browser = {
      describe: "fake",
      workDir: dir,
      call: async (tool) => {
        calls.push(tool);
        return reply;
      },
      close: async () => {},
    };
    return { b, calls };
  };

  test("the value goes to the vault on stdin; only its length comes back or is logged; no screenshot", async () => {
    process.env.WEB_FORGE_VAULT_BIN = vault;
    const secret = "cfat_" + "x".repeat(48);
    const { b, calls } = fake({ text: `### Result\n${JSON.stringify(JSON.stringify(secret))}\n`, isError: false });
    const logs: string[] = [];
    const d = new Driver(b, join(dir, "shots"), (s) => logs.push(s));
    try {
      expect(await d.extractToVault("read token", "async () => 'x'", null, "proj", "cf.api_token")).toEqual({ vaulted: "proj cf.api_token", length: 53 });
    } finally {
      delete process.env.WEB_FORGE_VAULT_BIN;
    }
    expect(readFileSync(sink, "utf8")).toBe(`proj cf.api_token ${secret}`);
    expect(calls).toEqual(["browser_run_code_unsafe"]);
    expect(logs.join("\n")).not.toContain(secret);
  });
  test("a failed extraction withholds the page's error text", async () => {
    const { b } = fake({ text: "### Error\nError: token cfat_LEAK not clickable\n", isError: true });
    const err = await new Driver(b, undefined, () => {}).extractToVault("read token", "async () => 1", null, "s", "p").catch((e) => e);
    expect(err).toBeInstanceOf(StepError);
    expect(String(err.message)).not.toContain("cfat_LEAK");
  });
  test("an empty or non-string result is refused before the vault is touched", async () => {
    const { b } = fake({ text: `### Result\n${JSON.stringify(JSON.stringify(""))}\n`, isError: false });
    await expect(new Driver(b, undefined, () => {}).extractToVault("read token", "async () => ''", null, "s", "p")).rejects.toThrow(/no string/);
  });
});
