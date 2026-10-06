// Tests for op_sa_token.sh — the plugin's one 1Password service-account token resolver,
// sourced by resolve_pushover_secret.sh and the verbatim-audit-notify scripts.
import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const LIB = join(import.meta.dir, "op_sa_token.sh");
const dir = mkdtempSync(join(tmpdir(), "op-sa-token-sh-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

function run(env: Record<string, string>): { code: number; out: string; err: string } {
  const proc = Bun.spawnSync(["/bin/bash", "-c", `. '${LIB}'; op_sa_token`], {
    // A fake HOME holding the OLD default path proves nothing reads it any more.
    env: { PATH: process.env.PATH ?? "/usr/bin:/bin", HOME: dir, ...env },
    stdout: "pipe",
    stderr: "pipe",
  });
  return { code: proc.exitCode ?? -1, out: proc.stdout.toString(), err: proc.stderr.toString() };
}

describe("op_sa_token.sh", () => {
  test("nothing configured: exit 1, names all three options, ignores the old default file", () => {
    const old = join(dir, ".claude/.secrets");
    Bun.spawnSync(["mkdir", "-p", old]);
    writeFileSync(join(old, "op-service-account-token"), "ops_old_default\n");
    const r = run({});
    expect(r.code).toBe(1);
    expect(r.out).toBe("");
    for (const name of ["OP_SERVICE_ACCOUNT_TOKEN", "OP_SA_TOKEN_CMD", "OP_SA_TOKEN_FILE"]) {
      expect(r.err).toContain(name);
    }
  });

  test("environment token wins", () => {
    const r = run({ OP_SERVICE_ACCOUNT_TOKEN: "ops_env", OP_SA_TOKEN_CMD: "/usr/bin/false" });
    expect(r).toMatchObject({ code: 0, out: "ops_env" });
  });

  test("command stdout, run as a plain argv with no shell expansion", () => {
    const r = run({ OP_SA_TOKEN_CMD: "printf %s ops_cmd;$HOME*" });
    expect(r).toMatchObject({ code: 0, out: "ops_cmd;$HOME*" });
  });

  test("failing or silent command: exit 2, never falls through to a file", () => {
    const file = join(dir, "tok-a");
    writeFileSync(file, "ops_file\n");
    expect(run({ OP_SA_TOKEN_CMD: "/usr/bin/false", OP_SA_TOKEN_FILE: file }).code).toBe(2);
    expect(run({ OP_SA_TOKEN_CMD: "/usr/bin/true" }).code).toBe(2);
  });

  test("named file: PUSHOVER_OP_SA_TOKEN_FILE beats OP_SA_TOKEN_FILE", () => {
    const a = join(dir, "tok-b");
    const b = join(dir, "tok-c");
    writeFileSync(a, "ops_pushover\n");
    writeFileSync(b, "ops_generic\n");
    expect(run({ OP_SA_TOKEN_FILE: b })).toMatchObject({ code: 0, out: "ops_generic" });
    expect(run({ PUSHOVER_OP_SA_TOKEN_FILE: a, OP_SA_TOKEN_FILE: b })).toMatchObject({ code: 0, out: "ops_pushover" });
  });

  test("missing or empty named file: exit 2", () => {
    const empty = join(dir, "empty");
    writeFileSync(empty, "\n");
    expect(run({ OP_SA_TOKEN_FILE: join(dir, "absent") }).code).toBe(2);
    expect(run({ OP_SA_TOKEN_FILE: empty }).code).toBe(2);
  });
});
