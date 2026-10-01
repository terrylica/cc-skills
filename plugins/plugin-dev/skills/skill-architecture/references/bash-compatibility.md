# Bash Compatibility for Skills

Claude Code's Bash tool runs **zsh** on macOS. Most everyday syntax behaves the same in zsh and bash, so wrap a block in bash only when it uses something zsh does not implement, or implements differently.

## Measured under zsh (2026-10-01)

Each row was run with `zsh -c '…'`.

| Form                                          | Under zsh                                                 | Wrap in bash?                          |
| --------------------------------------------- | --------------------------------------------------------- | -------------------------------------- |
| `FOO=$(cmd) other-cmd`, `$(...)`, `[[ ... ]]` | works                                                     | no                                     |
| `declare -A m; m[k]=v`                        | works                                                     | no                                     |
| `for i in {1..3}`                             | works                                                     | no                                     |
| `${!assoc[@]}` (keys of an associative array) | `bad substitution`                                        | **yes**                                |
| `${var,,}` / `${var^^}` (case conversion)     | `bad substitution`                                        | **yes**                                |
| `mapfile` / `readarray`                       | `command not found`                                       | **yes**                                |
| `BASH_REMATCH` after `[[ s =~ re ]]`          | **silently empty** (zsh uses `$match`)                    | **yes**                                |
| unquoted `$var` holding spaces                | **silently not word-split**                               | **yes**, or quote and split explicitly |
| `${arr[1]}`                                   | **silently the first element** (zsh arrays are 1-indexed) | **yes**                                |

The loud failures are easy: the command errors. The last three are the dangerous ones, because the block runs and produces a wrong answer.

## How to wrap

```bash
/usr/bin/env bash <<'SCRIPT_EOF'
declare -A seen=([a]=1 [b]=1)
for k in "${!seen[@]}"; do echo "$k"; done
SCRIPT_EOF
```

For one line, use `/usr/bin/env bash -c '…'`. Quote the heredoc delimiter (`<<'EOF'`) so the outer shell does not expand anything inside it.

## Not a shell difference

`grep -P` fails on macOS because BSD `grep` has no PCRE, whatever the shell. Use `grep -E`, `rg`, or `perl`.

## History

The [Skill Bash Compatibility Enforcement ADR](/docs/adr/2025-12-22-skill-bash-compatibility-enforcement.md) made a heredoc wrapper mandatory for every block. That rule rested on failures such as ``parse error near `('`` for `VAR=$(cmd) other`, which no longer reproduce, and nothing enforces it. It is superseded by the measured table above.
