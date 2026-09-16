#!/usr/bin/env bun
// @ts-nocheck — Bun subprocess APIs (.on() on ReadableStream) not in bun-types
/**
 * Stop hook: Subprocess Session Cleanup
 *
 * Problem: When Claude Code session ends, background processes,PUEUE jobs,
 * and orphaned subprocesses can remain, holding TTY references and causing
 * future session suspension when new Claude Code starts.
 *
 * Solution: On session end, perform comprehensive cleanup:
 * - Kill all PUEUE jobs
 * - Kill all background processes
 * - Detach orphaned processes
 * - Clear TTY locks and references
 *
 * Coverage: Session-level cleanup (runs once on shutdown)
 *
 * Reference: GitHub Issues #11898, #12507, #13598
 * Note: the former per-tool twin, posttooluse-subprocess-orphan-cleanup.ts, was deleted 2026-09-05 —
 * it was a proven no-op (same broken `ps -o cmd=` call, plus it filtered on its OWN pid as parent).
 */

/**
 * Kill only PUEUE jobs owned by this session.
 * The wrap guard records task IDs to a session-scoped file.
 * Falls back to killing all jobs only if the log file is missing.
 */
async function cleanupPueueJobs(): Promise<void> {
  try {
    // Check if pueue daemon is running
    const status_check = Bun.spawnSync(["pueue", "status"], {
      stdout: "ignore",
      stderr: "ignore",
    });

    if (status_check.exitCode !== 0) return;

    console.warn("🧹 Cleaning up PUEUE jobs...");

    // Read session task log — only kill jobs we started
    const sessionId = process.env.CLAUDE_SESSION_ID || String(process.ppid);
    const taskLogPath = `/tmp/claude-pueue-tasks-${sessionId}.txt`;

    let taskIds: string[] = [];
    try {
      const content = await Bun.file(taskLogPath).text();
      taskIds = content.trim().split("\n").filter(Boolean);
    } catch {
      // No task log — nothing to clean
    }

    if (taskIds.length > 0) {
      // Kill only our session's jobs
      for (const id of taskIds) {
        Bun.spawnSync(["pueue", "kill", id], {
          stdout: "ignore",
          stderr: "ignore",
        });
      }
      // Clean completed/killed jobs
      Bun.spawnSync(["pueue", "clean"], {
        stdout: "ignore",
        stderr: "ignore",
      });
      // Remove the session task log
      try { await Bun.write(taskLogPath, ""); } catch { /* ignore */ }
      console.warn(`   ✓ ${taskIds.length} session PUEUE job(s) cleaned`);
    } else {
      console.warn("   ✓ No session PUEUE jobs to clean");
    }
  } catch (e) {
    console.warn("   ⚠️  PUEUE cleanup error:", e);
  }
}

/**
 * Kill all background jobs in the shell
 */
async function cleanupBackgroundJobs(): Promise<void> {
  try {
    console.warn("🧹 Cleaning up background jobs...");

    // Get all background jobs and kill them
    Bun.spawnSync(
      [
        "bash",
        "-c",
        'jobs -l 2>/dev/null | awk \'{print $2}\' | xargs -r kill -9 2>/dev/null; true',
      ],
      {
        stdout: "ignore",
        stderr: "ignore",
      },
    );

    console.warn("   ✓ Background jobs terminated");
  } catch (e) {
    console.warn("   ⚠️  Background job cleanup error:", e);
  }
}

/**
 * Kill orphaned processes that might hold TTY references — WITHIN THIS SESSION'S
 * OWN PROCESS TREE ONLY.
 *
 * ── 2026-09-12: this function used to be a machine-wide SIGKILL. ────────────
 * It was, verbatim:
 *
 *   ps aux | grep -E "/dev/tty|stdin" | grep -v grep | awk '{print $2}' | xargs -r kill -9
 *
 * That is `kill -9` keyed on a SUBSTRING OF THE COMMAND LINE, across every
 * process on the machine, with no ownership check, no session check, and no
 * check that the match had anything to do with a TTY.
 *
 * It was caught doing exactly what that implies. The `samson-catchup` launchd
 * job's `ssh` carried the word "stdin" inside a shell COMMENT embedded in its
 * remote script, so `ps aux` matched it and this hook killed it mid-install.
 * Evidence: `launchd.err.log` recorded `99746 Killed: 9   ssh -o ConnectTimeout=…`,
 * and joining 1,635 stop-hook runs against 60 upgrade windows gave 3/3 SIGKILLed
 * upgrades overlapping a Stop hook versus 0/57 that did not (p ≈ 3e-5). A member's
 * upgrade was truncated mid-flight, twice, by a hook belonging to an unrelated
 * session.
 *
 * TWO defects, both addressed here:
 *
 *   1. SCOPE — a process this session did not start is never ours to kill. The
 *      kill set is now the descendants of this session's own root, and if that
 *      root cannot be identified we kill NOTHING. Refusing to act beats killing
 *      a stranger.
 *   2. SELECTOR — matching argv text is not evidence that a process holds a TTY
 *      (the victim above held none; it merely quoted the word in a comment). The
 *      heuristic is kept, but only as a filter INSIDE our own subtree, where the
 *      false positives are ours to eat instead of the machine's.
 *
 * This strictly REDUCES the set of processes killed, so it cannot regress any
 * cleanup the old code legitimately performed — it can only stop it reaching
 * bystanders. Sibling precedent: cleanupPueueJobs() above was scoped to the
 * session long ago; this function was simply never given the same treatment.
 *
 * Set ITP_ORPHAN_CLEANUP_DRY_RUN=1 to report the kill set without killing.
 */
async function cleanupOrphanedProcesses(): Promise<void> {
  try {
    console.warn("🧹 Cleaning up orphaned processes...");

    const snapshot = Bun.spawnSync(["ps", "-eo", "pid=,ppid=,command="], {
      stdout: "pipe",
      stderr: "ignore",
    });
    if (snapshot.exitCode !== 0) {
      console.warn("   ⚠️  ps snapshot failed — killing nothing");
      return;
    }

    const parentOf = new Map<number, number>();
    const childrenOf = new Map<number, number[]>();
    const commandOf = new Map<number, string>();

    for (const line of snapshot.stdout.toString().split("\n")) {
      const m = line.match(/^\s*(\d+)\s+(\d+)\s+(.*)$/);
      if (!m) continue;
      const pid = Number(m[1]);
      const ppid = Number(m[2]);
      parentOf.set(pid, ppid);
      commandOf.set(pid, m[3]);
      const sibs = childrenOf.get(ppid) ?? [];
      sibs.push(pid);
      childrenOf.set(ppid, sibs);
    }

    // Walk our own ancestry and take the HIGHEST ancestor that is still a
    // `claude` process — that is this session's root. Anything outside its
    // subtree belongs to someone else.
    let sessionRoot: number | null = null;
    let cursor: number | undefined = process.pid;
    const visited = new Set<number>();
    while (cursor && cursor > 1 && !visited.has(cursor)) {
      visited.add(cursor);
      if (/(^|\/)claude(\s|$)/.test(commandOf.get(cursor) ?? "")) sessionRoot = cursor;
      cursor = parentOf.get(cursor);
    }

    if (sessionRoot === null) {
      // We could not establish which tree is ours. The old code would have
      // killed machine-wide here. We kill nothing.
      console.warn("   ✓ No identifiable session root — killing nothing (by design)");
      return;
    }

    // Collect descendants of our root, excluding ourselves and our own ancestors.
    const ours = new Set<number>();
    const queue = [...(childrenOf.get(sessionRoot) ?? [])];
    while (queue.length > 0) {
      const pid = queue.pop() as number;
      if (ours.has(pid) || visited.has(pid)) continue;
      ours.add(pid);
      for (const child of childrenOf.get(pid) ?? []) queue.push(child);
    }

    const victims = [...ours].filter((pid) => {
      const c = commandOf.get(pid) ?? "";
      return c.includes("/dev/tty") || c.includes("stdin");
    });

    if (victims.length === 0) {
      console.warn("   ✓ No orphaned TTY holders in this session's tree");
      return;
    }

    if (process.env.ITP_ORPHAN_CLEANUP_DRY_RUN === "1") {
      console.warn(`   ⚠️  DRY RUN — would kill ${victims.length} pid(s) under ${sessionRoot}:`);
      for (const pid of victims) console.warn(`        ${pid}  ${(commandOf.get(pid) ?? "").slice(0, 120)}`);
      return;
    }

    for (const pid of victims) {
      try {
        process.kill(pid, "SIGKILL");
      } catch {
        // already gone
      }
    }
    console.warn(`   ✓ ${victims.length} orphaned process(es) cleared (session ${sessionRoot} subtree)`);
  } catch (e) {
    console.warn("   ⚠️  Orphan cleanup error:", e);
  }
}

/**
 * Clear TTY locks and references
 */
async function clearTTYReferences(): Promise<void> {
  try {
    console.warn("🧹 Clearing TTY references...");

    // Try to close any open TTY file descriptors
    const tty_files = ["/dev/tty", "/dev/tty.lock"];

    for (const tty_file of tty_files) {
      try {
        // Just check if file exists and is accessible
        const stat_check = Bun.spawnSync(["test", "-e", tty_file], {
          stdout: "ignore",
          stderr: "ignore",
        });

        // If we can access it, try to clear any locks (limited privileges)
        if (stat_check.exitCode === 0) {
          Bun.spawnSync(["bash", "-c", `fuser -k ${tty_file} 2>/dev/null; true`], {
            stdout: "ignore",
            stderr: "ignore",
          });
        }
      } catch (e) {
        // Ignore - we may not have permissions
      }
    }

    console.warn("   ✓ TTY references cleared");
  } catch (e) {
    console.warn("   ⚠️  TTY cleanup error:", e);
  }
}

/**
 * Final verification
 */
async function verifyCleanup(): Promise<void> {
  try {
    console.warn("🧹 Final verification...");

    // Check for remaining child processes.
    // `comm=`, NOT `cmd=`: `cmd` is a Linux/procps keyword that BSD/macOS `ps` rejects outright —
    // `ps -o ppid=,pid=,cmd=` exits 1 with "ps: cmd: keyword not found" and prints nothing, so the
    // whole verification silently degraded to inspecting an empty string. `comm=` is the portable
    // spelling and exits 0.
    const ps_output = await new Promise<string>((resolve) => {
      const proc = Bun.spawn(["bash", "-c", "ps -o ppid=,pid=,comm= | grep ^1"], {
        stdout: "pipe",
        stderr: "ignore",
      });

      let output = "";
      proc.stdout?.on("data", (chunk) => {
        output += chunk.toString();
      });

      proc.on("close", () => resolve(output));
    });

    // Guard the empty case before splitting: "".split("\n") returns [""], whose length is 1, so a
    // naive `.trim().split("\n").length` reports "1 process(es) still running" even when nothing is.
    const trimmed_ps_output = ps_output.trim();
    const remaining_count =
      trimmed_ps_output === "" ? 0 : trimmed_ps_output.split("\n").length;
    if (remaining_count > 0) {
      console.warn(`   ⚠️  ${remaining_count} process(es) still running`);
    } else {
      console.warn("   ✓ All processes cleaned");
    }
  } catch (e) {
    console.warn("   ⚠️  Verification error:", e);
  }
}

async function main() {
  try {
    console.warn(
      "╔════════════════════════════════════════════════════════════╗",
    );
    console.warn(
      "║  Session Cleanup: Terminating all subprocess references   ║",
    );
    console.warn(
      "╚════════════════════════════════════════════════════════════╝",
    );

    await cleanupPueueJobs();
    await cleanupBackgroundJobs();
    await cleanupOrphanedProcesses();
    await clearTTYReferences();
    await verifyCleanup();

    console.warn(
      "╔════════════════════════════════════════════════════════════╗",
    );
    console.warn(
      "║  ✓ Session cleanup complete - Claude Code ready to exit   ║",
    );
    console.warn(
      "╚════════════════════════════════════════════════════════════╝",
    );
  } catch (e) {
    console.warn("❌ Session cleanup failed:", e);
  }
}

main();
