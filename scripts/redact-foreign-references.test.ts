/**
 * scripts/redact-foreign-references.test.ts
 *
 * References to non-public repositories must not reach the CHANGELOG or a GitHub release.
 * The fictional slugs below stand in for a private repository; nothing here names a real
 * one. Visibility is injected so the unit tests make no network call; the last block runs
 * the REAL shipped transform, whose lookup fails closed for a repository that does not exist.
 */

import { describe, expect, test } from "bun:test";
import { createRequire } from "node:module";
import {
  ForeignReferenceRedactor,
  REDACTED_ISSUE,
  REDACTED_URL,
} from "./redact-foreign-references.ts";

const PUBLIC = new Set(["semantic-release/github", "anthropics/claude-code"]);
const isPublic = (slug: string) => PUBLIC.has(slug.toLowerCase());
const redactor = () => new ForeignReferenceRedactor("terrylica", "cc-skills", isPublic);

describe("ForeignReferenceRedactor.text", () => {
  test("a non-public owner/repo#N is generalised and counted", () => {
    const r = redactor();
    const out = r.text("(2026-10-18, acme-corp/secret-tool#319 and two earlier PRs that day)");
    expect(out).toBe(`(2026-10-18, ${REDACTED_ISSUE} and two earlier PRs that day)`);
    expect(out).not.toContain("acme-corp");
    expect(r.redactedCount).toBe(1);
  });

  test("this repository and public upstreams are kept unchanged", () => {
    const r = redactor();
    const text = "see terrylica/cc-skills#15, semantic-release/github#542 and #12";
    expect(r.text(text)).toBe(text);
    expect(r.redactedCount).toBe(0);
  });

  test("a github.com URL to a non-public repository is generalised; public URLs stay", () => {
    const r = redactor();
    const out = r.text(
      "details: https://github.com/acme-corp/secret-tool/pull/7#issuecomment-1 and https://github.com/anthropics/claude-code/issues/100.",
    );
    expect(out).toBe(`details: ${REDACTED_URL} and https://github.com/anthropics/claude-code/issues/100.`);
    expect(r.redactedCount).toBe(1);
  });

  test("a slug inside a path or URL is not mistaken for a reference", () => {
    const r = redactor();
    const text = "~/gh/acme-corp/secret-tool is a path, not a reference";
    expect(r.text(text)).toBe(text);
  });

  test("empty values pass through", () => {
    expect(redactor().text(null)).toBeNull();
    expect(redactor().text("")).toBe("");
  });
});

describe("ForeignReferenceRedactor.references", () => {
  test("drops non-public cross-repository references, keeps local and public ones", () => {
    const r = redactor();
    const refs = [
      { owner: null, repository: null, issue: "15" },
      { owner: "acme-corp", repository: "secret-tool", issue: "319" },
      { owner: "semantic-release", repository: "github", issue: "542" },
      { owner: null, repository: "cc-skills", issue: "3" },
      { owner: null, repository: "secret-tool", issue: "4" },
    ];
    expect(r.references(refs).map((x) => x.issue)).toEqual(["15", "542", "3"]);
    expect(r.redactedCount).toBe(2);
  });
});

describe("release.config.cjs applies the redaction on the release path", () => {
  const require = createRequire(import.meta.url);
  const config = require("../release.config.cjs");
  const plugin = config.plugins.find(
    (p: unknown) => Array.isArray(p) && p[0] === "@semantic-release/release-notes-generator",
  );
  const transform = plugin[1].writerOpts.transform;
  const CONTEXT = { host: "https://github.com", owner: "terrylica", repository: "cc-skills" };
  // A repository that does not exist: the real lookup gets a 404 (or no network) and must
  // treat it as not public.
  const GHOST = "terrylica-nonexistent-org-zz9/never-created-repo-zz9";

  test("subject, body and references all lose a non-public reference (fails closed)", () => {
    const out = transform(
      {
        type: "fix",
        scope: "itp-hooks",
        subject: `gate fix for ${GHOST}#319`,
        hash: "93dcfbfc00000000000000000000000000000000",
        notes: [],
        references: [
          { owner: GHOST.split("/")[0], repository: GHOST.split("/")[1], issue: "319", action: null },
          { owner: null, repository: null, issue: "15", action: "closes" },
        ],
        body: `Measured on 2026-10-18 (${GHOST}#319 and two earlier PRs).`,
      },
      CONTEXT,
    );
    const rendered = JSON.stringify(out);
    expect(rendered).not.toContain("nonexistent-org-zz9");
    expect(out.subject).toContain(REDACTED_ISSUE);
    expect(out.body).toContain(REDACTED_ISSUE);
    expect(out.references.map((x: { issue: string }) => x.issue)).toEqual(["15"]);
  }, 40_000);
});
