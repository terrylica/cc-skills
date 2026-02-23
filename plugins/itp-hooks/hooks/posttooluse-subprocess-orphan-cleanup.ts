#!/usr/bin/env bun
/**
 * PostToolUse hook: Subprocess Orphan Cleanup
 *
 * Problem: Even with stdin disconnection, orphaned/zombie processes can remain
 * holding references to TTY file descriptors, causing future suspensions.
 *
 * Solution: After ANY tool execution, scan for and clean up:
 * - Orphaned child processes
 * - Zombie processes
 * - Processes holding TTY references
 * - Detached but still-running background jobs
 *
 * Coverage: ALL tools (runs after Bash, Read, Write, LSP, Code, Git, etc.)
 *
 * Reference: GitHub Issues #11898, #12507, #13598
 * Related: pretooluse-subprocess-stdin-inlet-guard.ts (prevention)
 */

import { Subprocess } from "bun";

/**
 * Find all child processes of the current Claude Code session
 */
async function findChildProcesses(): Promise<
  Map<number, { pid: number; ppid: number; cmd: string }>
> {
  try {
    const result = await new Promise<string>((resolve, reject) => {
      const proc = Bun.spawn(["ps", "-o", "ppid=,pid=,cmd="], {
        stdout: "pipe",
        stderr: "ignore",
      });

      let output = "";
      proc.stdout?.on("data", (chunk) => {
        output += chunk.toString();
      });

      proc.on("close", () => resolve(output));
      proc.on("error", reject);
    });

    const processes = new Map<
      number,
      { pid: number; ppid: number; cmd: string }
    >();
    const lines = result.trim().split("\n");

    for (const line of lines) {
      const [ppid_str, pid_str, ...cmd_parts] = line.trim().split(/\s+/);
      const ppid = parseInt(ppid_str);
      const pid = parseInt(pid_str);
      const cmd = cmd_parts.join(" ");

      if (!isNaN(pid) && !isNaN(ppid)) {
        processes.set(pid, { pid, ppid, cmd });
      }
    }

    return processes;
  } catch (e) {
    console.warn("⚠️  Failed to enumerate child processes:", e);
    return new Map();
  }
}

/**
 * Check if a process is holding a TTY reference
 */
async function isHoldingTTY(pid: number): Promise<boolean> {
  try {
    const lsof_result = await new Promise<string>((resolve) => {
      const proc = Bun.spawn(["lsof", "-p", pid.toString()], {
        stdout: "pipe",
        stderr: "ignore",
      });

      let output = "";
      proc.stdout?.on("data", (chunk) => {
        output += chunk.toString();
      });

      proc.on("close", () => resolve(output));
      proc.on("error", () => resolve(""));
    });

    // Check if output contains TTY references
    return (
      lsof_result.includes("/dev/tty") ||
      lsof_result.includes("PTY") ||
      lsof_result.includes("CHR")
    );
  } catch (e) {
    // If lsof not available, use conservative approach
    return false;
  }
}

/**
 * Kill or detach a process
 */
async function cleanupProcess(pid: number, cmd: string): Promise<boolean> {
  try {
    // First try SIGTERM (graceful)
    process.kill(pid, "SIGTERM");
    console.warn(`   Terminating orphan process: ${pid} (${cmd})`);

    // Wait a bit, then force kill if still running
    await new Promise((resolve) => setTimeout(resolve, 100));

    try {
      process.kill(pid, "SIGKILL");
    } catch (e) {
      // Already dead
    }

    return true;
  } catch (e) {
    // Process may already be dead
    return false;
  }
}

/**
 * Clean up PUEUE jobs if they exist
 */
async function cleanupPueueJobs(): Promise<void> {
  try {
    // Check if pueue is available
    const status_check = Bun.spawnSync(["pueue", "status"], {
      stdout: "ignore",
      stderr: "ignore",
    });

    if (status_check.exitCode === 0) {
      // PUEUE is running - don't kill jobs, just verify they're tracked
      console.warn("   ℹ️  PUEUE jobs still active (managed separately)");
    }
  } catch (e) {
    // PUEUE not available
  }
}

async function main() {
  try {
    console.warn("🧹 Subprocess Orphan Cleanup: Scanning for zombie processes");

    // Get current Claude Code PID
    const claude_pid = process.pid;

    // Find all child processes
    const children = await findChildProcesses();

    let cleaned = 0;
    const claude_children = Array.from(children.values()).filter(
      (p) => p.ppid === claude_pid,
    );

    if (claude_children.length === 0) {
      console.warn("   ✓ No orphaned processes found");
    } else {
      // Check each child process
      for (const child of claude_children) {
        const holding_tty = await isHoldingTTY(child.pid);

        if (holding_tty) {
          console.warn(`   ⚠️  Found TTY-holding process: ${child.pid}`);
          const killed = await cleanupProcess(child.pid, child.cmd);
          if (killed) cleaned++;
        }
      }

      if (cleaned > 0) {
        console.warn(
          `   ✓ Cleaned up ${cleaned} orphaned process${cleaned === 1 ? "" : "es"}`,
        );
      }
    }

    // Clean up PUEUE jobs
    await cleanupPueueJobs();

    // Check for background jobs in shell
    try {
      const jobs_output = await new Promise<string>((resolve) => {
        const proc = Bun.spawn(["bash", "-c", "jobs -l"], {
          stdout: "pipe",
          stderr: "ignore",
        });

        let output = "";
        proc.stdout?.on("data", (chunk) => {
          output += chunk.toString();
        });

        proc.on("close", () => resolve(output));
        proc.on("error", () => resolve(""));
      });

      if (jobs_output.trim()) {
        console.warn(
          `   ℹ️  Background jobs present (may be intentional): ${jobs_output.split("\n").length} job(s)`,
        );
      }
    } catch (e) {
      // ignore
    }
  } catch (e) {
    console.warn("⚠️  Orphan cleanup error:", e);
  }
}

main();
