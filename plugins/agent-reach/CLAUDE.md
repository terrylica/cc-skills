# agent-reach Plugin

> Wraps [Panniantong/Agent-Reach](https://github.com/Panniantong/Agent-Reach) to search and read 15+ platforms (Twitter/X, Reddit, YouTube, GitHub, Bilibili, XiaoHongShu, Douyin, Weibo, WeChat, Xiaoyuzhou, LinkedIn, V2EX, RSS, Exa). Auto-update preflight keeps the CLI current.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [plugins/CLAUDE.md](../CLAUDE.md)

## Install & Health

Installed via `pipx` — the skill's preflight installs/updates automatically.

```bash
pipx install https://github.com/Panniantong/agent-reach/archive/main.zip --python python3.14
agent-reach install --env=auto
agent-reach doctor
```

## Skills

- [agent-reach](./skills/agent-reach/SKILL.md)

## References

- [README.md](./README.md)
- Upstream: <https://github.com/Panniantong/Agent-Reach>

## Shell access (issue #98)

The `agent-reach` skill declares broad `Bash` in `allowed-tools` — **by design**.
It drives a headless browser and shells out to varied, dynamically-constructed
commands, so a scoped `Bash(cmd:*)` allowlist would be brittle and would break
the skill. Note that `allowed-tools` gates _capability_, not auto-approval: every
command still goes through the normal Claude Code permission prompts unless the
operator has explicitly allowlisted it in settings. An external scanner flagged
this as "unrestricted shell approval" (#98); it is intentional, not a defect.
