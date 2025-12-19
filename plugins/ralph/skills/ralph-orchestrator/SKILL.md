---
name: ralph-orchestrator
description: Autonomous AI agent orchestration using the Ralph Wiggum technique - keeps AI in a loop until tasks complete. Use when mentioning "ralph", "ralph wiggum", "orchestrator", "long-running", "autonomous agent", "loop until done", "overnight coding", "evolutionary development", "multi-iteration", "hands-off automation".
allowed-tools: Bash, Read, Write, Glob, Grep
---

# Ralph Orchestrator

## Overview

**IMPORTANT:** This skill teaches about the **Ralph Orchestrator CLI tool** (`ralph run` command), which is a standalone tool separate from the Ralph Plugin for Claude Code (`/ralph:*` commands). If you need to enable autonomous loop mode within Claude Code itself, use the `/ralph:start` command instead.

Ralph Orchestrator is the production implementation of the **Ralph Wiggum technique** - a deceptively simple yet powerful approach to autonomous AI development. At its core, Ralph embodies a single idea: put an AI agent in a loop and let it iterate until the task is done.

The technique was created by [Geoffrey Huntley](https://ghuntley.com/ralph/) and is named after Ralph Wiggum's famous quote: "Me fail English? That's unpossible!" Ralph embraces **deterministic failure in an undeterministic world** - it fails predictably but in ways you can address.

As Huntley defines it, Ralph is fundamentally a Bash loop:

```bash
while :; do cat PROMPT.md | claude ; done
```

Ralph Orchestrator takes this elegantly simple concept and wraps it with production-grade features: checkpointing, metrics, error recovery, cost management, and multi-agent support.

### The Evolutionary Power

What makes Ralph transformative is its evolutionary nature. Each iteration:

1. **Reads** the current state (PROMPT.md and workspace)
2. **Executes** the AI agent with full context
3. **Modifies** files, runs tests, makes commits
4. **Checkpoints** progress via Git
5. **Repeats** until limits are reached

This creates an **emergent development process** where complex systems evolve from simple specifications. The AI doesn't need to solve everything at once - it iterates, learns from failures, and progressively builds toward the goal.

## When to Use Ralph

### Ideal Use Cases

| Scenario                | Why Ralph Excels                               |
| ----------------------- | ---------------------------------------------- |
| **Greenfield projects** | Start with a spec, wake up to working code     |
| **Large refactoring**   | Systematic, exhaustive changes across codebase |
| **Test generation**     | Iteratively build comprehensive test suites    |
| **Documentation**       | Generate docs that evolve with understanding   |
| **Bug hunts**           | Persistent debugging across multiple attempts  |
| **API implementations** | Build endpoints one by one with verification   |
| **Data pipelines**      | Complex transformations with validation        |

### When NOT to Use Ralph

- **Quick one-off tasks** - Use Claude Code directly
- **Interactive development** - Pair programming with instant feedback
- **Learning new concepts** - Better to work alongside AI
- **Sensitive operations** - Requires human oversight

### Decision Framework

```
Is the task well-defined with clear success criteria?
├── No  → Refine spec first, then consider Ralph
└── Yes → Does it require multiple iterations/steps?
          ├── No  → Use Claude Code directly
          └── Yes → Will you be away (sleeping, meeting, etc.)?
                    ├── No  → Claude Code may be faster for active work
                    └── Yes → Ralph is perfect - set it and forget it
```

## Quick Start

### Installation

```bash
# Clone and install
git clone https://github.com/mikeyobrien/ralph-orchestrator.git
cd ralph-orchestrator
uv sync

# Or install globally
pip install ralph-orchestrator
```

### Basic Usage

```bash
# Initialize a new project
ralph init

# Edit PROMPT.md with your task
# Then run
ralph run

# Or use inline prompt
ralph run -p "Build a REST API for user management with tests"
```

### Key Commands

| Command               | Description                                     |
| --------------------- | ----------------------------------------------- |
| `ralph init`          | Initialize project with PROMPT.md and ralph.yml |
| `ralph run`           | Start the orchestration loop                    |
| `ralph status`        | Check current progress and metrics              |
| `ralph clean`         | Clean workspace and reset state                 |
| `ralph run --dry-run` | Test without executing                          |

## Writing Effective Prompts

The PROMPT.md file is your contract with Ralph. A well-crafted prompt dramatically improves results.

### Prompt Template

```markdown
# Task: [Clear, Specific Name]

## Objective

[1-2 sentences describing the end goal]

## Context

[Background the AI needs to understand the task]

## Requirements

1. [Specific, measurable requirement]
2. [Another requirement]
3. [...]

## Constraints

- [Technical limitation]
- [Resource constraint]
- [Style/convention requirement]

## Success Criteria

The task is complete when:

- [ ] [Verifiable outcome 1]
- [ ] [Verifiable outcome 2]
- [ ] [Verifiable outcome 3]

## Progress Tracking

<!-- Ralph updates this section -->

- Status: Not Started
- Current: N/A
- Completed: None

---

The orchestrator will continue iterations until limits are reached.
```

### Prompt Best Practices

**Be Specific, Not Vague**

```markdown
# Bad

Build a website

# Good

Build a Flask web app with:

- User registration (email + password)
- SQLite database using SQLAlchemy
- Bootstrap 5 UI with responsive design
- Unit tests with pytest (>80% coverage)
```

**Include Examples**

```markdown
## Example API Response

GET /users/123
{
"id": 123,
"email": "user@example.com",
"created_at": "2025-01-15T10:30:00Z"
}
```

**Define Clear Boundaries**

```markdown
## Constraints

- Python 3.11+ only
- No external API calls
- Must work offline
- Follow PEP 8 style guide
- All functions require type hints
```

## CLI Reference

### Core Options

```bash
ralph [OPTIONS] [COMMAND]

Commands:
  init      Initialize a new Ralph project
  run       Run the orchestrator (default)
  status    Show current status and metrics
  clean     Clean up workspace
  prompt    Generate structured prompt from ideas

Options:
  -c, --config FILE           Configuration file (ralph.yml)
  -a, --agent TYPE            Agent: claude, q, gemini, acp, auto
  -P, --prompt-file FILE      Prompt file path (default: PROMPT.md)
  -p, --prompt-text TEXT      Inline prompt (overrides file)
  -i, --max-iterations N      Maximum iterations (default: 100)
  -t, --max-runtime SECONDS   Maximum runtime (default: 14400)
  -v, --verbose               Enable verbose output
  -d, --dry-run               Test mode without execution
```

### Cost and Resource Limits

```bash
--max-tokens N          Maximum total tokens (default: 1000000)
--max-cost DOLLARS      Maximum cost in USD (default: 50.0)
--checkpoint-interval N Git checkpoint frequency (default: 5)
--retry-delay SECONDS   Retry delay on errors (default: 2)
--no-git                Disable git checkpointing
--no-archive            Disable prompt archiving
--no-metrics            Disable metrics collection
```

### ACP (Agent Client Protocol) Options

```bash
--acp-agent COMMAND         ACP agent command (default: gemini)
--acp-permission-mode MODE  Permission handling:
                            - auto_approve: Approve all (CI/CD)
                            - deny_all: Deny all (testing)
                            - allowlist: Pattern-based approval
                            - interactive: Manual approval
```

## Cost and Time Expectations

### Realistic Estimates by Task Type

| Task Type        | Iterations | Time      | Cost (Claude) | Cost (Q/Gemini) |
| ---------------- | ---------- | --------- | ------------- | --------------- |
| Simple script    | 5-10       | 2-5 min   | $0.05-0.10    | $0.01-0.02      |
| Web API          | 20-40      | 10-20 min | $0.50-1.50    | $0.10-0.30      |
| Full application | 50-100     | 30-60 min | $2-10         | $0.50-2         |
| Large refactor   | 100+       | 1-4 hours | $5-50         | $1-10           |
| Documentation    | 15-30      | 5-15 min  | $0.30-0.80    | $0.05-0.15      |

### Cost Management Strategies

```bash
# Start conservative
ralph run --max-cost 5.0 --max-iterations 20

# Scale up after validation
ralph run --max-cost 50.0 --max-iterations 100

# Use tiered agents
ralph run -a q --max-cost 2.0          # Research phase
ralph run -a claude --max-cost 20.0     # Implementation
ralph run -a q --max-cost 2.0          # Testing phase
```

### ROI Perspective

The real measure is not API cost but **developer time saved**:

| Scenario      | Manual Estimate | Ralph Cost | Time Saved | ROI    |
| ------------- | --------------- | ---------- | ---------- | ------ |
| REST API      | 8 hours ($400)  | $5         | 7.5 hours  | 7,900% |
| Test suite    | 4 hours ($200)  | $3         | 3.8 hours  | 6,567% |
| Documentation | 3 hours ($150)  | $2         | 2.9 hours  | 7,400% |

## Real-World Success Stories

### Y Combinator Hackathon (2024)

**Task**: Build multiple products for hackathon submission overnight
**Approach**: Multiple Ralph loops running in parallel
**Result**: **6 repositories shipped** in a single session
**Key Insight**: Parallel execution multiplies productivity exponentially

### Contract MVP ($50K to $297)

**Task**: Build complete MVP for client contract
**Traditional Estimate**: $50,000 outsourcing cost
**Actual Cost**: **$297** in API credits
**Outcome**: Successful delivery with 16,835% cost savings
**Key Insight**: Detailed specification + iterative refinement = quality results

### CURSED Language Compiler

**Task**: Create a complete esoteric programming language
**Duration**: 3+ months of continuous iteration
**Result**: Working language and compiler that **the AI invented and programs in**
**Key Insight**: Long-running loops can achieve complex emergent behavior beyond training data

## Configuration (ralph.yml)

```yaml
# Ralph Orchestrator Configuration
agent: auto # claude, q, gemini, acp, auto
prompt_file: PROMPT.md # Task description file
max_iterations: 100 # Maximum loop iterations
max_runtime: 14400 # 4 hours in seconds
verbose: false # Enable verbose output

# Per-agent settings
adapters:
  claude:
    enabled: true
    timeout: 300 # 5 minutes per iteration
  q:
    enabled: true
    timeout: 300
  gemini:
    enabled: true
    timeout: 300
  acp:
    enabled: true
    timeout: 300
    tool_permissions:
      agent_command: gemini
      permission_mode: auto_approve
```

## Agent Selection Guide

| Agent      | Best For                         | Context Window | Speed  | Cost   |
| ---------- | -------------------------------- | -------------- | ------ | ------ |
| **Claude** | Complex logic, nuanced tasks     | 200K tokens    | Medium | Higher |
| **Q Chat** | AWS integrations, quick tasks    | Variable       | Fast   | Lower  |
| **Gemini** | Large codebases, research        | 2M tokens      | Medium | Lower  |
| **ACP**    | Custom agents, specialized tools | Varies         | Varies | Varies |

### Selection Strategy

```bash
# Complex task needing understanding
ralph run -a claude

# Large codebase, lots of context
ralph run -a gemini

# Quick iterations, cost-sensitive
ralph run -a q

# Overnight run with fallback
ralph run -a auto  # Auto-detects best available
```

## The Loop Philosophy

Ralph succeeds because it embraces fundamental principles:

1. **Simplicity over complexity** - The core is just a loop
2. **Persistence over perfection** - Keep trying until it works
3. **Deterministic failure** - Fail in predictable, fixable ways
4. **Git as memory** - Perfect checkpoint and recovery
5. **Human specification, AI implementation** - Clear separation of concerns

As Geoffrey Huntley noted: "It's better to fail predictably than succeed unpredictably."

## References

- [Prompt Templates](./references/prompt-templates.md) - 10+ battle-tested PROMPT.md templates
- [Troubleshooting](./references/troubleshooting.md) - Common issues and solutions

## External Resources

- [Ralph Orchestrator GitHub](https://github.com/mikeyobrien/ralph-orchestrator)
- [Geoffrey Huntley's Original Article](https://ghuntley.com/ralph/)
- [Claude Code Plugin Guide](https://paddo.dev/blog/ralph-wiggum-autonomous-loops/)
- [Full Documentation](https://mikeyobrien.github.io/ralph-orchestrator/)
