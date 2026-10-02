/**
 * Resource guards for hook-spawned subprocesses: an RSS watchdog, a kernel-enforced CPU
 * cap, and a machine-wide concurrency gate.
 *
 * ── WHY THIS EXISTS ──────────────────────────────────────────────────────────────────
 *
 * 2026-07-30: this machine froze and had to be power-cycled. The kernel's own jetsam
 * report (/Library/Logs/DiagnosticReports/JetsamEvent-2026-07-30-115148.ips) names the
 * culprit:
 *
 *     largestProcess: ty
 *     ty x5 instances  ->  73,442 MB   (21.0 / 19.1 / 15.8 / 15.8 GB + 7 MB)
 *     iTerm2                1,547 MB
 *     compressor grew 157,861 -> 1,163,083 pages between the 11:15 and 11:51 events
 *
 * `ty` is spawned by posttooluse-ty-type-check after EVERY .py/.pyi Write|Edit, in EVERY
 * concurrent Claude Code session. Four sessions were editing Python at once. Measured
 * normal behaviour on that same project: 35-47 MB for a single file, 119 MB for the whole
 * project, 473 MB for four concurrent whole-project checks. So 15-21 GB per process is
 * pathological, not a scaling curve.
 *
 * The pre-existing guardrails did not and could not stop it:
 *   - AbortSignal.timeout(4000) bounds DURATION, not memory. The jetsam report shows the
 *     four processes were 7.2-8.9 s old and already at 15.8-21.0 GB, i.e. they had
 *     outlived the 4 s deadline. Bun's default killSignal is SIGTERM, and under a
 *     thrashing compressor a SIGTERM'd process does not die promptly.
 *   - maxBuffer bounds OUTPUT SIZE, which was never the problem.
 * And `launchd`'s age in that same report shows an uptime of ~38 minutes: the machine had
 * ALREADY crashed once that morning and the fault recurred after the reboot. This is a
 * repeating failure, not a one-off.
 *
 * ── WHAT MACOS ACTUALLY OFFERS (measured on this machine, not assumed) ────────────────
 *
 * macOS has no cgroups, and the usual advice does not work here. Probing setrlimit(2)
 * directly through libc on this kernel:
 *
 *     RLIMIT_AS / RLIMIT_RSS  -> EINVAL (22) at EVERY value tried, 0.1 GB through 64 GB
 *     RLIMIT_DATA             -> EINVAL (22)
 *     RLIMIT_STACK            -> EINVAL (22)
 *     RLIMIT_CPU              -> ACCEPTED, and verified ENFORCED (SIGXCPU, rc -24)
 *     RLIMIT_FSIZE / CORE / NOFILE -> accepted
 *
 * `ulimit -v` and `ulimit -d` are likewise rejected by the shell with
 * "setrlimit failed: invalid argument". So there is NO kernel-enforced memory cap
 * available to a normal user process on macOS. Anything claiming otherwise is folklore.
 *
 * That leaves three real mechanisms, applied here in order of leverage:
 *
 *   1. CONCURRENCY GATE  - the incident REQUIRED four simultaneous processes. Bounding
 *                          concurrency bounds the worst case multiplicatively, and is the
 *                          only layer that helps when a single process is well-behaved
 *                          but the fleet is not.
 *   2. RSS WATCHDOG      - poll the child's resident size and SIGKILL past a ceiling.
 *                          The only actual memory bound obtainable on macOS. SIGKILL,
 *                          never SIGTERM: the incident showed a SIGTERM'd process
 *                          surviving seconds under memory pressure.
 *   3. RLIMIT_CPU        - kernel-enforced backstop via `sh -c 'ulimit -t N; exec ...'`,
 *                          so it still fires if this Bun process is itself starved and
 *                          its watchdog timer never runs. Verified working above.
 *
 * ── HOT-PATH COST ────────────────────────────────────────────────────────────────────
 *
 * This runs after every Python edit, so the common path must be free. It is: the watchdog
 * arms a single setTimeout and the FIRST poll happens only after
 * RESIDENT_MEMORY_WATCHDOG_FIRST_POLL_DELAY_MILLISECONDS. A normal ty check finishes in
 * ~5-100 ms, well before that, so it spawns zero `ps` processes and does zero extra work.
 * Only a subprocess that is already misbehaving ever pays for the watchdog.
 */

import { closeSync, mkdirSync, openSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";

// ══════════════════════════════════════════════════════════════════════════
//  Tunables — every number is justified against measured behaviour
// ══════════════════════════════════════════════════════════════════════════

/**
 * SIGKILL a guarded subprocess above this resident size.
 *
 * Measured ty peaks on the project that triggered the incident: 35-47 MB for one file,
 * 119 MB for the entire project, 473 MB aggregate for four concurrent whole-project runs.
 * 1500 MB is ~12x the whole-project peak — high enough that no honest check can trip it,
 * low enough that four simultaneous runaways cost 6 GB instead of 73 GB.
 */
export const GUARDED_SUBPROCESS_RESIDENT_MEMORY_KILL_CEILING_MEGABYTES = 1500;

/**
 * The watchdog does nothing until this long after spawn, which is what keeps the common
 * path free. Chosen to sit above a normal check (~5-100 ms) and far below the point where
 * a runaway becomes dangerous.
 */
export const RESIDENT_MEMORY_WATCHDOG_FIRST_POLL_DELAY_MILLISECONDS = 300;

/**
 * Poll period once the watchdog has armed. The incident's processes gained roughly 2 GB/s,
 * so a 200 ms period bounds overshoot past the ceiling to a few hundred MB.
 */
export const RESIDENT_MEMORY_WATCHDOG_POLL_INTERVAL_MILLISECONDS = 200;

/**
 * Kernel-enforced CPU-seconds ceiling, applied via `ulimit -t`. A normal check uses
 * milliseconds of CPU. This exists purely as a backstop for the case where the JS-side
 * watchdog never gets scheduled because the machine is already thrashing.
 */
export const GUARDED_SUBPROCESS_CPU_SECONDS_HARD_CEILING = 20;

/**
 * Machine-wide simultaneous-run ceiling, across every Claude Code session.
 *
 * The incident needed four. Two keeps the worst case bounded (2 x the RSS ceiling) while
 * still letting a second session's check proceed rather than being needlessly serialised.
 */
export const MACHINE_WIDE_CONCURRENT_GUARDED_SUBPROCESS_SLOT_COUNT = 2;

/**
 * A slot older than this is treated as abandoned. Bounded by the caller's own timeout
 * (4 s for ty) plus generous slack for a machine under load.
 */
export const CONCURRENCY_SLOT_STALE_RECLAIM_AGE_MILLISECONDS = 60_000;

/** Slots live under /tmp deliberately: it is cleared on boot, so a panic cannot leak a
 *  permanently-held slot into the next uptime. Holder liveness is still checked below. */
const CONCURRENCY_SLOT_DIRECTORY_PREFIX = "/tmp/.claude-subprocess-concurrency-slots";

// ══════════════════════════════════════════════════════════════════════════
//  Machine-wide concurrency slots
// ══════════════════════════════════════════════════════════════════════════

export interface AcquiredConcurrencySlot {
  readonly slotFilePath: string;
}

/**
 * True when no process with this pid exists. `kill(pid, 0)` is the POSIX liveness probe:
 * it delivers nothing and fails with ESRCH when the pid is gone.
 */
function isProcessIdentifierDeadSoItsSlotMayBeReclaimed(processIdentifier: number): boolean {
  if (!Number.isInteger(processIdentifier) || processIdentifier <= 0) return true;
  try {
    process.kill(processIdentifier, 0);
    return false;
  } catch (error: unknown) {
    // EPERM means the process EXISTS but belongs to someone else — that is alive, not dead.
    return (error as NodeJS.ErrnoException)?.code !== "EPERM";
  }
}

/**
 * Delete slot files whose holder is gone or which are older than the reclaim age.
 *
 * Reclaiming on liveness alone is not enough: a holder can be SIGKILLed and its pid reused
 * by an unrelated process, which would make a dead slot look alive forever. The age bound
 * is the backstop for that, and every caller's own timeout is far below it.
 */
function reclaimAbandonedConcurrencySlotsSwallowingAllFilesystemErrors(slotDirectory: string): void {
  let slotFileNames: string[];
  try {
    slotFileNames = readdirSync(slotDirectory);
  } catch {
    return;
  }
  const nowMilliseconds = Date.now();
  for (const slotFileName of slotFileNames) {
    const slotFilePath = `${slotDirectory}/${slotFileName}`;
    try {
      const [recordedPid, recordedTimestamp] = readFileSync(slotFilePath, "utf8").trim().split(" ");
      const holderPid = Number.parseInt(recordedPid ?? "", 10);
      const heldSinceMilliseconds = Number.parseInt(recordedTimestamp ?? "", 10);
      const holderIsGone = isProcessIdentifierDeadSoItsSlotMayBeReclaimed(holderPid);
      const slotIsStale =
        !Number.isFinite(heldSinceMilliseconds) ||
        nowMilliseconds - heldSinceMilliseconds > CONCURRENCY_SLOT_STALE_RECLAIM_AGE_MILLISECONDS;
      if (holderIsGone || slotIsStale) rmSync(slotFilePath, { force: true });
    } catch {
      // Unreadable/garbage slot file — treat as abandoned rather than blocking forever.
      try {
        rmSync(slotFilePath, { force: true });
      } catch {
        /* nothing further to try */
      }
    }
  }
}

/**
 * Try to claim one of N machine-wide slots. Returns null when all are taken.
 *
 * NON-BLOCKING on purpose. A type check is advisory: skipping one is invisible, whereas
 * waiting on a lock puts a hook — and therefore the user's edit — behind an unrelated
 * session's subprocess. "Fail open by doing less" is the only safe direction here.
 *
 * Race-safe via O_EXCL, which is atomic at the POSIX layer: if several sessions try the
 * same slot index simultaneously exactly one `openSync(..., "wx")` succeeds and the rest
 * see EEXIST and move to the next index.
 */
export function tryAcquireMachineWideConcurrencySlotForGuardedSubprocess(
  guardedToolName: string,
  slotCount: number = MACHINE_WIDE_CONCURRENT_GUARDED_SUBPROCESS_SLOT_COUNT,
): AcquiredConcurrencySlot | null {
  const slotDirectory = `${CONCURRENCY_SLOT_DIRECTORY_PREFIX}-${guardedToolName}`;
  try {
    mkdirSync(slotDirectory, { recursive: true });
  } catch {
    return null;
  }
  reclaimAbandonedConcurrencySlotsSwallowingAllFilesystemErrors(slotDirectory);

  for (let slotIndex = 0; slotIndex < slotCount; slotIndex += 1) {
    const slotFilePath = `${slotDirectory}/slot-${slotIndex}`;
    try {
      const fileDescriptor = openSync(slotFilePath, "wx");
      try {
        writeFileSync(fileDescriptor, `${process.pid} ${Date.now()}`);
      } finally {
        closeSync(fileDescriptor);
      }
      return { slotFilePath };
    } catch {
      // EEXIST: somebody else holds this slot. Try the next one.
    }
  }
  return null;
}

/** Release a slot. Safe to call twice, and safe if the file is already gone. */
export function releaseMachineWideConcurrencySlotSwallowingAllFilesystemErrors(
  slot: AcquiredConcurrencySlot | null,
): void {
  if (!slot) return;
  try {
    rmSync(slot.slotFilePath, { force: true });
  } catch {
    /* the reclaim path will collect it */
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Resident-memory watchdog
// ══════════════════════════════════════════════════════════════════════════

/**
 * Read one process's resident size in MB, or null if it is gone.
 *
 * `ps -o rss=` is used rather than proc_pid_rusage via FFI because this executes at most a
 * handful of times per guarded run — and, on the common path, zero times. An FFI binding
 * would be faster per call and strictly more code to get wrong.
 */
async function readProcessResidentSetSizeMegabytesOrNullWhenGone(
  processIdentifier: number,
): Promise<number | null> {
  try {
    const probe = Bun.spawn(["ps", "-o", "rss=", "-p", String(processIdentifier)], {
      stdout: "pipe",
      stderr: "ignore",
    });
    const residentKilobytesText = (await new Response(probe.stdout).text()).trim();
    await probe.exited;
    if (!residentKilobytesText) return null;
    const residentKilobytes = Number.parseInt(residentKilobytesText, 10);
    return Number.isFinite(residentKilobytes) ? residentKilobytes / 1024 : null;
  } catch {
    return null;
  }
}

export interface ResidentMemoryWatchdogHandle {
  /** Stop polling. Must be called on every exit path, including errors. */
  readonly disarm: () => void;
  /** True once the watchdog has SIGKILLed the subprocess for exceeding the ceiling. */
  readonly wasKilledForExceedingMemoryCeiling: () => boolean;
  /** Peak RSS the watchdog actually observed, for diagnostics. 0 if it never polled. */
  readonly observedPeakResidentMegabytes: () => number;
}

/**
 * Watch a subprocess's RSS and SIGKILL it past the ceiling.
 *
 * SIGKILL, deliberately, and never SIGTERM: the 2026-07-30 report shows processes that had
 * outlived a 4 s SIGTERM deadline by 3-5 seconds while sitting at 15-21 GB. Under a
 * thrashing compressor a catchable signal is not a reliable way to stop anything, and
 * SIGKILL cannot be blocked, caught, or slowed by the target. Killing a Rust type checker
 * mid-allocation is safe: it holds no lock we care about and writes no state we read.
 */
export function armResidentMemoryWatchdogThatSigkillsSubprocessAboveCeiling(
  processIdentifier: number,
  ceilingMegabytes: number = GUARDED_SUBPROCESS_RESIDENT_MEMORY_KILL_CEILING_MEGABYTES,
): ResidentMemoryWatchdogHandle {
  let pollTimer: ReturnType<typeof setTimeout> | null = null;
  let disarmed = false;
  let killed = false;
  let peakResidentMegabytes = 0;

  const pollOnce = async (): Promise<void> => {
    if (disarmed) return;
    const residentMegabytes = await readProcessResidentSetSizeMegabytesOrNullWhenGone(processIdentifier);
    if (disarmed) return;
    if (residentMegabytes === null) return; // exited between scheduling and polling
    if (residentMegabytes > peakResidentMegabytes) peakResidentMegabytes = residentMegabytes;
    if (residentMegabytes > ceilingMegabytes) {
      killed = true;
      try {
        process.kill(processIdentifier, "SIGKILL");
      } catch {
        /* already gone */
      }
      return;
    }
    pollTimer = setTimeout(() => void pollOnce(), RESIDENT_MEMORY_WATCHDOG_POLL_INTERVAL_MILLISECONDS);
    pollTimer.unref?.();
  };

  pollTimer = setTimeout(() => void pollOnce(), RESIDENT_MEMORY_WATCHDOG_FIRST_POLL_DELAY_MILLISECONDS);
  // unref so an armed watchdog can never keep the hook process alive past its work.
  pollTimer.unref?.();

  return {
    disarm: () => {
      disarmed = true;
      if (pollTimer) clearTimeout(pollTimer);
      pollTimer = null;
    },
    wasKilledForExceedingMemoryCeiling: () => killed,
    observedPeakResidentMegabytes: () => peakResidentMegabytes,
  };
}

// ══════════════════════════════════════════════════════════════════════════
//  Kernel-enforced CPU ceiling
// ══════════════════════════════════════════════════════════════════════════

/**
 * Wrap an argv so the kernel enforces a CPU-seconds ceiling on it.
 *
 * `ulimit -t` sets RLIMIT_CPU, which is one of the few rlimits this kernel accepts
 * (verified: RLIMIT_AS/RSS/DATA/STACK all return EINVAL, RLIMIT_CPU is accepted and fires
 * SIGXCPU on breach). `exec` replaces the shell so no extra process lingers and the pid
 * Bun reports is the real tool's pid — which the RSS watchdog depends on.
 *
 * Arguments are single-quoted with the POSIX '\'' escape, so a path containing spaces or
 * shell metacharacters cannot break out of the quoting into the command line.
 */
export function wrapArgvWithKernelEnforcedCpuSecondsCeiling(
  argv: readonly string[],
  cpuSecondsCeiling: number = GUARDED_SUBPROCESS_CPU_SECONDS_HARD_CEILING,
): string[] {
  const singleQuotedArgv = argv
    .map((argument) => `'${String(argument).replaceAll("'", `'\\''`)}'`)
    .join(" ");
  return ["/bin/sh", "-c", `ulimit -t ${cpuSecondsCeiling}; exec ${singleQuotedArgv}`];
}
