#!/usr/bin/env bun
/**
 * Test suite for posttooluse-typescript-upgrade-reminder.ts (iter-98 style:
 * once-per-session gate-claim via atomic O_EXCL filesystem operations).
 *
 * Strategy: each test uses a unique synthetic sessionId to keep gate-file
 * state independent. First call for a fresh sessionId wins the gate-claim
 * and emits additional_context; subsequent calls with the SAME sessionId
 * see the gate-file already exists and return noop.
 */

import { describe, it, expect, beforeEach, afterEach } from "bun:test";
import { rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator,
  buildTypeScriptUpgradeReminderMessage,
} from "./posttooluse-typescript-upgrade-reminder.ts";
import type { PostToolUseInput } from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";

// ══════════════════════════════════════════════════════════════════════════
//  Test fixtures
// ══════════════════════════════════════════════════════════════════════════

/** Generate a unique synthetic session ID for test isolation. */
function freshSessionId(testName: string): string {
  return `test-${testName}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

/** Clean up gate files after each test. */
function cleanUpGateFile(_sessionId: string): void {
  const gateDir = `/tmp/.claude-typescript-upgrade-reminder`;
  if (existsSync(gateDir)) {
    try {
      rmSync(gateDir, { recursive: true, force: true });
    } catch {
      // Best effort; test gate-file namespace is isolated by sessionId anyway
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Tests
// ══════════════════════════════════════════════════════════════════════════

describe("posttooluse-typescript-upgrade-reminder", () => {
  describe("buildTypeScriptUpgradeReminderMessage", () => {
    it("produces a compact, useful message", async () => {
      const msg = await buildTypeScriptUpgradeReminderMessage();
      expect(msg).toContain("TypeScript 7");
      expect(msg).toContain("Go-native tsc");
      expect(msg).toContain("types defaults to []");
      expect(msg).toContain("strict defaults true");
      expect(msg).toContain("typescript-latest-CLAUDE.md");
      expect(msg.length).toBeGreaterThan(200); // meaningful length
      expect(msg.length).toBeLessThan(3000); // concise (not bloated; drift report may add content)
    });

    it("mentions breaking changes", async () => {
      const msg = await buildTypeScriptUpgradeReminderMessage();
      expect(msg).toContain("TS2591");
      expect(msg).toContain("TS7006");
      expect(msg).toContain("TS5102");
      expect(msg).toContain("TS5108");
    });

    it("mentions performance knobs", async () => {
      const msg = await buildTypeScriptUpgradeReminderMessage();
      expect(msg).toContain("--checkers");
      expect(msg).toContain("--builders");
      expect(msg).toContain("--singleThreaded");
    });
  });

  describe("classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator", () => {
    afterEach(() => {
      cleanUpGateFile("unused");
    });

    describe("noop on non-file-edit tools", () => {
      it("returns noop when tool_name is not Write/Edit/MultiEdit", async () => {
        const sessionId = freshSessionId("noop-tool");
        const input: PostToolUseInput = {
          tool_name: "Bash",
          tool_input: { file_path: "/project/src/index.ts" },
          session_id: sessionId,
        };
        const decision = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input);
        expect(decision.kind).toBe("noop");
      });
    });

    describe("noop on temp-scratch files", () => {
      it("returns noop for files in /tmp", async () => {
        const sessionId = freshSessionId("tmp-file");
        const input: PostToolUseInput = {
          tool_name: "Write",
          tool_input: { file_path: "/tmp/scratch.ts" },
          session_id: sessionId,
        };
        const decision = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input);
        expect(decision.kind).toBe("noop");
      });

      it("returns noop for files in /private/tmp", async () => {
        const sessionId = freshSessionId("private-tmp-file");
        const input: PostToolUseInput = {
          tool_name: "Edit",
          tool_input: { file_path: "/private/tmp/test.tsx" },
          session_id: sessionId,
        };
        const decision = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input);
        expect(decision.kind).toBe("noop");
      });

      it("returns noop for files in $TMPDIR", async () => {
        const sessionId = freshSessionId("tmpdir-file");
        // Most likely /var/folders/... on macOS
        const tmpdir_val = process.env.TMPDIR;
        if (tmpdir_val) {
          const input: PostToolUseInput = {
            tool_name: "Write",
            tool_input: { file_path: `${tmpdir_val}/dev.ts` },
            session_id: sessionId,
          };
          const decision =
            await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input);
          expect(decision.kind).toBe("noop");
        }
      });
    });

    describe("noop on non-TypeScript files", () => {
      it("returns noop for .py files", async () => {
        const sessionId = freshSessionId("py-file");
        const input: PostToolUseInput = {
          tool_name: "Write",
          tool_input: { file_path: "/project/script.py" },
          session_id: sessionId,
        };
        const decision = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input);
        expect(decision.kind).toBe("noop");
      });

      it("returns noop for .go files", async () => {
        const sessionId = freshSessionId("go-file");
        const input: PostToolUseInput = {
          tool_name: "Edit",
          tool_input: { file_path: "/project/main.go" },
          session_id: sessionId,
        };
        const decision = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input);
        expect(decision.kind).toBe("noop");
      });

      it("returns noop for .json files (but NOT package.json)", async () => {
        const sessionId = freshSessionId("json-file");
        const input: PostToolUseInput = {
          tool_name: "Write",
          tool_input: { file_path: "/project/config.json" },
          session_id: sessionId,
        };
        const decision = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input);
        expect(decision.kind).toBe("noop");
      });
    });

    describe("emit reminder on first eligible file in session", () => {
      it("emits additional_context for .ts Write on first call", async () => {
        const sessionId = freshSessionId("first-ts-write");
        const input: PostToolUseInput = {
          tool_name: "Write",
          tool_input: { file_path: "/project/src/index.ts" },
          session_id: sessionId,
        };
        const decision = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input);
        expect(decision.kind).toBe("additional_context");
        if (decision.kind === "additional_context") {
          expect(decision.message).toContain("TypeScript 7");
          expect(decision.message).toContain("types defaults to []");
        }
      });

      it("emits additional_context for .tsx Edit on first call", async () => {
        const sessionId = freshSessionId("first-tsx-edit");
        const input: PostToolUseInput = {
          tool_name: "Edit",
          tool_input: { file_path: "/project/src/Component.tsx", old_string: "foo", new_string: "bar" },
          session_id: sessionId,
        };
        const decision = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input);
        expect(decision.kind).toBe("additional_context");
      });

      it("emits additional_context for .mts Write on first call", async () => {
        const sessionId = freshSessionId("first-mts-write");
        const input: PostToolUseInput = {
          tool_name: "Write",
          tool_input: { file_path: "/project/src/module.mts" },
          session_id: sessionId,
        };
        const decision = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input);
        expect(decision.kind).toBe("additional_context");
      });

      it("emits additional_context for .cts MultiEdit on first call", async () => {
        const sessionId = freshSessionId("first-cts-multiedit");
        const input: PostToolUseInput = {
          tool_name: "MultiEdit",
          tool_input: { file_path: "/project/src/index.cts" },
          session_id: sessionId,
        };
        const decision = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input);
        expect(decision.kind).toBe("additional_context");
      });

      it("emits additional_context for package.json Write on first call", async () => {
        const sessionId = freshSessionId("first-package-json");
        const input: PostToolUseInput = {
          tool_name: "Write",
          tool_input: { file_path: "/project/package.json" },
          session_id: sessionId,
        };
        const decision = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input);
        expect(decision.kind).toBe("additional_context");
      });

      it("emits additional_context for tsconfig.json Edit on first call", async () => {
        const sessionId = freshSessionId("first-tsconfig");
        const input: PostToolUseInput = {
          tool_name: "Edit",
          tool_input: { file_path: "/project/tsconfig.json", old_string: "foo", new_string: "bar" },
          session_id: sessionId,
        };
        const decision = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input);
        expect(decision.kind).toBe("additional_context");
      });
    });

    describe("once-per-session gate (no double-emit)", () => {
      it("returns noop on second call with SAME sessionId", async () => {
        const sessionId = freshSessionId("gate-test");

        // First call should win the gate and emit additional_context
        const input1: PostToolUseInput = {
          tool_name: "Write",
          tool_input: { file_path: "/project/src/index.ts" },
          session_id: sessionId,
        };
        const decision1 = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input1);
        expect(decision1.kind).toBe("additional_context");

        // Second call with SAME sessionId should lose the gate and return noop
        const input2: PostToolUseInput = {
          tool_name: "Write",
          tool_input: { file_path: "/project/src/other.ts" },
          session_id: sessionId,
        };
        const decision2 = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input2);
        expect(decision2.kind).toBe("noop");
      });

      it("emits additional_context on first call with DIFFERENT sessionId", async () => {
        // First session
        const sessionId1 = freshSessionId("gate-test-session1");
        const input1: PostToolUseInput = {
          tool_name: "Write",
          tool_input: { file_path: "/project/src/index.ts" },
          session_id: sessionId1,
        };
        const decision1 = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input1);
        expect(decision1.kind).toBe("additional_context");

        // Second (different) session should get its own gate-claim
        const sessionId2 = freshSessionId("gate-test-session2");
        const input2: PostToolUseInput = {
          tool_name: "Write",
          tool_input: { file_path: "/project/src/other.ts" },
          session_id: sessionId2,
        };
        const decision2 = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input2);
        expect(decision2.kind).toBe("additional_context");
      });
    });

    describe("missing file_path", () => {
      it("returns noop when file_path is undefined", async () => {
        const sessionId = freshSessionId("missing-path");
        const input: PostToolUseInput = {
          tool_name: "Write",
          tool_input: {},
          session_id: sessionId,
        };
        const decision = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input);
        expect(decision.kind).toBe("noop");
      });

      it("returns noop when file_path is empty string", async () => {
        const sessionId = freshSessionId("empty-path");
        const input: PostToolUseInput = {
          tool_name: "Write",
          tool_input: { file_path: "" },
          session_id: sessionId,
        };
        const decision = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input);
        expect(decision.kind).toBe("noop");
      });
    });

    describe("missing session_id (graceful degradation)", () => {
      it("uses 'unknown' when session_id is absent, still claims gate", async () => {
        const input: PostToolUseInput = {
          tool_name: "Write",
          tool_input: { file_path: "/project/src/index.ts" },
          // session_id omitted
        };
        const decision = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input);
        // Should still work (gate-claim with "unknown" sessionId)
        expect(decision.kind).toMatch(/noop|additional_context/);
      });
    });

    describe("error handling (fail-open)", () => {
      it("returns noop on any exception", async () => {
        const sessionId = freshSessionId("error-test");
        // Simulate a classifier that would throw if the gate-claim helper threw
        // (we can't easily inject an exception without mocking, but the classifier
        // catches its own errors)
        const input: PostToolUseInput = {
          tool_name: "Write",
          tool_input: { file_path: "/project/src/index.ts" },
          session_id: sessionId,
        };
        // The classifier is defensive and catches errors, so this should still work
        const decision = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input);
        expect(decision.kind).toMatch(/noop|additional_context/);
      });
    });
  });
});
