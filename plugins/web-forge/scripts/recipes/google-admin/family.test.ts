import { describe, expect, test } from "bun:test";
import { classifyPage, GOOGLE_ADMIN } from "./family.ts";

describe("classifyPage", () => {
  test.each([
    ["https://admin.google.com/ac/apps/gmail/defaultrouting", "Default routing", "ready"],
    ["https://accounts.google.com/v3/signin/challenge/pwd", "Verify it's you\nTo continue, first verify it's you", "reauth"],
    ["https://accounts.google.com/v3/signin/challenge/pwd", "Enter your password", "reauth"],
    ["https://accounts.google.com/v3/signin/identifier", "Sign in\nUse your Google Account", "signin"],
    ["https://example.com/", "", "other"],
    ["not a url", "", "other"],
  ])("%s", (url, text, want) => {
    expect(classifyPage(url, text)).toBe(want);
  });
});

test("the family carries its classifier", () => {
  expect(GOOGLE_ADMIN.classify("https://admin.google.com/ac/home", "")).toBe("ready");
});
