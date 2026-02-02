# Auto-Link Configuration Reference

Automatically link issues to projects based on labels, milestones, or repository.

## Configuration File

Create `.github/project-links.json` in your repository:

```json
{
  "version": "1.0",
  "owner": "terrylica",
  "mappings": [
    {
      "name": "Research Issues",
      "projectNumber": 2,
      "projectTitle": "Research Findings: Range Bar Patterns",
      "triggers": {
        "labels": [
          "research:regime",
          "research:patterns",
          "research:complete",
          "negative-finding"
        ],
        "labelPrefixes": ["research:"],
        "milestones": ["Research Phase 1", "Research Phase 2"]
      },
      "defaultFields": {
        "Status": "Todo"
      }
    },
    {
      "name": "Active Development",
      "projectNumber": 3,
      "projectTitle": "rangebar-py: Active Development",
      "triggers": {
        "labels": ["bug", "enhancement"],
        "repositories": ["terrylica/rangebar-py"]
      },
      "defaultFields": {
        "Status": "Todo",
        "Priority": "P2 Medium"
      }
    },
    {
      "name": "Plugin Development",
      "projectNumber": 4,
      "projectTitle": "cc-skills: Plugin Development",
      "triggers": {
        "repositories": ["terrylica/cc-skills"],
        "labels": ["gh-tools", "new-skill", "enhancement"]
      }
    }
  ],
  "settings": {
    "skipDuplicates": true,
    "logFile": "~/.claude/logs/project-autolink.jsonl"
  }
}
```

## Trigger Types

### Label-Based

Match issues with specific labels:

```json
{
  "triggers": {
    "labels": ["bug", "enhancement", "documentation"]
  }
}
```

### Label Prefix

Match issues with labels starting with a prefix:

```json
{
  "triggers": {
    "labelPrefixes": ["research:", "project:", "team:"]
  }
}
```

### Milestone-Based

Match issues assigned to specific milestones:

```json
{
  "triggers": {
    "milestones": ["v1.0", "Q1 2026", "Research Phase 1"]
  }
}
```

### Repository-Based

Match all issues from specific repositories:

```json
{
  "triggers": {
    "repositories": ["terrylica/rangebar-py", "terrylica/cc-skills"]
  }
}
```

### Combined Triggers (AND Logic)

All conditions must match:

```json
{
  "triggers": {
    "labels": ["bug"],
    "repositories": ["terrylica/rangebar-py"]
  },
  "requireAll": true
}
```

### Combined Triggers (OR Logic)

Any condition matches (default):

```json
{
  "triggers": {
    "labels": ["bug", "enhancement"],
    "milestones": ["v1.0"]
  },
  "requireAll": false
}
```

## Default Field Values

Set initial field values when linking:

```json
{
  "defaultFields": {
    "Status": "Todo",
    "Priority": "P2 Medium",
    "Iteration": "Current Sprint"
  }
}
```

## Label Convention Pattern

Use labels with `project:` prefix for self-documenting auto-linking:

| Label              | Auto-links to                   |
| ------------------ | ------------------------------- |
| `project:research` | Project #2 (Research Findings)  |
| `project:dev`      | Project #3 (Active Development) |
| `project:plugins`  | Project #4 (Plugin Development) |

## Hook Implementation

### PostToolUse Hook (TypeScript)

```typescript
// ~/.claude/hooks/posttooluse-project-autolink.ts
import { execSync } from "child_process";
import { readFileSync, existsSync } from "fs";

interface ProjectMapping {
  projectNumber: number;
  triggers: {
    labels?: string[];
    labelPrefixes?: string[];
    milestones?: string[];
    repositories?: string[];
  };
  defaultFields?: Record<string, string>;
}

interface Config {
  owner: string;
  mappings: ProjectMapping[];
}

export function onPostToolUse(tool: string, output: string, command: string) {
  if (tool !== "Bash") return;
  if (!output.includes("github.com") || !output.includes("/issues/")) return;

  // Extract issue URL from gh issue create output
  const urlMatch = output.match(
    /https:\/\/github\.com\/([^\/]+)\/([^\/]+)\/issues\/(\d+)/,
  );
  if (!urlMatch) return;

  const [, owner, repo, issueNum] = urlMatch;
  const issueUrl = urlMatch[0];

  // Load config
  const configPath = `${process.cwd()}/.github/project-links.json`;
  if (!existsSync(configPath)) return;

  const config: Config = JSON.parse(readFileSync(configPath, "utf-8"));

  // Get issue labels
  const labelsOutput = execSync(
    `gh issue view ${issueNum} --repo ${owner}/${repo} --json labels --jq '.labels[].name'`,
    { encoding: "utf-8" },
  );
  const labels = labelsOutput.trim().split("\n").filter(Boolean);

  // Find matching projects
  for (const mapping of config.mappings) {
    const matches = checkTriggers(mapping.triggers, labels, `${owner}/${repo}`);
    if (matches) {
      execSync(
        `gh project item-add ${mapping.projectNumber} --owner ${config.owner} --url ${issueUrl}`,
      );
      console.log(`Linked issue to project #${mapping.projectNumber}`);
    }
  }
}

function checkTriggers(
  triggers: ProjectMapping["triggers"],
  labels: string[],
  repo: string,
): boolean {
  if (triggers.labels?.some((l) => labels.includes(l))) return true;
  if (triggers.labelPrefixes?.some((p) => labels.some((l) => l.startsWith(p))))
    return true;
  if (triggers.repositories?.includes(repo)) return true;
  return false;
}
```

## Manual Bulk Linking

Link existing issues to projects:

```bash
# Link all issues with research labels to project #2
gh issue list --repo terrylica/rangebar-py \
  --label "research:regime" \
  --state all \
  --json url \
  --jq '.[].url' | \
while read url; do
  gh project item-add 2 --owner terrylica --url "$url"
  echo "Linked: $url"
done
```

## Verification

Check which issues are linked to a project:

```bash
gh project item-list 2 --owner terrylica --format json | \
  jq '.items[] | {title: .title, url: .content.url, status: .status}'
```

## Related

- [Field Types Reference](./field-types.md)
- [GraphQL Queries Reference](./graphql-queries.md)
