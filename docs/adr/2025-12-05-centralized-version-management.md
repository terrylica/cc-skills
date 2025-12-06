---
status: accepted
date: 2025-12-05
decision-maker: terrylica
consulted: Claude Code (12-agent DCTL audit)
research-method: Web research + local codebase analysis
clarification-iterations: 3
supersedes: sed-based version updates
perspectives:
  - EcosystemArtifact
  - DeveloperExperience
---

# Centralized Version Management with @semantic-release/exec

## Context and Problem Statement

The cc-skills repository has version information scattered across 4 files with 8 total version fields. The original sed-based approach had several problems:

1. **Platform-specific syntax**: `sed -i ''` is macOS-specific; Linux requires `sed -i`
2. **Greedy matching**: Pattern `"version": "[^"]*"` matches ALL version fields
3. **No validation**: Silent failures if pattern doesn't match
4. **Version drift**: package.json frozen at 1.0.0 while plugin.json was at 2.4.0
5. **Template risk**: Could corrupt template files with placeholder versions

## Research Summary

### Web Research Findings

1. **semantic-release-replace-plugin**: Has [known bugs with results validation](https://github.com/jpoehnelt/semantic-release-replace-plugin/issues/164)
2. **@semantic-release/exec**: Official plugin, full control via custom scripts
3. **npm postversion hook**: [Officially recommended](https://semantic-release.gitbook.io/semantic-release/support/faq) for version file updates
4. **Changesets**: Overkill for monolithic versioning

### Implementation Journey

| Attempt | Approach                                                  | Result                             |
| ------- | --------------------------------------------------------- | ---------------------------------- |
| 1       | semantic-release-replace-plugin with `results` validation | Failed - inverted validation logic |
| 2       | replace-plugin without `results`                          | Files not updated (unknown cause)  |
| 3       | **@semantic-release/exec + custom script**                | **Success**                        |

## Decision Log

| Question             | Answer                       | Rationale                                 |
| -------------------- | ---------------------------- | ----------------------------------------- |
| Sync package.json?   | Yes                          | Aligns with npm ecosystem; fixes drift    |
| Which tool?          | @semantic-release/exec       | Official plugin, full control, debuggable |
| Template protection? | Explicit file list in script | Script only updates 4 specific files      |

## Considered Options

1. **Keep sed** - Platform-specific, fragile
2. **semantic-release-replace-plugin** - Buggy validation, unreliable
3. **@semantic-release/exec + script** - Official plugin, full control ✓
4. **Changesets** - Overkill for monolithic versioning

## Decision Outcome

**Chosen option**: @semantic-release/exec with custom Node.js script

### Implementation

```yaml
# .releaserc.yml
- - "@semantic-release/exec"
  - prepareCmd: "node scripts/sync-versions.mjs ${nextRelease.version}"
```

The script (`scripts/sync-versions.mjs`) handles:

- Updates 4 files with 8 total version fields
- Validates expected replacement counts per file
- Exits with error if validation fails

### Positive Consequences

- Cross-platform compatible (Node.js)
- Full control over replacement logic
- Built-in validation with clear error messages
- Uses official semantic-release plugin
- Easier to debug and maintain
- Script can be run standalone for testing

### Negative Consequences

- Custom script to maintain (but simple ~80 lines)
- Extra file in repository

## Architecture

```
🔄 Version Sync Architecture

╭───────────────────╮  semantic-release                   ┌────────────────────────┐
│    Git Commits    │  analyzeCommits                     │   Version Determined   │
│                   │ ──────────────────────────────────> │                        │
╰───────────────────╯                                     └────────────────────────┘
                                                            │
                                                            │
                                                            ∨
┌───────────────────┐                                     ┌────────────────────────┐
│ sync-versions.mjs │                      version arg    │ @semantic-release/exec │
│                   │ <────────────────────────────────── │       prepareCmd       │
└───────────────────┘                                     └────────────────────────┘
  │
  │
  ∨
┌───────────────────┐                                     ┌────────────────────────┐
│  10 JSON Files    │                                     │ @semantic-release/git  │
│   (20 fields)     │ <─────────────────────────────────> │                        │
└───────────────────┘                                     └────────────────────────┘
                                                            │
                                                            │ commit
                                                            ∨
                                                          ╭────────────────────────╮
                                                          │     GitHub Release     │
                                                          ╰────────────────────────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🔄 Version Sync Architecture"; }

[ Commits ] { shape: rounded; label: "Git Commits"; }
[ Determined ] { label: "Version Determined"; origin: Commits; offset: 4,0; }
[ PrepareCmd ] { label: "@semantic-release/exec\nprepareCmd"; origin: Determined; offset: 0,2; }
[ SyncScript ] { label: "sync-versions.mjs"; origin: PrepareCmd; offset: -4,0; }
[ JSONFiles ] { label: "10 JSON Files\n(20 fields)"; origin: SyncScript; offset: 0,2; }
[ GitPlugin ] { label: "@semantic-release/git"; origin: JSONFiles; offset: 4,0; }
[ Release ] { shape: rounded; label: "GitHub Release"; origin: GitPlugin; offset: 0,2; }

[ Commits ] -- semantic-release\nanalyzeCommits --> [ Determined ]
[ Determined ] -> [ PrepareCmd ]
[ PrepareCmd ] -- version arg --> [ SyncScript ]
[ SyncScript ] -> [ JSONFiles ]
[ JSONFiles ] <-> [ GitPlugin ]
[ GitPlugin ] -- commit --> [ Release ]
```

</details>

## Version Field Inventory

### Files Synced (10 files, 20 fields)

**Core files (4 files, 14 fields):**

| File                              | Fields | Validated |
| --------------------------------- | ------ | --------- |
| `plugin.json`                     | 1      | ✓         |
| `package.json`                    | 1      | ✓         |
| `.claude-plugin/plugin.json`      | 1      | ✓         |
| `.claude-plugin/marketplace.json` | 11     | ✓         |

**Individual plugin files (6 files, 6 fields):**

| File                                             | Fields | Validated |
| ------------------------------------------------ | ------ | --------- |
| `plugins/*/.claude-plugin/plugin.json` (dynamic) | 1 each | ✓         |

The script dynamically discovers individual plugin.json files in `plugins/*/`.

### Protected Files (Not in script's file list)

| File                                                                                 | Version             | Why Protected        |
| ------------------------------------------------------------------------------------ | ------------------- | -------------------- |
| `plugins/itp/skills/semantic-release/assets/templates/package.json`                  | `0.0.0-development` | Template placeholder |
| `plugins/itp/skills/semantic-release/assets/templates/shareable-config/package.json` | `1.0.0`             | Example config       |

## Running Releases

### From CI (GitHub Actions)

```bash
npm run release
```

### From Local Machine

```bash
CI=true GITHUB_TOKEN="$(gh auth token)" npm run release
```

### Testing the Script

```bash
node scripts/sync-versions.mjs 1.2.3  # Test with any version
```

## More Information

- [Design Spec](/docs/design/2025-12-05-centralized-version-management/spec.md)
- [@semantic-release/exec](https://github.com/semantic-release/exec)
- [semantic-release FAQ](https://semantic-release.gitbook.io/semantic-release/support/faq)
- [replace-plugin issue #164](https://github.com/jpoehnelt/semantic-release-replace-plugin/issues/164)
