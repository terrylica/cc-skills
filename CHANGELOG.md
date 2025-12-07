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
