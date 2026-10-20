import { describe, expect, test } from "bun:test";
import { parseFlags, UsageError, type FlagSpec } from "./args.ts";
import { buildStepCode, parseRunCodeResult, PRELUDE } from "./page.ts";
import { classifyPage } from "./reauth.ts";

describe("parseFlags", () => {
  const specs: FlagSpec[] = [
    { name: "account", type: "string", required: true, help: "" },
    { name: "port", type: "int", env: "PORT_ENV", help: "" },
    { name: "scope", type: "string", choices: ["a", "b"], default: "a", help: "" },
    { name: "dry-run", type: "bool", help: "" },
  ];
  test("values, inline values, booleans, defaults, env", () => {
    expect(parseFlags(["--account", "x@example.com", "--dry-run"], specs, { PORT_ENV: "9" })).toEqual({ account: "x@example.com", "dry-run": true, port: 9, scope: "a" });
    expect(parseFlags(["--account=x@example.com", "--port=7", "--scope", "b"], specs)).toEqual({ account: "x@example.com", port: 7, scope: "b" });
  });
  test.each([
    [["--port", "1"], /--account is required/],
    [["--account"], /needs a value/],
    [["--account", "--dry-run"], /needs a value/],
    [["--account", "x", "--nope"], /unknown flag/],
    [["--account", "x", "--scope", "c"], /must be one of/],
    [["--account", "x", "--port", "1.5"], /whole number/],
    [["--account", "x", "--dry-run=1"], /takes no value/],
    [["stray"], /unexpected argument/],
  ])("rejects %j", (argv, rx) => {
    expect(() => parseFlags(argv, specs)).toThrow(UsageError);
    expect(() => parseFlags(argv, specs)).toThrow(rx);
  });
});

describe("parseRunCodeResult", () => {
  test("double-encoded JSON result", () => {
    const text = `### Result\n${JSON.stringify(JSON.stringify({ a: 1, b: ["x"] }))}\n### Ran Playwright code\n\`\`\`js\n...\n\`\`\``;
    expect(parseRunCodeResult(text)).toEqual({ ok: true, value: { a: 1, b: ["x"] } });
  });
  test("plain string result", () => {
    expect(parseRunCodeResult(`### Result\n"picked"\n`)).toEqual({ ok: true, value: "picked" });
  });
  test("error block", () => {
    const r = parseRunCodeResult("### Error\nError: checkbox count = 0\n### Ran Playwright code\n", true);
    expect(r.ok).toBe(false);
    expect(r.error).toBe("Error: checkbox count = 0");
  });
  test("unrecognised output is an error, never a silent success", () => {
    expect(parseRunCodeResult("something else").ok).toBe(false);
  });
});

describe("buildStepCode", () => {
  test("arguments travel as a JSON literal and the result is stringified", () => {
    const tricky = "it's \"quoted\"\n`tick` $" + "{x} </script>";
    const code = buildStepCode("async (page, args, H) => args.v", { v: tricky });
    expect(code).toContain("const ARGS = " + JSON.stringify({ v: tricky }) + ";");
    expect(code).toContain("JSON.stringify(r === undefined ? null : r)");
    expect(code).toContain("await page.bringToFront()");
  });
  test("the prelude is syntactically valid JavaScript", () => {
    // biome-ignore lint/security/noGlobalEval: compiling (not running) our own constant
    expect(() => new Function(`return (${PRELUDE});`)).not.toThrow();
  });
});

describe("classifyPage", () => {
  test.each([
    ["https://admin.google.com/ac/apps/gmail/defaultrouting", "Default routing", "admin"],
    ["https://accounts.google.com/v3/signin/challenge/pwd", "Verify it's you\nTo continue, first verify it's you", "reauth"],
    ["https://accounts.google.com/v3/signin/challenge/pwd", "Enter your password", "reauth"],
    ["https://accounts.google.com/v3/signin/identifier", "Sign in\nUse your Google Account", "signin"],
    ["https://example.com/", "", "other"],
    ["not a url", "", "other"],
  ])("%s", (url, text, want) => {
    expect(classifyPage(url, text)).toBe(want);
  });
});
