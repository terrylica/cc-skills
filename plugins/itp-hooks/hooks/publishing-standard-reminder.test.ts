/**
 * Tests for publishing-standard-reminder.ts.
 *
 * Run with: bun test plugins/itp-hooks/hooks/publishing-standard-reminder.test.ts
 *
 * The once-per-session gates live under the shared per-user /tmp gate directories, so every test uses a fresh random
 * session id and removes its gate files afterwards. No network.
 */

import { afterEach, describe, expect, test } from "bun:test";
import { rmSync } from "node:fs";
import { join } from "node:path";
import { perUserGateDirectory } from "./lib/posttooluse-subhook-async-helpers-iter95.ts";
import {
  ESCAPE_MARKER,
  REMINDER,
  classifyPublishingStandardReminderForPostToolUseOrchestrator,
  gateKey,
  isHtmlPagePath,
  isPublishCommand,
} from "./publishing-standard-reminder.ts";

const HOOK_PATH = join(import.meta.dir, "publishing-standard-reminder.ts");
const used: string[] = [];

function freshSession(): string {
  const id = `test-${crypto.randomUUID()}`;
  used.push(id);
  return id;
}

afterEach(() => {
  for (const id of used.splice(0)) {
    for (const gate of ["publishing-standard-publish", "publishing-standard-page"]) {
      rmSync(join(perUserGateDirectory(`/tmp/.claude-${gate}-reminder`), `${id}.reminded`), { force: true });
    }
  }
});

async function runHook(input: Record<string, unknown>): Promise<string | undefined> {
  const proc = Bun.spawn(["bun", HOOK_PATH], { stdin: "pipe", stdout: "pipe", stderr: "pipe" });
  proc.stdin.write(JSON.stringify(input));
  proc.stdin.end();
  const [stdout, exitCode] = await Promise.all([new Response(proc.stdout).text(), proc.exited]);
  expect(exitCode).toBe(0);
  const out = stdout.trim();
  if (out === "") return undefined;
  const parsed = JSON.parse(out).hookSpecificOutput;
  expect(["deny", "ask"]).not.toContain(parsed?.permissionDecision); // never denies or asks
  return parsed?.additionalContext;
}

describe("which commands publish pages", () => {
  test.each([
    "npx wrangler pages deploy dist --project-name site --branch main",
    "bunx wrangler@4 deploy --assets ./out",
    "wrangler versions deploy",
    "cd site && npx -y wrangler@4 deploy",
    "orca artifacts share report.html",
    "orca artifacts update --slug abc report.html",
    "netlify deploy --prod --dir public",
    "vercel --prod",
    "npx vercel deploy",
    "firebase deploy --only hosting",
    "surge ./public example.surge.sh",
    "npx gh-pages -d build",
  ])("publishes: %s", (cmd) => {
    expect(isPublishCommand(cmd)).toBe(true);
  });

  test.each([
    "wrangler deploy --dry-run --outdir /tmp/x",
    "wrangler pages deploy --help",
    "wrangler deploy -h",
    "wrangler whoami",
    "orca artifacts list --json",
    "git push origin main",
    "npm run build",
    `wrangler deploy ${ESCAPE_MARKER}`,
    "",
    // mentions, not runs
    "cat scripts/workers_deploy.sh",
    "grep -n 'npx wrangler pages deploy' notes.md",
    "git commit -m 'docs: run orca artifacts share to publish'",
    "cat > notes.md <<'EOF'\nnetlify deploy --prod\nEOF",
    "echo \"vercel --prod\"",
  ])("does not publish: %s", (cmd) => {
    expect(isPublishCommand(cmd)).toBe(false);
  });
});

describe("filters", () => {
  test("HTML page paths", () => {
    for (const p of ["/a/index.html", "/a/B.HTM", "/a/page.xhtml"]) expect(isHtmlPagePath(p)).toBe(true);
    for (const p of ["/a/page.md", "/a/style.css", "/a/html", "", undefined, 3]) expect(isHtmlPagePath(p)).toBe(false);
  });

  test("session ids become gate keys only as one plain path component", () => {
    expect(gateKey("3f2b9c1e-aaaa-4bbb-8ccc-0123456789ab")).toBe("3f2b9c1e-aaaa-4bbb-8ccc-0123456789ab");
    for (const bad of ["", "../x", "a/b", "a b", undefined, 7]) expect(gateKey(bad)).toBe("");
  });

  test("the reminder names the skill and fits on one line", () => {
    expect(REMINDER).toContain("Skill(devops-tools:publishing-standard)");
    expect(REMINDER.includes("\n")).toBe(false);
    expect(REMINDER.length).toBeLessThan(400);
  });
});

describe("PreToolUse, run as a process", () => {
  test("a publish command is reminded once per session", async () => {
    const session = freshSession();
    const input = { tool_name: "Bash", tool_input: { command: "npx wrangler pages deploy out" }, session_id: session };
    expect(await runHook(input)).toBe(REMINDER);
    expect(await runHook(input)).toBeUndefined();
  });

  test("other commands, other tools and missing session ids stay silent", async () => {
    expect(await runHook({ tool_name: "Bash", tool_input: { command: "ls" }, session_id: freshSession() })).toBeUndefined();
    expect(await runHook({ tool_name: "Read", tool_input: { file_path: "/x.html" }, session_id: freshSession() })).toBeUndefined();
    expect(await runHook({ tool_name: "Bash", tool_input: { command: "wrangler deploy" } })).toBeUndefined();
  });

  test("malformed input fails open", async () => {
    const proc = Bun.spawn(["bun", HOOK_PATH], { stdin: "pipe", stdout: "pipe", stderr: "pipe" });
    proc.stdin.write("not json");
    proc.stdin.end();
    expect(await proc.exited).toBe(0);
  });
});

describe("PostToolUse classifier", () => {
  const edit = (filePath: string, session: string, tool = "Write") => ({
    tool_name: tool,
    tool_input: { file_path: filePath, content: "<html></html>" },
    tool_response: {},
    session_id: session,
  });

  test("an HTML page written is reminded once per session, separately from publishing", async () => {
    const session = freshSession();
    const first = await classifyPublishingStandardReminderForPostToolUseOrchestrator(edit("/repo/site/index.html", session));
    expect(JSON.stringify(first)).toContain("publishing-standard");
    const second = await classifyPublishingStandardReminderForPostToolUseOrchestrator(edit("/repo/site/b.html", session, "Edit"));
    expect(JSON.stringify(second)).not.toContain("publishing-standard");
    // the publish gate is separate: the same session is still reminded before publishing
    expect(await runHook({ tool_name: "Bash", tool_input: { command: "wrangler deploy" }, session_id: session })).toBe(REMINDER);
  });

  test("non-HTML files and non-edit tools are not reminded", async () => {
    const session = freshSession();
    for (const input of [edit("/repo/a.md", session), edit("/repo/a.html", session, "Read")]) {
      const d = await classifyPublishingStandardReminderForPostToolUseOrchestrator(input);
      expect(JSON.stringify(d)).not.toContain("publishing-standard");
    }
  });
});
