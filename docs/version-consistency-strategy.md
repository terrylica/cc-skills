# Version Consistency Strategy

**Task:** Task 4: Version Consistency Strategy  
**Author:** PureMoon  
**Date:** 2026-03-02

## Executive Summary

This document analyzes the current versioning patterns in cc-skills and proposes a unified version consistency strategy. The analysis reveals **significant version drift** between marketplace.json and individual plugin files, and recommends a **marketplace.json-only versioning** approach with cleanup of legacy version files.

---

## Current State Analysis

### Version Sources Identified

| Location | File | Current Version | Status |
|----------|------|-----------------|--------|
| Root | `plugin.json` | 11.73.0 | ✓ Synced |
| Root | `package.json` | 11.73.0 | ✓ Synced |
| Root | `.claude-plugin/plugin.json` | 11.73.0 | ✓ Synced |
| Root | `.claude-plugin/marketplace.json` | 11.73.0 | ✓ Synced |
| Plugin | `plugins/link-tools/plugin.json` | 7.19.7 | ✗ Out of sync |
| Plugin | `plugins/plugin-dev/plugin.json` | 7.19.7 | ✗ Out of sync |
| Plugin | `plugins/git-town-workflow/plugin.json` | 1.0.0 | ✗ Out of sync |
| Plugin | `plugins/calcom-commander/package.json` | 1.0.0 | ✗ Out of sync |
| Plugin | `plugins/gmail-commander/package.json` | 1.0.0 | ✗ Out of sync |
| Plugin | `plugins/plugin-dev/package.json` | 1.0.0 | ✗ Out of sync |
| Plugin | `plugins/statusline-tools/package.json` | 1.0.0 | ✗ Out of sync |

### CLAUDE.md Files

- **Status:** No version numbers in any CLAUDE.md files
- **Recommendation:** Continue this pattern — documentation should not hardcode versions

### Version Sync Mechanism

The release process uses `scripts/sync-versions.mjs` which:
1. Runs during `@semantic-release/exec` prepare step
2. Updates 4 root-level files with version fields
3. Validates expected replacement counts
4. Designed for **marketplace.json-only versioning** (per ADR 2025-12-05)

---

## Issues Identified

### 1. Legacy Version Files Not Synced

The sync script was designed to use marketplace.json as the single source of truth, but 4 plugins still have individual version files that are never updated:

- `plugins/link-tools/plugin.json` (version 7.19.7)
- `plugins/plugin-dev/plugin.json` (version 7.19.7)
- `plugins/git-town-workflow/plugin.json` (version 1.0.0)
- `plugins/calcom-commander/package.json` (version 1.0.0)
- `plugins/gmail-commander/package.json` (version 1.0.0)
- `plugins/plugin-dev/package.json` (version 1.0.0)
- `plugins/statusline-tools/package.json` (version 1.0.0)

### 2. Version Drift Risk

With 7 files out of sync, there's risk that:
- Developers may reference stale versions
- Build processes expecting certain versions may fail
- Confusion about which version is "correct"

### 3. No Validation in CI

The current release process doesn't validate that all version files match before publishing.

---

## Recommendations

### Option A: Marketplace.json-Only Versioning (Recommended)

This aligns with the original ADR 2025-12-05 design and matches how claude-code-plugins-plus (254 plugins) operates.

**Actions:**
1. Delete legacy plugin.json files from plugins/ directory
2. Delete legacy package.json files from plugins/ directory  
3. Update sync-versions.mjs to fail if any plugin version files exist
4. Add pre-commit validation to catch new version files

**Pros:**
- Single source of truth
- Matches established patterns in larger plugin ecosystems
- Simpler release process
- No version drift possible

**Cons:**
- Breaking change for any external tooling expecting individual version files
- Requires cleanup of existing legacy files

### Option B: Full Plugin Version Sync

Update sync-versions.mjs to also sync all individual plugin version files.

**Actions:**
1. Modify FILES array in sync-versions.mjs to include plugins/*/plugin.json
2. Modify FILES array to include plugins/*/package.json
3. Add glob pattern matching for dynamic discovery
4. Update EXPECTED_COUNTS to account for variable plugin count

**Pros:**
- Maintains compatibility with external tooling
- Each plugin remains independently versionable

**Cons:**
- More complex sync script
- Version drift risk across 23+ plugin files
- More places for errors
- Contradicts ADR 2025-12-05 design decision

---

## Implementation Plan (Option A)

### Phase 1: Cleanup (Immediate)

```bash
# Remove legacy plugin.json files
rm plugins/link-tools/plugin.json
rm plugins/plugin-dev/plugin.json
rm plugins/git-town-workflow/plugin.json

# Remove legacy package.json files (keep if needed for dependencies)
rm plugins/calcom-commander/package.json
rm plugins/gmail-commander/package.json
rm plugins/plugin-dev/package.json
rm plugins/statusline-tools/package.json
```

### Phase 2: Validation (Post-Cleanup)

Add to `scripts/sync-versions.mjs`:

```javascript
// After auto-discovering plugins, verify no stray version files
const versionFiles = findFiles(pluginsDir, ['plugin.json', 'package.json']);
if (versionFiles.length > 0) {
  console.error(`Found stray version files: ${versionFiles.join(', ')}`);
  process.exit(1);
}
```

### Phase 3: Pre-Commit Hook (Optional)

Add validation to `.git/hooks/pre-commit`:

```bash
# Verify no plugin version files exist
find plugins -name "plugin.json" -o -name "package.json" | grep -v node_modules && {
  echo "Error: Individual plugin version files not allowed"
  exit 1
}
```

---

## Conclusion

The **marketplace.json-only versioning** approach (Option A) is recommended because:

1. It aligns with the existing ADR 2025-12-05 design
2. It matches how larger plugin ecosystems operate
3. It eliminates version drift entirely
4. It simplifies the release process

The legacy version files should be removed and validation added to prevent future drift.

---

## References

- [ADR 2025-12-05: Centralized Version Management](/docs/adr/2025-12-05-centralized-version-management.md)
- [scripts/sync-versions.mjs](scripts/sync-versions.mjs)
- [.releaserc.yml](.releaserc.yml)
- [marketplace.json](.claude-plugin/marketplace.json)
