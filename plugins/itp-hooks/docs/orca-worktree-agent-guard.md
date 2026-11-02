# Orca worktree agent guard

`hooks/pretooluse-orca-worktree-agent-guard.ts`, one of the Bash guards of `pretooluse-bash-guard-orchestrator.ts`.

**Rule** (operator, 2026-11-01, every device): a worktree gets an Orca sidebar entry only when it gets a session. A worktree made with `orca worktree create` and no `--agent` appears in Orca's sidebar with an idle shell and no session; on 2026-11-01 one such entry (`s503`, created for work its parent session did itself) prompted the rule.

**What it denies:** a Bash command with an `orca worktree create` invocation that carries no `--agent` (or `--agent=<id>`).

**What it allows:** `--agent` present, `--help`, mentions of the command in `echo`, `printf`, `grep`/`rg`, comments, `git commit`/`git tag` messages and `gh` issue, PR or release text, and the escape hatch `ORCA-NO-AGENT-OK: <reason of at least 10 characters>`. Any error inside the guard allows the command (fail-open).

**What to do instead:**

| Need | Use | In Orca's sidebar |
| --- | --- | --- |
| A session's own isolated work | a Claude Code worktree under `<repo>/.claude/worktrees/<name>`: the EnterWorktree tool, or `git worktree add .claude/worktrees/<name> -b <branch> origin/main` | hidden by default (a non-Orca worktree) |
| A parallel sub-task | a subagent with `isolation: worktree` | hidden; removed when it made no change |
| A separate session to watch | `orca worktree create --agent claude --prompt "<handoff>" …` (orca-tools' worktree-spinoff skill) | one entry, with its session running |

**Sources:** [Orca docs, Worktrees](https://www.onorca.dev/docs/model/worktrees) (worktrees made with `git worktree add` stay external until shown; Claude Code worktrees are their own external source, hidden by default); [Claude Code docs, worktrees](https://code.claude.com/docs/en/worktrees) (`.claude/worktrees/<name>`, EnterWorktree, subagent isolation, cleanup).

**Tests:** `hooks/pretooluse-orca-worktree-agent-guard.test.ts` spawns the real hook; the first deny case is the 2026-11-01 command.
