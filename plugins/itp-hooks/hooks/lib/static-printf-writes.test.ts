/**
 * Tests for lib/static-printf-writes.ts: printf output known from the command text alone.
 *
 * Run with: bun test plugins/itp-hooks/hooks/lib/static-printf-writes.test.ts
 */

import { describe, expect, test } from "bun:test";

import { evaluatePrintf, staticPrintfWrites } from "./static-printf-writes.ts";

describe("evaluatePrintf", () => {
  test.each([
    ["a\\nb\\n", [], "a\nb\n"],
    ["%s\\n", ["x", "y", "z"], "x\ny\nz\n"],
    ["%s=%s;", ["k", "v", "k2"], "k=v;k2=;"],
    ["100%%\\n", [], "100%\n"],
    ["%b", ["tab\\there"], "tab\there"],
    ["no conversions", ["ignored"], "no conversions"],
  ] as const)("printf %j %j", (format, args, expected) => {
    expect(evaluatePrintf(format, args)).toBe(expected);
  });

  test.each([["%d", ["3"]], ["%-10s", ["x"]], ["\\x41", []], ["\\101", []]] as const)(
    "unmodelled %j → null",
    (format, args) => {
      expect(evaluatePrintf(format, args)).toBeNull();
    },
  );
});

describe("staticPrintfWrites", () => {
  test("a literal printf redirected to a file", () => {
    expect(staticPrintfWrites("printf '%s\\n' 'one' 'two' > /tmp/b.md && gh issue comment 1 --body-file /tmp/b.md")).toEqual([
      { path: "/tmp/b.md", text: "one\ntwo\n" },
    ]);
  });

  test("the >path spelling", () => {
    expect(staticPrintfWrites("printf 'x\\n' >/tmp/b.md")).toEqual([{ path: "/tmp/b.md", text: "x\n" }]);
  });

  test.each([
    [`printf '%s\\n' "$BODY" > /tmp/b.md`],
    ["printf '%s\\n' $(cat notes) > /tmp/b.md"],
    ["printf 'x' >> /tmp/b.md"],
    ["printf -v var 'x' > /tmp/b.md"],
    ["printf 'x'"],
    ["echo printf 'x' > /tmp/b.md"],
  ])("not statically known: %s", (command) => {
    expect(staticPrintfWrites(command)).toEqual([]);
  });

  test("single-quoted dollar signs are literal", () => {
    expect(staticPrintfWrites("printf '%s\\n' 'costs $5' > /tmp/b.md")).toEqual([{ path: "/tmp/b.md", text: "costs $5\n" }]);
  });
});
