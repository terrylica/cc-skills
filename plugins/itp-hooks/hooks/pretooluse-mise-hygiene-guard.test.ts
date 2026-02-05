/**
 * Unit tests for pretooluse-mise-hygiene-guard.ts
 *
 * Tests:
 * - Secrets detection (hardcoded vs safe patterns)
 * - Line count threshold
 * - File targeting (mise.toml vs mise.local.toml)
 * - Plan mode bypass
 *
 * ADR: /docs/adr/2026-02-05-mise-hygiene-guard.md
 */

import { describe, expect, it } from "bun:test";
import { spawn } from "bun";

const HOOK_PATH = import.meta.dir + "/pretooluse-mise-hygiene-guard.ts";

interface HookResponse {
  hookSpecificOutput: {
    hookEventName: string;
    permissionDecision: "allow" | "deny" | "ask";
    permissionDecisionReason?: string;
  };
}

async function runHook(input: object): Promise<HookResponse> {
  const proc = spawn({
    cmd: ["bun", "run", "--bun", HOOK_PATH],
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });

  proc.stdin.write(JSON.stringify(input));
  proc.stdin.end();

  const output = await new Response(proc.stdout).text();
  await proc.exited;

  // Parse the last line of output (in case there are debug logs)
  const lines = output.trim().split("\n");
  const lastLine = lines[lines.length - 1];
  return JSON.parse(lastLine);
}

describe("pretooluse-mise-hygiene-guard", () => {
  describe("file targeting", () => {
    it("should check mise.toml", async () => {
      const result = await runHook({
        tool_name: "Write",
        tool_input: {
          file_path: "/project/mise.toml",
          content: "[env]\nVAR = \"value\"",
        },
      });
      expect(result.hookSpecificOutput.permissionDecision).toBe("allow");
    });

    it("should check .mise.toml", async () => {
      const result = await runHook({
        tool_name: "Write",
        tool_input: {
          file_path: "/project/.mise.toml",
          content: "[env]\nVAR = \"value\"",
        },
      });
      expect(result.hookSpecificOutput.permissionDecision).toBe("allow");
    });

    it("should ignore mise.local.toml (secrets allowed)", async () => {
      const result = await runHook({
        tool_name: "Write",
        tool_input: {
          file_path: "/project/mise.local.toml",
          content: '[env]\nAPI_KEY = "sk-secret123"',
        },
      });
      expect(result.hookSpecificOutput.permissionDecision).toBe("allow");
    });

    it("should ignore .mise.local.toml (secrets allowed)", async () => {
      const result = await runHook({
        tool_name: "Write",
        tool_input: {
          file_path: "/project/.mise.local.toml",
          content: '[env]\nPASSWORD = "hunter2"',
        },
      });
      expect(result.hookSpecificOutput.permissionDecision).toBe("allow");
    });

    it("should ignore non-mise files", async () => {
      const result = await runHook({
        tool_name: "Write",
        tool_input: {
          file_path: "/project/config.toml",
          content: '[env]\nAPI_KEY = "sk-secret123"',
        },
      });
      expect(result.hookSpecificOutput.permissionDecision).toBe("allow");
    });
  });

  describe("secrets detection", () => {
    const secretPatterns = [
      { name: "api_key", content: 'API_KEY = "sk-12345"' },
      { name: "secret_key", content: 'SECRET_KEY = "abc123"' },
      { name: "access_token", content: 'ACCESS_TOKEN = "token123"' },
      { name: "auth_token", content: 'AUTH_TOKEN = "authxyz"' },
      { name: "password", content: 'PASSWORD = "hunter2"' },
      { name: "gh_token", content: 'GH_TOKEN = "ghp_abc123"' },
      { name: "github_token", content: 'GITHUB_TOKEN = "ghp_xyz"' },
      { name: "npm_token", content: 'NPM_TOKEN = "npm_abc"' },
      { name: "aws_access_key", content: 'AWS_ACCESS_KEY = "AKIA..."' },
      { name: "database_password", content: 'DATABASE_PASSWORD = "dbpass"' },
      { name: "private_key", content: 'PRIVATE_KEY = "-----BEGIN"' },
      { name: "encryption_key", content: 'ENCRYPTION_KEY = "enc123"' },
    ];

    for (const { name, content } of secretPatterns) {
      it(`should block hardcoded ${name}`, async () => {
        const result = await runHook({
          tool_name: "Write",
          tool_input: {
            file_path: "/project/mise.toml",
            content: `[env]\n${content}`,
          },
        });
        expect(result.hookSpecificOutput.permissionDecision).toBe("deny");
        expect(result.hookSpecificOutput.permissionDecisionReason).toContain(
          "Secrets detected"
        );
      });
    }

    it("should allow comments containing secret keywords", async () => {
      const result = await runHook({
        tool_name: "Write",
        tool_input: {
          file_path: "/project/mise.toml",
          content: '[env]\n# API_KEY should be in mise.local.toml\nVAR = "value"',
        },
      });
      expect(result.hookSpecificOutput.permissionDecision).toBe("allow");
    });
  });

  describe("safe patterns (external references)", () => {
    const safePatterns = [
      {
        name: "read_file",
        content:
          "GH_TOKEN = \"{{ read_file(path=env.HOME ~ '/.secrets/token') | trim }}\"",
      },
      {
        name: "env reference",
        content: 'API_KEY = "{{ env.MY_SECRET }}"',
      },
      {
        name: "get_env",
        content: "SECRET = \"{{ get_env(name='MY_SECRET', default='') }}\"",
      },
      {
        name: "op_read (1Password)",
        content: "API_KEY = \"{{ op_read('op://Vault/Item/credential') }}\"",
      },
      {
        name: "cache",
        content: "TOKEN = \"{{ cache(key='token', run='op read ...') }}\"",
      },
      {
        name: "1Password URI",
        content: 'CRED = "op://Engineering/GitHub/token"',
      },
    ];

    for (const { name, content } of safePatterns) {
      it(`should allow ${name}`, async () => {
        const result = await runHook({
          tool_name: "Write",
          tool_input: {
            file_path: "/project/mise.toml",
            content: `[env]\n${content}`,
          },
        });
        expect(result.hookSpecificOutput.permissionDecision).toBe("allow");
      });
    }
  });

  describe("line count threshold", () => {
    it("should allow files under 100 lines", async () => {
      const content = "[env]\n" + Array(50).fill('VAR = "value"').join("\n");
      const result = await runHook({
        tool_name: "Write",
        tool_input: {
          file_path: "/project/mise.toml",
          content,
        },
      });
      expect(result.hookSpecificOutput.permissionDecision).toBe("allow");
    });

    it("should block files over 100 lines with hub-spoke suggestion", async () => {
      const content = "[env]\n" + Array(110).fill('VAR = "value"').join("\n");
      const result = await runHook({
        tool_name: "Write",
        tool_input: {
          file_path: "/project/mise.toml",
          content,
        },
      });
      expect(result.hookSpecificOutput.permissionDecision).toBe("deny");
      expect(result.hookSpecificOutput.permissionDecisionReason).toContain(
        "exceeds 100 lines"
      );
      expect(result.hookSpecificOutput.permissionDecisionReason).toContain(
        "hub-spoke"
      );
      expect(result.hookSpecificOutput.permissionDecisionReason).toContain(
        "task_config"
      );
    });

    it("should not check line count for Edit tool (partial content)", async () => {
      // Edit tool only has partial content, so we can't reliably check line count
      const content = "[env]\n" + Array(110).fill('VAR = "value"').join("\n");
      const result = await runHook({
        tool_name: "Edit",
        tool_input: {
          file_path: "/project/mise.toml",
          new_string: content,
        },
      });
      // Edit tool should still allow since we don't know full file size
      expect(result.hookSpecificOutput.permissionDecision).toBe("allow");
    });
  });

  describe("tool filtering", () => {
    it("should ignore Bash tool", async () => {
      const result = await runHook({
        tool_name: "Bash",
        tool_input: {
          command: "cat mise.toml",
        },
      });
      expect(result.hookSpecificOutput.permissionDecision).toBe("allow");
    });

    it("should ignore Read tool", async () => {
      const result = await runHook({
        tool_name: "Read",
        tool_input: {
          file_path: "/project/mise.toml",
        },
      });
      expect(result.hookSpecificOutput.permissionDecision).toBe("allow");
    });
  });

  describe("plan mode bypass", () => {
    it("should allow in plan mode (permission_mode=plan)", async () => {
      const result = await runHook({
        tool_name: "Write",
        tool_input: {
          file_path: "/project/mise.toml",
          content: '[env]\nAPI_KEY = "sk-secret123"',
        },
        permission_mode: "plan",
      });
      expect(result.hookSpecificOutput.permissionDecision).toBe("allow");
    });

    it("should allow writes to plan file", async () => {
      const result = await runHook({
        tool_name: "Write",
        tool_input: {
          file_path: "/Users/test/.claude/plans/test-plan.md",
          content: '[env]\nAPI_KEY = "sk-secret123"',
        },
      });
      // Plan files are allowed even with "secrets" (it's a plan, not real code)
      expect(result.hookSpecificOutput.permissionDecision).toBe("allow");
    });
  });

  describe("edge cases", () => {
    it("should handle empty content", async () => {
      const result = await runHook({
        tool_name: "Write",
        tool_input: {
          file_path: "/project/mise.toml",
          content: "",
        },
      });
      expect(result.hookSpecificOutput.permissionDecision).toBe("allow");
    });

    it("should handle missing content", async () => {
      const result = await runHook({
        tool_name: "Write",
        tool_input: {
          file_path: "/project/mise.toml",
        },
      });
      expect(result.hookSpecificOutput.permissionDecision).toBe("allow");
    });

    it("should prioritize secrets over line count", async () => {
      // A file with both secrets AND over 100 lines should mention secrets first
      const content =
        "[env]\n" +
        'API_KEY = "sk-secret"\n' +
        Array(110).fill('VAR = "value"').join("\n");
      const result = await runHook({
        tool_name: "Write",
        tool_input: {
          file_path: "/project/mise.toml",
          content,
        },
      });
      expect(result.hookSpecificOutput.permissionDecision).toBe("deny");
      expect(result.hookSpecificOutput.permissionDecisionReason).toContain(
        "Secrets detected"
      );
    });
  });
});
