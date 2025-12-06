---
status: accepted
date: 2025-12-05
decision-maker: terrylica
consulted: Claude Code (12-agent DCTL audit)
research-method: Web research + local codebase analysis
clarification-iterations: 3
perspectives:
  - EcosystemArtifact
  - DeveloperExperience
---

# Centralized Version Management with semantic-release-replace-plugin

## Context and Problem Statement

The cc-skills repository has version information scattered across 4 files with 8 total version fields. The current sed-based approach for version synchronization during releases has several problems:

1. **Platform-specific syntax**: `sed -i ''` is macOS-specific; Linux requires `sed -i`
2. **Greedy matching**: Pattern `"version": "[^"]*"` matches ALL version fields indiscriminately
3. **No validation**: Silent failures if pattern doesn't match
4. **Version drift**: package.json frozen at 1.0.0 while plugin.json is at 2.4.0
5. **Template risk**: Could accidentally corrupt template files with placeholder versions

## Research Summary

### Web Research Findings

1. **semantic-release-replace-plugin** (Google-backed): Purpose-built for multi-file version sync with validation
2. **@semantic-release/npm pkgRoot**: Can run multiple times but only for package.json files
3. **Changesets**: Overkill for monolithic versioning (designed for independent package versioning)
4. **jq-based scripts**: More robust than sed but still bespoke

### Local Codebase Analysis

**Files requiring version sync (SYNC):**

- `plugin.json` (1 field) - Source of truth
- `package.json` (1 field) - Currently frozen at 1.0.0
- `.claude-plugin/plugin.json` (1 field)
- `.claude-plugin/marketplace.json` (5 fields - root + 4 plugins)

**Files to protect (DO NOT SYNC):**

- `plugins/itp/skills/semantic-release/assets/templates/package.json` (0.0.0-development)
- `plugins/itp/skills/semantic-release/assets/templates/shareable-config/package.json` (1.0.0)

## Decision Log

| Question                | Answer                          | Rationale                                       |
| ----------------------- | ------------------------------- | ----------------------------------------------- |
| Sync package.json?      | Yes                             | Aligns with npm ecosystem standard; fixes drift |
| Which replacement tool? | semantic-release-replace-plugin | Idiomatic, validated, Google-backed             |
| Template protection?    | Explicit file targeting         | Simpler than regex exclusions                   |

## Considered Options

1. **Keep sed, add package.json** - Minimal change but retains fragility
2. **Switch to jq** - More robust but still bespoke
3. **semantic-release-replace-plugin** - Idiomatic with built-in validation
4. **Changesets** - Overkill for monolithic versioning

## Decision Outcome

**Chosen option**: semantic-release-replace-plugin

### Implementation

Replace @semantic-release/exec sed commands with declarative replace-plugin configuration:

```yaml
- - "semantic-release-replace-plugin"
  - replacements:
      - files: ["plugin.json"]
        from: "\"version\": \"[0-9]+\\.[0-9]+\\.[0-9]+\""
        to: '"version": "${nextRelease.version}"'
        countMatches: true
        results:
          - file: plugin.json
            hasChanged: true
            numMatches: 1
            numReplacements: 1
      # ... (similar for other 3 files)
```

### Positive Consequences

- Cross-platform compatible (no macOS-specific syntax)
- Built-in validation via `results` array
- Explicit file targeting protects templates
- Declarative YAML config vs shell commands
- Part of official semantic-release ecosystem

### Negative Consequences

- Additional npm dependency (semantic-release-replace-plugin)
- Slightly more verbose configuration
- Learning curve for results validation syntax

## Architecture

```
+-------------------+     semantic-release      +---------------------+
|   Git Commits     | ───────────────────────▶ |  Version Determined |
+-------------------+     analyzeCommits        +----------┬----------+
                                                           │
                                                           ▼
+-------------------+     replace-plugin        +---------------------+
|   4 JSON Files    | ◀─────────────────────── |  ${nextRelease}     |
|                   |     with validation       |                     |
| plugin.json (1)   |                          | results: numMatches |
| package.json (1)  |                          +---------------------+
| .claude-plugin/   |
|   plugin.json (1) |                          +---------------------+
|   marketplace (5) | ◀──────────────────────▶ |  @semantic-release/ |
+-------------------+     @semantic-release/    |        git          |
                              git commit        +---------------------+
```

## More Information

- [semantic-release-replace-plugin on GitHub](https://github.com/jpoehnelt/semantic-release-replace-plugin)
- [Official semantic-release Plugins List](https://semantic-release.gitbook.io/semantic-release/extending/plugins-list)
- [semantic-release FAQ](https://semantic-release.gitbook.io/semantic-release/support/faq)
