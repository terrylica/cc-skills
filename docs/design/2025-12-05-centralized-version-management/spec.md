# Design Spec: Centralized Version Management

**ADR**: [Centralized Version Management](/docs/adr/2025-12-05-centralized-version-management.md)

**Status**: Implemented (v2.5.1)

**Final Solution**: @semantic-release/exec + custom Node.js script

## Overview

Centralized version management for the cc-skills marketplace plugin using `@semantic-release/exec` with a custom validation script. This approach replaced both the original sed-based method and the buggy `semantic-release-replace-plugin`.

## Problem Statement

| Issue                           | Impact                       | Resolution                           |
| ------------------------------- | ---------------------------- | ------------------------------------ |
| sed `-i ''` is macOS-specific   | Breaks on Linux CI           | Node.js script (cross-platform)      |
| sed matches ALL version fields  | Could corrupt nested configs | Explicit 4-file list in script       |
| No validation after replacement | Silent failures              | Script validates 8 replacements      |
| package.json frozen at 1.0.0    | Version drift                | Now synced automatically             |
| replace-plugin `results` bug    | Failed releases              | Replaced with @semantic-release/exec |

## Final Working Solution

### Configuration (`.releaserc.yml`)

```yaml
plugins:
  - - "@semantic-release/commit-analyzer"
    - releaseRules:
        - { type: "docs", release: "patch" }
        - { type: "chore", release: "patch" }
        - { type: "style", release: "patch" }
        - { type: "refactor", release: "patch" }
        - { type: "test", release: "patch" }
        - { type: "build", release: "patch" }
        - { type: "ci", release: "patch" }
  - "@semantic-release/release-notes-generator"
  - "@semantic-release/changelog"
  - - "@semantic-release/exec"
    - prepareCmd: "node scripts/sync-versions.mjs ${nextRelease.version}"
  - - "@semantic-release/git"
    - assets:
        - CHANGELOG.md
        - plugin.json
        - package.json
        - .claude-plugin/plugin.json
        - .claude-plugin/marketplace.json
      message: "chore(release): ${nextRelease.version} [skip ci]"
  - "@semantic-release/github"
```

### Version Sync Script (`scripts/sync-versions.mjs`)

Key features:

- Updates 4 files with 8 total version fields
- Validates semver format
- Validates expected replacement counts per file
- Exits non-zero on any validation failure
- Can be run standalone for testing

```bash
# Test the script
node scripts/sync-versions.mjs 1.2.3

# Expected output:
# Updated plugin.json: 1 version field(s)
# Updated package.json: 1 version field(s)
# Updated .claude-plugin/plugin.json: 1 version field(s)
# Updated .claude-plugin/marketplace.json: 5 version field(s)
#
# --- Version Sync Summary ---
# Version: 1.2.3
# Files processed: 4
# Total replacements: 8
#
# Version sync completed successfully!
```

## Version Field Inventory

### Files Synced (10 files, 20 fields)

**Core files (4 files, 14 fields):**

| File                              | Fields | Expected |
| --------------------------------- | ------ | -------- |
| `plugin.json`                     | 1      | 1        |
| `package.json`                    | 1      | 1        |
| `.claude-plugin/plugin.json`      | 1      | 1        |
| `.claude-plugin/marketplace.json` | 11     | 11       |

**Individual plugin files (6 files, 6 fields):**

| File                                             | Fields | Expected |
| ------------------------------------------------ | ------ | -------- |
| `plugins/*/.claude-plugin/plugin.json` (dynamic) | 1 each | 1        |
| **Total**                                        | **20** | **20**   |

### Protected Files (Not in script's file list)

| File                                                                                 | Version             | Reason               |
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
/usr/bin/env bash -c 'CI=true GITHUB_TOKEN="$(gh auth token)" npm run release'
```

**Why CI=true?** semantic-release v25+ auto-enables dry-run mode outside CI environments as a safety feature.

### Dry Run

```bash
/usr/bin/env bash -c 'GITHUB_TOKEN="$(gh auth token)" npm run release:dry'
```

## Implementation Journey

### Attempt 1: semantic-release-replace-plugin with `results` validation

```yaml
# FAILED - Do not use
- - "semantic-release-replace-plugin"
  - replacements:
      - files: ["plugin.json"]
        from: '"version": "[0-9]+\\.[0-9]+\\.[0-9]+"'
        to: '"version": "${nextRelease.version}"'
        results:
          - file: plugin.json
            hasChanged: true
            numMatches: 1
```

**Error**: Validation logic inverted - expected `hasChanged: false` despite configuring `true`.

### Attempt 2: semantic-release-replace-plugin without `results`

```yaml
# FAILED - Files not updated
- - "semantic-release-replace-plugin"
  - replacements:
      - files: ["plugin.json"]
        from: '"version": "[0-9]+\\.[0-9]+\\.[0-9]+"'
        to: '"version": "${nextRelease.version}"'
        countMatches: true
```

**Error**: Plugin reported success but files unchanged. Root cause unknown.

### Attempt 3: @semantic-release/exec + custom script ✓

```yaml
# SUCCESS
- - "@semantic-release/exec"
  - prepareCmd: "node scripts/sync-versions.mjs ${nextRelease.version}"
```

**Result**: All 8 version fields updated, 5 files committed, release published.

## Verification Checklist

After each release, verify:

- [ ] GitHub release created with correct version tag
- [ ] `plugin.json` version matches release
- [ ] `package.json` version matches release
- [ ] `.claude-plugin/plugin.json` version matches release
- [ ] `.claude-plugin/marketplace.json` has 5 matching versions
- [ ] Template files unchanged (`0.0.0-development`, `1.0.0`)

Quick check command:

```bash
grep '"version"' plugin.json package.json .claude-plugin/*.json
```

## Rollback Plan

If issues occur, the script can be modified or replaced:

```bash
# Revert to manual updates
git revert HEAD  # Revert problematic release
# Manually update version files
node -e "
const fs = require('fs');
const VERSION = 'X.Y.Z';
['plugin.json', 'package.json', '.claude-plugin/plugin.json', '.claude-plugin/marketplace.json']
  .forEach(f => {
    let c = fs.readFileSync(f, 'utf8');
    c = c.replace(/\"version\": \"[0-9]+\.[0-9]+\.[0-9]+\"/g, '\"version\": \"' + VERSION + '\"');
    fs.writeFileSync(f, c);
  });
"
```

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

## Release History

| Version | Date       | Method                 | Result                      |
| ------- | ---------- | ---------------------- | --------------------------- |
| v2.5.0  | 2025-12-05 | replace-plugin         | Partial (manual fix needed) |
| v2.5.1  | 2025-12-05 | @semantic-release/exec | Success                     |

## References

- [ADR: Centralized Version Management](/docs/adr/2025-12-05-centralized-version-management.md)
- [@semantic-release/exec](https://github.com/semantic-release/exec)
- [semantic-release FAQ](https://semantic-release.gitbook.io/semantic-release/support/faq)
- [replace-plugin issue #164](https://github.com/jpoehnelt/semantic-release-replace-plugin/issues/164)
