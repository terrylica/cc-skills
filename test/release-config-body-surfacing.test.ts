/**
 * Tests that release.config.cjs surfaces the full multi-paragraph commit BODY in
 * generated release notes — the whole point of converting .releaserc.yml to JS.
 *
 * The default Angular preset renders only the commit subject; this config adds a
 * body-preserving writerOpts.transform + a commitPartial that prints {{body}}.
 * We reproduce the real conventional-changelog-writer pipeline:
 *   merged = { ...commit, ...transform(commit, ctx), raw: commit }   // writer merge
 *   output = Handlebars.compile(commitPartial)(merged, { data: { root: ctx } })
 * and assert the body text appears alongside the subject + short-hash link.
 *
 * Run: bun test test/release-config-body-surfacing.test.ts
 */

import { describe, expect, it } from "bun:test";
import { createRequire } from "node:module";
import Handlebars from "handlebars";

const require = createRequire(import.meta.url);
const releaseConfig = require("../release.config.cjs");

type CommitTransform = (
  commit: Record<string, unknown>,
  context: unknown,
) => Record<string, unknown> | undefined;

function getNotesWriterOpts(): { transform: CommitTransform; commitPartial: string } {
  const entry = releaseConfig.plugins.find(
    (p: unknown) => Array.isArray(p) && p[0] === "@semantic-release/release-notes-generator",
  );
  expect(entry).toBeDefined();
  return entry[1].writerOpts;
}

const CONTEXT = {
  host: "https://github.com",
  owner: "terrylica",
  repository: "cc-skills",
  repoUrl: "",
  linkReferences: true,
  commit: "commit",
  issue: "issues",
};

function sampleCommit(overrides: Record<string, unknown> = {}) {
  return {
    type: "feat",
    scope: "itp-hooks",
    subject: "add the release-notes extensiveness guard",
    header: "feat(itp-hooks): add the release-notes extensiveness guard",
    body: "This narrative paragraph explains WHY the release matters.\n\nA second paragraph adds detail and impact.",
    hash: "abcdef1234567890",
    shortHash: "abcdef1",
    notes: [],
    references: [],
    mentions: [],
    merge: null,
    ...overrides,
  };
}

describe("release.config.cjs — structure", () => {
  it("exports 9 plugins releasing from main", () => {
    expect(releaseConfig.branches).toEqual(["main"]);
    expect(releaseConfig.plugins).toHaveLength(9);
  });

  it("preserves the literal lodash version placeholder in exec commands", () => {
    const flat = JSON.stringify(releaseConfig, (_k, v) =>
      typeof v === "function" ? "[fn]" : v,
    );
    const dollar = "$";
    expect(flat).toContain(`${dollar}{nextRelease.version}`);
  });
});

describe("release.config.cjs — writerOpts transform", () => {
  it("keeps the commit body and maps type → Features", () => {
    const { transform } = getNotesWriterOpts();
    const out = transform(sampleCommit(), CONTEXT);
    expect(out.type).toBe("Features");
    expect(out.body).toContain("narrative paragraph");
    expect(out.body).toContain("second paragraph");
  });

  it("maps fix → Bug Fixes and discards unreleased types (chore)", () => {
    const { transform } = getNotesWriterOpts();
    expect(transform(sampleCommit({ type: "fix" }), CONTEXT).type).toBe("Bug Fixes");
    expect(transform(sampleCommit({ type: "chore" }), CONTEXT)).toBeUndefined();
  });
});

describe("release.config.cjs — commitPartial rendering (full pipeline)", () => {
  const render = (commit: Record<string, unknown>) => {
    const { transform, commitPartial } = getNotesWriterOpts();
    const patch = transform(commit, CONTEXT);
    const merged = { ...commit, ...patch, raw: commit }; // mirrors writer merge
    return Handlebars.compile(commitPartial)(merged, { data: { root: CONTEXT } });
  };

  it("renders the multi-paragraph body under the commit line", () => {
    const out = render(sampleCommit());
    expect(out).toContain("add the release-notes extensiveness guard"); // subject
    expect(out).toContain("abcdef1"); // short-hash link text
    expect(out).toContain("This narrative paragraph explains WHY"); // body p1
    expect(out).toContain("A second paragraph adds detail"); // body p2
  });

  it("omits the body block when a commit has no body", () => {
    const out = render(sampleCommit({ body: "" }));
    expect(out).toContain("add the release-notes extensiveness guard");
    expect(out).not.toContain("narrative paragraph");
  });
});
