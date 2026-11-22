/**
 * `bun test` preload: fixture hook errors go to a throwaway directory, never the live log.
 *
 * Tests raise hook errors on purpose (a subhook that throws, hangs or answers late; a schema failure for a
 * hook named "test-hook"), and hook-error-tracker.ts records every error. Without this, each run wrote them
 * to ~/.claude/logs/hook-errors.jsonl: 272 of 531 entries in the week to 2026-11-11 (terrylica/cc-skills#78).
 *
 * Registered in two bunfig.toml files, because bun reads bunfig.toml from the directory it is started in and
 * not from its parents (measured with bun 1.4.4, 2026-11-12): the repository root (repo:test, the pre-push
 * gate) and plugins/itp-hooks (a test file run by hand from there).
 *
 * A directory already named by the variable is kept, so the suite runners' own choice stands. Child
 * processes inherit the variable, which covers tests that spawn a hook with the parent's environment.
 *
 * The same holds for the orchestrators' sub-hook timing log (lib/orchestrator-subhook-timing.ts): while an
 * operator's timing window is open, a test run would otherwise append fixture timings to the live
 * ~/.claude/state/hook-census/ files, so ITP_HOOKS_HOOK_CENSUS_DIR points at a throwaway directory too.
 */
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { HOOK_ERROR_LOG_DIR_ENV } from "./hook-error-tracker.ts";

const HOOK_CENSUS_DIR_ENV = "ITP_HOOKS_HOOK_CENSUS_DIR";

if (!process.env[HOOK_ERROR_LOG_DIR_ENV]) {
  const dir = mkdtempSync(join(tmpdir(), "itp-hooks-error-log-"));
  process.env[HOOK_ERROR_LOG_DIR_ENV] = dir;
  process.on("exit", () => {
    try {
      rmSync(dir, { recursive: true, force: true });
    } catch {
      // A leftover temp directory is harmless; the operating system clears it.
    }
  });
}

if (!process.env[HOOK_CENSUS_DIR_ENV]) {
  const dir = mkdtempSync(join(tmpdir(), "itp-hooks-hook-census-"));
  process.env[HOOK_CENSUS_DIR_ENV] = dir;
  process.on("exit", () => {
    try {
      rmSync(dir, { recursive: true, force: true });
    } catch {
      // A leftover temp directory is harmless; the operating system clears it.
    }
  });
}
