import { describe, expect, test } from "bun:test";
import { markdownToTelegramHtml } from "./telegram-format.ts";

describe("markdownToTelegramHtml", () => {
  test("bold renders as <b>, not literal asterisks (the 2026-10-02 digest bug)", () => {
    expect(markdownToTelegramHtml("- **Review attached** – Terry sent a response")).toBe(
      "• <b>Review attached</b> – Terry sent a response",
    );
  });

  test("headings become bold lines; Telegram has no heading element", () => {
    expect(markdownToTelegramHtml("# Gmail Summary - Actionable Items")).toBe("<b>Gmail Summary - Actionable Items</b>");
    expect(markdownToTelegramHtml("### Key Action ###")).toBe("<b>Key Action</b>");
  });

  test("prose is HTML-escaped so Telegram cannot reject the message", () => {
    expect(markdownToTelegramHtml("**Invoice <123> & receipt**")).toBe("<b>Invoice &lt;123&gt; &amp; receipt</b>");
  });

  test("every bullet marker becomes •, nested indentation kept", () => {
    expect(markdownToTelegramHtml("- a\n* b\n+ c\n  - d")).toBe("• a\n• b\n• c\n  • d");
  });

  test("underscores inside words, emails and URLs are left alone", () => {
    const text = "user_name@example.com wrote to snake_case_name at https://example.com/x_y_z";
    expect(markdownToTelegramHtml(text)).toBe(text);
  });

  test("italic from single * and _", () => {
    expect(markdownToTelegramHtml("an *urgent* and _optional_ note")).toBe("an <i>urgent</i> and <i>optional</i> note");
  });

  test("a lone asterisk or arithmetic is not italicised", () => {
    expect(markdownToTelegramHtml("2 * 3 = 6")).toBe("2 * 3 = 6");
  });

  test("links keep their URL verbatim (with & escaped) and their escaped text", () => {
    expect(markdownToTelegramHtml("[A & B](https://x.com/a_b?c=1&d=2)")).toBe(
      '<a href="https://x.com/a_b?c=1&amp;d=2">A &amp; B</a>',
    );
  });

  test("code is escaped once and never formatted", () => {
    expect(markdownToTelegramHtml("run `a **b** <c>`")).toBe("run <code>a **b** &lt;c&gt;</code>");
    expect(markdownToTelegramHtml("```ts\nconst x = a<b && **c**;\n```")).toBe(
      '<pre><code class="language-ts">const x = a&lt;b &amp;&amp; **c**;</code></pre>',
    );
  });

  test("tags never span lines, so line-based chunking stays balanced", () => {
    const out = markdownToTelegramHtml("**unclosed\nbold**");
    expect(out).toBe("**unclosed\nbold**");
  });

  test("empty input", () => {
    expect(markdownToTelegramHtml("")).toBe("");
  });
});
