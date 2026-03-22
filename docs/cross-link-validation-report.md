# Cross-Link Validation Report

**Task:** Task 8: Cross-Link Validation & Broken Link Detection  
**Generated:** March 8, 2026  
**CLAUDE.md Files Analyzed:** 28

---

## Summary

| Metric         | Count | Percentage |
| -------------- | ----- | ---------- |
| Total Links    | 173   | 100%       |
| Valid Links    | 148   | 85%        |
| Broken Links   | 10    | 6%         |
| External Links | 14    | 8%         |

---

## Broken Links

### Files That Don't Exist (5)

These links point to files that don't exist in the repository:

| Source File                      | Broken Link                                | Issue                                                           |
| -------------------------------- | ------------------------------------------ | --------------------------------------------------------------- |
| `CLAUDE.md`                      | `./references/guide.md`                    | Non-existent template/example file                              |
| `CLAUDE.md`                      | `/docs/adr/file.md`                        | Example ADR path (placeholder)                                  |
| `plugins/CLAUDE.md`              | `./references/guide.md`                    | Same as above                                                   |
| `plugins/CLAUDE.md`              | `/docs/adr/file.md`                        | Same as above                                                   |
| `plugins/devops-tools/CLAUDE.md` | `/docs/infrastructure/zerotier-network.md` | Local reference (exists in `~/.claude/docs` but not in project) |

### Anchors That Don't Match (5)

These links point to files that exist, but the anchor/header doesn't match:

| Source File                         | Link                                                                   | Target Header Status                                                              |
| ----------------------------------- | ---------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `docs/CLAUDE.md`                    | `../plugins/itp-hooks/CLAUDE.md#vale-terminology-enforcement`          | Header doesn't exist in target                                                    |
| `docs/CLAUDE.md`                    | `../CLAUDE.md#development-toolchain`                                   | Header exists ("Development Toolchain") but anchor format differs                 |
| `plugins/CLAUDE.md`                 | `../CLAUDE.md#development-toolchain`                                   | Same as above                                                                     |
| `plugins/gmail-commander/CLAUDE.md` | `./skills/bot-process-control/SKILL.md#diagnosing-invalid_grant`       | Header exists ("Diagnosing `invalid_grant`") but anchor uses underscore vs hyphen |
| `plugins/tts-tg-sync/CLAUDE.md`     | `../itp-hooks/CLAUDE.md#typescript-services-swift-runner--bun---watch` | Header doesn't exist in target                                                    |

---

## External Links (14)

Links to external URLs (not validated - assumed working):

| Source File                        | URL                                                                                                         |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `CLAUDE.md`                        | <https://example.com>                                                                                       |
| `docs/CLAUDE.md`                   | <https://github.com/adr/madr>                                                                               |
| `plugins/CLAUDE.md`                | <https://example.com>                                                                                       |
| `plugins/gh-tools/CLAUDE.md`       | <https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-11-21-github-actions-no-testing-linting.md> |
| `plugins/gitnexus-tools/CLAUDE.md` | <https://www.npmjs.com/package/gitnexus>                                                                    |
| `plugins/itp-hooks/CLAUDE.md`      | <https://code.claude.com/docs/en/hooks>                                                                     |
| `plugins/itp-hooks/CLAUDE.md`      | <https://github.com/Nukesor/pueue>                                                                          |
| `plugins/itp-hooks/CLAUDE.md`      | <https://github.com/terrylica/rangebar-py/issues/77>                                                        |
| `plugins/itp-hooks/CLAUDE.md`      | <https://github.com/anthropics/claude-code/issues/11898>                                                    |
| `plugins/itp-hooks/CLAUDE.md`      | <https://github.com/anthropics/claude-code/issues/12507>                                                    |
| `plugins/itp-hooks/CLAUDE.md`      | <https://github.com/anthropics/claude-code/issues/13598>                                                    |
| `plugins/itp-hooks/CLAUDE.md`      | <https://github.com/terrylica/cc-skills/issues/28>                                                          |
| `plugins/kokoro-tts/CLAUDE.md`     | <https://github.com/Blaizzy/mlx-audio>                                                                      |

---

## Recommendations

### High Priority

1. **Remove template/example links** - The `./references/guide.md` and `/docs/adr/file.md` links appear to be template examples that should be removed or replaced with actual documentation.

2. **Fix zerotier-network.md reference** - Either:
   - Add the file to the project at `docs/infrastructure/zerotier-network.md`, or
   - Update the link to point to the local file path `~/.claude/docs/infrastructure/zerotier-network.md`, or
   - Remove the reference if it's no longer needed

3. **Fix vale-terminology-enforcement anchor** - Verify the correct section name in `plugins/itp-hooks/CLAUDE.md` and update the link in `docs/CLAUDE.md`

4. **Fix typescript-services-swift-runner--bun---watch anchor** - Verify the correct section name in `plugins/itp-hooks/CLAUDE.md` and update the link in `plugins/tts-tg-sync/CLAUDE.md`

### Medium Priority

1. **Standardize anchor format** - The `diagnosing-invalid_grant` link uses underscores while markdown processors typically convert spaces to hyphens. Consider updating to `diagnosing-invalid-grant`.

2. **Consider anchor compatibility** - The `development-toolchain` anchors technically work in most markdown viewers despite the space-to-hyphen conversion. This is a low-priority fix.

---

## Validation Script

A validation script has been created at `/tmp/crew-task8/validate_links.sh` that can be run to re-validate links after fixes are applied.

```bash
/tmp/crew-task8/validate_links.sh
```

---

## Notes

- The validation script uses `realpath` to resolve relative paths correctly
- Anchor detection accounts for case-insensitive matching but may have edge cases with special characters
- External links were not validated for availability
- Directory links (e.g., `./docs/troubleshooting/`) are treated as valid if the directory exists
