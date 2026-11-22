import { describe, expect, test } from "bun:test";
import { PROFILES_FILE, unknownProfileMessage } from "./profile-hint.ts";

describe("unknownProfileMessage", () => {
  test("a fresh user with no profile file is told where it goes and how to skip it", () => {
    const m = unknownProfileMessage("default", []);
    expect(m).toContain("unknown profile 'default'");
    expect(m).toContain("No profiles are configured");
    expect(m).toContain(PROFILES_FILE);
    expect(m).toContain("TELETHON_OP_UUID");
    expect(m).toContain("TELEGRAM_API_ID");
    expect(m).toContain("TELEGRAM_API_HASH");
    expect(m).not.toContain("Available: .");
  });

  test("known profiles are still listed", () => {
    expect(unknownProfileMessage("x", ["a", "b"])).toContain("Available: a, b.");
  });
});
