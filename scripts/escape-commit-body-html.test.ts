/**
 * scripts/escape-commit-body-html.test.ts
 *
 * GitHub renders a release body as GFM, which INTERPRETS raw HTML. Every angle bracket in
 * the last 400 commit bodies of this repo is prose or a CLI placeholder, and each one was
 * being silently deleted or mangled on the published page.
 *
 * The GFM claims here were established against GitHub's own /markdown API. The
 * network-backed test at the bottom re-verifies them rather than trusting this comment —
 * if GitHub ever changes, that test tells us instead of a reader discovering it in a
 * published release.
 */

import { describe, expect, test } from "bun:test";
import { escapeCommitBodyHtml } from "./escape-commit-body-html.ts";

describe("escapes angle brackets that GFM would eat", () => {
  const cases: [name: string, input: string, expected: string][] = [
    ["generic type parameter", "generic Vec<T> type", "generic Vec&lt;T> type"],
    ["two-arg generic", "a Map<Command,Handler> here", "a Map&lt;Command,Handler> here"],
    ["a tag named in prose", "a literal <br> here", "a literal &lt;br> here"],
    ["a block tag that would swallow", "a <details> block", "a &lt;details> block"],
    ["a CLI placeholder", "pass <uuid> to the tool", "pass &lt;uuid> to the tool"],
    ["an alternation placeholder", "run <verify|probe>", "run &lt;verify|probe>"],
    ["a comparison", "compare a<b and c>d", "compare a&lt;b and c>d"],
  ];

  for (const [name, input, expected] of cases) {
    test(name, () => {
      expect(escapeCommitBodyHtml(input)).toBe(expected);
    });
  }

  test("only `<` is escaped — `>` must survive for the `->` in aligned tables", () => {
    const row = "  corolla-cross-trade-in       -> vehicle-appraisal";
    expect(escapeCommitBodyHtml(row)).toBe(row);
  });
});

describe("leaves alone what already renders literally", () => {
  test("an inline code span is untouched", () => {
    const line = "the pattern is `/^-(.*?)-$/` and `Vec<T>` stays";
    expect(escapeCommitBodyHtml(line)).toBe(line);
  });

  test("a double-backtick span containing a backtick is untouched", () => {
    const line = "use ``a `b` c<T>`` verbatim";
    expect(escapeCommitBodyHtml(line)).toBe(line);
  });

  test("prose around a code span is still escaped", () => {
    expect(escapeCommitBodyHtml("before <T> `inside <T>` after <T>")).toBe(
      "before &lt;T> `inside <T>` after &lt;T>",
    );
  });

  test("a fenced block is untouched, and escaping resumes after it", () => {
    const input = ["before <T>", "```sh", "cmd --flag <value>", "```", "after <T>"].join("\n");
    const output = escapeCommitBodyHtml(input).split("\n");
    expect(output[0]).toBe("before &lt;T>");
    expect(output[2]).toBe("cmd --flag <value>");
    expect(output[4]).toBe("after &lt;T>");
  });

  test("an unterminated backtick does not swallow the rest of the line", () => {
    // A stray backtick must not turn the remainder into a pseudo code span and smuggle
    // an unescaped tag past the escaper.
    expect(escapeCommitBodyHtml("a ` stray and <br> after")).toBe("a ` stray and &lt;br> after");
  });
});

describe("markdown autolinks are real syntax, not HTML", () => {
  for (const link of ["<https://example.com/a_b>", "<http://x.test>", "<user@example.com>"]) {
    test(`preserves ${link}`, () => {
      expect(escapeCommitBodyHtml(`see ${link} for more`)).toBe(`see ${link} for more`);
    });
  }

  test("something merely LOOKING like an autolink is still escaped", () => {
    expect(escapeCommitBodyHtml("<not a link>")).toBe("&lt;not a link>");
  });
});

describe("degenerate input", () => {
  for (const [name, value] of [
    ["empty", ""],
    ["null", null],
    ["undefined", undefined],
  ] as const) {
    test(`${name} body is returned as-is`, () => {
      expect(escapeCommitBodyHtml(value as unknown as string)).toBe(value as unknown as string);
    });
  }

  test("text with no angle brackets is byte-identical", () => {
    const plain = "A perfectly ordinary sentence, with punctuation: and -- dashes.";
    expect(escapeCommitBodyHtml(plain)).toBe(plain);
  });
});

/**
 * The premise, re-verified against the live renderer.
 *
 * Every claim above rests on how GitHub actually treats these constructs. Asserting that
 * from memory is how a fix like this rots. Skipped when the API is unreachable rather than
 * passing vacuously offline.
 */
// PROCESS-STORM-OK: bounded and strictly sequential — one reachability probe plus four
// assertions, five `gh` invocations total for this file, each awaited before the next is
// spawned. No fan-out, no loop over unbounded input, no concurrency.
async function renderOnGitHub(text: string): Promise<string | null> {
  const proc = Bun.spawn(["gh", "api", "-X", "POST", "/markdown", "--input", "-"], {
    stdin: new TextEncoder().encode(JSON.stringify({ mode: "gfm", text })),
    stdout: "pipe",
    stderr: "pipe",
  });
  const out = await new Response(proc.stdout).text();
  await proc.exited;
  return proc.exitCode === 0 ? out : null;
}

const GITHUB_REACHABLE = (await renderOnGitHub("ping")) !== null;

describe.skipIf(!GITHUB_REACHABLE)("verified against GitHub's own renderer", () => {
  test("unescaped `Vec<T>` really does lose its type parameter", async () => {
    // The motivating defect. If this ever stops being true, the escaping is no longer
    // needed and this suite should be revisited rather than left as cargo cult.
    const rendered = await renderOnGitHub("generic Vec<T> type");
    expect(rendered).toContain("generic Vec type");
  });

  test("the escaped form renders the type parameter visibly", async () => {
    const rendered = await renderOnGitHub(escapeCommitBodyHtml("generic Vec<T> type"));
    expect(rendered).toContain("Vec&lt;T&gt; type");
  });

  test("an escaped `<br>` shows as text instead of breaking the line", async () => {
    const rendered = await renderOnGitHub(escapeCommitBodyHtml("a literal <br> here"));
    expect(rendered).toContain("&lt;br&gt;");
    expect(rendered).not.toContain("<br>");
  });

  test("a preserved autolink still becomes an anchor", async () => {
    const rendered = await renderOnGitHub(escapeCommitBodyHtml("see <https://example.com> now"));
    expect(rendered).toContain('href="https://example.com"');
  });
});
