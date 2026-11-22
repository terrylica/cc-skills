/**
 * Turn a hook `command` string into a stable, payload-free hook id (the script's file name).
 *
 * Port of parseHookCommand in scripts/validate-plugins.mjs, whose SSoT is tasks/lib/hook-command-parsing.sh: it
 * strips an `env` prefix, skips interpreter flags and a `run` subcommand, and takes the next token as the script.
 * command.test.ts fails when HOOK_COMMAND_INTERPRETERS drifts from the validator's set.
 *
 * Added here: an id is a name only when the command names a script (a path, or a file with a script extension) or an
 * executable found on PATH under exactly that spelling. Anything else is `inline:<hash>` of the command: an inline
 * shell script (`bash -c '…'`, `if …; then`), and two texts Claude Code records in a hook's `command` field that are
 * not commands at all, a configured `statusMessage` and a prompt hook's prompt with the user's words substituted
 * into it. The command text itself never leaves this module.
 */
import { readdirSync } from "node:fs";
import { basename, dirname } from "node:path";

export const HOOK_COMMAND_INTERPRETERS = new Set([
  "bun",
  "bunx",
  "node",
  "go",
  "gofmt",
  "moon",
  "moonx",
  "zig",
  "deno",
  "npx",
  "bash",
  "sh",
  "zsh",
  "python",
  "python3",
  "uv",
  "uvx",
]);

const SHELLS = new Set(["bash", "sh", "zsh"]);
const ENV_OPTIONS_TAKING_A_SEPARATE_ARGUMENT = new Set(["-u", "--unset", "-C", "--chdir", "-S", "--split-string"]);

function stripEnvPrefix(tokens: string[]): string[] {
  if (tokens.length === 0 || tokens[0]?.split("/").pop() !== "env") return tokens;
  let i = 1;
  while (i < tokens.length) {
    const token = tokens[i] ?? "";
    if (ENV_OPTIONS_TAKING_A_SEPARATE_ARGUMENT.has(token)) {
      i += 2;
      continue;
    }
    if (token.startsWith("-") || token.includes("=")) {
      i += 1;
      continue;
    }
    break;
  }
  const rest = tokens.slice(i);
  return rest.length < tokens.length ? stripEnvPrefix(rest) : rest;
}

export interface ParsedHookCommand {
  interpreter: string | null;
  scriptToken: string | null;
  inline: boolean;
}

export function parseHookCommand(command: string): ParsedHookCommand {
  const tokens = stripEnvPrefix(
    command
      .split(/\s+/)
      .filter(Boolean)
      .map((t) => t.replace(/["']/g, "")),
  );
  if (tokens.length === 0) return { interpreter: null, scriptToken: null, inline: false };
  const head = tokens[0]?.split("/").pop() ?? "";
  if (!HOOK_COMMAND_INTERPRETERS.has(head)) return { interpreter: null, scriptToken: tokens[0] ?? null, inline: false };
  let i = 1;
  while (i < tokens.length && ((tokens[i] ?? "").startsWith("-") || tokens[i] === "run")) {
    const flag = tokens[i] ?? "";
    if (SHELLS.has(head) && /^-[a-z]*c[a-z]*$/.test(flag)) return { interpreter: head, scriptToken: null, inline: true };
    i += 1;
  }
  return { interpreter: head, scriptToken: tokens[i] ?? null, inline: false };
}

/** A short, stable hash so an inline command can be counted without being stored. */
export function shortHash(text: string): string {
  return Bun.hash(text).toString(16).slice(0, 10);
}

const SCRIPT_EXTENSION = /\.(sh|bash|zsh|ts|mts|cts|mjs|cjs|js|py|rb|pl)$/;
const onPathCache = new Map<string, boolean>();

/** True when `name` is an executable on PATH under exactly this spelling; macOS file systems ignore case, so "Make" finds make. */
function isExecutableOnPath(name: string): boolean {
  let hit = onPathCache.get(name);
  if (hit === undefined) {
    hit = false;
    const found = /^[\w.+-]{1,64}$/.test(name) ? Bun.which(name) : null;
    if (found) {
      try {
        hit = readdirSync(dirname(found)).includes(name);
      } catch {
        hit = false;
      }
    }
    onPathCache.set(name, hit);
  }
  return hit;
}

/** The id a hook is counted under: its script's file name, an executable's name, or inline:<hash> for anything else. */
export function hookIdFromCommand(command: string): string {
  if (command === "callback") return "builtin:callback";
  const parsed = parseHookCommand(command);
  const token = parsed.scriptToken;
  if (parsed.inline || !token || token.includes("://") || token.includes("@")) return `inline:${shortHash(command)}`;
  if (token.includes("/") || SCRIPT_EXTENSION.test(token)) return basename(token);
  if (parsed.interpreter === null && isExecutableOnPath(token)) return token;
  return `inline:${shortHash(command)}`;
}
