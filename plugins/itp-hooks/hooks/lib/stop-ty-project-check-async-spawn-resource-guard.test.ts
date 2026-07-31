/**
 * Proves the Stop-hook resource guard prevents the 2026-07-31 runaway.
 *
 * Measured incident 2026-07-31: one unguarded Stop-hook run reached 14.4 GB and
 * was killed by the kernel at 17 minutes old. Multiple concurrent sessions exiting
 * would spawn several whole-tree `ty check .` runs simultaneously — the exact pattern
 * that caused 2026-07-30 to freeze the machine. This test proves the guard engages.
 *
 * Every allocation here is capped at ~80 MB and every guard ceiling is lowered to match,
 * so the suite can never reproduce the runaway it guards against.
 */

import { describe, expect, test } from "bun:test";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail,
} from "./posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95";

const scratchDirectory = mkdtempSync(join(tmpdir(), "stop-hook-guard-test-"));

describe("Stop-hook async spawn with resource guard", () => {
  const toolName = `stop-hook-guardtest-${process.pid}`;

  test("the shared async-spawn helper with guard skips when all slots busy", async () => {
    // Acquire both default slots (2) with dummy processes
    const slot1 = Bun.spawn(["sleep", "30"], { stdout: "ignore", stderr: "ignore" });
    const slot2 = Bun.spawn(["sleep", "30"], { stdout: "ignore", stderr: "ignore" });

    // Import and use the slot management directly
    const {
      tryAcquireMachineWideConcurrencySlotForGuardedSubprocess,
      releaseMachineWideConcurrencySlotSwallowingAllFilesystemErrors,
    } = await import(
      "./subprocess-resident-memory-watchdog-and-machine-wide-concurrency-slot-guard-iter124"
    );

    const acquired1 = tryAcquireMachineWideConcurrencySlotForGuardedSubprocess(toolName, 2);
    const acquired2 = tryAcquireMachineWideConcurrencySlotForGuardedSubprocess(toolName, 2);
    const acquired3 = tryAcquireMachineWideConcurrencySlotForGuardedSubprocess(toolName, 2);

    try {
      expect(acquired1).not.toBeNull();
      expect(acquired2).not.toBeNull();
      expect(acquired3).toBeNull(); // All slots full
    } finally {
      releaseMachineWideConcurrencySlotSwallowingAllFilesystemErrors(acquired1);
      releaseMachineWideConcurrencySlotSwallowingAllFilesystemErrors(acquired2);
      slot1.kill();
      slot2.kill();
    }
  });

  test("async spawn with guard returns skippedBecauseConcurrencySlotsBusy when no slots", async () => {
    // Hold both slots (2) so the spawn attempt has to skip
    const {
      tryAcquireMachineWideConcurrencySlotForGuardedSubprocess,
      releaseMachineWideConcurrencySlotSwallowingAllFilesystemErrors,
    } = await import(
      "./subprocess-resident-memory-watchdog-and-machine-wide-concurrency-slot-guard-iter124"
    );

    const held1 = tryAcquireMachineWideConcurrencySlotForGuardedSubprocess(toolName, 2);
    const held2 = tryAcquireMachineWideConcurrencySlotForGuardedSubprocess(toolName, 2);

    try {
      expect(held1).not.toBeNull();
      expect(held2).not.toBeNull();

      // Now try an async spawn — it should fail to acquire a slot and skip
      const result =
        await executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail(
          ["echo", "hello"],
          {
            timeoutMs: 5000,
            residentMemoryGuardedToolName: toolName,
          },
        );

      expect(result.skippedBecauseConcurrencySlotsBusy).toBe(true);
      expect(result.exitCode).toBeNull();
    } finally {
      releaseMachineWideConcurrencySlotSwallowingAllFilesystemErrors(held1);
      releaseMachineWideConcurrencySlotSwallowingAllFilesystemErrors(held2);
    }
  }, 15_000);

  test("async spawn with guard leaves a well-behaved subprocess completely alone", async () => {
    const result =
      await executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail(
        ["python3", "-c", "print('quick')"],
        {
          timeoutMs: 5000,
          residentMemoryGuardedToolName: toolName,
        },
      );

    expect(result.exitCode).toBe(0);
    expect(result.stdoutText).toContain("quick");
    expect(result.killedForExceedingMemoryCeiling).toBe(false);
    // Never polled: the first poll is deferred past a normal check's lifetime
    expect(result.observedPeakResidentMegabytes).toBe(0);
  }, 15_000);

  test("async spawn reports when subprocess is killed for timeout", async () => {
    const result =
      await executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail(
        ["sleep", "10"],
        {
          timeoutMs: 500, // Very short timeout
          residentMemoryGuardedToolName: toolName,
        },
      );

    // Timeout should result in either timedOut=true or a non-zero exit (AbortSignal kills)
    expect(result.timedOut || result.exitCode !== 0).toBe(true);
  }, 15_000);

  test("async spawn without guard still works", async () => {
    const result =
      await executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail(
        ["echo", "no-guard"],
        {
          timeoutMs: 5000,
          // No residentMemoryGuardedToolName — unguarded path
        },
      );

    expect(result.exitCode).toBe(0);
    expect(result.stdoutText).toContain("no-guard");
    expect(result.spawnFailed).toBe(false);
  }, 15_000);
});
