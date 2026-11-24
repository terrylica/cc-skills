/**
 * Tests for posttooluse-memory-efficiency-reminder.ts
 *
 * Run with: bun test plugins/itp-hooks/hooks/posttooluse-memory-efficiency-reminder.test.ts
 *
 * Pins the 2026-11-15 scope fix: the card fires only on data-path code. Before
 * it, the first code file of any session got it, and the operator reported it
 * on a 35-line Cloudflare Worker that only redirects requests. That Worker is
 * the first negative fixture below, verbatim.
 *
 * Load-bearing assertions:
 *   1. No evidence, no card: ordinary service code returns noop.
 *   2. No evidence, no gate claim: a misfire would spend the session's only
 *      reminder, so the first real data-path file after a non-data-path edit
 *      must still get the card.
 *   3. The evidence comes from the post-edit file on disk, so an Edit whose
 *      new_string has no imports still counts when the file imports pandas.
 */

import { afterAll, describe, expect, it } from "bun:test";
import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { perUserGateDirectory } from "./lib/posttooluse-subhook-async-helpers-iter95.ts";
import type { PostToolUseInput } from "./lib/posttooluse-subhook-contract-iter93.ts";
import {
  classifyMemoryEfficiencyReminderForPostToolUseOrchestrator as classify,
  detectDataPathEvidenceInSourceText,
} from "./posttooluse-memory-efficiency-reminder.ts";

// Repo-local scratch (gitignored tmp/): the iter-124 helper exempts system
// temp dirs, so a fixture there could never exercise the classifier.
const REPO_TMP = join(import.meta.dir, "..", "..", "..", "tmp");
mkdirSync(REPO_TMP, { recursive: true });
const FIXTURE_DIR = mkdtempSync(join(REPO_TMP, "memeff-test-"));
const GATE_DIR = perUserGateDirectory("/tmp/.claude-memory-efficiency-reminder");

const RUN_NONCE = `${process.pid}-${Date.now()}`;
const usedSessionIds: string[] = [];
let sessionCounter = 0;
const freshSessionId = (): string => {
  const id = `memeff-test-${RUN_NONCE}-${++sessionCounter}`;
  usedSessionIds.push(id);
  return id;
};

afterAll(() => {
  rmSync(FIXTURE_DIR, { recursive: true, force: true });
  // Remove only this suite's gate files; wiping the directory would re-arm
  // the reminder for real sessions running on this machine.
  for (const id of usedSessionIds) rmSync(join(GATE_DIR, `${id}.reminded`), { force: true });
});

/** Write `content` to the fixture dir and build the matching Write payload. */
function writeFixture(name: string, content: string, session_id: string): PostToolUseInput {
  const file_path = join(FIXTURE_DIR, name);
  writeFileSync(file_path, content);
  return { tool_name: "Write", session_id, tool_input: { file_path, content } } as PostToolUseInput;
}

// The file that triggered the 2026-11-15 report, verbatim.
const REDIRECT_WORKER = `export const HEADERS = {
  "X-Robots-Tag": "noindex, nofollow, noarchive, nosnippet, noimageindex, notranslate, noai, noimageai",
  "Referrer-Policy": "no-referrer",
  "Cache-Control": "max-age=3600",
};
const HOST_RE = /^[a-z0-9-]+(\\.[a-z0-9-]+)+$/;

/** The redirect for a request: [status, location], or null when TARGET_HOST is missing or malformed. */
export function redirect(method, url, host) {
  if (typeof host !== "string" || !HOST_RE.test(host)) return null;
  const u = new URL(url);
  u.protocol = "https:";
  u.hostname = host;
  u.port = "";
  return [method === "GET" || method === "HEAD" ? 301 : 308, u.toString()];
}

export default {
  fetch(request, env) {
    const r = redirect(request.method, request.url, env.TARGET_HOST);
    if (!r) return new Response("Not found\\n", { status: 404, headers: { ...HEADERS, "Content-Type": "text/plain" } });
    return new Response(null, { status: r[0], headers: { ...HEADERS, Location: r[1] } });
  },
};
`;

const POLARS_SCRIPT = `import polars as pl

def load(path: str) -> pl.LazyFrame:
    return pl.scan_parquet(path).filter(pl.col("bid") > 0)
`;

describe("detectDataPathEvidenceInSourceText", () => {
  const positives: Array<[string, string]> = [
    ["import polars as pl", "dataframe, array or columnar library"],
    ["import pandas as pd\ndf = pd.read_csv(p)", "dataframe, array or columnar library"],
    ["import numpy as np", "dataframe, array or columnar library"],
    ["import pyarrow as pa", "dataframe, array or columnar library"],
    ["use ndarray::Array2;", "dataframe, array or columnar library"],
    ['import { tableFromIPC } from "apache-arrow";', "Apache Arrow"],
    ["use arrow::array::Float64Array;", "Apache Arrow"],
    ['import "github.com/apache/arrow/go/v17/arrow"', "Apache Arrow"],
    ['const rows = await readParquet("ticks.parquet");', "Parquet"],
    ['import { createClient } from "@clickhouse/client";', "ClickHouse"],
    ["const prices = new Float64Array(n);", "numeric typed array"],
    ["let xs: Vec<f64> = Vec::new();", "numeric vector or slice"],
    ["func mean(xs []float64) float64 {", "numeric vector or slice"],
    ["std::vector<double> prices;", "numeric vector or slice"],
    ["import mmap", "memory map, raw copy or binary unpacking"],
    ["memcpy(dst, src, n);", "memory map, raw copy or binary unpacking"],
    ["vals = struct.unpack('<d', raw)", "memory map, raw copy or binary unpacking"],
    ["buf = malloc(n * sizeof(double));", "manual allocation"],
    ["import torch", "tensor library"],
    ["for row in csv.DictReader(fh):", "bulk CSV reader or writer"],
    // PR #104 review, item 3: data-path code the list missed.
    ["from scipy import stats", "dataframe, array or columnar library"],
    ["from sklearn.linear_model import Ridge", "dataframe, array or columnar library"],
    ['import pl from "nodejs-polars";', "dataframe, array or columnar library"],
    ['const duckdb = require("duckdb");', "dataframe, array or columnar library"],
    ['import { DuckDBInstance } from "@duckdb/node-api";', "dataframe, array or columnar library"],
    ['import "gonum.org/v1/gonum/mat"', "dataframe, array or columnar library"],
    ['import * as tf from "@tensorflow/tfjs";', "tensor library"],
    ['import "encoding/csv"', "bulk CSV reader or writer"],
    ["let mut rdr = csv::Reader::from_path(p)?;", "bulk CSV reader or writer"],
  ];
  for (const [text, signal] of positives) {
    it(`finds ${signal} in: ${text}`, () => {
      expect(detectDataPathEvidenceInSourceText(text)).toBe(signal);
    });
  }

  const negatives: string[] = [
    REDIRECT_WORKER,
    // Workers hash and encode with Uint8Array/ArrayBuffer; that is not a data path.
    "const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)));",
    "const buf: ArrayBuffer = await request.arrayBuffer();",
    "const add = (a, b) => a + b; // an arrow function",
    "let bytes: Vec<u8> = body.to_vec();",
    "def get_mode():\n    return os.environ.get('MODE', 'default')",
    "fn main() { println!(\"hello\"); }",
    "# we used to import torch here, now gone",
    // PR #104 review, item 2: a library's name in prose is not an import.
    "# No pandas here, just config",
    "// polars would be overkill for a lookup table",
    'const label = "numpy-style docstrings";',
    '"""Mirrors the pandas API without importing it."""',
  ];
  for (const text of negatives) {
    it(`finds nothing in: ${text.split("\n")[0].slice(0, 70)}`, () => {
      expect(detectDataPathEvidenceInSourceText(text)).toBeNull();
    });
  }
});

describe("evidence check stays linear (PR #104 review)", () => {
  it("a file of blank lines up to the read cap is checked in well under a frame", () => {
    // \s at a line start also matched newlines, which made the tensor pattern quadratic: 3.3 s on 65,536 blank lines.
    const t0 = performance.now();
    expect(detectDataPathEvidenceInSourceText("\n".repeat(262_144))).toBeNull();
    expect(performance.now() - t0).toBeLessThan(50);
  });
  it("the tensor import is still found after blank lines and indentation", () => {
    expect(detectDataPathEvidenceInSourceText("\n\n  import torch\n")).not.toBeNull();
    expect(detectDataPathEvidenceInSourceText("# import torch\n")).toBeNull();
  });
});

describe("classifier", () => {
  it("stays silent on the redirect Worker that triggered the 2026-11-15 report", async () => {
    const decision = await classify(writeFixture("redirect.js", REDIRECT_WORKER, freshSessionId()));
    expect(decision.kind).toBe("noop");
  });

  it("does not spend the session's reminder on code without evidence", async () => {
    const session = freshSessionId();
    expect((await classify(writeFixture("worker.js", REDIRECT_WORKER, session))).kind).toBe("noop");
    const decision = await classify(writeFixture("load.py", POLARS_SCRIPT, session));
    expect(decision.kind).toBe("additional_context");
  });

  it("fires on data-path code and names the file and the signal", async () => {
    const decision = await classify(writeFixture("load2.py", POLARS_SCRIPT, freshSessionId()));
    expect(decision.kind).toBe("additional_context");
    if (decision.kind !== "additional_context") return;
    expect(decision.message).toStartWith("[MEMORY-EFFICIENCY]");
    expect(decision.message).toContain("load2.py contains data-path code (dataframe, array or columnar library)");
  });

  it("fires at most once per session", async () => {
    const session = freshSessionId();
    expect((await classify(writeFixture("a.py", POLARS_SCRIPT, session))).kind).toBe("additional_context");
    expect((await classify(writeFixture("b.py", POLARS_SCRIPT, session))).kind).toBe("noop");
  });

  it("reads the post-edit file, so an Edit without imports in new_string still counts", async () => {
    const file_path = join(FIXTURE_DIR, "edit.py");
    writeFileSync(file_path, "import pandas as pd\n\ndef total(df):\n    return df['qty'].sum()\n");
    const decision = await classify({
      tool_name: "Edit",
      session_id: freshSessionId(),
      tool_input: { file_path, old_string: "sum()", new_string: "sum()" },
    } as PostToolUseInput);
    expect(decision.kind).toBe("additional_context");
  });

  it("skips test files even when they are data-path code", async () => {
    const decision = await classify(writeFixture("test_load.py", POLARS_SCRIPT, freshSessionId()));
    expect(decision.kind).toBe("noop");
  });

  // PR #104 review, item 5: branches with no test.
  it("falls back to the tool input when the file is gone from disk", async () => {
    const file_path = join(FIXTURE_DIR, "deleted.py");
    const decision = await classify({
      tool_name: "Write",
      session_id: freshSessionId(),
      tool_input: { file_path, content: POLARS_SCRIPT },
    } as PostToolUseInput);
    expect(decision.kind).toBe("additional_context");
  });

  it("falls back to the tool input when the file cannot be read", async () => {
    const input = writeFixture("unreadable.py", POLARS_SCRIPT, freshSessionId());
    chmodSync(String(input.tool_input?.file_path), 0o000);
    try {
      expect((await classify(input)).kind).toBe("additional_context");
    } finally {
      chmodSync(String(input.tool_input?.file_path), 0o644);
    }
  });

  for (const ext of [".mts", ".cts", ".mjs", ".cjs", ".jsx"]) {
    it(`treats ${ext} as code`, async () => {
      const decision = await classify(writeFixture(`load${ext}`, 'import pl from "nodejs-polars";\n', freshSessionId()));
      expect(decision.kind).toBe("additional_context");
    });
  }

  it("ignores extensions outside the code set", async () => {
    const decision = await classify(writeFixture("notes.md", "import polars as pl\n", freshSessionId()));
    expect(decision.kind).toBe("noop");
  });
});
