/**
 * Effective hook inventory: every handler a session would load, from settings files, enabled plugins' hooks.json,
 * module-style plugin directories, and the sub-hooks the itp-hooks orchestrators run in-process.
 *
 * Orchestrator registries are read by static parsing of the installed source (a hook module runs on import, so it
 * is never imported). Only ids, script paths, matchers and timeouts are reported, never a hook's full command.
 */
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { join } from "node:path";
import { hookIdFromCommand, parseHookCommand } from "./command.ts";

export interface SubhookRow {
  name: string;
  timeoutMs: number | null;
}

export interface HandlerRow {
  event: string;
  matcher: string;
  source: string;
  kind: "command" | "prompt" | "module" | "other";
  hookId: string;
  script: string | null;
  timeoutSec: number | null;
  /** Id of the hook's statusMessage: Claude Code records a hook that has one under that text instead of its command. */
  statusId?: string;
  subhooks?: SubhookRow[];
}

/** statusId → hookId for every handler with a statusMessage, so its transcript records count under its script. */
export function statusAliases(inv: Inventory): Map<string, string> {
  const aliases = new Map<string, string>();
  for (const h of inv.handlers) if (h.statusId && h.statusId !== h.hookId) aliases.set(h.statusId, h.hookId);
  return aliases;
}

export interface Inventory {
  settingsFiles: string[];
  plugins: { id: string; version: string | null; installPath: string | null; hooksJson: boolean; registrations: number }[];
  handlers: HandlerRow[];
  totals: { registrations: number; subhooks: number; byEvent: Record<string, number>; bySource: Record<string, number> };
  launcherDiff?: { onlyInFirst: string[]; onlyInSecond: string[] };
  warnings: string[];
}

/** Orchestrator script → the registry constant it runs (itp-hooks). */
export const ORCHESTRATOR_REGISTRIES: Record<string, string> = {
  "pretooluse-bash-guard-orchestrator.ts": "BASH_GUARD_REGISTRY",
  "pretooluse-write-edit-orchestrator.ts": "PRETOOLUSE_EDIT_TIME_ORCHESTRATOR_SUBHOOK_REGISTRY",
  "posttooluse-write-edit-orchestrator.ts": "POSTTOOLUSE_EDIT_TIME_ORCHESTRATOR_SUBHOOK_REGISTRY",
  "stop-orchestrator.ts": "SUBHOOKS",
};

type JsonObject = Record<string, unknown>;

function readJson(path: string): JsonObject | null {
  try {
    return JSON.parse(readFileSync(path, "utf8")) as JsonObject;
  } catch {
    return null;
  }
}

/** Index just past the `]` that closes the `[` at `open`, skipping string and template literals and comments. */
function matchingBracket(text: string, open: number): number {
  let depth = 0;
  for (let i = open; i < text.length; i++) {
    const c = text[i];
    if (c === '"' || c === "'" || c === "`") {
      const quote = c;
      for (i++; i < text.length && text[i] !== quote; i++) if (text[i] === "\\") i++;
      continue;
    }
    if (c === "/" && text[i + 1] === "/") {
      i = text.indexOf("\n", i);
      if (i < 0) return -1;
      continue;
    }
    if (c === "/" && text[i + 1] === "*") {
      i = text.indexOf("*/", i + 2) + 1;
      if (i <= 0) return -1;
      continue;
    }
    if (c === "[") depth++;
    else if (c === "]" && --depth === 0) return i + 1;
  }
  return -1;
}

/** Sub-hook names and timeouts from `const <registry> … = [ … ]` in an orchestrator's source. */
export function parseOrchestratorRegistry(source: string, registry: string): SubhookRow[] | null {
  const decl = new RegExp(`(?:const|let)\\s+${registry}\\b[^=]*=\\s*\\[`).exec(source);
  if (!decl) return null;
  const open = decl.index + decl[0].length - 1;
  const close = matchingBracket(source, open);
  if (close < 0) return null;
  const body = source.slice(open, close);
  const names = [...body.matchAll(/(?<=[{,\s])name:\s*"([^"]+)"/g)];
  return names.map((m, k) => {
    const end = k + 1 < names.length ? (names[k + 1]?.index ?? body.length) : body.length;
    const chunk = body.slice(m.index ?? 0, end);
    const t = /timeoutMs:\s*([\d_]+)/.exec(chunk);
    return { name: m[1] ?? "", timeoutMs: t ? Number((t[1] ?? "").replaceAll("_", "")) : null };
  });
}

function resolveScript(scriptToken: string | null, pluginRoot: string | null): string | null {
  if (!scriptToken) return null;
  const home = process.env.HOME ?? "";
  let p = scriptToken.replace(/\$\{HOME\}|\$HOME/g, home);
  if (pluginRoot) p = p.replace(/\$\{CLAUDE_PLUGIN_ROOT\}|\$CLAUDE_PLUGIN_ROOT/g, pluginRoot);
  if (p.startsWith("~/")) p = join(home, p.slice(2));
  return p;
}

function handlersFromHooksObject(hooks: unknown, source: string, pluginRoot: string | null, warnings: string[]): HandlerRow[] {
  const rows: HandlerRow[] = [];
  if (!hooks || typeof hooks !== "object") return rows;
  for (const [event, groups] of Object.entries(hooks as JsonObject)) {
    if (!Array.isArray(groups)) continue;
    for (const group of groups as JsonObject[]) {
      const matcher = typeof group.matcher === "string" ? group.matcher : "*";
      const entries = Array.isArray(group.hooks) ? (group.hooks as JsonObject[]) : [];
      for (const h of entries) {
        const type = typeof h.type === "string" ? h.type : "other";
        const timeoutSec = typeof h.timeout === "number" ? h.timeout : null;
        if (type !== "command" || typeof h.command !== "string") {
          rows.push({ event, matcher, source, kind: type === "prompt" ? "prompt" : "other", hookId: `${type}:${event}`, script: null, timeoutSec });
          continue;
        }
        const parsed = parseHookCommand(h.command);
        const script = parsed.inline ? null : resolveScript(parsed.scriptToken, pluginRoot);
        const row: HandlerRow = { event, matcher, source, kind: "command", hookId: hookIdFromCommand(h.command), script, timeoutSec };
        if (typeof h.statusMessage === "string" && h.statusMessage !== "") row.statusId = hookIdFromCommand(h.statusMessage);
        const registry = ORCHESTRATOR_REGISTRIES[row.hookId];
        if (registry && script) {
          try {
            const subhooks = parseOrchestratorRegistry(readFileSync(script, "utf8"), registry);
            if (subhooks) row.subhooks = subhooks;
            else warnings.push(`${row.hookId}: registry ${registry} not found in ${script}`);
          } catch {
            warnings.push(`${row.hookId}: cannot read ${script}`);
          }
        }
        rows.push(row);
      }
    }
  }
  return rows;
}

export interface InventoryOptions {
  configRoots: string[];
  projectDir?: string | undefined;
  pluginDirs?: string[] | undefined;
}

function realOrSelf(p: string): string {
  try {
    return realpathSync(p);
  } catch {
    return p;
  }
}

export function buildInventory(opts: InventoryOptions): Inventory {
  const warnings: string[] = [];
  const handlers: HandlerRow[] = [];
  const settingsFiles: string[] = [];
  const plugins: Inventory["plugins"] = [];
  const perRootKeys: Set<string>[] = [];

  const roots = [...new Map(opts.configRoots.map((r) => [realOrSelf(r), r])).values()];
  const primary = roots[0];
  roots.forEach((root, idx) => {
    const settingsPath = join(root, "settings.json");
    const settings = readJson(settingsPath);
    if (!settings) {
      warnings.push(`no readable settings.json in ${root}`);
      perRootKeys.push(new Set());
      return;
    }
    const rows = handlersFromHooksObject(settings.hooks, `settings:${settingsPath}`, null, warnings);
    perRootKeys.push(new Set(rows.map((r) => `${r.event}|${r.matcher}|${r.hookId}`)));
    if (idx > 0) return;
    settingsFiles.push(settingsPath);
    handlers.push(...rows);
  });
  let launcherDiff: Inventory["launcherDiff"];
  if (perRootKeys.length >= 2) {
    const a = perRootKeys[0] ?? new Set<string>();
    const b = perRootKeys[1] ?? new Set<string>();
    launcherDiff = {
      onlyInFirst: [...a].filter((k) => !b.has(k)).toSorted(),
      onlyInSecond: [...b].filter((k) => !a.has(k)).toSorted(),
    };
  }

  if (primary) {
    const settings = readJson(join(primary, "settings.json")) ?? {};
    const enabled = Object.entries((settings.enabledPlugins as JsonObject | undefined) ?? {})
      .filter(([, on]) => on === true)
      .map(([id]) => id);
    const installed = (readJson(join(primary, "plugins", "installed_plugins.json"))?.plugins as JsonObject | undefined) ?? {};
    for (const id of enabled) {
      const entry = (installed[id] as JsonObject[] | undefined)?.[0];
      const installPath = typeof entry?.installPath === "string" ? entry.installPath : null;
      const version = typeof entry?.version === "string" ? entry.version : null;
      const hooksPath = installPath ? join(installPath, "hooks", "hooks.json") : null;
      const hooksJson = hooksPath ? readJson(hooksPath) : null;
      let registrations = 0;
      if (hooksJson) {
        if (Array.isArray(hooksJson.modules)) {
          for (const mod of hooksJson.modules) {
            handlers.push({ event: "module", matcher: "*", source: `plugin:${id}${version ? `@${version}` : ""}`, kind: "module", hookId: String(mod), script: null, timeoutSec: null });
            registrations++;
          }
        }
        const rows = handlersFromHooksObject(hooksJson.hooks ?? null, `plugin:${id}${version ? `@${version}` : ""}`, installPath, warnings);
        registrations += rows.length;
        handlers.push(...rows);
      } else if (!installPath) {
        warnings.push(`enabled plugin ${id} is not in installed_plugins.json`);
      }
      plugins.push({ id, version, installPath, hooksJson: hooksJson !== null, registrations });
    }
  }

  for (const dir of opts.pluginDirs ?? []) {
    const hooksJson = readJson(join(dir, "hooks", "hooks.json"));
    if (!hooksJson) continue;
    const source = `plugin-dir:${dir.split("/").pop() ?? dir}`;
    for (const mod of Array.isArray(hooksJson.modules) ? hooksJson.modules : []) {
      handlers.push({ event: "module", matcher: "*", source, kind: "module", hookId: String(mod), script: null, timeoutSec: null });
    }
    handlers.push(...handlersFromHooksObject(hooksJson.hooks ?? null, source, dir, warnings));
  }

  if (opts.projectDir) {
    for (const name of ["settings.json", "settings.local.json"]) {
      const p = join(opts.projectDir, ".claude", name);
      const s = existsSync(p) ? readJson(p) : null;
      if (!s) continue;
      settingsFiles.push(p);
      handlers.push(...handlersFromHooksObject(s.hooks, `settings:${p}`, null, warnings));
    }
  }

  const byEvent: Record<string, number> = {};
  const bySource: Record<string, number> = {};
  let subhooks = 0;
  for (const h of handlers) {
    byEvent[h.event] = (byEvent[h.event] ?? 0) + 1;
    const src = h.source.startsWith("settings:") ? "settings" : h.source.split("@")[0] ?? h.source;
    bySource[src] = (bySource[src] ?? 0) + 1;
    subhooks += h.subhooks?.length ?? 0;
  }
  const inventory: Inventory = { settingsFiles, plugins, handlers, totals: { registrations: handlers.length, subhooks, byEvent, bySource }, warnings };
  if (launcherDiff) inventory.launcherDiff = launcherDiff;
  return inventory;
}
