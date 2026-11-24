import { describe, expect, test } from "bun:test";
import { commands, denyMessage, ESCAPE_TOKEN, problems, titleProblem, titlesIn } from "../hooks/issue-title-tally-guard.ts";

const bash = (command: string) => problems("Bash", { command });
const t = (s: string) => titlesIn(s).map((w) => w.text);
const run = async (payload: unknown) => {
  const p = Bun.spawn(["bun", `${import.meta.dir}/../hooks/issue-title-tally-guard.ts`], { stdin: new Blob([JSON.stringify(payload)]), stdout: "pipe" });
  const out = await new Response(p.stdout).text();
  return { code: await p.exited, out };
};

describe("the shell lexer", () => {
  test("splits commands on control operators and keeps quoted text whole", () => {
    expect(commands(`a "b c" 'd;e' && f | g; h\ni # j`).map((c) => c.map((w) => w.text))).toEqual([["a", "b c", "d;e"], ["f"], ["g"], ["h"], ["i"]]);
  });
  test("marks where an expansion starts, and keeps $( … ) inside its word", () => {
    const [w] = commands(`x "⣿⣶⣴ $(date +%F) report"`);
    expect(w![1]!.text).toBe("⣿⣶⣴ $(date +%F) report");
    expect(w![1]!.dynamicAt).toBe(4);
    expect(commands("x 'literal $HOME'")[0]![1]!.dynamicAt).toBe(-1);
  });
});

describe("titles found in shell text", () => {
  test("every --title form of gh issue create, new and edit", () => {
    expect(t(`gh issue create -R o/r --title "A b" --body x`)).toEqual(["A b"]);
    expect(t(`gh issue new -t 'A b'`)).toEqual(["A b"]);
    expect(t(`gh issue edit 5 --title="A b"`)).toEqual(["A b"]);
    expect(t(`gh issue edit 5 -tAb`)).toEqual(["Ab"]);
    expect(t(`gh issue edit 5 -t=Ab`)).toEqual(["Ab"]);
    expect(t(`GH_TOKEN=x /usr/local/bin/gh issue create --title Ab`)).toEqual(["Ab"]);
  });
  test("gh api: REST issue create/update with a title field, and GraphQL create/updateIssue", () => {
    expect(t(`gh api repos/o/r/issues -f title='A b' -f body=x`)).toEqual(["A b"]);
    expect(t(`gh api -X PATCH /repos/o/r/issues/7 -F title=Ab`)).toEqual(["Ab"]);
    expect(t(`gh api repos/o/r/issues/7 --raw-field=title=Ab`)).toEqual(["Ab"]);
    expect(t(`gh api graphql -f query='mutation{createIssue(input:{repositoryId:"x",title:"A b"}){issue{id}}}'`)).toEqual(["A b"]);
    expect(t(`gh api graphql -f query='mutation($t:String!){updateIssue(input:{id:"x",title:$t}){issue{id}}}' -f title=Ab`)).toEqual(["Ab"]);
  });
  test("ignores what does not write a title", () => {
    expect(titlesIn(`gh issue edit 5 --body "x" --add-label bug`)).toEqual([]);
    expect(titlesIn(`gh issue list --search "title"`)).toEqual([]);
    expect(titlesIn(`gh api repos/o/r/issues/7/comments -f body=x`)).toEqual([]);
    expect(titlesIn(`gh api -X GET repos/o/r/issues -f title=x`)).toEqual([]);
    expect(titlesIn(`gh api graphql -f query='query{repository(owner:"o",name:"r"){issues(first:1){nodes{title}}}}'`)).toEqual([]);
    expect(titlesIn(`echo "gh issue create --title x"`)).toEqual([]);
  });
});

describe("the rule", () => {
  test("a tally, one space, then the title passes", () => {
    expect(bash(`gh issue create --title "⣿⣶⣴ Fix the login timeout" --body x`)).toEqual([]);
    expect(bash(`gh issue edit 12 -t '⣀⣤⣿ Rename the config flag'`)).toEqual([]);
  });
  test("a missing tally is blocked", () => {
    expect(bash(`gh issue create --title "Fix the login timeout"`)).toEqual(['"Fix the login timeout" does not start with a Braille Tally and one space']);
  });
  test("levels in digits or numbering after the tally are blocked; the glyph alone", () => {
    expect(bash(`gh issue create --title "⣿⣶⣴ (8·6·5) Fix it"`)).toHaveLength(1);
    expect(bash(`gh issue create --title "⣿⣶⣴ 1. Fix it"`)).toHaveLength(1);
    expect(bash(`gh issue create --title "⣿⣶⣴ #3 Fix it"`)).toHaveLength(1);
    expect(bash(`gh issue create --title "⣿⣶⣴ IV. Fix it"`)).toHaveLength(1);
    expect(bash(`gh issue create --title "⣿⣶⣴ 2026 roadmap"`)).toEqual([]);
  });
  test("cells that are not tally levels, or a tally with no text, are blocked", () => {
    expect(bash(`gh issue create --title "⠿⠿⠿ Fix it"`)).toHaveLength(1);
    expect(bash(`gh issue create --title "⣿⣶⣴ "`)).toHaveLength(1);
  });
  test("a title from a variable is not known here and is allowed; a known prefix is still checked", () => {
    expect(titleProblem({ text: "$T", dynamicAt: 0 })).toBeUndefined();
    expect(bash(`gh issue create --title "$TITLE"`)).toEqual([]);
    expect(bash(`gh issue create --title "⣿⣶⣴ $WHAT"`)).toEqual([]);
    expect(bash(`gh issue create --title "Bug: $WHAT"`)).toHaveLength(1);
  });
  test("a shell script written to disk is checked; other files are not", () => {
    expect(problems("Write", { file_path: "/tmp/x.sh", content: "gh issue create --title Fix\n" })).toHaveLength(1);
    expect(problems("Write", { file_path: "/tmp/x", content: "#!/usr/bin/env bash\ngh issue edit 3 --title Fix\n" })).toHaveLength(1);
    expect(problems("Edit", { file_path: "/tmp/x.sh", old_string: "a", new_string: `gh issue create --title "⣿⣶⣴ Fix"` })).toEqual([]);
    expect(problems("Write", { file_path: "/tmp/notes.md", content: "gh issue create --title Fix" })).toEqual([]);
  });
  test("GitHub MCP issue tools are checked by their title argument", () => {
    expect(problems("mcp__github__create_issue", { owner: "o", repo: "r", title: "Fix" })).toHaveLength(1);
    expect(problems("mcp__github__issue_write", { method: "update", issue_number: 1, title: "⣿⣶⣴ Fix" })).toEqual([]);
    expect(problems("mcp__github__update_issue", { issue_number: 1, body: "x" })).toEqual([]);
  });
  test("the escape token silences it, and the deny message never spells the token", () => {
    expect(bash(`gh issue create --title "Fix" # ${ESCAPE_TOKEN}: upstream template`)).toEqual([]);
    expect(denyMessage(["x"])).not.toContain(ESCAPE_TOKEN);
  });
});

describe("the hook process", () => {
  test("denies with the fix, allows a tallied title, and fails open on garbage", async () => {
    const deny = await run({ tool_name: "Bash", tool_input: { command: `gh issue create --title "Fix it"` } });
    expect(deny.code).toBe(0);
    expect(JSON.parse(deny.out).hookSpecificOutput.permissionDecision).toBe("deny");
    expect((await run({ tool_name: "Bash", tool_input: { command: `gh issue create --title "⣿⣶⣴ Fix it"` } })).out).toBe("");
    const p = Bun.spawn(["bun", `${import.meta.dir}/../hooks/issue-title-tally-guard.ts`], { stdin: new Blob(["not json gh"]), stdout: "pipe" });
    expect(await new Response(p.stdout).text()).toBe("");
    expect(await p.exited).toBe(0);
  });
});
