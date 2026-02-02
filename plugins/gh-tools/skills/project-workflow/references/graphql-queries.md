# GraphQL Queries Reference

Advanced GitHub Projects v2 operations via GraphQL API.

## Authentication

All GraphQL queries require a Classic PAT with `project` scope:

```bash
export GH_TOKEN=$(cat ~/.claude/.secrets/gh-token-terrylica)
```

## Query: List User Projects

```bash
gh api graphql -f query='
query($login: String!) {
  user(login: $login) {
    projectsV2(first: 20) {
      nodes {
        id
        number
        title
        url
        closed
        items { totalCount }
        fields(first: 20) {
          nodes {
            ... on ProjectV2Field { id name }
            ... on ProjectV2SingleSelectField { id name options { id name color } }
            ... on ProjectV2IterationField { id name }
          }
        }
      }
    }
  }
}' -f login="terrylica"
```

## Query: Get Project Details

```bash
gh api graphql -f query='
query($login: String!, $number: Int!) {
  user(login: $login) {
    projectV2(number: $number) {
      id
      title
      shortDescription
      readme
      url
      items(first: 100) {
        nodes {
          id
          content {
            ... on Issue {
              number
              title
              state
              url
              labels(first: 10) { nodes { name } }
            }
            ... on PullRequest {
              number
              title
              state
              url
            }
          }
          fieldValues(first: 20) {
            nodes {
              ... on ProjectV2ItemFieldTextValue { text field { ... on ProjectV2Field { name } } }
              ... on ProjectV2ItemFieldNumberValue { number field { ... on ProjectV2Field { name } } }
              ... on ProjectV2ItemFieldDateValue { date field { ... on ProjectV2Field { name } } }
              ... on ProjectV2ItemFieldSingleSelectValue {
                name
                optionId
                field { ... on ProjectV2SingleSelectField { name } }
              }
              ... on ProjectV2ItemFieldIterationValue {
                title
                startDate
                duration
                field { ... on ProjectV2IterationField { name } }
              }
            }
          }
        }
      }
    }
  }
}' -f login="terrylica" -F number=2
```

## Query: Get Project Fields

```bash
gh api graphql -f query='
query($login: String!, $number: Int!) {
  user(login: $login) {
    projectV2(number: $number) {
      fields(first: 50) {
        nodes {
          ... on ProjectV2Field {
            id
            name
            dataType
          }
          ... on ProjectV2SingleSelectField {
            id
            name
            dataType
            options {
              id
              name
              color
              description
            }
          }
          ... on ProjectV2IterationField {
            id
            name
            dataType
            configuration {
              iterations {
                id
                title
                startDate
                duration
              }
            }
          }
        }
      }
    }
  }
}' -f login="terrylica" -F number=2
```

## Mutation: Create Project

```bash
gh api graphql -f query='
mutation($ownerId: ID!, $title: String!) {
  createProjectV2(input: {
    ownerId: $ownerId
    title: $title
  }) {
    projectV2 {
      id
      number
      url
    }
  }
}' -f ownerId="USER_NODE_ID" -f title="New Project"
```

Get user node ID first:

```bash
gh api graphql -f query='query { viewer { id login } }'
```

## Mutation: Add Item to Project

```bash
gh api graphql -f query='
mutation($projectId: ID!, $contentId: ID!) {
  addProjectV2ItemById(input: {
    projectId: $projectId
    contentId: $contentId
  }) {
    item {
      id
    }
  }
}' -f projectId="PROJECT_NODE_ID" -f contentId="ISSUE_NODE_ID"
```

Get issue node ID:

```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) {
      id
      title
    }
  }
}' -f owner="terrylica" -f repo="rangebar-py" -F number=57
```

## Mutation: Update Item Field Value

### Single Select Field

```bash
gh api graphql -f query='
mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
  updateProjectV2ItemFieldValue(input: {
    projectId: $projectId
    itemId: $itemId
    fieldId: $fieldId
    value: { singleSelectOptionId: $optionId }
  }) {
    projectV2Item { id }
  }
}' \
  -f projectId="PVT_xxx" \
  -f itemId="PVTI_xxx" \
  -f fieldId="PVTSSF_xxx" \
  -f optionId="OPTION_ID"
```

### Text Field

```bash
gh api graphql -f query='
mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $text: String!) {
  updateProjectV2ItemFieldValue(input: {
    projectId: $projectId
    itemId: $itemId
    fieldId: $fieldId
    value: { text: $text }
  }) {
    projectV2Item { id }
  }
}' \
  -f projectId="PVT_xxx" \
  -f itemId="PVTI_xxx" \
  -f fieldId="PVTF_xxx" \
  -f text="Root cause: boundary-locked returns"
```

### Date Field

```bash
gh api graphql -f query='
mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $date: Date!) {
  updateProjectV2ItemFieldValue(input: {
    projectId: $projectId
    itemId: $itemId
    fieldId: $fieldId
    value: { date: $date }
  }) {
    projectV2Item { id }
  }
}' \
  -f projectId="PVT_xxx" \
  -f itemId="PVTI_xxx" \
  -f fieldId="PVTF_xxx" \
  -f date="2026-02-15"
```

## Mutation: Create Custom Field

### Single Select Field with Options

```bash
gh api graphql -f query='
mutation($projectId: ID!, $name: String!) {
  createProjectV2Field(input: {
    projectId: $projectId
    dataType: SINGLE_SELECT
    name: $name
    singleSelectOptions: [
      {name: "Validated", color: GREEN, description: "Pattern confirmed"},
      {name: "Invalidated", color: RED, description: "Pattern failed"},
      {name: "Inconclusive", color: YELLOW, description: "Mixed results"},
      {name: "Blocked", color: GRAY, description: "Technical issues"}
    ]
  }) {
    projectV2Field {
      ... on ProjectV2SingleSelectField {
        id
        name
        options { id name color }
      }
    }
  }
}' -f projectId="PVT_xxx" -f name="Verdict"
```

### Text Field

```bash
gh api graphql -f query='
mutation($projectId: ID!, $name: String!) {
  createProjectV2Field(input: {
    projectId: $projectId
    dataType: TEXT
    name: $name
  }) {
    projectV2Field {
      ... on ProjectV2Field { id name }
    }
  }
}' -f projectId="PVT_xxx" -f name="Invalidation-Cause"
```

## Mutation: Delete Item from Project

```bash
gh api graphql -f query='
mutation($projectId: ID!, $itemId: ID!) {
  deleteProjectV2Item(input: {
    projectId: $projectId
    itemId: $itemId
  }) {
    deletedItemId
  }
}' -f projectId="PVT_xxx" -f itemId="PVTI_xxx"
```

## Helper: Get All IDs for a Project

```bash
# Get project ID and field IDs
gh api graphql -f query='
query($login: String!, $number: Int!) {
  user(login: $login) {
    projectV2(number: $number) {
      id
      title
      fields(first: 30) {
        nodes {
          ... on ProjectV2Field { id name dataType }
          ... on ProjectV2SingleSelectField {
            id name dataType
            options { id name }
          }
        }
      }
    }
  }
}' -f login="terrylica" -F number=2 | jq '.'
```

## Error Handling

Common errors and solutions:

| Error           | Cause                   | Solution                     |
| --------------- | ----------------------- | ---------------------------- |
| `NOT_FOUND`     | Wrong project/item ID   | Verify IDs with query first  |
| `FORBIDDEN`     | Missing `project` scope | Use Classic PAT              |
| `UNPROCESSABLE` | Invalid field value     | Check field type and options |

## Related

- [Field Types Reference](./field-types.md)
- [Auto-Link Configuration](./auto-link-config.md)
