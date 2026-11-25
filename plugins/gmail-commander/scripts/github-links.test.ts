// Unit tests for github-links.ts: issue references become short links, every reader of a private
// repository is checked with a FAKE gh runner (no network), and the access note is added only when needed.
//
// Run: bun test plugins/gmail-commander/scripts/github-links.test.ts
import { describe, expect, test } from "bun:test";
import {
  checkGithubAccess,
  collectGithubRepos,
  formatGithubAccessRefusal,
  GITHUB_ACCESS_NOTE,
  githubAccessProblems,
  hasGithubAccessRemark,
  insertBeforeSignature,
  linkGithubReferences,
  prepareGithubLinks,
  type GhResult,
  type GhRunner,
  type GithubAccessReport,
  type GithubReaderStatus,
} from "./github-links.ts";
import { blocksToHtml, blocksToPlainText, splitBodyIntoBlocks } from "./gmail-draft.ts";

const ISSUE = "https://github.com/acme/handbook/issues/12";

describe("linkGithubReferences: references become short text links", () => {
  test("a bare issue URL in the default repo reads #N", () => {
    expect(linkGithubReferences(`See ${ISSUE} today.`, "acme/handbook")).toBe(`See [#12](${ISSUE}) today.`);
  });

  test("the default repo is compared case-insensitively", () => {
    expect(linkGithubReferences(`See ${ISSUE}`, "ACME/Handbook")).toBe(`See [#12](${ISSUE})`);
  });

  test("a bare issue URL in another repo reads OWNER/REPO#N, and so does any URL without --github-repo", () => {
    const url = "https://github.com/acme/tools/pull/7";
    expect(linkGithubReferences(`See ${url}.`, "acme/handbook")).toBe(`See [acme/tools#7](${url}).`);
    expect(linkGithubReferences(`See ${ISSUE}`)).toBe(`See [acme/handbook#12](${ISSUE})`);
  });

  test("a URL with a comment fragment or /files keeps its full address behind the short label", () => {
    const url = `${ISSUE}#issuecomment-99`;
    expect(linkGithubReferences(`(see ${url})`, "acme/handbook")).toBe(`(see [#12](${url}))`);
    const files = "https://github.com/acme/handbook/pull/3/files";
    expect(linkGithubReferences(files, "acme/handbook")).toBe(`[#3](${files})`);
  });

  test("an autolink <URL> becomes a short link too", () => {
    expect(linkGithubReferences(`<${ISSUE}>`, "acme/handbook")).toBe(`[#12](${ISSUE})`);
  });

  test("OWNER/REPO#N in prose becomes a link, labelled #N when it is the default repo", () => {
    expect(linkGithubReferences("Tracked in acme/tools#5, ok?")).toBe("Tracked in [acme/tools#5](https://github.com/acme/tools/issues/5), ok?");
    expect(linkGithubReferences("Tracked in acme/handbook#5.", "acme/handbook")).toBe(`Tracked in [#5](https://github.com/acme/handbook/issues/5).`);
  });

  test("a bare #N becomes a link ONLY with --github-repo", () => {
    expect(linkGithubReferences("Fixed in #42.")).toBe("Fixed in #42.");
    expect(linkGithubReferences("Fixed in #42.", "acme/handbook")).toBe("Fixed in [#42](https://github.com/acme/handbook/issues/42).");
    expect(linkGithubReferences("(#42, #43)", "acme/handbook")).toBe(
      "([#42](https://github.com/acme/handbook/issues/42), [#43](https://github.com/acme/handbook/issues/43))",
    );
  });

  test("emphasis around a reference moves inside the link, so it still renders bold or italic", () => {
    const linked = linkGithubReferences("Done: **#12** and *acme/tools#5*.", "acme/handbook");
    expect(linked).toBe("Done: [**#12**](https://github.com/acme/handbook/issues/12) and [*acme/tools#5*](https://github.com/acme/tools/issues/5).");
    const blocks = splitBodyIntoBlocks(linked);
    expect(blocksToHtml(blocks)).toContain('<a href="https://github.com/acme/handbook/issues/12"><b>#12</b></a>');
    expect(blocksToPlainText(blocks)).toBe("Done: #12 (https://github.com/acme/handbook/issues/12) and acme/tools#5 (https://github.com/acme/tools/issues/5).\n");
  });

  test("other URLs are left alone", () => {
    const s = "https://github.com/acme/handbook and https://example.com/issues/3";
    expect(linkGithubReferences(s, "acme/handbook")).toBe(s);
  });
});

describe("linkGithubReferences: what it never touches", () => {
  const D = "acme/handbook";
  test.each([
    ["a code span", "Run `gh issue view #12` now"],
    ["a code span with a URL", `Look at \`${ISSUE}\``],
    ["a > quotation line", `> they wrote #12 and ${ISSUE}`],
    ["an existing named link's text", "[see #12](https://example.com/x)"],
    ["an existing named link's target", `[the issue](${ISSUE})`],
    ["part of a longer token before", "abc#12"],
    ["part of a longer token after", "#12a"],
    ["a hex colour", "colour #fff and #a1b2c3"],
    ["a leading zero", "#012"],
    ["a decimal", "#1.5"],
    ["an HTML entity", "&#12;"],
    ["a path fragment", "example.com/page#12 and docs/#3"],
    ["a heading marker", "# 12 things"],
  ])("%s", (_name, line) => {
    expect(linkGithubReferences(line, D)).toBe(line);
  });

  test("lines inside a ``` fence are verbatim", () => {
    const body = "```\nsee #12\n```\nafter #12";
    expect(linkGithubReferences(body, D)).toBe("```\nsee #12\n```\nafter [#12](https://github.com/acme/handbook/issues/12)");
  });

  test("a quotation stays verbatim while the answer under it is linked", () => {
    const body = "> please look at #12\n\nDone in #12.";
    expect(linkGithubReferences(body, D)).toBe("> please look at #12\n\nDone in [#12](https://github.com/acme/handbook/issues/12).");
  });
});

describe("both parts agree: html shows #N as a link, plain reads #N (URL)", () => {
  test("plain part and html part", () => {
    const blocks = splitBodyIntoBlocks(linkGithubReferences(`Fixed in ${ISSUE} and acme/tools#5.`, "acme/handbook"));
    expect(blocksToPlainText(blocks)).toBe(`Fixed in #12 (${ISSUE}) and acme/tools#5 (https://github.com/acme/tools/issues/5).\n`);
    const html = blocksToHtml(blocks);
    expect(html).toContain(`<a href="${ISSUE}">#12</a>`);
    expect(html).toContain(`<a href="https://github.com/acme/tools/issues/5">acme/tools#5</a>`);
    // The address inside the named link is not linked a second time.
    expect(html.match(/<a /g)?.length).toBe(2);
  });
});

describe("collectGithubRepos", () => {
  test("every repository linked, deduplicated case-insensitively, quotations and html included, non-repo paths skipped", () => {
    const body = `[#1](${ISSUE}) > https://github.com/ACME/Handbook/issues/2\nhttps://github.com/acme/tools.git and https://github.com/orgs/acme/people and https://github.com/jdoe`;
    expect(collectGithubRepos(body, '<a href="https://github.com/acme/site/blob/main/x.md">x</a>')).toEqual(["acme/handbook", "acme/tools", "acme/site"]);
  });

  test("trailing prose punctuation is not part of the repo name", () => {
    expect(collectGithubRepos("See https://github.com/acme/handbook.")).toEqual(["acme/handbook"]);
  });
});

/** A fake gh: maps the args (joined by spaces, up to the first flag after the path) to a result; anything else 404s. */
function fakeGh(routes: Record<string, GhResult>): GhRunner & { calls: string[] } {
  const calls: string[] = [];
  const run = async (args: string[]): Promise<GhResult> => {
    const key = args.slice(0, 2).join(" ");
    calls.push(key);
    return routes[key] ?? { ok: false, code: 1, stderr: "gh: Not Found (HTTP 404)" };
  };
  return Object.assign(run, { calls });
}
const ok = (v: unknown): GhResult => ({ ok: true, stdout: typeof v === "string" ? v : JSON.stringify(v) });

describe("checkGithubAccess with a fake gh", () => {
  test("public: everyone can-comment, and no permission call is made", async () => {
    const gh = fakeGh({ "api repos/acme/site": ok({ visibility: "public", private: false }) });
    const r = await checkGithubAccess(["acme/site"], ["jdoe"], gh);
    expect(r.repos["acme/site"]).toEqual({ visibility: "public", readers: { jdoe: "can-comment" }, notes: [] });
    expect(r.privateRepos).toBe(0);
    expect(gh.calls).toEqual(["api repos/acme/site"]);
  });

  test("private: read, triage (role_name) and admin can comment", async () => {
    const gh = fakeGh({
      "api repos/acme/handbook": ok({ visibility: "private", private: true }),
      "api repos/acme/handbook/collaborators/jdoe/permission": ok({ permission: "read", role_name: "read" }),
      "api repos/acme/handbook/collaborators/asmith/permission": ok({ permission: "read", role_name: "triage" }),
      "api repos/acme/handbook/collaborators/boss/permission": ok({ permission: "admin", role_name: "admin" }),
    });
    const r = await checkGithubAccess(["acme/handbook"], ["jdoe", "asmith", "boss"], gh);
    expect(r.repos["acme/handbook"]?.readers).toEqual({ jdoe: "can-comment", asmith: "can-comment", boss: "can-comment" });
    expect(r.privateRepos).toBe(1);
  });

  test("private: no permission but a pending invitation is invited-pending; without one, no-access", async () => {
    const gh = fakeGh({
      "api repos/acme/handbook": ok({ visibility: "private" }),
      "api repos/acme/handbook/collaborators/jdoe/permission": ok({ permission: "none", role_name: "" }),
      "api repos/acme/handbook/collaborators/asmith/permission": ok({ permission: "none" }),
      "api repos/acme/handbook/invitations": ok("JDoe\n"),
    });
    const r = await checkGithubAccess(["acme/handbook"], ["jdoe", "asmith"], gh);
    expect(r.repos["acme/handbook"]?.readers).toEqual({ jdoe: "invited-pending", asmith: "no-access" });
    // Invitations are read once per repository, not once per reader.
    expect(gh.calls.filter((c) => c.endsWith("/invitations")).length).toBe(1);
  });

  test("an expired invitation is invitation-expired, refuses, and the fix deletes it before re-inviting", async () => {
    const gh = fakeGh({
      "api repos/acme/handbook": ok({ visibility: "private" }),
      "api repos/acme/handbook/collaborators/jdoe/permission": ok({ permission: "none", role_name: "" }),
      "api repos/acme/handbook/collaborators/asmith/permission": ok({ permission: "none" }),
      "api repos/acme/handbook/invitations": ok("jdoe\ttrue\t111\nasmith\ttrue\t222\nasmith\tfalse\t333\n"),
    });
    const r = await checkGithubAccess(["acme/handbook"], ["jdoe", "asmith"], gh);
    // A live invitation wins over an expired one for the same person.
    expect(r.repos["acme/handbook"]?.readers).toEqual({ jdoe: "invitation-expired", asmith: "invited-pending" });
    const problems = githubAccessProblems(r, ["jdoe", "asmith"]);
    expect(problems).toEqual(["acme/handbook (private): jdoe's invitation has EXPIRED (GitHub invitations last 7 days), so the links show them a 404 page"]);
    expect(formatGithubAccessRefusal(problems, r)).toContain("gh api -X DELETE repos/acme/handbook/invitations/111 && gh api -X PUT repos/acme/handbook/collaborators/jdoe -f permission=pull");
  });

  test("the invitations query is real jq: string interpolation and tabs reach jq escaped, so it prints login, expired and id", async () => {
    const seen: string[][] = [];
    const gh: GhRunner = async (args) => {
      seen.push(args);
      if (args[1] === "repos/acme/handbook") return ok({ visibility: "private" });
      if (args[1]?.endsWith("/permission")) return ok({ permission: "none" });
      return ok("");
    };
    await checkGithubAccess(["acme/handbook"], ["jdoe"], gh);
    const jq = seen.find((a) => a[1] === "repos/acme/handbook/invitations")?.at(-1) ?? "";
    // A JS string "\(" would reach jq as "(" and print the filter text literally (a bug caught live).
    expect(jq).toContain(String.raw`"\(.invitee.login)\t\(.expired == true)\t\(.id)"`);
  });

  test("internal counts as restricted", async () => {
    const gh = fakeGh({
      "api repos/acme/handbook": ok({ visibility: "internal" }),
      "api repos/acme/handbook/collaborators/jdoe/permission": ok({ permission: "write" }),
    });
    const r = await checkGithubAccess(["acme/handbook"], ["jdoe"], gh);
    expect(r.privateRepos).toBe(1);
    expect(r.repos["acme/handbook"]?.readers.jdoe).toBe("can-comment");
  });

  test("gh unavailable: every repo and reader unknown with the reason, and gh is not called again", async () => {
    const gh = fakeGh({ "api repos/acme/handbook": { ok: false, code: null, stderr: "", unavailable: "gh CLI not found on PATH" } });
    const r = await checkGithubAccess(["acme/handbook", "acme/tools"], ["jdoe"], gh);
    for (const repo of ["acme/handbook", "acme/tools"]) {
      expect(r.repos[repo]?.visibility).toBe("unknown");
      expect(r.repos[repo]?.readers).toEqual({ jdoe: "unknown" });
      expect(r.repos[repo]?.notes.join(" ")).toContain("gh CLI not found on PATH");
    }
    expect(gh.calls).toEqual(["api repos/acme/handbook"]);
  });

  test("a permission lookup that fails is unknown with the reason", async () => {
    const gh = fakeGh({
      "api repos/acme/handbook": ok({ visibility: "private" }),
      "api repos/acme/handbook/collaborators/jdoe/permission": { ok: false, code: 1, stderr: "gh: Must have push access to view collaborator permission. (HTTP 403)" },
    });
    const r = await checkGithubAccess(["acme/handbook"], ["jdoe"], gh);
    expect(r.repos["acme/handbook"]?.readers.jdoe).toBe("unknown");
    expect(r.repos["acme/handbook"]?.notes[0]).toContain("HTTP 403");
  });
});

const report = (visibility: "public" | "private" | "unknown", readers: Record<string, GithubReaderStatus>): GithubAccessReport => ({
  repos: { "acme/handbook": { visibility, readers, notes: [] } },
  privateRepos: visibility === "private" ? 1 : 0,
});

describe("refusal rules", () => {

  test("private with no --github-reader refuses", () => {
    expect(githubAccessProblems(report("private", {}), [])).toEqual([
      "acme/handbook (private): no --github-reader given; name the GitHub login of everyone who will open the links",
    ]);
  });

  test("private with a no-access or unverifiable reader refuses; can-comment and invited-pending do not", () => {
    const r = report("private", { jdoe: "no-access", asmith: "can-comment", bwong: "invited-pending", cdoe: "unknown" });
    const problems = githubAccessProblems(r, ["jdoe", "asmith", "bwong", "cdoe"]);
    expect(problems.length).toBe(2);
    expect(problems[0]).toContain("jdoe has no access");
    expect(problems[1]).toContain("cdoe's access could not be verified");
  });

  test("public, and unknown visibility (gh missing), never refuse", () => {
    expect(githubAccessProblems(report("public", {}), [])).toEqual([]);
    expect(githubAccessProblems(report("unknown", { jdoe: "unknown" }), ["jdoe"])).toEqual([]);
  });

  test("the refusal names the repo, the reader, the invite command and the escape flag", () => {
    const r = report("private", { jdoe: "no-access" });
    const msg = formatGithubAccessRefusal(githubAccessProblems(r, ["jdoe"]), r);
    expect(msg).toStartWith("REFUSED:");
    expect(msg).toContain("acme/handbook (private): jdoe has no access");
    expect(msg).toContain("gh api -X PUT repos/acme/handbook/collaborators/jdoe -f permission=pull");
    expect(msg).toContain("--github-access-ok '<reason>'");
  });
});

describe("the access note", () => {
  test("a remark needs an access word AND a GitHub/link/issue word, outside quotations", () => {
    expect(hasGithubAccessRemark("The links need GitHub access.")).toBe(true);
    expect(hasGithubAccessRemark("I sent you an invitation to the issues.")).toBe(true);
    expect(hasGithubAccessRemark("We need access to the server.")).toBe(false);
    expect(hasGithubAccessRemark("> you said the links need access\n\nOk.")).toBe(false);
    expect(hasGithubAccessRemark(GITHUB_ACCESS_NOTE)).toBe(true);
    expect(hasGithubAccessRemark(GITHUB_ACCESS_NOTE, true)).toBe(true);
    expect(hasGithubAccessRemark("The links need GitHub access.", true)).toBe(false);
  });

  test("inserted before the provenance footer and a sign-off; else at the end", () => {
    expect(insertBeforeSignature("Hello.\n\nParked by Claude Code | session x\n", "NOTE")).toBe("Hello.\n\nNOTE\n\nParked by Claude Code | session x\n");
    expect(insertBeforeSignature("Hello.\n\nBest,\nJane\n\nvia Claude Code\n", "NOTE")).toBe("Hello.\n\nNOTE\n\nBest,\nJane\n\nvia Claude Code\n");
    expect(insertBeforeSignature("Hello.\n\nThanks,\n\nJane\n", "NOTE")).toBe("Hello.\n\nNOTE\n\nThanks,\n\nJane\n");
    expect(insertBeforeSignature("Hello.\n\nMore.", "NOTE")).toBe("Hello.\n\nMore.\n\nNOTE\n");
  });

  const priv = fakeGh({
    "api repos/acme/handbook": ok({ visibility: "private" }),
    "api repos/acme/handbook/collaborators/jdoe/permission": ok({ permission: "read" }),
    "api repos/acme/site": ok({ visibility: "public" }),
  });
  const opts = { githubRepo: "acme/handbook", readers: ["jdoe"], noAccessNote: false };

  test("appended: a private link and no remark", async () => {
    const r = await prepareGithubLinks("Fixed in #12.\n\nParked by Claude Code\n", opts, priv);
    expect(r.refusal).toBeNull();
    expect(r.accessNote).toBe("appended");
    expect(r.body).toBe(`Fixed in [#12](${ISSUE}).\n\n${GITHUB_ACCESS_NOTE}\n\nParked by Claude Code\n`);
    expect(r.githubAccess).toEqual({ repos: { "acme/handbook": { visibility: "private", readers: { jdoe: "can-comment" }, notes: [] } }, privateRepos: 1, accessOk: null });
  });

  test("present: the body already says so, and it is left alone", async () => {
    const body = "Fixed in #12. You have access to the GitHub issues already.\n";
    const r = await prepareGithubLinks(body, opts, priv);
    expect(r.accessNote).toBe("present");
    expect(r.body).toBe(`Fixed in [#12](${ISSUE}). You have access to the GitHub issues already.\n`);
  });

  test("suppressed: --no-github-access-note", async () => {
    const r = await prepareGithubLinks("Fixed in #12.\n", { ...opts, noAccessNote: true }, priv);
    expect(r.accessNote).toBe("suppressed");
    expect(r.body).not.toContain(GITHUB_ACCESS_NOTE);
  });

  test("not-needed: only public links, or no links at all (and then gh is never called)", async () => {
    expect((await prepareGithubLinks("See https://github.com/acme/site/issues/3", opts, priv)).accessNote).toBe("not-needed");
    const none = fakeGh({});
    const r = await prepareGithubLinks("No links here, item #4.", { readers: [], noAccessNote: false }, none);
    expect(r.accessNote).toBe("not-needed");
    expect(r.githubAccess).toEqual({ repos: {}, privateRepos: 0, accessOk: null });
    expect(none.calls).toEqual([]);
  });

  test("refusal from prepareGithubLinks when a reader has no access; --github-access-ok proceeds and records the reason", async () => {
    const gh = fakeGh({
      "api repos/acme/handbook": ok({ visibility: "private" }),
      "api repos/acme/handbook/collaborators/jdoe/permission": ok({ permission: "none" }),
      "api repos/acme/handbook/invitations": ok(""),
    });
    const refused = await prepareGithubLinks("Fixed in #12.", opts, gh);
    expect(refused.refusal).toContain("jdoe has no access");
    const forced = await prepareGithubLinks("Fixed in #12.", { ...opts, accessOk: "they get access tomorrow" }, gh);
    expect(forced.refusal).toBeNull();
    expect(forced.githubAccess.accessOk).toBe("they get access tomorrow");
    expect(forced.accessNote).toBe("appended");
  });

  test("an invited-pending reader is reported, and a remark that does not mention the invitation gets the note", async () => {
    const gh = fakeGh({
      "api repos/acme/handbook": ok({ visibility: "private" }),
      "api repos/acme/handbook/collaborators/jdoe/permission": ok({ permission: "none" }),
      "api repos/acme/handbook/invitations": ok("jdoe"),
    });
    const r = await prepareGithubLinks("Fixed in #12. The links need GitHub access.", opts, gh);
    expect(r.refusal).toBeNull();
    expect(r.accessNote).toBe("appended");
    expect(r.warnings.join("\n")).toContain("jdoe has a pending invitation to acme/handbook");
  });

  test("with --html the body is not rewritten, and a missing remark refuses", async () => {
    const r = await prepareGithubLinks(`Fixed in ${ISSUE}.`, { ...opts, authoredHtml: `<p>Fixed in <a href="${ISSUE}">#12</a>.</p>` }, priv);
    expect(r.body).toBe(`Fixed in ${ISSUE}.`);
    expect(r.refusal).toContain("--no-github-access-note");
  });

  test("gh unavailable: no refusal, a warning, and the note is added to be safe", async () => {
    const gh = fakeGh({ "api repos/acme/handbook": { ok: false, code: 4, stderr: "", unavailable: "gh is not signed in (run gh auth login)" } });
    const r = await prepareGithubLinks("Fixed in #12.", { ...opts, readers: [] }, gh);
    expect(r.refusal).toBeNull();
    expect(r.accessNote).toBe("appended");
    expect(r.warnings.join("\n")).toContain("gh is not signed in");
  });
});
