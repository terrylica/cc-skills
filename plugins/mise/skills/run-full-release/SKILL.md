---
name: run-full-release
description: "Run the current repo's mise release pipeline with auto-scaffolding. Handles GitHub releases (mandatory), PyPI publishing (if Python), and crates.io (if Rust). TRIGGERS - mise release, full release, version bump, release automation, mise run release."
allowed-tools: Read, Bash, Glob, Grep, Write, Edit, AskUserQuestion
argument-hint: "[--dry] [--status]"
model: haiku
---

# /mise:run-full-release

Run the current repo's mise release pipeline end-to-end. Detects GitHub releases (mandatory), PyPI (optional), and crates.io (optional).

## Step 0: Pre-Release Sync

```bash
git pull origin main
```

## Step 1: Detect Release Tasks

```bash
mise tasks ls 2>/dev/null | grep -i release
```

If release tasks **NOT FOUND** → read [scaffolding-and-recovery.md](./references/scaffolding-and-recovery.md) and scaffold first.

## Step 2: Execute Release

1. Check working directory: `git status --porcelain`
2. Push unpushed commits: `git log --oneline @{u}..HEAD` → `git push origin main`
3. Reset lockfile drift: `git diff --name-only | grep -E '(uv\.lock|package-lock\.json|Cargo\.lock|bun\.lockb)$' | xargs -r git checkout --`
4. If dirty → commit related changes or stash WIP, then verify clean
5. Route by flags:
   - `--dry` → `mise run release:dry`
   - `--status` → `mise run release:status`
   - No flags → `mise run release:full`
6. Post-release: reset any lockfile drift from release tasks

## References

- [Scaffolding & Recovery](./references/scaffolding-and-recovery.md) — audit, scaffold, error recovery, known issues
- [Task Implementations](./references/task-implementations.md) — PyPI, crates.io, postflight details

## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path (Glob for this skill's name) before editing. All corrections target THIS file and its sibling references/ — never other documentation.
1. **What failed?** — Fix the instruction that caused it. If it could recur, add it as an anti-pattern.
2. **What worked better than expected?** — Promote it to recommended practice. Document why.
3. **What drifted?** — Any script, reference, or external dependency that no longer matches reality gets fixed now.
4. **Log it.** — Every change gets an evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
