/**
 * op-sa-token.ts — resolve a 1Password Service Account token for `op`, from sources the
 * USER configured. The plugin's one implementation; tg-cli.ts uses it for every `op` call.
 *
 * Resolution order — these three, nothing else, and NO default path:
 *   1. OP_SERVICE_ACCOUNT_TOKEN already in the environment (used as-is).
 *   2. OP_SA_TOKEN_CMD — a command whose stdout is the token, e.g.
 *        export OP_SA_TOKEN_CMD='vault get op-service-account token'
 *      Split on whitespace into an argv and spawned DIRECTLY: no shell, so no quoting,
 *      globbing, expansion, pipes or redirections.
 *   3. OP_SA_TOKEN_FILE — a token file, read only when the user names one.
 *
 * Until 2026-10 this plugin silently read a hard-coded plaintext file under ~/.claude;
 * that default is gone. The token is returned to the caller for the `op` child's
 * environment and must never be put in an argv (readable from the process table).
 */

import { readFileSync } from "node:fs";

export type OpSaTokenResult =
  | { kind: "token"; token: string; source: "env" | "command" | "file" }
  | { kind: "unconfigured" }
  | { kind: "failed"; reason: string };

export const OP_SA_TOKEN_UNCONFIGURED_HINT =
  "no 1Password service-account token source is configured: export OP_SERVICE_ACCOUNT_TOKEN, " +
  "or set OP_SA_TOKEN_CMD to a command that prints it (e.g. OP_SA_TOKEN_CMD='vault get op-service-account token'), " +
  "or set OP_SA_TOKEN_FILE to a chmod-600 file holding it";

type Env = Record<string, string | undefined>;

export function resolveOpSaToken(env: Env = process.env): OpSaTokenResult {
  const fromEnv = env.OP_SERVICE_ACCOUNT_TOKEN?.trim();
  if (fromEnv) {
    return { kind: "token", token: fromEnv, source: "env" };
  }

  const cmd = env.OP_SA_TOKEN_CMD?.trim();
  if (cmd) {
    const argv = cmd.split(/\s+/);
    let proc: ReturnType<typeof Bun.spawnSync>;
    try {
      // stdin closed and stderr inherited so a failing command explains itself; the token
      // arrives on stdout only.
      proc = Bun.spawnSync(argv, { env: env as Record<string, string>, stdin: "ignore", stdout: "pipe", stderr: "inherit" });
    } catch (error) {
      return { kind: "failed", reason: `OP_SA_TOKEN_CMD (${argv[0]}) could not start: ${(error as Error).message}` };
    }
    if (proc.exitCode !== 0) {
      return { kind: "failed", reason: `OP_SA_TOKEN_CMD (${argv[0]}) exited ${proc.exitCode}` };
    }
    const token = (proc.stdout?.toString() ?? "").trim();
    if (!token) {
      return { kind: "failed", reason: `OP_SA_TOKEN_CMD (${argv[0]}) printed nothing` };
    }
    return { kind: "token", token, source: "command" };
  }

  const file = env.OP_SA_TOKEN_FILE?.trim();
  if (file) {
    let token: string;
    try {
      token = readFileSync(file, "utf8").trim();
    } catch (error) {
      return { kind: "failed", reason: `OP_SA_TOKEN_FILE ${file} is not readable: ${(error as Error).message}` };
    }
    if (!token) {
      return { kind: "failed", reason: `OP_SA_TOKEN_FILE ${file} is empty` };
    }
    return { kind: "token", token, source: "file" };
  }

  return { kind: "unconfigured" };
}
