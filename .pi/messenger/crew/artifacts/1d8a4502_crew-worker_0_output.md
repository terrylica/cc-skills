Task completed! I've created **docs/discovery-architecture.md** with a comprehensive analysis of the search and discovery architecture in cc-skills.

## Summary

**Current Discovery Mechanisms Analyzed:**
1. Hub-and-Spoke Navigation (CLAUDE.md hierarchy)
2. Skill Discovery via Slash Commands (164 SKILL.md files with frontmatter)
3. Plugin Registry (marketplace.json with keywords)
4. Link Validation (lychee.toml)
5. Validation Script (validate-plugins.mjs)

**6 Gaps Identified:**
1. No unified skill index (164 skills but no single list)
2. No full-text search capability
3. Weak cross-references between docs/ and plugins/ spokes
4. Hidden category/keyword metadata (not exposed to users)
5. No skill-to-skill references across plugins
6. Plugin dependencies not visible

**6 Recommendations Provided:**
1. Create unified skill index (high priority)
2. Add cross-reference links between spokes
3. Generate machine-readable skill metadata index
4. Add category browsing to root CLAUDE.md
5. Document plugin dependencies
6. Enhance skill trigger phrases

**Commit:** d988e15