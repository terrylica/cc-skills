# Ralph Tools Plugin

Autonomous AI orchestration using the Ralph Wiggum technique - keeps AI in a loop until tasks complete.

## Features

- Long-running AI automation with evolutionary development
- Production-grade orchestration with checkpointing and metrics
- Multi-agent support (Claude, Q Chat, Gemini, ACP)
- Cost management and resource limits
- Git-based progress checkpointing

## Skills

### ralph-orchestrator

Teaches users how to invoke Ralph Orchestrator effectively for:

- Greenfield projects (wake up to working code)
- Large refactoring (systematic changes across codebase)
- Test generation (comprehensive test suites)
- Documentation (evolving docs)
- Bug hunts (persistent debugging)

## Usage

### Invoke the Skill

```bash
# In Claude Code CLI
"I want to use ralph for overnight coding"
"How do I set up ralph orchestrator for my project?"
"Help me write a PROMPT.md for ralph"
```

### Quick Start with Ralph

```bash
# Initialize project
ralph init

# Edit PROMPT.md with your task
# Then run
ralph run

# Or inline prompt
ralph run -p "Build a REST API for user management"
```

## Files

```
ralph-tools/
├── README.md                                    # This file
├── ralph.yml                                    # Ralph configuration
├── PROMPT.md                                    # Task used to create this plugin
└── skills/
    └── ralph-orchestrator/
        ├── SKILL.md                             # Skill definition
        └── references/
            ├── prompt-templates.md              # 12 battle-tested templates
            └── troubleshooting.md               # Common issues and solutions
```

## Requirements

- Ralph Orchestrator installed (`ralph` command available)
- Installation: `uv tool install -e ~/eon/ralph-orchestrator/`

## Related

- [Ralph Orchestrator GitHub](https://github.com/mikeyobrien/ralph-orchestrator)
- [Geoffrey Huntley's Original Article](https://ghuntley.com/ralph/)
