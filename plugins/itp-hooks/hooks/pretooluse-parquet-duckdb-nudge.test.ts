/**
 * Tests for pretooluse-parquet-duckdb-nudge.ts.
 *
 * Run with: bun test plugins/itp-hooks/hooks/pretooluse-parquet-duckdb-nudge.test.ts
 *
 * 2026-10-17: the nudge fired on every command that mentioned `.parquet` and ran sed or awk
 * anywhere (e.g. reading a Python loader with `sed -n`), and again on every read_parquet in the
 * same session. It now matches sed/awk only when a Parquet file is one of their operands, and it
 * speaks once per session.
 */

import { describe, expect, test } from "bun:test";
import { join } from "node:path";

import { findParquetAntiPattern, lineToolOnParquet } from "./pretooluse-parquet-duckdb-nudge.ts";

const HOOK_PATH = join(import.meta.dir, "pretooluse-parquet-duckdb-nudge.ts");

async function contextOf(command: string, sessionId: string): Promise<string | undefined> {
  const proc = Bun.spawn(["bun", HOOK_PATH], { stdin: "pipe", stdout: "pipe", stderr: "pipe" });
  proc.stdin.write(JSON.stringify({ tool_name: "Bash", tool_input: { command }, session_id: sessionId }));
  proc.stdin.end();
  const out = (await new Response(proc.stdout).text()).trim();
  await proc.exited;
  return out === "" ? undefined : JSON.parse(out).hookSpecificOutput?.additionalContext;
}

describe("what counts as using a line tool on Parquet", () => {
  test.each([
    ["sed -n 1,80p scripts/load.py && ls data/ticks_2025.parquet"],
    ["awk '{print $1}' notes.txt; du -sh lake/*.parquet"],
    ["grep -n read_parquet scripts/*.py | sed 's/:.*//'"],
    ["echo 'sed s/x/y/ data.parquet'"],
  ])("not a line tool on Parquet: %s", (command) => {
    expect(lineToolOnParquet(command)).toBeNull();
  });

  test.each([
    ["sed -n 1,5p data/ticks_2025.parquet", "sed"],
    ["awk -F, '{print $2}' lake/XAUUSD_2024.parquet", "awk"],
    ["cat x | sed -e s/a/b/ year=2025/week=1.parquet", "sed"],
  ])("line tool on Parquet: %s", (command, tool) => {
    expect(lineToolOnParquet(command)).toBe(tool);
  });

  test("python read_parquet is still a match (it is the preference the nudge is about)", () => {
    expect(findParquetAntiPattern(`python -c "import pandas as pd; pd.read_parquet('x.parquet')"`)?.name).toBe(
      "python read_parquet",
    );
  });
});

describe("once per session", () => {
  test("the first matching command nudges, the second in the same session does not", async () => {
    const session = `parquet-nudge-${process.pid}-${Date.now()}`;
    const command = "sed -n 1,5p data/ticks_2025.parquet";
    expect(await contextOf(command, session)).toContain("DuckDB");
    expect(await contextOf(command, session)).toBeUndefined();
  });

  test("a command that does not match never consumes the session's one nudge", async () => {
    const session = `parquet-nudge-unconsumed-${process.pid}-${Date.now()}`;
    expect(await contextOf("sed -n 1,80p scripts/load.py; ls data/x.parquet", session)).toBeUndefined();
    expect(await contextOf("sed -n 1,5p data/ticks_2025.parquet", session)).toContain("DuckDB");
  });
});
