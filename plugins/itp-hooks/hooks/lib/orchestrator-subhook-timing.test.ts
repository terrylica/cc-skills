import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  SUBHOOK_TIMING_KEYS,
  recordSubhookTiming,
  resetTimingWindowCache,
  sanitizeSubhookTimingRecord,
  timingWindowOpen,
} from "./orchestrator-subhook-timing.ts";

let dir: string;
const DAY_MS = 86_400_000;

function openWindow(untilMs: number): void {
  writeFileSync(join(dir, "timing-window.json"), JSON.stringify({ until: new Date(untilMs).toISOString() }));
}

function timingLines(): Record<string, unknown>[] {
  const files = readdirSync(dir).filter((f) => f.startsWith("timing-") && f.endsWith(".jsonl"));
  return files.flatMap((f) =>
    readFileSync(join(dir, f), "utf8")
      .split("\n")
      .filter(Boolean)
      .map((l) => JSON.parse(l) as Record<string, unknown>),
  );
}

const sample = {
  orchestrator: "pretooluse-bash-guard-orchestrator",
  event: "PreToolUse",
  subhook: "pretooluse-git-worktree-guard",
  toolName: "Bash",
  toolUseId: "toolu_01",
  sessionId: "sess-1",
  elapsedMs: 3.14,
  verdict: "allow" as const,
  timedOut: false,
  errored: false,
};

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "subhook-timing-test-"));
  resetTimingWindowCache();
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
  resetTimingWindowCache();
});

describe("timing window", () => {
  test("closed when the flag file is absent", () => {
    expect(timingWindowOpen(dir)).toBe(false);
  });

  test("closed when until is in the past", () => {
    openWindow(Date.now() - DAY_MS);
    expect(timingWindowOpen(dir)).toBe(false);
  });

  test("closed when the flag file is malformed", () => {
    writeFileSync(join(dir, "timing-window.json"), "not json");
    expect(timingWindowOpen(dir)).toBe(false);
  });

  test("open when until is in the future", () => {
    openWindow(Date.now() + DAY_MS);
    expect(timingWindowOpen(dir)).toBe(true);
  });
});

describe("recordSubhookTiming", () => {
  test("writes nothing while the window is closed", () => {
    recordSubhookTiming(sample, dir);
    expect(timingLines()).toEqual([]);
  });

  test("writes nothing after the window has expired", () => {
    openWindow(Date.now() - 1000);
    recordSubhookTiming(sample, dir);
    expect(timingLines()).toEqual([]);
  });

  test("writes one line per call inside an open window", () => {
    openWindow(Date.now() + DAY_MS);
    recordSubhookTiming(sample, dir);
    recordSubhookTiming({ ...sample, subhook: "pretooluse-old-git-guard", verdict: "deny" }, dir);
    const lines = timingLines();
    expect(lines).toHaveLength(2);
    expect(lines[0]?.subhook).toBe("pretooluse-git-worktree-guard");
    expect(lines[0]?.elapsedMs).toBe(3.1);
    expect(lines[1]?.verdict).toBe("deny");
  });

  test("never writes a key outside the allowed list, whatever the caller passes", () => {
    openWindow(Date.now() + DAY_MS);
    const withPayload = { ...sample, command: "rm -rf /secret", tool_input: { content: "token" } };
    recordSubhookTiming(withPayload as unknown as typeof sample, dir);
    const allowed = new Set<string>(["ts", ...SUBHOOK_TIMING_KEYS]);
    for (const line of timingLines()) {
      for (const key of Object.keys(line)) expect(allowed.has(key)).toBe(true);
      expect(JSON.stringify(line)).not.toContain("secret");
    }
  });

  test("fails open when the directory cannot be written", () => {
    openWindow(Date.now() + DAY_MS);
    const blocker = join(dir, "not-a-dir");
    writeFileSync(blocker, "x");
    writeFileSync(join(dir, "timing-window.json"), JSON.stringify({ until: new Date(Date.now() + DAY_MS).toISOString() }));
    resetTimingWindowCache();
    expect(() => recordSubhookTiming(sample, join(blocker, "nested"))).not.toThrow();
    expect(existsSync(join(blocker, "nested"))).toBe(false);
  });
});

describe("sanitizeSubhookTimingRecord", () => {
  test("drops non-finite durations and wrong-typed flags, caps long strings", () => {
    const out = sanitizeSubhookTimingRecord({
      ...sample,
      elapsedMs: Number.NaN,
      timedOut: "yes" as unknown as boolean,
      subhook: "x".repeat(500),
    });
    expect(out.elapsedMs).toBeUndefined();
    expect(out.timedOut).toBeUndefined();
    expect(String(out.subhook)).toHaveLength(120);
  });
});
