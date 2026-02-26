# Official Command Structure Patterns

This skill generates commands following **three official patterns** from Anthropic documentation.

## Pattern A: Simple (Context -> Task)

**Best for**: Straightforward tasks with clear input/output
**Example**: Code review, file updates, simple analysis
**Official Reference**: code-review.md

**Structure**:

```markdown
---
allowed-tools: Bash(git diff:*), Bash(git log:*)
description: Purpose description
---

## Context

- Current state: !`bash command`
- Additional data: !`another command`

## Your task

[Clear instructions with numbered steps]
[Success criteria]
```

**When to use**:

- Simple, focused tasks
- Quick analysis or reviews
- Straightforward workflows
- 1-3 bash commands for context

---

## Pattern B: Multi-Phase (Discovery -> Analysis -> Task)

**Best for**: Complex discovery and documentation tasks
**Example**: Codebase analysis, comprehensive audits, system mapping
**Official Reference**: codebase-analysis.md

**Structure**:

```markdown
---
allowed-tools: Bash(find:*), Bash(tree:*), Bash(ls:*), Bash(grep:*), Bash(wc:*), Bash(du:*)
description: Comprehensive purpose
---

# Command Title

## Phase 1: Project Discovery

### Directory Structure

!`find . -type d | sort`

### File Count Analysis

!`find . -type f | wc -l`

## Phase 2: Detailed Analysis

[More discovery commands]
[File references with @]

## Phase 3: Your Task

Based on all discovered information, create:

1. **Deliverable 1**
   - Subsection
   - Details

2. **Deliverable 2**
   - Subsection
   - Details

At the end, write output to [filename].md
```

**When to use**:

- Comprehensive analysis needed
- Multiple discovery phases
- Large amounts of context gathering
- 10+ bash commands for data collection
- Generate detailed documentation files

---

## Pattern C: Agent-Style (Role -> Process -> Guidelines)

**Best for**: Specialized expert roles and coordination
**Example**: Domain experts, orchestrators, specialized advisors
**Official Reference**: openapi-expert.md

**Structure**:

```markdown
---
name: command-name
description: |
  Multi-line description for complex purpose
  explaining specialized role
color: yellow
---

You are a [specialized role] focusing on [domain expertise].

**Core Responsibilities:**

1. **Responsibility Area 1**
   - Specific tasks
   - Expected outputs

2. **Responsibility Area 2**
   - Specific tasks
   - Expected outputs

**Working Process:**

1. [Step 1 in workflow]
2. [Step 2 in workflow]
3. [Step 3 in workflow]

**Important Considerations:**

- [Guideline 1]
- [Guideline 2]
- [Constraint or best practice]

When you encounter [scenario], [action to take].
```

**When to use**:

- Need specialized domain expertise
- Orchestrating complex workflows
- Coordinating multiple sub-processes
- Acting as expert advisor
- Require specific procedural guidelines
