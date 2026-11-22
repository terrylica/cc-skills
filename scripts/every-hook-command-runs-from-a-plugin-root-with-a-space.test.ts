/**
 * scripts/every-hook-command-runs-from-a-plugin-root-with-a-space.test.ts
 *
 * Claude Code replaces the literal `${CLAUDE_PLUGIN_ROOT}` in a hook command with the
 * plugin's install path and runs the result with `/bin/sh -c`, unquoted. Orca starts
 * Claude sessions with CLAUDE_CONFIG_DIR under `~/Library/Application Support/...`, and a
 * `claude plugin update` run in such a session records an install path with a space. Every
 * hook whose command left the root unquoted then failed with
 * `/bin/sh: /Users/<user>/Library/Application: Permission denied` (exit 126), measured on
 * another marketplace's hooks on 2026-11-14.
 *
 * This test rebuilds that situation for every hooks.json in the marketplace: a plugin root
 * whose path contains a space, each referenced script replaced by a stub that prints a
 * marker, and each command substituted and run through `/bin/sh -c`.
 */

import { afterAll, describe, expect, test } from "bun:test";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { Glob } from "bun";

const REPO_ROOT = join(import.meta.dir, "..");
const PLACEHOLDER = "$" + "{CLAUDE_PLUGIN_ROOT}";
const MARKER = "STUB-HOOK-RAN";

type HookCommand = { plugin: string; command: string };

function collectHookCommands(): HookCommand[] {
  const found: HookCommand[] = [];
  for (const rel of new Glob("plugins/*/hooks/hooks.json").scanSync(REPO_ROOT)) {
    const plugin = rel.split("/")[1];
    const walk = (node: unknown): void => {
      if (Array.isArray(node)) {
        node.forEach(walk);
      } else if (node && typeof node === "object") {
        const obj = node as Record<string, unknown>;
        if (typeof obj.command === "string" && obj.command.includes(PLACEHOLDER)) {
          found.push({ plugin, command: obj.command });
        }
        Object.values(obj).forEach(walk);
      }
    };
    walk(JSON.parse(readFileSync(join(REPO_ROOT, rel), "utf8")));
  }
  return found;
}

const commands = collectHookCommands();
const scratch = mkdtempSync(join(tmpdir(), "cc-skills-hook-root-"));
afterAll(() => rmSync(scratch, { recursive: true, force: true }));

describe("every hook command runs from a plugin root that contains a space", () => {
  test("the marketplace registers hook commands that use the plugin root", () => {
    expect(commands.length).toBeGreaterThan(0);
  });

  for (const { plugin, command } of commands) {
    test(`${plugin}: ${command}`, () => {
      const root = join(scratch, plugin, "Application Support", "plugin root");
      // Every script the command names under the root becomes an executable stub.
      for (const m of command.matchAll(/\$\{CLAUDE_PLUGIN_ROOT\}"?(\/[^\s"']+)/g)) {
        const stub = join(root, m[1]);
        mkdirSync(dirname(stub), { recursive: true });
        const body = stub.endsWith(".sh")
          ? `#!/bin/sh\necho ${MARKER}\n`
          : `#!/usr/bin/env bun\nconsole.log("${MARKER}");\n`;
        writeFileSync(stub, body);
        chmodSync(stub, 0o755);
      }
      const substituted = command.split(PLACEHOLDER).join(root);
      const run = Bun.spawnSync(["/bin/sh", "-c", substituted], {
        env: { ...process.env, CLAUDE_PLUGIN_ROOT: root },
        stdin: "ignore",
        timeout: 15_000,
      });
      const out = run.stdout.toString() + run.stderr.toString();
      expect({ exit: run.exitCode, ranTheStub: out.includes(MARKER), out }).toMatchObject({
        exit: 0,
        ranTheStub: true,
      });
    });
  }
});
