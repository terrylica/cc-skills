---
name: auto-sync
description: "Keep a graphify knowledge graph current automatically: --watch mode (live rebuild on file save) or a post-commit git hook (rebuild per commit). TRIGGERS - graphify watch, auto-sync graph, keep graph updated, graphify git hook, graph out of date."
allowed-tools: Read, Bash, Glob, AskUserQuestion
---

# Auto-Sync the Graph

> **Self-Evolving Skill**: This skill improves through use. If the hook behavior or `--watch` semantics drift — fix this file immediately, don't defer. Only update for real, reproducible issues.

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

## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path before editing.
1. **What failed?** — Fix the instruction that caused it.
2. **What worked better than expected?** — Promote to recommended practice.
3. **What drifted?** — Fix any script, reference, or dependency (esp. `references/backends.md`) that no longer matches reality.
4. **Log it.** — Add a dated note to the plugin CLAUDE.md provenance with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
