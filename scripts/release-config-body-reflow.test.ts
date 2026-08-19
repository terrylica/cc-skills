/**
 * scripts/release-config-body-reflow.test.ts
 *
 * semantic-release publishes through the GitHub API via @semantic-release/github, so the
 * PreToolUse guard on `gh release create` never sees it. That gap shipped v26.2.0 and
 * v27.0.1 with prose hard-wrapped at ~72 columns, which GFM renders as literal <br> —
 * the identical text being RIGHT in the commit and WRONG on the release page.
 *
 * The fix lives in release.config.cjs's writerOpts.transform. These tests exercise the
 * REAL config object, not a copy of the function, because the failure mode was a correct
 * reflow that nothing on the automatic path called.
 */

import { describe, expect, test } from "bun:test";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);

/** Pull the transform out of the real, shipped config. */
function realTransform(): (commit: unknown, context: unknown) => { body?: string } {
  const config = require("../release.config.cjs");
  const plugin = config.plugins.find(
    (p: unknown) => Array.isArray(p) && p[0] === "@semantic-release/release-notes-generator",
  );
  if (!plugin) throw new Error("release-notes-generator plugin not found in release.config.cjs");
  return plugin[1].writerOpts.transform;
}

const CONTEXT = {
  host: "https://github.com",
  owner: "terrylica",
  repository: "cc-skills",
  issue: "issues",
  commit: "commit",
};

const commitWith = (body: string | null | undefined) => ({
  type: "fix",
  scope: "marketplace",
  subject: "redact remaining third-party identifiers",
  hash: "20808049664fdd0f14a2bf264042303b648289aa",
  notes: [],
  references: [],
  body,
});

describe("release.config.cjs reflows commit bodies before publishing", () => {
  test("hard-wrapped prose is joined into one paragraph", () => {
    // Reproduces the shape that actually shipped in v27.0.1.
    const wrapped =
      "v27.0.0 shipped a partial scrub. This completes it. An 11-agent audit swept all\n" +
      "2602 tracked files across five dimensions (known-client strings, contact data,\n" +
      "narrative docs + CHANGELOG) and adversarially verified each hit.";
    const out = realTransform()(commitWith(wrapped), CONTEXT);
    expect(out.body).not.toContain("all\n2602");
    expect(out.body?.split("\n").filter((l) => l.trim().length > 0)).toHaveLength(1);
  });

  test("list structure survives — reflow must not glue bullets together", () => {
    const body = "Intro line one\nintro line two\n\n- first point\n- second point\n";
    const out = realTransform()(commitWith(body), CONTEXT);
    expect(out.body).toContain("\n- first point");
    expect(out.body).toContain("\n- second point");
    expect(out.body).toContain("Intro line one intro line two");
  });

  test("headings and code fences are left alone", () => {
    const body = "## What changed\n\n```sh\nmise run release:full\n```\n";
    const out = realTransform()(commitWith(body), CONTEXT);
    expect(out.body).toContain("## What changed");
    expect(out.body).toContain("```sh\nmise run release:full\n```");
  });

  test("an already-flat body is passed through with its content untouched", () => {
    // `reflowMarkdown` normalizes a trailing newline, which is invisible in GFM inside
    // the `{{body}}` template. Asserting exact bytes here would pin that incidental
    // detail instead of the property that matters: flat text is not mangled.
    const flat = "One long single-line paragraph that needs no reflow at all.";
    expect(realTransform()(commitWith(flat), CONTEXT).body?.trimEnd()).toBe(flat);
  });

  for (const [name, value] of [
    ["null", null],
    ["undefined", undefined],
    ["empty", ""],
  ] as const) {
    test(`a ${name} body does not throw`, () => {
      expect(() => realTransform()(commitWith(value), CONTEXT)).not.toThrow();
    });
  }
});

/**
 * Rendering the real template, not just the transform.
 *
 * The reflow alone was NOT enough. v27.0.1 had a second, independent defect: Handlebars
 * strips the trailing newline of a line holding a lone block tag, so the intended blank
 * line collapsed and the body was emitted directly under the `* subject` bullet — which
 * GFM reads as a lazy continuation and renders INSIDE the list item. A transform-only
 * test passes happily while every release still looks wrong, so the assertion has to be
 * made against rendered output.
 *
 * `handlebars` is a transitive dependency of the notes generator rather than a declared
 * one. That is acceptable here precisely because the thing under test is the notes
 * generator: if handlebars is missing, the release pipeline is already broken.
 */
function renderCommit(body: string): string {
  const config = require("../release.config.cjs");
  const plugin = config.plugins.find(
    (p: unknown) => Array.isArray(p) && p[0] === "@semantic-release/release-notes-generator",
  );
  const writerOpts = plugin[1].writerOpts;
  const handlebars = require("handlebars");
  return handlebars.compile(writerOpts.commitPartial)(
    writerOpts.transform(commitWith(body), CONTEXT),
    {},
  );
}

describe("the rendered notes put the body in its own paragraph", () => {
  test("a blank line separates the bullet from the body", () => {
    const rendered = renderCommit("Prose line one\nprose line two.\n");
    // The exact regression: bullet, blank line, body. One newline means a lazy
    // continuation and the body disappears into the bullet.
    expect(rendered).toMatch(/redact remaining third-party identifiers[^\n]*\n\nProse line one/);
  });

  test("the body is not indented into the list item", () => {
    const rendered = renderCommit("Prose line one\nprose line two.\n");
    const bodyLine = rendered.split("\n").find((l) => l.startsWith("Prose"));
    // A leading space or two would nest it back under the bullet in GFM.
    expect(bodyLine).toBe("Prose line one prose line two.");
  });

  test("rendered output carries no hard-wrapped prose", () => {
    const { isAlreadyFlat } = require("./reflow-release-notes.ts");
    const rendered = renderCommit(
      "v27.0.0 shipped a partial scrub. This completes it. An 11-agent audit swept all\n" +
        "2602 tracked files across five dimensions and verified each hit.\n",
    );
    expect(isAlreadyFlat(rendered)).toBe(true);
  });

  test("a commit with no body renders no stray blank paragraph", () => {
    const config = require("../release.config.cjs");
    const plugin = config.plugins.find(
      (p: unknown) => Array.isArray(p) && p[0] === "@semantic-release/release-notes-generator",
    );
    const writerOpts = plugin[1].writerOpts;
    const handlebars = require("handlebars");
    const rendered = handlebars.compile(writerOpts.commitPartial)(
      writerOpts.transform(commitWith(""), CONTEXT),
      {},
    );
    expect(rendered.trimEnd().split("\n").filter((l: string) => l.trim() === "")).toHaveLength(0);
  });
});

/**
 * The third and worst defect: silent truncation.
 *
 * conventional-commits-parser's default `fieldPattern` is /^-(.*?)-$/, which a line of
 * dashes matches. A setext heading underline or a horizontal rule therefore diverts every
 * remaining body line into a field no template emits. v27.0.1 shipped 8 of its commit's
 * 66 body lines. The extensiveness guard did not catch it because the loss happens
 * downstream of the guard, between parsing and rendering.
 */
describe("commit bodies are not truncated by markdown dashes", () => {
  const BODY_WITH_SETEXT = [
    "Intro paragraph explaining the change.",
    "",
    "What was still exposed",
    "----------------------",
    "* first finding",
    "* second finding",
    "",
    "Redactions",
    "----------",
    "  old -> new",
    "",
    "Closing paragraph that must survive.",
  ].join("\n");

  const MESSAGE = `fix(marketplace): redact identifiers\n\n${BODY_WITH_SETEXT}\n`;

  const parserOptsFor = (pluginName: string) => {
    const config = require("../release.config.cjs");
    const plugin = config.plugins.find((p: unknown) => Array.isArray(p) && p[0] === pluginName);
    if (!plugin) throw new Error(`${pluginName} not found in release.config.cjs`);
    return plugin[1].parserOpts;
  };

  const parseWith = async (pluginName: string) => {
    const { CommitParser } = await import("conventional-commits-parser");
    return new CommitParser(parserOptsFor(pluginName)).parse(MESSAGE);
  };

  for (const plugin of [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator",
  ]) {
    test(`${plugin} keeps the whole body`, async () => {
      const parsed = await parseWith(plugin);
      expect(parsed.body).toContain("Closing paragraph that must survive.");
      expect(parsed.body).toContain("second finding");
      expect(parsed.body?.split("\n")).toHaveLength(BODY_WITH_SETEXT.split("\n").length);
    });
  }

  test("the default parser truncates — proving the fix is what saves it", async () => {
    // Without this, the tests above would pass against a parser that never had the bug,
    // and the fix could be deleted with the suite still green.
    const { CommitParser } = await import("conventional-commits-parser");
    const parsed = new CommitParser().parse(MESSAGE);
    expect(parsed.body).not.toContain("Closing paragraph that must survive.");
  });

  test("both plugins share the same fieldPattern, or the notes and the bump disagree", () => {
    // The config already documents that these two must mirror. A fieldPattern on only
    // one of them means the analyzer and the writer see different commit bodies.
    const analyzer = parserOptsFor("@semantic-release/commit-analyzer");
    const writer = parserOptsFor("@semantic-release/release-notes-generator");
    expect(String(analyzer.fieldPattern)).toBe(String(writer.fieldPattern));
    expect(analyzer.noteKeywords).toEqual(writer.noteKeywords);
  });
});

/**
 * The escaper must be WIRED IN, not merely present.
 *
 * escape-commit-body-html.test.ts proves the function is correct in isolation. That is not
 * the same claim as "the published notes are escaped" — the reflow had exactly this gap,
 * where a correct module sat unused on the automatic path for 200 releases. Verified by
 * mutation: stubbing the escape call out of release.config.cjs fails these.
 */
describe("release.config.cjs escapes commit-body HTML", () => {
  const bodyOf = (body: string) => realTransform()(commitWith(body), CONTEXT).body;

  test("a generic type parameter survives instead of being deleted by GFM", () => {
    expect(bodyOf("a Map<Command,Handler> here")).toContain("Map&lt;Command,Handler>");
  });

  test("a tag named in prose does not become a real tag", () => {
    const out = bodyOf("GFM turns a newline into a literal <br>, so text is wrong.");
    expect(out).toContain("&lt;br>");
    expect(out).not.toContain("<br>");
  });

  test("a CLI placeholder is not swallowed", () => {
    expect(bodyOf("pass <uuid> to the tool")).toContain("&lt;uuid>");
  });

  test("escaping composes with reflow and aligned-block preservation", () => {
    // All three fixes on one body: escape, fold the prose, keep the table's rows and its
    // `->` arrows. Any one of them regressing shows up here.
    const out = bodyOf("A <uuid> and\nwrapped prose.\n\n  a    -> b\n  cc   -> d\n");
    expect(out).toContain("A &lt;uuid> and wrapped prose.");
    expect(out).toContain("  a    -> b\n  cc   -> d");
  });

  test("code spans are left literal, so notes do not publish a visible &lt;", () => {
    expect(bodyOf("the type is `Vec<T>` exactly")).toContain("`Vec<T>`");
  });
});

describe("the reflow module stays reachable from CommonJS", () => {
  test("release.config.cjs can require it — no top-level await", () => {
    // The regression this pins: adding a top-level `await` to reflow-release-notes.ts
    // makes Node refuse the require (ERR_REQUIRE_ASYNC_MODULE), the transform silently
    // falls back to the raw body, and releases quietly go out wrapped again.
    const module = require("./reflow-release-notes.ts");
    expect(typeof module.reflowMarkdown).toBe("function");
  });

  test("the transform genuinely reflows rather than falling back", () => {
    // Distinguishes "reflow ran" from "reflow threw and returned the input". Without
    // this, the previous test could pass while every release published wrapped.
    const wrapped = "alpha beta gamma\ndelta epsilon zeta";
    const out = realTransform()(commitWith(wrapped), CONTEXT);
    expect(out.body?.trimEnd()).toBe("alpha beta gamma delta epsilon zeta");
  });
});
