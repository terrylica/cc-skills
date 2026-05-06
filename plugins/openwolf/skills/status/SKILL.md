---
name: status
description: "Show openwolf health for cwd (files, hooks, ledger, anatomy, daemon). TRIGGERS - openwolf status, openwolf health."
allowed-tools: Read, Bash, Glob
---

# OpenWolf Status

Surface the state of openwolf in the **current project** (cwd at invocation). Read-only — never mutates anything.

> **Self-Evolving Skill**: If `openwolf status` output drifts or new fields appear, update this file. Only for real, reproducible drift.

## Workflow

### Step 1: Preflight

```bash
command -v openwolf >/dev/null || { echo "openwolf binary not installed. Run /openwolf:install."; exit 1; }
[ -d "$(pwd)/.wolf" ] || { echo "No .wolf/ in $(pwd) — this project is not openwolf-managed."; exit 0; }
```

### Step 2: Run status

```bash
openwolf status
```

This prints (plain text to stdout):

- Core file integrity (`.wolf/*.md`, `.wolf/*.json`)
- Hook script integrity (`.wolf/hooks/*.js`)
- Hook registration in `.claude/settings.json`
- Token stats (sessions, reads, writes, tokens tracked, estimated savings)
- Anatomy file count
- Daemon state + last heartbeat

### Step 3: Cross-check the registry

```bash
node -e '
const fs=require("fs"), path=require("path"), os=require("os");
const reg = JSON.parse(fs.readFileSync(path.join(os.homedir(),".openwolf/registry.json"),"utf-8"));
const here = process.cwd().toLowerCase().replace(/\\/g,"/");
const entry = reg.projects.find(p => p.root.toLowerCase().replace(/\\/g,"/") === here);
console.log(entry ? `Registry: registered as "${entry.name}" v${entry.version} (since ${entry.registered_at.slice(0,10)})` : "Registry: NOT registered");
' 2>/dev/null || echo "Registry: not present at ~/.openwolf/registry.json"
```

### Step 4: Anatomy freshness check (advisory)

```bash
openwolf scan --check
echo "scan --check exit code: $?  (0 = anatomy in sync, 1 = stale; rerun openwolf scan)"
```

### Step 5: Summarize

Report concisely to the user:

- Health: any missing files / unregistered hooks
- Tokens saved this project (lifetime)
- Whether the anatomy is stale
- Whether the daemon is running

## Post-Execution Reflection

0. **Locate yourself.** — This SKILL.md path.
1. **Did `openwolf status` add new fields you didn't surface?** — Add a parser line.
2. **Did the registry path or shape change?** — Update the node one-liner in step 3.
