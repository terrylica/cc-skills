import { describe, expect, test } from "bun:test";
import { rmSync } from "node:fs";
import { dirname } from "node:path";
import { DEFAULT_TY_EDIT_GATE_DIRECTORY } from "./ty-edit-gate.ts";
import { perUserTempPath, perUserTempSuffix } from "./per-user-temp-path.ts";
import {
  releaseMachineWideConcurrencySlotSwallowingAllFilesystemErrors,
  tryAcquireMachineWideConcurrencySlotForGuardedSubprocess,
} from "./subprocess-rss-watchdog-and-slot-guard-iter124.ts";

// On Linux os.tmpdir() is the shared /tmp: a directory one account creates (umask 0755) is not writable by the next,
// so every shared temp directory a hook writes into carries the uid.
describe("per-user temp paths", () => {
  const uid = typeof process.getuid === "function" ? String(process.getuid()) : process.env.USER || "user";

  test("the suffix is the uid", () => {
    expect(perUserTempSuffix()).toBe(uid);
    expect(perUserTempPath("/tmp/.x")).toBe(`/tmp/.x-${uid}`);
  });

  test("the ty edit gate defaults to a per-user directory", () => {
    expect(DEFAULT_TY_EDIT_GATE_DIRECTORY).toBe(`/tmp/.claude-ty-edits-${uid}`);
  });

  test("concurrency slots live in a per-user directory", () => {
    const tool = `per-user-path-test-${process.pid}`;
    const slot = tryAcquireMachineWideConcurrencySlotForGuardedSubprocess(tool, 1);
    try {
      expect(slot).not.toBeNull();
      expect(slot?.slotFilePath).toContain(`/.claude-subprocess-concurrency-slots-${tool}-${uid}/`);
    } finally {
      releaseMachineWideConcurrencySlotSwallowingAllFilesystemErrors(slot);
      if (slot) rmSync(dirname(slot.slotFilePath), { recursive: true, force: true });
    }
  });
});
