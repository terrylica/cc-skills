# Bash Permission Patterns

## Critical Rule: Subcommand-Level Specificity

**NEVER ALLOWED**:

```yaml
allowed-tools: Bash
```

Blanket Bash permission is **prohibited** per official Anthropic patterns.

**TOO BROAD** (for commands with subcommands):

```yaml
allowed-tools: Bash(git:*), Bash(gh:*), Bash(npm:*)
```

Command-level wildcards allow dangerous operations (`git reset --hard`, `gh repo delete`).

**REQUIRED** (subcommand-level specificity):

```yaml
allowed-tools: Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(gh repo view:*)
```

Must specify **exact subcommands** for commands with subcommand hierarchies.

**OK** (commands without subcommands):

```yaml
allowed-tools: Bash(cp:*), Bash(mkdir -p:*), Bash(date:*), Bash(open:*)
```

Simple commands without subcommand hierarchies can use command-level.

---

## Official Permission Patterns

Based on Anthropic's documented examples:

**Git Operations** (code-review, update-docs):

```yaml
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Bash(git add:*), Bash(git commit:*)
```

**File Discovery** (codebase-analysis):

```yaml
allowed-tools: Bash(find:*), Bash(tree:*), Bash(ls:*), Bash(du:*)
```

**Content Analysis** (comprehensive discovery):

```yaml
allowed-tools: Bash(grep:*), Bash(wc:*), Bash(head:*), Bash(tail:*), Bash(cat:*)
```

**Data Processing** (custom analysis):

```yaml
allowed-tools: Bash(awk:*), Bash(sed:*), Bash(sort:*), Bash(uniq:*)
```

**Combined Patterns** (multi-phase commands):

```yaml
allowed-tools: Bash(find:*), Bash(tree:*), Bash(ls:*), Bash(grep:*), Bash(wc:*), Bash(du:*), Bash(head:*), Bash(tail:*), Bash(cat:*), Bash(touch:*)
```

---

## Permission Selection Guide

| Command Type        | Bash Permissions                            | Example Commands                |
| ------------------- | ------------------------------------------- | ------------------------------- |
| **Git Commands**    | `git status, git diff, git log, git branch` | code-review, commit-assist      |
| **Discovery**       | `find, tree, ls, du`                        | codebase-analyze, structure-map |
| **Analysis**        | `grep, wc, head, tail, cat`                 | search-code, count-lines        |
| **Update**          | `git diff, find, grep`                      | update-docs, sync-config        |
| **Data Processing** | `awk, sed, sort, uniq`                      | parse-data, format-output       |
| **Comprehensive**   | All of the above                            | full-audit, system-analyze      |
