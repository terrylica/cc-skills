// ADR: docs/adr/2026-02-14-calcom-commander.md
/**
 * Configuration loader — reads Cal.com API key from 1Password.
 */

import { execSync } from "child_process";

export interface CalcomConfig {
  apiKey: string;
  apiUrl: string;
}

export async function loadConfig(): Promise<CalcomConfig> {
  const uuid = process.env.CALCOM_OP_UUID;
  if (!uuid) {
    throw new Error("CALCOM_OP_UUID environment variable not set");
  }

  // Read API key from 1Password
  const apiKey = execSync(`op item get "${uuid}" --fields label=credential --reveal`, {
    encoding: "utf-8",
  }).trim();

  if (!apiKey) {
    throw new Error("Failed to read API key from 1Password");
  }

  // Try to read API URL from same 1Password item, fall back to env
  let apiUrl = process.env.CALCOM_API_URL || "";
  if (!apiUrl) {
    try {
      apiUrl = execSync(`op item get "${uuid}" --fields label=api_url --reveal`, {
        encoding: "utf-8",
      }).trim();
    } catch {
      // Fall back to cal.com cloud
      apiUrl = "https://api.cal.com/v2";
    }
  }

  // Ensure URL ends with /v2
  if (!apiUrl.endsWith("/v2") && !apiUrl.endsWith("/api/v2")) {
    apiUrl = apiUrl.replace(/\/+$/, "") + "/api/v2";
  }

  return { apiKey, apiUrl };
}
