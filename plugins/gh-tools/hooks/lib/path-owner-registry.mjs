// path-owner-registry.mjs — resolve a local filesystem path to its intended
// GitHub owner, from the machine-readable SSoT at ~/.claude/path-owner-registry.toml.
//
// Zero dependencies: a tiny purpose-built reader for the registry's flat
// `[[mapping]]` shape (path_prefix / owner / allow_orgs). No general TOML parser,
// no `gh`, no network — safe to call from a PreToolUse hook.
//
// Consumed by pretooluse-path-owner-guard.mjs. Override the registry location for
// tests with the PATH_OWNER_REGISTRY env var.

import { existsSync, readFileSync } from "fs";
import { homedir } from "os";
import { join, resolve } from "path";

/** Default SSoT location; override with PATH_OWNER_REGISTRY for tests. */
export function registryPath() {
  return process.env.PATH_OWNER_REGISTRY || join(homedir(), ".claude", "path-owner-registry.toml");
}

function expandTilde(p, home) {
  if (p === "~") return home;
  if (p.startsWith("~/")) return home + p.slice(1);
  return p;
}

/** Parse the flat `[[mapping]]` array. Ignores top-level keys and other tables. */
export function parseRegistry(text) {
  const mappings = [];
  let current = null;
  for (const rawLine of text.split("\n")) {
    const line = rawLine.replace(/#.*$/, "").trim(); // registry values never contain '#'
    if (!line) continue;
    if (line === "[[mapping]]") {
      current = {};
      mappings.push(current);
      continue;
    }
    if (line.startsWith("[")) {
      current = null; // some other table — stop assigning keys to a mapping
      continue;
    }
    const kv = line.match(/^([A-Za-z0-9_]+)\s*=\s*(.+)$/);
    if (!kv || !current) continue;
    const key = kv[1];
    const value = kv[2].trim();
    if (value.startsWith("[")) {
      current[key] = [...value.matchAll(/"([^"]*)"/g)].map((m) => m[1]);
    } else {
      const quoted = value.match(/^"([^"]*)"/);
      current[key] = quoted ? quoted[1] : value;
    }
  }
  return mappings.filter((m) => m.path_prefix && m.owner);
}

/**
 * Resolve the expected GitHub owner for `targetPath` (longest matching prefix wins).
 * Returns { owner, matchedPrefix, allowOrgs } or null when unmapped / registry absent.
 */
export function resolveExpectedOwner(targetPath) {
  const home = homedir();
  const path = registryPath();
  if (!existsSync(path)) return null;
  let mappings;
  try {
    mappings = parseRegistry(readFileSync(path, "utf-8"));
  } catch {
    return null;
  }
  const abs = resolve(targetPath);
  let best = null;
  for (const mapping of mappings) {
    const prefixAbs = resolve(expandTilde(mapping.path_prefix, home));
    if (abs === prefixAbs || abs.startsWith(`${prefixAbs}/`)) {
      if (!best || prefixAbs.length > best.prefixAbs.length) {
        best = { mapping, prefixAbs };
      }
    }
  }
  if (!best) return null;
  return {
    owner: best.mapping.owner,
    matchedPrefix: best.mapping.path_prefix,
    allowOrgs: best.mapping.allow_orgs || [],
  };
}

/** Extract the owner segment from a git remote URL (host-alias aware). */
export function ownerFromGitUrl(url) {
  if (!url) return null;
  // SSH / scp-like: git@github.com-<alias>:owner/repo(.git)  or  git@github.com:owner/repo
  let m = url.match(/^[^@\s]*@[^:\s]+:([^/\s]+)\/[^/\s]+/);
  if (m) return m[1];
  // URL form: proto://host/owner/repo
  m = url.match(/^[a-z]+:\/\/[^/\s]+\/([^/\s]+)\/[^/\s]+/i);
  if (m) return m[1];
  return null;
}
