/**
 * Tests for config-schema.ts (Valibot migration)
 *
 * Run with: bun test plugins/ru/hooks/core/config-schema.test.ts
 */

import { describe, expect, it, beforeEach, afterEach } from "bun:test";
import { mkdirSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { join } from "path";
import * as v from "valibot";
import {
  loadConfig,
  getConfigPath,
  RalphConfigSchema,
  ProtectionConfigSchema,
  GuidanceConfigSchema,
  LoopLimitsConfigSchema,
  LoopStateSchema,
} from "./config-schema";

const TMP_DIR = join(import.meta.dir, "test-tmp");

// --- Setup/Teardown ---

beforeEach(() => {
  mkdirSync(TMP_DIR, { recursive: true });
});

afterEach(() => {
  if (existsSync(TMP_DIR)) {
    rmSync(TMP_DIR, { recursive: true });
  }
});

// ============================================================================
// ProtectionConfig Schema Tests
// ============================================================================

describe("ProtectionConfigSchema", () => {
  it("should provide correct defaults", () => {
    const config = v.parse(ProtectionConfigSchema, {});
    expect(config.protected_files).toEqual([
      ".claude/loop-enabled",
      ".claude/loop-start-timestamp",
      ".claude/ru-config.json",
      ".claude/ralph-state.json",
    ]);
    expect(config.stop_script_marker).toBe("RALPH_STOP_SCRIPT");
    expect(config.bypass_markers).toContain("RALPH_STOP_SCRIPT");
    expect(config.bypass_markers).toContain("RALPH_ENCOURAGE_SCRIPT");
    expect(config.deletion_patterns.length).toBe(5);
  });

  it("should allow overriding protected_files", () => {
    const config = v.parse(ProtectionConfigSchema, {
      protected_files: [".claude/custom-file"],
    });
    expect(config.protected_files).toEqual([".claude/custom-file"]);
    // Other fields should still have defaults
    expect(config.stop_script_marker).toBe("RALPH_STOP_SCRIPT");
  });

  it("should allow adding bypass markers", () => {
    const config = v.parse(ProtectionConfigSchema, {
      bypass_markers: ["CUSTOM_MARKER"],
    });
    expect(config.bypass_markers).toEqual(["CUSTOM_MARKER"]);
  });
});

// ============================================================================
// GuidanceConfig Schema Tests
// ============================================================================

describe("GuidanceConfigSchema", () => {
  it("should provide empty defaults", () => {
    const config = v.parse(GuidanceConfigSchema, {});
    expect(config.forbidden).toEqual([]);
    expect(config.encouraged).toEqual([]);
    expect(config.timestamp).toBe("");
  });

  it("should convert string to array (backwards compat)", () => {
    const config = v.parse(GuidanceConfigSchema, {
      forbidden: "dependency upgrades",
      encouraged: "bug fixes",
    });
    expect(config.forbidden).toEqual(["dependency upgrades"]);
    expect(config.encouraged).toEqual(["bug fixes"]);
  });

  it("should handle null values", () => {
    const config = v.parse(GuidanceConfigSchema, {
      forbidden: null,
      encouraged: null,
    });
    expect(config.forbidden).toEqual([]);
    expect(config.encouraged).toEqual([]);
  });

  it("should handle arrays correctly", () => {
    const config = v.parse(GuidanceConfigSchema, {
      forbidden: ["deps", "formatting"],
      encouraged: ["tests", "docs"],
    });
    expect(config.forbidden).toEqual(["deps", "formatting"]);
    expect(config.encouraged).toEqual(["tests", "docs"]);
  });

  it("should convert non-string array items to strings", () => {
    const config = v.parse(GuidanceConfigSchema, {
      forbidden: [1, 2, 3],
      encouraged: [true, false],
    });
    expect(config.forbidden).toEqual(["1", "2", "3"]);
    expect(config.encouraged).toEqual(["true", "false"]);
  });
});

// ============================================================================
// LoopLimitsConfig Schema Tests
// ============================================================================

describe("LoopLimitsConfigSchema", () => {
  it("should provide correct defaults", () => {
    const config = v.parse(LoopLimitsConfigSchema, {});
    expect(config.min_hours).toBe(4.0);
    expect(config.max_hours).toBe(9.0);
    expect(config.min_iterations).toBe(50);
    expect(config.max_iterations).toBe(99);
    expect(config.poc_min_hours).toBe(0.083);
    expect(config.poc_max_hours).toBe(0.167);
    expect(config.cli_gap_threshold_seconds).toBe(300);
  });

  it("should allow partial overrides", () => {
    const config = v.parse(LoopLimitsConfigSchema, {
      max_hours: 12.0,
      max_iterations: 200,
    });
    expect(config.max_hours).toBe(12.0);
    expect(config.max_iterations).toBe(200);
    // Defaults for non-overridden
    expect(config.min_hours).toBe(4.0);
    expect(config.min_iterations).toBe(50);
  });
});

// ============================================================================
// LoopState Schema Tests
// ============================================================================

describe("LoopStateSchema", () => {
  it("should accept valid states", () => {
    expect(v.parse(LoopStateSchema, "stopped")).toBe("stopped");
    expect(v.parse(LoopStateSchema, "running")).toBe("running");
    expect(v.parse(LoopStateSchema, "draining")).toBe("draining");
  });

  it("should reject invalid states", () => {
    expect(() => v.parse(LoopStateSchema, "invalid")).toThrow();
    expect(() => v.parse(LoopStateSchema, "STOPPED")).toThrow();
    expect(() => v.parse(LoopStateSchema, "")).toThrow();
  });
});

// ============================================================================
// RalphConfig Schema Tests
// ============================================================================

describe("RalphConfigSchema", () => {
  it("should provide full defaults for empty object", () => {
    const config = v.parse(RalphConfigSchema, {});
    expect(config.state).toBe("stopped");
    expect(config.version).toBe("3.0.0");
    expect(config.poc_mode).toBe(false);
    expect(config.no_focus).toBe(false);
    expect(config.target_file).toBeNull();
    expect(config.protection.protected_files.length).toBe(4);
    expect(config.guidance.forbidden).toEqual([]);
  });

  it("should handle partial config", () => {
    const config = v.parse(RalphConfigSchema, {
      state: "running",
      poc_mode: true,
      guidance: {
        forbidden: ["deps"],
      },
    });
    expect(config.state).toBe("running");
    expect(config.poc_mode).toBe(true);
    expect(config.guidance.forbidden).toEqual(["deps"]);
    // Defaults preserved
    expect(config.version).toBe("3.0.0");
    expect(config.protection.protected_files.length).toBe(4);
  });

  it("should ignore extra fields (backwards compat)", () => {
    // Valibot strips unknown fields by default
    const config = v.parse(RalphConfigSchema, {
      state: "stopped",
      unknown_field: "should be ignored",
      another_unknown: 123,
    });
    expect(config.state).toBe("stopped");
    expect((config as any).unknown_field).toBeUndefined();
  });
});

// ============================================================================
// loadConfig Function Tests
// ============================================================================

describe("loadConfig", () => {
  it("should return defaults for non-existent project", () => {
    const config = loadConfig("/nonexistent/project");
    expect(config.state).toBe("stopped");
    expect(config.protection.protected_files.length).toBe(4);
  });

  it("should load config from project directory", () => {
    // Create test config
    const projectDir = join(TMP_DIR, "test-project");
    const claudeDir = join(projectDir, ".claude");
    mkdirSync(claudeDir, { recursive: true });
    writeFileSync(
      join(claudeDir, "ru-config.json"),
      JSON.stringify({
        state: "running",
        guidance: { forbidden: ["test-forbidden"] },
      })
    );

    const config = loadConfig(projectDir);
    expect(config.state).toBe("running");
    expect(config.guidance.forbidden).toEqual(["test-forbidden"]);
  });

  it("should handle malformed JSON gracefully", () => {
    const projectDir = join(TMP_DIR, "malformed-project");
    const claudeDir = join(projectDir, ".claude");
    mkdirSync(claudeDir, { recursive: true });
    writeFileSync(join(claudeDir, "ru-config.json"), "{ invalid json }");

    // Should return defaults, not throw
    const config = loadConfig(projectDir);
    expect(config.state).toBe("stopped");
  });
});

// ============================================================================
// getConfigPath Function Tests
// ============================================================================

describe("getConfigPath", () => {
  it("should return project config path when it exists", () => {
    const projectDir = join(TMP_DIR, "path-test");
    const claudeDir = join(projectDir, ".claude");
    mkdirSync(claudeDir, { recursive: true });
    writeFileSync(join(claudeDir, "ru-config.json"), "{}");

    const path = getConfigPath(projectDir);
    expect(path).toBe(join(projectDir, ".claude/ru-config.json"));
  });

  it("should return project path for creation when file doesn't exist", () => {
    const projectDir = join(TMP_DIR, "new-project");
    const path = getConfigPath(projectDir);
    expect(path).toBe(join(projectDir, ".claude/ru-config.json"));
  });
});
