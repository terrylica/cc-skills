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

import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { PROFILES_RELATIVE_PATH } from "./profile-hint.ts";

describe("the file the message names is the file tg-cli reads", () => {
  test("a profile file at PROFILES_RELATIVE_PATH is what lists the available profiles", () => {
    const home = mkdtempSync(join(tmpdir(), "tlg-profiles-"));
    try {
      mkdirSync(join(home, dirname(PROFILES_RELATIVE_PATH)), { recursive: true });
      // The default names a profile with no item, so the CLI stops at the profile lookup and never calls 1Password.
      writeFileSync(join(home, PROFILES_RELATIVE_PATH), JSON.stringify({ default: "absent", profiles: { probe: "item-id" } }));
      const env: Record<string, string> = { ...(process.env as Record<string, string>), HOME: home };
      for (const k of ["TELEGRAM_API_ID", "TELEGRAM_API_HASH", "TELETHON_OP_UUID"]) delete env[k];
      const r = spawnSync(process.execPath, ["--no-install", join(import.meta.dir, "tg-cli.ts"), "whoami"], { env, encoding: "utf8", timeout: 30_000 });
      expect(r.stdout + r.stderr).toContain("unknown profile 'absent'. Available: probe.");
    } finally {
      rmSync(home, { recursive: true, force: true });
    }
  });
});
