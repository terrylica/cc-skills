#!/usr/bin/env bun
/**
 * PreToolUse hook: Enforce Polars preference over Pandas
 *
 * Detects Pandas usage in Write/Edit content and prompts for confirmation.
 * Uses permissionDecision: "ask" to show dialog before writing.
 *
 * Exception: # polars-exception: comment allows Pandas usage.
 *
 * ADR: 2026-01-22-polars-preference-hook (pending)
 */

import { basename } from "path";

// --- Types ---

interface HookInput {
  tool_name: string;
  tool_input: {
    file_path?: string;
    content?: string;
    new_string?: string;
    command?: string;
  };
}

// --- Constants ---

const PANDAS_EXCEPTION_PATHS = [
  "mlflow-python",
  "legacy/",
  "third-party/",
];

const PANDAS_PATTERNS = [
  /^import pandas/m,
  /^from pandas import/m,
  /\bimport pandas as pd\b/,
  /\bpd\.DataFrame\(/,
  /\bpd\.read_csv\(/,
  /\bpd\.read_parquet\(/,
  /\bpd\.concat\(/,
  /\bpd\.merge\(/,
];

// --- Detection ---

function hasPandasException(content: string): boolean {
  return /# polars-exception:/.test(content);
}

function isExceptionPath(filePath: string): boolean {
  return PANDAS_EXCEPTION_PATHS.some((p) => filePath.includes(p));
}

function hasPandasUsage(content: string): boolean {
  return PANDAS_PATTERNS.some((p) => p.test(content));
}

function hasPolarsImport(content: string): boolean {
  return /import polars|from polars import/.test(content);
}

function askWithReason(reason: string): void {
  console.log(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: reason,
      },
    })
  );
}

// --- Main ---

async function main(): Promise<void> {
  let inputText = "";
  for await (const chunk of Bun.stdin.stream()) {
    inputText += new TextDecoder().decode(chunk);
  }

  let input: HookInput;
  try {
    input = JSON.parse(inputText);
  } catch (err) {
    console.error(
      "[polars-preference] JSON parse error:",
      err instanceof Error ? err.message : String(err)
    );
    process.exit(0);
  }

  const toolName = input.tool_name || "";
  if (toolName !== "Write" && toolName !== "Edit") {
    process.exit(0);
  }

  const filePath = input.tool_input?.file_path || "";
  const content =
    input.tool_input?.content || input.tool_input?.new_string || "";

  // Only check Python files
  if (!filePath.endsWith(".py")) {
    process.exit(0);
  }

  // Skip exception paths
  if (isExceptionPath(filePath)) {
    process.exit(0);
  }

  // Skip if exception comment present
  if (hasPandasException(content)) {
    process.exit(0);
  }

  // Skip if Polars already imported (hybrid usage is intentional)
  if (hasPolarsImport(content)) {
    process.exit(0);
  }

  // Check for Pandas
  if (!hasPandasUsage(content)) {
    process.exit(0);
  }

  const fileName = basename(filePath);
  askWithReason(`[POLARS PREFERENCE] Pandas detected - consider using Polars instead.

DETECTED: Pandas import/usage in ${fileName}

═══════════════════════════════════════════════════════════════════
IF USER APPROVES PANDAS: Add this comment at the TOP of the file:

  # polars-exception: <reason why Pandas is needed>

Example reasons:
  # polars-exception: MLflow tracking requires Pandas DataFrames
  # polars-exception: pandas-ta library only accepts Pandas
  # polars-exception: upstream API returns Pandas DataFrame
═══════════════════════════════════════════════════════════════════

POLARS MIGRATION CHEATSHEET (if converting):
  pd.read_csv()     → pl.read_csv() / pl.scan_csv()
  pd.DataFrame()    → pl.DataFrame()
  df.groupby()      → df.group_by()
  pd.concat()       → pl.concat()
  df.merge()        → df.join()

WHY POLARS: 30x faster, lazy evaluation, better memory efficiency.

REFERENCE: https://docs.pola.rs/user-guide/migration/pandas/`);
  process.exit(0);
}

main().catch(() => process.exit(0));
