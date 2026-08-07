/**
 * Tests for the skill-plugin-root guard (2026-08-05 draft-hold exit-127 incident).
 *
 * LAYER3-STRIPPED-PATH-OK: fixtures deliberately embed plugin-root paths
 * SKILL-PLUGIN-ROOT-OK: fixtures deliberately embed the broken spellings
 *
 * The three deniable shapes are each grounded in a verified fact about the
 * Claude Code runtime, so these tests pin those facts:
 *   - the substitution helper is `e.replace(/\$\{CLAUDE_PLUGIN_ROOT\}/g, path)`
 *     so braces are required
 *   - therefore bare `$CLAUDE_PLUGIN_ROOT` and the `:-default` form never match
 *   - and a SKILL.md body is served to the model verbatim on the Skill-tool
 *     path, so even the braced form is not substituted there
 */

import { describe, expect, test } from "bun:test";
import type { PreToolUseInput } from "./pretooluse-helpers.ts";
import {
  classifySkillPluginRootGuardForOrchestrator,
  detectSkillPluginRootViolationsInContentBlob,
  isSkillMarkdownFilePath,
  looksLikeJsonManifestLine,
} from "./pretooluse-skill-plugin-root-guard.ts";

const SKILL_MD = "/repo/plugins/example/skills/demo/SKILL.md";

// Built at runtime so the literal broken spellings never appear verbatim in
// this source file (they would trip the very guards under test when this file
// is itself edited, and the markers above are belt-and-suspenders).
const DOLLAR = String.fromCharCode(36);
const BARE = `${DOLLAR}CLAUDE_PLUGIN_ROOT`;
const BRACED = `${DOLLAR}{CLAUDE_PLUGIN_ROOT}`;
const WITH_DEFAULT = `${DOLLAR}{CLAUDE_PLUGIN_ROOT:-/fallback}`;

function writeInput(filePath: string, content: string): PreToolUseInput {
  return {
    tool_name: "Write",
    tool_input: { file_path: filePath, content },
  } as unknown as PreToolUseInput;
}

async function decisionKindFor(
  filePath: string,
  content: string,
): Promise<string> {
  const decision = await classifySkillPluginRootGuardForOrchestrator(
    writeInput(filePath, content),
  );
  return decision.kind;
}

describe("isSkillMarkdownFilePath", () => {
  test("accepts SKILL.md and skill references docs", () => {
    expect(isSkillMarkdownFilePath(SKILL_MD)).toBe(true);
    expect(
      isSkillMarkdownFilePath("/repo/plugins/x/skills/y/references/z.md"),
    ).toBe(true);
  });

  test("rejects manifests, scripts and non-skill markdown", () => {
    expect(isSkillMarkdownFilePath("/repo/plugins/x/hooks/hooks.json")).toBe(
      false,
    );
    expect(isSkillMarkdownFilePath("/repo/plugins/x/skills/y/run.ts")).toBe(
      false,
    );
    expect(isSkillMarkdownFilePath("/repo/plugins/x/CLAUDE.md")).toBe(false);
    expect(isSkillMarkdownFilePath(undefined)).toBe(false);
  });
});

describe("looksLikeJsonManifestLine", () => {
  test("recognizes key-value and array-element shapes", () => {
    expect(looksLikeJsonManifestLine('  "command": "bun x.ts",')).toBe(true);
    expect(looksLikeJsonManifestLine('    "/some/path/server.js"')).toBe(true);
    expect(looksLikeJsonManifestLine('    "/some/path/server.js",')).toBe(true);
  });

  test("does not mistake a shell command for a manifest line", () => {
    expect(
      looksLikeJsonManifestLine('bun "$ROOT/skills/_lib/core.ts" send'),
    ).toBe(false);
    expect(looksLikeJsonManifestLine('DH="$ROOT/a.sh"')).toBe(false);
  });
});

describe("violation detection", () => {
  test("classifies each of the three deniable shapes", () => {
    const bare = detectSkillPluginRootViolationsInContentBlob(
      `DH="${BARE}/skills/draft-hold/draft-hold.sh"`,
    );
    expect(bare).toHaveLength(1);
    expect(bare[0].kind).toBe("BARE_SPELLING");

    const withDefault = detectSkillPluginRootViolationsInContentBlob(
      `S="${WITH_DEFAULT}/a.sh"`,
    );
    expect(withDefault).toHaveLength(1);
    expect(withDefault[0].kind).toBe("NON_SUBSTITUTING_DEFAULT");

    const bracedShell = detectSkillPluginRootViolationsInContentBlob(
      `bun "${BRACED}/skills/_lib/core.ts" send`,
    );
    expect(bracedShell).toHaveLength(1);
    expect(bracedShell[0].kind).toBe("BRACED_IN_SHELL_CONTEXT");
  });

  test("reports the 1-based line number", () => {
    const violations = detectSkillPluginRootViolationsInContentBlob(
      ["# Title", "", `x="${BARE}/a"`].join("\n"),
    );
    expect(violations).toHaveLength(1);
    expect(violations[0].lineNumber).toBe(3);
  });

  test("exempts the braced form on JSON manifest lines", () => {
    expect(
      detectSkillPluginRootViolationsInContentBlob(
        `    "command": "bun ${BRACED}/hooks/notify.ts",`,
      ),
    ).toHaveLength(0);
  });

  test("still flags the BARE spelling inside a JSON manifest line", () => {
    // Bare never substitutes even in a manifest — a live bug, not a style nit.
    const violations = detectSkillPluginRootViolationsInContentBlob(
      `    "command": "bun ${BARE}/hooks/notify.ts",`,
    );
    expect(violations).toHaveLength(1);
    expect(violations[0].kind).toBe("BARE_SPELLING");
  });
});

describe("classifier decisions", () => {
  test("denies all three broken shapes in skill markdown", async () => {
    expect(await decisionKindFor(SKILL_MD, `DH="${BARE}/x/y.sh"`)).toBe("deny");
    expect(await decisionKindFor(SKILL_MD, `DH="${WITH_DEFAULT}/y.sh"`)).toBe(
      "deny",
    );
    expect(await decisionKindFor(SKILL_MD, `bun "${BRACED}/a.ts"`)).toBe(
      "deny",
    );
  });

  test("allows the migrated cc-plugin-root form", async () => {
    expect(
      await decisionKindFor(
        SKILL_MD,
        'DH="$(cc-plugin-root notes-commander)/skills/draft-hold/draft-hold.sh"',
      ),
    ).toBe("allow");
  });

  test("honors a FILE_WIDE escape hatch with a sufficient reason", async () => {
    expect(
      await decisionKindFor(
        SKILL_MD,
        `<!-- SKILL-PLUGIN-ROOT-OK: documents the variable itself -->\n${BARE}/x`,
      ),
    ).toBe("allow");
  });

  test("rejects an escape hatch whose reason is too short", async () => {
    expect(
      await decisionKindFor(
        SKILL_MD,
        `<!-- SKILL-PLUGIN-ROOT-OK: short -->\n${BARE}/x`,
      ),
    ).toBe("deny");
  });

  test("ignores files outside skill markdown", async () => {
    expect(
      await decisionKindFor(
        "/repo/plugins/x/hooks/hooks.json",
        `"command": "bun ${BRACED}/hooks/a.ts"`,
      ),
    ).toBe("allow");
    expect(
      await decisionKindFor(
        "/repo/plugins/x/skills/y/scripts/a.ts",
        "const p = process.env.CLAUDE_PLUGIN_ROOT;",
      ),
    ).toBe("allow");
  });

  test("covers the Edit payload shape", async () => {
    const decision = await classifySkillPluginRootGuardForOrchestrator({
      tool_name: "Edit",
      tool_input: { file_path: SKILL_MD, new_string: `x="${BARE}/a"` },
    } as unknown as PreToolUseInput);
    expect(decision.kind).toBe("deny");
  });

  test("covers the MultiEdit payload shape", async () => {
    const decision = await classifySkillPluginRootGuardForOrchestrator({
      tool_name: "MultiEdit",
      tool_input: {
        file_path: SKILL_MD,
        edits: [{ new_string: "harmless" }, { new_string: `y="${BARE}/b"` }],
      },
    } as unknown as PreToolUseInput);
    expect(decision.kind).toBe("deny");
  });

  test("ignores non-file-edit tools", async () => {
    const decision = await classifySkillPluginRootGuardForOrchestrator({
      tool_name: "Bash",
      tool_input: { command: `echo ${BARE}` },
    } as unknown as PreToolUseInput);
    expect(decision.kind).toBe("allow");
  });

  test("allows content with no mention at all", async () => {
    expect(await decisionKindFor(SKILL_MD, "nothing to see here")).toBe(
      "allow",
    );
  });

  test("denial message names the resolver and the escape hatch", async () => {
    const decision = await classifySkillPluginRootGuardForOrchestrator(
      writeInput(SKILL_MD, `DH="${BARE}/x/y.sh"`),
    );
    expect(decision.kind).toBe("deny");
    expect(decision.reason).toContain("cc-plugin-root");
    expect(decision.reason).toContain("SKILL-PLUGIN-ROOT-OK");
    expect(decision.reason).toContain("BARE_SPELLING");
  });
});
