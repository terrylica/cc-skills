# orca-tools

Skills for working with Claude Code under the [Orca IDE](https://www.onorca.dev): its CLI and its GUI, locally and on paired runtimes on other devices.

| Skill | What it does |
| --- | --- |
| [floating-terminal](./skills/floating-terminal/SKILL.md) | The default terminal for agents under Orca: runs a command that needs a person or a TTY (biometric unlock, a password manager's app integration, `sudo`, a prompt) in Orca's floating terminal and returns its real exit code and output as JSON. |
| [session-closeout](./skills/session-closeout/SKILL.md) | Closes out a session: a recall name sized to what Claude Code and Orca's Agent Session History display, a compact handoff as the last message, and, if wanted, a safe close of the session's own terminal tab to free memory. |
| [worktree-spinoff](./skills/worktree-spinoff/SKILL.md) | Spins a task off the default branch into its own Orca worktree, with one agent terminal, the handoff committed in the branch and a readable sidebar entry. It works on this machine or a paired runtime, and removes the worktree cleanly afterwards. |

```bash
claude plugin marketplace add terrylica/cc-skills
claude plugin install orca-tools@cc-skills
```

Requirements: the Orca IDE CLI, `bash ≥ 3.2`, `git ≥ 2.20`, `python3 ≥ 3.9`. A Nix profile is the reference way to get the same tools on macOS, Linux and BSD.
