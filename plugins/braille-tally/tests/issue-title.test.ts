import { describe, expect, test } from "bun:test";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { commands, denyMessage, ESCAPE_TOKEN, problems, titleProblem, titlesIn } from "../hooks/issue-title-tally-guard.ts";

const bash = (command: string) => problems("Bash", { command });
const t = (s: string) => titlesIn(s).map((w) => w.text);
const dir = mkdtempSync(join(tmpdir(), "issue-title-"));
const at = (name: string) => join(dir, name);
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
    const w = commands(`x "⣿⣶⣴ $(date +%F) report"`).find((c) => c[0]!.text === "x");
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
    expect(t(`gh api graphql -f query='mutation($t:String!){updateIssue(input:{id:"x",title:$t}){issue{id}}}' -f t=Ab`)).toEqual(["Ab"]);
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
    expect(problems("Write", { file_path: at("x.sh"), content: "gh issue create --title Fix\n" })).toHaveLength(1);
    expect(problems("Write", { file_path: at("x"), content: "#!/usr/bin/env bash\ngh issue edit 3 --title Fix\n" })).toHaveLength(1);
    expect(problems("Edit", { file_path: at("x.sh"), old_string: "a", new_string: `gh issue create --title "⣿⣶⣴ Fix"` })).toEqual([]);
    expect(problems("Write", { file_path: at("notes.md"), content: "gh issue create --title Fix" })).toEqual([]);
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

describe("review round: no false blocks", () => {
  test("gh as an argument, not the command, is not read", () => {
    expect(bash("echo gh issue create --title Fix")).toEqual([]);
    expect(bash("grep -rn 'x' . | xargs echo gh issue create --title Fix")).toEqual([]);
  });
  test("a heredoc written to a file is data; one fed to a shell is run", () => {
    expect(bash("cat > usage.txt <<'EOF'\ngh issue create --title Fix\nEOF\necho done")).toEqual([]);
    expect(bash("bash <<'EOF'\ngh issue create --title Fix\nEOF")).toHaveLength(1);
    expect(bash("cat <<-EOF > a.md\n\tgh issue create --title Fix\n\tEOF\ngh issue create --title Fix2")).toHaveLength(1);
  });
  test("a flag value that looks like --title is not a title", () => {
    expect(bash("gh issue edit 7 --body '--title=Fix is rejected'")).toEqual([]);
    expect(bash("gh issue create --label -t --title '⣿⣶⣴ Fix'")).toEqual([]);
  });
  test("a typed field read from a file or stdin is unknown", () => {
    expect(bash("printf x | gh api repos/o/r/issues -F title=@- -f body=x")).toEqual([]);
    expect(bash("gh api repos/o/r/issues -f title=@literal")).toHaveLength(1);
  });
  test("GraphQL: expansions, \\u escapes and other mutations' titles", () => {
    expect(bash(`gh api graphql -f query="mutation { createIssue(input: {repositoryId: \\"$R\\", title: \\"$TITLE\\"}) { issue { id } } }"`)).toEqual([]);
    expect(bash(`gh api graphql -f query='mutation{createIssue(input:{repositoryId:"x",title:"\\u28ff\\u28f6\\u28f4 Fix"}){issue{id}}}'`)).toEqual([]);
    expect(bash(`gh api graphql -f query='mutation{createIssue(input:{repositoryId:"x",title:"⣿⣶⣴ Fix"}){issue{id}} updatePullRequest(input:{pullRequestId:"p",title:"Docs"}){pullRequest{id}}}'`)).toEqual([]);
  });
  test("an MCP issue tool that is not GitHub's is not checked", () => {
    expect(problems("mcp__linear__create_issue", { title: "Fix" })).toEqual([]);
    expect(problems("mcp__plugin_github_github__issue_write", { title: "Fix" })).toHaveLength(1);
  });
  test("a script edit is judged by the titles it adds, not those already there", () => {
    const f = at("old.sh");
    writeFileSync(f, "#!/usr/bin/env bash\ngh issue create --title Legacy\necho hi\n");
    expect(problems("Edit", { file_path: f, old_string: "echo hi", new_string: "echo hello" })).toEqual([]);
    expect(problems("Write", { file_path: f, content: "#!/usr/bin/env bash\ngh issue create --title Legacy\necho hello\n" })).toEqual([]);
  });
});

describe("review round: no false passes", () => {
  test("--repo before the operation", () => {
    expect(bash("gh issue --repo o/r create --title Fix --body x")).toHaveLength(1);
    expect(bash("gh -R o/r issue edit 3 -t Fix")).toHaveLength(1);
  });
  test("inside a command substitution or backticks", () => {
    expect(bash("url=$(gh issue create --title 'Fix' --body x)")).toHaveLength(1);
    expect(bash('echo "made $(gh issue create --title Fix)"')).toHaveLength(1);
    expect(bash("u=`gh issue create --title Fix`")).toHaveLength(1);
  });
  test("ANSI-C quoting is literal", () => {
    expect(bash("gh issue create --title $'Fix the login timeout' --body x")).toHaveLength(1);
  });
  test("a GraphQL variable with any name resolves to its field", () => {
    expect(bash(`gh api graphql -f query='mutation($r:ID!,$t:String!){createIssue(input:{repositoryId:$r,title:$t}){issue{id}}}' -f r=x -f t=Fix`)).toHaveLength(1);
  });
  test("a partial edit that removes the tally from a script", () => {
    const f = at("new-issue.sh");
    writeFileSync(f, "#!/usr/bin/env bash\ngh issue create --title \"⣿⣶⣴ Fix login\" --body x\n");
    expect(problems("Edit", { file_path: f, old_string: "⣿⣶⣴ Fix login", new_string: "Fix login" })).toHaveLength(1);
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
