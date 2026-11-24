/**
 * Tests for posttooluse-ssot-principles.ts
 *
 * Run with: bun test plugins/itp-hooks/hooks/posttooluse-ssot-principles.test.ts
 *
 * Pins the 2026-11-15 evidence gate: the SSoT card fires only when ast-grep
 * finds an anti-pattern in the edited file. Before it, the first code file of
 * every session got the card even when the scan came back empty (operator
 * report, 2026-11-15, on a clean Cloudflare Worker redirect).
 *
 * Load-bearing assertions:
 *   1. A clean scan returns noop AND leaves the once-per-session gate
 *      unclaimed, so the first file with a real finding still gets the card.
 *   2. Extensions without ast-grep rules (.js, .tsx) are not scanned at all.
 */

import { afterAll, describe, expect, it } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { perUserGateDirectory } from "./lib/posttooluse-subhook-async-helpers-iter95.ts";
import type { PostToolUseInput } from "./lib/posttooluse-subhook-contract-iter93.ts";
import { classifySsotPrinciplesForPostToolUseOrchestrator as classify } from "./posttooluse-ssot-principles.ts";

const AST_GREP_AVAILABLE = Bun.which("ast-grep") !== null;

// Repo-local scratch (gitignored tmp/): system temp dirs are exempt from the
// classifier, so a fixture there could never exercise it.
const REPO_TMP = join(import.meta.dir, "..", "..", "..", "tmp");
mkdirSync(REPO_TMP, { recursive: true });
const FIXTURE_DIR = mkdtempSync(join(REPO_TMP, "ssot-test-"));
const GATE_DIR = perUserGateDirectory("/tmp/.claude-ssot-principles-reminder");

const RUN_NONCE = `${process.pid}-${Date.now()}`;
const usedSessionIds: string[] = [];
let sessionCounter = 0;
const freshSessionId = (): string => {
  const id = `ssot-test-${RUN_NONCE}-${++sessionCounter}`;
  usedSessionIds.push(id);
  return id;
};

afterAll(() => {
  rmSync(FIXTURE_DIR, { recursive: true, force: true });
  // Only this suite's gate files; wiping the directory would re-arm real sessions.
  for (const id of usedSessionIds) rmSync(join(GATE_DIR, `${id}.reminded`), { force: true });
});

function writeFixture(name: string, content: string, session_id: string): PostToolUseInput {
  const file_path = join(FIXTURE_DIR, name);
  writeFileSync(file_path, content);
  return { tool_name: "Write", session_id, tool_input: { file_path, content } } as PostToolUseInput;
}

const CLEAN_TS = `export function redirect(url: string, host: string): string {
  const u = new URL(url);
  u.hostname = host;
  return u.toString();
}
`;

const ENV_READING_TS = `export const apiBase = process.env.API_BASE;
`;

const ENV_READING_PY = `import os

def get_mode():
    return os.environ.get("MODE", "default")
`;

describe("ssot-principles evidence gate", () => {
  it.skipIf(!AST_GREP_AVAILABLE)("stays silent on a file ast-grep finds clean", async () => {
    const decision = await classify(writeFixture("clean.ts", CLEAN_TS, freshSessionId()));
    expect(decision.kind).toBe("noop");
  });

  it.skipIf(!AST_GREP_AVAILABLE)("does not spend the session's card on a clean file", async () => {
    const session = freshSessionId();
    expect((await classify(writeFixture("clean2.ts", CLEAN_TS, session))).kind).toBe("noop");
    const decision = await classify(writeFixture("config.ts", ENV_READING_TS, session));
    expect(decision.kind).toBe("additional_context");
    if (decision.kind !== "additional_context") return;
    expect(decision.message).toContain("DETECTED in current edit:");
    expect(decision.message).toContain("process.env.API_BASE");
  });

  it.skipIf(!AST_GREP_AVAILABLE)("fires on a Python env read, once per session", async () => {
    const session = freshSessionId();
    expect((await classify(writeFixture("mode.py", ENV_READING_PY, session))).kind).toBe("additional_context");
    expect((await classify(writeFixture("mode2.py", ENV_READING_PY, session))).kind).toBe("noop");
  });

  it("honors the SSoT-OK escape hatch in the new content", async () => {
    const content = `${ENV_READING_TS}// SSoT-OK: fixture\n`;
    const decision = await classify(writeFixture("escaped.ts", content, freshSessionId()));
    expect(decision.kind).toBe("noop");
  });

  it("does not scan extensions without ast-grep rules", async () => {
    for (const name of ["worker.js", "view.tsx", "App.java"]) {
      const decision = await classify(writeFixture(name, ENV_READING_TS, freshSessionId()));
      expect(decision.kind).toBe("noop");
    }
  });
});
