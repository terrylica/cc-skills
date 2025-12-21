---
status: accepted
date: 2025-12-06
decision-maker: Terry Li
consulted: [Plan-Agent]
research-method: single-agent
clarification-iterations: 4
perspectives: [ProviderToOtherComponents, EcosystemArtifact]
---

# ADR: Documentation Links in Release Notes

**Design Spec**: [Implementation Spec](/docs/design/2025-12-06-release-notes-adr-linking/spec.md)

## Context and Problem Statement

When semantic-release creates a GitHub release, the release notes only contain the commit-based changelog. Users want to see which Architecture Decision Records (ADRs) and Design Specs were involved since the last release, with clickable links.

This improves release transparency by connecting code changes to their architectural context, making it easier to understand the "why" behind releases.

### Before/After

**Before**: Release notes only contain commit-based changelog

```
               ⏮️ Before / ⏭️ After: Release Notes Enhancement

┌−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┐
╎ Before:                                                                     ╎
╎                                                                             ╎
╎ ┌──────────────────┐     ┌─────────────────────────┐     ┌────────────────┐ ╎
╎ │ semantic-release │     │ release-notes-generator │     │ GitHub Release │ ╎
╎ │                  │ ──> │     (commits only)      │ ──> │ (no ADR links) │ ╎
╎ └──────────────────┘     └─────────────────────────┘     └────────────────┘ ╎
╎                                                                             ╎
└−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏮️ Before / ⏭️ After: Release Notes Enhancement"; flow: east; }

( Before:
  [sr] { label: "semantic-release"; }
  [notes] { label: "release-notes-generator\n(commits only)"; }
  [gh] { label: "GitHub Release\n(no ADR links)"; }
)

[sr] -> [notes] -> [gh]
```

</details>

**After**: Release notes include ADR/Design Spec links via exec plugin

```
⏭️ After: Release Notes with ADR Links

┌−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┐
╎ After:                                                                                                                    ╎
╎                                                                                                                           ╎
╎ ┌─────────────────────────┐     ┌────────────────────────┐     ┌────────────────────────┐            ┌──────────────────┐ ╎
╎ │    semantic-release     │     │ @semantic-release/exec │     │ generate-doc-notes.mjs │  appends   │  GitHub Release  │ ╎
╎ │                         │ ──> │    generateNotesCmd    │ ──> │  (git diff + commits)  │ ─────────> │ (with ADR links) │ ╎
╎ └─────────────────────────┘     └────────────────────────┘     └────────────────────────┘            └──────────────────┘ ╎
╎   │                                                                                                    ∧                  ╎
╎   │                                                                                                    │                  ╎
╎   ∨                                                                                                    │                  ╎
╎ ┌─────────────────────────┐                                                                            │                  ╎
╎ │ release-notes-generator │ ───────────────────────────────────────────────────────────────────────────┘                  ╎
╎ └─────────────────────────┘                                                                                               ╎
╎                                                                                                                           ╎
└−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏭️ After: Release Notes with ADR Links"; flow: east; }

( After:
  [sr] { label: "semantic-release"; }
  [notes] { label: "release-notes-generator"; }
  [exec] { label: "@semantic-release/exec\ngenerateNotesCmd"; }
  [script] { label: "generate-doc-notes.mjs\n(git diff + commits)"; }
  [gh] { label: "GitHub Release\n(with ADR links)"; }
)

[sr] -> [notes]
[sr] -> [exec] -> [script]
[notes] -> [gh]
[script] -- appends --> [gh]
```

</details>

## Research Summary

| Agent Perspective | Key Finding                                                                   | Confidence |
| ----------------- | ----------------------------------------------------------------------------- | ---------- |
| Plan-Agent        | Union approach (git diff + commit parsing) provides best coverage             | High       |
| Plan-Agent        | Full HTTPS URLs required for GitHub release pages (relative links don't work) | High       |
| Plan-Agent        | Script should be shareable via `${CLAUDE_PLUGIN_ROOT}` path                   | High       |

## Decision Log

| Decision Area    | Options Evaluated                                 | Chosen          | Rationale                                                        |
| ---------------- | ------------------------------------------------- | --------------- | ---------------------------------------------------------------- |
| Detection Method | git diff only, commit parsing only, union of both | Union of both   | Catches both file changes and explicit ADR references in commits |
| Link Format      | Relative paths, full HTTPS URLs                   | Full HTTPS URLs | GitHub release pages require absolute URLs                       |
| Placement        | Top of release notes, after changelog             | After changelog | Less intrusive, changelog is primary content                     |
| Artifacts        | ADRs only, Design Specs only, both                | Both            | Complete architectural context                                   |

### Trade-offs Accepted

| Trade-off                        | Choice          | Accepted Cost                                       |
| -------------------------------- | --------------- | --------------------------------------------------- |
| Simplicity vs Completeness       | Union detection | Slightly more complex script, but catches more ADRs |
| Script size vs zero dependencies | Pure Node.js    | Larger script, but no npm dependencies needed       |

## Decision Drivers

- Release notes should provide full architectural context
- Links must work in GitHub release pages (not just repo browsing)
- Solution should be shareable across repositories
- No additional npm dependencies (pure Node.js)

## Considered Options

- **Option A**: Git diff only - detect ADRs from changed files
- **Option B**: Commit message parsing only - extract `ADR: YYYY-MM-DD-slug` references
- **Option C**: Union of both approaches <- Selected

## Decision Outcome

Chosen option: **Option C (Union of both)**, because it provides the most complete coverage. Git diff catches ADRs that were modified, while commit parsing catches ADRs referenced in commits even if the ADR file wasn't changed in the same release.

## Synthesis

**Convergent findings**: All analysis agreed that semantic-release's `generateNotesCmd` hook is the correct integration point, and that the script must output markdown to stdout.

**Divergent findings**: Initial consideration of relative links was rejected after confirming GitHub release pages require absolute URLs.

**Resolution**: Full HTTPS URLs with dynamic repo detection via `git remote get-url origin`.

## Consequences

### Positive

- Release notes include architectural context (ADRs and Design Specs)
- Users can click through to understand decisions behind changes
- Shareable script works across any repository
- No additional npm dependencies required

### Negative

- Adds script execution time to release process
- First release (no prior tag) requires special handling
- Script must handle edge cases (no ADRs, deleted files, missing frontmatter)

## Architecture

```
🏗️ generate-doc-notes.mjs Architecture

                         ╭──────────────────────────────╮
                         │      lastRelease.gitTag      │
                         ╰──────────────────────────────╯
                           │
                           │
                           ∨
┌──────────────────┐     ┌──────────────────────────────┐
│ git diff (files) │ <── │  git remote get-url origin   │
└──────────────────┘     └──────────────────────────────┘
  │                        │
  │                        │
  │                        ∨
  │                      ┌──────────────────────────────┐
  │                      │      git log (messages)      │
  │                      └──────────────────────────────┘
  │                        │
  │                        │
  │                        ∨
  │                      ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
  └────────────────────> ┃        Union + Dedupe        ┃
                         ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
                           │
                           │
                           ∨
                         ┌──────────────────────────────┐
                         │ extractTitle + extractStatus │
                         └──────────────────────────────┘
                           │
                           │
                           ∨
                         ╭──────────────────────────────╮
                         │      Markdown to stdout      │
                         ╰──────────────────────────────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ generate-doc-notes.mjs Architecture"; flow: south; }

[input] { label: "lastRelease.gitTag"; shape: rounded; }
[repo] { label: "git remote get-url origin"; }
[diff] { label: "git diff (files)"; }
[commits] { label: "git log (messages)"; }
[union] { label: "Union + Dedupe"; border: bold; }
[enrich] { label: "extractTitle + extractStatus"; }
[output] { label: "Markdown to stdout"; shape: rounded; }

[input] -> [repo]
[repo] -> [diff]
[repo] -> [commits]
[diff] -> [union]
[commits] -> [union]
[union] -> [enrich]
[enrich] -> [output]
```

</details>

## Scope Expansion (2025-12-21)

### Extended Documentation Coverage

The original implementation focused on ADRs and Design Specs. This expansion extends to **all markdown documentation**, enabling AI coding agents and humans to see a complete picture of documentation changes in each release.

### New Category Structure

```
1. Architecture Decisions
   ├── ADRs (docs/adr/*.md) - with status table
   └── Design Specs (docs/design/*/spec.md)

2. Plugin Documentation
   ├── Skills (plugins/*/skills/*/SKILL.md) - grouped by plugin
   ├── Plugin READMEs (plugins/*/README.md)
   └── Skill References (plugins/*/skills/*/references/*.md) - collapsible

3. Repository Documentation
   ├── Root docs (CLAUDE.md, README.md, CHANGELOG.md)
   └── General docs (docs/*.md excluding adr/, design/)

4. Commands & Other
   ├── Commands (plugins/*/commands/*.md)
   └── Other markdown files (catch-all)
```

### Rationale

| Decision                 | Choice                      | Rationale                                                |
| ------------------------ | --------------------------- | -------------------------------------------------------- |
| **Expanded scope**       | All markdown files          | AI agents benefit from complete documentation visibility |
| **Categorization**       | Hierarchical structure      | Clear organization for both human and machine readers    |
| **Collapsible sections** | `<details>` HTML tags       | Prevents verbose release notes when many skills change   |
| **Change type tracking** | new/updated/deleted/renamed | Clear indication of what happened to each file           |
| **Script rename**        | `generate-doc-notes.mjs`    | Reflects broader scope beyond just ADRs                  |

### Implementation Changes

- Script renamed from `generate-adr-notes.mjs` to `generate-doc-notes.mjs`
- Reference file renamed from `adr-release-linking.md` to `doc-release-linking.md`
- Configuration updated to use hardcoded relative path (no env var needed)
- Environment variable changed from `ADR_NOTES_SCRIPT` to `DOC_NOTES_SCRIPT` for shareable configs

## References

- [semantic-release skill](/plugins/itp/skills/semantic-release/SKILL.md)
- [@semantic-release/exec plugin](https://github.com/semantic-release/exec)
- [Documentation Release Linking Reference](/plugins/itp/skills/semantic-release/references/doc-release-linking.md)
