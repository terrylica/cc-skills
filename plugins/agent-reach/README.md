# Agent Reach Plugin

Give your AI agent eyes to see the entire internet. Wraps [Agent Reach](https://github.com/Panniantong/Agent-Reach) with auto-update preflight.

## Skills

- **agent-reach** — Search and read 15+ platforms with auto-update preflight

## Installation

Agent Reach is installed via pipx. The skill's preflight handles installation and updates automatically.

```bash
# Manual install (preflight does this for you)
pipx install https://github.com/Panniantong/agent-reach/archive/main.zip --python python3.13
agent-reach install --env=auto
```

## Health Check

```bash
agent-reach doctor
```
