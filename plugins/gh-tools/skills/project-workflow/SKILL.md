---
name: project-workflow
description: GitHub Issues + Projects v2 integration workflow. TRIGGERS - project create, link issue to project, project status, auto-link issues.
allowed-tools: Read, Bash, Grep, Glob, Write
---

# GitHub Projects v2 Workflow Skill

Integrate GitHub Issues with Projects v2 for organized tracking. Create projects, link issues automatically by labels, manage custom fields, and sync status across issue lifecycle.

## Critical Principle: Issues Are the Source of Truth

**GitHub Issues = Primary content repository with full version tracking.**
**GitHub Projects v2 = Personal visual tracker (no version history).**

### Why Issues First

| Feature             | Issues                  | Projects v2     | Discussions           |
| ------------------- | ----------------------- | --------------- | --------------------- |
| **Edit history**    | Full diff on every edit | None            | "Edited" badge only   |
| **Timeline**        | All changes logged      | None            | None                  |
| **Comment history** | Full diff               | N/A             | "Edited" badge only   |
| **Audit log**       | Enterprise              | Enterprise only | Team discussions only |
| **Searchable**      | Full-text + filters     | Limited         | Full-text             |
| **API history**     | `timelineItems` GraphQL | None            | None                  |

### Workflow Principle

```
┌─────────────────────────────────────────────────────────────┐
│                    CONTENT WORKFLOW                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   1. WRITE in Issues (source of truth)                       │
│      - Research findings, analysis, conclusions              │
│      - Full edit history preserved                           │
│      - Comments track evolving understanding                 │
│      - Labels categorize and filter                          │
│                                                              │
│   2. TRACK in Projects v2 (personal dashboard)               │
│      - Visual kanban/table/roadmap views                     │
│      - Status, Priority, Iteration fields                    │
│      - Cross-repo organization                               │
│      - NO content here - just links to Issues                │
│                                                              │
│   3. LINK bidirectionally                                    │
│      - Issues reference project for context                  │
│      - Projects link to Issues for content                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### What NOT to Put in Projects

- Research findings (put in Issue body)
- Analysis details (put in Issue comments)
- Conclusions (put in Issue body)
- Code snippets (put in Issue body with fenced blocks)

Projects v2 custom fields (Text, Number) have **no edit history**. If you update a field value, the previous value is lost forever.

## When to Use This Skill

Use this skill when:

- Creating GitHub Projects v2 boards for visual organization
- Linking issues to projects (manually or automatically by labels)
- Managing project custom fields (Status, Priority, Iteration, etc.)
- Setting up research-specific project tracking
- Automating issue-to-project workflows

**Remember**: Write content in Issues first, then link to Projects for tracking.

## Invocation

**Slash command**: `/gh-tools:project-workflow`

**Natural language triggers**:

- "Create a GitHub project for..."
- "Link this issue to a project"
- "Set up project tracking for research"
- "Add issue to project board"
- "Configure project fields"

## Core Concepts

### GitHub Projects v2 Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    GitHub Project v2                     │
├─────────────────────────────────────────────────────────┤
│  Views: Table | Board | Roadmap                         │
├─────────────────────────────────────────────────────────┤
│  Built-in Fields:                                       │
│  - Title, Assignees, Labels, Milestone, Repository      │
├─────────────────────────────────────────────────────────┤
│  Custom Fields:                                         │
│  - Status (Single Select): Todo/In Progress/Done        │
│  - Priority (Single Select): P0/P1/P2/P3                │
│  - Iteration: Sprint-based time boxes                   │
│  - Date: Due date, Start date                           │
│  - Text/Number: Free-form data                          │
├─────────────────────────────────────────────────────────┤
│  Items: Issues | Pull Requests | Draft Issues           │
└─────────────────────────────────────────────────────────┘
```

### Token Requirements

**CRITICAL**: GitHub Projects v2 API requires **Classic PAT** with `project` scope.

Fine-grained PATs do NOT support Projects v2 API. See: [GitHub CLI Issue #6680](https://github.com/cli/cli/issues/6680)

```bash
# Check current token type
cat ~/.claude/.secrets/gh-token-terrylica | head -c 10
# ghp_ = Classic PAT (supports Projects)
# github_pat_ = Fine-grained (NO Projects support)
```

## Commands Reference

### Project Operations

```bash
# List projects
gh project list --owner <owner>

# Create project
gh project create --owner <owner> --title "Project Name"

# Delete project
gh project delete <number> --owner <owner>

# View project details
gh project view <number> --owner <owner>
```

### Item Operations

```bash
# Add issue to project
gh project item-add <project-number> --owner <owner> \
  --url https://github.com/<owner>/<repo>/issues/<number>

# List project items
gh project item-list <project-number> --owner <owner>

# Remove item from project
gh project item-delete <project-number> --owner <owner> --id <item-id>
```

### Field Operations

```bash
# List project fields
gh project field-list <project-number> --owner <owner>

# Create custom field
gh project field-create <project-number> --owner <owner> \
  --name "Priority" --data-type SINGLE_SELECT

# Edit item field value
gh project item-edit --project-id <project-id> --id <item-id> \
  --field-id <field-id> --single-select-option-id <option-id>
```

## Supported Field Types

### Standard Fields

| Field      | Type          | Options                                 | Use Case          |
| ---------- | ------------- | --------------------------------------- | ----------------- |
| Status     | Single Select | Todo, In Progress, Done                 | Kanban workflow   |
| Priority   | Single Select | P0 Critical, P1 High, P2 Medium, P3 Low | Triage            |
| Iteration  | Iteration     | Sprint 1, Sprint 2, ...                 | Velocity planning |
| Due Date   | Date          | Calendar picker                         | Deadlines         |
| Start Date | Date          | Calendar picker                         | Timeline views    |

### Research-Specific Fields

| Field              | Type          | Options                                                | Use Case                         |
| ------------------ | ------------- | ------------------------------------------------------ | -------------------------------- |
| Research-Approach  | Single Select | TDA, Microstructure, Cross-threshold, Duration, Regime | Categorize research method       |
| Verdict            | Single Select | Validated, Invalidated, Inconclusive, Blocked          | Research outcome                 |
| Invalidation-Cause | Text          | Free text                                              | Root cause documentation         |
| Data-Coverage      | Text          | Free text                                              | Symbols, thresholds, date ranges |

## Auto-Linking Configuration

### Option 1: Label Prefix Convention

Labels prefixed with `project:` automatically link to matching projects:

| Label              | Project            |
| ------------------ | ------------------ |
| `project:research` | Research Findings  |
| `project:dev`      | Active Development |
| `project:bugs`     | Bug Triage         |

### Option 2: Config File Mapping

Create `.github/project-links.json` in repository:

```json
{
  "mappings": [
    {
      "labels": ["research:regime", "research:patterns", "research:complete"],
      "project": "Research Findings: Range Bar Patterns",
      "projectNumber": 2
    },
    {
      "labels": ["bug", "enhancement"],
      "project": "rangebar-py: Active Development",
      "projectNumber": 3
    }
  ],
  "owner": "terrylica"
}
```

## Workflow Examples

### 1. Create Research Project with Custom Fields

```bash
# Create project
gh project create --owner terrylica --title "Research Findings: Range Bar Patterns"

# Get project number from output, then add fields
gh project field-create 2 --owner terrylica \
  --name "Research-Approach" --data-type SINGLE_SELECT

gh project field-create 2 --owner terrylica \
  --name "Verdict" --data-type SINGLE_SELECT

gh project field-create 2 --owner terrylica \
  --name "Invalidation-Cause" --data-type TEXT

gh project field-create 2 --owner terrylica \
  --name "Data-Coverage" --data-type TEXT
```

### 2. Bulk Link Issues by Label

```bash
# Get all issues with research labels
gh issue list --repo terrylica/rangebar-py \
  --label "research:regime" --json number,url --jq '.[].url' | \
while read url; do
  gh project item-add 2 --owner terrylica --url "$url"
done
```

### 3. Query Project Items with GraphQL

```bash
gh api graphql -f query='
  query {
    user(login: "terrylica") {
      projectV2(number: 2) {
        items(first: 100) {
          nodes {
            content {
              ... on Issue {
                title
                number
                state
              }
            }
            fieldValues(first: 10) {
              nodes {
                ... on ProjectV2ItemFieldSingleSelectValue {
                  name
                  field { ... on ProjectV2SingleSelectField { name } }
                }
              }
            }
          }
        }
      }
    }
  }
'
```

## Hook Integration

### Auto-Link on Issue Create (PostToolUse)

When an issue is created with matching labels, automatically add to project:

```typescript
// hooks/posttooluse-project-autolink.ts
if (tool === "Bash" && output.includes("gh issue create")) {
  const issueUrl = extractIssueUrl(output);
  const labels = extractLabels(command);
  const project = findMatchingProject(labels);
  if (project) {
    exec(
      `gh project item-add ${project.number} --owner ${project.owner} --url ${issueUrl}`,
    );
  }
}
```

### Status Sync (Issue State → Project Status)

Sync issue open/closed state with project Status field:

```typescript
// When issue closed → set Status to "Done"
// When issue reopened → set Status to "In Progress"
```

## Current Projects (terrylica)

| #   | Project                               | Items | URL                                             |
| --- | ------------------------------------- | ----- | ----------------------------------------------- |
| 2   | Research Findings: Range Bar Patterns | 5     | <https://github.com/users/terrylica/projects/2> |
| 3   | rangebar-py: Active Development       | 3     | <https://github.com/users/terrylica/projects/3> |
| 4   | cc-skills: Plugin Development         | 1     | <https://github.com/users/terrylica/projects/4> |

## Troubleshooting

### "Resource not accessible by personal access token"

**Cause**: Using Fine-grained PAT instead of Classic PAT.

**Fix**: Switch to Classic PAT:

```bash
cd ~/.claude/.secrets
ln -sf gh-token-terrylica-classic gh-token-terrylica
```

### "Project not found"

**Cause**: Project number vs project ID confusion.

**Fix**: Use `gh project list --owner <owner>` to get correct project numbers.

### GraphQL mutations failing

**Cause**: Need project ID (not number) for GraphQL operations.

**Fix**: Get project ID first:

```bash
gh project view <number> --owner <owner> --format json | jq '.id'
```

## Related Documentation

- [GitHub Projects Best Practices](https://docs.github.com/en/issues/planning-and-tracking-with-projects/learning-about-projects/best-practices-for-projects)
- [Understanding Fields](https://docs.github.com/en/issues/planning-and-tracking-with-projects/understanding-fields)
- [gh-tools Issue Create Skill](./issue-create/SKILL.md)
- [cc-skills Issue #20: gh-tools Extension Plan](https://github.com/terrylica/cc-skills/issues/20)

## References

- [Field Types Reference](./references/field-types.md)
- [Auto-Link Configuration](./references/auto-link-config.md)
- [GraphQL Queries Reference](./references/graphql-queries.md)
