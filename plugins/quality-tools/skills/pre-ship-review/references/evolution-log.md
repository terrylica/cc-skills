**Skill**: [Pre-Ship Review](../SKILL.md)

# Evolution Log

Reverse chronological record of changes to the pre-ship-review skill.

---

## 2026-02-09: Initial creation

- Created pre-ship-review skill based on analysis of 15 real review issues from alpha-forge PR #135
- 9 anti-pattern categories identified, 8 universal (project-agnostic)
- Three-phase structure: external tools (Pyright, Vulture, import-linter, deptry, Semgrep, Griffe) -> cc-skills orchestration (code-hardcode-audit, dead-code-detector, pr-gfm-validator) -> human judgment (7 checks)
- TodoWrite templates for 3 ship types: new feature, bug fix, refactoring
- Tool install guide with graceful degradation when tools are missing
- Anti-pattern catalog with detection heuristics and fix approaches
