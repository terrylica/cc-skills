# git-town-workflow Plugin

> Prescriptive git-town workflow enforcement for fork-based development.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [gh-tools CLAUDE.md](../gh-tools/CLAUDE.md)

## Commands

| Command                         | Purpose                             |
| ------------------------------- | ----------------------------------- |
| `/git-town-workflow:scion`      | Create/configure fork workflow      |
| `/git-town-workflow:contribute` | Complete contribution cycle         |
| `/git-town-workflow:setup`      | Initialize git-town in repository   |
| `/git-town-workflow:tether`     | Install/uninstall enforcement hooks |

## Philosophy

**Git-town is canonical. Raw git branch commands are forbidden.**

| Blocked                | Use Instead       |
| ---------------------- | ----------------- |
| `git checkout -b`      | `git town hack`   |
| `git pull`             | `git town sync`   |
| `git merge`            | `git town sync`   |
| `git push origin main` | `git town sync`   |
| `git branch -d`        | `git town delete` |
| `git rebase`           | `git town sync`   |

Allowed: `git add`, `git commit`, `git status`, `git log`, `git diff`, `git stash`.

## Skills

- [contribute](./skills/contribute/SKILL.md)
- [scion](./skills/scion/SKILL.md) — renamed from `fork` to avoid `/fork` (alias for `/branch`) clash
- [tether](./skills/tether/SKILL.md) — renamed from `hooks` to avoid `/hooks` clash
- [setup](./skills/setup/SKILL.md)
