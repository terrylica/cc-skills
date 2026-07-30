/**
 * Proves each layer of the subprocess resource guard actually fires.
 *
 * Every allocation here is capped at ~120 MB and every guard ceiling is lowered to match,
 * so the suite can never reproduce the 2026-07-30 memory exhaustion it exists to prevent.
 * The production ceiling is 1500 MB; these tests pass their own small ceilings explicitly.
 */

import { describe, expect, test } from "bun:test";
import { existsSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  armResidentMemoryWatchdogThatSigkillsSubprocessAboveCeiling,
  releaseMachineWideConcurrencySlotSwallowingAllFilesystemErrors,
  tryAcquireMachineWideConcurrencySlotForGuardedSubprocess,
  wrapArgvWithKernelEnforcedCpuSecondsCeiling,
} from "./subprocess-resident-memory-watchdog-and-machine-wide-concurrency-slot-guard-iter124";

const scratchDirectory = mkdtempSync(join(tmpdir(), "subprocess-guard-test-"));

/** Allocates in 10 MB steps up to a hard 120 MB stop, touching pages so RSS is real. */
function writeBoundedAllocatorScript(): string {
  const scriptPath = join(scratchDirectory, "bounded_allocator.py");
  writeFileSync(
    scriptPath,
    [
      "import time",
      "chunks = []",
      "for _ in range(12):",              // hard ceiling: 120 MB
      "    b = bytearray(10 * 1024 * 1024)",
      "    for i in range(0, len(b), 4096): b[i] = 1",
      "    chunks.append(b)",
      "    time.sleep(0.15)",
      "time.sleep(5)",
      "print('survived')",
    ].join("\n"),
  );
  return scriptPath;
}

describe("machine-wide concurrency slots", () => {
  const toolName = `guardtest-${process.pid}`;

  test("hands out exactly N slots and then refuses", () => {
    const first = tryAcquireMachineWideConcurrencySlotForGuardedSubprocess(toolName, 2);
    const second = tryAcquireMachineWideConcurrencySlotForGuardedSubprocess(toolName, 2);
    const third = tryAcquireMachineWideConcurrencySlotForGuardedSubprocess(toolName, 2);

    expect(first).not.toBeNull();
    expect(second).not.toBeNull();
    // The whole point: the 2026-07-30 incident needed FOUR simultaneous processes.
    expect(third).toBeNull();

    releaseMachineWideConcurrencySlotSwallowingAllFilesystemErrors(first);
    releaseMachineWideConcurrencySlotSwallowingAllFilesystemErrors(second);
  });

  test("a released slot becomes available again", () => {
    const slot = tryAcquireMachineWideConcurrencySlotForGuardedSubprocess(toolName, 1);
    expect(slot).not.toBeNull();
    expect(tryAcquireMachineWideConcurrencySlotForGuardedSubprocess(toolName, 1)).toBeNull();
    releaseMachineWideConcurrencySlotSwallowingAllFilesystemErrors(slot);

    const reacquired = tryAcquireMachineWideConcurrencySlotForGuardedSubprocess(toolName, 1);
    expect(reacquired).not.toBeNull();
    releaseMachineWideConcurrencySlotSwallowingAllFilesystemErrors(reacquired);
  });

  test("releasing twice is safe and leaves no file behind", () => {
    const slot = tryAcquireMachineWideConcurrencySlotForGuardedSubprocess(toolName, 1);
    expect(slot).not.toBeNull();
    releaseMachineWideConcurrencySlotSwallowingAllFilesystemErrors(slot);
    releaseMachineWideConcurrencySlotSwallowingAllFilesystemErrors(slot);
    expect(existsSync(slot!.slotFilePath)).toBe(false);
  });

  test("a slot held by a DEAD process is reclaimed, not leaked forever", () => {
    const slot = tryAcquireMachineWideConcurrencySlotForGuardedSubprocess(toolName, 1);
    expect(slot).not.toBeNull();
    // Impersonate a holder that has since died. pid 2^31-1 cannot exist.
    writeFileSync(slot!.slotFilePath, `2147483647 ${Date.now()}`);

    // Without liveness-based reclaim this returns null forever and type checking silently
    // stops machine-wide — a worse outcome than the bug being guarded against.
    const reclaimed = tryAcquireMachineWideConcurrencySlotForGuardedSubprocess(toolName, 1);
    expect(reclaimed).not.toBeNull();
    releaseMachineWideConcurrencySlotSwallowingAllFilesystemErrors(reclaimed);
  });

  test("a live holder's slot is NOT stolen", () => {
    const slot = tryAcquireMachineWideConcurrencySlotForGuardedSubprocess(toolName, 1);
    expect(slot).not.toBeNull();
    writeFileSync(slot!.slotFilePath, `${process.pid} ${Date.now()}`);
    expect(tryAcquireMachineWideConcurrencySlotForGuardedSubprocess(toolName, 1)).toBeNull();
    releaseMachineWideConcurrencySlotSwallowingAllFilesystemErrors(slot);
  });
});

describe("kernel-enforced CPU ceiling", () => {
  test("wraps argv through sh with ulimit -t and exec", () => {
    const wrapped = wrapArgvWithKernelEnforcedCpuSecondsCeiling(["ty", "check", "a.py"], 20);
    expect(wrapped[0]).toBe("/bin/sh");
    expect(wrapped[1]).toBe("-c");
    expect(wrapped[2]).toContain("ulimit -t 20;");
    // `exec` matters: it keeps the reported pid equal to the tool's own pid, which the
    // RSS watchdog polls.
    expect(wrapped[2]).toContain("exec 'ty' 'check' 'a.py'");
  });

  test("a hostile filename cannot break out of the quoting and execute", async () => {
    // Behavioural, not textual: the injected text DOES appear inside the command string,
    // correctly neutralised by the '\'' escape. Asserting on the substring would fail
    // while the code is right. What matters is whether the shell ever RUNS it.
    const sentinelPath = join(scratchDirectory, "injection-sentinel");
    const hostileFileName = `/tmp/x'; touch ${sentinelPath}; '.py`;

    const subprocess = Bun.spawn(
      wrapArgvWithKernelEnforcedCpuSecondsCeiling(["echo", hostileFileName], 5),
      { stdout: "pipe", stderr: "ignore" },
    );
    const stdoutText = await new Response(subprocess.stdout).text();
    await subprocess.exited;

    expect(existsSync(sentinelPath)).toBe(false); // the injection never executed
    expect(stdoutText).toContain("touch"); // it was passed through as a literal argument
  }, 15_000);

  test("RLIMIT_CPU is genuinely enforced by this kernel (SIGXCPU)", async () => {
    // macOS rejects every MEMORY rlimit with EINVAL (verified: AS/RSS/DATA/STACK), so
    // RLIMIT_CPU is the only kernel-level bound available. If this ever stops holding,
    // the backstop layer is gone and we must know.
    const spinner = join(scratchDirectory, "spinner.py");
    writeFileSync(spinner, "import time\nt=time.time()\nwhile time.time()-t < 30: pass\n");
    const startedAt = Date.now();
    const subprocess = Bun.spawn(
      wrapArgvWithKernelEnforcedCpuSecondsCeiling(["python3", spinner], 1),
      { stdout: "ignore", stderr: "ignore" },
    );
    await subprocess.exited;
    const elapsedMilliseconds = Date.now() - startedAt;

    expect(subprocess.exitCode).not.toBe(0);
    expect(elapsedMilliseconds).toBeLessThan(15_000); // died on CPU limit, not the 30 s loop
  }, 30_000);
});

describe("resident-memory watchdog", () => {
  test("SIGKILLs a subprocess that climbs past the ceiling", async () => {
    const allocator = writeBoundedAllocatorScript();
    const subprocess = Bun.spawn(["python3", allocator], { stdout: "pipe", stderr: "ignore" });

    // 40 MB ceiling against a script that walks to 120 MB: it must die partway.
    const watchdog = armResidentMemoryWatchdogThatSigkillsSubprocessAboveCeiling(
      subprocess.pid,
      40,
    );
    const stdoutText = await new Response(subprocess.stdout).text();
    await subprocess.exited;
    watchdog.disarm();

    expect(watchdog.wasKilledForExceedingMemoryCeiling()).toBe(true);
    // SIGKILL, not SIGTERM — the incident showed SIGTERM'd processes surviving seconds.
    expect(subprocess.exitCode).not.toBe(0);
    expect(stdoutText).not.toContain("survived");
  }, 30_000);

  test("leaves a well-behaved subprocess completely alone", async () => {
    const subprocess = Bun.spawn(["python3", "-c", "print('quick')"], {
      stdout: "pipe",
      stderr: "ignore",
    });
    const watchdog = armResidentMemoryWatchdogThatSigkillsSubprocessAboveCeiling(
      subprocess.pid,
      40,
    );
    const stdoutText = await new Response(subprocess.stdout).text();
    await subprocess.exited;
    watchdog.disarm();

    expect(subprocess.exitCode).toBe(0);
    expect(stdoutText.trim()).toBe("quick");
    expect(watchdog.wasKilledForExceedingMemoryCeiling()).toBe(false);
    // Never polled: the first poll is deferred past a normal check's lifetime, which is
    // what keeps this free on the hot path (it runs after EVERY Python edit).
    expect(watchdog.observedPeakResidentMegabytes()).toBe(0);
  }, 15_000);

  test("disarm stops the watchdog from acting on a recycled pid", async () => {
    const subprocess = Bun.spawn(["python3", "-c", "pass"], { stdout: "ignore", stderr: "ignore" });
    const watchdog = armResidentMemoryWatchdogThatSigkillsSubprocessAboveCeiling(subprocess.pid, 1);
    await subprocess.exited;
    watchdog.disarm();
    await Bun.sleep(600); // past first-poll delay + one interval
    expect(watchdog.wasKilledForExceedingMemoryCeiling()).toBe(false);
  }, 15_000);
});
