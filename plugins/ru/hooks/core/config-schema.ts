#!/usr/bin/env bun
/**
 * Unified Ralph configuration schema - TypeScript/Valibot migration.
 *
 * Migrated from Python/Pydantic to TypeScript/Valibot for:
 * - 38x faster create+parse-once performance (our usage pattern)
 * - Zero Python runtime dependency
 * - Type-safe validation with inference
 *
 * Config file location: .claude/ru-config.json (per-project)
 * Fallback: ~/.claude/ralph-defaults.json (global defaults)
 *
 * ADR: Unified config-driven architecture for deterministic hook behavior.
 */

import { readFileSync, existsSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import * as v from "valibot";

// --- Schemas ---

/**
 * Configuration for file protection (PreToolUse guard).
 * These files cannot be deleted while Ralph loop is active.
 */
export const ProtectionConfigSchema = v.object({
  protected_files: v.optional(
    v.array(v.string()),
    [
      ".claude/loop-enabled",
      ".claude/loop-start-timestamp",
      ".claude/ru-config.json",
      ".claude/ralph-state.json",
    ]
  ),
  deletion_patterns: v.optional(
    v.array(v.string()),
    [
      "\\brm\\b",
      "\\bunlink\\b",
      "> /dev/null",
      ">\\s*/dev/null",
      "truncate\\b",
    ]
  ),
  bypass_markers: v.optional(
    v.array(v.string()),
    [
      "RALPH_STOP_SCRIPT",
      "RALPH_START_SCRIPT",
      "RALPH_ENCOURAGE_SCRIPT",
      "RALPH_FORBID_SCRIPT",
      "RALPH_AUDIT_SCRIPT",
      "RALPH_STATUS_SCRIPT",
      "RALPH_HOOKS_SCRIPT",
    ]
  ),
  stop_script_marker: v.optional(v.string(), "RALPH_STOP_SCRIPT"),
});

/**
 * User guidance for Ralph (forbidden/encouraged items).
 * Populated by /ru:start AUQ flow or manual /ru:forbid /ru:encourage.
 */
export const GuidanceConfigSchema = v.object({
  forbidden: v.optional(
    v.pipe(
      v.unknown(),
      v.transform((input): string[] => {
        // Backwards compat: convert string to list if needed
        if (input === null || input === undefined) return [];
        if (typeof input === "string") return [input];
        if (Array.isArray(input)) return input.map(String);
        return [];
      })
    ),
    []
  ),
  encouraged: v.optional(
    v.pipe(
      v.unknown(),
      v.transform((input): string[] => {
        if (input === null || input === undefined) return [];
        if (typeof input === "string") return [input];
        if (Array.isArray(input)) return input.map(String);
        return [];
      })
    ),
    []
  ),
  timestamp: v.optional(v.string(), ""),
});

/**
 * Configuration for loop time/iteration limits.
 */
export const LoopLimitsConfigSchema = v.object({
  min_hours: v.optional(v.number(), 4.0),
  max_hours: v.optional(v.number(), 9.0),
  min_iterations: v.optional(v.number(), 50),
  max_iterations: v.optional(v.number(), 99),
  poc_min_hours: v.optional(v.number(), 0.083),
  poc_max_hours: v.optional(v.number(), 0.167),
  poc_min_iterations: v.optional(v.number(), 10),
  poc_max_iterations: v.optional(v.number(), 20),
  cli_gap_threshold_seconds: v.optional(v.number(), 300),
});

/**
 * Loop state enum values.
 */
export const LoopStateSchema = v.picklist(["stopped", "running", "draining"]);

/**
 * Unified Ralph configuration.
 * Central config for all Ralph hooks.
 */
export const RalphConfigSchema = v.object({
  // State (managed by hooks)
  state: v.optional(LoopStateSchema, "stopped"),

  // Sub-configurations (only include what's needed for TypeScript hooks)
  protection: v.optional(ProtectionConfigSchema, {}),
  guidance: v.optional(GuidanceConfigSchema, {}),
  loop_limits: v.optional(LoopLimitsConfigSchema, {}),

  // Session-specific
  target_file: v.optional(v.nullable(v.string()), null),
  task_prompt: v.optional(v.nullable(v.string()), null),
  no_focus: v.optional(v.boolean(), false),
  poc_mode: v.optional(v.boolean(), false),
  production_mode: v.optional(v.boolean(), false),

  // Metadata
  version: v.optional(v.string(), "3.0.0"),
});

// --- Inferred Types ---

export type ProtectionConfig = v.InferOutput<typeof ProtectionConfigSchema>;
export type GuidanceConfig = v.InferOutput<typeof GuidanceConfigSchema>;
export type LoopLimitsConfig = v.InferOutput<typeof LoopLimitsConfigSchema>;
export type LoopState = v.InferOutput<typeof LoopStateSchema>;
export type RalphConfig = v.InferOutput<typeof RalphConfigSchema>;

// --- Config Loading ---

/**
 * Get path to config file, preferring project-level.
 */
export function getConfigPath(projectDir?: string): string {
  if (projectDir) {
    const projectConfig = join(projectDir, ".claude/ru-config.json");
    if (existsSync(projectConfig)) {
      return projectConfig;
    }
  }

  // Fall back to global defaults
  const globalConfig = join(homedir(), ".claude/ralph-defaults.json");
  if (existsSync(globalConfig)) {
    return globalConfig;
  }

  // Return project path for creation (if projectDir provided)
  if (projectDir) {
    return join(projectDir, ".claude/ru-config.json");
  }

  return globalConfig;
}

/**
 * Load configuration from JSON file.
 *
 * Note: Unlike Python version, we skip filelock since:
 * 1. Bun/Node JSON reads are atomic for small files
 * 2. Our hooks are short-lived (create+parse-once pattern)
 * 3. Race conditions are rare and non-critical for read operations
 */
export function loadConfig(projectDir?: string): RalphConfig {
  const configPath = getConfigPath(projectDir);

  if (existsSync(configPath)) {
    try {
      const data = JSON.parse(readFileSync(configPath, "utf-8"));
      // Parse with Valibot - applies defaults for missing fields
      return v.parse(RalphConfigSchema, data);
    } catch (e) {
      console.error(
        `[ralph] Warning: Failed to parse config ${configPath}: ${e}`
      );
    }
  }

  // Return default config
  return v.parse(RalphConfigSchema, {});
}

// --- Exports for PreToolUse guard ---

export { v };
