import { describe, expect, it } from "bun:test";
import {
  extractCatHeredoc,
  extractFlagValue,
  extractFlagValueDetailed,
  extractFlagValues,
  hasUnparseableCatHeredoc,
  readShellArg,
  splitShellWords,
} from "./shell-arg-extractor.ts";

describe("readShellArg", () => {
  it("reads a double-quoted token", () => {
    expect(readShellArg('"hello world" rest')).toEqual({ value: "hello world", endIndex: 13, quote: "double" });
  });
  it("reads a single-quoted token literally", () => {
    expect(readShellArg("'a\\nb'")).toEqual({ value: "a\\nb", endIndex: 6, quote: "single" });
  });
  it("decodes $'…' ANSI-C escapes", () => {
    expect(readShellArg("$'line one\\nline two'")).toMatchObject({ value: "line one\nline two", quote: "ansi-c" });
  });
  it("unescapes only \" \\ $ ` inside double quotes; leaves \\n literal", () => {
    expect(readShellArg('"a\\"b"')?.value).toBe('a"b');
    expect(readShellArg('"a\\nb"')?.value).toBe("a\\nb"); // backslash-n stays literal in shell double quotes
    expect(readShellArg('"a\\\\b"')?.value).toBe("a\\b");
  });
  it("preserves $(…) verbatim (no expansion)", () => {
    expect(readShellArg('"$(cat NOTES.md)"')?.value).toBe("$(cat NOTES.md)");
  });
  it("reads a bare token, backslash kept literal", () => {
    expect(readShellArg("./email-body.txt --next")).toMatchObject({ value: "./email-body.txt", quote: "none" });
  });
  it("skips leading blanks and returns null when only blanks remain", () => {
    expect(readShellArg("   x")?.value).toBe("x");
    expect(readShellArg("    ")).toBeNull();
  });
});

describe("extractFlagValue / extractFlagValueDetailed", () => {
  it("extracts a double-quoted value", () => {
    expect(extractFlagValue('gmail draft --body "hi there"', ["--body"])).toEqual({
      present: true,
      value: "hi there",
    });
  });
  it("honors = joining", () => {
    expect(extractFlagValue("cmd --file=/tmp/x", ["--file", "-F"])).toEqual({ present: true, value: "/tmp/x" });
  });
  it("reports a bare flag as present with no value", () => {
    expect(extractFlagValueDetailed("gh release create v1 --notes-from-tag", ["--notes-from-tag"])).toEqual({
      present: true,
    });
  });
  it("does not match a longer flag by prefix", () => {
    // --notes must NOT match --notes-file
    expect(extractFlagValueDetailed("gh release edit --notes-file NOTES.md", ["--notes"]).present).toBe(false);
  });
  it("returns not-present when no alias appears", () => {
    expect(extractFlagValue("gmail list -n 10", ["--body"])).toEqual({ present: false });
  });
  it("reports the quote kind (for sred's method selection)", () => {
    expect(extractFlagValueDetailed(`git commit -m "msg"`, ["-m"]).quote).toBe("double");
    expect(extractFlagValueDetailed(`git commit -m 'msg'`, ["-m"]).quote).toBe("single");
  });
});

describe("extractFlagValues (all occurrences)", () => {
  it("collects every -m/--message value in order", () => {
    expect(extractFlagValues(`git tag -a v1 -m "one" -m "two"`, ["-m", "--message"])).toEqual(["one", "two"]);
  });
  it("skips a bare flag with no value", () => {
    expect(extractFlagValues("cmd -m", ["-m"])).toEqual([]);
  });
});

describe("extractCatHeredoc", () => {
  it("parses a quoted-delimiter cat heredoc and strips edge newlines", () => {
    const cmd = `git commit -m "$(cat <<'EOF'\nfeat: x\n\nSRED-Type: y\nEOF\n)"`;
    expect(extractCatHeredoc(cmd)).toEqual({ delimiter: "EOF", body: "feat: x\n\nSRED-Type: y" });
  });
  it("parses a bare-delimiter cat heredoc", () => {
    const cmd = `git commit -m "$(cat <<EOF\nhello\nEOF\n)"`;
    expect(extractCatHeredoc(cmd)).toEqual({ delimiter: "EOF", body: "hello" });
  });
  it("returns null for a non-heredoc command", () => {
    expect(extractCatHeredoc(`git commit -m "plain"`)).toBeNull();
  });
  it("flags an unparseable heredoc via hasUnparseableCatHeredoc", () => {
    // Opening heredoc syntax present but no closing delimiter → unparseable.
    const cmd = `git commit -m "$(cat <<EOF\nno close here`;
    expect(extractCatHeredoc(cmd)).toBeNull();
    expect(hasUnparseableCatHeredoc(cmd)).toBe(true);
  });
});

const values = (command: string) => splitShellWords(command).map((word) => word.value);

describe("splitShellWords", () => {
  it("joins adjacent segments into ONE word, as the shell does", () => {
    // THE CASE THIS FUNCTION WAS ADDED FOR. `'\''` is the only way to put an apostrophe inside a
    // single-quoted word. readShellArg alone returns five tokens here, one of them a bare `merge;`,
    // so a caller looking for command separators ends the command inside the argument. That was a
    // measured fail-open in the PR review-invitation guard.
    expect(values(String.raw`--body 'don'\''t merge; fix' --request-changes`)).toEqual([
      "--body",
      "don't merge; fix",
      "--request-changes",
    ]);
  });

  it("joins the other adjacent-segment spellings too", () => {
    // Four segments: "it" -> it, '"' -> a double quote, "'s fine" -> 's fine. Joined: it"'s fine.
    expect(values(`--body "it"'"'"'s fine"`)).toEqual(["--body", `it"'s fine`]);
    expect(values(`pre'mid'post`)).toEqual(["premidpost"]);
    expect(values(`a$'x\\ty'b`)).toEqual(["ax\tyb"]);
  });

  it("marks a word bare only when it STARTS unquoted, which is the flag test", () => {
    const [flag, literal, mixed] = splitShellWords(`--approve '--approve' --body='x'`);
    expect(flag!.firstSegmentBare).toBe(true);
    expect(literal!.firstSegmentBare).toBe(false);
    expect(mixed!.firstSegmentBare).toBe(true);
    expect(mixed!.value).toBe("--body=x");
  });

  it("emits unquoted control operators as their own words", () => {
    expect(values(`a && b; c | d & e || f`)).toEqual(["a", "&&", "b", ";", "c", "|", "d", "&", "e", "||", "f"]);
    const ops = splitShellWords(`a && b`).filter((word) => word.isOperator).map((word) => word.value);
    expect(ops).toEqual(["&&"]);
  });

  it("does NOT treat an operator character inside quotes as an operator", () => {
    const words = splitShellWords(`--body "a && b; c"`);
    expect(words.map((word) => word.value)).toEqual(["--body", "a && b; c"]);
    expect(words.some((word) => word.isOperator)).toBe(false);
  });

  it("reports a newline in the preceding whitespace", () => {
    const words = splitShellWords("a\nb c");
    expect(words.map((word) => word.precededByNewline)).toEqual([false, true, false]);
  });

  it("honours a backslash escape outside quotes", () => {
    expect(values(String.raw`a\ b c`)).toEqual(["a b", "c"]);
    expect(values(String.raw`\'quoted\'`)).toEqual(["'quoted'"]);
  });

  it("terminates on unbalanced quotes rather than spinning", () => {
    expect(values(`--body "never closed`)).toEqual(["--body", "never closed"]);
    expect(values(`'`)).toEqual([""]);
  });

  it("leaves readShellArg's own behaviour untouched", () => {
    // The three existing consumers depend on readShellArg, not on this function. This pins that
    // adding word splitting did not change the single-argument reader they rely on.
    expect(readShellArg(String.raw`'don'\''t' rest`)?.value).toBe("don");
  });
});
