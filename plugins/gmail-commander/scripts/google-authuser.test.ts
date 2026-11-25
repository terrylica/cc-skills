// Unit tests for google-authuser.ts: Google web-app links in a draft body get `authuser=<email>`, so
// they open in the reader's work account; everything else is left exactly as written.
//
// Run: bun test plugins/gmail-commander/scripts/google-authuser.test.ts
import { describe, expect, test } from "bun:test";
import { addGoogleAuthuser, GOOGLE_AUTHUSER_EMAIL, isGoogleWebAppUrl, withGoogleAuthuser } from "./google-authuser.ts";
import { blocksToHtml, blocksToPlainText, parseArgs, splitBodyIntoBlocks } from "./gmail-draft.ts";

const EMAIL = "jane.doe@example.com";
const DOC = "https://docs.google.com/document/d/abc123/edit";
const WITH = (url: string, sep = "?"): string => `${url}${sep}authuser=${EMAIL}`;

/** The result must parse as a URL and carry exactly one authuser, equal to the email. */
function expectAuthuser(url: string, email = EMAIL): URL {
  const parsed = new URL(url);
  expect(parsed.searchParams.getAll("authuser")).toEqual([email]);
  return parsed;
}

describe("addGoogleAuthuser: Google web-app links open in the named account", () => {
  test("a bare doc URL gets authuser, and the result is a valid URL", () => {
    const r = addGoogleAuthuser(`See ${DOC} today.`, EMAIL);
    expect(r.body).toBe(`See ${WITH(DOC)} today.`);
    expect(r.links).toBe(1);
    expectAuthuser(WITH(DOC));
  });

  test("a named link's target gets authuser; its text is kept", () => {
    const r = addGoogleAuthuser(`Open [the roster](${DOC}).`, EMAIL);
    expect(r.body).toBe(`Open [the roster](${WITH(DOC)}).`);
    expect(r.links).toBe(1);
  });

  test("an existing query is kept and authuser appended", () => {
    const url = "https://drive.google.com/open?id=xyz&usp=sharing";
    const r = addGoogleAuthuser(url, EMAIL);
    expect(r.body).toBe(WITH(url, "&"));
    const parsed = expectAuthuser(r.body);
    expect(parsed.searchParams.get("id")).toBe("xyz");
    expect(parsed.searchParams.get("usp")).toBe("sharing");
  });

  test("a fragment stays last; authuser goes before the #", () => {
    const r = addGoogleAuthuser(`${DOC}#heading=h.abc`, EMAIL);
    expect(r.body).toBe(`${DOC}?authuser=${EMAIL}#heading=h.abc`);
    expect(expectAuthuser(r.body).hash).toBe("#heading=h.abc");
  });

  test("an existing authuser is replaced in place, and a repeat dropped", () => {
    const url = "https://docs.google.com/spreadsheets/d/s1/edit?authuser=1&usp=drivesdk&AuthUser=2#gid=0";
    const r = addGoogleAuthuser(url, EMAIL);
    expect(r.body).toBe(`https://docs.google.com/spreadsheets/d/s1/edit?authuser=${EMAIL}&usp=drivesdk#gid=0`);
    expectAuthuser(r.body);
  });

  test("mail.google.com is not touched", () => {
    const body = "Inbox: https://mail.google.com/mail/u/0/#inbox";
    expect(addGoogleAuthuser(body, EMAIL)).toEqual({ body, links: 0 });
  });

  test("a non-Google URL is not touched, nor a look-alike host", () => {
    const body = "https://example.com/doc?x=1 and https://docs.google.com.example.net/a and [x](https://example.org/)";
    expect(addGoogleAuthuser(body, EMAIL)).toEqual({ body, links: 0 });
  });

  test("a quotation block and a code span or fence are not touched", () => {
    const body = [`> the link was ${DOC}`, `> and [this](${DOC})`, "", `Use \`${DOC}\` as written.`, "", "```", DOC, "```", "", `But ${DOC} here.`].join("\n");
    const r = addGoogleAuthuser(body, EMAIL);
    expect(r.links).toBe(1);
    expect(r.body).toBe(body.replace(`But ${DOC} here.`, `But ${WITH(DOC)} here.`));
  });

  test("every listed app is rewritten; an autolink keeps its brackets", () => {
    for (const host of ["drive", "sheets", "slides", "forms", "sites", "script", "calendar", "meet"]) {
      expect(isGoogleWebAppUrl(`https://${host}.google.com/x`)).toBe(true);
    }
    expect(addGoogleAuthuser(`<${DOC}>`, EMAIL).body).toBe(`<${WITH(DOC)}>`);
  });

  test("a named link whose text is its address gets the new address in both places", () => {
    expect(addGoogleAuthuser(`[${DOC}](${DOC})`, EMAIL).body).toBe(`[${WITH(DOC)}](${WITH(DOC)})`);
  });

  test("`+` in the address is percent-encoded and round-trips; `@` stays readable", () => {
    const email = "jane+team@example.com";
    const out = withGoogleAuthuser(DOC, email);
    expect(out).toBe(`${DOC}?authuser=jane%2Bteam@example.com`);
    expectAuthuser(out, email);
  });
});

describe("the plain and html parts carry the rewritten URL", () => {
  test("plain part renders `text (URL)` with the new URL; html href matches", () => {
    const { body } = addGoogleAuthuser(`Please open [the roster](${DOC}) and ${DOC}.`, EMAIL);
    const blocks = splitBodyIntoBlocks(body);
    expect(blocksToPlainText(blocks)).toBe(`Please open the roster (${WITH(DOC)}) and ${WITH(DOC)}.\n`);
    expect(blocksToHtml(blocks)).toContain(`<a href="${WITH(DOC)}">the roster</a>`);
  });
});

describe("--google-authuser parsing", () => {
  const base = ["bun", "gmail-draft.ts", "--account", "a", "--body", "b.md", "--from", "X <x@example.com>"];

  test("absent → undefined; given → the address; repeated with the same value is fine", () => {
    expect(parseArgs(base).googleAuthuser).toBeUndefined();
    expect(parseArgs([...base, "--google-authuser", EMAIL]).googleAuthuser).toBe(EMAIL);
    expect(parseArgs([...base, "--google-authuser", EMAIL, "--google-authuser", EMAIL]).googleAuthuser).toBe(EMAIL);
  });

  test("a value that is not an email, a missing value, or two different addresses is refused", () => {
    expect(() => parseArgs([...base, "--google-authuser", "jane"])).toThrow(/not an email address/);
    expect(() => parseArgs([...base, "--google-authuser"])).toThrow(/needs an email address/);
    expect(() => parseArgs([...base, "--google-authuser", EMAIL, "--google-authuser", "a@example.org"])).toThrow(/different addresses/);
  });

  test("the email pattern accepts ordinary addresses and rejects malformed ones", () => {
    for (const ok of [EMAIL, "a+b@sub.example.co.uk"]) expect(GOOGLE_AUTHUSER_EMAIL.test(ok)).toBe(true);
    for (const bad of ["a@b", "@example.com", "a b@example.com", "a@@example.com", "<a@example.com>"]) expect(GOOGLE_AUTHUSER_EMAIL.test(bad)).toBe(false);
  });
});
