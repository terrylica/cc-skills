/**
 * config.ts - Feature flag configuration for session registry
 *
 * Config file: ~/.claude/session-registry-config.json
 *
 * Supports deprecation mode for when Claude Code native feature is complete:
 * - active: Full functionality (default)
 * - readonly: Read registry but don't write (for testing native)
 * - disabled: Complete disable
 */

import { existsSync, readFileSync } from "fs";

const CONFIG_FILE = `${process.env.HOME}/.claude/session-registry-config.json`;

export interface Config {
  enabled: boolean;
  version: string;
  deprecationMode: "active" | "readonly" | "disabled";
}

const DEFAULT_CONFIG: Config = {
  enabled: true,
  version: "1.0.0",
  deprecationMode: "active",
};

/**
 * Load configuration from file or return defaults
 */
export function loadConfig(): Config {
  try {
    if (existsSync(CONFIG_FILE)) {
      const fileContent = readFileSync(CONFIG_FILE, "utf-8");
      const parsed = JSON.parse(fileContent) as Partial<Config>;
      return { ...DEFAULT_CONFIG, ...parsed };
    }
  } catch (e) {
    // Config file corrupted - log and use defaults
    console.error("[session-registry] Config load failed, using defaults:", e);
  }
  return DEFAULT_CONFIG;
}

/**
 * Check if registry writes are enabled
 */
export function isWriteEnabled(): boolean {
  const config = loadConfig();
  return config.enabled && config.deprecationMode === "active";
}

/**
 * Check if registry reads are enabled
 */
export function isReadEnabled(): boolean {
  const config = loadConfig();
  return config.enabled && config.deprecationMode !== "disabled";
}

/**
 * Get the current plugin version for provenance marker
 */
export function getPluginVersion(): string {
  const config = loadConfig();
  return `session-registry-plugin@${config.version}`;
}
