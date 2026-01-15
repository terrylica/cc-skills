## Problem

The `pretooluse-version-guard.mjs` hook blocks edits to `CLAUDE.md` files that contain version history documentation, even when editing unrelated fields like dates.

### Reproduction

1. Try to edit `~/scripts/iterm2/CLAUDE.md` to change the date:

```markdown
**Updated**: 2026-01-09
**Version**: 3.0.0
```

1. The hook blocks with:

```
[VERSION-GUARD] Hardcoded version in CLAUDE.md

Found: "3.0.0"

Fix by using one of:
  my-package = "<version>"  (placeholder pattern)
  See [crates.io](link)     (registry link)
  # SSoT-OK                 (escape hatch comment)

SSoT: Version only in Cargo.toml/pyproject.toml/package.json
```

### Root Cause

The hook (`plugins/itp-hooks/hooks/pretooluse-version-guard.mjs`) has these issues:

1. **Checks content being written, not the whole file context** - If you edit ANY part of a markdown file that already contains version strings elsewhere, it blocks

2. **CLAUDE.md version history is legitimate** - These files document script/module version history (like changelogs) but are not in the `EXCLUDED_PATHS` list

3. **Pattern too broad** - The prose pattern `/Version:\s*(\d+\.\d+\.\d+)/gi` catches `**Version**: 3.0.0` which is standard documentation format

### Suggested Fixes

**Option 1**: Add CLAUDE.md to excluded paths (similar to CHANGELOG)

```javascript
const EXCLUDED_PATHS = [
  /CHANGELOG/i,
  /CLAUDE\.md$/i, // ADD THIS - Project docs often have version history
  // ...
];
```

**Option 2**: Only check the `new_string`/`content` being written, not versions that already exist in the file

**Option 3**: Exclude "Version History" sections in markdown files

### Context

- Hook location: `plugins/itp-hooks/hooks/pretooluse-version-guard.mjs`
- ADR referenced (not created): `/docs/adr/2026-01-09-version-ssot-guard.md`
- The SSoT principle is good, but CLAUDE.md files serve as project documentation where version history is appropriate

### Workaround

Add `# SSoT-OK` comment to the file, but this defeats the purpose of the guard for actual package versions.
