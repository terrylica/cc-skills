#!/usr/bin/env bun
/**
 * Print the ruff rule codes a repository's configuration IGNORES for one file, one per line.
 *
 *   bun ruff-ignored-codes.ts <repository-root> <file-path-relative-to-root>
 *
 * Used by code-correctness-guard.sh's inline-ignore audit (2026-10-17): a `# noqa: CODE` on a code
 * the repository has already decided to ignore is that repository's convention, not a one-off.
 *
 * Read properly, not grepped: a grep for the quoted code anywhere in pyproject.toml also matched
 * `select`/`extend-select` (rules turned ON) and per-file entries for unrelated paths (found in
 * review). Only these count: `ignore` and `extend-ignore` (top level or under `lint`), and
 * `per-file-ignores` / `extend-per-file-ignores` entries whose glob matches the file. ruff.toml,
 * .ruff.toml (top level) and pyproject.toml (`[tool.ruff]`) are read; a missing or malformed file
 * contributes nothing. Exit 0 always; no output means "no configured ignore applies".
 */

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

type Table = Record<string, unknown>;

function asTable(value: unknown): Table | null {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? (value as Table) : null;
}

function codesIn(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((v): v is string => typeof v === "string") : [];
}

function ruffSections(root: string): Table[] {
  const sections: Table[] = [];
  for (const name of ["ruff.toml", ".ruff.toml"]) {
    const path = join(root, name);
    if (!existsSync(path)) continue;
    try {
      const parsed = asTable(Bun.TOML.parse(readFileSync(path, "utf8")));
      if (parsed) sections.push(parsed);
    } catch {
      // malformed: contributes nothing
    }
  }
  const pyproject = join(root, "pyproject.toml");
  if (existsSync(pyproject)) {
    try {
      const ruff = asTable(asTable(asTable(Bun.TOML.parse(readFileSync(pyproject, "utf8")))?.tool)?.ruff);
      if (ruff) sections.push(ruff);
    } catch {
      // malformed: contributes nothing
    }
  }
  return sections;
}

/** Codes ignored for `relativePath` by the configuration at `root`. Exported for tests. */
export function ruffIgnoredCodes(root: string, relativePath: string): string[] {
  const codes = new Set<string>();
  for (const section of ruffSections(root)) {
    for (const scope of [section, asTable(section.lint)]) {
      if (scope === null) continue;
      for (const key of ["ignore", "extend-ignore"]) for (const c of codesIn(scope[key])) codes.add(c);
      for (const key of ["per-file-ignores", "extend-per-file-ignores"]) {
        const table = asTable(scope[key]);
        if (table === null) continue;
        for (const [pattern, list] of Object.entries(table)) {
          let matches = false;
          try {
            matches = new Bun.Glob(pattern).match(relativePath);
          } catch {
            matches = false;
          }
          if (matches) for (const c of codesIn(list)) codes.add(c);
        }
      }
    }
  }
  return [...codes].sort();
}

if (import.meta.main) {
  const [root, relativePath] = process.argv.slice(2);
  if (root && relativePath) {
    try {
      const out = ruffIgnoredCodes(root, relativePath);
      if (out.length > 0) process.stdout.write(`${out.join("\n")}\n`);
    } catch {
      // never fail the hook
    }
  }
}
