import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { maybeInjectOpToken, shSingleQuote } from "./op-token-injector.ts";

const dir = mkdtempSync(join(tmpdir(), "op-token-injector-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

const OP_CMD = `op read "op://Claude Automation/item/field"`;
const PATH = process.env.PATH ?? "/usr/bin:/bin";

/** Run the prefix the hook produced and report what OP_SERVICE_ACCOUNT_TOKEN became. */
function tokenSeenByShell(rewritten: string): string {
  const prefix = rewritten.slice(0, rewritten.length - OP_CMD.length);
  const proc = Bun.spawnSync(["/bin/sh", "-c", `${prefix}/usr/bin/printenv OP_SERVICE_ACCOUNT_TOKEN`], {
    env: { PATH, HOME: dir },
    stdout: "pipe",
  });
  return proc.stdout.toString().trim();
}

describe("maybeInjectOpToken", () => {
  test("nothing configured: command unchanged (no default file)", async () => {
    expect(await maybeInjectOpToken(OP_CMD, { PATH, HOME: dir })).toBe(OP_CMD);
  });

  test("non-Claude-Automation command unchanged", async () => {
    const cmd = `op read "op://Other/item/field"`;
    expect(await maybeInjectOpToken(cmd, { PATH, OP_SA_TOKEN_CMD: "printf %s x" })).toBe(cmd);
  });

  test("token already exported: command unchanged", async () => {
    expect(
      await maybeInjectOpToken(OP_CMD, { PATH, OP_SERVICE_ACCOUNT_TOKEN: "ops_x", OP_SA_TOKEN_CMD: "printf %s y" }),
    ).toBe(OP_CMD);
  });

  test("OP_SA_TOKEN_CMD: substitution, never the token, and no shell expansion", async () => {
    const out = await maybeInjectOpToken(OP_CMD, { PATH, OP_SA_TOKEN_CMD: "printf %s ops_cmd;$HOME" });
    expect(out).toBe(`OP_SERVICE_ACCOUNT_TOKEN="$('printf' '%s' 'ops_cmd;$HOME')" ${OP_CMD}`);
    expect(tokenSeenByShell(out)).toBe("ops_cmd;$HOME");
  });

  test("OP_SA_TOKEN_CMD wins over OP_SA_TOKEN_FILE", async () => {
    const file = join(dir, "tok-a");
    writeFileSync(file, "ops_file\n");
    const out = await maybeInjectOpToken(OP_CMD, { PATH, OP_SA_TOKEN_CMD: "printf %s ops_cmd", OP_SA_TOKEN_FILE: file });
    expect(tokenSeenByShell(out)).toBe("ops_cmd");
  });

  test("OP_SA_TOKEN_FILE: path substitution, token value absent from the command", async () => {
    const file = join(dir, "it's tok");
    writeFileSync(file, "ops_file_secret\n");
    const out = await maybeInjectOpToken(OP_CMD, { PATH, OP_SA_TOKEN_FILE: file });
    expect(out).not.toContain("ops_file_secret");
    expect(out.startsWith(`OP_SERVICE_ACCOUNT_TOKEN="$(cat ${shSingleQuote(file)})" `)).toBe(true);
    expect(tokenSeenByShell(out)).toBe("ops_file_secret");
  });

  test("OP_SA_TOKEN_FILE missing or empty: fail-open", async () => {
    const empty = join(dir, "empty");
    writeFileSync(empty, "\n");
    expect(await maybeInjectOpToken(OP_CMD, { PATH, OP_SA_TOKEN_FILE: join(dir, "absent") })).toBe(OP_CMD);
    expect(await maybeInjectOpToken(OP_CMD, { PATH, OP_SA_TOKEN_FILE: empty })).toBe(OP_CMD);
  });

  test("command that already sets the token is left alone", async () => {
    const cmd = `OP_SERVICE_ACCOUNT_TOKEN=x ${OP_CMD}`;
    expect(await maybeInjectOpToken(cmd, { PATH, OP_SA_TOKEN_CMD: "printf %s y" })).toBe(cmd);
  });
});
