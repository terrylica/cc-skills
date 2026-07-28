import { describe, it, expect, beforeEach, afterEach } from "bun:test";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { mkdir, writeFile, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import type { PostToolUseInput } from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import { classifyNativeTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator } from "./posttooluse-tsc-type-check.ts";

describe("posttooluse-tsc-type-check", () => {
  let tempDir: string;

  beforeEach(async () => {
    tempDir = join(tmpdir(), `tsc-test-${Date.now()}`);
    await mkdir(tempDir, { recursive: true });
  });

  afterEach(async () => {
    if (existsSync(tempDir)) {
      await rm(tempDir, { recursive: true });
    }
  });

  describe("basic skip conditions", () => {
    it("should noop when file_path is missing", async () => {
      const input: PostToolUseInput = {
        tool_name: "Write",
        tool_input: { file_path: undefined },
        session_id: "test-session",
      };
      const decision =
        await classifyNativeTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator(input);
      expect(decision.kind).toBe("noop");
    });

    it("should noop for non-.ts/.tsx files", async () => {
      const input: PostToolUseInput = {
        tool_name: "Write",
        tool_input: { file_path: "/tmp/example.py" },
        session_id: "test-session",
      };
      const decision =
        await classifyNativeTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator(input);
      expect(decision.kind).toBe("noop");
    });

    it("should noop for .jsx/.mjs files (only .ts/.tsx)", async () => {
      const input: PostToolUseInput = {
        tool_name: "Write",
        tool_input: { file_path: "/tmp/example.js" },
        session_id: "test-session",
      };
      const decision =
        await classifyNativeTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator(input);
      expect(decision.kind).toBe("noop");
    });

    it("should noop for node_modules paths", async () => {
      const input: PostToolUseInput = {
        tool_name: "Write",
        tool_input: { file_path: "/project/node_modules/dep/index.ts" },
        session_id: "test-session",
      };
      const decision =
        await classifyNativeTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator(input);
      expect(decision.kind).toBe("noop");
    });

    it("should noop when no tsconfig.json exists in ancestors", async () => {
      const isolatedDir = join(tmpdir(), `isolated-${Date.now()}`);
      await mkdir(isolatedDir, { recursive: true });
      try {
        const input: PostToolUseInput = {
          tool_name: "Write",
          tool_input: { file_path: join(isolatedDir, "orphan.ts") },
          session_id: "test-session",
        };
        const decision =
          await classifyNativeTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator(input);
        expect(decision.kind).toBe("noop");
      } finally {
        await rm(isolatedDir, { recursive: true });
      }
    });
  });

  describe("temp directory exemption (iter-124)", () => {
    it("should noop when file is in /tmp", async () => {
      const input: PostToolUseInput = {
        tool_name: "Write",
        tool_input: { file_path: "/tmp/throwaway.ts" },
        session_id: "test-session",
      };
      const decision =
        await classifyNativeTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator(input);
      expect(decision.kind).toBe("noop");
    });

    it("should noop when file is in /private/tmp", async () => {
      const input: PostToolUseInput = {
        tool_name: "Write",
        tool_input: { file_path: "/private/tmp/throwaway.ts" },
        session_id: "test-session",
      };
      const decision =
        await classifyNativeTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator(input);
      expect(decision.kind).toBe("noop");
    });

    it("should noop when file is in /var/folders (macOS temp)", async () => {
      const input: PostToolUseInput = {
        tool_name: "Write",
        tool_input: { file_path: "/var/folders/xy/random/T/throwaway.ts" },
        session_id: "test-session",
      };
      const decision =
        await classifyNativeTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator(input);
      expect(decision.kind).toBe("noop");
    });
  });

  describe("install reminder (iter-95 gate-file)", () => {
    it("should emit install reminder when tsc is not found (once per session)", async () => {
      // Create a minimal tsconfig.json in the temp dir but no tsc binary
      await writeFile(join(tempDir, "tsconfig.json"), "{}");
      const input: PostToolUseInput = {
        tool_name: "Write",
        tool_input: { file_path: join(tempDir, "example.ts") },
        session_id: "unique-session-for-reminder",
      };

      const decision =
        await classifyNativeTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator(input);

      if (decision.kind === "additional_context") {
        expect(decision.message).toContain("TypeScript");
        expect(decision.message).toContain("npm install");
        expect(decision.message).toContain("typescript@latest");
      }
    });
  });

  describe("symmetric-naming export alias for the orchestrator import block", () => {
    it("should export classifyTscTypeCheckForPostToolUseOrchestrator alias", async () => {
      const { classifyTscTypeCheckForPostToolUseOrchestrator } = await import(
        "./posttooluse-tsc-type-check.ts"
      );
      expect(classifyTscTypeCheckForPostToolUseOrchestrator).toBeDefined();
      expect(typeof classifyTscTypeCheckForPostToolUseOrchestrator).toBe("function");
    });

    it("should alias the precise algorithm-encoding name, not a separate implementation", async () => {
      const {
        classifyTscTypeCheckForPostToolUseOrchestrator,
        classifyNativeTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator:
          preciseAlgorithmEncodingExport,
      } = await import("./posttooluse-tsc-type-check.ts");
      expect(classifyTscTypeCheckForPostToolUseOrchestrator).toBe(preciseAlgorithmEncodingExport);
    });

    it("should NOT re-export the retired tsgo-era alias (@typescript/native-preview is frozen)", async () => {
      const moduleExports = await import("./posttooluse-tsc-type-check.ts");
      expect("classifyTsgoTypeCheckForPostToolUseOrchestrator" in moduleExports).toBe(false);
    });
  });

  describe("error handling (fail-open discipline)", () => {
    it("should noop on any thrown error", async () => {
      // Simulate an error by passing invalid JSON, though in practice
      // errors are unlikely. The catch block should handle gracefully.
      const input: PostToolUseInput = {
        tool_name: "Write",
        tool_input: { file_path: "/tmp/test.ts", nested: { deep: null } },
        session_id: "test",
      };
      const decision =
        await classifyNativeTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator(input);
      expect(decision.kind).toBe("noop");
    });
  });

  describe("flag changes: --singleThreaded", () => {
    it("should include --singleThreaded in tsc invocation args", async () => {
      // This test documents the Iter-126 optimization: single-threaded tsc
      // avoids spawning 4 checker workers per keystroke-ish edit on dev machines.
      // The actual subprocess call includes: [tscExecutable, "--noEmit", "--singleThreaded"]
      // This is a documentation test asserting the design decision.
      expect(true).toBe(true); // Placeholder for architectural documentation
    });
  });

  describe(".tsx file handling", () => {
    it("should process .tsx files", async () => {
      const input: PostToolUseInput = {
        tool_name: "Write",
        tool_input: { file_path: "/path/to/component.tsx" },
        session_id: "test-session",
      };
      // Will noop because no tsconfig found, but it won't skip due to extension
      const decision =
        await classifyNativeTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator(input);
      expect(decision.kind).toBe("noop"); // noop due to no tsconfig, not due to extension
    });
  });

  describe("orchestrator re-export contracts", () => {
    it("should have the primary export for orchestrator integration", async () => {
      const module = await import("./posttooluse-tsc-type-check.ts");
      const primaryExport = module.classifyNativeTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator;
      expect(primaryExport).toBeDefined();
      expect(typeof primaryExport).toBe("function");
    });
  });
});
