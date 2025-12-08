# ITP Plugin

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-9-blue.svg)]()
[![Commands](https://img.shields.io/badge/Commands-3-green.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

Execute approved plans from Claude Code's **Plan Mode** through an ADR-driven 4-phase workflow: preflight → implementation → formatting → release.

> [!NOTE]
> **Why "ITP"?** Originally "Implement The Plan"—shortened to prevent keyword priming. Using "implement" in a command name caused Claude Code to skip preflight and jump straight to implementation. The neutral acronym avoids action inference and is faster to type.

## Features

- **Preflight Phase**: Create ADR ([MADR 4.0](https://github.com/adr/madr)) and design spec with graph-easy diagrams
- **Phase 1**: Implementation with engineering standards
- **Phase 2**: Formatting with Prettier and GitHub push
- **Phase 3**: Semantic versioning and release automation

## How It Works

This plugin bridges Claude Code's **Plan Mode** and implementation:

1. **Enter Plan Mode** — Press `Shift+Tab` twice (or use `--permission-mode plan`)
2. **Create Plan** — Claude analyzes your request and writes a plan to `~/.claude/plans/<name>.md`
3. **Trigger /itp:go** — Two paths available (see below)
4. **Execute Workflow** — 4-phase transformation into permanent artifacts

> [!TIP]
> **Command Format**: Plugin commands display as `/itp:go`, `/itp:setup`, `/itp:hooks` in autocomplete. See [Slash Command Naming Convention](../../README.md#slash-command-naming-convention) for details on the `plugin:command` format.

### Plan Mode → /itp:go Bridge (Two Rejection Paths)

> [!TIP]
> **[Claude Code 2.0.57+](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)**: "Added feedback input when rejecting plans, allowing users to tell Claude what to change" — This enables both paths below.

Both paths use the **rejection feedback input** introduced in Claude Code 2.0.57. When reviewing a plan, you're presented with options (typically: approve, modify, reject). Choosing the **third option (reject)** opens a feedback input field where you can type a command or message.

```
🔄 Plan Mode → /itp:go Bridge (Two Rejection Paths)

                                 +---------------------------+
                                 | Plan Mode (Shift+Tab ×2)  |
                                 +---------------------------+
                                   |
                                   |
                                   v
                                 +---------------------------+
                                 | ~/.claude/plans/<name>.md |
                                 +---------------------------+
                                   |
                                   |
                                   v
+--------------------------+     +---------------------------+
| Path A: Type in feedback |     |        Review Plan        |
|  SlashCommand tool call  |     | Choose option 3 (reject)  |
|        /itp:go           | <-- |  → feedback input opens   |
+--------------------------+     +---------------------------+
  |                                |
  |                                |
  |                                v
  |                              +---------------------------+
  |                              |   Path B: Type message    |
  |                              |    "Wait for /itp:go"     |
  |                              +---------------------------+
  |                                |
  |                                |
  |                                v
  |                              +---------------------------+
  |                              |       Claude waits        |
  |                              |         for input         |
  |                              +---------------------------+
  |                                |
  |                                |
  |                                v
  |                              +---------------------------+
  |                              |      Type /itp:go         |
  |                              |     at command prompt     |
  |                              +---------------------------+
  |                                |
  |                                |
  |                                v
  |                              #===========================#
  |                              H      /itp:go Workflow     H
  +----------------------------> H        (4 phases)         H
                                 #===========================#
```

#### Path A: Direct Command in Feedback Input (Fastest)

1. Review the plan Claude created
2. Choose **option 3 (reject)** — feedback input field opens
3. Type: `SlashCommand tool call /itp:go`
4. ITP workflow triggers immediately

#### Path B: Defer to Command Prompt (More Control)

1. Review the plan Claude created
2. Choose **option 3 (reject)** — feedback input field opens
3. Type: `"Wait for my further instruction"`
4. Claude acknowledges: `"Understood. Waiting for your instructions."`
5. Type `/itp:go` at the command prompt

**Note**: If running with `--dangerously-skip-permissions`, you may need to press `Shift+Enter` to return to bypass-permissions mode before entering the `/itp:go` command.

#### Path Comparison

| Aspect           | Path A (Feedback Input)                     | Path B (Command Prompt)                   |
| ---------------- | ------------------------------------------- | ----------------------------------------- |
| **Steps**        | Fewer (direct trigger)                      | Extra step (Claude waits first)           |
| **Interface**    | Plain text field                            | Native slash command interface            |
| **Autocomplete** | ❌ No hints or suggestions                  | ✅ `/itp:go` shows in dropdown            |
| **Syntax**       | Must type full `SlashCommand tool call ...` | Just type `/itp:go` and select from hints |

**Recommendation**: Use **Path B** if you want the native Claude Code experience with autocomplete hints. Use **Path A** if you prefer fewer steps and don't mind typing the full command.

<!-- graph-easy source:
graph { flow: south; }
[ Plan Mode ] { label: "Plan Mode (Shift+Tab ×2)"; }
[ Plan File ] { label: "~/.claude/plans/<name>.md"; }
[ Review ] { label: "Review Plan\nChoose option 3 (reject)\n→ feedback input opens"; }
[ Path A ] { label: "Path A: Type in feedback\nSlashCommand tool call\n/itp:go"; }
[ Path B ] { label: "Path B: Type message\n\"Wait for /itp:go\""; }
[ Wait ] { label: "Claude waits\nfor input"; }
[ Cmd ] { label: "Type /itp:go\nat command prompt"; }
[ ITP ] { border: double; label: "/itp:go Workflow\n(4 phases)"; }

[ Plan Mode ] -> [ Plan File ] -> [ Review ]
[ Review ] --> [ Path A ]

[ Review ] --> [ Path B ]
[ Path A ] -> [ ITP ]
[ Path B ] -> [ Wait ] -> [ Cmd ] -> [ ITP ]
-->

### 4-Phase Workflow

```
🚀 /itp:go 4-Phase Workflow

╭──────────────╮     ┌─────────────┐     ┌──────────┐     ╔═══════════╗
│  Preflight   │     │   Phase 1   │     │ Phase 2  │     ║  Phase 3  ║
│ (ADR + Spec) │ ──> │ (Implement) │ ──> │ (Format) │ ──> ║ (Release) ║
╰──────────────╯     └─────────────┘     └──────────┘     ╚═══════════╝
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🚀 /itp:go 4-Phase Workflow"; flow: east; }
[ P0 ] { shape: rounded; label: "Preflight\n(ADR + Spec)"; }
[ P1 ] { label: "Phase 1\n(Implement)"; }
[ P2 ] { label: "Phase 2\n(Format)"; }
[ P3 ] { border: double; label: "Phase 3\n(Release)"; }
[ P0 ] -> [ P1 ] -> [ P2 ] -> [ P3 ]
```

</details>

### Why /itp:go?

The plan file in `~/.claude/plans/` is **ephemeral**—Claude uses random names like `abstract-fluttering-unicorn.md` that get overwritten on the next planning session. Decisions made during [AskUserQuestion](https://egghead.io/create-interactive-ai-tools-with-claude-codes-ask-user-question~b47wn) flows are also lost when context compacts.

The `/itp:go` workflow captures these ephemeral artifacts as **permanent** records:

> [!TIP]
> **Why capture decisions immediately?** See [Claude Code Ephemeral Context](skills/implement-plan-preflight/references/claude-code-ephemeral-context.md) for details on how plan files and question flows work—and why waiting means losing your architectural decisions.

```
📦 Artifact Transformation

┌−−−−−−−−−−−−−−−−−−−−−−┐           ┌−−−−−−−−−−−−−−−−−−┐
╎ Ephemeral:           ╎           ╎                  ╎
╎                      ╎           ╎                  ╎
╎ ┌──────────────────┐ ╎           ╎ ┌──────────────┐ ╎
╎ │ ~/.claude/plans/ │ ╎ /itp:go  ╎ │  /docs/adr/  │ ╎
╎ │ [!] Overwritten  │ ╎ ───────> ╎ │ [+] Persists │ ╎
╎ └──────────────────┘ ╎           ╎ └──────────────┘ ╎
╎                      ╎           ╎                  ╎
└−−−−−−−−−−−−−−−−−−−−−−┘           └−−−−−−−−−−−−−−−−−−┘
    │
    │ /itp:go
    ∨
┌−−−−−−−−−−−−−−−−−−−−−−┐
╎ Permanent:           ╎
╎                      ╎
╎ ┌──────────────────┐ ╎
╎ │  /docs/design/   │ ╎
╎ │   [+] Persists   │ ╎
╎ └──────────────────┘ ╎
╎                      ╎
└−−−−−−−−−−−−−−−−−−−−−−┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "📦 Artifact Transformation"; flow: east; }
( Ephemeral:
  [ Global Plan ] { label: "~/.claude/plans/\n[!] Overwritten"; }
)
( Permanent:
  [ ADR ] { label: "/docs/adr/\n[+] Persists"; }
  [ Spec ] { label: "/docs/design/\n[+] Persists"; }
)
[ Global Plan ] -- /itp:go --> [ ADR ]
[ Global Plan ] -- /itp:go --> [ Spec ]
```

</details>

## Installation

### Option 1: Plugin Installation (Recommended)

```bash
# 1. Add marketplace
/plugin marketplace add terrylica/cc-skills

# 2. Install plugin
/plugin install cc-skills@itp

# 3. Run setup (first time only)
/itp:setup

# 4. Use workflow
/itp:go my-feature -b
```

### Option 2: Settings Configuration

Add to `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "cc-skills": {
      "source": {
        "source": "github",
        "repo": "terrylica/cc-skills"
      }
    }
  }
}
```

### Option 3: Manual Installation

```bash
# 1. Clone repo
git clone git@github.com:terrylica/cc-skills.git /tmp/cc-skills

# 2. Copy commands
cp /tmp/cc-skills/plugins/itp/commands/go.md ~/.claude/commands/
cp /tmp/cc-skills/plugins/itp/commands/setup.md ~/.claude/commands/

# 3. Copy skills
cp -r /tmp/cc-skills/plugins/itp/skills/* ~/.claude/skills/

# 4. Install dependencies
bash /tmp/cc-skills/plugins/itp/scripts/install-dependencies.sh --install
```

## Platform Support

| Platform          | Status           | Package Manager |
| ----------------- | ---------------- | --------------- |
| macOS (Intel/ARM) | ✅ Supported     | Homebrew        |
| Ubuntu 20.04+     | ✅ Supported     | apt             |
| Debian 11+        | ✅ Supported     | apt             |
| Linuxbrew         | ✅ Supported     | Homebrew        |
| Windows/WSL       | ❌ Not supported | —               |

The install script auto-detects your platform and uses the appropriate package manager.

## Dependencies

> **Recommended**: Install [mise](https://mise.jdx.dev/) first for unified cross-platform tool management.

### Core (Required)

| Tool     | mise (Preferred)          | macOS Fallback      | Ubuntu Fallback                                    |
| -------- | ------------------------- | ------------------- | -------------------------------------------------- |
| uv       | `mise install uv`         | `brew install uv`   | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| gh       | `mise install github-cli` | `brew install gh`   | `sudo apt install gh`                              |
| prettier | —                         | `npm i -g prettier` | `npm i -g prettier`                                |

### ADR Diagrams (Required for Preflight)

| Tool       | mise (Preferred) | macOS Fallback           | Ubuntu Fallback              |
| ---------- | ---------------- | ------------------------ | ---------------------------- |
| cpanm      | —                | `brew install cpanminus` | `sudo apt install cpanminus` |
| graph-easy | —                | `cpanm Graph::Easy`      | `cpanm Graph::Easy`          |

### Code Audit (Optional)

| Tool    | mise (Preferred)       | macOS Fallback         | Ubuntu Fallback        |
| ------- | ---------------------- | ---------------------- | ---------------------- |
| ruff    | `mise install ruff`    | `uv tool install ruff` | `uv tool install ruff` |
| semgrep | `mise install semgrep` | `brew install semgrep` | `pip install semgrep`  |
| jscpd   | —                      | `npm i -g jscpd`       | `npm i -g jscpd`       |

### Release (Optional)

| Tool             | mise (Preferred)       | macOS Fallback                 | Ubuntu Fallback                                     |
| ---------------- | ---------------------- | ------------------------------ | --------------------------------------------------- |
| Node.js          | `mise install node`    | `brew install node`            | via nodesource                                      |
| semantic-release | —                      | `npm i -g semantic-release@25` | `npm i -g semantic-release@25`                      |
| doppler          | `mise install doppler` | `brew install doppler`         | `curl -Ls https://cli.doppler.com/install.sh \| sh` |

## Usage

### Full Workflow (Recommended)

```bash
# 1. Enter Plan Mode (press Shift+Tab twice in Claude Code)
#    Claude will create a plan in ~/.claude/plans/<adjective-noun-verb>.md

# 2. Approve the plan when prompted (ExitPlanMode)

# 3. Execute the approved plan
/itp:go my-feature -b    # Creates branch and executes 4-phase workflow
```

### Quick Commands

```bash
# Execute plan on current branch
/itp:go my-feature

# Execute plan with new feature branch
/itp:go my-feature -b

# Continue in-progress work
/itp:go -c

# Continue with explicit decision
/itp:go -c "use Redis"
```

### Workflow Phases

1. **Preflight**: Creates ADR, design spec, and diagrams
2. **Phase 1**: Implement from design spec with TodoWrite tracking
3. **Phase 2**: Format with Prettier, push to GitHub
4. **Phase 3**: Release with semantic-release (main/master only)

## Included Skills

| Skill                      | Purpose                           | Powered by                                                               |
| -------------------------- | --------------------------------- | ------------------------------------------------------------------------ |
| `implement-plan-preflight` | ADR and design spec creation      | —                                                                        |
| `adr-graph-easy-architect` | ASCII architecture diagrams       | [Graph::Easy](https://metacpan.org/pod/Graph::Easy)                      |
| `graph-easy`               | General ASCII diagram tool        | [Graph::Easy](https://metacpan.org/pod/Graph::Easy)                      |
| `impl-standards`           | Code quality standards            | —                                                                        |
| `adr-code-traceability`    | ADR-to-code linking               | —                                                                        |
| `code-hardcode-audit`      | Magic number detection            | [jscpd](https://github.com/kucherenko/jscpd)                             |
| `semantic-release`         | Versioning automation             | [semantic-release](https://github.com/semantic-release/semantic-release) |
| `pypi-doppler`             | Local PyPI publishing             | [Doppler](https://www.doppler.com/)                                      |
| `mise-configuration`       | Centralized env var configuration | [mise](https://mise.jdx.dev/)                                            |

## CI/CD Strategy

### graph-easy (Local-Only)

ADR diagrams using `graph-easy` are generated **locally** and committed to the repository. This avoids Perl/CPAN dependencies in CI/CD pipelines.

**Workflow:**

1. Developer runs `/itp:go` locally → generates ASCII diagrams
2. Diagrams are committed as part of the ADR/design spec
3. CI/CD validates the committed files (no regeneration needed)

**Why local-only?**

- Perl/cpanm adds 2-3 minutes to CI workflows
- Graph::Easy has no pre-built binaries
- Diagrams change infrequently (only during design phase)

## Troubleshooting

### graph-easy not found

```bash
# Install cpanminus first
brew install cpanminus

# Then install Graph::Easy
cpanm Graph::Easy
```

### Skills not appearing in list

After manual installation, restart Claude Code for skills to be discovered.

### ${CLAUDE_PLUGIN_ROOT} not set

For manual installation, use `~/.claude/` paths. The `${CLAUDE_PLUGIN_ROOT}` variable is only available in plugin context.

### Permission errors with npm

```bash
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'

# Add to your shell config (detects zsh vs bash)
SHELL_RC="$([[ "$SHELL" == */zsh ]] && echo ~/.zshrc || echo ~/.bashrc)"
echo 'export PATH=~/.npm-global/bin:$PATH' >> "$SHELL_RC"
source "$SHELL_RC"
```

## License

MIT
