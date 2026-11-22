import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const dir = mkdtempSync(join(tmpdir(), "cfsm-hook-"));
process.env.CF_SITEMAP_STATE = dir;
process.env.CF_SITEMAP_CONFIG = join(dir, "hook.json");
const lib = await import("./lib/cloudflare-deploy-sitemap.ts");
const HOOKS = import.meta.dir;

function run(script: string, payload: object): { out: string; code: number } {
  const r = Bun.spawnSync(["bun", join(HOOKS, script)], {
    stdin: new TextEncoder().encode(JSON.stringify(payload)),
    env: { ...process.env, CF_SITEMAP_STATE: dir, CF_SITEMAP_CONFIG: join(dir, "hook.json") },
  });
  return { out: r.stdout.toString(), code: r.exitCode ?? 0 };
}

beforeEach(() => {
  rmSync(lib.PENDING, { force: true });
  rmSync(lib.LAST, { force: true });
});
afterEach(() => rmSync(join(dir, "hook.json"), { force: true }));

describe("isDeployCommand", () => {
  test.each([
    "npx --yes wrangler@4 deploy --assets x --var PAGE_PATH:abc",
    "bunx wrangler pages deploy dist --project-name site",
    "wrangler versions deploy",
    "bash scripts/workers_deploy.sh --touch-id",
    "ssh mac 'cd /tmp && npx wrangler@4 pages deployment list; npx wrangler@4 pages deploy out'",
  ])("deploy: %s", (c) => expect(lib.isDeployCommand(c)).toBe(true));
  test.each([
    "bash scripts/workers_deploy.sh --dry-run",
    "npx wrangler@4 deploy --dry-run --outdir b",
    "npx wrangler@4 pages deployment list --project-name x",
    "npx wrangler@4 whoami",
    "python3 cfsm.py deploy ventures",
    "grep -n wrangler deploy notes.md".replace("wrangler deploy", "wrangler-deploy"),
    // mentions, not runs (each blocked a session's turn end before 2026-11-15)
    "cat scripts/share.sh; cat scripts/workers_deploy.sh",
    "sed -n 84,125p scripts/workers_deploy.sh",
    "grep -rn 'workers_deploy_token' docs scripts",
    "grep -n 'npx wrangler pages deploy' notes.md",
    "git commit -m 'docs: how to run wrangler deploy'",
    "cat > notes.md <<'EOF'\nRun wrangler deploy to publish.\nEOF",
    "echo \"npx wrangler@4 deploy\"",
  ])("not a deploy: %s", (c) => expect(lib.isDeployCommand(c)).toBe(false));

  test.each([
    "cd site && npx -y wrangler@4 deploy",
    "env WRANGLER_SEND_METRICS=false bunx wrangler@4 deploy --assets out",
    "scripts/workers_deploy.sh --touch-id",
    "timeout --foreground 2400 scripts/workers_deploy.sh --touch-id > log 2>&1",
    "pnpm dlx wrangler pages deploy dist",
    "bash -c 'npx wrangler deploy'",
  ])("still a deploy: %s", (c) => expect(lib.isDeployCommand(c)).toBe(true));
});

describe("hooks", () => {
  const deploy = { tool_name: "Bash", session_id: "s1", cwd: "/w", tool_input: { command: "npx wrangler@4 deploy" } };

  test("PostToolUse records the deploy and reminds with the configured command", () => {
    writeFileSync(join(dir, "hook.json"), JSON.stringify({ update_command: "UPDATE-NOW" }));
    const r = run("posttooluse-cloudflare-deploy-sitemap-reminder.ts", deploy);
    expect(JSON.parse(r.out).decision).toBe("block");
    expect(r.out).toContain("UPDATE-NOW");
    expect(lib.readPending()).toHaveLength(1);
  });

  test("PostToolUse ignores other commands and the escape hatch", () => {
    run("posttooluse-cloudflare-deploy-sitemap-reminder.ts", { ...deploy, tool_input: { command: "ls" } });
    run("posttooluse-cloudflare-deploy-sitemap-reminder.ts", { ...deploy, tool_input: { command: "npx wrangler deploy # CF-SITEMAP-OK" } });
    expect(lib.readPending()).toHaveLength(0);
  });

  test("Stop blocks only the deploying session, until the sitemap is newer, at most MAX_BLOCKS times", () => {
    run("posttooluse-cloudflare-deploy-sitemap-reminder.ts", deploy);
    expect(run("stop-cloudflare-sitemap-pending.ts", { session_id: "other" }).out).toBe("");
    for (let i = 0; i < lib.MAX_BLOCKS; i++) {
      expect(JSON.parse(run("stop-cloudflare-sitemap-pending.ts", { session_id: "s1" }).out).decision).toBe("block");
    }
    expect(run("stop-cloudflare-sitemap-pending.ts", { session_id: "s1" }).out).toBe("");
    expect(lib.readPending()).toHaveLength(0);
  });

  test("Stop passes once the sitemap is newer than the deploy", () => {
    run("posttooluse-cloudflare-deploy-sitemap-reminder.ts", deploy);
    writeFileSync(lib.LAST, JSON.stringify({ at: new Date(Date.now() + 1000).toISOString() }));
    expect(run("stop-cloudflare-sitemap-pending.ts", { session_id: "s1" }).out).toBe("");
    expect(lib.readPending()).toHaveLength(0);
  });

  test("the mark command writes LAST", () => {
    Bun.spawnSync(["sh", "-c", lib.markCommand()]);
    expect(lib.lastSitemapAt()).toBeGreaterThan(Date.now() - 60_000);
  });
});
