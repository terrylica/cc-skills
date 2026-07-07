---
name: auto-sync
description: "Keep a graphify knowledge graph current automatically: --watch mode (live rebuild on file save) or a post-commit git hook (rebuild per commit). TRIGGERS - graphify watch, auto-sync graph, keep graph updated, graphify git hook, graph out of date."
allowed-tools: Read, Bash, Glob, AskUserQuestion
---

# Auto-Sync the Graph

Two mechanisms keep `graphify-out/` in step with a changing corpus. They don't conflict — pick per repo temperament.

> **Prerequisite**: engine installed (`graphify-tools:setup`) and an initial graph built (`graphify-tools:build-graph`).

## Option A — post-commit git hook (recommended default)

```bash
cd <repo> && graphify hook install
```

- Rebuilds the graph once per commit; no background process
- Safe alongside existing hooks (appends, doesn't replace)
- **Worktree-per-branch note**: git hooks live in the shared `.git` dir config; a hook installed in the main checkout fires for worktree commits too — install once per repo, not per worktree

Verify:

```bash
cat <repo>/.git/hooks/post-commit | grep -n graphify
```

## Option B — live watch mode

```bash
graphify <target> --watch
```

- Code file saves → **instant** AST-only rebuild (no LLM, no tokens)
- Doc/image changes → notifies; run `graphify <target> --update` for the LLM re-pass
- Runs in the foreground — launch it via a background Bash task or a dedicated terminal pane, NOT inline in a Claude session
- Useful for multi-agent workflows where parallel agents write code and the graph must stay current between waves

## Choosing

| Situation                                              | Pick                                                                                     |
| ------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| Normal repo, commit-granularity freshness is fine      | Hook (A)                                                                                 |
| Active multi-agent session mutating files continuously | Watch (B)                                                                                |
| Both installed                                         | Fine — watch covers between-commit drift; hook covers sessions where watch isn't running |

## Teardown

```bash
# Watch: kill the foreground process
# Hook: remove the graphify stanza
sed -i '' '/graphify/d' <repo>/.git/hooks/post-commit
```
