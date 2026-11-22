import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { brotliCompressSync } from "node:zlib";
import { OutcomeAccumulator, readDebugLogs, readSubhookTimingFiles, stat, TimingAccumulator } from "./aggregate.ts";
import { HOOK_COMMAND_INTERPRETERS, hookIdFromCommand, parseHookCommand, shortHash } from "./command.ts";
import { buildInventory, ORCHESTRATOR_REGISTRIES, parseOrchestratorRegistry, statusAliases } from "./inventory.ts";
import { boldBulletsInSection, checkRules, headingsInSection } from "./rules.ts";
import { type CensusEvent, classifyRecord, extractTags, listTranscriptFiles, PROMPT_HOOK_ID, type ScanStats, scanTranscript } from "./transcripts.ts";

/** The literal a hooks.json command carries; Claude Code substitutes it, the census must not. */
const PLUGIN_ROOT_VAR = "$" + "{CLAUDE_PLUGIN_ROOT}";
const REPO = join(import.meta.dir, "..", "..", "..", "..");
const HOOKS = join(import.meta.dir, "..", "..", "hooks");
let tmp: string;

beforeAll(() => {
  tmp = mkdtempSync(join(tmpdir(), "hook-census-test-"));
});
afterAll(() => {
  rmSync(tmp, { recursive: true, force: true });
});

describe("command", () => {
  test("interpreter set matches scripts/validate-plugins.mjs (the JS port of the bash SSoT)", () => {
    const src = readFileSync(join(REPO, "scripts", "validate-plugins.mjs"), "utf8");
    const block = src.match(/HOOK_COMMAND_INTERPRETERS = new Set\(\[([\s\S]*?)\]\)/)?.[1] ?? "";
    const theirs = [...block.matchAll(/"([^"]+)"/g)].map((m) => m[1]);
    expect(theirs.length).toBeGreaterThan(5);
    expect([...HOOK_COMMAND_INTERPRETERS].toSorted()).toEqual(theirs.toSorted());
  });

  test.each([
    [`bun ${PLUGIN_ROOT_VAR}/hooks/foo.ts`, "foo.ts"],
    [`env -u AI_AGENT -u CLAUDECODE bun ${PLUGIN_ROOT_VAR}/hooks/foo.ts`, "foo.ts"],
    ["bash $HOME/.claude/hooks/saas-browser-guard.sh", "saas-browser-guard.sh"],
    ['"$HOME/.claude/hooks/x.sh" --flag', "x.sh"],
    ["/Users/a/.orca/agent-hooks/claude-hook.sh", "claude-hook.sh"],
  ])("%s → %s", (cmd, id) => {
    expect(hookIdFromCommand(cmd)).toBe(id);
  });

  test("an inline shell script is hashed, never echoed", () => {
    const id = hookIdFromCommand("bash -c 'echo secret-token | tee /tmp/x'");
    expect(id.startsWith("inline:")).toBe(true);
    expect(id).not.toContain("secret");
    expect(parseHookCommand("sh -lc 'true'").inline).toBe(true);
  });

  test("text that is not a command never becomes an id", () => {
    // What Claude Code writes in a hook's command field besides commands: a prompt hook's prompt with the user's
    // words in it, a configured statusMessage, an inline `if` script; and a capitalised word that macOS's
    // case-insensitive file system would resolve to an executable.
    for (const text of [
      "Please check whether the invoice went out",
      "Checking headless claude -p usage...",
      "if [ -f x ]; then exit 0; fi",
      "Make the release notes longer",
      "it@example.com please reply",
      "https://example.com/private/page is down",
    ]) {
      const id = hookIdFromCommand(text);
      expect(id).toBe(`inline:${shortHash(text)}`);
    }
    expect(hookIdFromCommand("callback")).toBe("builtin:callback");
    expect(hookIdFromCommand("ls -la")).toBe("ls");
  });
});

describe("inventory", () => {
  test("parses every real orchestrator registry in this repo", () => {
    for (const [file, registry] of Object.entries(ORCHESTRATOR_REGISTRIES)) {
      const rows = parseOrchestratorRegistry(readFileSync(join(HOOKS, file), "utf8"), registry);
      expect(rows).not.toBeNull();
      expect((rows ?? []).length).toBeGreaterThan(3);
      const names = (rows ?? []).map((r) => r.name);
      expect(new Set(names).size).toBe(names.length);
      for (const r of rows ?? []) expect(r.timeoutMs).toBeGreaterThan(0);
    }
  });

  test("skips brackets and name: inside strings when finding the registry's end", () => {
    const src = `export const BASH_GUARD_REGISTRY: readonly E[] = [
  { name: "a", main: a, timeoutMs: 4_000, description: "matches [a-z] and says name: \\"x\\"" },
  // a comment with ] in it
  { name: "b", main: b, timeoutMs: 9000, description: \`template ] here\` },
];
const AFTER = [{ name: "not-me" }];`;
    expect(parseOrchestratorRegistry(src, "BASH_GUARD_REGISTRY")).toEqual([
      { name: "a", timeoutMs: 4000 },
      { name: "b", timeoutMs: 9000 },
    ]);
  });

  test("builds handlers from settings, enabled plugins and orchestrators, and diffs two launchers", () => {
    const pluginRoot = join(tmp, "plugin");
    mkdirSync(join(pluginRoot, "hooks"), { recursive: true });
    writeFileSync(
      join(pluginRoot, "hooks", "pretooluse-bash-guard-orchestrator.ts"),
      'export const BASH_GUARD_REGISTRY = [{ name: "g1", main: x, timeoutMs: 4000 }, { name: "g2", main: y, timeoutMs: 14000 }];',
    );
    writeFileSync(
      join(pluginRoot, "hooks", "hooks.json"),
      JSON.stringify({
        hooks: {
          PreToolUse: [{ matcher: "Bash", hooks: [{ type: "command", command: `bun ${PLUGIN_ROOT_VAR}/hooks/pretooluse-bash-guard-orchestrator.ts`, timeout: 60 }] }],
          Stop: [{ hooks: [{ type: "command", command: `bun ${PLUGIN_ROOT_VAR}/hooks/stop-x.ts`, statusMessage: "Checking stop state..." }] }],
        },
      }),
    );
    const rootA = join(tmp, "rootA");
    const rootB = join(tmp, "rootB");
    for (const [root, extra] of [
      [rootA, "a-only.sh"],
      [rootB, "b-only.sh"],
    ] as const) {
      mkdirSync(join(root, "plugins"), { recursive: true });
      writeFileSync(
        join(root, "settings.json"),
        JSON.stringify({
          hooks: { PreToolUse: [{ matcher: "Bash", hooks: [{ type: "command", command: `bash ~/.claude/hooks/${extra}` }] }] },
          enabledPlugins: { "p@m": true, "off@m": false },
        }),
      );
      writeFileSync(join(root, "plugins", "installed_plugins.json"), JSON.stringify({ plugins: { "p@m": [{ installPath: pluginRoot, version: "1.2.3" }] } }));
    }
    const inv = buildInventory({ configRoots: [rootA, rootB] });
    expect(inv.totals.registrations).toBe(3);
    expect(inv.totals.subhooks).toBe(2);
    const orch = inv.handlers.find((h) => h.hookId === "pretooluse-bash-guard-orchestrator.ts");
    expect(orch?.subhooks).toEqual([
      { name: "g1", timeoutMs: 4000 },
      { name: "g2", timeoutMs: 14000 },
    ]);
    expect(orch?.source).toBe("plugin:p@m@1.2.3");
    expect(inv.plugins.map((p) => p.id)).toEqual(["p@m"]);
    expect(inv.launcherDiff).toEqual({ onlyInFirst: ["PreToolUse|Bash|a-only.sh"], onlyInSecond: ["PreToolUse|Bash|b-only.sh"] });
    expect(JSON.stringify(inv)).not.toContain("bash ~/.claude");
    // Claude Code records a hook with a statusMessage under that text; the alias counts it under its script.
    expect(statusAliases(inv).get(hookIdFromCommand("Checking stop state..."))).toBe("stop-x.ts");
    expect(JSON.stringify(inv)).not.toContain("Checking stop state");
  });
});

const deny = (tag: string, ts = "2026-11-10T00:00:00Z") => ({
  type: "user",
  timestamp: ts,
  sessionId: "s1",
  permissionDecision: { decision: "reject", source: "hook", reasonType: "hook", reasonCode: "hook:PreToolUse" },
  message: { content: [{ tool_use_id: "t1", type: "tool_result", is_error: true, content: `PreToolUse:Bash hook error: ${tag} This checkout has private-token-xyz` }] },
});

describe("transcripts", () => {
  test("tags come from the head of the message only", () => {
    expect(extractTags("[REVIEW-ROUND-GATE] No valid self-review record")).toEqual(["[REVIEW-ROUND-GATE]"]);
    expect(extractTags("[pretooluse-edit-time-orchestrator] shell-script-safety-guard → DENY\nrest")).toEqual(["shell-script-safety-guard"]);
    expect(extractTags("[bash /Users/x/.claude/hooks/saas-browser-guard.sh]: BLOCKED")).toEqual(["saas-browser-guard.sh"]);
    expect(extractTags("[orchestrator-subhook: ty-type-check]\n…\n[orchestrator-subhook: oxlint-check]")).toEqual(["ty-type-check", "oxlint-check"]);
    expect(extractTags("Plain text with a secret 12345 inside")[0]).toBe("untagged:Plain text with a");
    expect(extractTags("ℹ️ 13 Claude windows open")).toEqual(extractTags("ℹ️ 15 Claude windows open"));
    expect(extractTags("ℹ️ 13 Claude windows open")[0]).toBe("untagged:N Claude windows open");
    expect(extractTags("BLOCKED gmail-send-guard: /Users/x/private/draft.eml is unsigned")[0]).toBe("untagged:BLOCKED gmail-send-guard:");
  });

  test("classifies every record shape, keeping no message text", () => {
    const events: CensusEvent[] = [
      ...classifyRecord(deny("[gh-tools]")),
      ...classifyRecord({ type: "user", permissionDecision: { decision: "accept", source: "user_temporary", reasonCode: "hook:PreToolUse" } }),
      ...classifyRecord({ type: "user", permissionDecision: { decision: "accept", source: "hook", reasonType: "hook" } }),
      ...classifyRecord({ type: "attachment", attachment: { type: "hook_success", hookName: "PreToolUse:Bash", hookEvent: "PreToolUse", toolUseID: "t1", command: `bun ${PLUGIN_ROOT_VAR}/hooks/a.ts`, durationMs: 42, exitCode: 0 } }),
      ...classifyRecord({ type: "attachment", attachment: { type: "hook_cancelled", hookName: "PreToolUse:Bash", hookEvent: "PreToolUse", command: "bun /x/slow.ts", durationMs: 60000, timedOut: true, timeoutMs: 60000 } }),
      ...classifyRecord({ type: "attachment", attachment: { type: "hook_additional_context", hookName: "UserPromptSubmit", hookEvent: "UserPromptSubmit", content: ["[SaaS API-first] use the CLI"] } }),
      ...classifyRecord({
        type: "attachment",
        attachment: { type: "hook_blocking_error", hookName: "PostToolUse:Write", hookEvent: "PostToolUse", blockingError: { blockingError: "[typescript-upgrade-reminder] timed out after 2000ms — check", command: "bun /p/hooks/posttooluse-write-edit-orchestrator.ts" } },
      }),
      ...classifyRecord({
        type: "system",
        subtype: "stop_hook_summary",
        hookInfos: [
          { command: "bun /p/hooks/stop-orchestrator.ts", durationMs: 812 },
          { command: "Summarise private-token words from a prompt", promptText: "Summarise private-token words from a prompt", durationMs: 9000 },
        ],
        toolUseID: "t9",
      }),
    ];
    const kinds = events.map((e) => e.kind);
    expect(kinds).toEqual(["deny", "ask", "duration", "timeout", "context", "decision-block", "subhook-timeout", "duration", "duration"]);
    expect(events[8]).toMatchObject({ hookId: PROMPT_HOOK_ID, ms: 9000 });
    expect(events[0]).toMatchObject({ kind: "deny", event: "PreToolUse", tool: "Bash", tag: "[gh-tools]", toolUseId: "t1", sessionId: "s1" });
    expect(events[3]).toMatchObject({ hookId: "slow.ts", timeoutMs: 60000 });
    expect(events[6]).toMatchObject({ hookId: "typescript-upgrade-reminder", timeoutMs: 2000 });
    expect(JSON.stringify(events)).not.toContain("private-token");
  });

  test("streams .jsonl and .jsonl.br, honours the time window, counts bad lines", async () => {
    const proj = join(tmp, "projects", "-Users-x-repo");
    mkdirSync(join(proj, "sess", "subagents"), { recursive: true });
    const lines = [JSON.stringify(deny("[A]")), JSON.stringify(deny("[B]", "2025-01-01T00:00:00Z")), '{"type":"user","source":"hook",broken'].join("\n");
    writeFileSync(join(proj, "s1.jsonl"), lines);
    writeFileSync(join(proj, "s2.jsonl.br"), brotliCompressSync(Buffer.from(JSON.stringify(deny("[C]")))));
    writeFileSync(join(proj, "sess", "subagents", "agent-1.jsonl"), JSON.stringify(deny("[D]")));
    const files = listTranscriptFiles(join(tmp, "projects"), 0);
    expect(files).toHaveLength(3);
    const stats: ScanStats = { files: 0, lines: 0, parsed: 0, badLines: 0, unreadable: 0 };
    const tags: string[] = [];
    for (const f of files) await scanTranscript(f, Date.parse("2026-01-01"), Date.parse("2027-01-01"), (e) => tags.push(e.tag ?? ""), stats);
    expect(tags.toSorted()).toEqual(["[A]", "[C]", "[D]"]);
    expect(stats.badLines).toBe(1);
  });

  test("a corrupt .jsonl.br is counted unreadable and the scan goes on", async () => {
    const dir = join(tmp, "corrupt", "-x");
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "bad.jsonl.br"), Buffer.from("not brotli at all \u0000\u0001"));
    writeFileSync(join(dir, "good.jsonl"), JSON.stringify(deny("[OK]")));
    const stats: ScanStats = { files: 0, lines: 0, parsed: 0, badLines: 0, unreadable: 0 };
    const tags: string[] = [];
    for (const f of listTranscriptFiles(join(tmp, "corrupt"), 0)) await scanTranscript(f, 0, Date.parse("2027-01-01"), (e) => tags.push(e.tag ?? ""), stats);
    expect(stats.unreadable).toBe(1);
    expect(tags).toEqual(["[OK]"]);
  });
});

describe("aggregate", () => {
  test("stat uses nearest-rank percentiles", () => {
    expect(stat([5, 1, 3, 2, 4])).toEqual({ count: 5, p50: 3, p95: 5, max: 5, total: 15 });
    expect(stat([])).toEqual({ count: 0, p50: 0, p95: 0, max: 0, total: 0 });
  });

  test("outcomes count per tag, sample denies without text, skip keyless events", () => {
    const acc = new OutcomeAccumulator(1);
    for (const e of [...classifyRecord(deny("[X]")), ...classifyRecord(deny("[X]")), ...classifyRecord(deny("[Y]"))]) acc.add(e);
    acc.add({ kind: "timeout", event: "PreToolUse" });
    const o = acc.result({ since: "a", until: "b" });
    expect(o.byTag["[X]"]).toEqual({ deny: 2, context: 0, decisionBlock: 0, sessions: 1 });
    expect(o.samples.map((s) => s.tag)).toEqual(["[X]", "[Y]"]);
    expect(o.timeouts).toEqual({});
    expect(o.totals.timeout).toBe(1);
    expect(o.denyByDay).toEqual({ "2026-11-10": 3 });
  });

  test("timing folds transcript durations, sub-hook timing files and debug logs", () => {
    const acc = new TimingAccumulator();
    acc.addEvent({ kind: "duration", event: "PreToolUse", hookId: "a.ts", ms: 10, toolUseId: "t1", sessionId: "s" });
    acc.addEvent({ kind: "duration", event: "PreToolUse", hookId: "b.ts", ms: 30, toolUseId: "t1", sessionId: "s" });
    const dir = join(tmp, "census");
    mkdirSync(dir, { recursive: true });
    writeFileSync(
      join(dir, "timing-2026-11-16.jsonl"),
      `${JSON.stringify({ orchestrator: "o", event: "PreToolUse", subhook: "g1", elapsedMs: 4, verdict: "allow" })}\n{torn\n`,
    );
    expect(readSubhookTimingFiles(dir, "2026-11-16T00:00:00Z", "2026-11-17T00:00:00Z", acc)).toBe(1);
    const dbg = join(tmp, "debug");
    mkdirSync(dbg, { recursive: true });
    writeFileSync(
      join(dbg, "x.txt"),
      "2026-11-16T10:00:00.000Z [DEBUG] Hooks: PreToolUse:Bash [bun /c/itp-hooks/34.18.2/hooks/silent-guard.ts] (plugin itp-hooks@cc-skills) finished with status 0 (7ms)\n",
    );
    expect(readDebugLogs(dbg, 0, Date.parse("2027-01-01"), acc)).toBe(1);
    const t = acc.result({ since: "a", until: "b" }, []);
    expect(t.perEventCall.PreToolUse).toMatchObject({ count: 1, max: 30 });
    expect(t.perSubhook.g1).toMatchObject({ count: 1, verdicts: { allow: 1 } });
    expect(t.perHook["PreToolUse silent-guard.ts"]).toMatchObject({ count: 1, p50: 7 });
    expect(t.sources).toEqual({ transcript: 2, subhookTiming: 1, debugLog: 1 });
  });
});

describe("rules", () => {
  test("validates coverage, enforcers, escape parts, rationale anchors; reports honest status", () => {
    const hub = "## Behavioral Policies\n\n### Rule One\nx\n### Pointer\n## Topic Index\n### Not a rule\n";
    const fleet = "## Rules\n\n- **Fleet rule**: text\n";
    expect(headingsInSection(hub, "Behavioral Policies")).toEqual(["Rule One", "Pointer"]);
    expect(boldBulletsInSection(fleet, "Rules")).toEqual(["Fleet rule"]);
    const guard = join(tmp, "pretooluse-demo-guard.ts");
    writeFileSync(guard, "const ESCAPE = 'DEMO-OK';");
    const why = join(tmp, "decisions.md");
    writeFileSync(why, "## 2026-10-19 · the reason\n");
    const rulesFile = join(tmp, "rules.toml");
    writeFileSync(
      rulesFile,
      `[[rule]]
id = "one"
title = "Rule One"
hub_section = "Rule One"
category = "repository-contract"
origin = "observed-mistake"
status = "undecided"
rationale_ref = ["${why}#2026-10-19", "${why}#2099-01-01"]
[[rule.enforcement]]
enforcer = "${guard}"
mode = "block"
escape = ["DEMO", "-OK"]
tags = ["[DEMO]"]

[[rule]]
id = "two"
title = "Fleet rule"
hub_section = "Fleet rule"
category = "nonsense"
origin = "operator-policy"
status = "undecided"
`,
    );
    const inventory = {
      settingsFiles: [],
      plugins: [],
      handlers: [{ event: "PreToolUse", matcher: "Bash", source: "plugin:x", kind: "command" as const, hookId: "orch.ts", script: null, timeoutSec: null, subhooks: [{ name: "pretooluse-demo-guard", timeoutMs: 4000 }] }],
      totals: { registrations: 1, subhooks: 1, byEvent: {}, bySource: {} },
      warnings: [],
    };
    const outcomes = { byTag: { "[DEMO]": { deny: 5, context: 1, decisionBlock: 0, sessions: 2 } } } as unknown as Parameters<typeof checkRules>[0]["outcomes"];
    const r = checkRules({ file: rulesFile, expected: ["Rule One", "Fleet rule", "Missing rule"], inventory, outcomes });
    expect(r.coverage.missing).toEqual(["Missing rule"]);
    const one = r.checks.find((c) => c.id === "one");
    expect(one?.honestStatus).toBe("blocked-by-guard");
    expect(one?.enforcers[0]?.registered).toBe("yes");
    expect(one?.outcomes).toEqual({ deny: 5, context: 1, decisionBlock: 0 });
    expect(one?.problems).toEqual(['rationale anchor "2099-01-01" not found in ' + why]);
    const two = r.checks.find((c) => c.id === "two");
    expect(two?.honestStatus).toBe("no-enforcer");
    expect(two?.problems.some((p) => p.startsWith('category "nonsense"'))).toBe(true);
  });
});
