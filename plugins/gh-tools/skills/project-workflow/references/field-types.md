# GitHub Projects v2 Field Types Reference

Complete reference for all field types available in GitHub Projects v2.

## Built-in Fields (Read-Only)

These fields are automatically populated from the issue/PR:

| Field                | Description                    |
| -------------------- | ------------------------------ |
| Title                | Issue/PR title                 |
| Assignees            | Assigned users                 |
| Labels               | Applied labels                 |
| Milestone            | Associated milestone           |
| Repository           | Source repository              |
| Linked Pull Requests | PRs linked to issue            |
| Reviewers            | PR reviewers                   |
| Tracks/Tracked by    | Parent/sub-issue relationships |

## Custom Field Types

### Single Select

Dropdown with predefined options. Each option has a name, description, and color.

**Use cases**: Status, Priority, Category, Type

**CLI Creation**:

```bash
gh project field-create <number> --owner <owner> \
  --name "Priority" \
  --data-type SINGLE_SELECT
```

**Adding Options** (via GraphQL):

```bash
gh api graphql -f query='
mutation {
  createProjectV2Field(input: {
    projectId: "PROJECT_ID"
    dataType: SINGLE_SELECT
    name: "Priority"
    singleSelectOptions: [
      {name: "P0 Critical", color: RED, description: "Drop everything"},
      {name: "P1 High", color: ORANGE, description: "This sprint"},
      {name: "P2 Medium", color: YELLOW, description: "Next sprint"},
      {name: "P3 Low", color: GREEN, description: "Backlog"}
    ]
  }) {
    projectV2Field { id name }
  }
}'
```

**Available Colors**: `GRAY`, `RED`, `ORANGE`, `YELLOW`, `GREEN`, `BLUE`, `PURPLE`, `PINK`

### Iteration

Time-boxed periods for sprint planning.

**Use cases**: Sprints, Releases, Quarters

**CLI Creation**:

```bash
gh project field-create <number> --owner <owner> \
  --name "Sprint" \
  --data-type ITERATION
```

**Features**:

- Configurable iteration duration (1-4 weeks)
- Support for breaks between iterations
- Automatic date calculations
- Velocity tracking across iterations

### Date

Calendar date picker.

**Use cases**: Due Date, Start Date, Target Date, Review Date

**CLI Creation**:

```bash
gh project field-create <number> --owner <owner> \
  --name "Due Date" \
  --data-type DATE
```

### Text

Free-form text field.

**Use cases**: Notes, Root Cause, Summary, Links

**CLI Creation**:

```bash
gh project field-create <number> --owner <owner> \
  --name "Notes" \
  --data-type TEXT
```

### Number

Numeric field for quantitative data.

**Use cases**: Story Points, Estimate Hours, T-shirt Size (as numbers)

**CLI Creation**:

```bash
gh project field-create <number> --owner <owner> \
  --name "Story Points" \
  --data-type NUMBER
```

## Research Project Field Templates

### Research-Approach Field

```bash
# Options for categorizing research methodology
# TDA, Microstructure, Cross-threshold, Duration, Regime,
# Cross-asset, Pattern, Autocorrelation, Velocity, Other
```

### Verdict Field

```bash
# Research outcome classification
# Validated - Pattern confirmed with statistical significance
# Invalidated - Pattern failed validation criteria
# Inconclusive - Insufficient data or mixed results
# Blocked - Technical/data issues prevented completion
```

### Common Research Fields Combo

```bash
PROJECT_NUM=2
OWNER=terrylica

# Research-Approach
gh project field-create $PROJECT_NUM --owner $OWNER \
  --name "Research-Approach" --data-type SINGLE_SELECT

# Verdict
gh project field-create $PROJECT_NUM --owner $OWNER \
  --name "Verdict" --data-type SINGLE_SELECT

# Invalidation-Cause
gh project field-create $PROJECT_NUM --owner $OWNER \
  --name "Invalidation-Cause" --data-type TEXT

# Data-Coverage
gh project field-create $PROJECT_NUM --owner $OWNER \
  --name "Data-Coverage" --data-type TEXT
```

## Field Limits

- Maximum custom fields per project: 100
- Maximum options per Single Select: 50
- Maximum iterations: 100
- Field names: 1-256 characters

## Related

- [Auto-Link Configuration](./auto-link-config.md)
- [GraphQL Queries Reference](./graphql-queries.md)
