## [9.18.1](https://github.com/terrylica/cc-skills/compare/v9.18.0...v9.18.1) (2026-01-10)


### Bug Fixes

* **git-account-validator:** use correct PreToolUse JSON output format ([1538806](https://github.com/terrylica/cc-skills/commit/15388066005e247e70c510bc7497664ae1c32f31))
* **git-account-validator:** validate active gh account matches GH_ACCOUNT ([6c2f347](https://github.com/terrylica/cc-skills/commit/6c2f347d12e9f43a7604d24c297149d60938336d)), closes [#4](https://github.com/terrylica/cc-skills/issues/4)

# [9.18.0](https://github.com/terrylica/cc-skills/compare/v9.17.1...v9.18.0) (2026-01-10)


### Features

* **statusline-tools:** add asciinema cast file reference to statusline ([d8b71a4](https://github.com/terrylica/cc-skills/commit/d8b71a422fbd336156fdc4999cfadc557a81940b))

## [9.17.1](https://github.com/terrylica/cc-skills/compare/v9.17.0...v9.17.1) (2026-01-10)

# [9.17.0](https://github.com/terrylica/cc-skills/compare/v9.16.0...v9.17.0) (2026-01-10)


### Features

* **statusline-tools:** add session UUID chain display with lineage tracing ([871372e](https://github.com/terrylica/cc-skills/commit/871372ec54e10111ed1897636e04423b286dfdb1))

# [9.16.0](https://github.com/terrylica/cc-skills/compare/v9.15.0...v9.16.0) (2026-01-10)


### Features

* **itp-hooks:** add universal version SSoT guard ([76feea6](https://github.com/terrylica/cc-skills/commit/76feea65e1eef827bece446852d281ede5ecd803))

# [9.15.0](https://github.com/terrylica/cc-skills/compare/v9.14.0...v9.15.0) (2026-01-08)


### Bug Fixes

* **semantic-release:** avoid shell history expansion in verifyConditionsCmd ([1178c9f](https://github.com/terrylica/cc-skills/commit/1178c9fff69896240ee1b43f02790eebc19e100e))
* **semantic-release:** prevent release workflow hiccups ([cc6296f](https://github.com/terrylica/cc-skills/commit/cc6296f01cb34e6416784191b639b5f8dcec599b))


### Features

* **ralph:** add activation-gated bash wrappers for hooks ([c92bbdb](https://github.com/terrylica/cc-skills/commit/c92bbdb8a179dd9d15257fa090058dfd35d4ca86))
* **semantic-release:** add mise env loading to preflight verifyConditions ([36a90f7](https://github.com/terrylica/cc-skills/commit/36a90f73969880e8bd6ef3203e720706417a99a1))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/SKILL.md) - updated (+1/-1)

</details>


### Skill References

<details>
<summary><strong>itp/semantic-release</strong> (1 file)</summary>

- [Local Release Workflow (Canonical)](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/local-release-workflow.md) - updated (+44/-9)

</details>

# [9.14.0](https://github.com/terrylica/cc-skills/compare/v9.13.0...v9.14.0) (2026-01-08)


### Features

* **statusline-tools:** add session UUID as third line in status output ([01e3846](https://github.com/terrylica/cc-skills/commit/01e38467f5484ee7e7a6197a2601d91e162c71d2))





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [statusline-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/README.md) - updated (+17/-1)

# [9.13.0](https://github.com/terrylica/cc-skills/compare/v9.12.1...v9.13.0) (2026-01-05)


### Features

* **semantic-release:** add gh CLI workflow scope validation to preflight ([ecee9dd](https://github.com/terrylica/cc-skills/commit/ecee9ddff34e2576197fa922c7af8446fc99b99e))





---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>itp/semantic-release</strong> (1 file)</summary>

- [Local Release Workflow (Canonical)](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/local-release-workflow.md) - updated (+28)

</details>

## [9.12.1](https://github.com/terrylica/cc-skills/compare/v9.12.0...v9.12.1) (2026-01-05)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/SKILL.md) - updated (+2)

</details>


### Skill References

<details>
<summary><strong>itp/semantic-release</strong> (1 file)</summary>

- [Rust Projects with release-plz](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/rust-release-plz.md) - new (+263)

</details>

# [9.12.0](https://github.com/terrylica/cc-skills/compare/v9.11.3...v9.12.0) (2026-01-05)


### Bug Fixes

* **session-chronicle:** update 1Password credentials to Claude Automation vault ([87f0cd7](https://github.com/terrylica/cc-skills/commit/87f0cd7920d13f9dea7352e4a439126388a02f44))


### Features

* **itp:** add standalone /itp:release command ([88a4357](https://github.com/terrylica/cc-skills/commit/88a4357d3ac1527ba3dbf57c08ee63eb0c21653f))
* **itp:** wire /itp:release command to semantic-release skill ([f6f0797](https://github.com/terrylica/cc-skills/commit/f6f07979bec1099b421013026178504b3d597640))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| accepted | [Session Chronicle S3 Artifact Sharing](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-02-session-chronicle-s3-sharing.md) | updated (+3/-3) |

### Design Specs

- [Design Spec: Session-Chronicle S3 Artifact Sharing](https://github.com/terrylica/cc-skills/blob/main/docs/design/2026-01-02-session-chronicle-s3-sharing/spec.md) - updated (+13/-13)

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [session-chronicle](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/SKILL.md) - updated (+2/-2)

</details>


### Skill References

<details>
<summary><strong>devops-tools/session-chronicle</strong> (1 file)</summary>

- [S3 Artifact Retrieval Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/references/s3-retrieval-guide.md) - updated (+9/-9)

</details>


### Commands

<details>
<summary><strong>itp</strong> (1 command)</summary>

- [/itp:release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/release.md) - new (+137)

</details>

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Config](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/config.md) - updated (-22)

</details>


## Other Documentation

### Other

- [ralph-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/ralph-unified.md) - updated (-16)
- [Ralph Mental Model for Alpha-Forge](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/MENTAL-MODEL.md) - updated (+13/-16)

## [9.11.3](https://github.com/terrylica/cc-skills/compare/v9.11.2...v9.11.3) (2026-01-04)


### Bug Fixes

* **session-chronicle:** migrate S3 bucket and credentials to company account ([23d480a](https://github.com/terrylica/cc-skills/commit/23d480ad3ba783def375c75869bfc167c81d637c))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| accepted | [Session Chronicle S3 Artifact Sharing](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-02-session-chronicle-s3-sharing.md) | updated (+15) |

### Design Specs

- [Design Spec: Session-Chronicle S3 Artifact Sharing](https://github.com/terrylica/cc-skills/blob/main/docs/design/2026-01-02-session-chronicle-s3-sharing/spec.md) - updated (+28/-28)

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [session-chronicle](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/SKILL.md) - updated (+16/-16)

</details>


### Skill References

<details>
<summary><strong>devops-tools/session-chronicle</strong> (1 file)</summary>

- [S3 Artifact Retrieval Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/references/s3-retrieval-guide.md) - updated (+16/-16)

</details>


## Other Documentation

### Other

- [Post-Implementation Audit Report](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/tests/AUDIT-REPORT-2026-01-02.md) - updated (+5)

## [9.11.2](https://github.com/terrylica/cc-skills/compare/v9.11.1...v9.11.2) (2026-01-04)


### Bug Fixes

* **semantic-release:** use correct -q flag for git update-index ([05c8e58](https://github.com/terrylica/cc-skills/commit/05c8e58326b269599da36e047341738c36bff853))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/SKILL.md) - updated (+1/-1)

</details>


### Skill References

<details>
<summary><strong>itp/semantic-release</strong> (1 file)</summary>

- [Local Release Workflow (Canonical)](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/local-release-workflow.md) - updated (+2/-2)

</details>

## [9.11.1](https://github.com/terrylica/cc-skills/compare/v9.11.0...v9.11.1) (2026-01-04)


### Bug Fixes

* **semantic-release:** add git cache clearing to preflight ([00ef67f](https://github.com/terrylica/cc-skills/commit/00ef67fbc07c231d1a292e66459ee6ad5925f21c))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/SKILL.md) - updated (+6/-3)

</details>


### Skill References

<details>
<summary><strong>itp/semantic-release</strong> (1 file)</summary>

- [Local Release Workflow (Canonical)](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/local-release-workflow.md) - updated (+20/-4)

</details>

# [9.11.0](https://github.com/terrylica/cc-skills/compare/v9.10.4...v9.11.0) (2026-01-04)


### Features

* **gh-tools:** add WebFetch enforcement hook for GitHub CLI preference ([9ea4427](https://github.com/terrylica/cc-skills/commit/9ea4427904c1edabd93ac97341382387ca266830)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools)





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| accepted | [Session Chronicle S3 Artifact Sharing](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-02-session-chronicle-s3-sharing.md) | updated (+5/-5) |
| unknown | [gh-tools WebFetch Enforcement Hook](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-03-gh-tools-webfetch-enforcement.md) | new (+137) |

### Design Specs

- [Design Spec: Session-Chronicle S3 Artifact Sharing](https://github.com/terrylica/cc-skills/blob/main/docs/design/2026-01-02-session-chronicle-s3-sharing/spec.md) - updated (+26/-26)

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [session-chronicle](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/SKILL.md) - updated (+63/-7)

</details>


### Plugin READMEs

- [gh-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/README.md) - updated (+42/-4)

### Skill References

<details>
<summary><strong>devops-tools/session-chronicle</strong> (1 file)</summary>

- [S3 Artifact Retrieval Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/references/s3-retrieval-guide.md) - updated (+10/-10)

</details>


### Commands

<details>
<summary><strong>gh-tools</strong> (1 command)</summary>

- [gh-tools Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/commands/hooks.md) - new (+84)

</details>


## Other Documentation

### Other

- [Post-Implementation Audit Report](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/tests/AUDIT-REPORT-2026-01-02.md) - updated (+5/-5)

## [9.10.4](https://github.com/terrylica/cc-skills/compare/v9.10.3...v9.10.4) (2026-01-03)


### Bug Fixes

* **docs:** regenerate diagrams using graph-easy skill properly ([0711f1c](https://github.com/terrylica/cc-skills/commit/0711f1cf70aa83603cb096d8b89e0578d8c615b0))





---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>devops-tools/session-chronicle</strong> (1 file)</summary>

- [S3 Artifact Retrieval Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/references/s3-retrieval-guide.md) - updated (+8/-13)

</details>

<details>
<summary><strong>itp/semantic-release</strong> (1 file)</summary>

- [Local Release Workflow (Canonical)](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/local-release-workflow.md) - updated (+6/-13)

</details>

## [9.10.3](https://github.com/terrylica/cc-skills/compare/v9.10.2...v9.10.3) (2026-01-03)





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| accepted | [Centralized Version Management with @semantic-release/exec](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-05-centralized-version-management.md) | coupled |

### Design Specs

- [Design Spec: Centralized Version Management](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-05-centralized-version-management/spec.md) - updated (+13/-7)

## Plugin Documentation

### Skill References

<details>
<summary><strong>devops-tools/session-chronicle</strong> (1 file)</summary>

- [S3 Artifact Retrieval Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/references/s3-retrieval-guide.md) - updated (+28)

</details>

<details>
<summary><strong>itp/semantic-release</strong> (1 file)</summary>

- [Local Release Workflow (Canonical)](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/local-release-workflow.md) - updated (+38/-1)

</details>


## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+1/-1)

## [9.10.2](https://github.com/terrylica/cc-skills/compare/v9.10.1...v9.10.2) (2026-01-03)


### Bug Fixes

* **session-chronicle:** use Claude Automation vault for AWS credentials ([01f527f](https://github.com/terrylica/cc-skills/commit/01f527fd94886c4faad132438329414b384e91e4))





---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>devops-tools/session-chronicle</strong> (1 file)</summary>

- [S3 Artifact Retrieval Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/references/s3-retrieval-guide.md) - updated (+9/-9)

</details>

## [9.10.1](https://github.com/terrylica/cc-skills/compare/v9.10.0...v9.10.1) (2026-01-03)


### Bug Fixes

* **session-chronicle:** support 1Password biometric desktop app integration ([e37db06](https://github.com/terrylica/cc-skills/commit/e37db06d7d09a048d82080ade56eb04f0e02a5a5))

# [9.10.0](https://github.com/terrylica/cc-skills/compare/v9.9.3...v9.10.0) (2026-01-03)


### Bug Fixes

* **session-chronicle:** eliminate all silent failures in embedded scripts ([1e1bfd0](https://github.com/terrylica/cc-skills/commit/1e1bfd0d47d93038792a98a3857c9f99b3671905))


### Features

* **session-chronicle:** enforce complete session recording with AskUserQuestion flows ([bdaab73](https://github.com/terrylica/cc-skills/commit/bdaab73be0dad0d629226cc7d3fb350b8db84aba))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [session-chronicle](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/SKILL.md) - updated (+446/-311)

</details>

## [9.9.3](https://github.com/terrylica/cc-skills/compare/v9.9.2...v9.9.3) (2026-01-03)


### Bug Fixes

* **semantic-release:** simplify post-release verification, remove complex jq check ([a6e48c9](https://github.com/terrylica/cc-skills/commit/a6e48c9a03135e47f7bae8acdbe6b913b5b51dd5))

## [9.9.2](https://github.com/terrylica/cc-skills/compare/v9.9.1...v9.9.2) (2026-01-03)


### Bug Fixes

* **semantic-release:** fix jq quoting issue in installed_plugins.json check ([ef83d9c](https://github.com/terrylica/cc-skills/commit/ef83d9ce6e5cf649a57413ae82f5b174ab41deef))

## [9.9.1](https://github.com/terrylica/cc-skills/compare/v9.9.0...v9.9.1) (2026-01-03)


### Bug Fixes

* **semantic-release:** make post-release plugin verification fully automated ([d92e542](https://github.com/terrylica/cc-skills/commit/d92e542690a6aed3db026de06e6c08957329cb8b))

# [9.9.0](https://github.com/terrylica/cc-skills/compare/v9.8.1...v9.9.0) (2026-01-03)


### Features

* **semantic-release:** add post-release plugin cache verification ([2fd5893](https://github.com/terrylica/cc-skills/commit/2fd5893fb6d60b32ce8a52791866ecfe7324d4ab))

## [9.8.1](https://github.com/terrylica/cc-skills/compare/v9.8.0...v9.8.1) (2026-01-03)


### Bug Fixes

* **ralph:** make /ralph:stop execute bash script instead of summarizing ([78860de](https://github.com/terrylica/cc-skills/commit/78860dec665ddaa635f34f220fda0fe4fec06fe4))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Stop](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/stop.md) - updated (+2/-4)

</details>

# [9.8.0](https://github.com/terrylica/cc-skills/compare/v9.7.0...v9.8.0) (2026-01-03)


### Bug Fixes

* **ralph:** simplify global stop signal handling for cross-session reliability ([07212be](https://github.com/terrylica/cc-skills/commit/07212bed087599f81cc3ad054b2abfff959e9f90))


### Features

* **semantic-release:** add MAJOR version confirmation with multi-perspective analysis ([0d660f8](https://github.com/terrylica/cc-skills/commit/0d660f842acdfa10ae35a3f96f2805157f3d1915))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/SKILL.md) - updated (+222)

</details>


### Skill References

<details>
<summary><strong>itp/semantic-release</strong> (1 file)</summary>

- [Local Release Workflow (Canonical)](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/local-release-workflow.md) - updated (+109/-1)

</details>


## Other Documentation

### Other

- [Post-Implementation Audit Report](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/tests/AUDIT-REPORT-2026-01-02-MAJOR-CONFIRMATION.md) - new (+166)

# [9.7.0](https://github.com/terrylica/cc-skills/compare/v9.6.5...v9.7.0) (2026-01-02)


### Features

* **ralph:** add --remove flag to /ralph:encourage and /ralph:forbid ([57f1180](https://github.com/terrylica/cc-skills/commit/57f118070356f362c3316e0815dc6191e532b182))
* **session-chronicle:** add S3 artifact sharing with Brotli compression ([34f0082](https://github.com/terrylica/cc-skills/commit/34f0082fd602e186541df385b55bc2e5b5de71d7))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| accepted | [Ralph Guidance Freshness Detection](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-02-ralph-guidance-freshness-detection.md) | updated (+27/-1) |
| accepted | [Session Chronicle S3 Artifact Sharing](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-02-session-chronicle-s3-sharing.md) | new (+260) |

### Design Specs

- [Diagnosis: /ralph:encourage → Stop Hook Data Flow](https://github.com/terrylica/cc-skills/blob/main/docs/design/2026-01-02-ralph-guidance-freshness-detection/spec.md) - coupled
- [Design Spec: Session-Chronicle S3 Artifact Sharing](https://github.com/terrylica/cc-skills/blob/main/docs/design/2026-01-02-session-chronicle-s3-sharing/spec.md) - new (+443)

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [session-chronicle](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/SKILL.md) - updated (+107/-55)

</details>


### Plugin READMEs

- [devops-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/README.md) - updated (+14)
- [Ralph Plugin for Claude Code](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/README.md) - updated (+6/-4)

### Skill References

<details>
<summary><strong>devops-tools/session-chronicle</strong> (1 file)</summary>

- [S3 Artifact Retrieval Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/references/s3-retrieval-guide.md) - new (+167)

</details>


### Commands

<details>
<summary><strong>ralph</strong> (3 commands)</summary>

- [Ralph Loop: Config](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/config.md) - updated (+3/-1)
- [Ralph Loop: Encourage](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/encourage.md) - updated (+106/-2)
- [Ralph Loop: Forbid](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/forbid.md) - updated (+106/-2)

</details>


## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+4)

## Other Documentation

### Other

- [Post-Implementation Audit Report](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/tests/AUDIT-REPORT-2026-01-02.md) - new (+170)
- [Session Chronicle Tests](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/tests/README.md) - new (+74)
- [Getting Started with Ralph (First-Time Users)](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/GETTING-STARTED.md) - updated (+15/-11)

## [9.6.5](https://github.com/terrylica/cc-skills/compare/v9.6.4...v9.6.5) (2026-01-02)


### Bug Fixes

* **ralph:** handle cross-session race condition in /ralph:stop ([9ad8190](https://github.com/terrylica/cc-skills/commit/9ad81905a9da2e8d58a8f0853e20254c190cc216))

## [9.6.4](https://github.com/terrylica/cc-skills/compare/v9.6.3...v9.6.4) (2026-01-02)


### Bug Fixes

* **ralph:** add guidance freshness detection with on-the-fly constraint scanning ([3a4bda7](https://github.com/terrylica/cc-skills/commit/3a4bda7f3e15f546a484b81e7421da8a3b220b4d))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| accepted | [Ralph Guidance Freshness Detection](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-02-ralph-guidance-freshness-detection.md) | new (+268) |

### Design Specs

- [Diagnosis: /ralph:encourage → Stop Hook Data Flow](https://github.com/terrylica/cc-skills/blob/main/docs/design/2026-01-02-ralph-guidance-freshness-detection/spec.md) - new (+718)

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (3 commands)</summary>

- [Ralph Loop: Encourage](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/encourage.md) - updated (+5/-2)
- [Ralph Loop: Forbid](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/forbid.md) - updated (+5/-2)
- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+31/-3)

</details>

## [9.6.3](https://github.com/terrylica/cc-skills/compare/v9.6.2...v9.6.3) (2026-01-01)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>ralph</strong> (1 change)</summary>

- [session-guidance](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/skills/session-guidance/SKILL.md) - new (+439)

</details>


### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+12/-386)

</details>

## [9.6.2](https://github.com/terrylica/cc-skills/compare/v9.6.1...v9.6.2) (2026-01-01)


### Bug Fixes

* **ralph:** add proper YAML frontmatter and Skill tool invocation ([29a1530](https://github.com/terrylica/cc-skills/commit/29a15308f074b6f3f7f9a768acc77e88fb9a6f61))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>ralph</strong> (1 change)</summary>

- [constraint-discovery](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/skills/constraint-discovery/SKILL.md) - updated (+10/-1)

</details>


### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+1/-3)

</details>

## [9.6.1](https://github.com/terrylica/cc-skills/compare/v9.6.0...v9.6.1) (2026-01-01)


### Bug Fixes

* **session-chronicle:** extract FULL session chains, not fixed windows ([0599d35](https://github.com/terrylica/cc-skills/commit/0599d359e2e858adac7a17c12ba05e91bb405f54))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [session-chronicle](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/SKILL.md) - updated (+56/-15)

</details>

<details>
<summary><strong>ralph</strong> (1 change)</summary>

- [Constraint Discovery Skill](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/skills/constraint-discovery/SKILL.md) - new (+222)

</details>


### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+11/-175)

</details>

# [9.6.0](https://github.com/terrylica/cc-skills/compare/v9.5.2...v9.6.0) (2026-01-01)


### Features

* **devops-tools:** add session-chronicle skill for session archaeology ([56fb64f](https://github.com/terrylica/cc-skills/commit/56fb64fedfd5001b08c99bf567a930412a3465d7))
* **ralph:** add unlimited @ link following to Explore agents ([7128e44](https://github.com/terrylica/cc-skills/commit/7128e4438df82e9b0411c75b3e037d868975b7d1))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [session-chronicle](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/SKILL.md) - new (+489)

</details>


### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+67/-21)

</details>

## [9.5.2](https://github.com/terrylica/cc-skills/compare/v9.5.1...v9.5.2) (2026-01-01)


### Bug Fixes

* **ralph:** add blocking gate for agent results and deep-dive prompts ([ff354ea](https://github.com/terrylica/cc-skills/commit/ff354ea48e31ecc8c15d8c71479742191099c759))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+110/-32)

</details>

## [9.5.1](https://github.com/terrylica/cc-skills/compare/v9.5.0...v9.5.1) (2026-01-01)


### Bug Fixes

* **ralph:** make Step 1.4.5 Explore agents MANDATORY with explicit Task syntax ([60303fe](https://github.com/terrylica/cc-skills/commit/60303febcee19fa83804c82c716e60a65d51721a))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+135/-126)

</details>

# [9.5.0](https://github.com/terrylica/cc-skills/compare/v9.4.7...v9.5.0) (2026-01-01)


### Features

* **ralph:** add Explore-based constraint discovery to /ralph:start ([2274f96](https://github.com/terrylica/cc-skills/commit/2274f96642ccf462d0aa6a506cbd2ce70ece9933))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+115)

</details>


## Other Documentation

### Other

- [Explore Agent Integration: Architecture Diagrams](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/docs/EXPLORE-AGENT-ARCHITECTURE.md) - new (+615)
- [Explore Agent Integration for Ralph: Complete Design Package](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/docs/EXPLORE-AGENT-DESIGN-COMPLETE.md) - new (+380)
- [Explore Agent Integration: Implementation Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/docs/EXPLORE-AGENT-IMPLEMENTATION.md) - new (+989)
- [Explore Agent Integration: Complete Design Index](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/docs/EXPLORE-AGENT-INDEX.md) - new (+399)
- [Explore Agent Integration Design for Ralph](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/docs/EXPLORE-AGENT-INTEGRATION-DESIGN.md) - new (+589)
- [Ralph Explore Agent Prompts](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/docs/EXPLORE-AGENT-PROMPTS.md) - new (+419)
- [Explore Agent Integration: Executive Summary](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/docs/EXPLORE-AGENT-SUMMARY.md) - new (+461)
- [Ralph Explore Agent Prompts - Real Examples](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/docs/EXPLORE-EXAMPLES.md) - new (+445)
- [Ralph Explore Agent Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/docs/EXPLORE-GUIDE.md) - new (+237)
- [Ralph Explore Agents - Complete Documentation Index](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/docs/EXPLORE-INDEX.md) - new (+382)
- [Ralph Explore Prompts - Quick Reference Card](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/docs/EXPLORE-REFERENCE.md) - new (+268)

## [9.4.7](https://github.com/terrylica/cc-skills/compare/v9.4.6...v9.4.7) (2026-01-01)


### Bug Fixes

* **ralph:** wire constraint scan results to AskUserQuestion flows ([da8e1c9](https://github.com/terrylica/cc-skills/commit/da8e1c9591d5063384ba6ad8ffff91c091b5f1a6))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+226/-59)

</details>

## [9.4.6](https://github.com/terrylica/cc-skills/compare/v9.4.5...v9.4.6) (2025-12-31)


### Bug Fixes

* **ralph:** batch gitignore check using --stdin for performance ([d076dfb](https://github.com/terrylica/cc-skills/commit/d076dfb2adc4a13500bb1572cd1d06a8d3174b0f))

## [9.4.5](https://github.com/terrylica/cc-skills/compare/v9.4.4...v9.4.5) (2025-12-31)


### Bug Fixes

* **ralph:** suppress uv DEBUG output in constraint scanner ([2de7201](https://github.com/terrylica/cc-skills/commit/2de72014caabb1b33f8f7425686b2923935c3dc1))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+1/-1)

</details>

## [9.4.4](https://github.com/terrylica/cc-skills/compare/v9.4.3...v9.4.4) (2025-12-31)


### Bug Fixes

* **ralph:** robust uv discovery for mise-installed environments ([a969fe6](https://github.com/terrylica/cc-skills/commit/a969fe6d624abbdd8096c6e74d85d20538faeea5))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+103/-11)

</details>

## [9.4.3](https://github.com/terrylica/cc-skills/compare/v9.4.2...v9.4.3) (2025-12-31)





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| unknown | [asciinema-tools Daemon Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-26-asciinema-daemon-architecture.md) | updated (+15/-4) |

## Plugin Documentation

### Skill References

<details>
<summary><strong>asciinema-tools/asciinema-streaming-backup</strong> (1 file)</summary>

- [Idle Chunker Script (DEPRECATED)](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/references/idle-chunker.md) - updated (+10/-3)

</details>

## [9.4.2](https://github.com/terrylica/cc-skills/compare/v9.4.1...v9.4.2) (2025-12-31)


### Bug Fixes

* emit errors to stderr and fix shellcheck warnings ([315806a](https://github.com/terrylica/cc-skills/commit/315806a2c794d1d210dca4a11233f05ae6c0c1cd))

## [9.4.1](https://github.com/terrylica/cc-skills/compare/v9.4.0...v9.4.1) (2025-12-31)


### Bug Fixes

* **asciinema-tools:** improve daemon-setup robustness and remove leaked data ([0b2e2cf](https://github.com/terrylica/cc-skills/commit/0b2e2cf680b3e083b89bc874dc31ef10f8a0354f))
* **iterm2-layout:** generalize worktree examples in documentation ([d070f32](https://github.com/terrylica/cc-skills/commit/d070f32811525b5d0656540bed0a7cd7093336ee))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>iterm2-layout-config</strong> (1 change)</summary>

- [iterm2-layout](https://github.com/terrylica/cc-skills/blob/main/plugins/iterm2-layout-config/skills/iterm2-layout/SKILL.md) - updated (+5/-5)

</details>


### Commands

<details>
<summary><strong>asciinema-tools</strong> (1 command)</summary>

- [/asciinema-tools:daemon-setup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-setup.md) - updated (+27/-5)

</details>

# [9.4.0](https://github.com/terrylica/cc-skills/compare/v9.3.6...v9.4.0) (2025-12-31)


### Features

* **asciinema-tools:** add finalize and summarize commands for complete post-session workflow ([79b4101](https://github.com/terrylica/cc-skills/commit/79b41019ef7a06edec9bfb6ca47b5d496146ae4b))





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [Git-Town Workflow Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/README.md) - new (+105)

### Commands

<details>
<summary><strong>asciinema-tools</strong> (4 commands)</summary>

- [/asciinema-tools:daemon-status](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-status.md) - updated (+110/-61)
- [/asciinema-tools:finalize](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/finalize.md) - new (+255)
- [/asciinema-tools:post-session](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/post-session.md) - updated (+164/-28)
- [/asciinema-tools:summarize](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/summarize.md) - new (+239)

</details>

<details>
<summary><strong>git-town-workflow</strong> (4 commands)</summary>

- [Git-Town Contribution Workflow — STOP AND READ](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/commands/contribute.md) - new (+436)
- [Git-Town Fork Workflow — STOP AND READ](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/commands/fork.md) - new (+447)
- [Git-Town Enforcement Hooks — Installation](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/commands/hooks.md) - new (+228)
- [Git-Town Setup — One-Time Configuration](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/commands/setup.md) - new (+255)

</details>


## Other Documentation

### Other

- [Git-Town Command Cheatsheet](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/references/cheatsheet.md) - new (+126)

## [9.3.6](https://github.com/terrylica/cc-skills/compare/v9.3.5...v9.3.6) (2025-12-30)


### Bug Fixes

* **ralph:** add UV detection with loud validation failure ([a3f18d0](https://github.com/terrylica/cc-skills/commit/a3f18d0a9331fe6ffce84b09b5de5f3c48869a8e))

## [9.3.5](https://github.com/terrylica/cc-skills/compare/v9.3.4...v9.3.5) (2025-12-30)


### Bug Fixes

* **ralph:** expand hook install descriptions ([ef134fc](https://github.com/terrylica/cc-skills/commit/ef134fc313f9eb18b8cbd13e7a0aded2229e668b))

## [9.3.4](https://github.com/terrylica/cc-skills/compare/v9.3.3...v9.3.4) (2025-12-30)


### Bug Fixes

* **ralph:** remove RSSI branding throughout codebase ([cee1bc8](https://github.com/terrylica/cc-skills/commit/cee1bc8af6b089c500a1875e3de49a9fdb02655b))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| accepted | [Ralph Eternal Loop Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-20-ralph-rssi-eternal-loop.md) | updated (+33/-33) |
| unknown | [Ralph Stop Visibility Observability](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-22-ralph-stop-visibility-observability.md) | updated (+2/-2) |
| unknown | [Ralph Constraint Scanning](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-29-ralph-constraint-scanning.md) | updated (+1/-1) |

### Design Specs

- [Design Spec: Ralph Eternal Loop Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-20-ralph-rssi-eternal-loop/spec.md) - updated (+10/-10)

## Plugin Documentation

### Plugin READMEs

- [Ralph Plugin for Claude Code](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/README.md) - updated (+29/-29)

### Commands

<details>
<summary><strong>ralph</strong> (3 commands)</summary>

- [Ralph Loop: Config](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/config.md) - updated (+5/-5)
- [Ralph Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/hooks.md) - updated (+1/-1)
- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+4/-4)

</details>


## Other Documentation

### Other

- [ralph-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/ralph-unified.md) - updated (+7/-7)
- [Ralph POC Validation Task](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/tests/poc-task.md) - updated (+3/-3)
- [Ralph Mental Model for Alpha-Forge](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/MENTAL-MODEL.md) - updated (+22/-22)

## [9.3.3](https://github.com/terrylica/cc-skills/compare/v9.3.2...v9.3.3) (2025-12-30)





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| accepted | [Ralph RSSI Eternal Loop Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-20-ralph-rssi-eternal-loop.md) | coupled |

### Design Specs

- [Design Spec: Ralph RSSI Eternal Loop Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-20-ralph-rssi-eternal-loop/spec.md) - updated (+42/-39)

## [9.3.2](https://github.com/terrylica/cc-skills/compare/v9.3.1...v9.3.2) (2025-12-30)


### Bug Fixes

* **ralph:** update test imports for RSSI → Ralph rename ([071fc02](https://github.com/terrylica/cc-skills/commit/071fc020e0dd6fdf9fd6802be5162be2d16bd190))

## [9.3.1](https://github.com/terrylica/cc-skills/compare/v9.3.0...v9.3.1) (2025-12-30)


### Bug Fixes

* **ralph:** correct version numbers in MENTAL-MODEL.md (v9.2.4 → v9.3.0) ([c366b7a](https://github.com/terrylica/cc-skills/commit/c366b7a282b3db924fdd2d93b65d7b2f5e60a482))


### Code Refactoring

* **ralph:** rename RSSI modules to Ralph naming convention ([17cab6e](https://github.com/terrylica/cc-skills/commit/17cab6e5f6b09301490cb399871eb9194ddf3400))


### BREAKING CHANGES

* **ralph:** Users with existing state files should run
scripts/migrate-rssi-to-ralph.sh to preserve 99 iterations of learning.





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [Ralph Plugin for Claude Code](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/README.md) - updated (+1/-1)

### Commands

<details>
<summary><strong>ralph</strong> (2 commands)</summary>

- [Ralph Loop: Encourage](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/encourage.md) - updated (+1/-1)
- [Ralph Loop: Forbid](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/forbid.md) - updated (+1/-1)

</details>


## Other Documentation

### Other

- [ralph-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/ralph-unified.md) - renamed from `plugins/ralph/hooks/templates/rssi-unified.md`
- [Ralph Mental Model for Alpha-Forge](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/MENTAL-MODEL.md) - updated (+14/-14)

# [9.3.0](https://github.com/terrylica/cc-skills/compare/v9.2.3...v9.3.0) (2025-12-30)


### Features

* **ralph:** add dual-channel observability for hook operations ([52b717e](https://github.com/terrylica/cc-skills/commit/52b717e94c61ca49a31974d593173b0c4f771a0e))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+55/-2)

</details>


## Other Documentation

### Other

- [Ralph Mental Model for Alpha-Forge](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/MENTAL-MODEL.md) - updated (+203/-10)

## [9.2.3](https://github.com/terrylica/cc-skills/compare/v9.2.2...v9.2.3) (2025-12-30)


### Bug Fixes

* **ralph:** enhance MENTAL-MODEL.md with layman-friendly diagrams ([ff5d082](https://github.com/terrylica/cc-skills/commit/ff5d08233d7512a2fc078b70e4c9c4b5496cfd14))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| accepted | [Alpha-Forge Git Worktree Management System](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-14-alpha-forge-worktree-management.md) | updated (+57/-40) |
| accepted | [Ralph RSSI Eternal Loop Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-20-ralph-rssi-eternal-loop.md) | updated (+3/-1) |

### Design Specs

- [Alpha-Forge Git Worktree Management System - Implementation Spec](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-14-alpha-forge-worktree-management/spec.md) - coupled
- [Design Spec: Ralph RSSI Eternal Loop Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-20-ralph-rssi-eternal-loop/spec.md) - coupled

## Plugin Documentation

### Plugin READMEs

- [ITP Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/README.md) - updated (+57/-8)

## Other Documentation

### Other

- [Ralph Mental Model for Alpha-Forge](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/MENTAL-MODEL.md) - updated (+256/-7)
- [Test](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/tests/fixtures/repo_with_broken_links/README.md) - new (+3)
- [Test](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/tests/fixtures/repo_with_path_violations/README.md) - new (+3)
- [Sample Repo](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/tests/fixtures/sample_repo/README.md) - new (+1)

## [9.2.2](https://github.com/terrylica/cc-skills/compare/v9.2.1...v9.2.2) (2025-12-30)


### Bug Fixes

* **ralph:** install Bash PreToolUse hook for loop file protection ([54d61f1](https://github.com/terrylica/cc-skills/commit/54d61f1d8de46bf9e55ae1a01689121e72b4aeab))

## [9.2.1](https://github.com/terrylica/cc-skills/compare/v9.2.0...v9.2.1) (2025-12-30)


### Bug Fixes

* **ralph:** address adversarial audit findings for constraint scanner ([d7c5f5f](https://github.com/terrylica/cc-skills/commit/d7c5f5fd1ddd171c66f9c0147365a1bccc50f6b5))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (2 commands)</summary>

- [Ralph Loop: Config](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/config.md) - updated (+38/-7)
- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+118/-10)

</details>

# [9.2.0](https://github.com/terrylica/cc-skills/compare/v9.1.1...v9.2.0) (2025-12-30)


### Bug Fixes

* **statusline-tools:** move UTC time to line 2 with GitHub URL ([cc5dad9](https://github.com/terrylica/cc-skills/commit/cc5dad9878c1c9488e212a2a205887ce50aa5f1a))


### Features

* **ralph:** add constraint scanner with Pydantic v2 migration ([a340ef2](https://github.com/terrylica/cc-skills/commit/a340ef2cf16e01638b282ebd52f4c49a02808125))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| unknown | [Ralph Constraint Scanning](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-29-ralph-constraint-scanning.md) | new (+187) |

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+14/-2)

</details>


## Other Documentation

### Other

- [Ralph Mental Model for Alpha-Forge](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/MENTAL-MODEL.md) - updated (+90)

## [9.1.1](https://github.com/terrylica/cc-skills/compare/v9.1.0...v9.1.1) (2025-12-30)


### Bug Fixes

* **statusline-tools:** include date in local time display ([b92541b](https://github.com/terrylica/cc-skills/commit/b92541b0bd4a83c5a09af930facadf9ad33573e7))

# [9.1.0](https://github.com/terrylica/cc-skills/compare/v9.0.5...v9.1.0) (2025-12-30)


### Features

* **statusline-tools:** add local time after UTC in status line ([b551c01](https://github.com/terrylica/cc-skills/commit/b551c01a3ba6b78cb92c1ea820134b7a380a0dd5))

## [9.0.5](https://github.com/terrylica/cc-skills/compare/v9.0.4...v9.0.5) (2025-12-30)


### Bug Fixes

* **statusline-tools:** remove redundant branch display, fix worktree cache ([e649fa0](https://github.com/terrylica/cc-skills/commit/e649fa0d6874d4046e120bcf8e9a8e5df8c9d70d))

## [9.0.4](https://github.com/terrylica/cc-skills/compare/v9.0.3...v9.0.4) (2025-12-29)


### Bug Fixes

* **link-tools:** remove orphaned lib directory with dead code ([3dc3245](https://github.com/terrylica/cc-skills/commit/3dc3245294ba849c150996094abb8278dafbe22d))

## [9.0.3](https://github.com/terrylica/cc-skills/compare/v9.0.2...v9.0.3) (2025-12-29)





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [plugin-dev](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/README.md) - updated (+9)

### Skill References

<details>
<summary><strong>plugin-dev/skill-architecture</strong> (2 files)</summary>

- [Bash Compatibility for Skills](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/bash-compatibility.md) - updated (+6)
- [Scripts Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/scripts-reference.md) - updated (+19/-2)

</details>

## [9.0.2](https://github.com/terrylica/cc-skills/compare/v9.0.1...v9.0.2) (2025-12-29)


### Bug Fixes

* **plugin-dev:** add --project-local and --skip-bash flags to validate-skill ([79f37ce](https://github.com/terrylica/cc-skills/commit/79f37ce93220ac030914eba5fb1ce960a6b68df2))

## [9.0.1](https://github.com/terrylica/cc-skills/compare/v9.0.0...v9.0.1) (2025-12-29)


### Bug Fixes

* **statusline-tools:** exclude .claude/skills/ from lint-relative-paths ([8221474](https://github.com/terrylica/cc-skills/commit/822147479922f4d71f6f43838f715491fdd3b5d3))

# [9.0.0](https://github.com/terrylica/cc-skills/compare/v8.11.4...v9.0.0) (2025-12-29)


### Features

* **plugin-dev:** migrate skill validators from Python to Bun/TypeScript ([3b2623f](https://github.com/terrylica/cc-skills/commit/3b2623f34e91974ec6044432ea06e08654c762f9))


### BREAKING CHANGES

* **plugin-dev:** Python validators removed, use TypeScript equivalents

Migration:
- validate_skill.py → validate-skill.ts (11+ validation checks)
- validate_links.py → validate-links.ts (strict /docs/ policy)
- fix_bash_blocks.py → fix-bash-blocks.ts (auto heredoc wrapper)

New features:
- Stricter link policy: only /docs/adr/ and /docs/design/ allowed
- AST-based link extraction using marked + gray-matter
- AskUserQuestion JSON output for interactive mode
- Colored CLI output with ansis

Technical stack:
- Bun runtime with TypeScript
- marked v15 for markdown parsing
- gray-matter v4 for YAML frontmatter
- ansis v3 for terminal colors

All documentation references updated to new paths.





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| unknown | [Skill Bash Compatibility Enforcement](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-22-skill-bash-compatibility-enforcement.md) | updated (+2/-2) |

## Plugin Documentation

### Skills

<details>
<summary><strong>plugin-dev</strong> (1 change)</summary>

- [skill-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/SKILL.md) - updated (+6/-6)

</details>


### Plugin READMEs

- [plugin-dev](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/README.md) - updated (+9/-7)

### Skill References

<details>
<summary><strong>plugin-dev/skill-architecture</strong> (3 files)</summary>

- [Bash Compatibility for Skills](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/bash-compatibility.md) - updated (+8/-1)
- [Creation Workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/creation-workflow.md) - updated (+1/-1)
- [Scripts Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/scripts-reference.md) - updated (+31/-14)

</details>

## [8.11.4](https://github.com/terrylica/cc-skills/compare/v8.11.3...v8.11.4) (2025-12-29)


### Bug Fixes

* **statusline-tools:** skip skill directories in lint-relative-paths ([4b7067f](https://github.com/terrylica/cc-skills/commit/4b7067f75e3e5cc199104d361567d4d34821fd39))

## [8.11.3](https://github.com/terrylica/cc-skills/compare/v8.11.2...v8.11.3) (2025-12-29)


### Bug Fixes

* **docs:** correct broken internal links detected by lychee ([33febcc](https://github.com/terrylica/cc-skills/commit/33febcc1144ec75f7a104e2540a9de2903ac76eb))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| accepted | [Ralph RSSI Eternal Loop Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-20-ralph-rssi-eternal-loop.md) | updated (-1) |
| unknown | [Skill Bash Compatibility Enforcement](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-22-skill-bash-compatibility-enforcement.md) | updated (+1/-1) |

### Design Specs

- [Design Spec: Ralph RSSI Eternal Loop Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-20-ralph-rssi-eternal-loop/spec.md) - coupled

## Plugin Documentation

### Skills

<details>
<summary><strong>plugin-dev</strong> (1 change)</summary>

- [plugin-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/plugin-validator/SKILL.md) - updated (-1)

</details>


## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+1/-1)

## [8.11.2](https://github.com/terrylica/cc-skills/compare/v8.11.1...v8.11.2) (2025-12-29)


### Bug Fixes

* **ralph:** use full mise shims path for uv in stop hook ([02f47be](https://github.com/terrylica/cc-skills/commit/02f47be577c6c1a875d729f45c0795183b159288))

## [8.11.1](https://github.com/terrylica/cc-skills/compare/v8.11.0...v8.11.1) (2025-12-29)


### Bug Fixes

* **statusline-tools:** use --root-dir for lychee and document dependencies ([7ff56bf](https://github.com/terrylica/cc-skills/commit/7ff56bf697fde9080122922267680716417dc4ec))





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [statusline-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/README.md) - updated (+41/-7)

# [8.11.0](https://github.com/terrylica/cc-skills/compare/v8.10.2...v8.11.0) (2025-12-29)


### Bug Fixes

* **statusline-tools:** add --base flag to lychee for root-relative paths ([ec6e238](https://github.com/terrylica/cc-skills/commit/ec6e23819c64e8f86445f504e8cbf406cd3dab96))
* **statusline-tools:** add skills to exclude_dirs in lint-relative-paths ([80f0171](https://github.com/terrylica/cc-skills/commit/80f0171e75910a683edd0c04ccdf09231cb7bb72))
* **statusline-tools:** respect .gitignore in link validators ([c967003](https://github.com/terrylica/cc-skills/commit/c967003cf81b5d6e64fee79403081a978c674986))


### Features

* **doc-tools:** add terminal-print skill for iTerm2 output printing ([e3430f0](https://github.com/terrylica/cc-skills/commit/e3430f0528757488b65dcfbe407e9e24879c16d8))
* **dotfiles-tools:** add Stop hook for chezmoi sync enforcement ([a480025](https://github.com/terrylica/cc-skills/commit/a4800252848bf2eea5323ed4502af4a8327daf08))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>doc-tools</strong> (1 change)</summary>

- [terminal-print](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/terminal-print/SKILL.md) - new (+117)

</details>


### Plugin READMEs

- [doc-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/README.md) - updated (+2)
- [dotfiles-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/README.md) - updated (+44/-11)

### Skill References

<details>
<summary><strong>doc-tools/terminal-print</strong> (1 file)</summary>

- [Terminal Print Workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/terminal-print/references/workflow.md) - new (+125)

</details>

## [8.10.2](https://github.com/terrylica/cc-skills/compare/v8.10.1...v8.10.2) (2025-12-28)


### Bug Fixes

* **docs:** add fake-data-guard to command descriptions ([3e635f8](https://github.com/terrylica/cc-skills/commit/3e635f83cc29eacbfd1bf75d8e9652f003450cad))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>itp</strong> (1 command)</summary>

- [ITP Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/hooks.md) - updated (+6/-2)

</details>

<details>
<summary><strong>itp-hooks</strong> (1 command)</summary>

- [ITP Hooks Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/commands/setup.md) - updated (+11/-8)

</details>

## [8.10.1](https://github.com/terrylica/cc-skills/compare/v8.10.0...v8.10.1) (2025-12-28)


### Bug Fixes

* **itp-hooks:** update stale /itp-hooks:hooks reference to /itp:hooks ([2328fde](https://github.com/terrylica/cc-skills/commit/2328fde1a210241d07fef0de6667cd17d0559b36))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| implemented | [Universal Fake Data Guard PreToolUse Hook](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-27-fake-data-guard-universal.md) | coupled |

### Design Specs

- [Fake Data Guard Implementation Specification](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-27-fake-data-guard-universal/spec.md) - new (+260)

## Plugin Documentation

### Commands

<details>
<summary><strong>itp-hooks</strong> (1 command)</summary>

- [ITP Hooks Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/commands/setup.md) - updated (+1/-1)

</details>

# [8.10.0](https://github.com/terrylica/cc-skills/compare/v8.9.6...v8.10.0) (2025-12-28)


### Features

* **itp-hooks:** add fake data guard PreToolUse hook ([98a8eb1](https://github.com/terrylica/cc-skills/commit/98a8eb17a3ea6bfee30108bdcd6ae5d4c0e34775))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| implemented | [Universal Fake Data Guard PreToolUse Hook](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-27-fake-data-guard-universal.md) | new (+172) |

## Plugin Documentation

### Commands

<details>
<summary><strong>itp-hooks</strong> (1 command)</summary>

- [hooks](https://github.com/terrylica/cc-skills/blob/v8.9.6/plugins/itp-hooks/commands/hooks.md) - deleted

</details>

## [8.9.6](https://github.com/terrylica/cc-skills/compare/v8.9.5...v8.9.6) (2025-12-28)


### Bug Fixes

* **git-account-validator:** respect SSH host aliases in remote URL ([70d3a3f](https://github.com/terrylica/cc-skills/commit/70d3a3faebcb6970623f0b8e270ad2ac32cf58c1))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/SKILL.md) - updated (+25)

</details>


### Skill References

<details>
<summary><strong>itp/semantic-release</strong> (1 file)</summary>

- [Python Projects with semantic-release (Node.js) - 2025 Production Pattern](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/python-projects-nodejs-semantic-release.md) - updated (+72)

</details>

## [8.9.5](https://github.com/terrylica/cc-skills/compare/v8.9.4...v8.9.5) (2025-12-28)





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [ITP Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/README.md) - updated (+2)

## Repository Documentation

### Root Documentation

- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+9/-1)

## Other Documentation

### Other

- [Troubleshooting cc-skills Marketplace Installation](https://github.com/terrylica/cc-skills/blob/main/docs/troubleshooting/marketplace-installation.md) - updated (+53)
- [Getting Started with Ralph (First-Time Users)](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/GETTING-STARTED.md) - updated (+15/-1)

## [8.9.4](https://github.com/terrylica/cc-skills/compare/v8.9.3...v8.9.4) (2025-12-28)


### Bug Fixes

* **ralph:** create STATE_DIR and CONFIG_DIR on import to prevent FileNotFoundError ([0152e1f](https://github.com/terrylica/cc-skills/commit/0152e1ffceb8480789ee955aea236b744052f048))





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [Ralph Plugin for Claude Code](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/README.md) - updated (+2/-1)

## Other Documentation

### Other

- [Ralph Mental Model for Alpha-Forge](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/MENTAL-MODEL.md) - updated (+17/-5)

## [8.9.3](https://github.com/terrylica/cc-skills/compare/v8.9.2...v8.9.3) (2025-12-27)


### Bug Fixes

* **ralph:** address race conditions and argument handling issues ([ffc0853](https://github.com/terrylica/cc-skills/commit/ffc0853e856c69cf117d36bb2b1881d2b325c028))





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [Ralph Plugin for Claude Code](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/README.md) - updated (+1)

### Commands

<details>
<summary><strong>ralph</strong> (3 commands)</summary>

- [Ralph Loop: Audit Now](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/audit-now.md) - updated (+1/-1)
- [Ralph Loop: Encourage](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/encourage.md) - updated (+1/-1)
- [Ralph Loop: Forbid](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/forbid.md) - updated (+1/-1)

</details>

## [8.9.2](https://github.com/terrylica/cc-skills/compare/v8.9.1...v8.9.2) (2025-12-27)


### Bug Fixes

* **itp:** use origin remote for browser URLs instead of gh repo view ([eef3882](https://github.com/terrylica/cc-skills/commit/eef38827a4bab194dfcea2897f97c2ae64527788))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>itp</strong> (1 command)</summary>

- [⛔ ITP Workflow — STOP AND READ](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/go.md) - updated (+14/-2)

</details>

## [8.9.1](https://github.com/terrylica/cc-skills/compare/v8.9.0...v8.9.1) (2025-12-27)





---

## Documentation Changes

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+7)
- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+2)

## Other Documentation

### Other

- [Troubleshooting cc-skills Marketplace Installation](https://github.com/terrylica/cc-skills/blob/main/docs/troubleshooting/marketplace-installation.md) - new (+527)
- [Getting Started with Ralph (First-Time Users)](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/GETTING-STARTED.md) - updated (+2)

# [8.9.0](https://github.com/terrylica/cc-skills/compare/v8.8.0...v8.9.0) (2025-12-27)


### Features

* **statusline-tools:** add global ignore patterns for lint-relative-paths ([45e174b](https://github.com/terrylica/cc-skills/commit/45e174bfd42b483d0b23c6665ec1911171b31071))





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [statusline-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/README.md) - updated (+19)

### Commands

<details>
<summary><strong>statusline-tools</strong> (3 commands)</summary>

- [Status Line Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/commands/hooks.md) - updated (+30/-1)
- [Global Ignore Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/commands/ignore.md) - new (+100)
- [Status Line Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/commands/setup.md) - updated (+32/-1)

</details>

# [8.8.0](https://github.com/terrylica/cc-skills/compare/v8.7.7...v8.8.0) (2025-12-27)


### Features

* **validate:** add hooks.json schema validation to prevent "Invalid discriminator value" regressions ([108a325](https://github.com/terrylica/cc-skills/commit/108a3250ead526f1cd6b389bea09a1673f920e5b))

## [8.7.7](https://github.com/terrylica/cc-skills/compare/v8.7.6...v8.7.7) (2025-12-27)


### Bug Fixes

* **ralph:** correct PreToolUse hook JSON structure in manage-hooks.sh ([b4d626c](https://github.com/terrylica/cc-skills/commit/b4d626cb69bbed770a3aaf714af681c9d081b49a))

## [8.7.6](https://github.com/terrylica/cc-skills/compare/v8.7.5...v8.7.6) (2025-12-27)


### Bug Fixes

* **statusline-tools:** add archives and state to lint exclude dirs ([1ba2793](https://github.com/terrylica/cc-skills/commit/1ba2793b70e4b9286d742c041dab89e1497a1dfe))

## [8.7.5](https://github.com/terrylica/cc-skills/compare/v8.7.4...v8.7.5) (2025-12-27)





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [Ralph Plugin for Claude Code](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/README.md) - updated (+3/-1)

## Repository Documentation

### Root Documentation

- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+30/-5)

## Other Documentation

### Other

- [Getting Started with Ralph (First-Time Users)](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/GETTING-STARTED.md) - new (+252)

## [8.7.4](https://github.com/terrylica/cc-skills/compare/v8.7.3...v8.7.4) (2025-12-27)





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| accepted | [Ralph RSSI Eternal Loop Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-20-ralph-rssi-eternal-loop.md) | coupled |

### Design Specs

- [Design Spec: Ralph RSSI Eternal Loop Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-20-ralph-rssi-eternal-loop/spec.md) - updated (+26/-18)

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (2 commands)</summary>

- [Ralph Loop: Encourage](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/encourage.md) - updated (+20/-2)
- [Ralph Loop: Forbid](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/forbid.md) - updated (+21/-3)

</details>


## Other Documentation

### Other

- [Ralph Mental Model for Alpha-Forge](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/MENTAL-MODEL.md) - updated (+11)

## [8.7.3](https://github.com/terrylica/cc-skills/compare/v8.7.2...v8.7.3) (2025-12-27)


### Bug Fixes

* **ralph:** web research trigger only in exploration mode, not implementation ([06742fb](https://github.com/terrylica/cc-skills/commit/06742fb36483839c9c0a28238690d44be79011d1))





---

## Documentation Changes

## Other Documentation

### Other

- [rssi-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/rssi-unified.md) - updated (+4/-1)

## [8.7.2](https://github.com/terrylica/cc-skills/compare/v8.7.1...v8.7.2) (2025-12-27)


### Bug Fixes

* **ralph:** unify templates so encourage/forbid guidance applies to all phases ([6ba72d6](https://github.com/terrylica/cc-skills/commit/6ba72d6a0ed054df5464a0b4a4d90c27b1556986))





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [Ralph Plugin for Claude Code](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/README.md) - updated (+1/-3)

## Other Documentation

### Other

- [implementation-mode](https://github.com/terrylica/cc-skills/blob/v8.7.1/plugins/ralph/hooks/templates/implementation-mode.md) - deleted
- [rssi-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/rssi-unified.md) - renamed from `plugins/ralph/hooks/templates/exploration-mode.md`

## [8.7.1](https://github.com/terrylica/cc-skills/compare/v8.7.0...v8.7.1) (2025-12-26)


### Bug Fixes

* **validate:** integrate AJV schema validation into validateMarketplaceEntries ([158292c](https://github.com/terrylica/cc-skills/commit/158292c3f458256b407119dcdab769a4475ec082))

# [8.7.0](https://github.com/terrylica/cc-skills/compare/v8.6.0...v8.7.0) (2025-12-26)


### Features

* **validate:** modernize with tinyglobby + AJV, adopt Bun runtime ([8980686](https://github.com/terrylica/cc-skills/commit/89806863484f841ecc5a66d8c6cab8908b77783d))





---

## Documentation Changes

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+16/-16)

# [8.6.0](https://github.com/terrylica/cc-skills/compare/v8.5.1...v8.6.0) (2025-12-26)


### Features

* **validate:** add hook pitfall detection for common bugs ([0fd1732](https://github.com/terrylica/cc-skills/commit/0fd1732831f91f977d0820842e1ebf53a96bc2d0))

## [8.5.1](https://github.com/terrylica/cc-skills/compare/v8.5.0...v8.5.1) (2025-12-26)


### Bug Fixes

* **itp-hooks:** skip ADR reminder if file already has ADR reference ([fba3267](https://github.com/terrylica/cc-skills/commit/fba326791559271ed28539ff31675a39887fcc66))

# [8.5.0](https://github.com/terrylica/cc-skills/compare/v8.4.3...v8.5.0) (2025-12-26)


### Features

* **ralph:** show guidance in /ralph:status ([112881a](https://github.com/terrylica/cc-skills/commit/112881a763c5e4f91f2f28525b0a9f465998b5da))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Status](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/status.md) - updated (+33)

</details>

## [8.4.3](https://github.com/terrylica/cc-skills/compare/v8.4.2...v8.4.3) (2025-12-26)


### Bug Fixes

* **ralph:** preserve guidance across /ralph:start restarts ([62aa170](https://github.com/terrylica/cc-skills/commit/62aa1707de70fcf2f08d51cd4c932c1737a8d5a6))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+10/-1)

</details>

## [8.4.2](https://github.com/terrylica/cc-skills/compare/v8.4.1...v8.4.2) (2025-12-26)


### Code Refactoring

* **ralph:** consolidate exploration templates into unified file ([445db85](https://github.com/terrylica/cc-skills/commit/445db851b04490ea8c44433acebcd44e9cc69993))


### BREAKING CHANGES

* **ralph:** alpha-forge-exploration.md removed, use exploration-mode.md with adapter_name="alpha-forge"





---

## Documentation Changes

## Other Documentation

### Other

- [alpha-forge-exploration](https://github.com/terrylica/cc-skills/blob/v8.4.1/plugins/ralph/hooks/templates/alpha-forge-exploration.md) - deleted
- [exploration-mode](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/exploration-mode.md) - updated (+348/-39)
- [implementation-mode](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/implementation-mode.md) - updated (-6)

## [8.4.1](https://github.com/terrylica/cc-skills/compare/v8.4.0...v8.4.1) (2025-12-26)


### Bug Fixes

* **ralph:** add RSSI protocol and data reminder to all templates ([2076bd8](https://github.com/terrylica/cc-skills/commit/2076bd85dd8fc6ae5e7b39c1b5d3cb46f32b35be))





---

## Documentation Changes

## Other Documentation

### Other

- [alpha-forge-exploration](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/alpha-forge-exploration.md) - updated (+4)
- [exploration-mode](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/exploration-mode.md) - updated (+6/-2)
- [implementation-mode](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/implementation-mode.md) - updated (+6)

# [8.4.0](https://github.com/terrylica/cc-skills/compare/v8.3.0...v8.4.0) (2025-12-26)


### Features

* **ralph:** add RSSI branding and behavioral reminder to implementation mode ([ca4c7df](https://github.com/terrylica/cc-skills/commit/ca4c7dfde2b79ce91a40639e6ac4d0538585cf6c))

# [8.3.0](https://github.com/terrylica/cc-skills/compare/v8.2.1...v8.3.0) (2025-12-26)


### Features

* **validate:** add hook pitfall detection for common bugs ([c1807e5](https://github.com/terrylica/cc-skills/commit/c1807e5896c5c3a67153a9dd38f13c8fbff4589c))

## [8.2.1](https://github.com/terrylica/cc-skills/compare/v8.2.0...v8.2.1) (2025-12-26)


### Bug Fixes

* **hooks:** fix PostToolUse blocking errors for relative paths and ruff success ([69fd2c6](https://github.com/terrylica/cc-skills/commit/69fd2c638fecb17ef70dffde67629f2be6bf909f))

# [8.2.0](https://github.com/terrylica/cc-skills/compare/v8.1.11...v8.2.0) (2025-12-26)


### Features

* **asciinema-tools:** add launchd daemon architecture for background chunking ([d5657d3](https://github.com/terrylica/cc-skills/commit/d5657d3dfd1de6c2a28d61c75e0e7d41bfa7bb6a))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| unknown | [asciinema-tools Daemon Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-26-asciinema-daemon-architecture.md) | new (+205) |

## Plugin Documentation

### Commands

<details>
<summary><strong>asciinema-tools</strong> (6 commands)</summary>

- [/asciinema-tools:bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/bootstrap.md) - updated (+192/-70)
- [/asciinema-tools:daemon-logs](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-logs.md) - new (+98)
- [/asciinema-tools:daemon-setup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-setup.md) - new (+574)
- [/asciinema-tools:daemon-start](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-start.md) - new (+73)
- [/asciinema-tools:daemon-status](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-status.md) - new (+130)
- [/asciinema-tools:daemon-stop](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-stop.md) - new (+69)

</details>

## [8.1.11](https://github.com/terrylica/cc-skills/compare/v8.1.10...v8.1.11) (2025-12-26)


### Bug Fixes

* **ralph:** add git remote detection for sparse checkouts/branches ([474246c](https://github.com/terrylica/cc-skills/commit/474246ca95b8ce3f690a2fd11842229b4628c6be))





---

## Documentation Changes

## Other Documentation

### Other

- [Ralph Hook Validation - Alpha-Forge Comprehensive Test Suite](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/docs/ALPHA-FORGE-VALIDATION-PROMPT.md) - updated (+34/-2)

## [8.1.10](https://github.com/terrylica/cc-skills/compare/v8.1.9...v8.1.10) (2025-12-26)





---

## Documentation Changes

## Other Documentation

### Other

- [Ralph Hook Validation - Alpha-Forge Comprehensive Test Suite](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/docs/ALPHA-FORGE-VALIDATION-PROMPT.md) - updated (+404/-61)

## [8.1.9](https://github.com/terrylica/cc-skills/compare/v8.1.8...v8.1.9) (2025-12-26)





---

## Documentation Changes

## Other Documentation

### Other

- [Link Validation Hook Test - Meta-Prompt](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/docs/LINK-VALIDATION-TEST-PROMPT.md) - new (+124)

## [8.1.8](https://github.com/terrylica/cc-skills/compare/v8.1.7...v8.1.8) (2025-12-26)


### Bug Fixes

* **statusline-tools:** add stop_hook_active check to prevent infinite loop ([a22774b](https://github.com/terrylica/cc-skills/commit/a22774be3410f6d481866a6986b9d679a377b526))
* **statusline-tools:** use decision:block so Claude sees violations ([7ffbee3](https://github.com/terrylica/cc-skills/commit/7ffbee3ee6244719c14a849e973b02addc4db58c))

## [8.1.7](https://github.com/terrylica/cc-skills/compare/v8.1.6...v8.1.7) (2025-12-26)


### Bug Fixes

* **statusline-tools:** include actual violation details in Stop hook ([b9b61b2](https://github.com/terrylica/cc-skills/commit/b9b61b245bedf95cd1dfa13892ed746269b84568))

## [8.1.6](https://github.com/terrylica/cc-skills/compare/v8.1.5...v8.1.6) (2025-12-26)


### Bug Fixes

* **ralph:** move and update alpha-forge validation meta-prompt ([64c468b](https://github.com/terrylica/cc-skills/commit/64c468bf820d14ce35f23482f5a4f0b7ed6d8273))





---

## Documentation Changes

## Other Documentation

### Other

- [Ralph Hook Validation - Alpha-Forge Meta-Prompt](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/docs/ALPHA-FORGE-VALIDATION-PROMPT.md) - renamed from `plugins/ralph/hooks/plugins/ralph/docs/ALPHA-FORGE-VALIDATION-PROMPT.md`

## [8.1.5](https://github.com/terrylica/cc-skills/compare/v8.1.4...v8.1.5) (2025-12-26)





---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+14/-10)

</details>

## [8.1.4](https://github.com/terrylica/cc-skills/compare/v8.1.3...v8.1.4) (2025-12-26)


### Bug Fixes

* **validate:** correct Stop hook output format recommendation ([a8bab52](https://github.com/terrylica/cc-skills/commit/a8bab527cded5141d438228952f725741e87ea12))

## [8.1.3](https://github.com/terrylica/cc-skills/compare/v8.1.2...v8.1.3) (2025-12-26)


### Bug Fixes

* **statusline-tools:** use systemMessage for Stop hook output ([1a92495](https://github.com/terrylica/cc-skills/commit/1a924953eeac1817348a6a53965fcb4460900f2a))

## [8.1.2](https://github.com/terrylica/cc-skills/compare/v8.1.1...v8.1.2) (2025-12-26)





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [Ralph Plugin for Claude Code](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/README.md) - updated (+19/-1)

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+5/-4)

</details>

## [8.1.1](https://github.com/terrylica/cc-skills/compare/v8.1.0...v8.1.1) (2025-12-26)





---

## Documentation Changes

## Other Documentation

### Other

- [Ralph Hook Validation - Alpha-Forge Meta-Prompt](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/plugins/ralph/docs/ALPHA-FORGE-VALIDATION-PROMPT.md) - new (+88)

# [8.1.0](https://github.com/terrylica/cc-skills/compare/v8.0.3...v8.1.0) (2025-12-26)


### Features

* **hooks:** add silent failure detection and fix deprecated output patterns ([9d98b0c](https://github.com/terrylica/cc-skills/commit/9d98b0c4e75857e33df7b2c917500a8cd7219536))





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [ITP Hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/README.md) - updated (+41/-1)

### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+268/-98)

</details>


### Commands

<details>
<summary><strong>itp-hooks</strong> (1 command)</summary>

- [ITP Hooks Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/commands/setup.md) - new (+99)

</details>

## [8.0.3](https://github.com/terrylica/cc-skills/compare/v8.0.2...v8.0.3) (2025-12-26)


### Bug Fixes

* **ralph:** add git worktree detection to alpha-forge guard ([380ff16](https://github.com/terrylica/cc-skills/commit/380ff16f841187c260ba37d3432a6036aea1e90a))

## [8.0.2](https://github.com/terrylica/cc-skills/compare/v8.0.1...v8.0.2) (2025-12-26)


### Bug Fixes

* **ralph:** add alpha-forge only guard to all hooks ([cbb8f99](https://github.com/terrylica/cc-skills/commit/cbb8f99a18c26b8e145810d6c3716e684e4d9cfa))

## [8.0.1](https://github.com/terrylica/cc-skills/compare/v8.0.0...v8.0.1) (2025-12-26)


### Bug Fixes

* **marketplace:** remove unsupported 'requires' field causing schema errors ([1efa729](https://github.com/terrylica/cc-skills/commit/1efa729d9d6b2fd46b894c2fe0c77ba72d56b217)), closes [#9444](https://github.com/terrylica/cc-skills/issues/9444)





---

## Documentation Changes

## Repository Documentation

### Root Documentation

- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+19)

# [8.0.0](https://github.com/terrylica/cc-skills/compare/v7.19.7...v8.0.0) (2025-12-26)


### Features

* **plugins:** consolidate 7 plugins into 4 merged plugins with dependency tracking ([8d6096d](https://github.com/terrylica/cc-skills/commit/8d6096dc54695aecd5967064afb449a58ad83f5e))


### BREAKING CHANGES

* **plugins:** Plugin names changed - update your /plugin install commands

Merged plugins:
- skill-architecture + validate-plugin-structure → plugin-dev
- link-validator + link-checker → link-tools
- doc-build-tools → doc-tools (6 skills total)
- mql5-tools + mql5com → mql5 (4 skills)
- notification-tools → devops-tools (8 skills)

New features:
- Added 'requires' field to marketplace.json for dependency declaration
- Enhanced validate-plugins.mjs with dependency graph detection
- Circular dependency detection (doc-tools ↔ itp)
- Installation instructions generation with dependency order
- Loud/explicit error output for Claude Code CLI visibility

Reference: https://github.com/anthropics/claude-code/issues/9444





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [dual-channel-watchexec-notifications](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/dual-channel-watchexec/SKILL.md) - renamed from `plugins/notification-tools/skills/dual-channel-watchexec/SKILL.md`

</details>

<details>
<summary><strong>doc-tools</strong> (4 changes)</summary>

- [latex-build](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-build/SKILL.md) - renamed from `plugins/doc-build-tools/skills/latex-build/SKILL.md`
- [latex-setup](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-setup/SKILL.md) - renamed from `plugins/doc-build-tools/skills/latex-setup/SKILL.md`
- [latex-tables](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-tables/SKILL.md) - renamed from `plugins/doc-build-tools/skills/latex-tables/SKILL.md`
- [pandoc-pdf-generation](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/pandoc-pdf-generation/SKILL.md) - renamed from `plugins/doc-build-tools/skills/pandoc-pdf-generation/SKILL.md`

</details>

<details>
<summary><strong>link-tools</strong> (2 changes)</summary>

- [link-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/skills/link-validation/SKILL.md) - renamed from `plugins/link-checker/skills/link-validation/SKILL.md`
- [link-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/skills/link-validator/SKILL.md) - renamed from `plugins/link-validator/skills/link-validator/SKILL.md`

</details>

<details>
<summary><strong>mql5</strong> (4 changes)</summary>

- [article-extractor](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/article-extractor/SKILL.md) - renamed from `plugins/mql5com/skills/article-extractor/SKILL.md`
- [log-reader](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/log-reader/SKILL.md) - renamed from `plugins/mql5com/skills/log-reader/SKILL.md`
- [mql5-indicator-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/mql5-indicator-patterns/SKILL.md) - renamed from `plugins/mql5-tools/skills/mql5-indicator-patterns/SKILL.md`
- [python-workspace](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/python-workspace/SKILL.md) - renamed from `plugins/mql5com/skills/python-workspace/SKILL.md`

</details>

<details>
<summary><strong>plugin-dev</strong> (2 changes)</summary>

- [plugin-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/plugin-validator/SKILL.md) - new (+133)
- [skill-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/SKILL.md) - renamed from `plugins/skill-architecture/skills/skill-architecture/SKILL.md`

</details>


### Plugin READMEs

- [devops-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/README.md) - updated (+13/-2)
- [doc-build-tools](https://github.com/terrylica/cc-skills/blob/v7.19.7/plugins/doc-build-tools/README.md) - deleted
- [doc-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/README.md) - updated (+42/-19)
- [link-checker](https://github.com/terrylica/cc-skills/blob/v7.19.7/plugins/link-checker/README.md) - deleted
- [link-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/README.md) - new (+58)
- [link-validator](https://github.com/terrylica/cc-skills/blob/v7.19.7/plugins/link-validator/README.md) - deleted
- [mql5-tools](https://github.com/terrylica/cc-skills/blob/v7.19.7/plugins/mql5-tools/README.md) - deleted
- [mql5](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/README.md) - new (+56)
- [mql5com](https://github.com/terrylica/cc-skills/blob/v7.19.7/plugins/mql5com/README.md) - deleted
- [notification-tools](https://github.com/terrylica/cc-skills/blob/v7.19.7/plugins/notification-tools/README.md) - deleted
- [plugin-dev](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/README.md) - new (+66)
- [skill-architecture](https://github.com/terrylica/cc-skills/blob/v7.19.7/plugins/skill-architecture/README.md) - deleted

### Skill References

<details>
<summary><strong>devops-tools/dual-channel-watchexec</strong> (5 files)</summary>

- [❌ WRONG - Sends HTML to Pushover](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/dual-channel-watchexec/references/common-pitfalls.md) - renamed from `plugins/notification-tools/skills/dual-channel-watchexec/references/common-pitfalls.md`
- [Load Pushover credentials from Doppler](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/dual-channel-watchexec/references/credential-management.md) - renamed from `plugins/notification-tools/skills/dual-channel-watchexec/references/credential-management.md`
- [Canonical source for Pushover credentials](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/dual-channel-watchexec/references/pushover-integration.md) - renamed from `plugins/notification-tools/skills/dual-channel-watchexec/references/pushover-integration.md`
- [Python API call](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/dual-channel-watchexec/references/telegram-html.md) - renamed from `plugins/notification-tools/skills/dual-channel-watchexec/references/telegram-html.md`
- [Use stat to check modification time](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/dual-channel-watchexec/references/watchexec-patterns.md) - renamed from `plugins/notification-tools/skills/dual-channel-watchexec/references/watchexec-patterns.md`

</details>

<details>
<summary><strong>doc-tools/latex-build</strong> (5 files)</summary>

- [Build all .tex files in directory](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-build/references/advanced-patterns.md) - renamed from `plugins/doc-build-tools/skills/latex-build/references/advanced-patterns.md`
- [PDF output](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-build/references/common-commands.md) - renamed from `plugins/doc-build-tools/skills/latex-build/references/common-commands.md`
- [Use pdflatex by default](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-build/references/configuration.md) - renamed from `plugins/doc-build-tools/skills/latex-build/references/configuration.md`
- [latexmk watches ALL included files](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-build/references/multi-file-projects.md) - renamed from `plugins/doc-build-tools/skills/latex-build/references/multi-file-projects.md`
- [Check installation](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-build/references/troubleshooting.md) - renamed from `plugins/doc-build-tools/skills/latex-build/references/troubleshooting.md`

</details>

<details>
<summary><strong>doc-tools/latex-setup</strong> (5 files)</summary>

- [Download from mactex.org](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-setup/references/installation.md) - renamed from `plugins/doc-build-tools/skills/latex-setup/references/installation.md`
- [Use kpsewhich to find package](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-setup/references/package-management.md) - renamed from `plugins/doc-build-tools/skills/latex-setup/references/package-management.md`
- [Add -synctex=1 flag](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-setup/references/skim-configuration.md) - renamed from `plugins/doc-build-tools/skills/latex-setup/references/skim-configuration.md`
- [Add to ~/.zshrc or ~/.bash_profile](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-setup/references/troubleshooting.md) - renamed from `plugins/doc-build-tools/skills/latex-setup/references/troubleshooting.md`
- [Check TeX version](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-setup/references/verification.md) - renamed from `plugins/doc-build-tools/skills/latex-setup/references/verification.md`

</details>

<details>
<summary><strong>doc-tools/latex-tables</strong> (5 files)</summary>

- [Column Spec](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-tables/references/column-spec.md) - renamed from `plugins/doc-build-tools/skills/latex-tables/references/column-spec.md`
- [Lines Borders](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-tables/references/lines-borders.md) - renamed from `plugins/doc-build-tools/skills/latex-tables/references/lines-borders.md`
- [Migration](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-tables/references/migration.md) - renamed from `plugins/doc-build-tools/skills/latex-tables/references/migration.md`
- [Table Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-tables/references/table-patterns.md) - renamed from `plugins/doc-build-tools/skills/latex-tables/references/table-patterns.md`
- [Troubleshooting](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-tables/references/troubleshooting.md) - renamed from `plugins/doc-build-tools/skills/latex-tables/references/troubleshooting.md`

</details>

<details>
<summary><strong>doc-tools/pandoc-pdf-generation</strong> (7 files)</summary>

- [Bibliography Citations](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/pandoc-pdf-generation/references/bibliography-citations.md) - renamed from `plugins/doc-build-tools/skills/pandoc-pdf-generation/references/bibliography-citations.md`
- [Core Development Principles for PDF Generation](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/pandoc-pdf-generation/references/core-principles.md) - renamed from `plugins/doc-build-tools/skills/pandoc-pdf-generation/references/core-principles.md`
- [1. Executive Summary](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/pandoc-pdf-generation/references/document-patterns.md) - renamed from `plugins/doc-build-tools/skills/pandoc-pdf-generation/references/document-patterns.md`
- [LaTeX Parameters Reference for Pandoc](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/pandoc-pdf-generation/references/latex-parameters.md) - renamed from `plugins/doc-build-tools/skills/pandoc-pdf-generation/references/latex-parameters.md`
- [Markdown Structure for PDF Generation](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/pandoc-pdf-generation/references/markdown-for-pdf.md) - renamed from `plugins/doc-build-tools/skills/pandoc-pdf-generation/references/markdown-for-pdf.md`
- [General diagrams](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/pandoc-pdf-generation/references/troubleshooting-pandoc.md) - renamed from `plugins/doc-build-tools/skills/pandoc-pdf-generation/references/troubleshooting-pandoc.md`
- [Document Title        ← Makes this Section 1](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/pandoc-pdf-generation/references/yaml-structure.md) - renamed from `plugins/doc-build-tools/skills/pandoc-pdf-generation/references/yaml-structure.md`

</details>

<details>
<summary><strong>link-tools/link-validator</strong> (1 file)</summary>

- [Link Patterns Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/skills/link-validator/references/link-patterns.md) - renamed from `plugins/link-validator/skills/link-validator/references/link-patterns.md`

</details>

<details>
<summary><strong>mql5/article-extractor</strong> (4 files)</summary>

- [Data Sources](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/article-extractor/references/data-sources.md) - renamed from `plugins/mql5com/skills/article-extractor/references/data-sources.md`
- [MQL5 Article Extractor - Examples](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/article-extractor/references/examples.md) - renamed from `plugins/mql5com/skills/article-extractor/references/examples.md`
- [Extraction Modes](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/article-extractor/references/extraction-modes.md) - renamed from `plugins/mql5com/skills/article-extractor/references/extraction-modes.md`
- [Count articles extracted](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/article-extractor/references/troubleshooting.md) - renamed from `plugins/mql5com/skills/article-extractor/references/troubleshooting.md`

</details>

<details>
<summary><strong>mql5/mql5-indicator-patterns</strong> (5 files)</summary>

- [Buffer Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/mql5-indicator-patterns/references/buffer-patterns.md) - renamed from `plugins/mql5-tools/skills/mql5-indicator-patterns/references/buffer-patterns.md`
- [Complete Template](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/mql5-indicator-patterns/references/complete-template.md) - renamed from `plugins/mql5-tools/skills/mql5-indicator-patterns/references/complete-template.md`
- [Debugging](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/mql5-indicator-patterns/references/debugging.md) - renamed from `plugins/mql5-tools/skills/mql5-indicator-patterns/references/debugging.md`
- [Display Scale](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/mql5-indicator-patterns/references/display-scale.md) - renamed from `plugins/mql5-tools/skills/mql5-indicator-patterns/references/display-scale.md`
- [Recalculation](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/mql5-indicator-patterns/references/recalculation.md) - renamed from `plugins/mql5-tools/skills/mql5-indicator-patterns/references/recalculation.md`

</details>

<details>
<summary><strong>mql5/python-workspace</strong> (4 files)</summary>

- [Step 1: Generate config](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/python-workspace/references/capabilities-detailed.md) - renamed from `plugins/mql5com/skills/python-workspace/references/capabilities-detailed.md`
- [Step 1: Generate config](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/python-workspace/references/troubleshooting-errors.md) - renamed from `plugins/mql5com/skills/python-workspace/references/troubleshooting-errors.md`
- [Validation Metrics](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/python-workspace/references/validation-metrics.md) - renamed from `plugins/mql5com/skills/python-workspace/references/validation-metrics.md`
- [One-liner (v3.0.0 headless)](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/python-workspace/references/workflows-complete.md) - renamed from `plugins/mql5com/skills/python-workspace/references/workflows-complete.md`

</details>

<details>
<summary><strong>plugin-dev/plugin-validator</strong> (1 file)</summary>

- [Silent Failure Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/plugin-validator/references/silent-failure-patterns.md) - new (+158)

</details>

<details>
<summary><strong>plugin-dev/skill-architecture</strong> (14 files)</summary>

- [Agent Skill Name](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/advanced-topics.md) - renamed from `plugins/skill-architecture/skills/skill-architecture/references/advanced-topics.md`
- [Bash Compatibility for Skills](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/bash-compatibility.md) - renamed from `plugins/skill-architecture/skills/skill-architecture/references/bash-compatibility.md`
- [Creation Workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/creation-workflow.md) - renamed from `plugins/skill-architecture/skills/skill-architecture/references/creation-workflow.md`
- [Error Message Style Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/error-message-style.md) - renamed from `plugins/skill-architecture/skills/skill-architecture/references/error-message-style.md`
- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/evolution-log.md) - renamed from `plugins/skill-architecture/skills/skill-architecture/references/evolution-log.md`
- [Path Patterns Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/path-patterns.md) - renamed from `plugins/skill-architecture/skills/skill-architecture/references/path-patterns.md`
- [Progressive Disclosure](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/progressive-disclosure.md) - renamed from `plugins/skill-architecture/skills/skill-architecture/references/progressive-disclosure.md`
- [Scripts Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/scripts-reference.md) - renamed from `plugins/skill-architecture/skills/skill-architecture/references/scripts-reference.md`
- [Safe API Client](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/security-practices.md) - renamed from `plugins/skill-architecture/skills/skill-architecture/references/security-practices.md`
- [Structural Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/structural-patterns.md) - renamed from `plugins/skill-architecture/skills/skill-architecture/references/structural-patterns.md`
- [Marketplace Sync Tracking](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/SYNC-TRACKING.md) - renamed from `plugins/skill-architecture/skills/skill-architecture/references/SYNC-TRACKING.md`
- [Token Efficiency](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/token-efficiency.md) - renamed from `plugins/skill-architecture/skills/skill-architecture/references/token-efficiency.md`
- [My Skill](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/validation-reference.md) - renamed from `plugins/skill-architecture/skills/skill-architecture/references/validation-reference.md`
- [Workflow Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/workflow-patterns.md) - renamed from `plugins/skill-architecture/skills/skill-architecture/references/workflow-patterns.md`

</details>


### Commands

<details>
<summary><strong>plugin-dev</strong> (1 command)</summary>

- [⛔ Create Plugin — STOP AND READ](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/commands/create.md) - renamed from `plugins/itp/commands/plugin-add.md`

</details>


## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+2/-2)
- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+55/-101)

## Other Documentation

### Other

- [Implementation Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/dual-channel-watchexec/reference.md) - renamed from `plugins/notification-tools/skills/dual-channel-watchexec/reference.md`
- [Modern LaTeX Workflow for macOS (2025)](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-setup/REFERENCE.md) - renamed from `plugins/doc-build-tools/skills/latex-setup/REFERENCE.md`

## [7.19.7](https://github.com/terrylica/cc-skills/compare/v7.19.6...v7.19.7) (2025-12-26)


### Bug Fixes

* **ralph:** add verbose error handling to archive-plan.sh ([b0bb0e1](https://github.com/terrylica/cc-skills/commit/b0bb0e1de97574c2edf5c52e816905915dd9f75c))

## [7.19.6](https://github.com/terrylica/cc-skills/compare/v7.19.5...v7.19.6) (2025-12-26)


### Bug Fixes

* **ralph:** eliminate all silent failures in manage-hooks.sh ([33a782a](https://github.com/terrylica/cc-skills/commit/33a782aa53486e17a3860f126d0b9d6d26bcc38d))

## [7.19.5](https://github.com/terrylica/cc-skills/compare/v7.19.4...v7.19.5) (2025-12-26)


### Bug Fixes

* **ralph:** clean up timestamp and cache files on uninstall ([e7b649f](https://github.com/terrylica/cc-skills/commit/e7b649fae2180d736abf911fbd50863efb053641))

## [7.19.4](https://github.com/terrylica/cc-skills/compare/v7.19.3...v7.19.4) (2025-12-26)


### Bug Fixes

* **ralph:** add missing pretooluse-loop-guard.py to preflight check ([9e7a52f](https://github.com/terrylica/cc-skills/commit/9e7a52f0a4e3dffa19cbd8a9de44448d3416fe10))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/hooks.md) - updated (+22/-6)

</details>

## [7.19.3](https://github.com/terrylica/cc-skills/compare/v7.19.2...v7.19.3) (2025-12-26)


### Bug Fixes

* **ralph:** correct MENTAL-MODEL.md paths and clarify Alpha-Forge convergence ([41780ac](https://github.com/terrylica/cc-skills/commit/41780ac9066d09dcf7b43541792fa6d4a3356c63))





---

## Documentation Changes

## Other Documentation

### Other

- [Ralph Mental Model for Alpha-Forge](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/MENTAL-MODEL.md) - updated (+7/-4)

## [7.19.2](https://github.com/terrylica/cc-skills/compare/v7.19.1...v7.19.2) (2025-12-26)


### Bug Fixes

* **ralph:** add documentation links to /ralph:hooks status output ([063e06f](https://github.com/terrylica/cc-skills/commit/063e06ff0f94dfd49ea95faf32e6cb7928fe6b8f))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/hooks.md) - updated (+14/-2)

</details>

## [7.19.1](https://github.com/terrylica/cc-skills/compare/v7.19.0...v7.19.1) (2025-12-26)





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [Ralph Plugin for Claude Code](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/README.md) - updated (+137/-12)

# [7.19.0](https://github.com/terrylica/cc-skills/compare/v7.18.2...v7.19.0) (2025-12-26)


### Bug Fixes

* **skill:** recommend ASCII for GitHub, boxart for terminal only ([1a6389b](https://github.com/terrylica/cc-skills/commit/1a6389b794ab61789ea76485c8d4adcadda3b01c))


### Features

* **ralph:** comprehensive installation integrity with restart detection ([842fe4c](https://github.com/terrylica/cc-skills/commit/842fe4cf593183345fd35a5febb14b3faaa540c3))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [graph-easy](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/graph-easy/SKILL.md) - updated (+23/-18)

</details>


### Commands

<details>
<summary><strong>ralph</strong> (8 commands)</summary>

- [Ralph Loop: Audit Now](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/audit-now.md) - updated (+7/-2)
- [Ralph Loop: Config](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/config.md) - updated (+14/-4)
- [Ralph Loop: Encourage](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/encourage.md) - updated (+17/-4)
- [Ralph Loop: Forbid](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/forbid.md) - updated (+17/-4)
- [Ralph Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/hooks.md) - updated (+226/-7)
- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+67)
- [Ralph Loop: Status](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/status.md) - updated (+13/-2)
- [Ralph Loop: Stop](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/stop.md) - updated (+6/-2)

</details>

## [7.18.2](https://github.com/terrylica/cc-skills/compare/v7.18.1...v7.18.2) (2025-12-26)


### Bug Fixes

* **semantic-release:** improve deleted file handling in release notes ([e18ca62](https://github.com/terrylica/cc-skills/commit/e18ca624da560c22b8e3b400ac9af550cdc3bdd1))

## [7.18.1](https://github.com/terrylica/cc-skills/compare/v7.18.0...v7.18.1) (2025-12-26)


### Bug Fixes

* **ralph:** remove SDK harness command and associated files ([79d25fd](https://github.com/terrylica/cc-skills/commit/79d25fde53014c76fc835c46f7d4fec2b66e6592))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [harness](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/harness.md) - deleted (-113)

</details>

# [7.18.0](https://github.com/terrylica/cc-skills/compare/v7.17.0...v7.18.0) (2025-12-26)


### Features

* **doc-tools:** extend ascii-diagram-validator for graph-easy boxart ([f098092](https://github.com/terrylica/cc-skills/commit/f098092d30d0e87e746bbbfed8e6e1e27872503c))
* **ralph:** add session state continuity with infallible inheritance tracking ([b09d39d](https://github.com/terrylica/cc-skills/commit/b09d39d424627c9cc7e02102a45eba2f4c0a77ed))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [graph-easy](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/graph-easy/SKILL.md) - updated (+35/-7)

</details>


### Plugin READMEs

- [Ralph Plugin for Claude Code](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/README.md) - updated (+62/-13)

## Other Documentation

### Other

- [Ralph Mental Model for Alpha-Forge](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/MENTAL-MODEL.md) - updated (+113/-5)

# [7.17.0](https://github.com/terrylica/cc-skills/compare/v7.16.8...v7.17.0) (2025-12-26)


### Features

* **ralph:** implement RSSI Beyond AGI - Intelligence Explosion mode ([efa10c4](https://github.com/terrylica/cc-skills/commit/efa10c47069852fd4e84d32e965a26c2fc797905))

## [7.16.8](https://github.com/terrylica/cc-skills/compare/v7.16.7...v7.16.8) (2025-12-26)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>link-validator</strong> (1 change)</summary>

- [link-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/link-validator/skills/link-validator/SKILL.md) - renamed from `plugins/link-validator/SKILL.md`

</details>

<details>
<summary><strong>skill-architecture</strong> (1 change)</summary>

- [skill-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/skills/skill-architecture/SKILL.md) - renamed from `plugins/skill-architecture/SKILL.md`

</details>


### Plugin READMEs

- [Skill Architecture Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/README.md) - updated (+14/-14)

### Skill References

<details>
<summary><strong>link-validator/link-validator</strong> (1 file)</summary>

- [Link Patterns Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/link-validator/skills/link-validator/references/link-patterns.md) - renamed from `plugins/link-validator/references/link-patterns.md`

</details>

<details>
<summary><strong>skill-architecture/skill-architecture</strong> (14 files)</summary>

- [Agent Skill Name](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/skills/skill-architecture/references/advanced-topics.md) - renamed from `plugins/skill-architecture/references/advanced-topics.md`
- [Bash Compatibility for Skills](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/skills/skill-architecture/references/bash-compatibility.md) - renamed from `plugins/skill-architecture/references/bash-compatibility.md`
- [Creation Workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/skills/skill-architecture/references/creation-workflow.md) - renamed from `plugins/skill-architecture/references/creation-workflow.md`
- [Error Message Style Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/skills/skill-architecture/references/error-message-style.md) - renamed from `plugins/skill-architecture/references/error-message-style.md`
- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/skills/skill-architecture/references/evolution-log.md) - renamed from `plugins/skill-architecture/references/evolution-log.md`
- [Path Patterns Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/skills/skill-architecture/references/path-patterns.md) - renamed from `plugins/skill-architecture/references/path-patterns.md`
- [Progressive Disclosure](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/skills/skill-architecture/references/progressive-disclosure.md) - renamed from `plugins/skill-architecture/references/progressive-disclosure.md`
- [Scripts Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/skills/skill-architecture/references/scripts-reference.md) - renamed from `plugins/skill-architecture/references/scripts-reference.md`
- [Safe API Client](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/skills/skill-architecture/references/security-practices.md) - renamed from `plugins/skill-architecture/references/security-practices.md`
- [Structural Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/skills/skill-architecture/references/structural-patterns.md) - renamed from `plugins/skill-architecture/references/structural-patterns.md`
- [Marketplace Sync Tracking](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/skills/skill-architecture/references/SYNC-TRACKING.md) - renamed from `plugins/skill-architecture/references/SYNC-TRACKING.md`
- [Token Efficiency](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/skills/skill-architecture/references/token-efficiency.md) - renamed from `plugins/skill-architecture/references/token-efficiency.md`
- [My Skill](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/skills/skill-architecture/references/validation-reference.md) - renamed from `plugins/skill-architecture/references/validation-reference.md`
- [Workflow Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/skills/skill-architecture/references/workflow-patterns.md) - renamed from `plugins/skill-architecture/references/workflow-patterns.md`

</details>

## [7.16.7](https://github.com/terrylica/cc-skills/compare/v7.16.6...v7.16.7) (2025-12-25)


### Bug Fixes

* **ralph:** remove broken links to gitignored runtime directories ([0b4213c](https://github.com/terrylica/cc-skills/commit/0b4213c6de266188738a3739f930a64a43856812))





---

## Documentation Changes

## Other Documentation

### Other

- [Ralph Mental Model for Alpha-Forge](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/MENTAL-MODEL.md) - updated (+20/-20)

## [7.16.6](https://github.com/terrylica/cc-skills/compare/v7.16.5...v7.16.6) (2025-12-25)


### Bug Fixes

* **ralph:** add 5 graph-easy diagrams and 16 hyperlinks to MENTAL-MODEL.md ([adab79b](https://github.com/terrylica/cc-skills/commit/adab79bec2356cc686486e311d0138d5f8fb4702))





---

## Documentation Changes

## Other Documentation

### Other

- [Ralph Mental Model for Alpha-Forge](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/MENTAL-MODEL.md) - updated (+354/-57)

## [7.16.5](https://github.com/terrylica/cc-skills/compare/v7.16.4...v7.16.5) (2025-12-25)


### Bug Fixes

* **ralph:** audit fixes, constants centralization, and MENTAL-MODEL.md ([c544eb4](https://github.com/terrylica/cc-skills/commit/c544eb4866f2332ad66865a59e4be54ca1118dcb))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| accepted | [Ralph RSSI Eternal Loop Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-20-ralph-rssi-eternal-loop.md) | coupled |

### Design Specs

- [Design Spec: Ralph RSSI Eternal Loop Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-20-ralph-rssi-eternal-loop/spec.md) - updated (+29/-3)

## Plugin Documentation

### Plugin READMEs

- [Ralph Plugin for Claude Code](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/README.md) - updated (+8/-6)

### Commands

<details>
<summary><strong>ralph</strong> (2 commands)</summary>

- [Ralph Loop: Config](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/config.md) - updated (+22)
- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+12/-7)

</details>


## Other Documentation

### Other

- [alpha-forge-convergence](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/alpha-forge-convergence.md) - deleted (-32)
- [Example: If WebSearch found "Temporal Fusion Transformer"](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/alpha-forge-exploration.md) - updated (+2/-2)
- [alpha-forge-research-experts](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/alpha-forge-research-experts.md) - deleted (-209)
- [alpha-forge-slo-experts](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/alpha-forge-slo-experts.md) - deleted (-347)
- [Ralph Mental Model for Alpha-Forge](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/MENTAL-MODEL.md) - new (+141)

## [7.16.4](https://github.com/terrylica/cc-skills/compare/v7.16.3...v7.16.4) (2025-12-25)


### Bug Fixes

* **ralph:** fail loudly when Jinja2 unavailable for complex templates ([d0fc686](https://github.com/terrylica/cc-skills/commit/d0fc6869de42d4c1bb7b72f84358b639710149a6))

## [7.16.3](https://github.com/terrylica/cc-skills/compare/v7.16.2...v7.16.3) (2025-12-25)


### Bug Fixes

* **ralph:** support nested dict access in fallback template renderer ([65d52b7](https://github.com/terrylica/cc-skills/commit/65d52b76e2458845d683b866095496daaccad16d))

## [7.16.2](https://github.com/terrylica/cc-skills/compare/v7.16.1...v7.16.2) (2025-12-25)


### Bug Fixes

* **ralph:** add global stop signal for version-agnostic stop ([dbcd448](https://github.com/terrylica/cc-skills/commit/dbcd448d91e2461c1a804b62e622f5628cca0a14))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Stop](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/stop.md) - updated (+7/-5)

</details>

## [7.16.1](https://github.com/terrylica/cc-skills/compare/v7.16.0...v7.16.1) (2025-12-25)


### Bug Fixes

* **ralph:** session-aware stop with holistic project directory resolution ([5f68a57](https://github.com/terrylica/cc-skills/commit/5f68a57b79a7b64a4a7b0db5202f883143b54067))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Stop](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/stop.md) - updated (+121/-49)

</details>

# [7.16.0](https://github.com/terrylica/cc-skills/compare/v7.15.4...v7.16.0) (2025-12-25)


### Features

* **ralph:** add GPU infrastructure awareness for alpha-forge ([d203158](https://github.com/terrylica/cc-skills/commit/d20315884bcc3516143ef602ee3e8b4bf280cbab))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| unknown | [asciinema-tools Plugin Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-24-asciinema-tools-plugin.md) | new (+180) |

## Plugin Documentation

### Skills

<details>
<summary><strong>asciinema-tools</strong> (6 changes)</summary>

- [asciinema-analyzer](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-analyzer/SKILL.md) - new (+378)
- [asciinema-cast-format](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-cast-format/SKILL.md) - new (+215)
- [asciinema-converter](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-converter/SKILL.md) - new (+324)
- [asciinema-player](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-player/SKILL.md) - renamed from `plugins/devops-tools/skills/asciinema-player/SKILL.md`
- [asciinema-recorder](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-recorder/SKILL.md) - renamed from `plugins/devops-tools/skills/asciinema-recorder/SKILL.md`
- [asciinema-streaming-backup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/SKILL.md) - renamed from `plugins/devops-tools/skills/asciinema-streaming-backup/SKILL.md`

</details>


### Plugin READMEs

- [asciinema-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/README.md) - new (+149)
- [devops-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/README.md) - updated (+19/-48)

### Skill References

<details>
<summary><strong>asciinema-tools/asciinema-analyzer</strong> (2 files)</summary>

- [Analysis Tiers Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-analyzer/references/analysis-tiers.md) - new (+276)
- [Domain Keywords Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-analyzer/references/domain-keywords.md) - new (+202)

</details>

<details>
<summary><strong>asciinema-tools/asciinema-streaming-backup</strong> (4 files)</summary>

- [Autonomous Validation Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/references/autonomous-validation.md) - renamed from `plugins/devops-tools/skills/asciinema-streaming-backup/references/autonomous-validation.md`
- [GitHub Actions Workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/references/github-workflow.md) - renamed from `plugins/devops-tools/skills/asciinema-streaming-backup/references/github-workflow.md`
- [Idle Chunker Script](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/references/idle-chunker.md) - renamed from `plugins/devops-tools/skills/asciinema-streaming-backup/references/idle-chunker.md`
- [Setup Scripts](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/references/setup-scripts.md) - renamed from `plugins/devops-tools/skills/asciinema-streaming-backup/references/setup-scripts.md`

</details>


### Commands

<details>
<summary><strong>asciinema-tools</strong> (11 commands)</summary>

- [/asciinema-tools:analyze](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/analyze.md) - new (+46)
- [/asciinema-tools:backup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/backup.md) - new (+39)
- [/asciinema-tools:bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/bootstrap.md) - new (+247)
- [/asciinema-tools:convert](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/convert.md) - new (+42)
- [/asciinema-tools:format](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/format.md) - new (+35)
- [/asciinema-tools:full-workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/full-workflow.md) - new (+53)
- [/asciinema-tools:hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/hooks.md) - new (+52)
- [/asciinema-tools:play](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/play.md) - new (+39)
- [/asciinema-tools:post-session](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/post-session.md) - new (+50)
- [/asciinema-tools:record](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/record.md) - new (+36)
- [/asciinema-tools:setup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/setup.md) - new (+48)

</details>


## Other Documentation

### Other

- [Example: If WebSearch found "Temporal Fusion Transformer"](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/alpha-forge-exploration.md) - updated (+24)

## [7.15.4](https://github.com/terrylica/cc-skills/compare/v7.15.3...v7.15.4) (2025-12-24)


### Bug Fixes

* **docs:** update link convention documentation for marketplace plugins ([2caf502](https://github.com/terrylica/cc-skills/commit/2caf502ab8daee3b2d7df8bc19d56767b436eab6))





---

## Documentation Changes

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+9/-1)

## Other Documentation

### Other

- [Link Patterns Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/link-validator/references/link-patterns.md) - updated (+27/-17)

## [7.15.3](https://github.com/terrylica/cc-skills/compare/v7.15.2...v7.15.3) (2025-12-24)


### Bug Fixes

* **validator:** correct link convention for marketplace plugins ([840f150](https://github.com/terrylica/cc-skills/commit/840f150a43dc1f8ea174ed85cbb43ec531c55a3e))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>alpha-forge-worktree</strong> (1 change)</summary>

- [worktree-manager](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-worktree/skills/worktree-manager/SKILL.md) - updated (+2/-2)

</details>

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [mlflow-python](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/mlflow-python/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>iterm2-layout-config</strong> (1 change)</summary>

- [iterm2-layout](https://github.com/terrylica/cc-skills/blob/main/plugins/iterm2-layout-config/skills/iterm2-layout/SKILL.md) - updated (+1/-1)

</details>


### Skill References

<details>
<summary><strong>alpha-forge-worktree/worktree-manager</strong> (1 file)</summary>

- [Alpha-Forge Worktree Naming Conventions](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-worktree/skills/worktree-manager/references/naming-conventions.md) - updated (+1/-1)

</details>

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [Without heredoc, zsh interprets directly](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+1/-1)

</details>

## [7.15.2](https://github.com/terrylica/cc-skills/compare/v7.15.1...v7.15.2) (2025-12-24)


### Bug Fixes

* **skills:** use relative paths for in-repo ADR links ([f2c5090](https://github.com/terrylica/cc-skills/commit/f2c5090b1877d872207d2bbf3004df360d585da0))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>alpha-forge-worktree</strong> (1 change)</summary>

- [worktree-manager](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-worktree/skills/worktree-manager/SKILL.md) - updated (+2/-2)

</details>

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [mlflow-python](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/mlflow-python/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>iterm2-layout-config</strong> (1 change)</summary>

- [iterm2-layout](https://github.com/terrylica/cc-skills/blob/main/plugins/iterm2-layout-config/skills/iterm2-layout/SKILL.md) - updated (+1/-1)

</details>


### Skill References

<details>
<summary><strong>alpha-forge-worktree/worktree-manager</strong> (1 file)</summary>

- [Alpha-Forge Worktree Naming Conventions](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-worktree/skills/worktree-manager/references/naming-conventions.md) - updated (+1/-1)

</details>

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [Without heredoc, zsh interprets directly](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+1/-1)

</details>

## [7.15.1](https://github.com/terrylica/cc-skills/compare/v7.15.0...v7.15.1) (2025-12-24)


### Bug Fixes

* **skills:** apply validate_skill.py to all production skills ([61bf292](https://github.com/terrylica/cc-skills/commit/61bf2921c58185f74bbd339f7cea64b1c3c2ef5b))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>alpha-forge-worktree</strong> (1 change)</summary>

- [worktree-manager](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-worktree/skills/worktree-manager/SKILL.md) - updated (+2/-2)

</details>

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [mlflow-python](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/mlflow-python/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>iterm2-layout-config</strong> (1 change)</summary>

- [iterm2-layout](https://github.com/terrylica/cc-skills/blob/main/plugins/iterm2-layout-config/skills/iterm2-layout/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>itp</strong> (2 changes)</summary>

- [mise-configuration](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-configuration/SKILL.md) - updated (+3/-2)
- [mise-tasks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/SKILL.md) - updated (+3/-2)

</details>


### Skill References

<details>
<summary><strong>alpha-forge-worktree/worktree-manager</strong> (1 file)</summary>

- [Alpha-Forge Worktree Naming Conventions](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-worktree/skills/worktree-manager/references/naming-conventions.md) - updated (+1/-1)

</details>

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [Without heredoc, zsh interprets directly](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+1/-1)

</details>

# [7.15.0](https://github.com/terrylica/cc-skills/compare/v7.14.2...v7.15.0) (2025-12-24)


### Features

* **skill-architecture:** add comprehensive skill validator with interactive clarification ([5d6bdcf](https://github.com/terrylica/cc-skills/commit/5d6bdcfb284aca33b714bf9d8aca609d04d79790))

## [7.14.2](https://github.com/terrylica/cc-skills/compare/v7.14.1...v7.14.2) (2025-12-24)


### Bug Fixes

* **skills:** improve YAML frontmatter with TRIGGERS and allowed-tools ([99ba698](https://github.com/terrylica/cc-skills/commit/99ba698927415f8e46887dd34982e99f1dd95890))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/SKILL.md) - updated (+2/-1)

</details>

<details>
<summary><strong>notion-api</strong> (1 change)</summary>

- [notion-sdk](https://github.com/terrylica/cc-skills/blob/main/plugins/notion-api/skills/notion-sdk/SKILL.md) - updated (+2/-1)

</details>

## [7.14.1](https://github.com/terrylica/cc-skills/compare/v7.14.0...v7.14.1) (2025-12-24)


### Bug Fixes

* **semantic-release:** add bash heredoc wrappers for zsh compatibility ([1e04d40](https://github.com/terrylica/cc-skills/commit/1e04d40ae4f369c0e8501cc587d0c5259d4490e9))





---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>itp/semantic-release</strong> (1 file)</summary>

- [Local Release Workflow (Canonical)](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/local-release-workflow.md) - updated (+10)

</details>

# [7.14.0](https://github.com/terrylica/cc-skills/compare/v7.13.0...v7.14.0) (2025-12-24)


### Features

* **notion-api:** add test suite and documentation insights from integration testing ([8934bea](https://github.com/terrylica/cc-skills/commit/8934bea30b16bc240e14ea5173667f4ccb793d18))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/SKILL.md) - updated (+44)

</details>

<details>
<summary><strong>notion-api</strong> (1 change)</summary>

- [notion-sdk](https://github.com/terrylica/cc-skills/blob/main/plugins/notion-api/skills/notion-sdk/SKILL.md) - updated (+125/-2)

</details>


### Skill References

<details>
<summary><strong>notion-api/notion-sdk</strong> (3 files)</summary>

- [Notion Block Types Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/notion-api/skills/notion-sdk/references/block-types.md) - updated (+37)
- [Pagination Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/notion-api/skills/notion-sdk/references/pagination.md) - updated (+30)
- [Notion Property Types Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/notion-api/skills/notion-sdk/references/property-types.md) - updated (+34)

</details>

# [7.13.0](https://github.com/terrylica/cc-skills/compare/v7.12.0...v7.13.0) (2025-12-23)


### Features

* **ralph:** add 5-part autonomous loop enhancement ([083652e](https://github.com/terrylica/cc-skills/commit/083652e5ed1edecc8d9345f1679274a541d2d39e))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (3 commands)</summary>

- [Ralph Loop: Audit Now](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/audit-now.md) - new (+110)
- [Ralph Loop: Encourage](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/encourage.md) - new (+90)
- [Ralph Loop: Forbid](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/forbid.md) - new (+100)

</details>

# [7.12.0](https://github.com/terrylica/cc-skills/compare/v7.11.1...v7.12.0) (2025-12-23)


### Features

* **asciinema-recorder:** add AskUserQuestion flows for interactive recording setup ([f0cdc8d](https://github.com/terrylica/cc-skills/commit/f0cdc8d6638cfac16eda72f0666ffa4bc6c015da))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [asciinema-recorder](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-recorder/SKILL.md) - updated (+130/-23)

</details>

## [7.11.1](https://github.com/terrylica/cc-skills/compare/v7.11.0...v7.11.1) (2025-12-23)


### Bug Fixes

* **ralph:** always prompt for preset confirmation before loop start ([86596f9](https://github.com/terrylica/cc-skills/commit/86596f9fdfee72ab42eb6f1e4e7742260667a537))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated (+38/-10)

</details>

# [7.11.0](https://github.com/terrylica/cc-skills/compare/v7.10.0...v7.11.0) (2025-12-23)


### Features

* **notion-api:** add Notion API plugin with notion-client SDK ([0e8dd69](https://github.com/terrylica/cc-skills/commit/0e8dd69e9c6536e363cf6e56ae5935afb49859e6))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>notion-api</strong> (1 change)</summary>

- [notion-sdk](https://github.com/terrylica/cc-skills/blob/main/plugins/notion-api/skills/notion-sdk/SKILL.md) - new (+175)

</details>


### Plugin READMEs

- [Notion API Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/notion-api/README.md) - new (+86)

### Skill References

<details>
<summary><strong>notion-api/notion-sdk</strong> (4 files)</summary>

- [Notion Block Types Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/notion-api/skills/notion-sdk/references/block-types.md) - new (+329)
- [Pagination Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/notion-api/skills/notion-sdk/references/pagination.md) - new (+176)
- [Notion Property Types Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/notion-api/skills/notion-sdk/references/property-types.md) - new (+255)
- [Rich Text Formatting Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/notion-api/skills/notion-sdk/references/rich-text.md) - new (+239)

</details>

# [7.10.0](https://github.com/terrylica/cc-skills/compare/v7.9.0...v7.10.0) (2025-12-23)


### Features

* **semantic-release:** add auto-push workflow and HTTPS-first authentication ([f3d1a59](https://github.com/terrylica/cc-skills/commit/f3d1a596ebd8e73c88d175c59fdbb8f5f492f458))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/SKILL.md) - updated (+17/-22)

</details>


### Skill References

<details>
<summary><strong>itp/semantic-release</strong> (3 files)</summary>

- [Documentation Linking in Release Notes](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/doc-release-linking.md) - updated (+39/-22)
- [Local Release Workflow (Canonical)](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/local-release-workflow.md) - updated (+219/-276)
- [Environment-agnostic path](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/workflow-patterns.md) - updated (+21/-88)

</details>

# [7.9.0](https://github.com/terrylica/cc-skills/compare/v7.8.0...v7.9.0) (2025-12-23)


### Features

* **ralph:** add dual time tracking (runtime + wall-clock) ([222bc18](https://github.com/terrylica/cc-skills/commit/222bc189cb1fe10f72db419d104a33dec186ea4f))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| unknown | [Ralph Dual Time Tracking (Runtime + Wall-Clock)](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-22-ralph-dual-time-tracking.md) | new |

## Plugin Documentation

### Plugin READMEs

- [Ralph Plugin for Claude Code](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/README.md) - updated

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Status](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/status.md) - updated

</details>

# [7.8.0](https://github.com/terrylica/cc-skills/compare/v7.7.1...v7.8.0) (2025-12-23)


### Features

* **ralph:** add user guidance lists for RSSI autonomous loop ([ce57dd0](https://github.com/terrylica/cc-skills/commit/ce57dd04a9d59688ef9eb7d554cab9705723787b))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (1 command)</summary>

- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated

</details>


## Other Documentation

### Other

- [Example: If WebSearch found "Temporal Fusion Transformer"](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/alpha-forge-exploration.md) - updated

## [7.7.1](https://github.com/terrylica/cc-skills/compare/v7.7.0...v7.7.1) (2025-12-23)





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| unknown | [Ralph Stop Visibility Observability](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-22-ralph-stop-visibility-observability.md) | new |

## Plugin Documentation

### Plugin READMEs

- [Ralph Plugin for Claude Code](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/README.md) - updated

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated

# [7.7.0](https://github.com/terrylica/cc-skills/compare/v7.6.0...v7.7.0) (2025-12-23)


### Features

* **ralph:** add 5-layer stop visibility observability system ([ada180c](https://github.com/terrylica/cc-skills/commit/ada180c839be43255d9365671f48569c41f82954))





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [Skill Architecture Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/README.md) - updated

### Commands

<details>
<summary><strong>ralph</strong> (2 commands)</summary>

- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated
- [Ralph Loop: Status](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/status.md) - updated

</details>

# [7.6.0](https://github.com/terrylica/cc-skills/compare/v7.5.1...v7.6.0) (2025-12-22)


### Bug Fixes

* **ralph:** use exploration template for CONVERGED busywork blocking ([f9d96db](https://github.com/terrylica/cc-skills/commit/f9d96db23ea7c2c7fd3439f8e503819e2f0d7e72))


### Features

* **skill-architecture:** enforce bash compatibility in skill creation ([899b406](https://github.com/terrylica/cc-skills/commit/899b40653245488bb94bc77e316e2484ef468164))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| unknown | [Skill Bash Compatibility Enforcement](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-22-skill-bash-compatibility-enforcement.md) | new |

## Plugin Documentation

### Skills

<details>
<summary><strong>alpha-forge-worktree</strong> (1 change)</summary>

- [worktree-manager](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-worktree/skills/worktree-manager/SKILL.md) - updated

</details>

<details>
<summary><strong>devops-tools</strong> (5 changes)</summary>

- [asciinema-recorder](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-recorder/SKILL.md) - updated
- [asciinema-streaming-backup](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-streaming-backup/SKILL.md) - updated
- [doppler-secret-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/doppler-secret-validation/SKILL.md) - updated
- [mlflow-python](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/mlflow-python/SKILL.md) - updated
- [session-recovery](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-recovery/SKILL.md) - updated

</details>

<details>
<summary><strong>doc-build-tools</strong> (1 change)</summary>

- [pandoc-pdf-generation](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-build-tools/skills/pandoc-pdf-generation/SKILL.md) - updated

</details>

<details>
<summary><strong>doc-tools</strong> (1 change)</summary>

- [ascii-diagram-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/ascii-diagram-validator/SKILL.md) - updated

</details>

<details>
<summary><strong>dotfiles-tools</strong> (1 change)</summary>

- [chezmoi-workflows](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/skills/chezmoi-workflows/SKILL.md) - updated

</details>

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [pr-gfm-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/pr-gfm-validator/SKILL.md) - updated

</details>

<details>
<summary><strong>iterm2-layout-config</strong> (1 change)</summary>

- [iterm2-layout](https://github.com/terrylica/cc-skills/blob/main/plugins/iterm2-layout-config/skills/iterm2-layout/SKILL.md) - updated

</details>

<details>
<summary><strong>itp</strong> (6 changes)</summary>

- [adr-graph-easy-architect](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/adr-graph-easy-architect/SKILL.md) - updated
- [graph-easy](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/graph-easy/SKILL.md) - updated
- [mise Configuration SSoT](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-configuration/SKILL.md) - updated
- [mise Tasks Orchestration](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/SKILL.md) - updated
- [pypi-doppler](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/pypi-doppler/SKILL.md) - updated
- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/SKILL.md) - updated

</details>

<details>
<summary><strong>itp-hooks</strong> (1 change)</summary>

- [hooks-development](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/SKILL.md) - updated

</details>

<details>
<summary><strong>mql5com</strong> (1 change)</summary>

- [log-reader](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5com/skills/log-reader/SKILL.md) - updated

</details>

<details>
<summary><strong>notification-tools</strong> (1 change)</summary>

- [dual-channel-watchexec-notifications](https://github.com/terrylica/cc-skills/blob/main/plugins/notification-tools/skills/dual-channel-watchexec/SKILL.md) - updated

</details>

<details>
<summary><strong>quality-tools</strong> (1 change)</summary>

- [multi-agent-e2e-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/multi-agent-e2e-validation/SKILL.md) - updated

</details>


### Plugin Skills

- [skill-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/SKILL.md) - updated

### Plugin READMEs

- [ITP Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/README.md) - updated
- [Link Checker Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/link-checker/README.md) - updated

### Skill References

<details>
<summary><strong>alpha-forge-worktree/worktree-manager</strong> (1 file)</summary>

- [Alpha-Forge Worktree Naming Conventions](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-worktree/skills/worktree-manager/references/naming-conventions.md) - updated

</details>

<details>
<summary><strong>devops-tools/asciinema-streaming-backup</strong> (4 files)</summary>

- [Autonomous Validation Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-streaming-backup/references/autonomous-validation.md) - updated
- [GitHub Actions Workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-streaming-backup/references/github-workflow.md) - updated
- [Idle Chunker Script](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-streaming-backup/references/idle-chunker.md) - updated
- [Setup Scripts](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-streaming-backup/references/setup-scripts.md) - updated

</details>

<details>
<summary><strong>devops-tools/clickhouse-cloud-management</strong> (1 file)</summary>

- [SQL Patterns Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/clickhouse-cloud-management/references/sql-patterns.md) - updated

</details>

<details>
<summary><strong>devops-tools/doppler-secret-validation</strong> (1 file)</summary>

- [Doppler CLI Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/doppler-secret-validation/references/doppler-patterns.md) - updated

</details>

<details>
<summary><strong>devops-tools/doppler-workflows</strong> (2 files)</summary>

- [Use AWS credentials](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/doppler-workflows/references/aws-credentials.md) - updated
- [Publish package](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/doppler-workflows/references/pypi-publishing.md) - updated

</details>

<details>
<summary><strong>devops-tools/mlflow-python</strong> (1 file)</summary>

- [Authentication Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/mlflow-python/references/authentication.md) - updated

</details>

<details>
<summary><strong>doc-build-tools/latex-build</strong> (1 file)</summary>

- [PDF output](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-build-tools/skills/latex-build/references/common-commands.md) - updated

</details>

<details>
<summary><strong>doc-build-tools/latex-setup</strong> (1 file)</summary>

- [Add to ~/.zshrc or ~/.bash_profile](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-build-tools/skills/latex-setup/references/troubleshooting.md) - updated

</details>

<details>
<summary><strong>doc-tools/ascii-diagram-validator</strong> (2 files)</summary>

- [ASCII Alignment Checker - Integration Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/ascii-diagram-validator/references/INTEGRATION_GUIDE.md) - updated
- [ASCII Alignment Checker - Script Design Report](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/ascii-diagram-validator/references/SCRIPT_DESIGN_REPORT.md) - updated

</details>

<details>
<summary><strong>dotfiles-tools/chezmoi-workflows</strong> (4 files)</summary>

- [Configuration](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/skills/chezmoi-workflows/references/configuration.md) - updated
- [Prompt Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/skills/chezmoi-workflows/references/prompt-patterns.md) - updated
- [Secret Detection](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/skills/chezmoi-workflows/references/secret-detection.md) - updated
- [macOS](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/skills/chezmoi-workflows/references/setup.md) - updated

</details>

<details>
<summary><strong>itp-hooks/hooks-development</strong> (4 files)</summary>

- [Debugging Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/debugging-guide.md) - updated
- [Hook Templates](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/hook-templates.md) - updated
- [Without heredoc, zsh interprets directly](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated
- [Hook Visibility Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/visibility-patterns.md) - updated

</details>

<details>
<summary><strong>itp/code-hardcode-audit</strong> (1 file)</summary>

- [Troubleshooting](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/code-hardcode-audit/references/troubleshooting.md) - updated

</details>

<details>
<summary><strong>itp/implement-plan-preflight</strong> (1 file)</summary>

- [Preflight Workflow Steps](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/implement-plan-preflight/references/workflow-steps.md) - updated

</details>

<details>
<summary><strong>itp/mise-configuration</strong> (2 files)</summary>

- [GitHub Token Multi-Account Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-configuration/references/github-tokens.md) - updated
- [mise [env] Code Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-configuration/references/patterns.md) - updated

</details>

<details>
<summary><strong>itp/semantic-release</strong> (8 files)</summary>

- [Authentication for semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/authentication.md) - updated
- [Documentation Linking in Release Notes](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/doc-release-linking.md) - updated
- [Local Release Workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/local-release-workflow.md) - updated
- [PyPI Publishing with Doppler Secret Management](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/pypi-publishing-with-doppler.md) - updated
- [Python Projects with semantic-release (Node.js) - 2025 Production Pattern](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/python-projects-nodejs-semantic-release.md) - updated
- [Install Node.js 24 LTS (using mise)](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/troubleshooting.md) - updated
- [Version Alignment Standards](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/version-alignment.md) - updated
- [Environment-agnostic path](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/workflow-patterns.md) - updated

</details>

<details>
<summary><strong>notification-tools/dual-channel-watchexec</strong> (5 files)</summary>

- [❌ WRONG - Sends HTML to Pushover](https://github.com/terrylica/cc-skills/blob/main/plugins/notification-tools/skills/dual-channel-watchexec/references/common-pitfalls.md) - updated
- [Load Pushover credentials from Doppler](https://github.com/terrylica/cc-skills/blob/main/plugins/notification-tools/skills/dual-channel-watchexec/references/credential-management.md) - updated
- [Canonical source for Pushover credentials](https://github.com/terrylica/cc-skills/blob/main/plugins/notification-tools/skills/dual-channel-watchexec/references/pushover-integration.md) - updated
- [Python API call](https://github.com/terrylica/cc-skills/blob/main/plugins/notification-tools/skills/dual-channel-watchexec/references/telegram-html.md) - updated
- [Use stat to check modification time](https://github.com/terrylica/cc-skills/blob/main/plugins/notification-tools/skills/dual-channel-watchexec/references/watchexec-patterns.md) - updated

</details>

<details>
<summary><strong>quality-tools/code-clone-assistant</strong> (1 file)</summary>

- [Create working directory](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/code-clone-assistant/references/complete-workflow.md) - updated

</details>


### Commands

<details>
<summary><strong>dotfiles-tools</strong> (1 command)</summary>

- [Dotfiles Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/commands/hooks.md) - updated

</details>

<details>
<summary><strong>git-account-validator</strong> (1 command)</summary>

- [Git Account Validator Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/git-account-validator/commands/hooks.md) - updated

</details>

<details>
<summary><strong>itp</strong> (4 commands)</summary>

- [⛔ ITP Workflow — STOP AND READ](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/go.md) - updated
- [ITP Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/hooks.md) - updated
- [⛔ Add Plugin to Marketplace — STOP AND READ](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/plugin-add.md) - updated
- [ITP Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/setup.md) - updated

</details>

<details>
<summary><strong>itp-hooks</strong> (1 command)</summary>

- [ITP Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/commands/hooks.md) - updated

</details>

<details>
<summary><strong>statusline-tools</strong> (2 commands)</summary>

- [Status Line Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/commands/hooks.md) - updated
- [Status Line Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/commands/setup.md) - updated

</details>


## Other Documentation

### Other

- [AWS Credentials Management with Doppler](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/doppler-workflows/AWS_WORKFLOW.md) - updated
- [Step 4: List all sessions currently stored](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-recovery/TROUBLESHOOTING.md) - updated
- [Modern LaTeX Workflow for macOS (2025)](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-build-tools/skills/latex-setup/REFERENCE.md) - updated
- [[3.0.0](https://github.com/terrylica/cc-skills/compare/v2.0.0...v3.0.0) (2025-12-04)](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/CHANGELOG.md) - updated
- [Implementation Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/notification-tools/skills/dual-channel-watchexec/reference.md) - updated
- [Example: If WebSearch found "Temporal Fusion Transformer"](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/alpha-forge-exploration.md) - updated
- [Bash Compatibility for Skills](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/references/bash-compatibility.md) - new
- [Creation Workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/references/creation-workflow.md) - updated
- [Error Message Style Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/references/error-message-style.md) - updated
- [Path Patterns Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/skill-architecture/references/path-patterns.md) - updated

## [7.5.1](https://github.com/terrylica/cc-skills/compare/v7.5.0...v7.5.1) (2025-12-22)


### Bug Fixes

* **ralph:** prevent orphaned running state on script failure ([b21369c](https://github.com/terrylica/cc-skills/commit/b21369c2d6519243f898970f223860255769385f))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ralph</strong> (3 commands)</summary>

- [Ralph SDK Harness](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/harness.md) - updated
- [Ralph Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/hooks.md) - updated
- [Ralph Loop: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/start.md) - updated

</details>

# [7.5.0](https://github.com/terrylica/cc-skills/compare/v7.4.0...v7.5.0) (2025-12-22)


### Features

* **devops-tools:** add interactive configuration to asciinema-streaming-backup ([b431465](https://github.com/terrylica/cc-skills/commit/b4314650e064a1755774da780b494e8d0a599424))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [asciinema-streaming-backup](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-streaming-backup/SKILL.md) - updated

</details>


### Plugin READMEs

- [devops-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/README.md) - updated

### Skill References

<details>
<summary><strong>devops-tools/asciinema-streaming-backup</strong> (3 files)</summary>

- [Autonomous Validation Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-streaming-backup/references/autonomous-validation.md) - new
- [Idle Chunker Script](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-streaming-backup/references/idle-chunker.md) - updated
- [Setup Scripts](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-streaming-backup/references/setup-scripts.md) - updated

</details>

# [7.4.0](https://github.com/terrylica/cc-skills/compare/v7.3.0...v7.4.0) (2025-12-22)


### Features

* **asciinema-streaming-backup:** add AskUserQuestion flows and GitHub account detection ([03affac](https://github.com/terrylica/cc-skills/commit/03affacf523bb14ffd9dd9fa8f4e7f159c6f7fb5))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [asciinema-streaming-backup](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-streaming-backup/SKILL.md) - updated

</details>

# [7.3.0](https://github.com/terrylica/cc-skills/compare/v7.2.2...v7.3.0) (2025-12-22)


### Features

* **devops-tools:** add asciinema-streaming-backup skill ([ee5fb0f](https://github.com/terrylica/cc-skills/commit/ee5fb0f11a62051b776a3ed4099371da5c29f730))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [asciinema-streaming-backup](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-streaming-backup/SKILL.md) - new

</details>


### Plugin READMEs

- [devops-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/README.md) - updated

### Skill References

<details>
<summary><strong>devops-tools/asciinema-streaming-backup</strong> (3 files)</summary>

- [GitHub Actions Workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-streaming-backup/references/github-workflow.md) - new
- [Idle Chunker Script](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-streaming-backup/references/idle-chunker.md) - new
- [Setup Scripts](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-streaming-backup/references/setup-scripts.md) - new

</details>

## [7.2.2](https://github.com/terrylica/cc-skills/compare/v7.2.1...v7.2.2) (2025-12-22)


### Bug Fixes

* **devops-tools:** remove -c flag from asciinema-recorder ([d646014](https://github.com/terrylica/cc-skills/commit/d646014686bea050f11fffd47e7b80ff8b09c1b7))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [asciinema-recorder](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-recorder/SKILL.md) - updated

</details>

## [7.2.1](https://github.com/terrylica/cc-skills/compare/v7.2.0...v7.2.1) (2025-12-22)


### Bug Fixes

* **devops-tools:** expand asciinema-recorder trigger phrases ([2a01131](https://github.com/terrylica/cc-skills/commit/2a011311e635c4abcf26eea9c00692d732e6952d))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [asciinema-recorder](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-recorder/SKILL.md) - updated

</details>


### Plugin READMEs

- [devops-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/README.md) - updated

# [7.2.0](https://github.com/terrylica/cc-skills/compare/v7.1.0...v7.2.0) (2025-12-22)


### Features

* **devops-tools:** add asciinema-recorder skill for recording Claude Code sessions ([bc52a73](https://github.com/terrylica/cc-skills/commit/bc52a7366694a901a574ee778fe2f05c7316f2cb))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [asciinema-recorder](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-recorder/SKILL.md) - new

</details>


### Plugin READMEs

- [devops-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/README.md) - updated

# [7.1.0](https://github.com/terrylica/cc-skills/compare/v7.0.0...v7.1.0) (2025-12-22)


### Features

* **statusline-tools:** add UTC timestamp with date to status line ([44030fe](https://github.com/terrylica/cc-skills/commit/44030fee4b9e84666061026544fd270890573868))

# [7.0.0](https://github.com/terrylica/cc-skills/compare/v6.5.1...v7.0.0) (2025-12-22)


* feat(asciinema-player)!: rewrite for iTerm2-only playback ([c23d646](https://github.com/terrylica/cc-skills/commit/c23d64642dbcabdc0ecd95c67c79f4bd6bc2c49e))


### BREAKING CHANGES

* Browser-based player removed. Now uses iTerm2 CLI only.

Why:
- Browser player crashes on large files (>100MB) due to 4GB memory limit
- iTerm2 CLI streams from disk with minimal memory usage
- Instant startup vs slow download+parse

Changes:
- Remove browser player (serve_cast.py, player-template.html)
- Add iTerm2 requirement check in preflight
- Use AppleScript to spawn clean window (bypasses default arrangements)
- AskUserQuestion for speed: 2x, 6x, 16x, custom
- AskUserQuestion for options: idle limit, loop, resize, markers (multi-select)
- Add CLI options reference table
- Add AppleScript reference for clean window creation

Platform: macOS only (requires iTerm2)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [asciinema-player](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-player/SKILL.md) - updated

</details>


### Skill References

<details>
<summary><strong>devops-tools/asciinema-player</strong> (1 file)</summary>

- [Player Options](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-player/references/player-options.md) - deleted

</details>

## [6.5.1](https://github.com/terrylica/cc-skills/compare/v6.5.0...v6.5.1) (2025-12-22)

# [6.5.0](https://github.com/terrylica/cc-skills/compare/v6.4.1...v6.5.0) (2025-12-22)


### Features

* **dotfiles-tools:** enhance chezmoi hook to detect untracked config files ([ff71693](https://github.com/terrylica/cc-skills/commit/ff7169337f0583a803708ea98e3a5fe432235da8))

## [6.4.1](https://github.com/terrylica/cc-skills/compare/v6.4.0...v6.4.1) (2025-12-21)


### Bug Fixes

* **asciinema-player:** use semver range for auto-upgrade with minimum version ([fd42458](https://github.com/terrylica/cc-skills/commit/fd4245897bb2afddea2caa9822c81126a63acb49))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [asciinema-player](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-player/SKILL.md) - updated

</details>

# [6.4.0](https://github.com/terrylica/cc-skills/compare/v6.3.1...v6.4.0) (2025-12-21)


### Bug Fixes

* **asciinema-player:** upgrade to v3.10.0 for asciicast v3 support ([44db67c](https://github.com/terrylica/cc-skills/commit/44db67c2240ba01b78accf3bd37553bb50c252d5))
* **asciinema-player:** use available port when default is occupied ([fa55afc](https://github.com/terrylica/cc-skills/commit/fa55afcb9cb717d829429cdde721514ece925bb9))


### Features

* **asciinema-player:** redesign with mandatory AskUserQuestion flows and preflight checks ([d3985a8](https://github.com/terrylica/cc-skills/commit/d3985a808fd88406c57f25eebe29301516017a8f))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [asciinema-player](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-player/SKILL.md) - updated

</details>


## Other Documentation

### Other

- [Example: If WebSearch found "Temporal Fusion Transformer"](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/alpha-forge-exploration.md) - updated

## [6.3.1](https://github.com/terrylica/cc-skills/compare/v6.3.0...v6.3.1) (2025-12-21)


### Bug Fixes

* **statusline-tools:** correct two-line layout ([2479105](https://github.com/terrylica/cc-skills/commit/2479105f0d4ef2fc6f3f0d64070c1339b87cc59a))

# [6.3.0](https://github.com/terrylica/cc-skills/compare/v6.2.0...v6.3.0) (2025-12-21)


### Features

* **statusline-tools:** change to two-line status format ([90fb9a4](https://github.com/terrylica/cc-skills/commit/90fb9a428d69dcf3dfb69e6c5f72baf890602b8f))

# [6.2.0](https://github.com/terrylica/cc-skills/compare/v6.1.0...v6.2.0) (2025-12-21)


### Features

* **devops-tools:** add AskUserQuestion-driven workflow to asciinema-player ([316b829](https://github.com/terrylica/cc-skills/commit/316b82909fe82b43383d316b9f9b9b50e80170c6))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [asciinema-player](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-player/SKILL.md) - updated

</details>

# [6.1.0](https://github.com/terrylica/cc-skills/compare/v6.0.0...v6.1.0) (2025-12-21)


### Features

* **devops-tools:** add asciinema-player skill for terminal recordings ([5cbc4d1](https://github.com/terrylica/cc-skills/commit/5cbc4d16ea2c0b8cd65d9239e14c77ccecbf1571))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [asciinema-player](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-player/SKILL.md) - new

</details>


### Plugin READMEs

- [devops-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/README.md) - updated

### Skill References

<details>
<summary><strong>devops-tools/asciinema-player</strong> (1 file)</summary>

- [Player Options Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/asciinema-player/references/player-options.md) - new

</details>

# [6.0.0](https://github.com/terrylica/cc-skills/compare/v5.25.0...v6.0.0) (2025-12-21)


### Bug Fixes

* **ralph:** align implementation with design philosophy ([e7d7755](https://github.com/terrylica/cc-skills/commit/e7d775528b4dc08dee47c467418bd5e0235fa53c))


### BREAKING CHANGES

* **ralph:** Ralph is now Alpha Forge exclusive

- Delete validation templates (linting/test coverage = busywork)
- Remove validation.py and render_validation_round method
- Zero idle tolerance: MAX_IDLE_BEFORE_EXPLORE = 1
- Remove exponential backoff waiting pattern (immediate exploration)
- Remove universal.py adapter (Alpha Forge only)
- Update registry to return None for non-Alpha Forge projects
- Update Design Philosophy: replace "Adapter Extensibility" with "Alpha Forge Exclusive"
- Update README to reflect all changes
- Remove busywork references from exploration templates





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [Ralph Plugin for Claude Code](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/README.md) - updated

## Other Documentation

### Other

- [Example: If WebSearch found "Temporal Fusion Transformer"](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/alpha-forge-exploration.md) - updated
- [exploration-mode](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/exploration-mode.md) - updated
- [validation-round-1](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/validation-round-1.md) - deleted
- [validation-round-2](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/validation-round-2.md) - deleted
- [validation-round-3](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/validation-round-3.md) - deleted

# [5.25.0](https://github.com/terrylica/cc-skills/compare/v5.24.3...v5.25.0) (2025-12-21)


### Features

* **release-notes:** expand documentation linking to all markdown files ([86fb31e](https://github.com/terrylica/cc-skills/commit/86fb31e5ebeabe45b7093e3cee3f29ec02475b8e))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| accepted | [Documentation Links in Release Notes](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-06-release-notes-adr-linking.md) | updated |
| implemented | [Shell Command Portability for Zsh Compatibility](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-06-shell-command-portability-zsh.md) | coupled |
| accepted | [mise Environment Variables as Centralized Configuration](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-08-mise-env-centralized-config.md) | updated |

### Design Specs

- [Documentation Links in Release Notes](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-06-release-notes-adr-linking/spec.md) (updated)
- [Shell Command Portability for Zsh Compatibility](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-06-shell-command-portability-zsh/spec.md) (updated)
- [mise Environment Variables as Centralized Configuration](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-08-mise-env-centralized-config/spec.md) (updated)

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/SKILL.md) - updated

</details>


### Skill References

<details>
<summary><strong>itp/semantic-release</strong> (3 files)</summary>

- [Adr Release Linking](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/adr-release-linking.md) - deleted
- [Documentation Linking in Release Notes](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/doc-release-linking.md) - new
- [Resources](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/resources.md) - updated

</details>

## [5.24.3](https://github.com/terrylica/cc-skills/compare/v5.24.2...v5.24.3) (2025-12-21)


### Bug Fixes

* **ralph:** align dependencies with best practices, add design philosophy ([f00f872](https://github.com/terrylica/cc-skills/commit/f00f872584fd503616db0279391af3296a440744)), closes [Hi#Impact](https://github.com/Hi/issues/Impact)

## [5.24.2](https://github.com/terrylica/cc-skills/compare/v5.24.1...v5.24.2) (2025-12-21)

## [5.24.1](https://github.com/terrylica/cc-skills/compare/v5.24.0...v5.24.1) (2025-12-21)


### Bug Fixes

* **release:** add revert type to release rules ([66a5753](https://github.com/terrylica/cc-skills/commit/66a5753a022aa46ff4180da434e8001f21dcb8a8))


### Reverts

* **ralph:** remove redundant cooldown, use existing stamina backoff ([ab95990](https://github.com/terrylica/cc-skills/commit/ab95990d9b2f0bc9f2984dd51f2d8b93934d2c6f))

# [5.24.0](https://github.com/terrylica/cc-skills/compare/v5.23.0...v5.24.0) (2025-12-21)


### Features

* **ralph:** add idle command guard to block repetitive git status ([4551a7a](https://github.com/terrylica/cc-skills/commit/4551a7a619eeb61d0b39f03ba0cc31110c95fe9c))

# [5.23.0](https://github.com/terrylica/cc-skills/compare/v5.22.0...v5.23.0) (2025-12-21)


### Features

* **ralph:** exponential backoff for idle detection (stamina-style) ([b9c5f13](https://github.com/terrylica/cc-skills/commit/b9c5f13819342bcd05610e7a0dde6b54025bfca1))

# [5.22.0](https://github.com/terrylica/cc-skills/compare/v5.21.5...v5.22.0) (2025-12-21)


### Features

* **ralph:** deterministic idle detection to prevent token waste ([128ae77](https://github.com/terrylica/cc-skills/commit/128ae776de5ddd46015f029640f801662f4e1947))

## [5.21.5](https://github.com/terrylica/cc-skills/compare/v5.21.4...v5.21.5) (2025-12-21)


### Bug Fixes

* **ralph:** forbid idle monitoring loop that wastes tokens ([a263339](https://github.com/terrylica/cc-skills/commit/a263339bfa9711aa3f3e4dff305bf29fd2930d4e))

## [5.21.4](https://github.com/terrylica/cc-skills/compare/v5.21.3...v5.21.4) (2025-12-21)


### Bug Fixes

* **ralph:** prevent premature stop when task complete but agent idling ([ff7ab6f](https://github.com/terrylica/cc-skills/commit/ff7ab6fb1cc58a93c8acb8b40eff958a3477fc3e))

## [5.21.3](https://github.com/terrylica/cc-skills/compare/v5.21.2...v5.21.3) (2025-12-21)


### Bug Fixes

* **ralph:** actionable RSSI hook with 5-step loop ([8f60322](https://github.com/terrylica/cc-skills/commit/8f60322da46da54f7bd6622cd69e849c852c896c))

## [5.21.2](https://github.com/terrylica/cc-skills/compare/v5.21.1...v5.21.2) (2025-12-21)


### Bug Fixes

* **ralph:** ultra-minimal RSSI hook output for no_focus mode ([ce1200a](https://github.com/terrylica/cc-skills/commit/ce1200aea829e990baca0127d53399e1a67a6d4d))

## [5.21.1](https://github.com/terrylica/cc-skills/compare/v5.21.0...v5.21.1) (2025-12-21)


### Bug Fixes

* **ralph:** trim stop hook output to concise status only ([6bfc8d1](https://github.com/terrylica/cc-skills/commit/6bfc8d162d50ddceb8f59d88ca672707a81a8506))

# [5.21.0](https://github.com/terrylica/cc-skills/compare/v5.20.0...v5.21.0) (2025-12-21)


### Features

* **ralph:** goal-driven dynamic search depth for alpha-forge integration ([aa714ef](https://github.com/terrylica/cc-skills/commit/aa714ef6a15b58c55bfa9952a6e327ce729d5306))

# [5.20.0](https://github.com/terrylica/cc-skills/compare/v5.19.3...v5.20.0) (2025-12-21)


### Features

* **ralph:** dynamic iterative WebSearch for SOTA discovery ([a863788](https://github.com/terrylica/cc-skills/commit/a86378884c2178e1b5f2aa6ec6b0149d39c66cd4))

## [5.19.3](https://github.com/terrylica/cc-skills/compare/v5.19.2...v5.19.3) (2025-12-21)


### Bug Fixes

* **ralph:** make RSSI template action-oriented, forbid status-only responses ([66515d1](https://github.com/terrylica/cc-skills/commit/66515d17718e829679a8b528fc191ef681757703))

## [5.19.2](https://github.com/terrylica/cc-skills/compare/v5.19.1...v5.19.2) (2025-12-21)


### Bug Fixes

* **ralph:** add no-focus mode convergence detection ([05330ff](https://github.com/terrylica/cc-skills/commit/05330ffb12feaf7e6bf8a3be137d843ac1945ec7))

## [5.19.1](https://github.com/terrylica/cc-skills/compare/v5.19.0...v5.19.1) (2025-12-21)


### Bug Fixes

* **devops-tools,quality-tools:** update gapless-crypto-data to gapless-crypto-clickhouse ([4b4510d](https://github.com/terrylica/cc-skills/commit/4b4510da3520cad3fdbc116d729ee5e37bb5ecad))

# [5.19.0](https://github.com/terrylica/cc-skills/compare/v5.18.0...v5.19.0) (2025-12-21)


### Features

* **ralph:** use gapless-crypto-clickhouse for historical data ([c516bec](https://github.com/terrylica/cc-skills/commit/c516becad68739e7542beb9b8f6164cc22c0209f))

# [5.18.0](https://github.com/terrylica/cc-skills/compare/v5.17.0...v5.18.0) (2025-12-21)


### Features

* **ralph:** add DATA INTEGRITY constraints for real historical data ([8e20ad4](https://github.com/terrylica/cc-skills/commit/8e20ad4e0d9b5d65b6cc7a646057afb650f49c6f))

# [5.17.0](https://github.com/terrylica/cc-skills/compare/v5.16.0...v5.17.0) (2025-12-21)


### Features

* **ralph:** add AUTONOMOUS MODE directive and SDK harness ([1de8eb4](https://github.com/terrylica/cc-skills/commit/1de8eb480c355c2cd61554eac9d0280e6a21fd3e))

# [5.16.0](https://github.com/terrylica/cc-skills/compare/v5.15.0...v5.16.0) (2025-12-21)


### Bug Fixes

* **ralph:** correct adapter detection path in start.md ([80d309c](https://github.com/terrylica/cc-skills/commit/80d309c4497f79b77c4b0d8c05928a323e6ee2ff))


### Features

* **ralph:** auto-invoke /research command for Alpha Forge research sessions ([09d7033](https://github.com/terrylica/cc-skills/commit/09d7033caebbc6ccad9ecf16e21e55b3cced0bf6))
* **ralph:** implement SOTA iterative patterns for Alpha Forge RSSI ([d71f150](https://github.com/terrylica/cc-skills/commit/d71f15049b088fa42a89897e71786211425e42d2))

# [5.15.0](https://github.com/terrylica/cc-skills/compare/v5.14.0...v5.15.0) (2025-12-21)


### Features

* **ralph:** auto-select focus files without prompting ([463a984](https://github.com/terrylica/cc-skills/commit/463a984c1faeecbd6afe7db4a8e553bfae0879b4))

# [5.14.0](https://github.com/terrylica/cc-skills/compare/v5.13.0...v5.14.0) (2025-12-21)


### Features

* **ralph:** fail fast when version cannot be determined ([676c23b](https://github.com/terrylica/cc-skills/commit/676c23ba9fc9d6df53a9036e832886030f060edc))

# [5.13.0](https://github.com/terrylica/cc-skills/compare/v5.12.1...v5.13.0) (2025-12-21)


### Features

* **ralph:** show local repo version from package.json ([9798c88](https://github.com/terrylica/cc-skills/commit/9798c88a5767145fa1c121a818792c6ed3bffd2a))

## [5.12.1](https://github.com/terrylica/cc-skills/compare/v5.12.0...v5.12.1) (2025-12-21)


### Bug Fixes

* **ralph:** prefer local-dev when symlink directory exists ([fbe546e](https://github.com/terrylica/cc-skills/commit/fbe546ede847d448b440f683d88eb57f42b30dc1))

# [5.12.0](https://github.com/terrylica/cc-skills/compare/v5.11.1...v5.12.0) (2025-12-21)


### Features

* **ralph:** add version banner to /ralph:start ([80cb8ed](https://github.com/terrylica/cc-skills/commit/80cb8ed547aebadaa6e8bcac6399b96a6f26a002))

## [5.11.1](https://github.com/terrylica/cc-skills/compare/v5.11.0...v5.11.1) (2025-12-21)


### Bug Fixes

* **ralph:** add Alpha Forge research sessions to start.md discovery ([8229f38](https://github.com/terrylica/cc-skills/commit/8229f38f336307211486fef19f5483591d8ae7af))

# [5.11.0](https://github.com/terrylica/cc-skills/compare/v5.10.4...v5.11.0) (2025-12-21)


### Features

* **ralph:** add Alpha Forge research session discovery ([71b30d9](https://github.com/terrylica/cc-skills/commit/71b30d9e1223a225d0b394c9bd3df78955dff9df))

## [5.10.4](https://github.com/terrylica/cc-skills/compare/v5.10.3...v5.10.4) (2025-12-21)


### Bug Fixes

* **ralph:** add simple alpha-forge detection failsafe ([70465e6](https://github.com/terrylica/cc-skills/commit/70465e600786d1d54ef011a715483048ef7dbe3f))

## [5.10.3](https://github.com/terrylica/cc-skills/compare/v5.10.2...v5.10.3) (2025-12-21)


### Bug Fixes

* **ralph:** add parent directory detection to alpha-forge adapter ([406fb0e](https://github.com/terrylica/cc-skills/commit/406fb0e3be9076f11b5f239ce95ee3f62565af1d))

## [5.10.2](https://github.com/terrylica/cc-skills/compare/v5.10.1...v5.10.2) (2025-12-21)

## [5.10.1](https://github.com/terrylica/cc-skills/compare/v5.10.0...v5.10.1) (2025-12-21)


### Bug Fixes

* **ralph:** apply busywork filter at all stages for Alpha Forge ([51de144](https://github.com/terrylica/cc-skills/commit/51de144f7ac6fadcdc63ec173c5f8d95d7a3582a))

# [5.10.0](https://github.com/terrylica/cc-skills/compare/v5.9.3...v5.10.0) (2025-12-21)


### Features

* **ralph:** add reinforcement learning with persistent artifacts for Alpha Forge ([f8ea147](https://github.com/terrylica/cc-skills/commit/f8ea14763f000c20dad2ed1ec1f0c9a8db017487))

# [5.10.0](https://github.com/terrylica/cc-skills/compare/v5.9.3...v5.10.0) (2025-12-21)


### Features

* **ralph:** add reinforcement learning with persistent artifacts for Alpha Forge ([f8ea147](https://github.com/terrylica/cc-skills/commit/f8ea14763f000c20dad2ed1ec1f0c9a8db017487))

## [5.9.3](https://github.com/terrylica/cc-skills/compare/v5.9.2...v5.9.3) (2025-12-21)


### Bug Fixes

* **ralph:** strict busywork filter for Alpha Forge eternal loop ([7d69c49](https://github.com/terrylica/cc-skills/commit/7d69c49f375c2ffd92f3d77adf594e26740c3a23))

## [5.9.2](https://github.com/terrylica/cc-skills/compare/v5.9.1...v5.9.2) (2025-12-21)


### Bug Fixes

* **ralph:** detect research completion and stop loop ([7b60d70](https://github.com/terrylica/cc-skills/commit/7b60d70cd3ea07ea3e70dfee48cc07a3932f103c))

## [5.9.1](https://github.com/terrylica/cc-skills/compare/v5.9.0...v5.9.1) (2025-12-21)


### Bug Fixes

* **ralph:** improve adapter detection and completion for ITP workflow ([c311323](https://github.com/terrylica/cc-skills/commit/c311323d4300b63e12a4da15343f73acb2bedb65))

# [5.9.0](https://github.com/terrylica/cc-skills/compare/v5.8.7...v5.9.0) (2025-12-20)


### Bug Fixes

* **ralph:** use kill switch for reliable /ralph:stop termination ([27454e6](https://github.com/terrylica/cc-skills/commit/27454e615ef55462cb9db3cf6359aa2e58c734fc))


### Features

* **ralph:** add SLO enforcement for Alpha Forge projects ([70b024e](https://github.com/terrylica/cc-skills/commit/70b024e053f7425d0016924a710bb8e012aae2ba))
* **ralph:** add unified config schema with externalized magic numbers ([50eedb0](https://github.com/terrylica/cc-skills/commit/50eedb05ad8aea04c26d2bcbd8290f410f05d0c6))
* **ralph:** enhance /ralph:config with v2.0 unified schema ([f31fb7c](https://github.com/terrylica/cc-skills/commit/f31fb7c3f3dde2e8330c4dfe14fc583e57413e95))
* **ralph:** implement state machine in start/stop commands ([716cba3](https://github.com/terrylica/cc-skills/commit/716cba36eb8e5333572927e847cab259536ccf29))

## [5.8.7](https://github.com/terrylica/cc-skills/compare/v5.8.6...v5.8.7) (2025-12-20)


### Bug Fixes

* **ralph:** allow /ralph:stop to bypass loop guard ([c758374](https://github.com/terrylica/cc-skills/commit/c758374b1df5f5539e9711a213b75c8f55841e10))

## [5.8.6](https://github.com/terrylica/cc-skills/compare/v5.8.5...v5.8.6) (2025-12-20)


### Bug Fixes

* **ralph:** add PreToolUse hook to guard loop control files ([89cb426](https://github.com/terrylica/cc-skills/commit/89cb42641772e6de7844b4d72bda4e02eb499865))

## [5.8.5](https://github.com/terrylica/cc-skills/compare/v5.8.4...v5.8.5) (2025-12-20)


### Bug Fixes

* **ralph:** add explicit constraints to prevent self-termination ([f93a38a](https://github.com/terrylica/cc-skills/commit/f93a38aacedfd44ce26af2ee46661121bca82241))

## [5.8.4](https://github.com/terrylica/cc-skills/compare/v5.8.3...v5.8.4) (2025-12-20)


### Bug Fixes

* **ralph:** handle None values in theme dict for web discovery ([5d2f2ee](https://github.com/terrylica/cc-skills/commit/5d2f2ee2ac49a9baa43f262c8034a120f1fd637e))

## [5.8.3](https://github.com/terrylica/cc-skills/compare/v5.8.2...v5.8.3) (2025-12-20)


### Bug Fixes

* **ralph:** always use RSSI exploration mode in no_focus mode ([d6357f9](https://github.com/terrylica/cc-skills/commit/d6357f935719034f136d17f04a2e4131975d2933))

## [5.8.2](https://github.com/terrylica/cc-skills/compare/v5.8.1...v5.8.2) (2025-12-20)


### Bug Fixes

* **ralph:** remove invalid line-length from ruff.toml ([3152227](https://github.com/terrylica/cc-skills/commit/3152227d58902dbcaa43d1bb1827fb56ec24fe13))

## [5.8.1](https://github.com/terrylica/cc-skills/compare/v5.8.0...v5.8.1) (2025-12-20)

# [5.8.0](https://github.com/terrylica/cc-skills/compare/v5.7.1...v5.8.0) (2025-12-20)


### Bug Fixes

* **ralph:** use absolute import in rssi_meta.py ([690f137](https://github.com/terrylica/cc-skills/commit/690f1378e0eb3d444fc9e1753c9ad3591b82ab38))


### Features

* **ralph:** implement RSSI eternal loop architecture ([2b6bc06](https://github.com/terrylica/cc-skills/commit/2b6bc068b6cc2d2a546428f68f808d2159ae675b))

## [5.7.1](https://github.com/terrylica/cc-skills/compare/v5.7.0...v5.7.1) (2025-12-20)


### Bug Fixes

* **ralph:** align adapter tests with RSSI-only stopping design ([61e8ead](https://github.com/terrylica/cc-skills/commit/61e8ead76be3d6a851bb4bd03eb8cc40a3ee37db))

# [5.7.0](https://github.com/terrylica/cc-skills/compare/v5.6.0...v5.7.0) (2025-12-20)


### Features

* **ralph:** add plan mode discovery and user confirmation flow ([f59cc83](https://github.com/terrylica/cc-skills/commit/f59cc83af3e6bfa480a1aeef030a49facdb5a5c9))

# [5.6.0](https://github.com/terrylica/cc-skills/compare/v5.5.5...v5.6.0) (2025-12-20)


### Features

* **ralph:** add research experts and fix metrics display for Alpha Forge ([4f6a425](https://github.com/terrylica/cc-skills/commit/4f6a425c6f7b318b6db906ec09885aee5f045785))

## [5.5.5](https://github.com/terrylica/cc-skills/compare/v5.5.4...v5.5.5) (2025-12-20)


### Bug Fixes

* **statusline-tools:** use HOOK_SCRIPT_RESOLVED for status display ([8b2383e](https://github.com/terrylica/cc-skills/commit/8b2383e52b2091519c9b03897b09fd5347973fd6))
* **statusline-tools:** use HOOK_SCRIPT_SETTINGS for consistent logging ([0058144](https://github.com/terrylica/cc-skills/commit/0058144f023c194934708aff7d0e33a9f199fda5))

## [5.5.4](https://github.com/terrylica/cc-skills/compare/v5.5.3...v5.5.4) (2025-12-20)


### Bug Fixes

* **statusline-tools:** use marketplace path for auto-updates ([0ae976d](https://github.com/terrylica/cc-skills/commit/0ae976d01536b0225541b5452fc7bcb5f16adb03))

## [5.5.3](https://github.com/terrylica/cc-skills/compare/v5.5.2...v5.5.3) (2025-12-20)


### Bug Fixes

* add lychee config to exclude test fixtures and generated dirs ([9a37752](https://github.com/terrylica/cc-skills/commit/9a377526ba6efa5aab684f87c456aa2ac19d4e89))

## [5.5.2](https://github.com/terrylica/cc-skills/compare/v5.5.1...v5.5.2) (2025-12-20)


### Bug Fixes

* **statusline-tools:** add separator between git status and link validation ([d9036aa](https://github.com/terrylica/cc-skills/commit/d9036aa853cb8775c865cf026c014e58f5647ef0))

## [5.5.1](https://github.com/terrylica/cc-skills/compare/v5.5.0...v5.5.1) (2025-12-20)


### Bug Fixes

* **statusline-tools:** resolve Stop hook failure from pipefail and file scanning ([e0913ef](https://github.com/terrylica/cc-skills/commit/e0913efa2ca14036a7539f44daf33e3bc9a792c2))

# [5.5.0](https://github.com/terrylica/cc-skills/compare/v5.4.0...v5.5.0) (2025-12-20)


### Features

* **statusline-tools:** add custom status line plugin with git status, link validation, and path linting ([6cbb11c](https://github.com/terrylica/cc-skills/commit/6cbb11c9edcbcf5968f2c29b0e54ff5a265177ab))

# [5.4.0](https://github.com/terrylica/cc-skills/compare/v5.3.0...v5.4.0) (2025-12-20)


### Features

* **ralph:** add multi-repository adapter architecture ([1ab4637](https://github.com/terrylica/cc-skills/commit/1ab46370872d3f440278915c427d98c7a4d7e27d))

# [5.3.0](https://github.com/terrylica/cc-skills/compare/v5.2.2...v5.3.0) (2025-12-20)


### Features

* **ralph:** modularize RSSI hooks into separation of concerns architecture ([bc4e050](https://github.com/terrylica/cc-skills/commit/bc4e050567a7de9db5e4a2823ef7d6e68b3cfe37))

## [5.2.2](https://github.com/terrylica/cc-skills/compare/v5.2.1...v5.2.2) (2025-12-20)

## [5.2.1](https://github.com/terrylica/cc-skills/compare/v5.2.0...v5.2.1) (2025-12-20)


### Bug Fixes

* **semantic-release:** simplify account verification to HTTPS-first workflow ([e0ae2a2](https://github.com/terrylica/cc-skills/commit/e0ae2a28e7cc3848f399b5632c47f2121b3b72ab))

# [5.2.0](https://github.com/terrylica/cc-skills/compare/v5.1.7...v5.2.0) (2025-12-20)


### Features

* **ralph:** add file discovery and argument parsing ([51c8dee](https://github.com/terrylica/cc-skills/commit/51c8dee9b88135cb9773ab8869b596ade9a35d1c))

## [5.1.7](https://github.com/terrylica/cc-skills/compare/v5.1.6...v5.1.7) (2025-12-19)


### Bug Fixes

* **ralph:** add shell compatibility for macOS zsh ([dbd1722](https://github.com/terrylica/cc-skills/commit/dbd1722cb8608b1a8c0d63faf6133e959526babb))

## [5.1.6](https://github.com/terrylica/cc-skills/compare/v5.1.5...v5.1.6) (2025-12-19)

## [5.1.5](https://github.com/terrylica/cc-skills/compare/v5.1.4...v5.1.5) (2025-12-19)


### Bug Fixes

* **ralph:** correct Stop hook for multi-iteration loops ([a9a0701](https://github.com/terrylica/cc-skills/commit/a9a0701bd9e3d45a51db6c5e7697b8cc2d802def))

## [5.1.4](https://github.com/terrylica/cc-skills/compare/v5.1.3...v5.1.4) (2025-12-19)


### Bug Fixes

* **ralph:** use correct Stop hook schema per Claude Code docs ([5a1e2db](https://github.com/terrylica/cc-skills/commit/5a1e2dbe095c9e7c6dcae463617a09da72c515ad))

## [5.1.3](https://github.com/terrylica/cc-skills/compare/v5.1.2...v5.1.3) (2025-12-19)


### Bug Fixes

* **git-account-validator:** change default to warn-only for network issues ([a139c06](https://github.com/terrylica/cc-skills/commit/a139c06689509588719d7222659ac601fa02da7c))

## [5.1.2](https://github.com/terrylica/cc-skills/compare/v5.1.1...v5.1.2) (2025-12-19)


### Bug Fixes

* **ralph:** use correct Stop hook JSON schema ([eb115d0](https://github.com/terrylica/cc-skills/commit/eb115d0fe925e713b5df3f345ea08a6a19035335))

## [5.1.1](https://github.com/terrylica/cc-skills/compare/v5.1.0...v5.1.1) (2025-12-19)


### Bug Fixes

* **ralph:** improve status accuracy and hook validation ([73d3acc](https://github.com/terrylica/cc-skills/commit/73d3accbb9ea09f5929f9c26dc81823a8b53d50b))

# [5.0.0](https://github.com/terrylica/cc-skills/compare/v4.8.4...v5.0.0) (2025-12-19)


### Features

* **ralph:** add autonomous loop hooks and slash commands ([a39ccc5](https://github.com/terrylica/cc-skills/commit/a39ccc57a3b9786b5fa6442306b627c1984b1c54))


### BREAKING CHANGES

* **ralph:** Plugin renamed from ralph-tools to ralph

## [4.8.4](https://github.com/terrylica/cc-skills/compare/v4.8.3...v4.8.4) (2025-12-19)


### Bug Fixes

* **docs:** add GitHub token reference docs for mise multi-account setup ([bf4eb93](https://github.com/terrylica/cc-skills/commit/bf4eb936e75cdbc9d2084b8c1f2d0b96bc9818a5))

## [4.8.3](https://github.com/terrylica/cc-skills/compare/v4.8.2...v4.8.3) (2025-12-18)


### Bug Fixes

* **docs:** add release notes visibility warning to semantic-release skill ([3a3b7fd](https://github.com/terrylica/cc-skills/commit/3a3b7fdcd82587811dac44ec376d78a8e9ff0c61))

## [4.8.2](https://github.com/terrylica/cc-skills/compare/v4.8.1...v4.8.2) (2025-12-18)

## [4.8.1](https://github.com/terrylica/cc-skills/compare/v4.8.0...v4.8.1) (2025-12-18)


### Bug Fixes

* **docs:** align documentation with actual plugin/skill counts and paths ([6a89dfc](https://github.com/terrylica/cc-skills/commit/6a89dfcf35169bf8167880b61a4ab443eb3dd168))

# [4.8.0](https://github.com/terrylica/cc-skills/compare/v4.7.2...v4.8.0) (2025-12-17)


### Features

* **itp-hooks:** add hooks-development skill for PostToolUse visibility patterns ([c1de3ac](https://github.com/terrylica/cc-skills/commit/c1de3acbd0fd2d96f22b4438d67108b8d8c2edda))

## [4.7.2](https://github.com/terrylica/cc-skills/compare/v4.7.1...v4.7.2) (2025-12-17)

## [4.7.1](https://github.com/terrylica/cc-skills/compare/v4.7.0...v4.7.1) (2025-12-17)


### Bug Fixes

* **dotfiles-tools:** use decision:block JSON for Claude visibility ([a8f20c3](https://github.com/terrylica/cc-skills/commit/a8f20c3b819a4b1f3dfbb1b0c25d1131cba29595))

# [4.7.0](https://github.com/terrylica/cc-skills/compare/v4.6.1...v4.7.0) (2025-12-17)


### Features

* **dotfiles-tools:** add /dotfiles:hooks installer command ([7e568e8](https://github.com/terrylica/cc-skills/commit/7e568e8d7318f3a032de6162cf430734cabe2295))

## [4.6.1](https://github.com/terrylica/cc-skills/compare/v4.6.0...v4.6.1) (2025-12-17)


### Bug Fixes

* **dotfiles-tools:** use INSTRUCTION prefix for deterministic skill invocation ([29de9e4](https://github.com/terrylica/cc-skills/commit/29de9e41272f243041e27bc9b6208df4f4a35528))

# [4.6.0](https://github.com/terrylica/cc-skills/compare/v4.5.0...v4.6.0) (2025-12-17)


### Features

* **dotfiles-tools:** add chezmoi sync reminder PostToolUse hook ([96f9fbd](https://github.com/terrylica/cc-skills/commit/96f9fbd70ecc8b82e22cc1b3063333992f6a45da))

# [4.5.0](https://github.com/terrylica/cc-skills/compare/v4.4.0...v4.5.0) (2025-12-16)


### Bug Fixes

* **dotfiles-tools:** improve skill description with specific triggers ([8ff7fe3](https://github.com/terrylica/cc-skills/commit/8ff7fe341591ca0bcd360332e5876ff313c141c2))
* **dotfiles-tools:** use portable chezmoi git commands ([8039eea](https://github.com/terrylica/cc-skills/commit/8039eea11df522f89e049a93931f7f5aba6b5c10))
* **dotfiles-tools:** validation fixes for universal applicability ([db192a2](https://github.com/terrylica/cc-skills/commit/db192a23ad732c6cd40efeb9272139cabc488d71))


### Features

* **dotfiles-tools:** add setup guide for universal chezmoi configuration ([9233cb9](https://github.com/terrylica/cc-skills/commit/9233cb9677424bf200e8d4214aed4c851ac8a0ab))
* **dotfiles-tools:** expand description with common tool triggers ([e815cf0](https://github.com/terrylica/cc-skills/commit/e815cf08ad7c905caf4480fd020e4acf69cda8a6))

# [4.4.0](https://github.com/terrylica/cc-skills/compare/v4.3.0...v4.4.0) (2025-12-16)


### Features

* **iterm2-layout-config:** add plugin for TOML-based configuration separation ([5aa88d0](https://github.com/terrylica/cc-skills/commit/5aa88d044a5dbf20a9048e99017ab494fee5112d))

# [4.3.0](https://github.com/terrylica/cc-skills/compare/v4.2.0...v4.3.0) (2025-12-16)


### Features

* **ralph-tools:** add 'ralph wiggum' as skill trigger ([cdd02dc](https://github.com/terrylica/cc-skills/commit/cdd02dcedc507b1405dee09c3c028135407170f2))

# [4.2.0](https://github.com/terrylica/cc-skills/compare/v4.1.1...v4.2.0) (2025-12-15)


### Features

* **alpha-forge-worktree:** add direnv integration for auto-loading secrets ([0e8214c](https://github.com/terrylica/cc-skills/commit/0e8214c0fe531a4587e1066f4f5c21156e6f751c))

## [4.1.1](https://github.com/terrylica/cc-skills/compare/v4.1.0...v4.1.1) (2025-12-15)

# [4.1.0](https://github.com/terrylica/cc-skills/compare/v4.0.0...v4.1.0) (2025-12-15)


### Bug Fixes

* add ralph-tools plugin with validation fixes ([952d1e3](https://github.com/terrylica/cc-skills/commit/952d1e345c003c0102b7c875db9c23a620369c80))


### Features

* **itp:** add ralph-orchestrator skill for autonomous AI development ([da1ba3b](https://github.com/terrylica/cc-skills/commit/da1ba3b63f1dee2190dfa5c240fbacbb334f7063))

# [4.0.0](https://github.com/terrylica/cc-skills/compare/v3.5.0...v4.0.0) (2025-12-15)


### Features

* **alpha-forge-worktree:** refactor to skills-only architecture with natural language triggers ([9d71107](https://github.com/terrylica/cc-skills/commit/9d71107a5550625c226c156c12b61d5bb9f25145))


### BREAKING CHANGES

* **alpha-forge-worktree:** The /af:wt slash command is removed. Use natural language
triggers like "create worktree for [description]" instead.

# [3.5.0](https://github.com/terrylica/cc-skills/compare/v3.4.1...v3.5.0) (2025-12-15)


### Features

* **marketplace:** register alpha-forge-worktree plugin ([ac70daf](https://github.com/terrylica/cc-skills/commit/ac70dafaf421bf147940bbee64ac2a8d71a150cb))
* **plugin:** add alpha-forge-worktree plugin for git worktree management ([16c40bd](https://github.com/terrylica/cc-skills/commit/16c40bda8d036eb4dea45db1e42e5655677b3c7b))
* **validation:** enhance plugin validation to prevent marketplace registration oversight ([0792242](https://github.com/terrylica/cc-skills/commit/0792242964ae7da80543d964b246c886bb7b7398))

## [3.4.1](https://github.com/terrylica/cc-skills/compare/v3.4.0...v3.4.1) (2025-12-15)

# [3.4.0](https://github.com/terrylica/cc-skills/compare/v3.3.0...v3.4.0) (2025-12-15)


### Features

* **pandoc-pdf-generation:** add --hide-details flag to strip <details> blocks from PDF ([be2012e](https://github.com/terrylica/cc-skills/commit/be2012e5154852884582adfc7f42605ef51a0190))

# [3.3.0](https://github.com/terrylica/cc-skills/compare/v3.2.0...v3.3.0) (2025-12-14)


### Bug Fixes

* **git-account-validator:** pre-flush SSH ControlMaster cache before validation ([5ef6820](https://github.com/terrylica/cc-skills/commit/5ef682055f55f799e565c9a79fad4166bcb1cb5b))


### Features

* **git-account-validator:** add pre-push validation plugin for multi-account GitHub ([73984f7](https://github.com/terrylica/cc-skills/commit/73984f7e889ad73b499477e305be23c2aa9bec38))

# [3.2.0](https://github.com/terrylica/cc-skills/compare/v3.1.2...v3.2.0) (2025-12-13)


### Features

* **pandoc-pdf-generation:** add orientation options and markdown authoring guide ([f4d2d61](https://github.com/terrylica/cc-skills/commit/f4d2d610263ceac4cb165fcede37eaaa1d6dd770))

## [3.1.2](https://github.com/terrylica/cc-skills/compare/v3.1.1...v3.1.2) (2025-12-13)


### Bug Fixes

* **itp-hooks:** detect file trees to avoid false positives in diagram blocking ([b71d7cb](https://github.com/terrylica/cc-skills/commit/b71d7cb4e70719e06e72dcb7d1a6f76c85596ea8))

## [3.1.1](https://github.com/terrylica/cc-skills/compare/v3.1.0...v3.1.1) (2025-12-13)


### Bug Fixes

* **itp-hooks:** broaden plan file exemption to any /plans/ directory ([e206d03](https://github.com/terrylica/cc-skills/commit/e206d03376721cd1656919b51e9c2f7e0a448d44))

# [3.1.0](https://github.com/terrylica/cc-skills/compare/v3.0.0...v3.1.0) (2025-12-13)


### Features

* **graph-easy:** add wrapper script for mise-installed binary ([ae4fcf9](https://github.com/terrylica/cc-skills/commit/ae4fcf948f0a00e99a76eb0b9f16e48b516c46e7))

# [3.0.0](https://github.com/terrylica/cc-skills/compare/v2.30.0...v3.0.0) (2025-12-13)


### Features

* **devops-tools:** add mlflow-python skill with QuantStats integration ([12a4ba7](https://github.com/terrylica/cc-skills/commit/12a4ba7355c01270d21aa5699590e4b7b94132de))


### BREAKING CHANGES

* **devops-tools:** mlflow-query skill deleted without deprecation period

# [2.30.0](https://github.com/terrylica/cc-skills/compare/v2.29.0...v2.30.0) (2025-12-12)


### Features

* **itp:** add plugin-add command for marketplace plugin creation ([6c30ea9](https://github.com/terrylica/cc-skills/commit/6c30ea9648726de4885e5aae852f5dec2732ed4b))

# [2.29.0](https://github.com/terrylica/cc-skills/compare/v2.28.0...v2.29.0) (2025-12-12)


### Features

* **marketplace:** register link-checker plugin and add auto-discovery ([0527f4a](https://github.com/terrylica/cc-skills/commit/0527f4a87760603f72b4a6059d32bb835d6aad4d))

# [2.28.0](https://github.com/terrylica/cc-skills/compare/v2.27.1...v2.28.0) (2025-12-11)


### Features

* **link-checker:** add universal link validation plugin ([#2](https://github.com/terrylica/cc-skills/issues/2)) ([56e9800](https://github.com/terrylica/cc-skills/commit/56e980025c380781698d4daa12cbb5a8bf634d7a))

## [2.27.1](https://github.com/terrylica/cc-skills/compare/v2.27.0...v2.27.1) (2025-12-11)

# [2.27.0](https://github.com/terrylica/cc-skills/compare/v2.26.1...v2.27.0) (2025-12-11)


### Bug Fixes

* **release:** update expected plugin count after skill audit ([0c7d1ed](https://github.com/terrylica/cc-skills/commit/0c7d1eda6d4a28b1f1d9600ccbba3eb7c6205fea))


### Features

* Ruff PostToolUse linting + skill audit cleanup ([#1](https://github.com/terrylica/cc-skills/issues/1)) ([2670f98](https://github.com/terrylica/cc-skills/commit/2670f9816abb8f4ca8d511d79bc3c7533878307b))

## [2.26.1](https://github.com/terrylica/cc-skills/compare/v2.26.0...v2.26.1) (2025-12-11)

# [2.26.0](https://github.com/terrylica/cc-skills/compare/v2.25.0...v2.26.0) (2025-12-10)


### Features

* **clickhouse:** add hub-based skill delegation to architect skill ([aa3a2fe](https://github.com/terrylica/cc-skills/commit/aa3a2feb107cc6d5f1141ca884a719344f704b4b))
* **clickhouse:** add Python driver policy to all ClickHouse skills ([38cee2c](https://github.com/terrylica/cc-skills/commit/38cee2cb9110263e37f36ff35c4796e3c225aae2))

# [2.25.0](https://github.com/terrylica/cc-skills/compare/v2.24.0...v2.25.0) (2025-12-10)


### Features

* **clickhouse:** close documentation gaps in skill ecosystem ([281f491](https://github.com/terrylica/cc-skills/commit/281f49108af2e625f8e25bf07a68cd7f24bb922d))

# [2.24.0](https://github.com/terrylica/cc-skills/compare/v2.23.0...v2.24.0) (2025-12-10)


### Features

* **clickhouse-architect:** add schema documentation guidance for AI understanding ([0653234](https://github.com/terrylica/cc-skills/commit/065323469b2a67ab8b6b0ccfef46a52864c63d41))

# [2.23.0](https://github.com/terrylica/cc-skills/compare/v2.22.1...v2.23.0) (2025-12-10)


### Features

* **itp-hooks:** add workflow-aware graph-easy detection ([c9775ae](https://github.com/terrylica/cc-skills/commit/c9775aec9141e0eeebf6c0089b55d15f0205a57b))

## [2.22.1](https://github.com/terrylica/cc-skills/compare/v2.22.0...v2.22.1) (2025-12-10)


### Bug Fixes

* **itp-hooks:** exempt plan files from ASCII diagram blocking ([6c5aa9b](https://github.com/terrylica/cc-skills/commit/6c5aa9b962aa4e977deb4921cb12675b9ff246bf))

# [2.22.0](https://github.com/terrylica/cc-skills/compare/v2.21.1...v2.22.0) (2025-12-09)


### Bug Fixes

* **quality-tools:** add ALP codec development status to clickhouse-architect ([8ff3525](https://github.com/terrylica/cc-skills/commit/8ff352526b15bdc3c2603aa0e383c6a81c0a74ad)), closes [#91362](https://github.com/terrylica/cc-skills/issues/91362) [#60533](https://github.com/terrylica/cc-skills/issues/60533) [#91362](https://github.com/terrylica/cc-skills/issues/91362)


### Features

* **devops-tools:** add clickhouse-pydantic-config skill ([e171d05](https://github.com/terrylica/cc-skills/commit/e171d05fa61386a363f73fbdf3ce137c603f6ee2))

## [2.21.1](https://github.com/terrylica/cc-skills/compare/v2.21.0...v2.21.1) (2025-12-09)


### Bug Fixes

* **quality-tools:** rectify clickhouse-architect skill based on empirical validation ([33fc270](https://github.com/terrylica/cc-skills/commit/33fc2702d06c97ca66a304d762e4626f0f9f4a14)), closes [#45615](https://github.com/terrylica/cc-skills/issues/45615)

# [2.21.0](https://github.com/terrylica/cc-skills/compare/v2.20.1...v2.21.0) (2025-12-09)


### Features

* **quality-tools:** add clickhouse-architect skill for schema design ([7926523](https://github.com/terrylica/cc-skills/commit/7926523d23948cd7280ca72d3acfe4bf576c836e))

## [2.20.1](https://github.com/terrylica/cc-skills/compare/v2.20.0...v2.20.1) (2025-12-09)

# [2.20.0](https://github.com/terrylica/cc-skills/compare/v2.19.0...v2.20.0) (2025-12-09)


### Bug Fixes

* align documentation with recent releases ([246c179](https://github.com/terrylica/cc-skills/commit/246c179a967bb01b9f8a234a0ac209824f542a31))
* **itp:** clarify Python baseline >=3.11 in mise-configuration ([364fa21](https://github.com/terrylica/cc-skills/commit/364fa21f0d0f300088416602ef537eca7c2e27de))


### Features

* **devops-tools:** add clickhouse-cloud-management skill ([ce1409b](https://github.com/terrylica/cc-skills/commit/ce1409bd67ae3b7e409b42fdc0605fd47789e45e))
* **itp:** add mise-tasks skill with bidirectional cross-references ([7827bde](https://github.com/terrylica/cc-skills/commit/7827bde8777d47bfcf60868896fb5504ae70ebb6))

# [2.19.0](https://github.com/terrylica/cc-skills/compare/v2.18.0...v2.19.0) (2025-12-08)


### Features

* **itp:** polish mise-configuration skill to SOTA best practices ([9113bfa](https://github.com/terrylica/cc-skills/commit/9113bfaa00a91ee935a7502a43e336f0097f3f55))
* **itp:** wire mise-configuration skill into /itp:go workflow ([550be35](https://github.com/terrylica/cc-skills/commit/550be35a3cdfbca1609708aee9db7b0d8d616509))

# [2.18.0](https://github.com/terrylica/cc-skills/compare/v2.17.0...v2.18.0) (2025-12-08)


### Features

* **itp:** add mise [env] as centralized configuration for ITP skills ([140ed67](https://github.com/terrylica/cc-skills/commit/140ed67db176b7f6f1d179d9f14e69901b0788ba))
* **itp:** add mise-configuration skill for env var SSoT pattern ([e202ebf](https://github.com/terrylica/cc-skills/commit/e202ebf507b1d3ca0c269aa40ba6a8b34cc781bc))

# [2.17.0](https://github.com/terrylica/cc-skills/compare/v2.16.2...v2.17.0) (2025-12-08)


### Features

* **itp:** integrate gitleaks into code-hardcode-audit skill ([24dedd4](https://github.com/terrylica/cc-skills/commit/24dedd411df452567bece1626726bd8add769f1b))

## [2.16.2](https://github.com/terrylica/cc-skills/compare/v2.16.1...v2.16.2) (2025-12-08)


### Bug Fixes

* **itp:** clarify version numbers are derived, not hardcoded ([dadb3c3](https://github.com/terrylica/cc-skills/commit/dadb3c36dc790477219039ddcc30d4fe969c014c))

## [2.16.1](https://github.com/terrylica/cc-skills/compare/v2.16.0...v2.16.1) (2025-12-08)

# [2.16.0](https://github.com/terrylica/cc-skills/compare/v2.15.0...v2.16.0) (2025-12-08)


### Features

* **itp:** rename /itp:itp command to /itp:go for shortcut support ([032c240](https://github.com/terrylica/cc-skills/commit/032c240f25ad77b0ae3ac7c335bdcbf879ab8d09))

# [2.15.0](https://github.com/terrylica/cc-skills/compare/v2.14.0...v2.15.0) (2025-12-08)


### Features

* **itp:** add gitleaks secret scanner to setup command ([920fa14](https://github.com/terrylica/cc-skills/commit/920fa14c88ecc39d6afd1aa4a2fec73f9b60cbf2))

# [2.14.0](https://github.com/terrylica/cc-skills/compare/v2.13.0...v2.14.0) (2025-12-07)


### Features

* **scripts:** add idempotency fixes across 8 shell scripts ([40bc880](https://github.com/terrylica/cc-skills/commit/40bc880b33360d6eb0a219606024de2aa1e3f9ec))

# [2.13.0](https://github.com/terrylica/cc-skills/compare/v2.12.1...v2.13.0) (2025-12-07)


### Features

* **itp:** add hooks reminder to setup command ([af34e6e](https://github.com/terrylica/cc-skills/commit/af34e6e42840e1f8db9b16d16ee4fd9b6dd41480))

## [2.12.1](https://github.com/terrylica/cc-skills/compare/v2.12.0...v2.12.1) (2025-12-07)


### Bug Fixes

* **adr:** regenerate diagrams with graph-easy boxart ([b2ee96f](https://github.com/terrylica/cc-skills/commit/b2ee96f762d21e785ec9dbc980cf96b5fd8b9422))

# [2.12.0](https://github.com/terrylica/cc-skills/compare/v2.11.4...v2.12.0) (2025-12-07)


### Features

* **itp:** add /itp hooks command for settings.json hook management ([cf2a675](https://github.com/terrylica/cc-skills/commit/cf2a67546c5a223597ffb70f35c8e286fa88b0e5))

## [2.11.4](https://github.com/terrylica/cc-skills/compare/v2.11.3...v2.11.4) (2025-12-07)


### Bug Fixes

* **itp-hooks:** remove dual hooks config, rely on standalone plugin.json ([fb0c3a4](https://github.com/terrylica/cc-skills/commit/fb0c3a483beed602927af9b8d22a4f3e109ae4d4))

## [2.11.3](https://github.com/terrylica/cc-skills/compare/v2.11.2...v2.11.3) (2025-12-07)


### Bug Fixes

* **itp-hooks:** add plugin.json for standalone hook loading ([dc723cb](https://github.com/terrylica/cc-skills/commit/dc723cbc5d8ae6efec2d1cd133170938a879bbeb))

## [2.11.2](https://github.com/terrylica/cc-skills/compare/v2.11.1...v2.11.2) (2025-12-07)


### Bug Fixes

* **itp-hooks:** add symlink for hooks path resolution ([26b7456](https://github.com/terrylica/cc-skills/commit/26b74560d0b004f97fc641ce9bac0fe6b409f845))

## [2.11.1](https://github.com/terrylica/cc-skills/compare/v2.11.0...v2.11.1) (2025-12-07)


### Bug Fixes

* **itp-hooks:** correct hooks path resolution in marketplace.json ([635f580](https://github.com/terrylica/cc-skills/commit/635f58018e18f3a36b62bdf59a31a9f91cb14311))

# [2.11.0](https://github.com/terrylica/cc-skills/compare/v2.10.2...v2.11.0) (2025-12-06)


### Features

* **itp-hooks:** add as opt-in marketplace plugin ([87202c6](https://github.com/terrylica/cc-skills/commit/87202c6fd5b385d5c1167d6edc7962e85674d17c))





---

## Architecture Decisions

### ADRs

- [ADR: PreToolUse and PostToolUse Hooks for Implementation Standards](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-06-pretooluse-posttooluse-hooks.md) (implemented)

### Design Specs

- [PreToolUse and PostToolUse Hooks](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-06-pretooluse-posttooluse-hooks/spec.md)

## [2.10.2](https://github.com/terrylica/cc-skills/compare/v2.10.1...v2.10.2) (2025-12-06)

## [2.10.1](https://github.com/terrylica/cc-skills/compare/v2.10.0...v2.10.1) (2025-12-06)


### Bug Fixes

* **hooks:** use exit code 2 for hard blocks, move graph-easy to PostToolUse ([18e1922](https://github.com/terrylica/cc-skills/commit/18e1922cbbcbbc8fd1b9774d91c9d642a05e9540))





---

## Architecture Decisions

### ADRs

- [ADR: PreToolUse and PostToolUse Hooks for Implementation Standards](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-06-pretooluse-posttooluse-hooks.md) (implemented)

### Design Specs

- [PreToolUse and PostToolUse Hooks](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-06-pretooluse-posttooluse-hooks/spec.md)

# [2.10.0](https://github.com/terrylica/cc-skills/compare/v2.9.2...v2.10.0) (2025-12-06)


### Features

* **hooks:** add PreToolUse/PostToolUse enforcement for implementation standards ([8fab271](https://github.com/terrylica/cc-skills/commit/8fab27106b51421e0afe11801a264405a6b05e78))





---

## Architecture Decisions

### ADRs

- [ADR: PreToolUse and PostToolUse Hooks for Implementation Standards](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-06-pretooluse-posttooluse-hooks.md) (implemented)
- [ADR: Shell Command Portability for Zsh Compatibility](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-06-shell-command-portability-zsh.md) (implemented)

### Design Specs

- [PreToolUse and PostToolUse Hooks](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-06-pretooluse-posttooluse-hooks/spec.md)
- [Shell Command Portability for Zsh Compatibility](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-06-shell-command-portability-zsh/spec.md)

## [2.9.2](https://github.com/terrylica/cc-skills/compare/v2.9.1...v2.9.2) (2025-12-06)





---

## Architecture Decisions

### ADRs

- [Centralized Version Management with @semantic-release/exec](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-05-centralized-version-management.md) (accepted)
- [ADR: Shell Command Portability for Zsh Compatibility](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-06-shell-command-portability-zsh.md) (accepted)

### Design Specs

- [Design Spec: Centralized Version Management](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-05-centralized-version-management/spec.md)
- [ADR/Design Spec Links in Release Notes](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-06-release-notes-adr-linking/spec.md)
- [Shell Command Portability for Zsh Compatibility](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-06-shell-command-portability-zsh/spec.md)

## [2.9.1](https://github.com/terrylica/cc-skills/compare/v2.9.0...v2.9.1) (2025-12-06)


### Bug Fixes

* **semantic-release:** use env var for generateNotesCmd to bypass lodash templates ([f0ea53d](https://github.com/terrylica/cc-skills/commit/f0ea53d782a407239446144f1c78a6dabd9162dc))





---

## Architecture Decisions

### ADRs

- [ADR: ADR/Design Spec Links in Release Notes](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-06-release-notes-adr-linking.md) (implemented)

### Design Specs

- [ADR/Design Spec Links in Release Notes](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-06-release-notes-adr-linking/spec.md)

# [2.9.0](https://github.com/terrylica/cc-skills/compare/v2.8.0...v2.9.0) (2025-12-06)


### Bug Fixes

* **semantic-release:** use relative path for generateNotesCmd ([909975e](https://github.com/terrylica/cc-skills/commit/909975e414700a582e3ee7e0334f6e4b8a06b06b))


### Features

* **semantic-release:** add ADR/Design Spec links in release notes ([dc5771b](https://github.com/terrylica/cc-skills/commit/dc5771bbb2a0cd235093d7a03a6b5c6dc8c9e48a))





---

## Architecture Decisions

### ADRs

- [ADR: ADR/Design Spec Links in Release Notes](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-06-release-notes-adr-linking.md) (accepted)

### Design Specs

- [ADR/Design Spec Links in Release Notes](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-06-release-notes-adr-linking/spec.md)

# [2.8.0](https://github.com/terrylica/cc-skills/compare/v2.7.0...v2.8.0) (2025-12-06)


### Features

* **itp:** add plan-aware todo integration (merge, not overwrite) ([c679d24](https://github.com/terrylica/cc-skills/commit/c679d24f0f4ae0c00adf6875baa95eb99d8548d2))

# [2.7.0](https://github.com/terrylica/cc-skills/compare/v2.6.2...v2.7.0) (2025-12-06)


### Bug Fixes

* **mql5com:** convert absolute paths to relative in references ([9576f0e](https://github.com/terrylica/cc-skills/commit/9576f0e860083a5b08788cdb1455f550ba8f1012))


### Code Refactoring

* adopt marketplace.json-only versioning (strict: false) ([9de694c](https://github.com/terrylica/cc-skills/commit/9de694c6988abcc84595deb8aa2b177e2b49088b))


### Features

* **mql5com:** add mql5.com operations plugin with 4 skills ([0e9c34d](https://github.com/terrylica/cc-skills/commit/0e9c34d34dd665fdec576c9fa64bc77e5e438618))
* **plugins:** migrate 12 personal skills to marketplace plugins ([76c9eda](https://github.com/terrylica/cc-skills/commit/76c9edae8736952444cb0980f7d8ada5a85a19cb))


### BREAKING CHANGES

* Individual plugin.json files no longer exist.
All plugin metadata now comes from marketplace.json only.

## [2.6.2](https://github.com/terrylica/cc-skills/compare/v2.6.1...v2.6.2) (2025-12-06)


### Bug Fixes

* **release:** add individual plugin files to git assets ([17240b9](https://github.com/terrylica/cc-skills/commit/17240b9bcec6e038746dcf1378edbe9b91778445))

## [2.6.1](https://github.com/terrylica/cc-skills/compare/v2.6.0...v2.6.1) (2025-12-06)


### Bug Fixes

* sync individual plugin versions with dynamic discovery ([13cc346](https://github.com/terrylica/cc-skills/commit/13cc346007843c572eba7ed7353a5dea02f434b4))

# [2.6.0](https://github.com/terrylica/cc-skills/compare/v2.5.2...v2.6.0) (2025-12-06)


### Features

* add 6 new plugins to marketplace ([78686fc](https://github.com/terrylica/cc-skills/commit/78686fcd297ce78b55c355facd899e93fba49218))

## [2.5.2](https://github.com/terrylica/cc-skills/compare/v2.5.1...v2.5.2) (2025-12-06)

## [2.5.1](https://github.com/terrylica/cc-skills/compare/v2.5.0...v2.5.1) (2025-12-06)


### Bug Fixes

* **release:** sync version files to 2.5.0 and simplify replace-plugin config ([cd33ae2](https://github.com/terrylica/cc-skills/commit/cd33ae2950abd732fa008a642f95640b9d3509eb))

# [2.5.0](https://github.com/terrylica/cc-skills/compare/v2.4.0...v2.5.0) (2025-12-06)


### Features

* **release:** migrate to semantic-release-replace-plugin for centralized versioning ([61547d5](https://github.com/terrylica/cc-skills/commit/61547d5b0c6ad09c58084d341e409dc14d095748))

# [2.5.0](https://github.com/terrylica/cc-skills/compare/v2.4.0...v2.5.0) (2025-12-06)


### Features

* **release:** migrate to semantic-release-replace-plugin for centralized versioning ([61547d5](https://github.com/terrylica/cc-skills/commit/61547d5b0c6ad09c58084d341e409dc14d095748))

# [2.4.0](https://github.com/terrylica/cc-skills/compare/v2.3.8...v2.4.0) (2025-12-05)


### Features

* **itp:** TodoWrite-driven interactive setup workflow ([92ffe29](https://github.com/terrylica/cc-skills/commit/92ffe29ad737686ecad9894b62c00a4e43cd1647))

## [2.3.8](https://github.com/terrylica/cc-skills/compare/v2.3.7...v2.3.8) (2025-12-05)

## [2.3.7](https://github.com/terrylica/cc-skills/compare/v2.3.6...v2.3.7) (2025-12-05)

### Bug Fixes

- terminology alignment across cc-skills repository ([4059431](https://github.com/terrylica/cc-skills/commit/40594310c3e9739cd97780a0c0db2b7c13bb1864))

## [2.3.6](https://github.com/terrylica/cc-skills/compare/v2.3.5...v2.3.6) (2025-12-05)

### Bug Fixes

- **graph-easy:** replace --version check with functional test ([924222c](https://github.com/terrylica/cc-skills/commit/924222c96584eff659bbc5623b6abeb854787427))

## [2.3.5](https://github.com/terrylica/cc-skills/compare/v2.3.4...v2.3.5) (2025-12-05)

## [2.3.4](https://github.com/terrylica/cc-skills/compare/v2.3.3...v2.3.4) (2025-12-05)

### Bug Fixes

- remove hardcoded paths for cross-user portability ([7a40912](https://github.com/terrylica/cc-skills/commit/7a409128a9adfdd2551aa39a3b452611ec7dd86d))

## [2.3.3](https://github.com/terrylica/cc-skills/compare/v2.3.2...v2.3.3) (2025-12-05)

### Bug Fixes

- **graph-easy:** use PATH-resolved graph-easy instead of hardcoded path ([595e67b](https://github.com/terrylica/cc-skills/commit/595e67b76f2a26ba0fa72889412d12f5f9e9a65a))

## [2.3.2](https://github.com/terrylica/cc-skills/compare/v2.3.1...v2.3.2) (2025-12-05)

## [2.3.1](https://github.com/terrylica/cc-skills/compare/v2.3.0...v2.3.1) (2025-12-05)

# [2.3.0](https://github.com/terrylica/cc-skills/compare/v2.2.2...v2.3.0) (2025-12-05)

### Features

- **release:** bump version on all commit types for marketplace compatibility ([4190837](https://github.com/terrylica/cc-skills/commit/4190837448554e03611d56e004b853ee1f0a6372))

## [2.2.2](https://github.com/terrylica/cc-skills/compare/v2.2.1...v2.2.2) (2025-12-05)

### Bug Fixes

- **docs:** include documentation updates in release ([7e20b09](https://github.com/terrylica/cc-skills/commit/7e20b0907bf8ac256ee2a663de94e0cc4d7b185d))

## [2.2.1](https://github.com/terrylica/cc-skills/compare/v2.2.0...v2.2.1) (2025-12-05)

### Bug Fixes

- **itp:** rename itp-setup to setup for better command ordering ([1a2f324](https://github.com/terrylica/cc-skills/commit/1a2f32445b7bd6ec6a3423306b3cffa2fef88c33))

# [2.2.0](https://github.com/terrylica/cc-skills/compare/v2.1.1...v2.2.0) (2025-12-05)

### Features

- **skill-architecture:** add path-patterns reference for safe/unsafe patterns ([4c6f192](https://github.com/terrylica/cc-skills/commit/4c6f1922538e483fd8dbe3dbc138618325798d3f))

## [2.1.1](https://github.com/terrylica/cc-skills/compare/v2.1.0...v2.1.1) (2025-12-05)

### Bug Fixes

- **itp:** use explicit marketplace path fallback in commands ([5d6ae9c](https://github.com/terrylica/cc-skills/commit/5d6ae9c6a9f3f9c07277c69a1aaf83f49ad176f8))

# [2.1.0](https://github.com/terrylica/cc-skills/compare/v2.0.1...v2.1.0) (2025-12-05)

### Features

- **link-validator:** add standalone plugin for markdown link portability validation ([d576718](https://github.com/terrylica/cc-skills/commit/d57671867681c6bc0259b40358e4fcfa608db629))

## [2.0.1](https://github.com/terrylica/cc-skills/compare/v2.0.0...v2.0.1) (2025-12-05)

### Bug Fixes

- **plugins:** use relative paths for marketplace skill links ([bc60957](https://github.com/terrylica/cc-skills/commit/bc6095793222663b29894874b8b695fd6e02a27b))

# [2.0.0](https://github.com/terrylica/cc-skills/compare/v1.0.0...v2.0.0) (2025-12-04)

- feat(itp)!: rename itp-workflow to itp for brevity ([8228250](https://github.com/terrylica/cc-skills/commit/822825051970209df3adc1f5e705c3083113ec5e)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools)

### BREAKING CHANGES

- Plugin renamed from itp-workflow to itp.
  Users must reinstall: `/plugin install cc-skills@itp`

Changes:

- Rename plugins/itp-workflow/ → plugins/itp/

# 1.0.0 (2025-12-04)

### Features

- add itp-workflow as second plugin in cc-skills marketplace ([c430526](https://github.com/terrylica/cc-skills/commit/c4305268b652eccc19f5de95d06965651ee4d698))
- **gh-tools:** add GitHub workflow automation plugin ([a5bd91f](https://github.com/terrylica/cc-skills/commit/a5bd91f2131095ab59759bef9a02cceea92f7472)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools) [#tools](https://github.com/terrylica/cc-skills/issues/tools)
- initial cc-skills marketplace with skill-architecture plugin ([638bb44](https://github.com/terrylica/cc-skills/commit/638bb440ae220cb8ea96788331ecdfb2a1e9dbd4))
- **skill-architecture:** add proactive Continuous Improvement section ([6458e27](https://github.com/terrylica/cc-skills/commit/6458e27d016eda2ffdd27bef1e0eb3abdda8fd16))
