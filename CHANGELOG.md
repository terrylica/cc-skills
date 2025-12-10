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
