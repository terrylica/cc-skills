// The vendored-bundle check (#91) must pass on current bundles, and catch a changed lockfile and a missing file.
import { afterEach, describe, expect, test } from "bun:test";
import { appendFileSync, cpSync, mkdirSync, mkdtempSync, rmSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

import { check, TARGETS } from "./vendor-plugin-deps.ts";

const REPO = resolve(import.meta.dir, "..");
const made: string[] = [];
afterEach(() => {
  for (const d of made.splice(0)) rmSync(d, { recursive: true, force: true });
});

/** A throwaway repo root holding one target's inputs and its committed outputs. */
function copyOf(id: string): { root: string; dir: string } {
  const t = TARGETS.find((x) => x.id === id);
  if (!t) throw new Error(`no target ${id}`);
  const root = mkdtempSync(join(tmpdir(), "vendor-check-"));
  made.push(root);
  const dir = join(root, t.dir);
  mkdirSync(join(dir, "vendor"), { recursive: true });
  for (const f of ["package.json", "bun.lock"]) cpSync(join(REPO, t.dir, f), join(dir, f));
  cpSync(join(REPO, t.dir, "vendor"), join(dir, "vendor"), { recursive: true });
  return { root, dir };
}

describe("vendor-plugin-deps --check", () => {
  test("every committed bundle is current", () => {
    expect(check()).toEqual([]);
  });
  test("a changed bun.lock makes the bundle stale", () => {
    const { root, dir } = copyOf("gdrive");
    const gdrive = TARGETS.filter((t) => t.id === "gdrive");
    expect(check(gdrive, root)).toEqual([]);
    appendFileSync(join(dir, "bun.lock"), "\n");
    expect(check(gdrive, root)).toEqual([expect.stringContaining("is stale")]);
  });
  test("a missing bundle, declaration or license file is reported", () => {
    const { root, dir } = copyOf("gmail");
    const gmail = TARGETS.filter((t) => t.id === "gmail");
    unlinkSync(join(dir, "vendor", "googleapis-gmail.d.ts"));
    unlinkSync(join(dir, "vendor", "googleapis-gmail.LICENSES.txt"));
    expect(check(gmail, root).join("\n")).toMatch(/type declarations[\s\S]*license notice/);
    unlinkSync(join(dir, "vendor", "googleapis-gmail.js"));
    expect(check(gmail, root)).toEqual([expect.stringContaining("is missing")]);
  });
});
