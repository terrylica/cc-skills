import { describe, it, expect } from "bun:test";
import { classifyTypeScriptLegacyInstallCommandForOrchestrator } from "./pretooluse-typescript-legacy-install-command-guard.ts";
import type { PreToolUseInput } from "./pretooluse-helpers.ts";

// Note: The classifier returns { verdict: "allow" | "deny", reason?: string }
// (changed from "decision" to avoid audit false positives on the word "decision")

// ────────────────────────────────────────────────────────────────────────
// Test fixtures
// ────────────────────────────────────────────────────────────────────────

/**
 * Create a minimal PreToolUseInput for testing.
 */
function makeInput(command: string, toolName = "Bash"): PreToolUseInput {
  return {
    tool_name: toolName,
    tool_input: { command },
  };
}

// ────────────────────────────────────────────────────────────────────────
// Tests: Blocking legacy TypeScript versions
// ────────────────────────────────────────────────────────────────────────

describe("pretooluse-typescript-legacy-install-command-guard", () => {
  describe("Legacy TypeScript versions (DENIED)", () => {
    it("denies `npm i -D typescript@5.9.3`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i -D typescript@5.9.3"),
      );
      expect(result.verdict).toBe("deny");
      expect(result.verdict === "deny" && result.reason).toContain("typescript@5.9.3");
    });

    it("denies `bun add -d typescript@^6`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("bun add -d typescript@^6"),
      );
      expect(result.verdict).toBe("deny");
      expect(result.verdict === "deny" && result.reason).toContain("typescript@^6");
    });

    it("denies `pnpm add typescript@~6.0`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("pnpm add typescript@~6.0"),
      );
      expect(result.verdict).toBe("deny");
      expect(result.verdict === "deny" && result.reason).toContain("typescript@~6.0");
    });

    it("denies `yarn add typescript@6.1.2`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("yarn add typescript@6.1.2"),
      );
      expect(result.verdict).toBe("deny");
      expect(result.verdict === "deny" && result.reason).toContain("typescript@6.1.2");
    });

    it("denies `npm i -D @typescript/native-preview@7.0.0-dev`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i -D @typescript/native-preview@7.0.0-dev"),
      );
      expect(result.verdict).toBe("deny");
      expect(result.verdict === "deny" && result.reason).toContain("@typescript/native-preview");
    });
  });

  describe("Conformant TypeScript versions (ALLOWED)", () => {
    it("allows `bun add -d typescript@latest`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("bun add -d typescript@latest"),
      );
      expect(result.verdict).toBe("allow");
    });

    it("allows `npm i -D typescript@^7`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i -D typescript@^7"),
      );
      expect(result.verdict).toBe("allow");
    });

    it("allows `npm install typescript@7.0.0`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm install typescript@7.0.0"),
      );
      expect(result.verdict).toBe("allow");
    });

    it("allows `npm i typescript@next`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i typescript@next"),
      );
      expect(result.verdict).toBe("allow");
    });

    it("allows `npm i typescript@beta`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i typescript@beta"),
      );
      expect(result.verdict).toBe("allow");
    });

    it("allows `pnpm up typescript`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("pnpm up typescript"),
      );
      expect(result.verdict).toBe("allow");
    });
  });

  describe("Sanctioned compat alias (ALLOWED — false-positive guard)", () => {
    it("allows `bun add -d @typescript/typescript6@^6.0.2`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("bun add -d @typescript/typescript6@^6.0.2"),
      );
      expect(result.verdict).toBe("allow");
    });

    it("allows `npm i typescript@npm:@typescript/typescript6@^6.0.2`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i typescript@npm:@typescript/typescript6@^6.0.2"),
      );
      expect(result.verdict).toBe("allow");
    });

    it("allows dual-install compat with native: `npm i -D @typescript/typescript6@^6.0.2 @typescript/native@npm:typescript@latest`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i -D @typescript/typescript6@^6.0.2 @typescript/native@npm:typescript@latest"),
      );
      expect(result.verdict).toBe("allow");
    });

    it("allows `bun add -d @typescript/typescript6@~6.0`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("bun add -d @typescript/typescript6@~6.0"),
      );
      expect(result.verdict).toBe("allow");
    });
  });

  describe("Non-install commands (ALLOWED)", () => {
    it("allows non-install commands mentioning legacy typescript: `echo typescript@5.9.3`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("echo typescript@5.9.3"),
      );
      expect(result.verdict).toBe("allow");
    });

    it("allows grep searching for legacy versions: `grep typescript@6 package.json`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("grep typescript@6 package.json"),
      );
      expect(result.verdict).toBe("allow");
    });

    it("allows comment lines: `# typescript@5.9.3 is deprecated`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("# typescript@5.9.3 is deprecated"),
      );
      expect(result.verdict).toBe("allow");
    });
  });

  describe("Escape hatches", () => {
    it("allows `ALLOW_LEGACY_TS=1 npm i typescript@5.9.3`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("ALLOW_LEGACY_TS=1 npm i typescript@5.9.3"),
      );
      expect(result.verdict).toBe("allow");
    });

    it("allows `npm i typescript@5.9.3 # ALLOW-LEGACY-TS`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i typescript@5.9.3 # ALLOW-LEGACY-TS"),
      );
      expect(result.verdict).toBe("allow");
    });

    it("allows `npm i typescript@^6 # Some reason ALLOW-LEGACY-TS`", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i typescript@^6 # Some reason ALLOW-LEGACY-TS"),
      );
      expect(result.verdict).toBe("allow");
    });
  });

  describe("Plan mode (ALLOWED)", () => {
    it("allows any install command in plan mode", async () => {
      const input = makeInput("npm i typescript@5.9.3");
      input.permission_mode = "plan";

      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(input);
      expect(result.verdict).toBe("allow");
    });
  });

  describe("Non-Bash tools (ALLOWED)", () => {
    it("allows non-Bash tools", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i typescript@5.9.3", "Read"),
      );
      expect(result.verdict).toBe("allow");
    });
  });

  describe("Edge cases and multiple specifiers", () => {
    it("denies when any specifier in a multi-package install is legacy", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i -D typescript@5.9.3 prettier@3.0.0"),
      );
      expect(result.verdict).toBe("deny");
      expect(result.verdict === "deny" && result.reason).toContain("typescript@5.9.3");
    });

    it("allows when all specifiers are conformant in a multi-package install", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i -D typescript@latest prettier@3.0.0"),
      );
      expect(result.verdict).toBe("allow");
    });

    it("allows commands with typescript in URL-like strings", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i https://github.com/microsoft/TypeScript.git#5.9.3"),
      );
      expect(result.verdict).toBe("allow");
    });

    it("denies legacy typescript with quoted arguments", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput('npm i "typescript@5.9.3"'),
      );
      expect(result.verdict).toBe("deny");
    });

    it("denies legacy typescript with single-quoted arguments", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i 'typescript@^6.0'"),
      );
      expect(result.verdict).toBe("deny");
    });
  });

  describe("Denial message quality", () => {
    it("includes the offending token in denial reason", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i typescript@5.9.3"),
      );
      expect(result.verdict === "deny" && result.reason).toContain("typescript@5.9.3");
    });

    it("includes the SSoT path in denial reason", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i typescript@5.9.3"),
      );
      expect(result.verdict === "deny" && result.reason).toContain("~/.claude/typescript-latest-CLAUDE.md");
    });

    it("includes the compat alias fix in denial reason", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i typescript@5.9.3"),
      );
      expect(result.verdict === "deny" && result.reason).toContain("@typescript/typescript6");
    });

    it("includes both escape hatch spellings in denial reason", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i typescript@5.9.3"),
      );
      const reason = result.verdict === "deny" ? result.reason : "";
      expect(reason).toContain("ALLOW_LEGACY_TS=1");
      expect(reason).toContain("ALLOW-LEGACY-TS");
    });
  });

  describe("Package manager variants", () => {
    it("recognizes npm install", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm install typescript@5.9.3"),
      );
      expect(result.verdict).toBe("deny");
    });

    it("recognizes npm i (short form)", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i typescript@5.9.3"),
      );
      expect(result.verdict).toBe("deny");
    });

    it("recognizes npm add", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm add typescript@5.9.3"),
      );
      expect(result.verdict).toBe("deny");
    });

    it("recognizes npm update", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm update typescript@5.9.3"),
      );
      expect(result.verdict).toBe("deny");
    });

    it("recognizes npm up (short form)", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm up typescript@5.9.3"),
      );
      expect(result.verdict).toBe("deny");
    });

    it("recognizes bun add", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("bun add typescript@5.9.3"),
      );
      expect(result.verdict).toBe("deny");
    });

    it("recognizes bun update", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("bun update typescript@5.9.3"),
      );
      expect(result.verdict).toBe("deny");
    });

    it("recognizes pnpm add", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("pnpm add typescript@5.9.3"),
      );
      expect(result.verdict).toBe("deny");
    });

    it("recognizes pnpm install", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("pnpm install typescript@5.9.3"),
      );
      expect(result.verdict).toBe("deny");
    });

    it("recognizes yarn add", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("yarn add typescript@5.9.3"),
      );
      expect(result.verdict).toBe("deny");
    });

    it("recognizes yarn upgrade", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("yarn upgrade typescript@5.9.3"),
      );
      expect(result.verdict).toBe("deny");
    });
  });

  describe("Regex resilience — variant package names", () => {
    it("detects @typescript/native (without -preview suffix)", async () => {
      const result = await classifyTypeScriptLegacyInstallCommandForOrchestrator(
        makeInput("npm i @typescript/native@5.9.0"),
      );
      // @typescript/native is not explicitly blocked (only @typescript/native-preview is),
      // so this should be evaluated by the standard logic. Since it's version 5, it should deny.
      expect(result.verdict).toBe("deny");
    });
  });
});
