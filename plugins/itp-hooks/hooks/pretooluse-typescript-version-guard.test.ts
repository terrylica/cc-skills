#!/usr/bin/env bun
/**
 * Unit tests for pretooluse-typescript-version-guard.ts (iter-92)
 *
 * Coverage:
 *   - Denies legacy TypeScript versions in Write/Edit package.json
 *   - Allows "typescript": "latest" and other dist-tags
 *   - Allows the sanctioned @typescript/typescript6 dual-install alias
 *   - Allows non-package.json files containing the same text
 *   - Honors ALLOW-LEGACY-TS escape hatch (both proposed and on-disk)
 *   - Allows MultiEdit (staged-migration convention)
 *   - Allows plan mode
 *   - Skips node_modules paths
 */

import { describe, it, expect } from "bun:test";
import type { PreToolUseInput } from "./pretooluse-helpers.ts";
import { classifyTypeScriptVersionGuardForOrchestrator } from "./pretooluse-typescript-version-guard.ts";

// ============================================================================
// Test fixture helpers
// ============================================================================

function makePreToolUseInput(overrides: Partial<PreToolUseInput> = {}): PreToolUseInput {
  return {
    tool_name: "Write",
    tool_use_id: "test-id",
    tool_input: {},
    ...overrides,
  };
}

function makePackageJsonPayload(packageJsonFragment: string): PreToolUseInput {
  return makePreToolUseInput({
    tool_name: "Write",
    tool_input: {
      file_path: "/Users/test/my-project/package.json",
      content: packageJsonFragment,
    },
  });
}

function makeEditPayload(filePath: string, newString: string): PreToolUseInput {
  return makePreToolUseInput({
    tool_name: "Edit",
    tool_input: {
      file_path: filePath,
      new_string: newString,
    },
  });
}

// ============================================================================
// Test suite
// ============================================================================

describe("pretooluse-typescript-version-guard", () => {
  describe("denies legacy TypeScript versions", () => {
    it("should deny Write with legacy typescript@^5.6.0", async () => {
      const input = makePackageJsonPayload(
        JSON.stringify({
          devDependencies: {
            typescript: "^5.6.0",
          },
        })
      );

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("deny");
      expect(decision.reason).toContain("TypeScript 7.x");
      expect(decision.reason).toContain('"typescript": "^5.6.0"');
      expect(decision.reason).toContain("legacy");
    });

    it("should deny Write with typescript@5.9.3", async () => {
      const input = makePackageJsonPayload(
        '"typescript": "5.9.3",'
      );

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("deny");
      expect(decision.reason).toContain("5.9.3");
    });

    it("should deny Edit with bare fragment containing legacy version", async () => {
      const input = makeEditPayload(
        "/Users/test/project/package.json",
        '"typescript": "6.0.0",'
      );

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("deny");
      expect(decision.reason).toContain("6.0.0");
    });

    it("should deny Write with @typescript/native-preview (deprecated)", async () => {
      // Note: the actual payload must have unescaped quotes for the regex to match
      const input = makePreToolUseInput({
        tool_name: "Write",
        tool_input: {
          file_path: "/Users/test/my-project/package.json",
          content: `{"devDependencies": {"@typescript/native-preview": "^7.0.0-dev.20260707.2"}}`,
        },
      });

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("deny");
      expect(decision.reason).toContain("deprecated");
      expect(decision.reason).toContain("@typescript/native-preview");
    });
  });

  describe("allows conformant versions and dist-tags", () => {
    it("should allow typescript@latest", async () => {
      const input = makePackageJsonPayload(
        JSON.stringify({
          devDependencies: {
            typescript: "latest",
          },
        })
      );

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("allow");
    });

    it("should allow typescript@next", async () => {
      const input = makePackageJsonPayload(
        JSON.stringify({
          devDependencies: {
            typescript: "next",
          },
        })
      );

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("allow");
    });

    it("should allow typescript@^7.0.0", async () => {
      const input = makePackageJsonPayload(
        JSON.stringify({
          devDependencies: {
            typescript: "^7.0.0",
          },
        })
      );

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("allow");
    });

    it("should allow typescript@>=7.0.0", async () => {
      const input = makePackageJsonPayload(
        JSON.stringify({
          devDependencies: {
            typescript: ">=7.0.0",
          },
        })
      );

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("allow");
    });
  });

  describe("allows the sanctioned @typescript/typescript6 compat alias", () => {
    it("should allow dual-install pair (typescript6 + @typescript/native)", async () => {
      const input = makePackageJsonPayload(
        JSON.stringify({
          devDependencies: {
            "@typescript/native": "npm:typescript@latest",
            typescript: "npm:@typescript/typescript6@^6.0.2",
          },
        })
      );

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      // This is the critical false-positive test: the "6" in typescript6 must NOT
      // be misread as a legacy version
      expect(decision.kind).toBe("allow");
    });

    it("should allow single @typescript/typescript6 alias without @typescript/native", async () => {
      const input = makePackageJsonPayload(
        JSON.stringify({
          devDependencies: {
            typescript: "npm:@typescript/typescript6@^6.0.2",
          },
        })
      );

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("allow");
    });

    it("should allow Volar example: Astro + dual-install", async () => {
      const input = makePackageJsonPayload(
        JSON.stringify({
          devDependencies: {
            astro: "^4.0.0",
            "@typescript/native": "npm:typescript@latest",
            typescript: "npm:@typescript/typescript6@^6.0.2",
          },
        })
      );

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("allow");
    });
  });

  describe("file type and path filtering", () => {
    it("should allow non-package.json files containing the same text", async () => {
      const legacyText = '"typescript": "^5.6.0"';
      const input = makePreToolUseInput({
        tool_name: "Write",
        tool_input: {
          file_path: "/Users/test/README.md",
          content: `Here is an example package.json:\n${legacyText}`,
        },
      });

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("allow");
    });

    it("should skip package.json files under node_modules", async () => {
      const input = makePreToolUseInput({
        tool_name: "Write",
        tool_input: {
          file_path: "/Users/test/node_modules/my-package/package.json",
          content: JSON.stringify({
            devDependencies: {
              typescript: "^5.6.0",
            },
          }),
        },
      });

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("allow");
    });

    it("should allow non-Write/Edit tools", async () => {
      const input = makePreToolUseInput({
        tool_name: "Read",
        tool_input: {
          file_path: "/Users/test/package.json",
          content: JSON.stringify({
            devDependencies: {
              typescript: "^5.6.0",
            },
          }),
        },
      });

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("allow");
    });
  });

  describe("escape hatch: ALLOW-LEGACY-TS marker", () => {
    it("should allow Write when ALLOW-LEGACY-TS is in proposed content", async () => {
      const input = makePackageJsonPayload(
        JSON.stringify({
          devDependencies: {
            typescript: "^5.6.0", // Legacy
          },
        }) + "\n// ALLOW-LEGACY-TS"
      );

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("allow");
    });

    it("should allow Write when ALLOW-LEGACY-TS marker is anywhere in content", async () => {
      const input = makePackageJsonPayload(
        "// Legacy TypeScript allowed here - ALLOW-LEGACY-TS\n" +
        JSON.stringify({
          devDependencies: {
            typescript: "5.5.4",
          },
        })
      );

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("allow");
    });
  });

  describe("MultiEdit and plan mode", () => {
    it("should allow MultiEdit (staged-migration convention)", async () => {
      const input = makePreToolUseInput({
        tool_name: "MultiEdit",
        tool_input: {
          file_path: "/Users/test/package.json",
          content: JSON.stringify({
            devDependencies: {
              typescript: "^5.6.0",
            },
          }),
        },
      });

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("allow");
    });

    it("should allow plan mode", async () => {
      const input = makePreToolUseInput({
        tool_name: "Write",
        tool_input: {
          file_path: "/Users/test/package.json",
          content: JSON.stringify({
            devDependencies: {
              typescript: "^5.6.0",
            },
          }),
        },
        // Simulate plan mode by setting permission_mode
        permission_mode: "plan",
      });

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      // Should allow because plan mode is detected
      expect(decision.kind).toBe("allow");
    });
  });

  describe("package.json with no TypeScript dependency", () => {
    it("should allow package.json with no typescript dependency", async () => {
      const input = makePackageJsonPayload(
        JSON.stringify({
          devDependencies: {
            react: "^18.0.0",
            "react-dom": "^18.0.0",
          },
        })
      );

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("allow");
    });

    it("should allow empty package.json", async () => {
      const input = makePackageJsonPayload("{}");

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("allow");
    });
  });

  describe("edge cases", () => {
    it("should handle malformed JSON gracefully (no typescript found)", async () => {
      const input = makePackageJsonPayload("{ not valid json ");

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      // The regex-based finder won't match malformed JSON, so it finds nothing
      expect(decision.kind).toBe("allow");
    });

    it("should deny when multiple TypeScript dependencies are present and at least one blocks", async () => {
      const input = makePackageJsonPayload(
        JSON.stringify({
          devDependencies: {
            typescript: "^5.9.0",
            "@typescript/native": "npm:typescript@latest",
          },
        })
      );

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      // Should deny because typescript@^5.9.0 is legacy
      expect(decision.kind).toBe("deny");
      expect(decision.reason).toContain("5.9.0");
    });

    it("should allow when all TypeScript dependencies are conformant", async () => {
      const input = makePackageJsonPayload(
        JSON.stringify({
          devDependencies: {
            typescript: "^7.1.0",
            "@typescript/native": "npm:typescript@latest",
          },
        })
      );

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("allow");
    });
  });

  describe("unresolvable protocols (fail-open)", () => {
    it("should allow workspace: protocol (unresolvable)", async () => {
      const input = makePackageJsonPayload(
        JSON.stringify({
          devDependencies: {
            typescript: "workspace:*",
          },
        })
      );

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("allow");
    });

    it("should allow git: protocol (unresolvable)", async () => {
      const input = makePackageJsonPayload(
        JSON.stringify({
          devDependencies: {
            typescript: "git+https://github.com/microsoft/TypeScript.git#release-7.0",
          },
        })
      );

      const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

      expect(decision.kind).toBe("allow");
    });
  });
});
