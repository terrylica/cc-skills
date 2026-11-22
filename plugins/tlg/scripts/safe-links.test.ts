import { describe, expect, test } from "bun:test";
import { badLinks, exactLinks, hostOf, linkSpans } from "./safe-links.ts";

const plain = (text: string): string => exactLinks(text, { html: false });
const html = (text: string): string => exactLinks(text, { html: true });

describe("exactLinks — the measured cases (2026-11-22)", () => {
  test("bare host/path followed by a full-width comma and Chinese ends at the comma", () => {
    expect(plain("打开 github.com/login/device，用你自己的账号")).toBe(
      '打开 <a href="https://github.com/login/device">github.com/login/device</a>，用你自己的账号',
    );
  });

  test("https:// form ends at the comma too and keeps its scheme", () => {
    expect(plain("打开 https://github.com/login/device，用你自己的账号")).toBe(
      '打开 <a href="https://github.com/login/device">https://github.com/login/device</a>，用你自己的账号',
    );
  });

  test("a space before the comma gives the same exact link", () => {
    expect(plain("打开 github.com/login/device ，用你自己的账号")).toBe(
      '打开 <a href="https://github.com/login/device">github.com/login/device</a> ，用你自己的账号',
    );
  });

  test("an explicit <a> is left exactly as written", () => {
    const text = '打开 <a href="https://github.com/login/device">github.com/login/device</a>，用你自己的账号';
    expect(html(text)).toBe(text);
  });

  test("text inside <code> and <pre> is never linked", () => {
    const text = "<code>github.com/login/device，用</code> <pre>https://example.com/x，好</pre>";
    expect(html(text)).toBe(text);
  });
});

describe("exactLinks — Chinese and English", () => {
  test("link at the end of a line and of the text", () => {
    expect(plain("登录：t.me/example_bot\n下一行 docs.example.org/a/b")).toBe(
      '登录：<a href="https://t.me/example_bot">t.me/example_bot</a>\n下一行 <a href="https://docs.example.org/a/b">docs.example.org/a/b</a>',
    );
  });

  test("ideograph glued on both sides", () => {
    expect(plain("进入github.com/x了")).toBe('进入<a href="https://github.com/x">github.com/x</a>了');
  });

  test("ASCII sentence punctuation after a link is not part of it", () => {
    expect(plain("See github.com/a/b. Then t.me/x, and example.com!")).toBe(
      'See <a href="https://github.com/a/b">github.com/a/b</a>. Then <a href="https://t.me/x">t.me/x</a>, and <a href="https://example.com">example.com</a>!',
    );
  });

  test("inside ASCII parentheses; balanced parentheses in a URL stay", () => {
    expect(plain("(see https://en.wikipedia.org/wiki/Foo_(bar)) and (github.com/x)")).toBe(
      '(see <a href="https://en.wikipedia.org/wiki/Foo_(bar)">https://en.wikipedia.org/wiki/Foo_(bar)</a>) and (<a href="https://github.com/x">github.com/x</a>)',
    );
  });

  test("inside full-width parentheses and corner brackets", () => {
    expect(plain("（github.com/x）「t.me/y」【example.com/z】")).toBe(
      '（<a href="https://github.com/x">github.com/x</a>）「<a href="https://t.me/y">t.me/y</a>」【<a href="https://example.com/z">example.com/z</a>】',
    );
  });

  test("full-width punctuation of every kind ends a link", () => {
    for (const p of ["。", "，", "、", "：", "；", "！", "？", "“", "”", "‘", "’", "《", "》", "　", "～"]) {
      expect(linkSpans(`github.com/x${p}后`)[0]?.visible).toBe("github.com/x");
    }
  });

  test("query strings and fragments are kept; plain-text & is escaped once", () => {
    expect(plain("填 https://example.com/a?b=1&c=2#d，然后")).toBe(
      '填 <a href="https://example.com/a?b=1&amp;c=2#d">https://example.com/a?b=1&amp;c=2#d</a>，然后',
    );
  });

  test("HTML input: &amp; stays inside the URL, &gt; ends it", () => {
    expect(html("看 docs.example.org/a?b=1&amp;c=2，好 &lt;https://x.com/y&gt;")).toBe(
      '看 <a href="https://docs.example.org/a?b=1&amp;c=2">docs.example.org/a?b=1&amp;c=2</a>，好 &lt;<a href="https://x.com/y">https://x.com/y</a>&gt;',
    );
  });

  test("several links in one message, mixed with formatting", () => {
    expect(html("<b>步骤</b>：github.com/login/device，然后 t.me/x。<i>example.com/y</i>")).toBe(
      '<b>步骤</b>：<a href="https://github.com/login/device">github.com/login/device</a>，然后 <a href="https://t.me/x">t.me/x</a>。<i><a href="https://example.com/y">example.com/y</a></i>',
    );
  });

  test("emoji right after a link ends it", () => {
    expect(plain("github.com/x🎉 好")).toBe('<a href="https://github.com/x">github.com/x</a>🎉 好');
  });

  test("http scheme and a single-label host with a port", () => {
    expect(plain("健康检查 http://localhost:8787/health。")).toBe(
      '健康检查 <a href="http://localhost:8787/health">http://localhost:8787/health</a>。',
    );
  });

  test("plain text with no link is only escaped", () => {
    expect(plain("a < b & c > d，好")).toBe("a &lt; b &amp; c &gt; d，好");
  });
});

describe("exactLinks — what is not a link", () => {
  test("file names, paths, versions and abbreviations", () => {
    const text = "tg-cli.ts README.md src/commands/cli.ts v1.2.3 e.g. i.e. Node.js 3.14";
    expect(linkSpans(text)).toEqual([]);
  });

  test("e-mail addresses", () => {
    expect(linkSpans("first.last@example.com 或 user@github.com")).toEqual([]);
  });

  test("a host glued to a preceding word or path", () => {
    expect(linkSpans("foo/github.com/x a_github.com/y x@t.me/z")).toEqual([]);
  });
});

describe("linkSpans offsets are UTF-16, as Telegram counts", () => {
  test("after an astral emoji", () => {
    const text = "🎉 github.com/x，好";
    const [span] = linkSpans(text);
    expect(span?.offset).toBe(3);
    expect(text.slice(span?.offset, (span?.offset ?? 0) + (span?.length ?? 0))).toBe("github.com/x");
  });
});

describe("badLinks — reading back what the server stored", () => {
  const text = "打开 github.com/login/device，用你自己的账号";

  test("a Url entity that swallowed the comma and Chinese is reported", () => {
    const bad = badLinks({
      message: text,
      entities: [{ className: "MessageEntityUrl", offset: 3, length: text.length - 3 }],
    });
    expect(bad).toHaveLength(1);
    expect(bad[0]?.text).toBe("github.com/login/device，用你自己的账号");
  });

  test("an exact Url entity is fine", () => {
    expect(badLinks({ message: text, entities: [{ className: "MessageEntityUrl", offset: 3, length: 23 }] })).toEqual([]);
  });

  test("an exact TextUrl is fine; a swallowing TextUrl is reported", () => {
    const url = "https://github.com/login/device";
    expect(badLinks({ message: text, entities: [{ className: "MessageEntityTextUrl", offset: 3, length: 23, url }] })).toEqual([]);
    expect(
      badLinks({ message: text, entities: [{ className: "MessageEntityTextUrl", offset: 3, length: 25, url }] }),
    ).toHaveLength(1);
  });

  test("a TextUrl showing one host and opening another is reported", () => {
    const bad = badLinks({
      message: "go to github.com/x now",
      entities: [{ className: "MessageEntityTextUrl", offset: 6, length: 12, url: "https://evil.example/x" }],
    });
    expect(bad[0]?.reason).toContain("github.com");
  });

  test("a label with no URL in it, mentions and other entities are fine", () => {
    expect(
      badLinks({
        message: "点这里 Alice 粗体",
        entities: [
          { className: "MessageEntityTextUrl", offset: 0, length: 3, url: "https://example.com/a" },
          { className: "MessageEntityTextUrl", offset: 4, length: 5, url: "tg://user?id=1" },
          { className: "MessageEntityBold", offset: 10, length: 2 },
        ],
      }),
    ).toEqual([]);
  });

  test("a message without entities has no bad links", () => {
    expect(badLinks({ message: text })).toEqual([]);
    expect(badLinks({ message: text, entities: null })).toEqual([]);
  });
});

describe("hostOf", () => {
  test("strips scheme, port, path and case", () => {
    expect(hostOf("HTTPS://GitHub.com:443/login?x=1")).toBe("github.com");
    expect(hostOf("t.me/x")).toBe("t.me");
  });
});
