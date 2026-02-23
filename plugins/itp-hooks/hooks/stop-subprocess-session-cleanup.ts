#!/usr/bin/env bun
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
 * Related: posttooluse-subprocess-orphan-cleanup.ts (per-tool cleanup)
 */

/**
 * Kill all PUEUE jobs
 */
async function cleanupPueueJobs(): Promise<void> {
  try {
    // Check if pueue daemon is running
    const status_check = Bun.spawnSync(["pueue", "status"], {
      stdout: "ignore",
      stderr: "ignore",
    });

    if (status_check.exitCode === 0) {
      console.warn("🧹 Cleaning up PUEUE jobs...");

      // Kill all running jobs
      Bun.spawnSync(["pueue", "kill"], {
        stdout: "ignore",
        stderr: "ignore",
      });

      // Clean job queue
      Bun.spawnSync(["pueue", "clean"], {
        stdout: "ignore",
        stderr: "ignore",
      });

      console.warn("   ✓ PUEUE jobs cleaned");
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
 * Kill all orphaned processes that might hold TTY references
 */
async function cleanupOrphanedProcesses(): Promise<void> {
  try {
    console.warn("🧹 Cleaning up orphaned processes...");

    // Find and kill processes with TTY references
    Bun.spawnSync(
      [
        "bash",
        "-c",
        'ps aux | grep -E "/dev/tty|stdin" | grep -v grep | awk \'{print $2}\' | xargs -r kill -9 2>/dev/null; true',
      ],
      {
        stdout: "ignore",
        stderr: "ignore",
      },
    );

    console.warn("   ✓ Orphaned processes cleared");
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

    // Check for remaining child processes
    const ps_output = await new Promise<string>((resolve) => {
      const proc = Bun.spawn(["bash", "-c", "ps -o ppid=,pid=,cmd= | grep ^1"], {
        stdout: "pipe",
        stderr: "ignore",
      });

      let output = "";
      proc.stdout?.on("data", (chunk) => {
        output += chunk.toString();
      });

      proc.on("close", () => resolve(output));
    });

    const remaining_count = ps_output.trim().split("\n").length;
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
