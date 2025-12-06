# Design Spec: Centralized Version Management

**ADR**: [Centralized Version Management](/docs/adr/2025-12-05-centralized-version-management.md)

**Status**: Implemented (v2.5.0)

## Overview

This spec documents the implementation of centralized version management using `semantic-release-replace-plugin`, including lessons learned from the initial rollout.

## Problem Statement

| Issue                           | Impact                       | Resolution                          |
| ------------------------------- | ---------------------------- | ----------------------------------- |
| sed `-i ''` is macOS-specific   | Breaks on Linux CI           | Use replace-plugin (cross-platform) |
| sed matches ALL version fields  | Could corrupt nested configs | Explicit file targeting             |
| No validation after replacement | Silent failures              | `countMatches: true`                |
| package.json frozen at 1.0.0    | Version drift                | Now synced to plugin version        |

## Implementation Details

### Working Configuration

```yaml
# .releaserc.yml
- - "semantic-release-replace-plugin"
  - replacements:
      - files: ["plugin.json"]
        from: '"version": "[0-9]+\\.[0-9]+\\.[0-9]+"'
        to: '"version": "${nextRelease.version}"'
        countMatches: true

      - files: ["package.json"]
        from: '"version": "[0-9]+\\.[0-9]+\\.[0-9]+"'
        to: '"version": "${nextRelease.version}"'
        countMatches: true

      - files: [".claude-plugin/plugin.json"]
        from: '"version": "[0-9]+\\.[0-9]+\\.[0-9]+"'
        to: '"version": "${nextRelease.version}"'
        countMatches: true

      - files: [".claude-plugin/marketplace.json"]
        from: '"version": "[0-9]+\\.[0-9]+\\.[0-9]+"'
        to: '"version": "${nextRelease.version}"'
        countMatches: true
```

### Key Configuration Notes

1. **Regex Pattern**: `'"version": "[0-9]+\\.[0-9]+\\.[0-9]+"'`
   - Must match exact format in JSON files (space after colon)
   - Double-escaped backslashes required in YAML

2. **countMatches**: Set to `true` for basic verification (logs match count)

3. **DO NOT USE `results` validation**: See [Lessons Learned](#lessons-learned)

## Version Field Inventory

### Files to Sync (4 files, 8 fields)

| File                              | Fields | Format               |
| --------------------------------- | ------ | -------------------- |
| `plugin.json`                     | 1      | `"version": "X.Y.Z"` |
| `package.json`                    | 1      | `"version": "X.Y.Z"` |
| `.claude-plugin/plugin.json`      | 1      | `"version": "X.Y.Z"` |
| `.claude-plugin/marketplace.json` | 5      | `"version": "X.Y.Z"` |

### Protected Files (DO NOT SYNC)

| File                                                                                 | Version             | Reason               |
| ------------------------------------------------------------------------------------ | ------------------- | -------------------- |
| `plugins/itp/skills/semantic-release/assets/templates/package.json`                  | `0.0.0-development` | Template placeholder |
| `plugins/itp/skills/semantic-release/assets/templates/shareable-config/package.json` | `1.0.0`             | Example config       |

**Protection mechanism**: Explicit file targeting (only 4 production files listed)

## Running Releases

### From CI (GitHub Actions)

```bash
# Automatic - CI environment detected
npm run release
```

### From Local Machine

```bash
# Must set CI=true to bypass dry-run mode
CI=true GITHUB_TOKEN="$(gh auth token)" npm run release
```

### Dry Run

```bash
GITHUB_TOKEN="$(gh auth token)" npm run release:dry
```

## Lessons Learned

### 1. `results` Validation is Unreliable

**Original Plan**: Use `results` array for strict validation:

```yaml
results:
  - file: plugin.json
    hasChanged: true
    numMatches: 1
    numReplacements: 1
```

**What Happened**: Validation failed with inverted logic:

```
Error: Expected match not found!
- Expected: hasChanged: false, numMatches: 0
+ Received: hasChanged: true, numMatches: 1
```

The plugin expected `false/0` despite configuring `true/1`. This appears to be a bug in `semantic-release-replace-plugin` v1.2.7.

**Resolution**: Remove `results` blocks entirely. Use `countMatches: true` for basic logging.

### 2. Local Releases Require CI=true

**Original Plan**: Run `npm run release` locally

**What Happened**: semantic-release v25 auto-enables dry-run mode outside CI environments:

```
⚠ This run was not triggered in a known CI environment, running in dry-run mode.
```

**Resolution**: Set `CI=true` environment variable for local releases.

### 3. Version File Updates May Not Commit

**Original Plan**: Replace-plugin updates files → @semantic-release/git commits them

**What Happened**: Plugin reported success but files weren't modified. Only CHANGELOG.md was committed.

**Root Cause**: Unknown - possibly race condition or plugin execution order issue.

**Resolution**: Verify version files after release. If drift detected, manually sync and commit:

```bash
node -e "
const fs = require('fs');
['plugin.json', 'package.json', '.claude-plugin/plugin.json', '.claude-plugin/marketplace.json']
  .forEach(f => {
    let c = fs.readFileSync(f, 'utf8');
    c = c.replace(/\"version\": \"[0-9]+\.[0-9]+\.[0-9]+\"/g, '\"version\": \"X.Y.Z\"');
    fs.writeFileSync(f, c);
  });
"
```

## Verification Checklist

After each release, verify:

- [ ] GitHub release created with correct version tag
- [ ] `plugin.json` version matches release
- [ ] `package.json` version matches release
- [ ] `.claude-plugin/plugin.json` version matches release
- [ ] `.claude-plugin/marketplace.json` has 5 matching versions
- [ ] Template files unchanged (`0.0.0-development`, `1.0.0`)

## Rollback Plan

If critical issues occur:

```bash
# Revert to previous release config
git revert HEAD
npm uninstall semantic-release-replace-plugin

# Re-add sed-based approach (not recommended)
# Better: fix replace-plugin config or file issue report
```

## Future Improvements

1. **File issue** with semantic-release-replace-plugin about `results` validation bug
2. **Add post-release hook** to verify version file updates automatically
3. **Consider alternative plugins** if issues persist (e.g., `@semantic-release/exec` with portable scripts)

## References

- [semantic-release-replace-plugin](https://github.com/jpoehnelt/semantic-release-replace-plugin)
- [semantic-release v25 changelog](https://github.com/semantic-release/semantic-release/releases/tag/v25.0.0)
- [ADR: Centralized Version Management](/docs/adr/2025-12-05-centralized-version-management.md)
