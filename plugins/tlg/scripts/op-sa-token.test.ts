import { afterAll, describe, expect, test } from "bun:test";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { resolveOpSaToken } from "./op-sa-token.ts";

const dir = mkdtempSync(join(tmpdir(), "op-sa-token-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

const PATH = process.env.PATH ?? "/usr/bin:/bin";

describe("resolveOpSaToken", () => {
  test("nothing configured -> unconfigured, never a default file", () => {
    expect(resolveOpSaToken({ PATH, HOME: dir })).toEqual({ kind: "unconfigured" });
  });

  test("environment token wins over command and file", () => {
    const r = resolveOpSaToken({
      PATH,
      OP_SERVICE_ACCOUNT_TOKEN: "ops_env",
      OP_SA_TOKEN_CMD: "/usr/bin/false",
      OP_SA_TOKEN_FILE: join(dir, "absent"),
    });
    expect(r).toEqual({ kind: "token", token: "ops_env", source: "env" });
  });

  test("command stdout is the token; argv is not shell-interpreted", () => {
    const r = resolveOpSaToken({ PATH, OP_SA_TOKEN_CMD: "printf %s ops_cmd;$HOME" });
    // A shell would have split on ';' and expanded $HOME. Spawned directly, printf
    // receives the literal word and prints it.
    expect(r).toEqual({ kind: "token", token: "ops_cmd;$HOME", source: "command" });
  });

  test("command wins over file", () => {
    const file = join(dir, "tok-a");
    writeFileSync(file, "ops_file\n");
    const r = resolveOpSaToken({ PATH, OP_SA_TOKEN_CMD: "printf %s ops_cmd", OP_SA_TOKEN_FILE: file });
    expect(r).toMatchObject({ kind: "token", token: "ops_cmd" });
  });

  test("failing or silent command is reported, not skipped", () => {
    expect(resolveOpSaToken({ PATH, OP_SA_TOKEN_CMD: "/usr/bin/false" }).kind).toBe("failed");
    expect(resolveOpSaToken({ PATH, OP_SA_TOKEN_CMD: "/usr/bin/true" }).kind).toBe("failed");
    expect(resolveOpSaToken({ PATH, OP_SA_TOKEN_CMD: "/nonexistent/prog" }).kind).toBe("failed");
  });

  test("named file is read and trimmed", () => {
    const file = join(dir, "tok-b");
    writeFileSync(file, "ops_file\n");
    chmodSync(file, 0o600);
    expect(resolveOpSaToken({ PATH, OP_SA_TOKEN_FILE: file })).toEqual({
      kind: "token",
      token: "ops_file",
      source: "file",
    });
  });

  test("missing or empty named file is reported", () => {
    const empty = join(dir, "tok-empty");
    writeFileSync(empty, "\n");
    expect(resolveOpSaToken({ PATH, OP_SA_TOKEN_FILE: join(dir, "absent") }).kind).toBe("failed");
    expect(resolveOpSaToken({ PATH, OP_SA_TOKEN_FILE: empty }).kind).toBe("failed");
  });
});
