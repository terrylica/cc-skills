# Comprehensive Naming Convention

## Command File Naming Rules

All slash command files MUST follow kebab-case convention:

**Format**: `[verb]-[noun].md`, `[noun]-[verb].md`, or `[domain]-[action].md`

**Rules**:

1. **Case**: Lowercase only with hyphens as separators
2. **Length**: 2-4 words maximum
3. **Characters**: Only `[a-z0-9-]` allowed (letters, numbers, hyphens)
4. **Start/End**: Must begin and end with letter or number (not hyphen)
5. **No**: Spaces, underscores, camelCase, TitleCase, or special characters

---

## Conversion Algorithm

**User Input** -> **Command Name**

```
Input: "Analyze customer feedback and generate insights"
|
1. Extract action: "analyze"
2. Extract target: "feedback"
3. Combine: "analyze-feedback"
4. Validate: Matches [a-z0-9-]+ pattern
5. Output: analyze-feedback.md
```

**More Examples**:

- "Review pull requests" -> `pr-review.md` or `review-pr.md`
- "Generate API documentation" -> `api-document.md` or `document-api.md`
- "Update README files" -> `update-readme.md` or `readme-update.md`
- "Audit security compliance" -> `security-audit.md` or `compliance-audit.md`
- "Research market trends" -> `research-market.md` or `market-research.md`
- "Analyze code quality" -> `code-analyze.md` or `analyze-code.md`

---

## Official Examples (From Anthropic Docs)

**Correct**:

- `code-review.md` (verb-noun)
- `codebase-analysis.md` (noun-noun compound)
- `update-claude-md.md` (verb-noun-qualifier)
- `openapi-expert.md` (domain-role)

**Incorrect**:

- `code_review.md` (snake_case - wrong)
- `CodeReview.md` (PascalCase - wrong)
- `codeReview.md` (camelCase - wrong)
- `review.md` (too vague - needs target)
- `analyze-customer-feedback-data.md` (too long - >4 words)
