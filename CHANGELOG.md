# [16.0.0](https://github.com/terrylica/cc-skills/compare/v15.0.0...v16.0.0) (2026-04-22)


* fix(autonomous-loop)!: waker-tier model — never use ScheduleWakeup as pacing ([1cf0915](https://github.com/terrylica/cc-skills/commit/1cf0915ffcb21420e89d346b836b9318d9dc7fa9))


### Features

* **macro-keyboard:** add plugin for 3-key USB-C/Bluetooth macro pad on macOS ([8ef6899](https://github.com/terrylica/cc-skills/commit/8ef6899e756ebc5ee80155b7809111e84433bb26))


### BREAKING CHANGES

* the `Nothing in flight, self-directed work continues`
row is removed from the pacing table. Contracts that interpreted this
row as "schedule 60s wake-up between iterations" will now correctly
chain in-turn. No action needed from users — the template is
idempotent on next firing.

Research basis: Anthropic's own `/loop` docs (self-paced interval is
for continuous work; ScheduleWakeup is for external blockers), plus
durable-execution patterns from Temporal / Restate / LangGraph
(event-driven primary, timer-only-as-safety-net).

# [15.0.0](https://github.com/terrylica/cc-skills/compare/v14.0.0...v15.0.0) (2026-04-22)


* feat(release)!: add Phase 1.5 pre-sync to release:full ([8d66160](https://github.com/terrylica/cc-skills/commit/8d66160b5e65202ad54ef060b2a905e4f405d3c5))


### Bug Fixes

* **autonomous-loop:** use CLAUDE_PLUGIN_ROOT + add parallel-secondary-work clause ([e034cf7](https://github.com/terrylica/cc-skills/commit/e034cf7e8a4eedef2562043e9ef8d1afaf06415a)), closes [#6](https://github.com/terrylica/cc-skills/issues/6) [#7](https://github.com/terrylica/cc-skills/issues/7)


### BREAKING CHANGES

* release:full now runs six phases instead of five.
Custom downstream invocations that replicate individual phases should
add release:presync between preflight and version, or continue to call
release:full as the single entry point.

# [14.0.0](https://github.com/terrylica/cc-skills/compare/v13.0.0...v14.0.0) (2026-04-21)


* feat(itp)!: remove release and semantic-release skills ([ccb91f5](https://github.com/terrylica/cc-skills/commit/ccb91f58d2a6b0dc219e16d181734d91811f04ec))


### Bug Fixes

* **release:** drop generateNotesCmd pointing at deleted script ([bac5421](https://github.com/terrylica/cc-skills/commit/bac54213f343b62e86e9a707437d1ce366d833be))


### Features

* **chronicle-share:** Phase 1 — bundle.sh + manifest v1 ([7ec85c0](https://github.com/terrylica/cc-skills/commit/7ec85c06db6d0859da759005996de35bc23092b5))
* **chronicle-share:** Phase 2 — sanitize.sh + manifest v2 additions ([f1171d7](https://github.com/terrylica/cc-skills/commit/f1171d74fa1e65907d815325f83167af0026ebef))
* **chronicle-share:** scaffold plugin for R2 producer pipeline ([6885ab7](https://github.com/terrylica/cc-skills/commit/6885ab797eadd8d90b7fce5c07a10fc48ab2a3bb))


### BREAKING CHANGES

* The `itp:release` and `itp:semantic-release` skills
have been removed. `/itp:release` no longer exists.

Migration: use `/mise:run-full-release` instead. Every repo owns its
release DAG in `.mise/tasks/release/`, which is where the logic
actually belongs — the two itp skills had drifted into either thin
delegators to mise or reference material duplicated across other
skills.

Purge includes:
- plugins/itp/skills/release/ (entire directory)
- plugins/itp/skills/semantic-release/ (entire directory, incl. templates,
  references, scripts, and historical audit report)

Cross-reference cleanup:
- plugins/itp/CLAUDE.md: drop Skills and Commands entries; update
  Phase 3 description to point at the mise release pipeline
- plugins/itp/skills/impl-standards/SKILL.md + references: drop
  semantic-release row from the Related Skills table; update
  constants-management to refer to mise release pipeline
- plugins/itp/skills/mise-configuration/references/github-tokens.md:
  drop semantic-release link
- plugins/itp/skills/mise-tasks/references/release-workflow-patterns.md:
  drop semantic-release from Related header
- plugins/itp/skills/pypi-doppler/SKILL.md: drop semantic-release
  bullet from the Related Skills list
- plugins/plugin-dev/skills/create/SKILL.md: replace two
  Skill(itp:semantic-release) references with Skill(mise:run-full-release)
- plugins/plugin-dev/skills/skill-architecture/references/scripts-reference.md:
  replace "Semantic Release" section with "Release Pipeline" pointing
  at the mise skill
- README.md: update docs examples, plugin-dev dependency row, and
  the itp plugin summary to drop the removed skills
- docs/discovery-architecture.md + docs/metadata-linking-framework.md:
  replace removed-skill examples (keywords, frontmatter samples,
  cross-reference tables) with still-existing skills

CHANGELOG.md historical entries referencing these skills are kept
intact — history is immutable.

SRED-Type: experimental-development

# [13.0.0](https://github.com/terrylica/cc-skills/compare/v12.52.0...v13.0.0) (2026-04-20)


* feat(autonomous-loop)!: remove ru plugin superseded by autonomous-loop ([f076802](https://github.com/terrylica/cc-skills/commit/f076802cd553c8ae7c92ee5b002480d76a970cdb))


### BREAKING CHANGES

* /ru:* commands removed. Migrate to /autonomous-loop:*
per docs/adr/2026-04-20-remove-ru-plugin.md migration table. Advanced
features (forbid/encourage/wizard) have no direct replacement and
require manual contract editing.





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| unknown | [Remove `ru` plugin — superseded by `autonomous-loop`](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-04-20-remove-ru-plugin.md) | new (+63) |

## Plugin Documentation

### Skills

<details>
<summary><strong>ru</strong> (9 changes)</summary>

- [audit now](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/skills/audit-now/SKILL.md) - deleted
- [encourage](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/skills/encourage/SKILL.md) - deleted
- [forbid](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/skills/forbid/SKILL.md) - deleted
- [hooks](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/skills/hooks/SKILL.md) - deleted
- [settings](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/skills/settings/SKILL.md) - deleted
- [start](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/skills/start/SKILL.md) - deleted
- [status](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/skills/status/SKILL.md) - deleted
- [stop](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/skills/stop/SKILL.md) - deleted
- [wizard](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/skills/wizard/SKILL.md) - deleted

</details>


### Plugin READMEs

- [ru](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/README.md) - deleted

### Skill References

<details>
<summary><strong>ru/audit-now</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/skills/audit-now/references/evolution-log.md) - deleted

</details>

<details>
<summary><strong>ru/encourage</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/skills/encourage/references/evolution-log.md) - deleted

</details>

<details>
<summary><strong>ru/forbid</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/skills/forbid/references/evolution-log.md) - deleted

</details>

<details>
<summary><strong>ru/hooks</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/skills/hooks/references/evolution-log.md) - deleted

</details>

<details>
<summary><strong>ru/settings</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/skills/settings/references/evolution-log.md) - deleted

</details>

<details>
<summary><strong>ru/start</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/skills/start/references/evolution-log.md) - deleted

</details>

<details>
<summary><strong>ru/status</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/skills/status/references/evolution-log.md) - deleted

</details>

<details>
<summary><strong>ru/stop</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/skills/stop/references/evolution-log.md) - deleted

</details>

<details>
<summary><strong>ru/wizard</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/skills/wizard/references/evolution-log.md) - deleted

</details>


## Other Documentation

### Other

- [CLAUDE](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/CLAUDE.md) - deleted
- [ralph-unified](https://github.com/terrylica/cc-skills/blob/v12.52.0/plugins/ru/hooks/templates/ralph-unified.md) - deleted

# [12.52.0](https://github.com/terrylica/cc-skills/compare/v12.51.0...v12.52.0) (2026-04-20)


### Features

* **autonomous-loop:** add plugin for self-revising LOOP_CONTRACT.md pattern ([7194e28](https://github.com/terrylica/cc-skills/commit/7194e2831c108252aa0c9829577afd6e718da01c))
* **plugins:** add crucible - self-evolving research methodology plugin ([deb9aab](https://github.com/terrylica/cc-skills/commit/deb9aab38df17ae091ee137a51bcfce821b9cc53))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| unknown | [autonomous-loop plugin — self-revising execution contract for long-horizon autonomous work](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-04-20-autonomous-loop.md) | new (+114) |

### Design Specs

- [Design Spec: autonomous-loop plugin](https://github.com/terrylica/cc-skills/blob/main/docs/design/2026-04-20-autonomous-loop/spec.md) - new (+105)

## Plugin Documentation

### Skills

<details>
<summary><strong>autonomous-loop</strong> (3 changes)</summary>

- [start](https://github.com/terrylica/cc-skills/blob/main/plugins/autonomous-loop/skills/start/SKILL.md) - new (+112)
- [status](https://github.com/terrylica/cc-skills/blob/main/plugins/autonomous-loop/skills/status/SKILL.md) - new (+112)
- [stop](https://github.com/terrylica/cc-skills/blob/main/plugins/autonomous-loop/skills/stop/SKILL.md) - new (+109)

</details>

<details>
<summary><strong>crucible</strong> (5 changes)</summary>

- [crucible-navigator](https://github.com/terrylica/cc-skills/blob/main/plugins/crucible/skills/00-navigator/SKILL.md) - new (+96)
- [crucible-research-foundations](https://github.com/terrylica/cc-skills/blob/main/plugins/crucible/skills/a-research-foundations/SKILL.md) - new (+189)
- [crucible-investigation-methodology](https://github.com/terrylica/cc-skills/blob/main/plugins/crucible/skills/b-investigation-methodology/SKILL.md) - new (+189)
- [crucible-meta-governance](https://github.com/terrylica/cc-skills/blob/main/plugins/crucible/skills/c-meta-governance/SKILL.md) - new (+168)
- [crucible-emergent-resurrection](https://github.com/terrylica/cc-skills/blob/main/plugins/crucible/skills/d-emergent-resurrection/SKILL.md) - new (+218)

</details>


### Plugin READMEs

- [autonomous-loop](https://github.com/terrylica/cc-skills/blob/main/plugins/autonomous-loop/README.md) - new (+79)
- [crucible](https://github.com/terrylica/cc-skills/blob/main/plugins/crucible/README.md) - new (+70)

### Skill References

<details>
<summary><strong>crucible/00-navigator</strong> (1 file)</summary>

- [evolution-log: 00-navigator](https://github.com/terrylica/cc-skills/blob/main/plugins/crucible/skills/00-navigator/references/evolution-log.md) - new (+29)

</details>

<details>
<summary><strong>crucible/a-research-foundations</strong> (1 file)</summary>

- [evolution-log: a-research-foundations](https://github.com/terrylica/cc-skills/blob/main/plugins/crucible/skills/a-research-foundations/references/evolution-log.md) - new (+22)

</details>

<details>
<summary><strong>crucible/b-investigation-methodology</strong> (1 file)</summary>

- [evolution-log: b-investigation-methodology](https://github.com/terrylica/cc-skills/blob/main/plugins/crucible/skills/b-investigation-methodology/references/evolution-log.md) - new (+22)

</details>

<details>
<summary><strong>crucible/c-meta-governance</strong> (1 file)</summary>

- [evolution-log: c-meta-governance](https://github.com/terrylica/cc-skills/blob/main/plugins/crucible/skills/c-meta-governance/references/evolution-log.md) - new (+22)

</details>

<details>
<summary><strong>crucible/d-emergent-resurrection</strong> (1 file)</summary>

- [evolution-log: d-emergent-resurrection](https://github.com/terrylica/cc-skills/blob/main/plugins/crucible/skills/d-emergent-resurrection/references/evolution-log.md) - new (+22)

</details>


## Other Documentation

### Other

- [autonomous-loop Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/autonomous-loop/CLAUDE.md) - new (+77)
- [<PROJECT OR CAMPAIGN TITLE>](https://github.com/terrylica/cc-skills/blob/main/plugins/autonomous-loop/templates/LOOP_CONTRACT.template.md) - new (+190)
- [crucible — Plugin Navigator](https://github.com/terrylica/cc-skills/blob/main/plugins/crucible/CLAUDE.md) - new (+104)

# [12.51.0](https://github.com/terrylica/cc-skills/compare/v12.50.1...v12.51.0) (2026-04-17)


### Features

* **tlg:** auto-split long messages + --reply-to flag ([fe63231](https://github.com/terrylica/cc-skills/commit/fe6323161f5b67b5869fdd52452ebd88fb8ddb3e))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>tlg</strong> (2 changes)</summary>

- [draft-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/draft-message/SKILL.md) - updated (+1)
- [send-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/send-message/SKILL.md) - updated (+26/-4)

</details>

## [12.50.1](https://github.com/terrylica/cc-skills/compare/v12.50.0...v12.50.1) (2026-04-17)





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [quant-research](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/README.md) - updated (+14/-10)

## Other Documentation

### Other

- [agent-reach Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/agent-reach/CLAUDE.md) - new (+24)
- [asciinema-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/CLAUDE.md) - updated (+24/-8)
- [Cal.com Commander Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/CLAUDE.md) - updated (+9)
- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (+34/-29)
- [cli-anything Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/cli-anything/CLAUDE.md) - updated (+4)
- [devops-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/CLAUDE.md) - updated (+29/-19)
- [doc-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/CLAUDE.md) - updated (+10/-12)
- [dotfiles-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/CLAUDE.md) - updated (+3/-4)
- [gemini-deep-research Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gemini-deep-research/CLAUDE.md) - updated (+4)
- [gh-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/CLAUDE.md) - updated (+14/-9)
- [git-town-workflow Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/CLAUDE.md) - updated (+7)
- [gitnexus-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/CLAUDE.md) - updated (+4/-6)
- [Gmail Commander Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/CLAUDE.md) - updated (+22/-10)
- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+13/-4)
- [itp Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/CLAUDE.md) - updated (+15/-17)
- [kokoro-tts Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/CLAUDE.md) - updated (+11)
- [link-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/CLAUDE.md) - updated (+2/-4)
- [media-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/media-tools/CLAUDE.md) - updated (+1/-3)
- [mise Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/CLAUDE.md) - updated (+7)
- [mql5 Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/CLAUDE.md) - updated (+6/-6)
- [plugin-dev Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/CLAUDE.md) - updated (+3/-4)
- [productivity-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/CLAUDE.md) - updated (+8/-9)
- [quality-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/CLAUDE.md) - updated (+11/-12)
- [quant-research Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/CLAUDE.md) - updated (+8/-9)
- [ru Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/CLAUDE.md) - updated (+12)
- [rust-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/CLAUDE.md) - updated (+2/-4)
- [statusline-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/CLAUDE.md) - updated (+4/-6)
- [Telegram CLI Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/CLAUDE.md) - updated (+19)
- [tts-tg-sync Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/CLAUDE.md) - updated (+13)

# [12.50.0](https://github.com/terrylica/cc-skills/compare/v12.49.1...v12.50.0) (2026-04-17)


### Features

* **itp-hooks:** allow maturin pyproject.toml co-located with Cargo.toml ([a052b6c](https://github.com/terrylica/cc-skills/commit/a052b6c57ab3082181f131efa5d59b80e39356fb))
* **tlg:** migrate Bruntwork to supergroup with topics ([945c009](https://github.com/terrylica/cc-skills/commit/945c009bdb63bb586d20b0e5acd1f01a62a3f8c1))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (2 changes)</summary>

- [firecrawl-research-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/SKILL.md) - updated (+15/-15)
- [pueue-job-orchestration](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/SKILL.md) - updated (+5/-4)

</details>

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [research-archival](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/research-archival/SKILL.md) - updated (+9/-9)

</details>

<details>
<summary><strong>rust-tools</strong> (2 changes)</summary>

- [rust-dependency-audit](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-dependency-audit/SKILL.md) - updated (+1/-1)
- [rust-sota-arsenal](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>tlg</strong> (3 changes)</summary>

- [draft-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/draft-message/SKILL.md) - updated (+2/-2)
- [send-media](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/send-media/SKILL.md) - updated (+2/-2)
- [send-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/send-message/SKILL.md) - updated (+49/-8)

</details>


### Skill References

<details>
<summary><strong>devops-tools/firecrawl-research-patterns</strong> (6 files)</summary>

- [Academic Paper Routing](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/academic-paper-routing.md) - updated (+18/-18)
- [API Endpoint Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/api-endpoint-reference.md) - updated (+15/-15)
- [Recursive Research Protocol](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/recursive-research-protocol.md) - updated (+2/-2)
- [Firecrawl Bootstrap: Fresh Installation](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/self-hosted-bootstrap-guide.md) - updated (+1/-1)
- [Firecrawl Self-Hosted Operations](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/self-hosted-operations.md) - updated (+21/-21)
- [Firecrawl Troubleshooting](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/self-hosted-troubleshooting.md) - updated (+10/-10)

</details>

<details>
<summary><strong>gh-tools/research-archival</strong> (1 file)</summary>

- [URL Routing](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/research-archival/references/url-routing.md) - updated (+14/-14)

</details>


## Repository Documentation

### General Documentation

- [1Password Credential Registry](https://github.com/terrylica/cc-skills/blob/main/docs/1password-credential-registry.md) - new (+37)

## Other Documentation

### Other

- [devops-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/CLAUDE.md) - updated (+6/-6)
- [ralph-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/hooks/templates/ralph-unified.md) - updated (+4/-3)

## [12.49.1](https://github.com/terrylica/cc-skills/compare/v12.49.0...v12.49.1) (2026-04-16)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>tlg</strong> (1 change)</summary>

- [send-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/send-message/SKILL.md) - updated (+12/-4)

</details>

# [12.49.0](https://github.com/terrylica/cc-skills/compare/v12.48.0...v12.49.0) (2026-04-15)


### Features

* **tlg:** add draft command + draft-message skill (Saved Messages pattern) ([77a10a4](https://github.com/terrylica/cc-skills/commit/77a10a47a08cf786aec91f4bea778d2b0c057246)), closes [tdesktop#29111](https://github.com/tdesktop/issues/29111)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>tlg</strong> (2 changes)</summary>

- [draft-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/draft-message/SKILL.md) - new (+163)
- [send-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/send-message/SKILL.md) - updated (+31)

</details>

# [12.48.0](https://github.com/terrylica/cc-skills/compare/v12.47.1...v12.48.0) (2026-04-15)


### Features

* **session-chronicle:** add field-aware sanitizer + mandatory pre-S3 step ([d5c3d4d](https://github.com/terrylica/cc-skills/commit/d5c3d4d15c6e13751f8a0eb8233d99f0dd35dd61))
* **tlg:** add --html flag to edit command + document separator length rules ([04d174e](https://github.com/terrylica/cc-skills/commit/04d174ef18be70abcc14a574453222edbb01d232))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [session-chronicle](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/SKILL.md) - updated (+41/-3)

</details>

<details>
<summary><strong>tlg</strong> (1 change)</summary>

- [send-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/send-message/SKILL.md) - updated (+13/-1)

</details>

## [12.47.1](https://github.com/terrylica/cc-skills/compare/v12.47.0...v12.47.1) (2026-04-15)





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| partially | [PreToolUse and PostToolUse Hooks for Implementation Standards](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-06-pretooluse-posttooluse-hooks.md) | updated (+3/-1) |

### Design Specs

- [PreToolUse and PostToolUse Hooks](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-06-pretooluse-posttooluse-hooks/spec.md) - coupled

## Plugin Documentation

### Plugin READMEs

- [ITP Hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/README.md) - updated (-1)

### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+14/-14)

</details>


## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (-1)

# [12.47.0](https://github.com/terrylica/cc-skills/compare/v12.46.0...v12.47.0) (2026-04-14)


### Features

* **infra:** migrate to Tailscale-only, add VNC tunnel forward ([7689d53](https://github.com/terrylica/cc-skills/commit/7689d5387d05464b9427cce0e930da90d94bb43f)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools)
* **tlg:** add --html flag to tg-cli send command ([6b5eff8](https://github.com/terrylica/cc-skills/commit/6b5eff8da438969e9e81578827e1c28bf6299175))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (2 changes)</summary>

- [firecrawl-research-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/SKILL.md) - updated (+15/-16)
- [pueue-job-orchestration](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/SKILL.md) - updated (+9/-11)

</details>

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [research-archival](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/research-archival/SKILL.md) - updated (+14/-15)

</details>

<details>
<summary><strong>rust-tools</strong> (2 changes)</summary>

- [rust-dependency-audit](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-dependency-audit/SKILL.md) - updated (+2/-3)
- [rust-sota-arsenal](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/SKILL.md) - updated (+2/-3)

</details>

<details>
<summary><strong>tlg</strong> (1 change)</summary>

- [send-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/send-message/SKILL.md) - updated (+11/-8)

</details>


### Plugin READMEs

- [devops-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/README.md) - updated (+2/-2)

### Skill References

<details>
<summary><strong>devops-tools/firecrawl-research-patterns</strong> (6 files)</summary>

- [Academic Paper Routing](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/academic-paper-routing.md) - updated (+18/-18)
- [API Endpoint Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/api-endpoint-reference.md) - updated (+15/-15)
- [Recursive Research Protocol](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/recursive-research-protocol.md) - updated (+2/-2)
- [Firecrawl Bootstrap: Fresh Installation](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/self-hosted-bootstrap-guide.md) - updated (+2/-2)
- [Firecrawl Self-Hosted Operations](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/self-hosted-operations.md) - updated (+22/-22)
- [Firecrawl Troubleshooting](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/self-hosted-troubleshooting.md) - updated (+14/-14)

</details>

<details>
<summary><strong>devops-tools/pueue-job-orchestration</strong> (1 file)</summary>

- [Installation Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/references/installation-guide.md) - updated (+1/-1)

</details>

<details>
<summary><strong>gh-tools/research-archival</strong> (2 files)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/research-archival/references/evolution-log.md) - updated (+1/-1)
- [URL Routing](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/research-archival/references/url-routing.md) - updated (+16/-16)

</details>


## Other Documentation

### Other

- [devops-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/CLAUDE.md) - updated (+7/-10)
- [ralph-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/hooks/templates/ralph-unified.md) - updated (+13/-10)
- [ssh-tunnel-companion](https://github.com/terrylica/cc-skills/blob/main/plugins/ssh-tunnel-companion/CLAUDE.md) - updated (+11/-9)

# [12.46.0](https://github.com/terrylica/cc-skills/compare/v12.45.1...v12.46.0) (2026-04-13)


### Features

* **statusline-tools:** show both 7d and 5h quota windows with color demarcation ([8fee458](https://github.com/terrylica/cc-skills/commit/8fee45833cdcea175f96d4f0e42c7a5086606e36))
* **tlg:** add session preflight + check-auth and auth subcommands ([cb80661](https://github.com/terrylica/cc-skills/commit/cb80661ba0238fc82614e067d5856832eccd3c80))





---

## Documentation Changes

## Other Documentation

### Other

- [ssh-tunnel-companion](https://github.com/terrylica/cc-skills/blob/main/plugins/ssh-tunnel-companion/CLAUDE.md) - updated (+10)

## [12.45.1](https://github.com/terrylica/cc-skills/compare/v12.45.0...v12.45.1) (2026-04-11)


### Bug Fixes

* **itp-hooks:** exclude flag arguments from pth contamination guard regex ([46144fe](https://github.com/terrylica/cc-skills/commit/46144fed2f24ad104b32d7357c7ea909859df57a))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>tlg</strong> (3 changes)</summary>

- [send-media](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/send-media/SKILL.md) - updated (+85/-29)
- [send-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/send-message/SKILL.md) - updated (+151/-18)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/setup/SKILL.md) - updated (+105/-47)

</details>

# [12.45.0](https://github.com/terrylica/cc-skills/compare/v12.44.0...v12.45.0) (2026-04-11)


### Bug Fixes

* **claude-tts-companion:** multi-monitor subtitle positioning ([2660d18](https://github.com/terrylica/cc-skills/commit/2660d180a08a32d6432ad69d44b2e655e7c9a123)), closes [terrylica/claude-config#76](https://github.com/terrylica/claude-config/issues/76)


### Features

* **statusline-tools:** append raw statusline data to JSONL for analytics ([19dd068](https://github.com/terrylica/cc-skills/commit/19dd068d313ac1f78f999868b36f03ef34f8777b))

# [12.44.0](https://github.com/terrylica/cc-skills/compare/v12.43.3...v12.44.0) (2026-04-09)


### Features

* **itp-hooks:** register .pth contamination guard + remove memory reference ([01fc6d8](https://github.com/terrylica/cc-skills/commit/01fc6d88f9d4dd1f9d9efee297ad2f4f281f14c8))

## [12.43.3](https://github.com/terrylica/cc-skills/compare/v12.43.2...v12.43.3) (2026-04-09)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>statusline-tools</strong> (4 changes)</summary>

- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/hooks/SKILL.md) - updated (+12/-7)
- [ignore](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/ignore/SKILL.md) - updated (+2/-1)
- [session-info](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/session-info/SKILL.md) - updated (+4/-15)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/setup/SKILL.md) - updated (+3/-1)

</details>


### Plugin READMEs

- [statusline-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/README.md) - updated (+85/-26)

### Skill References

<details>
<summary><strong>statusline-tools/hooks</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/hooks/references/evolution-log.md) - updated (+1/-24)

</details>

<details>
<summary><strong>statusline-tools/ignore</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/ignore/references/evolution-log.md) - updated (+1/-24)

</details>

<details>
<summary><strong>statusline-tools/session-info</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/session-info/references/evolution-log.md) - updated (+1/-24)

</details>

<details>
<summary><strong>statusline-tools/setup</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/setup/references/evolution-log.md) - updated (+1/-24)

</details>


## Other Documentation

### Other

- [statusline-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/CLAUDE.md) - updated (+20/-7)

## [12.43.2](https://github.com/terrylica/cc-skills/compare/v12.43.1...v12.43.2) (2026-04-09)


### Bug Fixes

* **itp-hooks:** UV enforcement guard false positive on chained git commit ([138aeda](https://github.com/terrylica/cc-skills/commit/138aedaad5f68fbcdbde09335c256913d11c090b))

## [12.43.1](https://github.com/terrylica/cc-skills/compare/v12.43.0...v12.43.1) (2026-04-08)


### Bug Fixes

* **itp-hooks:** use plain stdout for PostToolUse memory efficiency hook ([4542a2a](https://github.com/terrylica/cc-skills/commit/4542a2a245725df1dd9f0999771d33028cb8c9a4))

# [12.43.0](https://github.com/terrylica/cc-skills/compare/v12.42.4...v12.43.0) (2026-04-08)


### Features

* **itp-hooks:** memory efficiency reminder hook (once per session) ([139b413](https://github.com/terrylica/cc-skills/commit/139b4138948138b78de193d83bd9a1744cf033d5))

## [12.42.4](https://github.com/terrylica/cc-skills/compare/v12.42.3...v12.42.4) (2026-04-08)


### Bug Fixes

* **itp-hooks:** skip stdin-inlet guard for SSH remote commands ([cf67586](https://github.com/terrylica/cc-skills/commit/cf6758625bdb59633943bf46bb868dcbd14e800f))

## [12.42.3](https://github.com/terrylica/cc-skills/compare/v12.42.2...v12.42.3) (2026-04-08)


### Bug Fixes

* **itp-hooks:** skip local guards for SSH remote commands ([66c6356](https://github.com/terrylica/cc-skills/commit/66c6356bd3d77c843eb91b16f54d842e6988ec66))
* **quick-260407-odg:** make fallback hide() calls cancellable via pendingLingerHide ([994ed8a](https://github.com/terrylica/cc-skills/commit/994ed8adfedea38c5c66c5d3b1231c80ab00ff6f))
* **quick-260407-odg:** re-assert panel front ordering every 0.5s in tickStreaming ([211e308](https://github.com/terrylica/cc-skills/commit/211e308ebdd4ad3c78af3b3be733a8ac6071cb10))





---

## Documentation Changes

## Other Documentation

### Other

- [subtitle-panel-intermittent-disappear](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/subtitle-panel-intermittent-disappear.md) - new (+74)
- [260407-odg-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/quick/260407-odg-fix-subtitle-panel-intermittent-disappea/260407-odg-PLAN.md) - new (+307)
- [Project State](https://github.com/terrylica/cc-skills/blob/main/.planning/STATE.md) - updated (+7/-6)

## [12.42.2](https://github.com/terrylica/cc-skills/compare/v12.42.1...v12.42.2) (2026-04-07)


### Bug Fixes

* **release:** preserve old plugin cache versions during sync ([e510889](https://github.com/terrylica/cc-skills/commit/e510889ce3fa25069c30bfef9adcc54879b4c682))

## [12.42.1](https://github.com/terrylica/cc-skills/compare/v12.42.0...v12.42.1) (2026-04-07)





---

## Documentation Changes

## Other Documentation

### Other

- [Debug Session: iterm2-stop-notification](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/iterm2-stop-notification.md) - new (+80)

# [12.42.0](https://github.com/terrylica/cc-skills/compare/v12.41.0...v12.42.0) (2026-04-07)


### Bug Fixes

* **claude-tts-companion:** self-healing WAV path fallback + collapsed telemetry ([285416a](https://github.com/terrylica/cc-skills/commit/285416ab96513dd9e4783f204d0f63597ed206ae)), closes [#if](https://github.com/terrylica/cc-skills/issues/if)


### Features

* **claude-tts-companion:** expose afplay WAV telemetry on /health + log SettingsStore dir failures ([0489c04](https://github.com/terrylica/cc-skills/commit/0489c04a351abbddd8574b89f28aa507d76690a4))





---

## Documentation Changes

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+23/-122)

### General Documentation

- [Lessons Learned](https://github.com/terrylica/cc-skills/blob/main/docs/LESSONS.md) - updated (+6)

## Other Documentation

### Other

- [tts-no-audio-260406](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/tts-no-audio-260406.md) - new (+94)
- [260406-nts-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/quick/260406-nts-fix-pythontimestampresponse-snake-case-c/260406-nts-PLAN.md) - new (+146)
- [Quick Task 260406-nts: Fix PythonTimestampResponse snake_case Swift Property Names](https://github.com/terrylica/cc-skills/blob/main/.planning/quick/260406-nts-fix-pythontimestampresponse-snake-case-c/260406-nts-SUMMARY.md) - new (+95)
- [260407-h07-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/quick/260407-h07-antifragile-fix-for-afplayplayer-wav-wri/260407-h07-PLAN.md) - new (+830)
- [Research: Antifragile AfplayPlayer fix](https://github.com/terrylica/cc-skills/blob/main/.planning/quick/260407-h07-antifragile-fix-for-afplayplayer-wav-wri/260407-h07-RESEARCH.md) - new (+477)
- [Quick 260407-h07: Antifragile fix for AfplayPlayer WAV write Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/quick/260407-h07-antifragile-fix-for-afplayplayer-wav-wri/260407-h07-SUMMARY.md) - new (+153)
- [Quick 260407-h07: Antifragile AfplayPlayer WAV-Write Fix — Verification Report](https://github.com/terrylica/cc-skills/blob/main/.planning/quick/260407-h07-antifragile-fix-for-afplayplayer-wav-wri/260407-h07-VERIFICATION.md) - new (+86)
- [Roadmap: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/ROADMAP.md) - updated (+38/-38)
- [Project State](https://github.com/terrylica/cc-skills/blob/main/.planning/STATE.md) - updated (+6/-4)
- [claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/CLAUDE.md) - updated (+84/-1)

# [12.41.0](https://github.com/terrylica/cc-skills/compare/v12.40.0...v12.41.0) (2026-04-06)


### Bug Fixes

* **statusline,ssh-tunnel:** restore ccmax-monitor account display ([6afbedc](https://github.com/terrylica/cc-skills/commit/6afbedccc912e7d099dd8341948b5c7c123be4fa))


### Features

* **quality-tools:** canonical anchoring + proposer prompt for term_similarity ([3ca953b](https://github.com/terrylica/cc-skills/commit/3ca953b8667b5aa553e40d3977fddde284f675bf))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>quality-tools</strong> (1 change)</summary>

- [telemetry-terminology-similarity](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/telemetry-terminology-similarity/SKILL.md) - updated (+45/-10)

</details>


### Skill References

<details>
<summary><strong>quality-tools/telemetry-terminology-similarity</strong> (1 file)</summary>

- [Proposer Prompt Template](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/telemetry-terminology-similarity/references/proposer-prompt.md) - new (+202)

</details>


## Other Documentation

### Other

- [Canonical Telemetry Names Dictionary](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/telemetry-terminology-similarity/references/canonical-dictionary/README.md) - new (+52)
- [ssh-tunnel-companion](https://github.com/terrylica/cc-skills/blob/main/plugins/ssh-tunnel-companion/CLAUDE.md) - updated (+6/-4)

# [12.40.0](https://github.com/terrylica/cc-skills/compare/v12.39.1...v12.40.0) (2026-04-06)


### Bug Fixes

* **quality-tools:** eliminate mega-clusters in term_similarity ([c0c686f](https://github.com/terrylica/cc-skills/commit/c0c686fb64ba5383e82d219dc0f74559e92a3a5b))


### Features

* **quality-tools:** v2 term_similarity — raw scores, WordNet, no thresholds ([a67cb28](https://github.com/terrylica/cc-skills/commit/a67cb2817a5619d928e5afe3cc8be78f145b97b5))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>quality-tools</strong> (1 change)</summary>

- [telemetry-terminology-similarity](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/telemetry-terminology-similarity/SKILL.md) - updated (+82/-116)

</details>

## [12.39.1](https://github.com/terrylica/cc-skills/compare/v12.39.0...v12.39.1) (2026-04-06)


### Bug Fixes

* **quality-tools:** fix cross-repo invocation of term_similarity skill ([883e316](https://github.com/terrylica/cc-skills/commit/883e316090f0eefce7ed3ceeffbfaaa4a1392a8e))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>quality-tools</strong> (1 change)</summary>

- [telemetry-terminology-similarity](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/telemetry-terminology-similarity/SKILL.md) - updated (+46/-15)

</details>

# [12.39.0](https://github.com/terrylica/cc-skills/compare/v12.38.2...v12.39.0) (2026-04-06)


### Features

* **devops-tools:** add lightweight logging pattern as preferred default ([a3d53f8](https://github.com/terrylica/cc-skills/commit/a3d53f8e0eb21f48f2ea98aeac0f2bbfaf8aee64))
* **quality-tools:** add telemetry-terminology-similarity skill ([1d05ecb](https://github.com/terrylica/cc-skills/commit/1d05ecb03ffe1879a5134d81cc6bf37cb330d251))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [python-logging-best-practices](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/python-logging-best-practices/SKILL.md) - updated (+268/-131)

</details>

<details>
<summary><strong>quality-tools</strong> (1 change)</summary>

- [telemetry-terminology-similarity](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/telemetry-terminology-similarity/SKILL.md) - new (+221)

</details>


## Other Documentation

### Other

- [quality-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/CLAUDE.md) - updated (+1)

## [12.38.2](https://github.com/terrylica/cc-skills/compare/v12.38.1...v12.38.2) (2026-04-05)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [python-logging-best-practices](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/python-logging-best-practices/SKILL.md) - updated (+155/-65)

</details>


### Skill References

<details>
<summary><strong>devops-tools/python-logging-best-practices</strong> (5 files)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/python-logging-best-practices/references/evolution-log.md) - updated (+57)
- [Python Logging Architecture Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/python-logging-best-practices/references/logging-architecture.md) - updated (+104/-30)
- [Loguru Configuration Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/python-logging-best-practices/references/loguru-patterns.md) - updated (+78/-8)
- [Migration Guide: print() to Structured Logging](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/python-logging-best-practices/references/migration-guide.md) - updated (+20/-18)
- [Platformdirs Xdg](https://github.com/terrylica/cc-skills/blob/v12.38.1/plugins/devops-tools/skills/python-logging-best-practices/references/platformdirs-xdg.md) - deleted

</details>

## [12.38.1](https://github.com/terrylica/cc-skills/compare/v12.38.0...v12.38.1) (2026-04-04)

# [12.38.0](https://github.com/terrylica/cc-skills/compare/v12.37.0...v12.38.0) (2026-04-04)


### Bug Fixes

* **claude-tts-companion:** audit fixes for pipelined playback state machine ([72884aa](https://github.com/terrylica/cc-skills/commit/72884aa33bf675b5923ce117eace72c2e9ca3257))


### Features

* **claude-tts-companion,statusline:** Telegram Q&A handler + ccmax monitor ([497d87a](https://github.com/terrylica/cc-skills/commit/497d87a2918a71f09a6e6e848887c25ffa5d955f))

# [12.37.0](https://github.com/terrylica/cc-skills/compare/v12.36.1...v12.37.0) (2026-04-03)


### Features

* **claude-tts-companion:** pipelined paragraph playback with RTF-driven prefetch ([7d0964b](https://github.com/terrylica/cc-skills/commit/7d0964b2999c67aeeb547500c69d9833f91d7669))





---

## Documentation Changes

## Other Documentation

### Other

- [Phase 1: Single-Consumer Consolidation Verification Report](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/phases/01-single-consumer-consolidation/01-VERIFICATION.md) - new (+99)

## [12.36.1](https://github.com/terrylica/cc-skills/compare/v12.36.0...v12.36.1) (2026-04-03)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [issue-create](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issue-create/SKILL.md) - updated (+31/-2)

</details>


## Other Documentation

### Other

- [gh-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/CLAUDE.md) - updated (+2)

# [12.36.0](https://github.com/terrylica/cc-skills/compare/v12.35.1...v12.36.0) (2026-04-03)


### Features

* add ssh-tunnel-companion plugin scaffold ([9946279](https://github.com/terrylica/cc-skills/commit/9946279e15c155b01c697bb65e43a740f880897f))
* **statusline,gh-tools:** wiki URL detection + org fast-path in identity guard ([17caf23](https://github.com/terrylica/cc-skills/commit/17caf23a20fb9dc12ec6a6d319df0ba4affb28ad)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools)





---

## Documentation Changes

## Other Documentation

### Other

- [Architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/codebase/ARCHITECTURE.md) - new (+285)
- [Codebase Concerns](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/codebase/CONCERNS.md) - new (+323)
- [Coding Conventions](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/codebase/CONVENTIONS.md) - new (+216)
- [External Integrations](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/codebase/INTEGRATIONS.md) - new (+178)
- [Technology Stack](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/codebase/STACK.md) - new (+137)
- [Codebase Structure](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/codebase/STRUCTURE.md) - new (+299)
- [Testing Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/codebase/TESTING.md) - new (+380)
- [01-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/phases/01-single-consumer-consolidation/01-01-PLAN.md) - new (+196)
- [Phase 1 Plan 1: Remove Bun Bot Notification Watcher Summary](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/phases/01-single-consumer-consolidation/01-01-SUMMARY.md) - new (+105)
- [Phase 1: Single-Consumer Consolidation - Context](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/phases/01-single-consumer-consolidation/01-CONTEXT.md) - new (+67)
- [claude-tts-companion — Notification Intelligence Milestone](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/PROJECT.md) - new (+94)
- [Requirements: claude-tts-companion — Notification Intelligence](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/REQUIREMENTS.md) - new (+89)
- [Architecture: Notification Intelligence Pipeline](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/research/ARCHITECTURE.md) - new (+318)
- [Feature Landscape: Notification Intelligence](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/research/FEATURES.md) - new (+100)
- [Domain Pitfalls](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/research/PITFALLS.md) - new (+269)
- [Technology Stack: Notification Intelligence](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/research/STACK.md) - new (+420)
- [Project Research Summary](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/research/SUMMARY.md) - new (+176)
- [Roadmap: claude-tts-companion — Notification Intelligence](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/ROADMAP.md) - new (+146)
- [Project State](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/STATE.md) - new (+81)
- [claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/CLAUDE.md) - updated (+339)
- [ssh-tunnel-companion](https://github.com/terrylica/cc-skills/blob/main/plugins/ssh-tunnel-companion/CLAUDE.md) - new (+195)

## [12.35.1](https://github.com/terrylica/cc-skills/compare/v12.35.0...v12.35.1) (2026-04-02)

# [12.35.0](https://github.com/terrylica/cc-skills/compare/v12.34.0...v12.35.0) (2026-04-02)


### Bug Fixes

* **tts:** kill previous tts_kokoro.sh instance on rapid re-invocation ([d4950a4](https://github.com/terrylica/cc-skills/commit/d4950a48d5965c3fc4d334c8bcec7853f381edaa))
* **tts:** pass speed setting to Kokoro synthesis engine ([390faf0](https://github.com/terrylica/cc-skills/commit/390faf0aa8220655b73b816b7ca6f8fe1c537fc8))
* **tts:** queue consecutive invocations instead of preempting ([7df85ac](https://github.com/terrylica/cc-skills/commit/7df85ac55b46140bb2502b0924e94172f66bed28))
* **tts:** simplify health check to companion-only for reliability ([c44f225](https://github.com/terrylica/cc-skills/commit/c44f225b14574ddbb90cd08a5378619e931430d5))
* **tts:** stop script kills entire queue, not just current playback ([c2c8a13](https://github.com/terrylica/cc-skills/commit/c2c8a13cb831ef73b54d95e94cbfd0883c35c4ea))
* **tts:** use awk %c NUL output instead of \0 for macOS compatibility ([7c7bb9c](https://github.com/terrylica/cc-skills/commit/7c7bb9c21100c4dc6fe98bb031936bf099ca6752))


### Features

* **quant-research:** add odb-microstructure-forensics skill ([c96c5b4](https://github.com/terrylica/cc-skills/commit/c96c5b418152c9bc26e3de73625ab0535a0688fd))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>productivity-tools</strong> (1 change)</summary>

- [notion-cli](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/notion-cli/SKILL.md) - new (+205)

</details>

<details>
<summary><strong>quant-research</strong> (1 change)</summary>

- [odb-microstructure-forensics](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/odb-microstructure-forensics/SKILL.md) - new (+191)

</details>


### Skill References

<details>
<summary><strong>productivity-tools/notion-cli</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/notion-cli/references/evolution-log.md) - new (+11)

</details>

<details>
<summary><strong>quant-research/odb-microstructure-forensics</strong> (2 files)</summary>

- [ClickHouse Schema Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/odb-microstructure-forensics/references/clickhouse-schema.md) - new (+72)
- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/odb-microstructure-forensics/references/evolution-log.md) - new (+9)

</details>


## Other Documentation

### Other

- [productivity-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/CLAUDE.md) - updated (+2/-1)
- [quant-research Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/CLAUDE.md) - updated (+9/-8)

# [12.34.0](https://github.com/terrylica/cc-skills/compare/v12.33.0...v12.34.0) (2026-04-01)


### Bug Fixes

* **calendar-event-manager:** replace date strings with programmatic construction ([da189b4](https://github.com/terrylica/cc-skills/commit/da189b4efdce9b3da6356a92095c434522237826))
* **pueue:** exclude SSH from auto-wrap and add duration gate to reminder ([1636604](https://github.com/terrylica/cc-skills/commit/1636604dab31ee1f5d605a8ad71b6c544333b060))
* **skills:** restrict disable-model-invocation: true to hooks only ([2c2af20](https://github.com/terrylica/cc-skills/commit/2c2af20ac13978bb46795782c06315f3334aa1af))
* **tts:** add word-tracking to bionic reading mode ([c2470a0](https://github.com/terrylica/cc-skills/commit/c2470a0242338ded8e2d55945946ed086ad48306))
* **tts:** bionic reading uses opacity contrast instead of font weight ([7d370ca](https://github.com/terrylica/cc-skills/commit/7d370ca096339daccb1914e1ae2ddad54802c629))


### Features

* **agent-reach:** sync with upstream router architecture ([910c12d](https://github.com/terrylica/cc-skills/commit/910c12d3e40f430b5cbac95e2fb64bd81ad0f22c))
* **tts:** adjustable bionic suffix opacity via SwiftBar ([8d7178c](https://github.com/terrylica/cc-skills/commit/8d7178cf3bcf0cbe134887c4364eaf687f568c1c))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>agent-reach</strong> (1 change)</summary>

- [agent-reach](https://github.com/terrylica/cc-skills/blob/main/plugins/agent-reach/skills/agent-reach/SKILL.md) - updated (+40/-127)

</details>

<details>
<summary><strong>asciinema-tools</strong> (5 changes)</summary>

- [bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/bootstrap/SKILL.md) - updated (+1/-1)
- [daemon-setup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-setup/SKILL.md) - updated (+1/-1)
- [daemon-start](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-start/SKILL.md) - updated (+1/-1)
- [daemon-stop](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-stop/SKILL.md) - updated (+1/-1)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/setup/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>calcom-commander</strong> (2 changes)</summary>

- [infra-deploy](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/infra-deploy/SKILL.md) - updated (+1/-1)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/setup/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [cloudflare-workers-publish](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/cloudflare-workers-publish/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>doc-tools</strong> (1 change)</summary>

- [latex-setup](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-setup/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>git-town-workflow</strong> (1 change)</summary>

- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/skills/setup/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>gmail-commander</strong> (1 change)</summary>

- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/setup/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>itp</strong> (4 changes)</summary>

- [bootstrap-monorepo](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/bootstrap-monorepo/SKILL.md) - updated (+1/-1)
- [release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/release/SKILL.md) - updated (+1/-1)
- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/SKILL.md) - updated (+1/-1)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/setup/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>itp-hooks</strong> (1 change)</summary>

- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/setup/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>mise</strong> (1 change)</summary>

- [sred-commit](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/sred-commit/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>productivity-tools</strong> (1 change)</summary>

- [calendar-event-manager](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/calendar-event-manager/SKILL.md) - updated (+82/-14)

</details>

<details>
<summary><strong>ru</strong> (2 changes)</summary>

- [start](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/start/SKILL.md) - updated (+1/-1)
- [stop](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/stop/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>statusline-tools</strong> (1 change)</summary>

- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/setup/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>tlg</strong> (15 changes)</summary>

- [cleanup-deleted](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/cleanup-deleted/SKILL.md) - updated (+1/-1)
- [create-group](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/create-group/SKILL.md) - updated (+2/-2)
- [delete-messages](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/delete-messages/SKILL.md) - updated (+2/-2)
- [download-media](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/download-media/SKILL.md) - updated (+2/-2)
- [dump-channel](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/dump-channel/SKILL.md) - new (+128)
- [find-user](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/find-user/SKILL.md) - updated (+2/-2)
- [forward-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/forward-message/SKILL.md) - updated (+2/-2)
- [list-dialogs](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/list-dialogs/SKILL.md) - updated (+2/-2)
- [manage-members](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/manage-members/SKILL.md) - updated (+2/-2)
- [mark-read](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/mark-read/SKILL.md) - updated (+2/-2)
- [pin-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/pin-message/SKILL.md) - updated (+2/-2)
- [search-messages](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/search-messages/SKILL.md) - updated (+2/-2)
- [send-media](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/send-media/SKILL.md) - updated (+2/-2)
- [send-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/send-message/SKILL.md) - updated (+2/-2)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/setup/SKILL.md) - updated (+5/-5)

</details>

<details>
<summary><strong>tts-tg-sync</strong> (4 changes)</summary>

- [clean-component-removal](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/clean-component-removal/SKILL.md) - updated (+1/-1)
- [component-version-upgrade](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/component-version-upgrade/SKILL.md) - updated (+1/-1)
- [full-stack-bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/full-stack-bootstrap/SKILL.md) - updated (+1/-1)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/setup/SKILL.md) - updated (+1/-1)

</details>


### Skill References

<details>
<summary><strong>agent-reach/agent-reach</strong> (6 files)</summary>

- [职场招聘](https://github.com/terrylica/cc-skills/blob/main/plugins/agent-reach/skills/agent-reach/references/career.md) - new (+29)
- [开发工具](https://github.com/terrylica/cc-skills/blob/main/plugins/agent-reach/skills/agent-reach/references/dev.md) - new (+63)
- [搜索工具](https://github.com/terrylica/cc-skills/blob/main/plugins/agent-reach/skills/agent-reach/references/search.md) - new (+33)
- [社交媒体 & 社区](https://github.com/terrylica/cc-skills/blob/main/plugins/agent-reach/skills/agent-reach/references/social.md) - new (+209)
- [视频/播客](https://github.com/terrylica/cc-skills/blob/main/plugins/agent-reach/skills/agent-reach/references/video.md) - new (+115)
- [网页阅读](https://github.com/terrylica/cc-skills/blob/main/plugins/agent-reach/skills/agent-reach/references/web.md) - new (+76)

</details>

<details>
<summary><strong>plugin-dev/skill-architecture</strong> (3 files)</summary>

- [Invocation Control](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/invocation-control.md) - updated (+7/-11)
- [Task Templates](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/task-templates.md) - updated (+1/-1)
- [My Skill](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/validation-reference.md) - updated (+2/-1)

</details>


## Other Documentation

### Other

- [Telegram CLI Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/CLAUDE.md) - updated (+2/-2)

# [12.33.0](https://github.com/terrylica/cc-skills/compare/v12.32.0...v12.33.0) (2026-04-01)


### Bug Fixes

* **validation:** fix sandwich check SIGPIPE and add reminder to skill-architecture ([3fcc5dd](https://github.com/terrylica/cc-skills/commit/3fcc5dd52d82bd1ae0faab080b305c2b4eff0c73))


### Features

* **validation:** enforce self-evolution sandwich in validator and release preflight ([c49a67f](https://github.com/terrylica/cc-skills/commit/c49a67f44b78387439e43cf549cb027a723aec5b))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>plugin-dev</strong> (1 change)</summary>

- [skill-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/SKILL.md) - updated (+2)

</details>

# [12.32.0](https://github.com/terrylica/cc-skills/compare/v12.31.1...v12.32.0) (2026-04-01)


### Bug Fixes

* **skills:** move Post-Execution Reflection to bottom of 20 misplaced skills ([46de475](https://github.com/terrylica/cc-skills/commit/46de47562bfbd48e33ceb452f738bac5b1a776a0))


### Features

* **skills:** add Post-Execution Reflection to all 154 remaining skills ([7494ff3](https://github.com/terrylica/cc-skills/commit/7494ff3544a11f14b49e4b73e18f02ee2f2e6db4))
* **skills:** add Self-Evolving Skill reminder to top of all 192 skills ([3c68e4c](https://github.com/terrylica/cc-skills/commit/3c68e4c2a0381c6d47c4d686cebf7c84fe6673c2))
* **skills:** make Post-Execution Reflection compulsory for all skills, not just stepwise ([7da5165](https://github.com/terrylica/cc-skills/commit/7da5165f7803c828d467cd12fd76e753c43e71d8))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>agent-reach</strong> (1 change)</summary>

- [agent-reach](https://github.com/terrylica/cc-skills/blob/main/plugins/agent-reach/skills/agent-reach/SKILL.md) - updated (+13)

</details>

<details>
<summary><strong>asciinema-tools</strong> (24 changes)</summary>

- [analyze](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/analyze/SKILL.md) - updated (+13)
- [asciinema-analyzer](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-analyzer/SKILL.md) - updated (+15)
- [asciinema-cast-format](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-cast-format/SKILL.md) - updated (+13)
- [asciinema-converter](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-converter/SKILL.md) - updated (+13)
- [asciinema-player](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-player/SKILL.md) - updated (+15)
- [asciinema-recorder](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-recorder/SKILL.md) - updated (+15)
- [asciinema-streaming-backup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/SKILL.md) - updated (+15)
- [backup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/backup/SKILL.md) - updated (+13)
- [bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/bootstrap/SKILL.md) - updated (+14/-12)
- [convert](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/convert/SKILL.md) - updated (+13)
- [daemon-logs](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-logs/SKILL.md) - updated (+13)
- [daemon-setup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-setup/SKILL.md) - updated (+2)
- [daemon-start](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-start/SKILL.md) - updated (+13)
- [daemon-status](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-status/SKILL.md) - updated (+13)
- [daemon-stop](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-stop/SKILL.md) - updated (+13)
- [finalize](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/finalize/SKILL.md) - updated (+15)
- [format](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/format/SKILL.md) - updated (+13)
- [full-workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/full-workflow/SKILL.md) - updated (+13)
- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/hooks/SKILL.md) - updated (+13)
- [play](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/play/SKILL.md) - updated (+13)
- [post-session](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/post-session/SKILL.md) - updated (+15)
- [record](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/record/SKILL.md) - updated (+13)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/setup/SKILL.md) - updated (+13)
- [summarize](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/summarize/SKILL.md) - updated (+15)

</details>

<details>
<summary><strong>calcom-commander</strong> (6 changes)</summary>

- [booking-config](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/booking-config/SKILL.md) - updated (+15)
- [booking-notify](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/booking-notify/SKILL.md) - updated (+15)
- [calcom-access](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/calcom-access/SKILL.md) - updated (+15)
- [health](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/health/SKILL.md) - updated (+13)
- [infra-deploy](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/infra-deploy/SKILL.md) - updated (+15)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/setup/SKILL.md) - updated (+2)

</details>

<details>
<summary><strong>cli-anything</strong> (1 change)</summary>

- [cli-anything](https://github.com/terrylica/cc-skills/blob/main/plugins/cli-anything/skills/cli-anything/SKILL.md) - updated (+13)

</details>

<details>
<summary><strong>devops-tools</strong> (23 changes)</summary>

- [agentic-process-monitor](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/agentic-process-monitor/SKILL.md) - updated (+13)
- [claude-code-proxy-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/claude-code-proxy-patterns/SKILL.md) - updated (+13)
- [clickhouse-cloud-management](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/clickhouse-cloud-management/SKILL.md) - updated (+13)
- [clickhouse-pydantic-config](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/clickhouse-pydantic-config/SKILL.md) - updated (+13)
- [cloudflare-workers-publish](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/cloudflare-workers-publish/SKILL.md) - updated (+15/-13)
- [disk-hygiene](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/disk-hygiene/SKILL.md) - updated (+15)
- [distributed-job-safety](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/SKILL.md) - updated (+13)
- [doppler-secret-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/doppler-secret-validation/SKILL.md) - updated (+15)
- [doppler-workflows](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/doppler-workflows/SKILL.md) - updated (+13)
- [dual-channel-watchexec](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/dual-channel-watchexec/SKILL.md) - updated (+13)
- [firecrawl-research-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/SKILL.md) - updated (+13)
- [macbook-desktop-mode](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/macbook-desktop-mode/SKILL.md) - updated (+15)
- [ml-data-pipeline-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/ml-data-pipeline-architecture/SKILL.md) - updated (+15)
- [ml-failfast-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/ml-failfast-validation/SKILL.md) - updated (+13)
- [mlflow-python](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/mlflow-python/SKILL.md) - updated (+13)
- [project-directory-migration](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/project-directory-migration/SKILL.md) - updated (+15)
- [pueue-job-orchestration](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/SKILL.md) - updated (+13)
- [python-logging-best-practices](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/python-logging-best-practices/SKILL.md) - updated (+13)
- [python-memory-safe-scripts](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/python-memory-safe-scripts/SKILL.md) - updated (+13)
- [session-chronicle](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/SKILL.md) - updated (+13)
- [session-debrief](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-debrief/SKILL.md) - updated (+16)
- [session-recovery](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-recovery/SKILL.md) - updated (+13)
- [worktree-manager](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/worktree-manager/SKILL.md) - updated (+15)

</details>

<details>
<summary><strong>doc-tools</strong> (10 changes)</summary>

- [academic-pdf-to-gfm](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/academic-pdf-to-gfm/SKILL.md) - updated (+15)
- [ascii-diagram-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/ascii-diagram-validator/SKILL.md) - updated (+13)
- [documentation-standards](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/documentation-standards/SKILL.md) - updated (+13)
- [glossary-management](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/glossary-management/SKILL.md) - updated (+13)
- [latex-build](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-build/SKILL.md) - updated (+13)
- [latex-setup](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-setup/SKILL.md) - updated (+13)
- [latex-tables](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-tables/SKILL.md) - updated (+13)
- [pandoc-pdf-generation](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/pandoc-pdf-generation/SKILL.md) - updated (+13)
- [plotext-financial-chart](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/plotext-financial-chart/SKILL.md) - updated (+13)
- [terminal-print](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/terminal-print/SKILL.md) - updated (+13)

</details>

<details>
<summary><strong>dotfiles-tools</strong> (3 changes)</summary>

- [chezmoi-sync](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/skills/chezmoi-sync/SKILL.md) - updated (+15)
- [chezmoi-workflows](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/skills/chezmoi-workflows/SKILL.md) - updated (+13)
- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/skills/hooks/SKILL.md) - updated (+13)

</details>

<details>
<summary><strong>gemini-deep-research</strong> (1 change)</summary>

- [gemini-deep-research](https://github.com/terrylica/cc-skills/blob/main/plugins/gemini-deep-research/skills/research/SKILL.md) - updated (+13)

</details>

<details>
<summary><strong>gh-tools</strong> (6 changes)</summary>

- [fork-intelligence](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/fork-intelligence/SKILL.md) - updated (+15)
- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/hooks/SKILL.md) - updated (+13)
- [issue-create](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issue-create/SKILL.md) - updated (+13)
- [issues-workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issues-workflow/SKILL.md) - updated (+13)
- [pr-gfm-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/pr-gfm-validator/SKILL.md) - updated (+15)
- [research-archival](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/research-archival/SKILL.md) - updated (+13)

</details>

<details>
<summary><strong>git-town-workflow</strong> (4 changes)</summary>

- [contribute](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/skills/contribute/SKILL.md) - updated (+14/-12)
- [fork](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/skills/fork/SKILL.md) - updated (+14/-12)
- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/skills/hooks/SKILL.md) - updated (+15)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/skills/setup/SKILL.md) - updated (+14/-12)

</details>

<details>
<summary><strong>gitnexus-tools</strong> (4 changes)</summary>

- [dead-code](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/dead-code/SKILL.md) - updated (+15)
- [explore](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/explore/SKILL.md) - updated (+15)
- [impact](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/impact/SKILL.md) - updated (+15)
- [reindex](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/reindex/SKILL.md) - updated (+15)

</details>

<details>
<summary><strong>gmail-commander</strong> (6 changes)</summary>

- [bot-process-control](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/bot-process-control/SKILL.md) - updated (+15)
- [email-triage](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/email-triage/SKILL.md) - updated (+15)
- [gmail-access](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/gmail-access/SKILL.md) - updated (+15)
- [health](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/health/SKILL.md) - updated (+13)
- [interactive-bot](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/interactive-bot/SKILL.md) - updated (+15)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/setup/SKILL.md) - updated (+2)

</details>

<details>
<summary><strong>itp</strong> (15 changes)</summary>

- [adr-code-traceability](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/adr-code-traceability/SKILL.md) - updated (+13)
- [adr-graph-easy-architect](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/adr-graph-easy-architect/SKILL.md) - updated (+13)
- [bootstrap-monorepo](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/bootstrap-monorepo/SKILL.md) - updated (+13)
- [code-hardcode-audit](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/code-hardcode-audit/SKILL.md) - updated (+13)
- [go](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/go/SKILL.md) - updated (+14/-12)
- [graph-easy](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/graph-easy/SKILL.md) - updated (+13)
- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/hooks/SKILL.md) - updated (+13)
- [impl-standards](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/impl-standards/SKILL.md) - updated (+13)
- [implement-plan-preflight](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/implement-plan-preflight/SKILL.md) - updated (+13)
- [mise-configuration](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-configuration/SKILL.md) - updated (+13)
- [mise-tasks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/SKILL.md) - updated (+13)
- [pypi-doppler](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/pypi-doppler/SKILL.md) - updated (+13)
- [release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/release/SKILL.md) - updated (+13)
- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/SKILL.md) - updated (+13)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/setup/SKILL.md) - updated (+17/-15)

</details>

<details>
<summary><strong>itp-hooks</strong> (2 changes)</summary>

- [hooks-development](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/SKILL.md) - updated (+13)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/setup/SKILL.md) - updated (+15)

</details>

<details>
<summary><strong>kokoro-tts</strong> (8 changes)</summary>

- [diagnose](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/diagnose/SKILL.md) - updated (+15)
- [health](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/health/SKILL.md) - updated (+13)
- [install](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/install/SKILL.md) - updated (+15)
- [realtime-audio-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/realtime-audio-architecture/SKILL.md) - updated (+13)
- [remove](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/remove/SKILL.md) - updated (+15)
- [server](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/server/SKILL.md) - updated (+13)
- [synthesize](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/synthesize/SKILL.md) - updated (+13)
- [upgrade](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/upgrade/SKILL.md) - updated (+15)

</details>

<details>
<summary><strong>link-tools</strong> (2 changes)</summary>

- [link-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/skills/link-validation/SKILL.md) - updated (+13)
- [link-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/skills/link-validator/SKILL.md) - updated (+13)

</details>

<details>
<summary><strong>media-tools</strong> (1 change)</summary>

- [youtube-to-bookplayer](https://github.com/terrylica/cc-skills/blob/main/plugins/media-tools/skills/youtube-to-bookplayer/SKILL.md) - updated (+12/-10)

</details>

<details>
<summary><strong>mise</strong> (4 changes)</summary>

- [list-repo-tasks](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/list-repo-tasks/SKILL.md) - updated (+15)
- [run-full-release](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/run-full-release/SKILL.md) - updated (+2)
- [show-env-status](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/show-env-status/SKILL.md) - updated (+13)
- [sred-commit](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/sred-commit/SKILL.md) - updated (+15)

</details>

<details>
<summary><strong>mql5</strong> (6 changes)</summary>

- [article-extractor](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/article-extractor/SKILL.md) - updated (+13)
- [fxview-parquet-consumer](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/fxview-parquet-consumer/SKILL.md) - updated (+13)
- [log-reader](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/log-reader/SKILL.md) - updated (+13)
- [mql5-indicator-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/mql5-indicator-patterns/SKILL.md) - updated (+13)
- [python-workspace](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/python-workspace/SKILL.md) - updated (+13)
- [tick-collection-ops](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/tick-collection-ops/SKILL.md) - updated (+13)

</details>

<details>
<summary><strong>plugin-dev</strong> (3 changes)</summary>

- [create](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/create/SKILL.md) - updated (+6/-4)
- [plugin-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/plugin-validator/SKILL.md) - updated (+15/-13)
- [skill-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/SKILL.md) - updated (+19/-3)

</details>

<details>
<summary><strong>productivity-tools</strong> (7 changes)</summary>

- [calendar-event-manager](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/calendar-event-manager/SKILL.md) - updated (+13)
- [gdrive-access](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/gdrive-access/SKILL.md) - updated (+15)
- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/hooks/SKILL.md) - updated (+13)
- [imessage-query](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/imessage-query/SKILL.md) - updated (+13)
- [iterm2-layout](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/iterm2-layout/SKILL.md) - updated (+13)
- [notion-sdk](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/notion-sdk/SKILL.md) - updated (+13)
- [slash-command-factory](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/slash-command-factory/SKILL.md) - updated (+13)

</details>

<details>
<summary><strong>quality-tools</strong> (10 changes)</summary>

- [alpha-forge-preship](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/alpha-forge-preship/SKILL.md) - updated (+13)
- [clickhouse-architect](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/clickhouse-architect/SKILL.md) - updated (+13)
- [code-clone-assistant](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/code-clone-assistant/SKILL.md) - updated (+13)
- [dead-code-detector](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/dead-code-detector/SKILL.md) - updated (+13)
- [multi-agent-e2e-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/multi-agent-e2e-validation/SKILL.md) - updated (+15)
- [multi-agent-performance-profiling](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/multi-agent-performance-profiling/SKILL.md) - updated (+15)
- [pre-ship-review](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/pre-ship-review/SKILL.md) - updated (+17/-15)
- [refactoring-guide](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/refactoring-guide/SKILL.md) - updated (+13)
- [schema-e2e-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/schema-e2e-validation/SKILL.md) - updated (+13)
- [symmetric-dogfooding](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/symmetric-dogfooding/SKILL.md) - updated (+15)

</details>

<details>
<summary><strong>quant-research</strong> (7 changes)</summary>

- [adaptive-wfo-epoch](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/SKILL.md) - updated (+13)
- [backtesting-py-oracle](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/backtesting-py-oracle/SKILL.md) - updated (+13)
- [evolutionary-metric-ranking](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/evolutionary-metric-ranking/SKILL.md) - updated (+15/-13)
- [exchange-session-detector](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/exchange-session-detector/SKILL.md) - updated (+13)
- [opendeviation-eval-metrics](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/opendeviation-eval-metrics/SKILL.md) - updated (+13)
- [sharpe-ratio-non-iid-corrections](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/sharpe-ratio-non-iid-corrections/SKILL.md) - updated (+13)
- [zigzag-pattern-classifier](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/zigzag-pattern-classifier/SKILL.md) - updated (+13)

</details>

<details>
<summary><strong>ru</strong> (9 changes)</summary>

- [audit-now](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/audit-now/SKILL.md) - updated (+13)
- [encourage](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/encourage/SKILL.md) - updated (+13)
- [forbid](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/forbid/SKILL.md) - updated (+13)
- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/hooks/SKILL.md) - updated (+13)
- [settings](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/settings/SKILL.md) - updated (+13)
- [start](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/start/SKILL.md) - updated (+15)
- [status](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/status/SKILL.md) - updated (+14)
- [stop](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/stop/SKILL.md) - updated (+14)
- [wizard](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/wizard/SKILL.md) - updated (+15)

</details>

<details>
<summary><strong>rust-tools</strong> (2 changes)</summary>

- [rust-dependency-audit](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-dependency-audit/SKILL.md) - updated (+13)
- [rust-sota-arsenal](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/SKILL.md) - updated (+15)

</details>

<details>
<summary><strong>statusline-tools</strong> (4 changes)</summary>

- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/hooks/SKILL.md) - updated (+13)
- [ignore](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/ignore/SKILL.md) - updated (+13)
- [session-info](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/session-info/SKILL.md) - updated (+13)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/setup/SKILL.md) - updated (+13)

</details>

<details>
<summary><strong>tlg</strong> (14 changes)</summary>

- [cleanup-deleted](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/cleanup-deleted/SKILL.md) - updated (+13/-1)
- [create-group](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/create-group/SKILL.md) - updated (+12)
- [delete-messages](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/delete-messages/SKILL.md) - updated (+12)
- [download-media](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/download-media/SKILL.md) - updated (+13/-1)
- [find-user](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/find-user/SKILL.md) - updated (+12)
- [forward-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/forward-message/SKILL.md) - updated (+12)
- [list-dialogs](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/list-dialogs/SKILL.md) - updated (+19/-7)
- [manage-members](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/manage-members/SKILL.md) - updated (+12)
- [mark-read](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/mark-read/SKILL.md) - updated (+12)
- [pin-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/pin-message/SKILL.md) - updated (+12)
- [search-messages](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/search-messages/SKILL.md) - updated (+12)
- [send-media](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/send-media/SKILL.md) - updated (+12)
- [send-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/send-message/SKILL.md) - updated (+17/-5)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/setup/SKILL.md) - updated (+22/-6)

</details>

<details>
<summary><strong>tts-tg-sync</strong> (10 changes)</summary>

- [bot-process-control](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/bot-process-control/SKILL.md) - updated (+15/-13)
- [clean-component-removal](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/clean-component-removal/SKILL.md) - updated (+17/-15)
- [component-version-upgrade](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/component-version-upgrade/SKILL.md) - updated (+17/-15)
- [diagnostic-issue-resolver](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/diagnostic-issue-resolver/SKILL.md) - updated (+17/-15)
- [full-stack-bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/full-stack-bootstrap/SKILL.md) - updated (+17/-15)
- [health](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/health/SKILL.md) - updated (+14/-12)
- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/hooks/SKILL.md) - updated (+13)
- [settings-and-tuning](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/settings-and-tuning/SKILL.md) - updated (+17/-15)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/setup/SKILL.md) - updated (+15)
- [voice-quality-audition](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/voice-quality-audition/SKILL.md) - updated (+17/-15)

</details>

## [12.31.1](https://github.com/terrylica/cc-skills/compare/v12.31.0...v12.31.1) (2026-04-01)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>mise</strong> (1 change)</summary>

- [run-full-release](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/run-full-release/SKILL.md) - updated (+95/-26)

</details>


### Skill References

<details>
<summary><strong>mise/run-full-release</strong> (3 files)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/run-full-release/references/evolution-log.md) - updated (+20/-1)
- [Scaffolding And Recovery](https://github.com/terrylica/cc-skills/blob/v12.31.0/plugins/mise/skills/run-full-release/references/scaffolding-and-recovery.md) - deleted
- [Task Implementations](https://github.com/terrylica/cc-skills/blob/v12.31.0/plugins/mise/skills/run-full-release/references/task-implementations.md) - deleted

</details>


## Repository Documentation

### General Documentation

- [Lessons Learned](https://github.com/terrylica/cc-skills/blob/main/docs/LESSONS.md) - updated (+2)

## Other Documentation

### Other

- [mise Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/CLAUDE.md) - updated (+6/-27)

# [12.31.0](https://github.com/terrylica/cc-skills/compare/v12.30.1...v12.31.0) (2026-04-01)


### Bug Fixes

* **skills:** relocate self-evolution for attention primacy/recency and fix tlg skill standards ([1326a30](https://github.com/terrylica/cc-skills/commit/1326a308f97879ddbdc2349052bc205cb701de06))
* **tts:** add paragraph breaks to multi-chunk subtitle pages ([8ffe076](https://github.com/terrylica/cc-skills/commit/8ffe076fe20a646bd3d9dee8a7e415d5cb07bbe0))
* **tts:** append trailing words dropped by Kokoro tokenizer to subtitles ([fb4a11c](https://github.com/terrylica/cc-skills/commit/fb4a11c47a9b435413b5ecd43ade91ffb1a6ee59))
* **tts:** onset padding for all pipeline paths and strip middle dot ([58ce3ac](https://github.com/terrylica/cc-skills/commit/58ce3acaaa9860f372dc5d23efb4cf361c1738f7))
* **tts:** pad onsets for trailing words dropped by Kokoro tokenizer ([889b396](https://github.com/terrylica/cc-skills/commit/889b39668073b9323db24a766fc5b8461cf770f3))
* **tts:** recognize middle dot (·) as bullet marker for paragraph splitting ([13b3913](https://github.com/terrylica/cc-skills/commit/13b3913b9b938064a65f5a7b43a505da024fbec1))
* **tts:** replace + and & symbols with words for subtitle alignment ([ba57aad](https://github.com/terrylica/cc-skills/commit/ba57aad6cdc9ab80eb6ceb251d20c46a2888f875))


### Features

* **tts:** add tts_stop.sh for ⌃ESC hotkey to kill TTS instantly ([5886f0c](https://github.com/terrylica/cc-skills/commit/5886f0c280a80a93f71b1fb8b509fd526e78b85f))
* **tts:** progressive chunking for faster time-to-first-audio ([76bdf62](https://github.com/terrylica/cc-skills/commit/76bdf62199726307e74cfa460026b09af2ed91e5))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>plugin-dev</strong> (1 change)</summary>

- [skill-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/SKILL.md) - updated (+61/-43)

</details>

<details>
<summary><strong>tlg</strong> (12 changes)</summary>

- [cleanup-deleted](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/cleanup-deleted/SKILL.md) - updated (+6/-1)
- [create-group](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/create-group/SKILL.md) - updated (+6/-1)
- [delete-messages](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/delete-messages/SKILL.md) - updated (+6/-1)
- [download-media](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/download-media/SKILL.md) - updated (+6/-1)
- [find-user](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/find-user/SKILL.md) - updated (+6/-1)
- [forward-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/forward-message/SKILL.md) - updated (+6/-1)
- [manage-members](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/manage-members/SKILL.md) - updated (+6/-1)
- [mark-read](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/mark-read/SKILL.md) - updated (+6/-1)
- [pin-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/pin-message/SKILL.md) - updated (+6/-1)
- [search-messages](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/search-messages/SKILL.md) - updated (+6/-1)
- [send-media](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/send-media/SKILL.md) - updated (+6/-1)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/setup/SKILL.md) - updated (+1/-1)

</details>


### Skill References

<details>
<summary><strong>plugin-dev/skill-architecture</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/evolution-log.md) - updated (+32)

</details>

## [12.30.1](https://github.com/terrylica/cc-skills/compare/v12.30.0...v12.30.1) (2026-04-01)


### Bug Fixes

* **tts:** use SIGKILL instead of SIGTERM to stop afplay ([7eb74ae](https://github.com/terrylica/cc-skills/commit/7eb74ae457676c55ba1448fc43e5ef62338002c6))

# [12.30.0](https://github.com/terrylica/cc-skills/compare/v12.29.3...v12.30.0) (2026-04-01)


### Bug Fixes

* **tts:** preserve numbered list prefixes in speech and unwrap terminal soft-wraps ([21966de](https://github.com/terrylica/cc-skills/commit/21966de5d175251c4c815dcb7503c3d648061b4e))


### Features

* **claude-tts-companion:** add Makefile for atomic build-deploy-restart ([0e22605](https://github.com/terrylica/cc-skills/commit/0e226054c56e52534c64b367c13fc53c4e4cfa03))

## [12.29.3](https://github.com/terrylica/cc-skills/compare/v12.29.2...v12.29.3) (2026-03-31)


### Bug Fixes

* **tts:** add killall afplay safety net to stop() for race condition ([be32ab2](https://github.com/terrylica/cc-skills/commit/be32ab2b43d0448ec93fdfc4910f1ede0d8c6e15))

## [12.29.2](https://github.com/terrylica/cc-skills/compare/v12.29.1...v12.29.2) (2026-03-31)


### Bug Fixes

* **tts:** hide subtitle panel on stop playback ([fd959ea](https://github.com/terrylica/cc-skills/commit/fd959eac2fe74a7a4e1175cb9d9837ada03591a1))

## [12.29.1](https://github.com/terrylica/cc-skills/compare/v12.29.0...v12.29.1) (2026-03-31)


### Bug Fixes

* **tts:** fix audio jitter via launchd ProcessType=Interactive scheduling ([815844e](https://github.com/terrylica/cc-skills/commit/815844e2892fb3b940898c4473221140664aa120))

# [12.29.0](https://github.com/terrylica/cc-skills/compare/v12.28.3...v12.29.0) (2026-03-31)


### Features

* **tts:** add audio routing audit to detect virtual device jitter at startup ([9bd033c](https://github.com/terrylica/cc-skills/commit/9bd033c5d56c5bc45cecdd6735dfac99f85ec8b5))

## [12.28.3](https://github.com/terrylica/cc-skills/compare/v12.28.2...v12.28.3) (2026-03-31)


### Bug Fixes

* **tts:** increase HTTP handler timeout and improve tts_kokoro.sh reliability ([9b57f53](https://github.com/terrylica/cc-skills/commit/9b57f5302dbf4c30deeb381945534a0ec013e9d9))

## [12.28.2](https://github.com/terrylica/cc-skills/compare/v12.28.1...v12.28.2) (2026-03-31)


### Bug Fixes

* **claude-tts-companion:** eliminate audio jitter via posix_spawn backend ([c3525c2](https://github.com/terrylica/cc-skills/commit/c3525c2e392fbae14710b5de65bdf6f2a09f0e6d))

## [12.28.1](https://github.com/terrylica/cc-skills/compare/v12.28.0...v12.28.1) (2026-03-31)


### Bug Fixes

* **tts:** eliminate audio jitter via posix_spawn afplay backend ([2be6067](https://github.com/terrylica/cc-skills/commit/2be6067267c4295a3a390b7a0ae5ffd522dfaf37))

# [12.28.0](https://github.com/terrylica/cc-skills/compare/v12.27.1...v12.28.0) (2026-03-31)


### Features

* **tts:** replace AVAudioEngine with afplay subprocess for jitter-free playback ([e2e80e1](https://github.com/terrylica/cc-skills/commit/e2e80e1e989a47ec5e760d70dc76d2125ef7b9fd))

## [12.27.1](https://github.com/terrylica/cc-skills/compare/v12.27.0...v12.27.1) (2026-03-30)


### Bug Fixes

* **tts:** ipv6 localhost format and increased tts timeout to 120s ([11a086f](https://github.com/terrylica/cc-skills/commit/11a086f8d19c5fd4b5f9475076f22b238adad5b0))

# [12.27.0](https://github.com/terrylica/cc-skills/compare/v12.26.2...v12.27.0) (2026-03-30)


### Bug Fixes

* **itp-hooks:** pueue hook improvements for Claude Code integration ([155c0f7](https://github.com/terrylica/cc-skills/commit/155c0f7ea76923d570e0c5bfc3ccb9591122da46))
* scope inline-ignore audit to edited lines only ([e70dc40](https://github.com/terrylica/cc-skills/commit/e70dc4005173fa2504e8755faec6d014066762b9))
* **tts:** 500ms inter-paragraph delay for MLX server stability ([5276dcd](https://github.com/terrylica/cc-skills/commit/5276dcdf25d3676defebdbc811f1dda014da881e))
* **tts:** anti-fragile startup and circuit breaker tuning ([54a3668](https://github.com/terrylica/cc-skills/commit/54a3668fc52d326451e59699b5ed27dc2e46d021))
* **tts:** clear stale edge hints before first streaming chunk ([21f4a92](https://github.com/terrylica/cc-skills/commit/21f4a92936ed818d8a4296a8388416c5c903d576))
* **tts:** correct zigzag edge hints and health-gated synthesis ([b464770](https://github.com/terrylica/cc-skills/commit/b464770c5be6886b910214dc47b523525bb4d91e))
* **tts:** edge hints applied on chunk activation, not scheduling ([1e98d15](https://github.com/terrylica/cc-skills/commit/1e98d15c55f9ee58d789839e9712bed8e6bd672a))
* **tts:** remove diagonal line artifact from border mask ([9fe3d12](https://github.com/terrylica/cc-skills/commit/9fe3d123033820317536abc81e76aaf227c0552b))
* **tts:** streaming subtitle hide after last paragraph finishes ([0c32afe](https://github.com/terrylica/cc-skills/commit/0c32afe90bca77c63486168cbf6b4b9f3875296f))
* **tts:** suppress subtitle-only flash for automated TTS requests ([72720db](https://github.com/terrylica/cc-skills/commit/72720db9cf7b8bd6b0bc62c70fef44fe3097e954))
* **tts:** zigzag indicators as overlay strips, clean last segment ([b70e533](https://github.com/terrylica/cc-skills/commit/b70e533ec852e9f69384252dc65c33b08feaa3f7))
* **tts:** zigzag replaces border edge instead of overlapping ([c6150e9](https://github.com/terrylica/cc-skills/commit/c6150e92d6a735fbe6e402bb5a5cbcfc612d3e80))


### Features

* **quick-260330-9js:** add POST /tts/stop endpoint for mid-stream cancellation ([7007be8](https://github.com/terrylica/cc-skills/commit/7007be88d85fc5ad602b705fb036adb609eb722a))
* **quick-260330-9js:** streaming paragraph-chunked TTS pipeline ([aa3e950](https://github.com/terrylica/cc-skills/commit/aa3e950bd58ed0c6d303d5c8b87abffb43b08977))
* **tts:** adaptive paragraph segmentation with configurable budget ([1de124b](https://github.com/terrylica/cc-skills/commit/1de124be6dfaca77f452c42dd702e8c43e8025d9))
* **tts:** add GET /tts/status endpoint and TTSQueue.Status ([a665ae0](https://github.com/terrylica/cc-skills/commit/a665ae068c5bbef60da3b56377f67bc95039030e))
* **tts:** jagged rainbow border for bisected paragraph continuation ([361a831](https://github.com/terrylica/cc-skills/commit/361a831b46f4c6a5a742981cd0146ae47893b4bf))





---

## Documentation Changes

## Other Documentation

### Other

- [260330-9js-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/quick/260330-9js-streaming-paragraph-chunking-for-long-tt/260330-9js-PLAN.md) - new (+266)
- [Quick Plan 260330-9js: Streaming Paragraph Chunking for Long TTS Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/quick/260330-9js-streaming-paragraph-chunking-for-long-tt/260330-9js-SUMMARY.md) - new (+100)
- [Project State](https://github.com/terrylica/cc-skills/blob/main/.planning/STATE.md) - updated (+7/-1)

## [12.26.2](https://github.com/terrylica/cc-skills/compare/v12.26.1...v12.26.2) (2026-03-30)


### Bug Fixes

* **claude-tts-companion:** bypass audio rebuild cooldown when device actually changed ([ff969a0](https://github.com/terrylica/cc-skills/commit/ff969a0ae58cdcd3a051316baa1bec4100031fcf))

## [12.26.1](https://github.com/terrylica/cc-skills/compare/v12.26.0...v12.26.1) (2026-03-30)


### Bug Fixes

* **claude-tts-companion:** replace character-offset anchoring with paragraph-structure counting ([01dcb71](https://github.com/terrylica/cc-skills/commit/01dcb714577d05335c213d70726d5b89670e5e6e))





---

## Documentation Changes

## Other Documentation

### Other

- [subtitle-incorrect-paragraph-breaks](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/subtitle-incorrect-paragraph-breaks.md) - updated (+3/-2)

# [12.26.0](https://github.com/terrylica/cc-skills/compare/v12.25.0...v12.26.0) (2026-03-30)


### Features

* **statusline:** add release age "ago" suffix to version tag ([681a9e7](https://github.com/terrylica/cc-skills/commit/681a9e7ac608dfd224d8bf8fb63798ad159c710f))

# [12.25.0](https://github.com/terrylica/cc-skills/compare/v12.24.4...v12.25.0) (2026-03-30)


### Features

* **statusline:** show git version tag after status indicators ([08f19ff](https://github.com/terrylica/cc-skills/commit/08f19ffbf79e3fa9672b51fac92fa411cf0f4a05))

## [12.24.4](https://github.com/terrylica/cc-skills/compare/v12.24.3...v12.24.4) (2026-03-30)


### Bug Fixes

* **claude-tts-companion:** character-offset anchoring for paragraph break alignment ([33a9d7a](https://github.com/terrylica/cc-skills/commit/33a9d7aada76f732dc3c6b94a1fe4ab702bd5a97))





---

## Documentation Changes

## Other Documentation

### Other

- [subtitle-incorrect-paragraph-breaks](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/subtitle-incorrect-paragraph-breaks.md) - new (+43)

## [12.24.3](https://github.com/terrylica/cc-skills/compare/v12.24.2...v12.24.3) (2026-03-29)


### Bug Fixes

* **statusline-tools:** remove dying-session detection from Stop hook GC ([83115f7](https://github.com/terrylica/cc-skills/commit/83115f7e57a09042095e88485fd361a60a25624a))

## [12.24.2](https://github.com/terrylica/cc-skills/compare/v12.24.1...v12.24.2) (2026-03-29)


### Bug Fixes

* **statusline-tools:** use session JSONL mtime as liveness signal for non-durable crons ([6c5984b](https://github.com/terrylica/cc-skills/commit/6c5984bdb793be4dbb9dfcdfebdf9719d97bb982))

## [12.24.1](https://github.com/terrylica/cc-skills/compare/v12.24.0...v12.24.1) (2026-03-29)


### Bug Fixes

* **statusline-tools:** implement anti-fragile 3-layer defense-in-depth cron registry GC ([0a070fd](https://github.com/terrylica/cc-skills/commit/0a070fd65f89f63ac2aa831665d88361b04eb135))
* subtitle sync drift + punctuation restoration ([cb6a335](https://github.com/terrylica/cc-skills/commit/cb6a335081bc131a6c2f7635a2de12eb117e8976)), closes [terrylica/cc-skills#73](https://github.com/terrylica/cc-skills/issues/73)





---

## Documentation Changes

## Other Documentation

### Other

- [speech-subtitle-sync-drift-v2](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/speech-subtitle-sync-drift-v2.md) - new (+82)
- [subtitle-punctuation-stripped](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/subtitle-punctuation-stripped.md) - new (+82)
- [Plan 03-02 Summary: Word Timestamps + TTS Karaoke](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/03-tts-engine/03-02-SUMMARY.md) - new (+43)
- [Roadmap: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/ROADMAP.md) - updated (+19/-19)

# [12.24.0](https://github.com/terrylica/cc-skills/compare/v12.23.1...v12.24.0) (2026-03-29)


### Features

* **itp-hooks:** add Stop hook for markdownlint + prettier on .md files ([c5a88ac](https://github.com/terrylica/cc-skills/commit/c5a88ac5a195ad28a6aa78b2ac0595c20baf91a0))





---

## Documentation Changes

## Other Documentation

### Other

- [Milestones](https://github.com/terrylica/cc-skills/blob/main/.planning/MILESTONES.md) - updated (+60)
- [Milestone v4.9.0 Audit Report](https://github.com/terrylica/cc-skills/blob/main/.planning/milestones/v4.9.0-MILESTONE-AUDIT.md) - updated (+55/-43)
- [Requirements Archive: v4.9.0 SwiftBar UI & Telegram Bot Activation](https://github.com/terrylica/cc-skills/blob/main/.planning/milestones/v4.9.0-REQUIREMENTS.md) - updated (+35/-20)
- [Roadmap: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/milestones/v4.9.0-ROADMAP.md) - updated (+45/-2)
- [Telegram Bot Verification](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/33-telegram-bot-verification/33-01-PLAN.md) - new (+143)
- [Phase 33 Plan 01: Telegram Bot Verification Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/33-telegram-bot-verification/33-01-SUMMARY.md) - new (+94)
- [Phase 33: Telegram Bot Verification - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/33-telegram-bot-verification/33-CONTEXT.md) - new (+58)
- [Telegram Bot Verification](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/33-telegram-bot-verification/33-VERIFICATION.md) - new (+105)
- [E2E Pipeline Verification](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/34-e2e-pipeline-verification/34-01-PLAN.md) - new (+149)
- [Phase 34 Plan 01: E2E Pipeline Verification Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/34-e2e-pipeline-verification/34-01-SUMMARY.md) - new (+86)
- [Phase 34: E2E Pipeline Verification - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/34-e2e-pipeline-verification/34-CONTEXT.md) - new (+59)
- [E2E Pipeline Verification](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/34-e2e-pipeline-verification/34-VERIFICATION.md) - new (+94)
- [Requirements: claude-tts-companion v4.9.0](https://github.com/terrylica/cc-skills/blob/main/.planning/REQUIREMENTS.md) - updated (+23/-23)
- [Roadmap: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/ROADMAP.md) - updated (+30/-2)
- [Project State](https://github.com/terrylica/cc-skills/blob/main/.planning/STATE.md) - updated (+10/-6)
- [v4.9.0-MILESTONE-AUDIT](https://github.com/terrylica/cc-skills/blob/v12.23.1/.planning/v4.9.0-MILESTONE-AUDIT.md) - deleted

## [12.23.1](https://github.com/terrylica/cc-skills/compare/v12.23.0...v12.23.1) (2026-03-29)


### Bug Fixes

* **itp-hooks:** catch ruff: noqa, skip test files in audit ([c508925](https://github.com/terrylica/cc-skills/commit/c508925411e5b45eeabc535a9ffe262ee85afcd3))





---

## Documentation Changes

## Other Documentation

### Other

- [Phase 32 Plan 02: Health Check Timer Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/32-audio-device-resilience/32-02-SUMMARY.md) - new (+103)
- [Phase 32: Audio Device Resilience Verification Report](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/32-audio-device-resilience/32-VERIFICATION.md) - new (+147)
- [Requirements: claude-tts-companion v4.9.0](https://github.com/terrylica/cc-skills/blob/main/.planning/REQUIREMENTS.md) - updated (+4/-4)
- [Roadmap: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/ROADMAP.md) - updated (+2/-2)
- [Project State](https://github.com/terrylica/cc-skills/blob/main/.planning/STATE.md) - updated (+10/-8)
- [Milestone v4.9.0 Audit Report](https://github.com/terrylica/cc-skills/blob/main/.planning/v4.9.0-MILESTONE-AUDIT.md) - new (+143)

# [12.23.0](https://github.com/terrylica/cc-skills/compare/v12.22.0...v12.23.0) (2026-03-29)


### Bug Fixes

* caption history text wrapping + layout + capacity 1000 ([e94d022](https://github.com/terrylica/cc-skills/commit/e94d0224bd5bb04a0fec2827a10382c1a27d06c5))
* **itp-hooks:** remove BLE001 rule and align README table ([bbaecd3](https://github.com/terrylica/cc-skills/commit/bbaecd3982afc9a1f4d51ffa67cf75edd99ccfe1))
* replace NSTableView with NSTextView for caption history word wrap ([58d017c](https://github.com/terrylica/cc-skills/commit/58d017c0265220e04a381cc2aaa6e003a51c5df6))
* single newline between paragraphs (no empty lines) in both subtitle and caption history ([0e59555](https://github.com/terrylica/cc-skills/commit/0e5955537bcdb9735a3c64dd8663f9d1f87c183f))
* use preprocessed text in ChunkResult to prevent word-count drift ([c81d6d1](https://github.com/terrylica/cc-skills/commit/c81d6d19240c781f6cba99e1c28f9b278c5417f3))


### Features

* **32-01:** add audio resilience constants to Config.swift ([af9c0e7](https://github.com/terrylica/cc-skills/commit/af9c0e750368f330ddccd5107e5f7f15488498eb))
* **32-01:** add CoreAudio HAL listener + full engine rebuild + debounce ([4becbd3](https://github.com/terrylica/cc-skills/commit/4becbd357f79306d911260650ad1fe31e5402993))
* **32-02:** add periodic health check timer to AudioStreamPlayer ([ad9c319](https://github.com/terrylica/cc-skills/commit/ad9c319f4d318ab93313b1d716dc200e3de2b0d9))
* animated rainbow gradient border + top-left position memory ([e95a7ed](https://github.com/terrylica/cc-skills/commit/e95a7ede9e38b24327e073424d355ddaac590733))
* caption history UUID + sync telemetry + word wrap fix ([4d956cc](https://github.com/terrylica/cc-skills/commit/4d956ccde83c681d1d072390ba4d7b5ee1f96bd5))
* **itp-hooks:** add PostToolUse inline ignore audit + docs ([2827ef6](https://github.com/terrylica/cc-skills/commit/2827ef62c265bf7bcd64632d7fdf8efeba1622cb))
* **itp-hooks:** add PreToolUse inline ignore guard ([260958a](https://github.com/terrylica/cc-skills/commit/260958a9ea5e1b1d2b0edfd989d61c81312b58d9))
* paragraph breaks in subtitle without affecting word-onset sync ([b84f1c1](https://github.com/terrylica/cc-skills/commit/b84f1c17b55c20f3c487f02c03cd9d0373f84750))
* preserve paragraph breaks in subtitle display ([50deb46](https://github.com/terrylica/cc-skills/commit/50deb46ca16646491765ecc52d05cc79956b0122))
* solid black subtitle background + persist drag position ([0348b58](https://github.com/terrylica/cc-skills/commit/0348b58aaea900250b05fdbf4f76b74a08844943))
* subtle UUID label + right-click copies subtitle in triple backticks ([58a309e](https://github.com/terrylica/cc-skills/commit/58a309e9fa3f004371df61aad6bf64abef589d25))





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [ITP Hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/README.md) - updated (+7/-7)

## Other Documentation

### Other

- [32-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/32-audio-device-resilience/32-01-PLAN.md) - new (+288)
- [Phase 32 Plan 01: Audio Device Resilience Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/32-audio-device-resilience/32-01-SUMMARY.md) - new (+116)
- [32-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/32-audio-device-resilience/32-02-PLAN.md) - new (+239)
- [Phase 32: Audio Device Resilience - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/32-audio-device-resilience/32-CONTEXT.md) - new (+147)
- [Phase 32: Audio Device Resilience - Discussion Log](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/32-audio-device-resilience/32-DISCUSSION-LOG.md) - new (+55)
- [Phase 32: Audio Device Resilience - Research](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/32-audio-device-resilience/32-RESEARCH.md) - new (+477)
- [Phase 32 — Validation Strategy](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/32-audio-device-resilience/32-VALIDATION.md) - new (+75)
- [Requirements: claude-tts-companion v4.9.0](https://github.com/terrylica/cc-skills/blob/main/.planning/REQUIREMENTS.md) - updated (+26/-11)
- [Roadmap: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/ROADMAP.md) - updated (+17/-2)
- [Project State](https://github.com/terrylica/cc-skills/blob/main/.planning/STATE.md) - updated (+17/-10)
- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+39/-1)

# [12.22.0](https://github.com/terrylica/cc-skills/compare/v12.21.0...v12.22.0) (2026-03-29)


### Bug Fixes

* align word tokenization with Kokoro + strip markdown before TTS ([6c38fff](https://github.com/terrylica/cc-skills/commit/6c38fffb3898a0905a484c897f6b1ddfb2086862)), closes [#headings](https://github.com/terrylica/cc-skills/issues/headings)
* auto-size subtitle panel to paragraph + word-wrap caption history ([380ed20](https://github.com/terrylica/cc-skills/commit/380ed20050581d003f3f979ecfe8d4c8532f6d63))
* capture subtitlePanel directly in linger timer to prevent stuck subtitles ([4e4d87f](https://github.com/terrylica/cc-skills/commit/4e4d87ff79d66eb18308f8fed3068809fad60db2))
* eliminate first-buffer audio blip by pre-starting player node on reset ([172e39c](https://github.com/terrylica/cc-skills/commit/172e39cba1cfaf2e4b675687e74992d11fae452c))
* full-paragraph synthesis + 48kHz upsample + audit cleanup ([7d79f63](https://github.com/terrylica/cc-skills/commit/7d79f63934e6eb9dbcf27ce3094e969c40347b75))
* **hooks:** remove ADR reference from code traceability reminder ([6be008c](https://github.com/terrylica/cc-skills/commit/6be008ce69482d14605ff7203b38ca03b43c4aa3))
* left-align subtitles + auto-size panel height + single-page paragraph ([00ff059](https://github.com/terrylica/cc-skills/commit/00ff05923f1aaaf1ceb1d8079b2cb567e6b3e79f))
* Python TTS server auto-restarts after 10s idle to reclaim Metal GPU memory ([5d1c8a6](https://github.com/terrylica/cc-skills/commit/5d1c8a62bdd413d242fd77919435a8079c806c04)), closes [#1086](https://github.com/terrylica/cc-skills/issues/1086)
* record TTS text to caption history via TTSQueue ([46632d7](https://github.com/terrylica/cc-skills/commit/46632d739b875cee0a72f39551abe26eb1c0f093))


### Features

* **14-01:** create fxview-parquet-consumer cc-skill ([cfc200d](https://github.com/terrylica/cc-skills/commit/cfc200d0cad348abd76042f48995a3439e8297ea))
* **14-01:** create tick-collection-ops cc-skill ([bed18af](https://github.com/terrylica/cc-skills/commit/bed18af999cac21d81ce706d924dc5e34ade0213))
* **26-01:** switch TTSEngine to /v1/audio/speech-with-timestamps for native word onsets ([8b6a7b7](https://github.com/terrylica/cc-skills/commit/8b6a7b7bff7e0b25e53978b0ae803583de270907))
* **29:** activate Telegram bot with credentials from secrets file ([cfdf364](https://github.com/terrylica/cc-skills/commit/cfdf3649b8206a9ada65ca5c01543f6ab5db3731))
* **30:** SwiftBar shows Python TTS health + proper bot status ([6f65cf3](https://github.com/terrylica/cc-skills/commit/6f65cf3ea25f065569f2024aafedf565098550ce))
* add middle screen position option for subtitle overlay ([cf15d3c](https://github.com/terrylica/cc-skills/commit/cf15d3c7700d6b3f64d46b129a05b66eadb4fd67))
* add priority-aware TTS queue with preemption for concurrent requests ([4b19f47](https://github.com/terrylica/cc-skills/commit/4b19f4713911ab888eb25584b7fecc326c852091))
* hold Option key to drag subtitle panel to any position ([6d93c78](https://github.com/terrylica/cc-skills/commit/6d93c78dfa95dcca6f727aec15af29099acff2f7))
* **itp-hooks:** add setproctitle reminder for Python service/daemon files ([c5c42cc](https://github.com/terrylica/cc-skills/commit/c5c42ccc8488780c9bbb93e756423bfbdfb22a03))
* Notification hook support for plan mode TTS alerts ([a53a4ba](https://github.com/terrylica/cc-skills/commit/a53a4babe8b55b4f6a182d6c9af0f5c8d502af5b))
* paragraph subtitle scope (default) with sentence-by-sentence option ([4d6136a](https://github.com/terrylica/cc-skills/commit/4d6136a4fde2bf78e925c20ff990778586d37a5d))
* subtitle panel always draggable — click and drag to reposition ([b634f7d](https://github.com/terrylica/cc-skills/commit/b634f7deb46c99110a498dfe0c545ad2ef735657))
* **tts:** delegate MLX synthesis to Python Kokoro server (localhost:8779) ([010cfe2](https://github.com/terrylica/cc-skills/commit/010cfe29a267a4da8be840d73edd601c4e6a74fe))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>mise</strong> (1 change)</summary>

- [run-full-release](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/run-full-release/SKILL.md) - updated (+21/-320)

</details>

<details>
<summary><strong>mql5</strong> (2 changes)</summary>

- [fxview-parquet-consumer](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/fxview-parquet-consumer/SKILL.md) - new (+143)
- [tick-collection-ops](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/tick-collection-ops/SKILL.md) - new (+181)

</details>


### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+85/-36)

</details>

<details>
<summary><strong>mise/run-full-release</strong> (1 file)</summary>

- [Scaffolding & Recovery](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/run-full-release/references/scaffolding-and-recovery.md) - new (+176)

</details>


## Other Documentation

### Other

- [spike-mlx-metal-memory](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/spike-mlx-metal-memory.md) - new (+96)
- [telegram-notification-formatting](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/telegram-notification-formatting.md) - new (+129)
- [tts-test-streaming](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/tts-test-streaming.md) - new (+46)
- [Milestones](https://github.com/terrylica/cc-skills/blob/main/.planning/MILESTONES.md) - updated (+157)
- [v4.7.0-MILESTONE-AUDIT](https://github.com/terrylica/cc-skills/blob/main/.planning/milestones/v4.7.0-MILESTONE-AUDIT.md) - renamed from `.planning/v4.7.0-MILESTONE-AUDIT.md`
- [Requirements Archive: v4.7.0 Architecture Hardening + Feature Expansion](https://github.com/terrylica/cc-skills/blob/main/.planning/milestones/v4.7.0-REQUIREMENTS.md) - new (+393)
- [Roadmap: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/milestones/v4.7.0-ROADMAP.md) - new (+573)
- [v4.8.0-MILESTONE-AUDIT](https://github.com/terrylica/cc-skills/blob/main/.planning/milestones/v4.8.0-MILESTONE-AUDIT.md) - new (+87)
- [Requirements Archive: v4.8.0 Python MLX TTS Consolidation](https://github.com/terrylica/cc-skills/blob/main/.planning/milestones/v4.8.0-REQUIREMENTS.md) - new (+90)
- [Roadmap: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/milestones/v4.8.0-ROADMAP.md) - new (+670)
- [v4.9.0-MILESTONE-AUDIT](https://github.com/terrylica/cc-skills/blob/main/.planning/milestones/v4.9.0-MILESTONE-AUDIT.md) - new (+60)
- [Requirements Archive: v4.9.0 SwiftBar UI & Telegram Bot Activation](https://github.com/terrylica/cc-skills/blob/main/.planning/milestones/v4.9.0-REQUIREMENTS.md) - new (+61)
- [Roadmap: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/milestones/v4.9.0-ROADMAP.md) - new (+727)
- [Phase 20.1: MLX Metal Memory Lifecycle - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/20.1-mlx-metal-memory-lifecycle/20.1-CONTEXT.md) - new (+124)
- [25-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/25-python-tts-server-timestamp-endpoint/25-01-PLAN.md) - new (+288)
- [Phase 25 Plan 01: Python TTS Server Timestamp Endpoint Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/25-python-tts-server-timestamp-endpoint/25-01-SUMMARY.md) - new (+119)
- [Phase 25: Python TTS Server Timestamp Endpoint - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/25-python-tts-server-timestamp-endpoint/25-CONTEXT.md) - new (+95)
- [Phase 25: Python TTS Server Timestamp Endpoint Verification Report](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/25-python-tts-server-timestamp-endpoint/25-VERIFICATION.md) - new (+96)
- [26-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/26-swift-ttsengine-python-integration/26-01-PLAN.md) - new (+224)
- [Phase 26 Plan 01: Swift TTSEngine Python Integration Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/26-swift-ttsengine-python-integration/26-01-SUMMARY.md) - new (+107)
- [Phase 26: Swift TTSEngine Python Integration - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/26-swift-ttsengine-python-integration/26-CONTEXT.md) - new (+88)
- [Phase 26: Swift TTSEngine Python Integration Verification Report](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/26-swift-ttsengine-python-integration/26-VERIFICATION.md) - new (+112)
- [27-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/27-mlx-dependency-removal/27-01-PLAN.md) - new (+216)
- [Phase 27 Plan 01: MLX Dependency Removal Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/27-mlx-dependency-removal/27-01-SUMMARY.md) - new (+132)
- [Phase 27: MLX Dependency Removal - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/27-mlx-dependency-removal/27-CONTEXT.md) - new (+74)
- [28-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/28-memory-lifecycle-cleanup/28-01-PLAN.md) - new (+239)
- [Phase 28 Plan 01: Memory Lifecycle Cleanup Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/28-memory-lifecycle-cleanup/28-01-SUMMARY.md) - new (+109)
- [Phase 28: Memory Lifecycle Cleanup - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/28-memory-lifecycle-cleanup/28-CONTEXT.md) - new (+78)
- [Phase 29: Telegram Bot Activation - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/29-telegram-bot-activation/29-CONTEXT.md) - new (+69)
- [Phase 30: SwiftBar UI Updates Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/30-swiftbar-ui-updates/30-01-SUMMARY.md) - new (+98)
- [Phase 30: SwiftBar UI Updates - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/30-swiftbar-ui-updates/30-CONTEXT.md) - new (+65)
- [claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/PROJECT.md) - updated (+36/-20)
- [Requirements: claude-tts-companion v4.9.0](https://github.com/terrylica/cc-skills/blob/main/.planning/REQUIREMENTS.md) - updated (+33/-365)
- [Roadmap: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/ROADMAP.md) - updated (+170/-16)
- [Project State](https://github.com/terrylica/cc-skills/blob/main/.planning/STATE.md) - updated (+34/-88)
- [Benchmark: FluidAudio CoreML Kokoro TTS](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/debug/benchmark-fluidaudio.md) - new (+168)
- [Benchmark: Python MLX Kokoro TTS (Baseline)](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/debug/benchmark-python-mlx-baseline.md) - new (+48)
- [Benchmark: sherpa-onnx Kokoro TTS](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/debug/benchmark-sherpa-onnx.md) - new (+105)
- [MLX Python Memory Leak Research: IOAccelerator / Metal GPU Memory](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/debug/mlx-python-memory-leak-research.md) - new (+419)
- [tts-periodic-audio-stutters](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/debug/tts-periodic-audio-stutters.md) - new (+107)
- [TTS Runtime Alternatives Research](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/debug/tts-runtime-alternatives-research.md) - new (+310)
- [Python TTS Server Delegation Summary](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/.planning/quick/python-tts-delegation-SUMMARY.md) - new (+64)

# [12.21.0](https://github.com/terrylica/cc-skills/compare/v12.20.1...v12.21.0) (2026-03-28)


### Bug Fixes

* **hooks:** migrate gh-issue-no-anchors from deprecated decision:block to permissionDecision:deny ([3e721ef](https://github.com/terrylica/cc-skills/commit/3e721ef3ddd085d4bdaf41bb98ede8e425a914ba)), closes [#issue-no-anchors](https://github.com/terrylica/cc-skills/issues/issue-no-anchors)
* **hooks:** version-guard excludes all dot-prefixed directories ([504d61b](https://github.com/terrylica/cc-skills/commit/504d61be441afc6c614ec214c83a77a8a7dc6a85))
* **hooks:** version-guard now excludes .planning/ directories ([0857b0a](https://github.com/terrylica/cc-skills/commit/0857b0a0b6743012e4a922a3725332e78d0c0f57))
* replace AVAudioPlayer with AVAudioEngine batch-then-play for stutter-free TTS ([06374bc](https://github.com/terrylica/cc-skills/commit/06374bc9ae000fe1d1057edf270e8fa2348c9f3a))


### Features

* **18-01:** create CompanionApp coordinator and slim main.swift to 42 lines ([44455a9](https://github.com/terrylica/cc-skills/commit/44455a917afcfd29ea8cac8aabdfcfea8a785fae))
* **19-02:** create PlaybackManager @MainActor class and migrate TTSEngine to actor ([e9cf6ef](https://github.com/terrylica/cc-skills/commit/e9cf6ef0e2aadf9cad0b56707546f516914bfc7b))
* **19-02:** update all callers for actor TTSEngine and PlaybackManager ([f50cbc5](https://github.com/terrylica/cc-skills/commit/f50cbc530818a8a5799ecafd0242097ce24340b2))
* **20.1-01:** add synthesis counter + graceful restart + launchd tuning ([8e243f8](https://github.com/terrylica/cc-skills/commit/8e243f84c9720078976830dfdfb0d8b973d6e9af))
* **21-01:** add TTSPipelineCoordinator for exclusive pipeline access ([d457d1a](https://github.com/terrylica/cc-skills/commit/d457d1a0e82d670ec0a98c06980e8e314e0095b9))
* **21-01:** migrate TelegramBot and HTTPControlServer to TTSPipelineCoordinator ([7267b8f](https://github.com/terrylica/cc-skills/commit/7267b8f86999a73a1715c68aa9744143f03cdf89))
* **21-02:** add AVAudioEngine route change recovery to AudioStreamPlayer ([ac47c35](https://github.com/terrylica/cc-skills/commit/ac47c354558893ae7b16b94b3e20095554ba2193))
* **21-02:** add memory pressure monitoring and subtitle-only degradation ([920abab](https://github.com/terrylica/cc-skills/commit/920abab8adb81802ab329d0f1751f2201baa6fad))
* **22-01:** add DisplayMode enum, BionicRenderer, settings + HTTP API integration ([51fbba3](https://github.com/terrylica/cc-skills/commit/51fbba3ff18d23e446a7610c3d1dd5ef67dc6a00))
* **22-01:** integrate bionic rendering into SubtitlePanel ([46d513f](https://github.com/terrylica/cc-skills/commit/46d513f3bf97ddaa36dd6b59176291846522773d))
* **23-01:** add CaptionHistoryPanel with scrollable table, timestamps, and click-to-copy ([5b1c92a](https://github.com/terrylica/cc-skills/commit/5b1c92a514f512159ba4b1a3b9e691361520febc))
* **23-01:** add HTTP panel endpoints and CompanionApp wiring ([99141d3](https://github.com/terrylica/cc-skills/commit/99141d3d4ba5e1c8c5aaf870e9051e0b63796cce))
* **24-01:** add CSherpaOnnx C module target with vendored header and linker settings ([3503580](https://github.com/terrylica/cc-skills/commit/3503580d31eb2b59bc038f2e29c68520ac121bf3))
* **24-01:** add SherpaOnnxEngine with on-demand loading and 30s idle unload ([f1c9d08](https://github.com/terrylica/cc-skills/commit/f1c9d0891513d72a6b9dc050f9dcfcd0bbe7cee3))
* **24-02:** update TelegramBot to use CJK auto-routing dispatch ([ba0a1b4](https://github.com/terrylica/cc-skills/commit/ba0a1b4c0b46ba12f06370ebb6ce194239bb7819))
* **24-02:** wire SherpaOnnxEngine into TTSEngine with CJK auto-routing ([a813529](https://github.com/terrylica/cc-skills/commit/a8135295794c936cc8e6d540754191fb61450e7e))
* **skill-architecture:** add compulsory Post-Execution Reflection to 24 skills ([ce6f563](https://github.com/terrylica/cc-skills/commit/ce6f563dd239678e82e19733790cb0b6bfe27b7f)), closes [#70](https://github.com/terrylica/cc-skills/issues/70)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>asciinema-tools</strong> (2 changes)</summary>

- [bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/bootstrap/SKILL.md) - updated (+14)
- [daemon-setup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-setup/SKILL.md) - updated (+15)

</details>

<details>
<summary><strong>calcom-commander</strong> (1 change)</summary>

- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/setup/SKILL.md) - updated (+15)

</details>

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [cloudflare-workers-publish](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/cloudflare-workers-publish/SKILL.md) - updated (+13)

</details>

<details>
<summary><strong>git-town-workflow</strong> (3 changes)</summary>

- [contribute](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/skills/contribute/SKILL.md) - updated (+14)
- [fork](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/skills/fork/SKILL.md) - updated (+14)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/skills/setup/SKILL.md) - updated (+14)

</details>

<details>
<summary><strong>gmail-commander</strong> (1 change)</summary>

- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/setup/SKILL.md) - updated (+15)

</details>

<details>
<summary><strong>itp</strong> (2 changes)</summary>

- [go](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/go/SKILL.md) - updated (+14)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/setup/SKILL.md) - updated (+14)

</details>

<details>
<summary><strong>media-tools</strong> (1 change)</summary>

- [youtube-to-bookplayer](https://github.com/terrylica/cc-skills/blob/main/plugins/media-tools/skills/youtube-to-bookplayer/SKILL.md) - updated (+13)

</details>

<details>
<summary><strong>plugin-dev</strong> (3 changes)</summary>

- [create](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/create/SKILL.md) - updated (+14)
- [plugin-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/plugin-validator/SKILL.md) - updated (+14)
- [skill-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/SKILL.md) - updated (+41/-4)

</details>

<details>
<summary><strong>quality-tools</strong> (1 change)</summary>

- [pre-ship-review](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/pre-ship-review/SKILL.md) - updated (+14)

</details>

<details>
<summary><strong>quant-research</strong> (1 change)</summary>

- [evolutionary-metric-ranking](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/evolutionary-metric-ranking/SKILL.md) - updated (+13)

</details>

<details>
<summary><strong>tts-tg-sync</strong> (8 changes)</summary>

- [bot-process-control](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/bot-process-control/SKILL.md) - updated (+13)
- [clean-component-removal](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/clean-component-removal/SKILL.md) - updated (+14)
- [component-version-upgrade](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/component-version-upgrade/SKILL.md) - updated (+14)
- [diagnostic-issue-resolver](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/diagnostic-issue-resolver/SKILL.md) - updated (+14)
- [full-stack-bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/full-stack-bootstrap/SKILL.md) - updated (+14)
- [health](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/health/SKILL.md) - updated (+14)
- [settings-and-tuning](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/settings-and-tuning/SKILL.md) - updated (+14)
- [voice-quality-audition](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/voice-quality-audition/SKILL.md) - updated (+14)

</details>


### Skill References

<details>
<summary><strong>plugin-dev/skill-architecture</strong> (5 files)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/evolution-log.md) - updated (+23)
- [Phased Execution Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/phased-execution.md) - updated (+43/-9)
- [Post-Execution Reflection](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/post-execution-reflection.md) - new (+186)
- [Task Templates](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/task-templates.md) - updated (+16/-13)
- [Theory: Self-Evolving Agent Skills](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/theory-self-evolution.md) - new (+122)

</details>


## Other Documentation

### Other

- [profile-mlx-metal-memory](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/profile-mlx-metal-memory.md) - new (+94)
- [tts-periodic-audio-stutters](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/tts-periodic-audio-stutters.md) - new (+85)
- [18-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/18-companioncore-library-test-infrastructure/18-01-PLAN.md) - new (+420)
- [Phase 18 Plan 01: CompanionCore Library Extraction Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/18-companioncore-library-test-infrastructure/18-01-SUMMARY.md) - new (+158)
- [18-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/18-companioncore-library-test-infrastructure/18-02-PLAN.md) - new (+339)
- [Phase 18 Plan 02: Unit Tests for Five Pure Types Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/18-companioncore-library-test-infrastructure/18-02-SUMMARY.md) - new (+131)
- [Phase 18: CompanionCore Library & Test Infrastructure - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/18-companioncore-library-test-infrastructure/18-CONTEXT.md) - new (+136)
- [Phase 18: CompanionCore Library & Test Infrastructure - Discussion Log](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/18-companioncore-library-test-infrastructure/18-DISCUSSION-LOG.md) - new (+60)
- [Phase 18: CompanionCore Library & Test Infrastructure - Research](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/18-companioncore-library-test-infrastructure/18-RESEARCH.md) - new (+547)
- [Phase 18 — Validation Strategy](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/18-companioncore-library-test-infrastructure/18-VALIDATION.md) - new (+76)
- [Phase 18: CompanionCore Library & Test Infrastructure Verification Report](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/18-companioncore-library-test-infrastructure/18-VERIFICATION.md) - new (+117)
- [19-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/19-ttsengine-decomposition-actor-migration/19-01-PLAN.md) - new (+219)
- [Phase 19 Plan 01: TTSEngine Pure Type Extraction Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/19-ttsengine-decomposition-actor-migration/19-01-SUMMARY.md) - new (+144)
- [19-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/19-ttsengine-decomposition-actor-migration/19-02-PLAN.md) - new (+401)
- [Phase 19 Plan 02: PlaybackManager Extraction and TTSEngine Actor Migration Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/19-ttsengine-decomposition-actor-migration/19-02-SUMMARY.md) - new (+166)
- [Phase 19: TTSEngine Decomposition & Actor Migration - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/19-ttsengine-decomposition-actor-migration/19-CONTEXT.md) - new (+127)
- [Phase 19: TTSEngine Decomposition & Actor Migration - Research](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/19-ttsengine-decomposition-actor-migration/19-RESEARCH.md) - new (+504)
- [Phase 19: TTSEngine Decomposition & Actor Migration Verification Report](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/19-ttsengine-decomposition-actor-migration/19-VERIFICATION.md) - new (+140)
- [20-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/20-unit-integration-tests/20-01-PLAN.md) - new (+276)
- [Phase 20 Plan 01: Pure-Struct Unit Tests Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/20-unit-integration-tests/20-01-SUMMARY.md) - new (+131)
- [20-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/20-unit-integration-tests/20-02-PLAN.md) - new (+267)
- [Phase 20 Plan 02: SubtitleChunker + Streaming Pipeline Tests Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/20-unit-integration-tests/20-02-SUMMARY.md) - new (+125)
- [Phase 20: Unit & Integration Tests - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/20-unit-integration-tests/20-CONTEXT.md) - new (+87)
- [Phase 20: Unit & Integration Tests Verification Report](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/20-unit-integration-tests/20-VERIFICATION.md) - new (+102)
- [20.1-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/20.1-mlx-metal-memory-lifecycle/20.1-01-PLAN.md) - new (+350)
- [Phase 20.1 Plan 01: MLX Metal Memory Lifecycle Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/20.1-mlx-metal-memory-lifecycle/20.1-01-SUMMARY.md) - new (+134)
- [21-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/21-pipeline-hardening/21-01-PLAN.md) - new (+236)
- [Phase 21 Plan 01: TTS Pipeline Coordinator Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/21-pipeline-hardening/21-01-SUMMARY.md) - new (+104)
- [21-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/21-pipeline-hardening/21-02-PLAN.md) - new (+266)
- [Phase 21 Plan 02: Hardware Event Hardening Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/21-pipeline-hardening/21-02-SUMMARY.md) - new (+117)
- [Phase 21: Pipeline Hardening - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/21-pipeline-hardening/21-CONTEXT.md) - new (+89)
- [Phase 21: Pipeline Hardening Verification Report](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/21-pipeline-hardening/21-VERIFICATION.md) - new (+113)
- [22-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/22-bionic-reading-mode/22-01-PLAN.md) - new (+270)
- [Phase 22 Plan 01: Bionic Reading Mode Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/22-bionic-reading-mode/22-01-SUMMARY.md) - new (+129)
- [22-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/22-bionic-reading-mode/22-02-PLAN.md) - new (+158)
- [Phase 22 Plan 02: SwiftBar Bionic Reading Toggle Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/22-bionic-reading-mode/22-02-SUMMARY.md) - new (+108)
- [Phase 22: Bionic Reading Mode - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/22-bionic-reading-mode/22-CONTEXT.md) - new (+89)
- [Phase 22: Bionic Reading Mode Verification Report](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/22-bionic-reading-mode/22-VERIFICATION.md) - new (+147)
- [23-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/23-caption-history-panel/23-01-PLAN.md) - new (+301)
- [Phase 23 Plan 01: Caption History Panel Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/23-caption-history-panel/23-01-SUMMARY.md) - new (+106)
- [23-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/23-caption-history-panel/23-02-PLAN.md) - new (+167)
- [Phase 23 Plan 02: SwiftBar Caption History Button Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/23-caption-history-panel/23-02-SUMMARY.md) - new (+102)
- [Phase 23: Caption History Panel - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/23-caption-history-panel/23-CONTEXT.md) - new (+83)
- [Phase 23: Caption History Panel Verification Report](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/23-caption-history-panel/23-VERIFICATION.md) - new (+132)
- [24-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/24-chinese-tts-fallback/24-01-PLAN.md) - new (+510)
- [Phase 24 Plan 01: CSherpaOnnx Module + SherpaOnnxEngine Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/24-chinese-tts-fallback/24-01-SUMMARY.md) - new (+121)
- [24-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/24-chinese-tts-fallback/24-02-PLAN.md) - new (+308)
- [Phase 24 Plan 02: CJK TTS Routing Integration Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/24-chinese-tts-fallback/24-02-SUMMARY.md) - new (+114)
- [Phase 24: Chinese TTS Fallback - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/24-chinese-tts-fallback/24-CONTEXT.md) - new (+84)
- [Phase 24: Chinese TTS Fallback Verification Report](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/24-chinese-tts-fallback/24-VERIFICATION.md) - new (+148)
- [claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/PROJECT.md) - updated (+40/-31)
- [Requirements: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/REQUIREMENTS.md) - updated (+111/-5)
- [Architecture Patterns <!-- # SSoT-OK -->](https://github.com/terrylica/cc-skills/blob/main/.planning/research/ARCHITECTURE.md) - updated (+414/-258)
- [Feature Landscape <!-- # SSoT-OK -->](https://github.com/terrylica/cc-skills/blob/main/.planning/research/FEATURES.md) - updated (+116/-95)
- [Domain Pitfalls <!-- # SSoT-OK -->](https://github.com/terrylica/cc-skills/blob/main/.planning/research/PITFALLS.md) - updated (+252/-195)
- [Technology Stack — v4.7.0 Additions <!-- # SSoT-OK -->](https://github.com/terrylica/cc-skills/blob/main/.planning/research/STACK.md) - updated (+163/-151)
- [Project Research Summary <!-- # SSoT-OK -->](https://github.com/terrylica/cc-skills/blob/main/.planning/research/SUMMARY.md) - updated (+135/-115)
- [Roadmap: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/ROADMAP.md) - updated (+230/-39)
- [Project State](https://github.com/terrylica/cc-skills/blob/main/.planning/STATE.md) - updated (+80/-64)
- [v4.7.0-MILESTONE-AUDIT](https://github.com/terrylica/cc-skills/blob/main/.planning/v4.7.0-MILESTONE-AUDIT.md) - new (+118)

## [12.20.1](https://github.com/terrylica/cc-skills/compare/v12.20.0...v12.20.1) (2026-03-27)





---

## Documentation Changes

## Other Documentation

### Other

- [audio-choppy-at-start](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/audio-choppy-at-start.md) - updated (+10/-2)
- [audio-choppy-silenced](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/audio-choppy-silenced.md) - updated (+10/-2)
- [audio-inter-chunk-gaps](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/audio-inter-chunk-gaps.md) - updated (+10/-2)
- [e2e-notification-pipeline-validation](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/e2e-notification-pipeline-validation.md) - updated (+10/-2)
- [intermittent-sync-drift](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/intermittent-sync-drift.md) - updated (+10/-2)
- [minimax-tts-telegram-fallback](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/minimax-tts-telegram-fallback.md) - updated (+10/-2)
- [mlx-metal-resource-crash](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/mlx-metal-resource-crash.md) - updated (+11/-2)
- [sentence-end-choppy-audio](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/sentence-end-choppy-audio.md) - updated (+10/-2)
- [speech-lags-behind-subs-v2](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/speech-lags-behind-subs-v2.md) - updated (+10/-2)
- [streaming-tts-early-cutoff](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/streaming-tts-early-cutoff.md) - updated (+10/-2)
- [subtitle-audio-desync](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/subtitle-audio-desync.md) - updated (+10/-2)
- [subtitle-highlight-bounceback](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/subtitle-highlight-bounceback.md) - updated (+10/-2)
- [tts-cutoff-and-subs-without-speech](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/tts-cutoff-and-subs-without-speech.md) - updated (+10/-2)
- [tts-speed-regression](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/tts-speed-regression.md) - updated (+10/-2)
- [tts-subtitle-lag](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/tts-subtitle-lag.md) - updated (+10/-2)

# [12.20.0](https://github.com/terrylica/cc-skills/compare/v12.19.1...v12.20.0) (2026-03-27)


### Features

* **quality-tools:** add refactoring-guide skill ([fc57c11](https://github.com/terrylica/cc-skills/commit/fc57c112c7273f02324891185b001f3a58c5c43f))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>quality-tools</strong> (1 change)</summary>

- [refactoring-guide](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/refactoring-guide/SKILL.md) - new (+116)

</details>


### Skill References

<details>
<summary><strong>quality-tools/refactoring-guide</strong> (7 files)</summary>

- [Architectural Refactoring Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/refactoring-guide/references/architecture.md) - new (+142)
- [Module Boundary Design](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/refactoring-guide/references/module-boundaries.md) - new (+118)
- [Rust-Specific Modularization](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/refactoring-guide/references/rust-specific.md) - new (+160)
- [Structural Coupling Analysis](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/refactoring-guide/references/structural-coupling.md) - new (+128)
- [Swift/macOS-Specific Modularization](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/refactoring-guide/references/swift-macos-specific.md) - new (+131)
- [Tactical Refactoring Moves](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/refactoring-guide/references/tactical-moves.md) - new (+202)
- [Type-Level Design for Refactoring](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/refactoring-guide/references/type-design.md) - new (+115)

</details>


## Other Documentation

### Other

- [mlx-metal-resource-crash](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/mlx-metal-resource-crash.md) - new (+78)
- [Anti-Fragility Audit: claude-tts-companion TTS Pipeline](https://github.com/terrylica/cc-skills/blob/main/.planning/quick/260327-d2e-replace-sherpa-onnx-with-kokoro-ios-mlx-/ANTI-FRAGILITY-AUDIT.md) - new (+307)

## [12.19.1](https://github.com/terrylica/cc-skills/compare/v12.19.0...v12.19.1) (2026-03-27)


### Bug Fixes

* remove direct MLX API calls that caused dual-Metal-device crash ([fe49c3f](https://github.com/terrylica/cc-skills/commit/fe49c3f6085f2852a63b3326557e46016af3fd76))

# [12.19.0](https://github.com/terrylica/cc-skills/compare/v12.18.0...v12.19.0) (2026-03-27)


### Bug Fixes

* add 300ms audioLaunchDelay to subtitle scheduling for afplay sync ([3020d64](https://github.com/terrylica/cc-skills/commit/3020d6472686faa057fb92b92184c89b4daa42ea))
* add pronunciation overrides to prevent Kokoro TTS mispronouncing "plugin" as "plu-gin" ([604b653](https://github.com/terrylica/cc-skills/commit/604b65344d9409ea2a9a4e4bcb7c4171ba2f1387))
* cancel in-progress audio before new TTS dispatch ([6c524be](https://github.com/terrylica/cc-skills/commit/6c524bedff56066de51c3d47c8952d78edee2a1f))
* clean up WAV after playback, not before synthesis (prevents AudioFileOpen failure on concurrent TTS) ([62e11f4](https://github.com/terrylica/cc-skills/commit/62e11f4c541c7fb2da917a7122643b2c8913c0eb))
* clear MLX Metal cache between sessions + cancel SyncDriver immediately ([9119ddc](https://github.com/terrylica/cc-skills/commit/9119ddceb13ebc1bc5e4d571ced0f9a0585b037f))
* complete e2e notification pipeline — 3 root causes resolved ([75fff04](https://github.com/terrylica/cc-skills/commit/75fff04d739cb72027c92ef08ddae32f00e557bd))
* defer stopPlayback until new audio is ready, not at synthesis start ([c5941a5](https://github.com/terrylica/cc-skills/commit/c5941a57ffbb6b093bf857ed8ee1d1cbc48e5a1f))
* make subtitle panel visible to screencapture (sharingType readOnly) ([248af95](https://github.com/terrylica/cc-skills/commit/248af95fc5bd305a08550f6b37f0cc61b8211b38))
* match legacy TTS speed 1.2 (was 1.0) + full-precision model in plist ([27444ff](https://github.com/terrylica/cc-skills/commit/27444ff9621b9c2c70111529273769d699d5f2d9))
* measure subtitle line width with bold font to prevent karaoke overflow ([89e8353](https://github.com/terrylica/cc-skills/commit/89e8353d75e0ea40bc703c07e35fba59d59f5246))
* normalize whitespace in subtitle chunker to prevent page-flip stall ([96bc589](https://github.com/terrylica/cc-skills/commit/96bc5897b15113174e67bae94009c433aa6ce9c8))
* replace DispatchSource directory watcher with reliable 2s polling timer ([4b96db9](https://github.com/terrylica/cc-skills/commit/4b96db91d4889103eace22e7c4fb3d3019dc8eaf))
* report actual Telegram bot status in health endpoint (was hardcoded "unknown") ([e06d5b2](https://github.com/terrylica/cc-skills/commit/e06d5b22fc354223562393115f75eca541b1a0c0))
* subtitle panel wrapping — three root causes (height calc, Auto Layout, attributed string) ([5d9faa7](https://github.com/terrylica/cc-skills/commit/5d9faa760cae636a14cba79b67bec1fa3b4290e9))
* SubtitlePanel reads font size and position from SettingsStore dynamically ([41a27a3](https://github.com/terrylica/cc-skills/commit/41a27a3aeb18d095fae3e22d46a3f6a7036a6083))
* SyncDriver finishPlayback when !isPlaying regardless of currentTime ([dda4212](https://github.com/terrylica/cc-skills/commit/dda42128a39387a78b433b54842df8320dfef05a))
* throttle SyncDriver "waiting for chunk" log to once per chunk index ([8e09cf5](https://github.com/terrylica/cc-skills/commit/8e09cf593f6b9aac4a267bfec06400c8552662c4))
* track file mtime in NotificationWatcher to detect overwrites (same sessionId = same filename) ([03a0336](https://github.com/terrylica/cc-skills/commit/03a0336ddc611e024e0573fef3d6309a0494d5d9))
* TTS test plays audio with karaoke subs, custom text input, hyphenated word alignment ([c511d6c](https://github.com/terrylica/cc-skills/commit/c511d6c8adaa97bb4c08bdcd233f5d04a8ccba03))
* **tts:** add explicit URLSession timeout for MiniMax API calls ([9cce899](https://github.com/terrylica/cc-skills/commit/9cce899b4c28f84d9ac16d9ac7e77862f4b75c1b))
* **tts:** add TTS circuit breaker and subtitle-only graceful degradation ([6b819fd](https://github.com/terrylica/cc-skills/commit/6b819fde486113972ed0044710b7f8671b1c6eca))
* **tts:** check prepareToPlay() and play() return values for diagnostics ([fabe92b](https://github.com/terrylica/cc-skills/commit/fabe92b26f54a48c924e5e7743f30d6c997a87cc))
* **tts:** clean up WAV files on stop() for stream and pre-buffered players ([cc4c81b](https://github.com/terrylica/cc-skills/commit/cc4c81b9ec351c573894ba038ace3235689b3b49))
* **tts:** harden MLX Metal memory management to prevent 499000 resource limit crash ([7e9519e](https://github.com/terrylica/cc-skills/commit/7e9519e1868f9d789fc480a282b2a8c110f37f4c))
* **tts:** make isStreamingInProgress thread-safe with NSLock ([f44ac41](https://github.com/terrylica/cc-skills/commit/f44ac41db5611c2013eb84a1f04fd55503a77903))
* **tts:** prevent App Nap from degrading 60Hz karaoke timer during playback ([6b934a1](https://github.com/terrylica/cc-skills/commit/6b934a1eb8f47285c68a0952eeaae16c1a8d4322))
* **tts:** retain warm-up player to prevent early ARC deallocation ([0ea16c4](https://github.com/terrylica/cc-skills/commit/0ea16c4425812c18e228ff65abc49d5ef7d60dc9))
* **tts:** validate model files at startup to fail fast on missing models ([077d5ca](https://github.com/terrylica/cc-skills/commit/077d5ca8537d87d52cce581b578fb70516bf5cf5))
* use wrappingLabelWithString for multi-line subtitle text wrapping ([4f3d901](https://github.com/terrylica/cc-skills/commit/4f3d9019a219508973c4c02d37e3eb0e516aaa5b))
* wire summarizePromptForDisplay for multi-turn prompt condensing (PROMPT-04) ([ec7ab60](https://github.com/terrylica/cc-skills/commit/ec7ab60c4541c8fd6f4a25358f7ab198ed3473f7))


### Features

* **11-01:** port legacy TypeScript formatting pipeline to TelegramFormatter.swift ([0e6129f](https://github.com/terrylica/cc-skills/commit/0e6129f2c7c3248a99cf57778dc2e61db4b1c2b8))
* **11-02:** extract all JSON metadata fields in notification handler ([671813a](https://github.com/terrylica/cc-skills/commit/671813a2f8001f96e32124556fc5ce5ce7ba9850))
* **11-02:** wire rich formatting and silent Tail Brief into TelegramBot ([96df19a](https://github.com/terrylica/cc-skills/commit/96df19a109208c7127fd84876eb22b7db2ae6ed1))
* **12-01:** add noise filtering and improved turn extraction to TranscriptParser ([971e0aa](https://github.com/terrylica/cc-skills/commit/971e0aa1fc214f81cd3e1984fc34194ed1f8f929))
* **12-02:** rewrite SummaryEngine with exact legacy prompts and add prompt condensing ([7445d64](https://github.com/terrylica/cc-skills/commit/7445d6470bf6deeacf1f687b820ea7b6a253d89b))
* **13-01:** rewrite AutoContinue with full legacy evaluation engine ([d18f99a](https://github.com/terrylica/cc-skills/commit/d18f99a5bd29043ba1e2a90fe7eca1f207ec057a))
* **13-02:** add rich decision notification formatting to AutoContinueEvaluator ([75efca2](https://github.com/terrylica/cc-skills/commit/75efca2bd53964cf99562da1d454945d33fbeb49))
* **13-02:** wire rich decision notifications into main.swift notification handler ([e03697e](https://github.com/terrylica/cc-skills/commit/e03697e369b7aab48301f0d4472f6af2d524ed66))
* **14-01:** add CJK language detection and per-outlet feature gates ([622219a](https://github.com/terrylica/cc-skills/commit/622219ae6e3c2ee9fd6d6daab0973888164f06e9))
* **14-02:** wire feature gates and language detection into TTS dispatch ([9012675](https://github.com/terrylica/cc-skills/commit/9012675be161e738796ff78716cf021dafdcac0c))
* **15-01:** add callback query handlers and inline keyboard to TelegramBot ([64de0e4](https://github.com/terrylica/cc-skills/commit/64de0e40df4decd5d50abe54b2b09d0e3c41a8b5))
* **15-01:** add InlineButtonManager with state tracking and keyboard construction ([cc858ef](https://github.com/terrylica/cc-skills/commit/cc858ef9faf998dc2bd00c94b6445ef6733a40e2))
* **16-01:** add NotificationProcessor with dedup and rate limiting ([0bc2ba1](https://github.com/terrylica/cc-skills/commit/0bc2ba1b0c842a64e7fd4b7eec116b8ef8fa31ce))
* **16-01:** wire NotificationProcessor into main.swift notification callback ([73aaa33](https://github.com/terrylica/cc-skills/commit/73aaa33ea038b807c7fcd466392a5ca632c7c30d))
* **17-01:** create SubtitleChunker with pixel-width page chunking ([92e0f56](https://github.com/terrylica/cc-skills/commit/92e0f5600d28f806f6ba6e5c966bd45707029e6b))
* **17-01:** refactor SubtitlePanel with paged karaoke and generation counter ([c25ca6f](https://github.com/terrylica/cc-skills/commit/c25ca6fc888cda304f5e14b52391af9df39f31b0))
* **17-02:** wire SubtitleChunker into dispatchTTS for paged karaoke display ([309dc66](https://github.com/terrylica/cc-skills/commit/309dc6655833dd8ed251d0fd5ffd5173052c155d))
* **260326-n1n:** add stop-ty-project-check.ts for cross-file type checking on session exit ([689b106](https://github.com/terrylica/cc-skills/commit/689b106ded2ed51d890d40ef76ff2752de6036b9))
* **260326-n1n:** upgrade ty hook with --python-version 3.13, concise output, edge case hardening ([02c70e6](https://github.com/terrylica/cc-skills/commit/02c70e609ea75ddf0f5bb24c1b68007850505050))
* **260327-d2e:** replace sherpa-onnx deps with kokoro-ios MLX in Package.swift and Config ([e6f331e](https://github.com/terrylica/cc-skills/commit/e6f331e9c19ce3ed0dc018b1bb3585d82ee2b76e))
* **260327-d2e:** rewrite TTSEngine for kokoro-ios MLX with native word timestamps ([bbe10fa](https://github.com/terrylica/cc-skills/commit/bbe10fa04d2d07ac346dcecb8fdf25a6f537c2eb))
* **quick-260327-0rt:** create SubtitleSyncDriver with 60Hz polling loop ([f0a112d](https://github.com/terrylica/cc-skills/commit/f0a112d143222f6970dd47f9db4adb1b2813c28e))
* **quick-260327-0rt:** replace afplay with AVAudioPlayer + delete audioLaunchDelay ([f39f1c7](https://github.com/terrylica/cc-skills/commit/f39f1c77a3aa1acb145c8ad80a6e9344bfd28380))
* **quick-260327-0rt:** wire SubtitleSyncDriver into dispatchTTS, remove timer scheduling ([7ec4d6a](https://github.com/terrylica/cc-skills/commit/7ec4d6a047098d02593a10767733b36d47c3f8f0))
* streaming sentence-chunked TTS synthesis pipeline ([04dab3b](https://github.com/terrylica/cc-skills/commit/04dab3bc81a8ba872212782d5f5a61c5644d3e1d))
* widen subtitle panel from 70% to 90% screen width ([1f4647c](https://github.com/terrylica/cc-skills/commit/1f4647c5060cd187003d875de2bb6743aa912b3e))





---

## Documentation Changes

## Other Documentation

### Other

- [audio-choppy-at-start](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/audio-choppy-at-start.md) - new (+54)
- [audio-choppy-silenced](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/audio-choppy-silenced.md) - new (+52)
- [audio-inter-chunk-gaps](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/audio-inter-chunk-gaps.md) - new (+42)
- [e2e-notification-pipeline-validation](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/e2e-notification-pipeline-validation.md) - new (+88)
- [intermittent-sync-drift](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/intermittent-sync-drift.md) - new (+66)
- [sentence-end-choppy-audio](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/sentence-end-choppy-audio.md) - new (+47)
- [speech-lags-behind-subs-v2](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/speech-lags-behind-subs-v2.md) - new (+51)
- [streaming-tts-early-cutoff](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/streaming-tts-early-cutoff.md) - new (+57)
- [subtitle-audio-desync](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/subtitle-audio-desync.md) - new (+61)
- [subtitle-highlight-bounceback](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/subtitle-highlight-bounceback.md) - new (+44)
- [tts-cutoff-and-subs-without-speech](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/tts-cutoff-and-subs-without-speech.md) - new (+224)
- [tts-speed-regression](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/tts-speed-regression.md) - new (+71)
- [tts-subtitle-lag](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/tts-subtitle-lag.md) - new (+47)
- [Milestones](https://github.com/terrylica/cc-skills/blob/main/.planning/MILESTONES.md) - new (+23)
- [v4.6.0 Legacy Pipeline Feature Parity — Milestone Audit](https://github.com/terrylica/cc-skills/blob/main/.planning/milestones/v4.6.0-MILESTONE-AUDIT.md) - new (+138)
- [Requirements Archive: v4.6.0 Legacy Pipeline Feature Parity](https://github.com/terrylica/cc-skills/blob/main/.planning/milestones/v4.6.0-REQUIREMENTS.md) - new (+287)
- [Roadmap: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/milestones/v4.6.0-ROADMAP.md) - new (+382)
- [11-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/11-notification-formatting/11-01-PLAN.md) - new (+326)
- [Phase 11 Plan 01: Notification Formatting Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/11-notification-formatting/11-01-SUMMARY.md) - new (+117)
- [11-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/11-notification-formatting/11-02-PLAN.md) - new (+357)
- [Phase 11 Plan 02: Notification Wiring Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/11-notification-formatting/11-02-SUMMARY.md) - new (+113)
- [Phase 11: Notification Formatting — Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/11-notification-formatting/11-CONTEXT.md) - new (+74)
- [12-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/12-ai-summary-prompts/12-01-PLAN.md) - new (+209)
- [Phase 12 Plan 01: Noise Filtering & Turn Extraction Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/12-ai-summary-prompts/12-01-SUMMARY.md) - new (+97)
- [12-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/12-ai-summary-prompts/12-02-PLAN.md) - new (+336)
- [Phase 12 Plan 02: Legacy Prompt Templates & Prompt Condensing Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/12-ai-summary-prompts/12-02-SUMMARY.md) - new (+100)
- [Phase 12: AI Summary Prompts — Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/12-ai-summary-prompts/12-CONTEXT.md) - new (+55)
- [Verify SYSTEM_PROMPT is verbatim](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/13-auto-continue-evaluation/13-01-PLAN.md) - new (+368)
- [Phase 13 Plan 01: Auto-Continue Evaluation Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/13-auto-continue-evaluation/13-01-SUMMARY.md) - new (+107)
- [Verify rich notification format](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/13-auto-continue-evaluation/13-02-PLAN.md) - new (+232)
- [Phase 13 Plan 02: Rich Decision Notifications Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/13-auto-continue-evaluation/13-02-SUMMARY.md) - new (+129)
- [Phase 13: Auto-Continue Evaluation — Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/13-auto-continue-evaluation/13-CONTEXT.md) - new (+37)
- [14-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/14-tts-dispatch--feature-gates/14-01-PLAN.md) - new (+179)
- [Phase 14 Plan 01: LanguageDetector + FeatureGates Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/14-tts-dispatch--feature-gates/14-01-SUMMARY.md) - new (+100)
- [14-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/14-tts-dispatch--feature-gates/14-02-PLAN.md) - new (+249)
- [Phase 14 Plan 02: TTS Dispatch Wiring Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/14-tts-dispatch--feature-gates/14-02-SUMMARY.md) - new (+95)
- [Phase 14: TTS Dispatch & Feature Gates — Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/14-tts-dispatch--feature-gates/14-CONTEXT.md) - new (+37)
- [15-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/15-telegram-inline-buttons/15-01-PLAN.md) - new (+348)
- [Phase 15 Plan 01: Inline Button Infrastructure Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/15-telegram-inline-buttons/15-01-SUMMARY.md) - new (+148)
- [15-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/15-telegram-inline-buttons/15-02-PLAN.md) - new (+173)
- [Phase 15 Plan 02: Notification Flow Wiring Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/15-telegram-inline-buttons/15-02-SUMMARY.md) - new (+105)
- [Phase 15: Telegram Inline Buttons — Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/15-telegram-inline-buttons/15-CONTEXT.md) - new (+37)
- [16-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/16-integration--reliability/16-01-PLAN.md) - new (+259)
- [Phase 16 Plan 01: Integration Reliability Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/16-integration--reliability/16-01-SUMMARY.md) - new (+102)
- [Phase 16: Integration & Reliability — Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/16-integration--reliability/16-CONTEXT.md) - new (+37)
- [17-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/17-tts-streaming-subtitle-chunking/17-01-PLAN.md) - new (+359)
- [Phase 17 Plan 01: Subtitle Chunker and Paged Karaoke Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/17-tts-streaming-subtitle-chunking/17-01-SUMMARY.md) - new (+104)
- [17-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/17-tts-streaming-subtitle-chunking/17-02-PLAN.md) - new (+234)
- [Phase 17 Plan 02: Wire SubtitleChunker into TTS Dispatch Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/17-tts-streaming-subtitle-chunking/17-02-SUMMARY.md) - new (+98)
- [Phase 17: TTS Streaming & Subtitle Chunking - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/17-tts-streaming-subtitle-chunking/17-CONTEXT.md) - new (+93)
- [Phase 17: TTS Streaming & Subtitle Chunking - Research](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/17-tts-streaming-subtitle-chunking/17-RESEARCH.md) - new (+409)
- [Phase 17 — Validation Strategy](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/17-tts-streaming-subtitle-chunking/17-VALIDATION.md) - new (+74)
- [Phase 17: TTS Streaming & Subtitle Chunking Verification Report](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/17-tts-streaming-subtitle-chunking/17-VERIFICATION.md) - new (+161)
- [260326-n1n-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/quick/260326-n1n-upgrade-ty-hook-python-version-concise-o/260326-n1n-PLAN.md) - new (+243)
- [Quick Task 260326-n1n: Upgrade ty Hook Suite Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/quick/260326-n1n-upgrade-ty-hook-python-version-concise-o/260326-n1n-SUMMARY.md) - new (+102)
- [260327-0rt-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/quick/260327-0rt-replace-afplay-with-avaudioplayer-plus-c/260327-0rt-PLAN.md) - new (+295)
- [Replace sherpa-onnx with MLX Metal GPU - Research](https://github.com/terrylica/cc-skills/blob/main/.planning/quick/260327-c6s-replace-sherpa-onnx-with-mlx-metal-gpu-f/260327-c6s-RESEARCH.md) - new (+346)
- [Spike Report: kokoro-ios (MLX Swift Kokoro TTS) on M3 Max](https://github.com/terrylica/cc-skills/blob/main/.planning/quick/260327-c6s-replace-sherpa-onnx-with-mlx-metal-gpu-f/SPIKE-kokoro-ios.md) - new (+174)
- [260327-d2e-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/quick/260327-d2e-replace-sherpa-onnx-with-kokoro-ios-mlx-/260327-d2e-PLAN.md) - new (+334)
- [Quick Task 260327-d2e: Replace sherpa-onnx with kokoro-ios MLX Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/quick/260327-d2e-replace-sherpa-onnx-with-kokoro-ios-mlx-/260327-d2e-SUMMARY.md) - new (+128)
- [Requirements: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/REQUIREMENTS.md) - updated (+64/-58)
- [Roadmap: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/ROADMAP.md) - updated (+74/-26)
- [Project State](https://github.com/terrylica/cc-skills/blob/main/.planning/STATE.md) - updated (+54/-20)
- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+43/-16)

# [12.18.0](https://github.com/terrylica/cc-skills/compare/v12.17.0...v12.18.0) (2026-03-26)


### Bug Fixes

* **03:** use Kokoro v1.0 af_heart voice + fix struct layout crash ([316bfe6](https://github.com/terrylica/cc-skills/commit/316bfe664026896bc831d17fab8b32e64fc2ec2e))
* **06:** restore missing Config constants after merge conflict ([5338b5e](https://github.com/terrylica/cc-skills/commit/5338b5ec26abe9604109aa12302e20b4830b520c))
* add read delay for notification file parsing race condition ([0981e3c](https://github.com/terrylica/cc-skills/commit/0981e3c8670cd5a28506f0492bf9694295f14cd9))
* correct MiniMax API endpoint and model name ([2df6250](https://github.com/terrylica/cc-skills/commit/2df62502b0a13c172206f41f2daa0533bad4c092))
* default isWatching=true so bot sends notifications without /start ([af765cb](https://github.com/terrylica/cc-skills/commit/af765cb5872d724fe40987b181adf6edbe0bb47e))
* handle MiniMax thinking model response + increase token budget ([0fc98cf](https://github.com/terrylica/cc-skills/commit/0fc98cfef6304a882e8005152c1c4e8ebaa14781))
* replace subtitle-only demo with TTS+karaoke demo in dev mode ([18ddbb5](https://github.com/terrylica/cc-skills/commit/18ddbb5d9bf666cc493c4ee3eae3ead4679aa91a))
* switch to full precision Kokoro model for better voice quality ([c7b3a87](https://github.com/terrylica/cc-skills/commit/c7b3a87d9cad999df772c3bda1810024eef8f4c6))


### Features

* **03-01:** create TTSEngine.swift with sherpa-onnx C API wrapper ([c0ddd5b](https://github.com/terrylica/cc-skills/commit/c0ddd5b6e4fced7f717edba6477e8f98356b90ee))
* **03-01:** patch sherpa-onnx for duration tensor + rebuild static libs ([ab057a2](https://github.com/terrylica/cc-skills/commit/ab057a2cd6b1026bb543590248ebe1e1509ffce3))
* **03-02:** add word timestamp extraction and synthesizeWithTimestamps to TTSEngine ([febf289](https://github.com/terrylica/cc-skills/commit/febf289197cab48155a6e273c765e88753664b93))
* **03-02:** wire TTSEngine into main.swift, replace demo with real TTS karaoke ([4874e7e](https://github.com/terrylica/cc-skills/commit/4874e7edd2c3b3a24264f998bd393d50e03dfba8))
* **04-01:** add MiniMax config constants and CircuitBreaker ([ee1ce77](https://github.com/terrylica/cc-skills/commit/ee1ce7737163d0c10dd893673aa536647a6b77a7))
* **04-01:** create MiniMaxClient with URLSession API calls ([58d71d0](https://github.com/terrylica/cc-skills/commit/58d71d0dae7e583cafc5974f9b4657b77ad49d30))
* **04-02:** add arcSummary and tailBrief methods to SummaryEngine ([c47a25a](https://github.com/terrylica/cc-skills/commit/c47a25abafec94fb4533a98d36ad57261c2046e9))
* **04-02:** create SummaryEngine with data types and single-turn summary ([51c0118](https://github.com/terrylica/cc-skills/commit/51c011859941666ac4014772441a96f7b2a8bced))
* **05-01:** add TelegramBot actor with long polling and 7 command handlers ([533f8e4](https://github.com/terrylica/cc-skills/commit/533f8e49323669f4406c22793eb8efa77a6a8785))
* **05-01:** add TelegramFormatter with HTML escaping, fence-aware chunking, and markdown-to-HTML conversion ([e413c6a](https://github.com/terrylica/cc-skills/commit/e413c6ad7176005e1ba551176fee6c063c59e683))
* **05-02:** add session notification + TTS dispatch to TelegramBot ([1d23994](https://github.com/terrylica/cc-skills/commit/1d2399495ec058bb609d9822ec78804b27188b2a))
* **05-02:** wire TelegramBot into main.swift with all subsystem refs ([4731ce4](https://github.com/terrylica/cc-skills/commit/4731ce4791de70a41cb8d39271f849c2370ff95d))
* **06-01:** add Claude CLI subprocess with model selection and NDJSON parsing ([d7d047d](https://github.com/terrylica/cc-skills/commit/d7d047dd6557b7d28e8d5c12981431e77ebad0f8))
* **06-01:** add JSONL transcript parser for Claude Code sessions ([492b38b](https://github.com/terrylica/cc-skills/commit/492b38bfb903aa9e422405b1a20eb385b355b5d3))
* **06-02:** add PromptExecutor with model flags, streaming edit-in-place, circuit breaker ([1b74b2e](https://github.com/terrylica/cc-skills/commit/1b74b2eff0d436f43f7b297655b9853d9a8fb39b))
* **06-02:** wire /prompt command into TelegramBot with edit-in-place and /done cancel ([d8ced0e](https://github.com/terrylica/cc-skills/commit/d8ced0e2699f753a4189313e2b6a38b7c26e60d8))
* **07-01:** add file watching directory paths to Config.swift ([85a308a](https://github.com/terrylica/cc-skills/commit/85a308ac44a9855b0cbbea4c56a3d4b119028cd8))
* **07-01:** create FileWatcher.swift with NotificationWatcher and JSONLTailer ([7e46c66](https://github.com/terrylica/cc-skills/commit/7e46c66f9d1eb9ef433bf06014cb9eeded2fdf70))
* **07-02:** create AutoContinueEvaluator with MiniMax evaluation and plan discovery ([31e66ab](https://github.com/terrylica/cc-skills/commit/31e66ab2f6c161703daaa911c674b76ebc06d451))
* **07-02:** wire NotificationWatcher and AutoContinueEvaluator into main.swift ([b4ffab2](https://github.com/terrylica/cc-skills/commit/b4ffab21f3061d4c4b818e151629ab2ec75c1cee))
* **08-01:** add FlyingFox dependency and SettingsStore with disk persistence ([3eb18c9](https://github.com/terrylica/cc-skills/commit/3eb18c9a6ebcde35c159066bd4ace6b89847bbfc))
* **08-01:** create HTTPControlServer with all 6 API endpoints ([f595867](https://github.com/terrylica/cc-skills/commit/f59586788c4d9ce14d0c90387b73fb2813b60997))
* **08-02:** wire HTTPControlServer into main.swift lifecycle ([964081f](https://github.com/terrylica/cc-skills/commit/964081ffb7ef80a5efab3cec371434c26be0891f))
* **10-01:** add install and rollback deployment scripts ([0430086](https://github.com/terrylica/cc-skills/commit/043008602244ab20f4868ba861b8e2dcce7983f7))
* **10-01:** add launchd plist and update Config.swift model path ([cc713a5](https://github.com/terrylica/cc-skills/commit/cc713a5b69821ae442ec1a22ea73292b666548f0))
* **10-02:** add CaptionHistory ring buffer for subtitle scrollback and clipboard copy ([ae9ff50](https://github.com/terrylica/cc-skills/commit/ae9ff50f569e6098b048ed741732627ab9791d7d))
* **10-02:** add ThinkingWatcher for extended thinking JSONL monitoring and MiniMax summarization ([27cf09d](https://github.com/terrylica/cc-skills/commit/27cf09d0e8a5949b68b429122ed37ca768d71edc))
* **10-02:** wire CaptionHistory and ThinkingWatcher into HTTP server and main.swift ([226d1f9](https://github.com/terrylica/cc-skills/commit/226d1f913e4def8ed18a44eeb056dee981be77ea))
* **gh-tools:** add gh-issue-no-anchors hook to block anchor links in issues ([78b2c16](https://github.com/terrylica/cc-skills/commit/78b2c166508085156e51ddef74eade473338c010)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools) [#issue-no-anchors](https://github.com/terrylica/cc-skills/issues/issue-no-anchors) [#anchor](https://github.com/terrylica/cc-skills/issues/anchor) [#123](https://github.com/terrylica/cc-skills/issues/123)





---

## Documentation Changes

## Other Documentation

### Other

- [minimax-tts-telegram-fallback](https://github.com/terrylica/cc-skills/blob/main/.planning/debug/minimax-tts-telegram-fallback.md) - new (+79)
- [Phase 2: Subtitle Overlay Verification Report](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/02-subtitle-overlay/02-VERIFICATION.md) - new (+152)
- [03-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/03-tts-engine/03-01-PLAN.md) - new (+403)
- [Phase 03 Plan 01: TTS Engine Core Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/03-tts-engine/03-01-SUMMARY.md) - new (+117)
- [03-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/03-tts-engine/03-02-PLAN.md) - new (+376)
- [Phase 03: TTS Engine — Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/03-tts-engine/03-CONTEXT.md) - new (+76)
- [Phase 03: TTS Engine Verification Report](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/03-tts-engine/03-VERIFICATION.md) - new (+163)
- [04-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/04-ai-summaries/04-01-PLAN.md) - new (+248)
- [Phase 04 Plan 01: MiniMax API Client & Circuit Breaker Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/04-ai-summaries/04-01-SUMMARY.md) - new (+122)
- [04-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/04-ai-summaries/04-02-PLAN.md) - new (+346)
- [Phase 04 Plan 02: Summary Prompt Templates Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/04-ai-summaries/04-02-SUMMARY.md) - new (+115)
- [Phase 04: AI Summaries — Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/04-ai-summaries/04-CONTEXT.md) - new (+72)
- [05-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/05-telegram-bot-core/05-01-PLAN.md) - new (+355)
- [Phase 05 Plan 01: Telegram Bot Core Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/05-telegram-bot-core/05-01-SUMMARY.md) - new (+130)
- [05-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/05-telegram-bot-core/05-02-PLAN.md) - new (+394)
- [Phase 05 Plan 02: Bot Notification Wiring Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/05-telegram-bot-core/05-02-SUMMARY.md) - new (+134)
- [Phase 05: Telegram Bot Core — Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/05-telegram-bot-core/05-CONTEXT.md) - new (+78)
- [Phase 6 Plan 1: CLI Subprocess + JSONL Parser + Model Selection](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/06-telegram-bot-commands/06-01-PLAN.md) - new (+81)
- [Phase 6 Plan 1: CLI Subprocess + JSONL Parser + Model Selection Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/06-telegram-bot-commands/06-01-SUMMARY.md) - new (+74)
- [Must show "Build complete!" with no errors](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/06-telegram-bot-commands/06-02-PLAN.md) - new (+332)
- [Phase 6 Plan 2: Prompt Executor + /prompt Command Wiring Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/06-telegram-bot-commands/06-02-SUMMARY.md) - new (+122)
- [Phase 06: Telegram Bot Commands — Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/06-telegram-bot-commands/06-CONTEXT.md) - new (+63)
- [07-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/07-file-watching-auto-continue/07-01-PLAN.md) - new (+224)
- [Phase 07 Plan 01: File Watching Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/07-file-watching-auto-continue/07-01-SUMMARY.md) - new (+108)
- [07-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/07-file-watching-auto-continue/07-02-PLAN.md) - new (+391)
- [Phase 07 Plan 02: Auto-Continue Evaluator Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/07-file-watching-auto-continue/07-02-SUMMARY.md) - new (+113)
- [Phase 07: File Watching & Auto-Continue — Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/07-file-watching-auto-continue/07-CONTEXT.md) - new (+66)
- [08-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/08-http-control-api/08-01-PLAN.md) - new (+292)
- [Phase 08 Plan 01: HTTP Control API Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/08-http-control-api/08-01-SUMMARY.md) - new (+115)
- [08-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/08-http-control-api/08-02-PLAN.md) - new (+197)
- [Phase 08 Plan 02: HTTP Control API Lifecycle Wiring Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/08-http-control-api/08-02-SUMMARY.md) - new (+119)
- [Phase 08: HTTP Control API — Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/08-http-control-api/08-CONTEXT.md) - new (+65)
- [09-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/09-swiftbar-integration/09-01-PLAN.md) - new (+270)
- [Phase 09 Plan 01: SwiftBar Plugin v3.0.0 Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/09-swiftbar-integration/09-01-SUMMARY.md) - new (+106)
- [For karaokeEnabled toggle](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/09-swiftbar-integration/09-02-PLAN.md) - new (+193)
- [Phase 09 Plan 02: SwiftBar Action Script v3.0.0 Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/09-swiftbar-integration/09-02-SUMMARY.md) - new (+115)
- [Phase 09: SwiftBar Integration — Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/09-swiftbar-integration/09-CONTEXT.md) - new (+59)
- [10-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/10-deployment-extras/10-01-PLAN.md) - new (+239)
- [Phase 10 Plan 01: Deployment Scripts Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/10-deployment-extras/10-01-SUMMARY.md) - new (+112)
- [10-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/10-deployment-extras/10-02-PLAN.md) - new (+260)
- [Phase 10 Plan 02: Caption History, Clipboard Copy, and Thinking Watcher Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/10-deployment-extras/10-02-SUMMARY.md) - new (+136)
- [Phase 10: Deployment & Extras — Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/10-deployment-extras/10-CONTEXT.md) - new (+61)
- [claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/PROJECT.md) - updated (+15)
- [260326-fvh-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/quick/260326-fvh-deploy-tts-companion/260326-fvh-PLAN.md) - new (+129)
- [Quick Task 260326-fvh: Deploy claude-tts-companion Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/quick/260326-fvh-deploy-tts-companion/260326-fvh-SUMMARY.md) - new (+124)
- [Requirements: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/REQUIREMENTS.md) - updated (+166/-88)
- [Roadmap: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/ROADMAP.md) - updated (+152/-52)
- [Project State](https://github.com/terrylica/cc-skills/blob/main/.planning/STATE.md) - updated (+42/-42)
- [Architectural Convergence in AI Engineering: The Case for Standardized Agent Skills Over Bespoke Scaffolding](https://github.com/terrylica/cc-skills/blob/main/docs/research/gemini-custom-vs-standard-ai-harness.md) - new (+278)
- [Structuring a Hybrid GitHub Repository as a Claude Code Plugin Marketplace: Architectural Analysis and Implementation Patterns](https://github.com/terrylica/cc-skills/blob/main/docs/research/gemini-marketplace-skills-architecture.md) - new (+316)
- [The Autonomous Metacognitive Layer: Self-Evolving Agent Skills and the Protocol of Continuous Adaptation](https://github.com/terrylica/cc-skills/blob/main/docs/research/gemini-self-evolving-skills.md) - new (+320)
- [Encoding Operational Empiricism: The Strategic Imperative for Agent Skills in Enterprise AI Software Engineering](https://github.com/terrylica/cc-skills/blob/main/docs/research/gemini-skill-worthy-knowledge-taxonomy.md) - new (+220)
- [为什么我们应该用 Agent Skills 来共享工程知识](https://github.com/terrylica/cc-skills/blob/main/docs/research/skills-as-knowledge-justification.md) - updated (+368/-188)

# [12.17.0](https://github.com/terrylica/cc-skills/compare/v12.16.0...v12.17.0) (2026-03-26)


### Features

* **01-01:** create CSherpaOnnx C module target with vendored headers ([292e1d2](https://github.com/terrylica/cc-skills/commit/292e1d2d8dc70ef27a95b4b9e7a5f86701567311))
* **01-01:** create Package.swift and Config.swift ([de58561](https://github.com/terrylica/cc-skills/commit/de58561176ae87c6874ead4d3a27cf6ea3ebddfb))
* **01-02:** create main.swift entry point with NSApp accessory + SIGTERM + C interop ([5bc1bd4](https://github.com/terrylica/cc-skills/commit/5bc1bd4a80e264b1fc3487142c01d1453bbf4f33))
* **02-01:** create SubtitlePanel.swift with floating overlay panel ([e16bdc9](https://github.com/terrylica/cc-skills/commit/e16bdc98d85210f4507998fc8bdee803af0b4922))
* **02-01:** create SubtitleStyle.swift with visual constants ([e91d0a7](https://github.com/terrylica/cc-skills/commit/e91d0a71ed91d920494fdb4541f7193c5d8bacc4))
* **02-02:** add karaoke highlighting engine and demo mode to SubtitlePanel ([bdeba49](https://github.com/terrylica/cc-skills/commit/bdeba49824018a2bfec2be552ab56015be0c63e0))
* **02-02:** wire SubtitlePanel into main.swift with demo on startup ([9c50388](https://github.com/terrylica/cc-skills/commit/9c503883a37d26f890f986c8a03ad432402cabd0))





---

## Documentation Changes

## Repository Documentation

### Root Documentation

- [[12.17.0](https://github.com/terrylica/cc-skills/compare/v12.16.0...v12.17.0) (2026-03-26)](https://github.com/terrylica/cc-skills/blob/main/CHANGELOG.md) - updated (+55)
- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+138)

## Other Documentation

### Other

- [01-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/01-foundation-build-system/01-01-PLAN.md) - new (+261)
- [Phase 01 Plan 01: Foundation Build System Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/01-foundation-build-system/01-01-SUMMARY.md) - new (+149)
- [01-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/01-foundation-build-system/01-02-PLAN.md) - new (+263)
- [Phase 01 Plan 02: Entry Point & Build Verification Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/01-foundation-build-system/01-02-SUMMARY.md) - new (+150)
- [Phase 1: Foundation & Build System - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/01-foundation-build-system/01-CONTEXT.md) - new (+64)
- [Phase 1: Foundation & Build System - Research](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/01-foundation-build-system/01-RESEARCH.md) - new (+457)
- [Phase 01: Foundation & Build System Verification Report](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/01-foundation-build-system/01-VERIFICATION.md) - new (+132)
- [02-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/02-subtitle-overlay/02-01-PLAN.md) - new (+233)
- [Phase 02 Plan 01: Subtitle Panel Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/02-subtitle-overlay/02-01-SUMMARY.md) - new (+129)
- [02-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/02-subtitle-overlay/02-02-PLAN.md) - new (+274)
- [Phase 02 Plan 02: Karaoke Demo Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/02-subtitle-overlay/02-02-SUMMARY.md) - new (+120)
- [Phase 02: Subtitle Overlay — Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/02-subtitle-overlay/02-CONTEXT.md) - new (+57)
- [claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/PROJECT.md) - new (+113)
- [Requirements: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/REQUIREMENTS.md) - new (+194)
- [Architecture Patterns](https://github.com/terrylica/cc-skills/blob/main/.planning/research/ARCHITECTURE.md) - new (+361)
- [Feature Landscape](https://github.com/terrylica/cc-skills/blob/main/.planning/research/FEATURES.md) - new (+118)
- [Domain Pitfalls](https://github.com/terrylica/cc-skills/blob/main/.planning/research/PITFALLS.md) - new (+365)
- [Technology Stack](https://github.com/terrylica/cc-skills/blob/main/.planning/research/STACK.md) - new (+199)
- [Project Research Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/research/SUMMARY.md) - new (+196)
- [Roadmap: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/ROADMAP.md) - new (+234)
- [Project State](https://github.com/terrylica/cc-skills/blob/main/.planning/STATE.md) - new (+92)
- [为什么我们应该用 Agent Skills 来共享工程知识](https://github.com/terrylica/cc-skills/blob/main/docs/research/skills-as-knowledge-justification.md) - new (+355)
- [claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/CLAUDE.md) - new (+39)

# [12.17.0](https://github.com/terrylica/cc-skills/compare/v12.16.0...v12.17.0) (2026-03-26)


### Features

* **01-01:** create CSherpaOnnx C module target with vendored headers ([292e1d2](https://github.com/terrylica/cc-skills/commit/292e1d2d8dc70ef27a95b4b9e7a5f86701567311))
* **01-01:** create Package.swift and Config.swift ([de58561](https://github.com/terrylica/cc-skills/commit/de58561176ae87c6874ead4d3a27cf6ea3ebddfb))
* **01-02:** create main.swift entry point with NSApp accessory + SIGTERM + C interop ([5bc1bd4](https://github.com/terrylica/cc-skills/commit/5bc1bd4a80e264b1fc3487142c01d1453bbf4f33))
* **02-01:** create SubtitlePanel.swift with floating overlay panel ([e16bdc9](https://github.com/terrylica/cc-skills/commit/e16bdc98d85210f4507998fc8bdee803af0b4922))
* **02-01:** create SubtitleStyle.swift with visual constants ([e91d0a7](https://github.com/terrylica/cc-skills/commit/e91d0a71ed91d920494fdb4541f7193c5d8bacc4))
* **02-02:** add karaoke highlighting engine and demo mode to SubtitlePanel ([bdeba49](https://github.com/terrylica/cc-skills/commit/bdeba49824018a2bfec2be552ab56015be0c63e0))
* **02-02:** wire SubtitlePanel into main.swift with demo on startup ([9c50388](https://github.com/terrylica/cc-skills/commit/9c503883a37d26f890f986c8a03ad432402cabd0))





---

## Documentation Changes

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+138)

## Other Documentation

### Other

- [01-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/01-foundation-build-system/01-01-PLAN.md) - new (+261)
- [Phase 01 Plan 01: Foundation Build System Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/01-foundation-build-system/01-01-SUMMARY.md) - new (+149)
- [01-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/01-foundation-build-system/01-02-PLAN.md) - new (+263)
- [Phase 01 Plan 02: Entry Point & Build Verification Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/01-foundation-build-system/01-02-SUMMARY.md) - new (+150)
- [Phase 1: Foundation & Build System - Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/01-foundation-build-system/01-CONTEXT.md) - new (+64)
- [Phase 1: Foundation & Build System - Research](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/01-foundation-build-system/01-RESEARCH.md) - new (+457)
- [Phase 01: Foundation & Build System Verification Report](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/01-foundation-build-system/01-VERIFICATION.md) - new (+132)
- [02-01-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/02-subtitle-overlay/02-01-PLAN.md) - new (+233)
- [Phase 02 Plan 01: Subtitle Panel Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/02-subtitle-overlay/02-01-SUMMARY.md) - new (+129)
- [02-02-PLAN](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/02-subtitle-overlay/02-02-PLAN.md) - new (+274)
- [Phase 02 Plan 02: Karaoke Demo Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/02-subtitle-overlay/02-02-SUMMARY.md) - new (+120)
- [Phase 02: Subtitle Overlay — Context](https://github.com/terrylica/cc-skills/blob/main/.planning/phases/02-subtitle-overlay/02-CONTEXT.md) - new (+57)
- [claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/PROJECT.md) - new (+113)
- [Requirements: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/REQUIREMENTS.md) - new (+194)
- [Architecture Patterns](https://github.com/terrylica/cc-skills/blob/main/.planning/research/ARCHITECTURE.md) - new (+361)
- [Feature Landscape](https://github.com/terrylica/cc-skills/blob/main/.planning/research/FEATURES.md) - new (+118)
- [Domain Pitfalls](https://github.com/terrylica/cc-skills/blob/main/.planning/research/PITFALLS.md) - new (+365)
- [Technology Stack](https://github.com/terrylica/cc-skills/blob/main/.planning/research/STACK.md) - new (+199)
- [Project Research Summary](https://github.com/terrylica/cc-skills/blob/main/.planning/research/SUMMARY.md) - new (+196)
- [Roadmap: claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/.planning/ROADMAP.md) - new (+234)
- [Project State](https://github.com/terrylica/cc-skills/blob/main/.planning/STATE.md) - new (+92)
- [为什么我们应该用 Agent Skills 来共享工程知识](https://github.com/terrylica/cc-skills/blob/main/docs/research/skills-as-knowledge-justification.md) - new (+355)
- [claude-tts-companion](https://github.com/terrylica/cc-skills/blob/main/plugins/claude-tts-companion/CLAUDE.md) - new (+39)

# [12.16.0](https://github.com/terrylica/cc-skills/compare/v12.15.0...v12.16.0) (2026-03-24)


### Bug Fixes

* **mql5:** align headless-mt5-remote with skill-architecture standards ([98ca174](https://github.com/terrylica/cc-skills/commit/98ca17459380c23d3fc34f802c43d1aeeec03dfa))


### Features

* **mql5:** add headless-mt5-remote skill ([2c57939](https://github.com/terrylica/cc-skills/commit/2c57939fe4c785ee227c94f8f1dc4bd70768566e))
* **mql5:** add mql5-ship skill — deploy EA+DLL from macOS to bigblack ([f311028](https://github.com/terrylica/cc-skills/commit/f311028743fb8895a138c9058887627f96e28a7f))





---

## Documentation Changes

## Other Documentation

### Other

- [tts-tg-sync Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/CLAUDE.md) - updated (+8)

# [12.15.0](https://github.com/terrylica/cc-skills/compare/v12.14.0...v12.15.0) (2026-03-24)


### Bug Fixes

* **clickhouse-architect:** add mutations_sync + lightweight DELETE hazard warning ([#295](https://github.com/terrylica/cc-skills/issues/295) lessons) ([19f523a](https://github.com/terrylica/cc-skills/commit/19f523a8cb474d346337593ff16645b51621b24f))
* **clickhouse-architect:** nuance daily vs monthly partitioning guidance ([31eb893](https://github.com/terrylica/cc-skills/commit/31eb893caa80189be3d818df95b713afc6b594c2)), closes [#6](https://github.com/terrylica/cc-skills/issues/6)


### Features

* **clickhouse-architect:** encode partition + write optimization best practices ([e2e20ea](https://github.com/terrylica/cc-skills/commit/e2e20eabcec3e77cde350952946ca89122dcabf8)), closes [#6](https://github.com/terrylica/cc-skills/issues/6)
* **devops-tools:** add python-memory-safe-scripts skill ([7ff918d](https://github.com/terrylica/cc-skills/commit/7ff918d20b716554b3b8dd1f2c5eba6d36f31c72))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [python-memory-safe-scripts](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/python-memory-safe-scripts/SKILL.md) - new (+246)

</details>

<details>
<summary><strong>quality-tools</strong> (1 change)</summary>

- [clickhouse-architect](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/clickhouse-architect/SKILL.md) - updated (+35/-9)

</details>


### Skill References

<details>
<summary><strong>quality-tools/clickhouse-architect</strong> (4 files)</summary>

- [Anti-Patterns and Fixes](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/clickhouse-architect/references/anti-patterns-and-fixes.md) - updated (+105/-22)
- [Audit and Diagnostics](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/clickhouse-architect/references/audit-and-diagnostics.md) - updated (+61)
- [Cache Schema Evolution](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/clickhouse-architect/references/cache-schema-evolution.md) - updated (+3/-1)
- [Schema Design Workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/clickhouse-architect/references/schema-design-workflow.md) - updated (+32)

</details>

# [12.14.0](https://github.com/terrylica/cc-skills/compare/v12.13.2...v12.14.0) (2026-03-22)


### Bug Fixes

* **gemini-deep-research:** update profile path from openclaw to local share ([7c43802](https://github.com/terrylica/cc-skills/commit/7c4380275bfaf7b6135a8ebed97d9a631dfe6323))


### Features

* **statusline:** add conditional UTC/local date display based on timezone drift ([6ef938e](https://github.com/terrylica/cc-skills/commit/6ef938e19ca03f163bbf866f03f6d6c801c3a904))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>mise</strong> (1 change)</summary>

- [run-full-release](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/run-full-release/SKILL.md) - updated (+1/-1)

</details>


## Repository Documentation

### General Documentation

- [Cross-Link Validation Report](https://github.com/terrylica/cc-skills/blob/main/docs/cross-link-validation-report.md) - updated (+37/-38)

## Other Documentation

### Other

- [gemini-deep-research Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gemini-deep-research/CLAUDE.md) - updated (-3)

## [12.13.2](https://github.com/terrylica/cc-skills/compare/v12.13.1...v12.13.2) (2026-03-21)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>tts-tg-sync</strong> (10 changes)</summary>

- [bot-process-control](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/bot-process-control/SKILL.md) - renamed from `plugins/tts-telegram-sync/skills/bot-process-control/SKILL.md`
- [clean-component-removal](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/clean-component-removal/SKILL.md) - renamed from `plugins/tts-telegram-sync/skills/clean-component-removal/SKILL.md`
- [component-version-upgrade](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/component-version-upgrade/SKILL.md) - renamed from `plugins/tts-telegram-sync/skills/component-version-upgrade/SKILL.md`
- [diagnostic-issue-resolver](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/diagnostic-issue-resolver/SKILL.md) - renamed from `plugins/tts-telegram-sync/skills/diagnostic-issue-resolver/SKILL.md`
- [full-stack-bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/full-stack-bootstrap/SKILL.md) - renamed from `plugins/tts-telegram-sync/skills/full-stack-bootstrap/SKILL.md`
- [health](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/health/SKILL.md) - renamed from `plugins/tts-telegram-sync/skills/health/SKILL.md`
- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/hooks/SKILL.md) - renamed from `plugins/tts-telegram-sync/skills/hooks/SKILL.md`
- [settings-and-tuning](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/settings-and-tuning/SKILL.md) - renamed from `plugins/tts-telegram-sync/skills/settings-and-tuning/SKILL.md`
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/setup/SKILL.md) - renamed from `plugins/tts-telegram-sync/skills/setup/SKILL.md`
- [voice-quality-audition](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/voice-quality-audition/SKILL.md) - renamed from `plugins/tts-telegram-sync/skills/voice-quality-audition/SKILL.md`

</details>


### Plugin READMEs

- [TTS Telegram Sync](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/README.md) - renamed from `plugins/tts-telegram-sync/README.md`

### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+2/-2)

</details>

<details>
<summary><strong>plugin-dev/skill-architecture</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/evolution-log.md) - updated (+2/-2)

</details>

<details>
<summary><strong>tts-tg-sync/bot-process-control</strong> (3 files)</summary>

- [bot-process-control Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/bot-process-control/references/evolution-log.md) - renamed from `plugins/tts-telegram-sync/skills/bot-process-control/references/evolution-log.md`
- [Operational Commands](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/bot-process-control/references/operational-commands.md) - renamed from `plugins/tts-telegram-sync/skills/bot-process-control/references/operational-commands.md`
- [Process Tree](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/bot-process-control/references/process-tree.md) - renamed from `plugins/tts-telegram-sync/skills/bot-process-control/references/process-tree.md`

</details>

<details>
<summary><strong>tts-tg-sync/clean-component-removal</strong> (1 file)</summary>

- [clean-component-removal Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/clean-component-removal/references/evolution-log.md) - renamed from `plugins/tts-telegram-sync/skills/clean-component-removal/references/evolution-log.md`

</details>

<details>
<summary><strong>tts-tg-sync/component-version-upgrade</strong> (2 files)</summary>

- [component-version-upgrade Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/component-version-upgrade/references/evolution-log.md) - renamed from `plugins/tts-telegram-sync/skills/component-version-upgrade/references/evolution-log.md`
- [Upgrade Procedures](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/component-version-upgrade/references/upgrade-procedures.md) - renamed from `plugins/tts-telegram-sync/skills/component-version-upgrade/references/upgrade-procedures.md`

</details>

<details>
<summary><strong>tts-tg-sync/diagnostic-issue-resolver</strong> (3 files)</summary>

- [Common Issues -- Expanded Diagnostic Procedures](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/diagnostic-issue-resolver/references/common-issues.md) - renamed from `plugins/tts-telegram-sync/skills/diagnostic-issue-resolver/references/common-issues.md`
- [diagnostic-issue-resolver Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/diagnostic-issue-resolver/references/evolution-log.md) - renamed from `plugins/tts-telegram-sync/skills/diagnostic-issue-resolver/references/evolution-log.md`
- [Lock Debugging -- Two-Layer Lock Mechanism](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/diagnostic-issue-resolver/references/lock-debugging.md) - renamed from `plugins/tts-telegram-sync/skills/diagnostic-issue-resolver/references/lock-debugging.md`

</details>

<details>
<summary><strong>tts-tg-sync/full-stack-bootstrap</strong> (4 files)</summary>

- [BotFather Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/full-stack-bootstrap/references/botfather-guide.md) - renamed from `plugins/tts-telegram-sync/skills/full-stack-bootstrap/references/botfather-guide.md`
- [full-stack-bootstrap Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/full-stack-bootstrap/references/evolution-log.md) - renamed from `plugins/tts-telegram-sync/skills/full-stack-bootstrap/references/evolution-log.md`
- [Kokoro TTS Engine Bootstrap Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/full-stack-bootstrap/references/kokoro-bootstrap.md) - renamed from `plugins/tts-telegram-sync/skills/full-stack-bootstrap/references/kokoro-bootstrap.md`
- [Upstream: MLX-Audio Kokoro](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/full-stack-bootstrap/references/upstream-fork.md) - renamed from `plugins/tts-telegram-sync/skills/full-stack-bootstrap/references/upstream-fork.md`

</details>

<details>
<summary><strong>tts-tg-sync/health</strong> (2 files)</summary>

- [health Evolution Log (formerly system-health-check)](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/health/references/evolution-log.md) - renamed from `plugins/tts-telegram-sync/skills/health/references/evolution-log.md`
- [Health Checks Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/health/references/health-checks.md) - renamed from `plugins/tts-telegram-sync/skills/health/references/health-checks.md`

</details>

<details>
<summary><strong>tts-tg-sync/hooks</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/hooks/references/evolution-log.md) - renamed from `plugins/tts-telegram-sync/skills/hooks/references/evolution-log.md`

</details>

<details>
<summary><strong>tts-tg-sync/settings-and-tuning</strong> (3 files)</summary>

- [Configuration Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/settings-and-tuning/references/config-reference.md) - renamed from `plugins/tts-telegram-sync/skills/settings-and-tuning/references/config-reference.md`
- [settings-and-tuning Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/settings-and-tuning/references/evolution-log.md) - renamed from `plugins/tts-telegram-sync/skills/settings-and-tuning/references/evolution-log.md`
- [mise.toml Architecture Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/settings-and-tuning/references/mise-toml-reference.md) - renamed from `plugins/tts-telegram-sync/skills/settings-and-tuning/references/mise-toml-reference.md`

</details>

<details>
<summary><strong>tts-tg-sync/setup</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/setup/references/evolution-log.md) - renamed from `plugins/tts-telegram-sync/skills/setup/references/evolution-log.md`

</details>

<details>
<summary><strong>tts-tg-sync/voice-quality-audition</strong> (2 files)</summary>

- [voice-quality-audition Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/voice-quality-audition/references/evolution-log.md) - renamed from `plugins/tts-telegram-sync/skills/voice-quality-audition/references/evolution-log.md`
- [Voice Catalog](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/skills/voice-quality-audition/references/voice-catalog.md) - renamed from `plugins/tts-telegram-sync/skills/voice-quality-audition/references/voice-catalog.md`

</details>


## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+1/-1)

### General Documentation

- [Accessibility & Findability Review](https://github.com/terrylica/cc-skills/blob/main/docs/accessibility-findability-review.md) - updated (+3/-3)
- [Cross-Link Validation Report](https://github.com/terrylica/cc-skills/blob/main/docs/cross-link-validation-report.md) - updated (+2/-2)
- [Content Deduplication Analysis](https://github.com/terrylica/cc-skills/blob/main/docs/deduplication-analysis.md) - updated (+5/-5)
- [Search & Discovery Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/discovery-architecture.md) - updated (+3/-3)
- [Governance & Maintenance Model](https://github.com/terrylica/cc-skills/blob/main/docs/governance-maintenance-model.md) - updated (+2/-2)
- [Governance & Maintenance Model](https://github.com/terrylica/cc-skills/blob/main/docs/governance-model.md) - updated (+2/-2)
- [Hooks Development Guide](https://github.com/terrylica/cc-skills/blob/main/docs/HOOKS.md) - updated (+1/-1)
- [Metadata & Linking Framework](https://github.com/terrylica/cc-skills/blob/main/docs/metadata-linking-framework.md) - updated (+2/-2)
- [Documentation Standards Compliance Matrix](https://github.com/terrylica/cc-skills/blob/main/docs/standards-compliance-matrix.md) - updated (+8/-8)

## Other Documentation

### Other

- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (+1/-1)
- [kokoro-tts Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/CLAUDE.md) - updated (+2/-2)
- [tts-tg-sync Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-tg-sync/CLAUDE.md) - renamed from `plugins/tts-telegram-sync/CLAUDE.md`

## [12.13.1](https://github.com/terrylica/cc-skills/compare/v12.13.0...v12.13.1) (2026-03-21)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>tlg</strong> (14 changes)</summary>

- [cleanup-deleted](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/cleanup-deleted/SKILL.md) - renamed from `plugins/telegram-cli/skills/cleanup-deleted/SKILL.md`
- [create-group](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/create-group/SKILL.md) - renamed from `plugins/telegram-cli/skills/create-group/SKILL.md`
- [delete-messages](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/delete-messages/SKILL.md) - renamed from `plugins/telegram-cli/skills/delete-messages/SKILL.md`
- [download-media](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/download-media/SKILL.md) - renamed from `plugins/telegram-cli/skills/download-media/SKILL.md`
- [find-user](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/find-user/SKILL.md) - renamed from `plugins/telegram-cli/skills/find-user/SKILL.md`
- [forward-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/forward-message/SKILL.md) - renamed from `plugins/telegram-cli/skills/forward-message/SKILL.md`
- [list-dialogs](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/list-dialogs/SKILL.md) - renamed from `plugins/telegram-cli/skills/list-dialogs/SKILL.md`
- [manage-members](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/manage-members/SKILL.md) - renamed from `plugins/telegram-cli/skills/manage-members/SKILL.md`
- [mark-read](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/mark-read/SKILL.md) - renamed from `plugins/telegram-cli/skills/mark-read/SKILL.md`
- [pin-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/pin-message/SKILL.md) - renamed from `plugins/telegram-cli/skills/pin-message/SKILL.md`
- [search-messages](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/search-messages/SKILL.md) - renamed from `plugins/telegram-cli/skills/search-messages/SKILL.md`
- [send-media](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/send-media/SKILL.md) - renamed from `plugins/telegram-cli/skills/send-media/SKILL.md`
- [send-message](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/send-message/SKILL.md) - renamed from `plugins/telegram-cli/skills/send-message/SKILL.md`
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/skills/setup/SKILL.md) - renamed from `plugins/telegram-cli/skills/setup/SKILL.md`

</details>


## Other Documentation

### Other

- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (+1/-1)
- [Telegram CLI Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/tlg/CLAUDE.md) - renamed from `plugins/telegram-cli/CLAUDE.md`

# [12.13.0](https://github.com/terrylica/cc-skills/compare/v12.12.2...v12.13.0) (2026-03-21)


### Features

* **statusline-tools:** add cron-countdown.py PID to ccstatus line ([5f5c392](https://github.com/terrylica/cc-skills/commit/5f5c39251ee3c0d3b46834054cb3a1cb6099f05d))

## [12.12.2](https://github.com/terrylica/cc-skills/compare/v12.12.1...v12.12.2) (2026-03-21)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>ru</strong> (5 changes)</summary>

- [audit-now](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/audit-now/SKILL.md) - updated (+1/-1)
- [encourage](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/encourage/SKILL.md) - updated (+1/-1)
- [forbid](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/forbid/SKILL.md) - updated (+1/-1)
- [settings](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/settings/SKILL.md) - renamed from `plugins/ru/skills/config/SKILL.md`
- [wizard](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/wizard/SKILL.md) - updated (+8/-8)

</details>


### Plugin READMEs

- [RU](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/README.md) - updated (+1/-1)

### Skill References

<details>
<summary><strong>ru/settings</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/settings/references/evolution-log.md) - renamed from `plugins/ru/skills/config/references/evolution-log.md`

</details>


## Repository Documentation

### Root Documentation

- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+1/-1)

## Other Documentation

### Other

- [ru Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/CLAUDE.md) - updated (+1/-1)

## [12.12.1](https://github.com/terrylica/cc-skills/compare/v12.12.0...v12.12.1) (2026-03-20)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>quant-research</strong> (1 change)</summary>

- [zigzag-pattern-classifier](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/zigzag-pattern-classifier/SKILL.md) - updated (+9/-5)

</details>


### Skill References

<details>
<summary><strong>quant-research/zigzag-pattern-classifier</strong> (4 files)</summary>

- [Binning Methodology: Freedman–Diaconis for FD-Binned Variants](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/zigzag-pattern-classifier/references/binning-methodology.md) - new (+395)
- [Data Pipeline: End-to-End ZigZag Classification System](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/zigzag-pattern-classifier/references/data-pipeline.md) - new (+592)
- [EURUSD Validation Scenarios: Three Market Conditions](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/zigzag-pattern-classifier/references/eurusd-validation-scenarios.md) - new (+292)
- [Notation & Definitions: Single Source of Truth](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/zigzag-pattern-classifier/references/notation-definitions.md) - new (+404)

</details>

# [12.12.0](https://github.com/terrylica/cc-skills/compare/v12.11.0...v12.12.0) (2026-03-20)


### Features

* **quant-research:** add zigzag-pattern-classifier skill + make MiniMax model configurable ([9bf4829](https://github.com/terrylica/cc-skills/commit/9bf48291c92dad50525d0b964bbc5c2195c62bc8))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (2 changes)</summary>

- [claude-code-proxy-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/claude-code-proxy-patterns/SKILL.md) - updated (+3/-4)
- [session-debrief](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-debrief/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>quant-research</strong> (1 change)</summary>

- [zigzag-pattern-classifier](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/zigzag-pattern-classifier/SKILL.md) - new (+268)

</details>


### Skill References

<details>
<summary><strong>devops-tools/claude-code-proxy-patterns</strong> (1 file)</summary>

- [Provider Compatibility Matrix](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/claude-code-proxy-patterns/references/provider-compatibility.md) - updated (+2/-2)

</details>

<details>
<summary><strong>quant-research/zigzag-pattern-classifier</strong> (3 files)</summary>

- [Epsilon Tolerance Band: "Equal" Price Level Definition](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/zigzag-pattern-classifier/references/epsilon-tolerance-detail.md) - new (+315)
- [UP–DOWN–UP Variants: 9 Complete Classification](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/zigzag-pattern-classifier/references/three-pivot-variants.md) - new (+393)
- [UP–DOWN Variants: Granular Two-Pivot Classification with FD Binning](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/zigzag-pattern-classifier/references/two-pivot-variants.md) - new (+316)

</details>

# [12.11.0](https://github.com/terrylica/cc-skills/compare/v12.10.0...v12.11.0) (2026-03-19)


### Features

* **plugins:** add agent-reach plugin + consolidate tts-telegram-sync skills ([5622c87](https://github.com/terrylica/cc-skills/commit/5622c879d63fbf9360623a5f2c100541b2a22bb4))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>agent-reach</strong> (1 change)</summary>

- [agent-reach](https://github.com/terrylica/cc-skills/blob/main/plugins/agent-reach/skills/agent-reach/SKILL.md) - new (+232)

</details>

<details>
<summary><strong>devops-tools</strong> (2 changes)</summary>

- [dual channel watchexec notifications](https://github.com/terrylica/cc-skills/blob/v12.10.0/plugins/devops-tools/skills/dual-channel-watchexec-notifications/SKILL.md) - deleted
- [macbook-desktop-mode](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/macbook-desktop-mode/SKILL.md) - updated (+4)

</details>

<details>
<summary><strong>kokoro-tts</strong> (1 change)</summary>

- [realtime-audio-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/realtime-audio-architecture/SKILL.md) - updated (+4)

</details>

<details>
<summary><strong>quant-research</strong> (1 change)</summary>

- [backtesting-py-oracle](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/backtesting-py-oracle/SKILL.md) - updated (+114)

</details>

<details>
<summary><strong>tts-telegram-sync</strong> (2 changes)</summary>

- [health](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/health/SKILL.md) - updated (+178/-36)
- [system health check](https://github.com/terrylica/cc-skills/blob/v12.10.0/plugins/tts-telegram-sync/skills/system-health-check/SKILL.md) - deleted

</details>


### Plugin READMEs

- [Agent Reach Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/agent-reach/README.md) - new (+23)
- [TTS Telegram Sync](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/README.md) - updated (+1/-1)

### Skill References

<details>
<summary><strong>agent-reach/agent-reach</strong> (1 file)</summary>

- [Channel Setup Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/agent-reach/skills/agent-reach/references/setup-channels.md) - new (+70)

</details>

<details>
<summary><strong>devops-tools/dual-channel-watchexec-notifications</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/v12.10.0/plugins/devops-tools/skills/dual-channel-watchexec-notifications/references/evolution-log.md) - deleted

</details>

<details>
<summary><strong>tts-telegram-sync/health</strong> (2 files)</summary>

- [health Evolution Log (formerly system-health-check)](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/health/references/evolution-log.md) - updated (+4/-25)
- [Health Checks Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/health/references/health-checks.md) - renamed from `plugins/tts-telegram-sync/skills/system-health-check/references/health-checks.md`

</details>

<details>
<summary><strong>tts-telegram-sync/system-health-check</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/v12.10.0/plugins/tts-telegram-sync/skills/system-health-check/references/evolution-log.md) - deleted

</details>

# [12.10.0](https://github.com/terrylica/cc-skills/compare/v12.9.0...v12.10.0) (2026-03-18)


### Features

* **quant-research:** add sharpe-ratio-non-iid-corrections skill with 82-equation tracker ([bfd7395](https://github.com/terrylica/cc-skills/commit/bfd7395c2f90be1189b7a986e16f6b8a176b4493))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| accepted | [Ralph Dual Time Tracking (Runtime + Wall-Clock)](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-22-ralph-dual-time-tracking.md) | updated (+1/-1) |
| accepted | [asciinema-tools Plugin Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-24-asciinema-tools-plugin.md) | updated (+1/-1) |
| accepted | [asciinema-tools Daemon Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-26-asciinema-daemon-architecture.md) | updated (+3/-3) |
| accepted | [SR&ED Dynamic Project Discovery via Claude Agent SDK](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-18-sred-dynamic-discovery.md) | updated (+1/-1) |

### Design Specs

- [SR&ED Project Discovery: Forked Haiku Session via Claude Agent SDK](https://github.com/terrylica/cc-skills/blob/main/docs/design/2026-01-18-sred-dynamic-discovery/spec.md) - updated (+3/-3)

## Plugin Documentation

### Skills

<details>
<summary><strong>asciinema-tools</strong> (2 changes)</summary>

- [bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/bootstrap/SKILL.md) - updated (+1/-1)
- [daemon-setup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-setup/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>calcom-commander</strong> (1 change)</summary>

- [calcom-access](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/calcom-access/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [macbook-desktop-mode](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/macbook-desktop-mode/SKILL.md) - new (+321)

</details>

<details>
<summary><strong>gmail-commander</strong> (1 change)</summary>

- [gmail-access](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/gmail-access/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>mql5</strong> (1 change)</summary>

- [log-reader](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/log-reader/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>plugin-dev</strong> (1 change)</summary>

- [skill-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/SKILL.md) - updated (+2/-2)

</details>

<details>
<summary><strong>productivity-tools</strong> (1 change)</summary>

- [gdrive-access](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/gdrive-access/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>quant-research</strong> (4 changes)</summary>

- [adaptive-wfo-epoch](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/SKILL.md) - updated (+7)
- [evolutionary-metric-ranking](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/evolutionary-metric-ranking/SKILL.md) - updated (+6/-5)
- [opendeviation-eval-metrics](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/opendeviation-eval-metrics/SKILL.md) - updated (+4/-3)
- [sharpe-ratio-non-iid-corrections](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/sharpe-ratio-non-iid-corrections/SKILL.md) - new (+159)

</details>

<details>
<summary><strong>telegram-cli</strong> (14 changes)</summary>

- [cleanup-deleted](https://github.com/terrylica/cc-skills/blob/main/plugins/telegram-cli/skills/cleanup-deleted/SKILL.md) - new (+57)
- [create-group](https://github.com/terrylica/cc-skills/blob/main/plugins/telegram-cli/skills/create-group/SKILL.md) - new (+46)
- [delete-messages](https://github.com/terrylica/cc-skills/blob/main/plugins/telegram-cli/skills/delete-messages/SKILL.md) - new (+47)
- [download-media](https://github.com/terrylica/cc-skills/blob/main/plugins/telegram-cli/skills/download-media/SKILL.md) - new (+47)
- [find-user](https://github.com/terrylica/cc-skills/blob/main/plugins/telegram-cli/skills/find-user/SKILL.md) - new (+57)
- [forward-message](https://github.com/terrylica/cc-skills/blob/main/plugins/telegram-cli/skills/forward-message/SKILL.md) - new (+39)
- [list-dialogs](https://github.com/terrylica/cc-skills/blob/main/plugins/telegram-cli/skills/list-dialogs/SKILL.md) - updated (+22/-11)
- [manage-members](https://github.com/terrylica/cc-skills/blob/main/plugins/telegram-cli/skills/manage-members/SKILL.md) - new (+63)
- [mark-read](https://github.com/terrylica/cc-skills/blob/main/plugins/telegram-cli/skills/mark-read/SKILL.md) - new (+30)
- [pin-message](https://github.com/terrylica/cc-skills/blob/main/plugins/telegram-cli/skills/pin-message/SKILL.md) - new (+38)
- [search-messages](https://github.com/terrylica/cc-skills/blob/main/plugins/telegram-cli/skills/search-messages/SKILL.md) - new (+49)
- [send-media](https://github.com/terrylica/cc-skills/blob/main/plugins/telegram-cli/skills/send-media/SKILL.md) - new (+58)
- [send-message](https://github.com/terrylica/cc-skills/blob/main/plugins/telegram-cli/skills/send-message/SKILL.md) - updated (+23/-22)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/telegram-cli/skills/setup/SKILL.md) - updated (+44/-24)

</details>


### Plugin READMEs

- [asciinema-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/README.md) - updated (+1/-1)
- [devops-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/README.md) - updated (+1/-1)
- [gh-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/README.md) - updated (+1/-1)

### Skill References

<details>
<summary><strong>asciinema-tools/asciinema-analyzer</strong> (1 file)</summary>

- [Domain Keywords Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-analyzer/references/domain-keywords.md) - updated (+1/-1)

</details>

<details>
<summary><strong>asciinema-tools/daemon-setup</strong> (1 file)</summary>

- [Verification and Troubleshooting](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-setup/references/verification-and-troubleshooting.md) - updated (+1/-1)

</details>

<details>
<summary><strong>devops-tools/macbook-desktop-mode</strong> (1 file)</summary>

- [macbook-desktop-mode Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/macbook-desktop-mode/references/evolution-log.md) - new (+16)

</details>

<details>
<summary><strong>itp/mise-tasks</strong> (1 file)</summary>

- [Meta-Prompt: Autonomous Polyglot Monorepo Bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/references/bootstrap-monorepo.md) - updated (+2/-2)

</details>

<details>
<summary><strong>plugin-dev/skill-architecture</strong> (2 files)</summary>

- [Agent Skill Name](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/advanced-topics.md) - updated (+2/-2)
- [My Skill](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/validation-reference.md) - updated (+2/-2)

</details>

<details>
<summary><strong>quant-research/opendeviation-eval-metrics</strong> (1 file)</summary>

- [Sharpe Ratio Formulas for Range Bars](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/opendeviation-eval-metrics/references/sharpe-formulas.md) - updated (+5)

</details>

<details>
<summary><strong>quant-research/sharpe-ratio-non-iid-corrections</strong> (2 files)</summary>

- [How to Use the Sharpe Ratio](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/sharpe-ratio-non-iid-corrections/references/how-to-use-the-sharpe-ratio-2026.md) - renamed from `plugins/quant-research/skills/opendeviation-eval-metrics/references/how-to-use-the-sharpe-ratio-2026.md`
- [Sharpe Paper Equation → Implementation Tracker](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/sharpe-ratio-non-iid-corrections/references/sharpe-paper-tracker.md) - new (+119)

</details>


## Repository Documentation

### Root Documentation

- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+4/-4)

## Other Documentation

### Other

- [Troubleshooting cc-skills Marketplace Installation](https://github.com/terrylica/cc-skills/blob/main/docs/troubleshooting/marketplace-installation.md) - updated (+1/-1)
- [quant-research Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/CLAUDE.md) - updated (+8/-7)
- [Telegram CLI Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/telegram-cli/CLAUDE.md) - updated (+111/-34)
- [PRD.md - Nested CLAUDE.md Link Farm Migration](https://github.com/terrylica/cc-skills/blob/main/PRD.md) - updated (+11/-1)

# [12.9.0](https://github.com/terrylica/cc-skills/compare/v12.8.0...v12.9.0) (2026-03-17)


### Bug Fixes

* **quant-research:** fix all 53 $$-block equations broken by GH pre-processor ([297a5bd](https://github.com/terrylica/cc-skills/commit/297a5bda4e7df65e64c9f3339df74d8cc1e11da1))
* **quant-research:** reformat 11 long equations to prevent ugly wrapping on GitHub ([a9ebab6](https://github.com/terrylica/cc-skills/commit/a9ebab670b6d3e79f706a26f02f56cc294cc18b0))
* **quant-research:** resolve all GitHub GFM math rendering failures in Sharpe ratio doc ([da8da22](https://github.com/terrylica/cc-skills/commit/da8da222c47be43d8aff90c692a21a83289193e0))
* **quant-research:** resolve GitHub GFM math rendering errors in Sharpe ratio doc ([c708660](https://github.com/terrylica/cc-skills/commit/c708660aa7f5414e16c9ffe323dfc4d110681cd2))


### Features

* **doc-tools:** add academic-pdf-to-gfm skill with two-layer GFM math validator ([f2e47d4](https://github.com/terrylica/cc-skills/commit/f2e47d460d98e4cec6e859bcfa467ea33c2e267e))
* **doc-tools:** add E0 check to validator — detect \!\, in $$ blocks ([dd0dec7](https://github.com/terrylica/cc-skills/commit/dd0dec743eb18de10ea19afe0386d05c6827c5ad))
* **doc-tools:** add W6 GitLab.com 50-math-span limit check to validator ([ba8b5a5](https://github.com/terrylica/cc-skills/commit/ba8b5a58ccde5385e47627500b7712f9e4be924e))
* **quant-research:** add Numba reference implementation and fix GFM math rendering ([6ce3f99](https://github.com/terrylica/cc-skills/commit/6ce3f993c7e0685207b6ca1fb96da46e327c67d7))
* **telegram-cli:** new plugin for MTProto user-account messaging via Telethon ([3df945e](https://github.com/terrylica/cc-skills/commit/3df945ecd0e672c9488121187fad68866dd2beb9)), closes [#26](https://github.com/terrylica/cc-skills/issues/26)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (2 changes)</summary>

- [clickhouse-cloud-management](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/clickhouse-cloud-management/SKILL.md) - updated (+2)
- [clickhouse-pydantic-config](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/clickhouse-pydantic-config/SKILL.md) - updated (+2)

</details>

<details>
<summary><strong>doc-tools</strong> (1 change)</summary>

- [academic-pdf-to-gfm](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/academic-pdf-to-gfm/SKILL.md) - new (+381)

</details>

<details>
<summary><strong>quality-tools</strong> (1 change)</summary>

- [clickhouse-architect](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/clickhouse-architect/SKILL.md) - updated (+37/-1)

</details>

<details>
<summary><strong>telegram-cli</strong> (3 changes)</summary>

- [list-dialogs](https://github.com/terrylica/cc-skills/blob/main/plugins/telegram-cli/skills/list-dialogs/SKILL.md) - new (+42)
- [send-message](https://github.com/terrylica/cc-skills/blob/main/plugins/telegram-cli/skills/send-message/SKILL.md) - new (+56)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/telegram-cli/skills/setup/SKILL.md) - new (+69)

</details>


### Skill References

<details>
<summary><strong>doc-tools/academic-pdf-to-gfm</strong> (2 files)</summary>

- [GitHub GFM Math Support Table](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/academic-pdf-to-gfm/references/github-math-support-table.md) - new (+195)
- [PDF Type Detection Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/academic-pdf-to-gfm/references/pdf-type-detection.md) - new (+181)

</details>

<details>
<summary><strong>quant-research/opendeviation-eval-metrics</strong> (2 files)</summary>

- [Beyond Hit Rate: Outcome Predictability Framework](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/opendeviation-eval-metrics/references/beyond-hit-rate.md) - updated (+21)
- [How to Use the Sharpe Ratio](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/opendeviation-eval-metrics/references/how-to-use-the-sharpe-ratio-2026.md) - updated (+184/-101)

</details>


## Other Documentation

### Other

- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (+1)
- [doc-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/CLAUDE.md) - updated (+12/-11)
- [Skill Benchmark: academic-pdf-to-gfm](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/academic-pdf-to-gfm-workspace/iteration-1/benchmark.md) - new (+13)
- [Validating Math Equations in GFM Markdown Before Pushing to GitHub](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/academic-pdf-to-gfm-workspace/iteration-1/eval-katex-validation-ci/with_skill/outputs/response.md) - new (+203)
- [Validating LaTeX/KaTeX Equations in Markdown for CI](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/academic-pdf-to-gfm-workspace/iteration-1/eval-katex-validation-ci/without_skill/outputs/response.md) - new (+227)
- [Why Your Matrix Equation Shows Raw LaTeX on GitHub](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/academic-pdf-to-gfm-workspace/iteration-1/eval-matrix-rendering-fix/with_skill/outputs/response.md) - new (+77)
- [Why Your Matrix Equation Shows Raw LaTeX on GitHub](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/academic-pdf-to-gfm-workspace/iteration-1/eval-matrix-rendering-fix/without_skill/outputs/response.md) - new (+119)
- [Converting Your Finance PDF to GitHub Markdown](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/academic-pdf-to-gfm-workspace/iteration-1/eval-word-pdf-tool-selection/with_skill/outputs/response.md) - new (+127)
- [PDF to GitHub Markdown: Tool Selection and Math Handling](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/academic-pdf-to-gfm-workspace/iteration-1/eval-word-pdf-tool-selection/without_skill/outputs/response.md) - new (+141)
- [Telegram CLI Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/telegram-cli/CLAUDE.md) - new (+54)

# [12.8.0](https://github.com/terrylica/cc-skills/compare/v12.7.0...v12.8.0) (2026-03-15)


### Features

* **quant-research:** add opendeviation-eval-metrics SOTA reference + exchange-session-detector skill ([307ccf5](https://github.com/terrylica/cc-skills/commit/307ccf505b607dbf1957ac2afd313d0a92812e23)), closes [hi#confidence](https://github.com/hi/issues/confidence)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>quant-research</strong> (2 changes)</summary>

- [exchange-session-detector](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/exchange-session-detector/SKILL.md) - new (+175)
- [opendeviation-eval-metrics](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/opendeviation-eval-metrics/SKILL.md) - renamed from `plugins/quant-research/skills/rangebar-eval-metrics/SKILL.md`

</details>


### Skill References

<details>
<summary><strong>quant-research/exchange-session-detector</strong> (3 files)</summary>

- [ClickHouse Session Detection SQL](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/exchange-session-detector/references/clickhouse-session-sql.md) - new (+95)
- [Exchange Registry Pattern](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/exchange-session-detector/references/exchange-registry.md) - new (+123)
- [SessionDetector Pattern](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/exchange-session-detector/references/session-detector-pattern.md) - new (+185)

</details>

<details>
<summary><strong>quant-research/opendeviation-eval-metrics</strong> (13 files)</summary>

- [Anti-Patterns in Range Bar Metrics](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/opendeviation-eval-metrics/references/anti-patterns.md) - renamed from `plugins/quant-research/skills/rangebar-eval-metrics/references/anti-patterns.md`
- [Beyond Hit Rate: Outcome Predictability Framework](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/opendeviation-eval-metrics/references/beyond-hit-rate.md) - new (+86)
- [Crypto Market Considerations](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/opendeviation-eval-metrics/references/crypto-markets.md) - renamed from `plugins/quant-research/skills/rangebar-eval-metrics/references/crypto-markets.md`
- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/opendeviation-eval-metrics/references/evolution-log.md) - renamed from `plugins/quant-research/skills/rangebar-eval-metrics/references/evolution-log.md`
- [How to Use the Sharpe Ratio](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/opendeviation-eval-metrics/references/how-to-use-the-sharpe-ratio-2026.md) - new (+812)
- [Metrics JSON Schema](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/opendeviation-eval-metrics/references/metrics-schema.md) - renamed from `plugins/quant-research/skills/rangebar-eval-metrics/references/metrics-schema.md`
- [ML Prediction Quality Metrics](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/opendeviation-eval-metrics/references/ml-prediction-quality.md) - renamed from `plugins/quant-research/skills/rangebar-eval-metrics/references/ml-prediction-quality.md`
- [Risk Metrics for Range Bars](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/opendeviation-eval-metrics/references/risk-metrics.md) - renamed from `plugins/quant-research/skills/rangebar-eval-metrics/references/risk-metrics.md`
- [Sharpe Ratio Formulas for Range Bars](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/opendeviation-eval-metrics/references/sharpe-formulas.md) - renamed from `plugins/quant-research/skills/rangebar-eval-metrics/references/sharpe-formulas.md`
- [State-of-the-Art Methods (2025-2026)](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/opendeviation-eval-metrics/references/sota-2025-2026.md) - renamed from `plugins/quant-research/skills/rangebar-eval-metrics/references/sota-2025-2026.md`
- [Structured Logging Contract for AWFES Experiments](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/opendeviation-eval-metrics/references/structured-logging.md) - renamed from `plugins/quant-research/skills/rangebar-eval-metrics/references/structured-logging.md`
- [Temporal Aggregation for Range Bars](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/opendeviation-eval-metrics/references/temporal-aggregation.md) - renamed from `plugins/quant-research/skills/rangebar-eval-metrics/references/temporal-aggregation.md`
- [Worked Examples](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/opendeviation-eval-metrics/references/worked-examples.md) - renamed from `plugins/quant-research/skills/rangebar-eval-metrics/references/worked-examples.md`

</details>


## Other Documentation

### Other

- [quant-research Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/CLAUDE.md) - updated (+2/-1)
- [Session Detection Upgrade Guide: opendeviationbar-py](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/exchange-session-detector-workspace/iteration-1/upgrade-path/with_skill/outputs/session-detection-upgrade-guide.md) - new (+902)
- [Exchange Session Detection: Upgrade Plan](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/exchange-session-detector-workspace/iteration-1/upgrade-path/without_skill/outputs/exchange-session-upgrade-plan.md) - new (+628)

# [12.7.0](https://github.com/terrylica/cc-skills/compare/v12.6.1...v12.7.0) (2026-03-15)


### Features

* **devops-tools:** add agentic-process-monitor skill ([1c7fa5b](https://github.com/terrylica/cc-skills/commit/1c7fa5bc56ac5b1c22c9f416c20f13ecbc3ec2b4))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [agentic-process-monitor](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/agentic-process-monitor/SKILL.md) - new (+170)

</details>

## [12.6.1](https://github.com/terrylica/cc-skills/compare/v12.6.0...v12.6.1) (2026-03-14)


### Bug Fixes

* **statusline-tools:** use background thread for sound playback in iTerm2 component ([97e7f2f](https://github.com/terrylica/cc-skills/commit/97e7f2f1f3a40d07403482657e9ceae0ec8fb2fe))

# [12.6.0](https://github.com/terrylica/cc-skills/compare/v12.5.1...v12.6.0) (2026-03-14)


### Features

* **statusline-tools:** add escalating sound alerts to cron countdown ([f196867](https://github.com/terrylica/cc-skills/commit/f196867cfec9adffed97dbc9e0dad8eac5d59e36))

## [12.5.1](https://github.com/terrylica/cc-skills/compare/v12.5.0...v12.5.1) (2026-03-14)


### Reverts

* **statusline-tools:** remove countdown from CC statusline — now in iTerm2 component ([8c76aff](https://github.com/terrylica/cc-skills/commit/8c76affddd7723378d145feea9ae19e7ba906711))

# [12.5.0](https://github.com/terrylica/cc-skills/compare/v12.4.0...v12.5.0) (2026-03-14)


### Features

* **statusline-tools:** add iTerm2 Python status bar component for real-time cron countdown ([f0b1edf](https://github.com/terrylica/cc-skills/commit/f0b1edfb85721025488e65bce849a9bcda20edf3))

# [12.4.0](https://github.com/terrylica/cc-skills/compare/v12.3.6...v12.4.0) (2026-03-14)


### Features

* **statusline-tools:** add countdown timer to cron job display ([da32601](https://github.com/terrylica/cc-skills/commit/da326010d3da62e8af650a4b3f67b47f32cffacc))

## [12.3.6](https://github.com/terrylica/cc-skills/compare/v12.3.5...v12.3.6) (2026-03-14)


### Bug Fixes

* **gemini-deep-research:** fix 5 automation bugs found during empirical session ([0c8febe](https://github.com/terrylica/cc-skills/commit/0c8febe12454dfbefc2dbe7a567db431e0d231f2))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gemini-deep-research</strong> (1 change)</summary>

- [gemini-deep-research](https://github.com/terrylica/cc-skills/blob/main/plugins/gemini-deep-research/skills/research/SKILL.md) - updated (+7/-6)

</details>

## [12.3.5](https://github.com/terrylica/cc-skills/compare/v12.3.4...v12.3.5) (2026-03-13)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [firecrawl-research-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/SKILL.md) - updated (+64/-11)

</details>


### Skill References

<details>
<summary><strong>devops-tools/firecrawl-research-patterns</strong> (1 file)</summary>

- [Academic Paper Routing](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/academic-paper-routing.md) - updated (+1/-1)

</details>

## [12.3.4](https://github.com/terrylica/cc-skills/compare/v12.3.3...v12.3.4) (2026-03-13)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [firecrawl-research-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/SKILL.md) - updated (+14/-10)

</details>


### Skill References

<details>
<summary><strong>devops-tools/firecrawl-research-patterns</strong> (1 file)</summary>

- [Academic Paper Routing](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/academic-paper-routing.md) - updated (+26/-17)

</details>

## [12.3.3](https://github.com/terrylica/cc-skills/compare/v12.3.2...v12.3.3) (2026-03-13)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [firecrawl-research-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/SKILL.md) - updated (+39/-3)

</details>


### Skill References

<details>
<summary><strong>devops-tools/firecrawl-research-patterns</strong> (1 file)</summary>

- [Academic Paper Routing](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/academic-paper-routing.md) - updated (+13/-11)

</details>

## [12.3.2](https://github.com/terrylica/cc-skills/compare/v12.3.1...v12.3.2) (2026-03-13)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [firecrawl-research-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/SKILL.md) - updated (+67/-62)

</details>


### Skill References

<details>
<summary><strong>devops-tools/firecrawl-research-patterns</strong> (1 file)</summary>

- [Academic Paper Routing](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/academic-paper-routing.md) - updated (+28/-14)

</details>

## [12.3.1](https://github.com/terrylica/cc-skills/compare/v12.3.0...v12.3.1) (2026-03-13)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [firecrawl-research-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/SKILL.md) - updated (+164/-15)

</details>


### Skill References

<details>
<summary><strong>devops-tools/firecrawl-research-patterns</strong> (2 files)</summary>

- [Academic Paper Routing](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/academic-paper-routing.md) - updated (+32)
- [Firecrawl Self-Hosted Operations](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/self-hosted-operations.md) - updated (+34/-12)

</details>

# [12.3.0](https://github.com/terrylica/cc-skills/compare/v12.2.0...v12.3.0) (2026-03-13)


### Features

* **session-debrief:** add turn-level chunking + synthesis merge for oversized payloads ([67a5784](https://github.com/terrylica/cc-skills/commit/67a57844f75d3cf1561f47af84b77755a7b828da))
* **statusline-tools:** add cron-tracker PostToolUse hook for global scheduler persistence ([41d8cde](https://github.com/terrylica/cc-skills/commit/41d8cde880488921348585a12d37bd43167d355e))
* **statusline-tools:** display last 5 versioned cron prompts as numbered OSC 8 hyperlinks ([679aad9](https://github.com/terrylica/cc-skills/commit/679aad94769773ec273904f7dcd1a33176b2bba1))

# [12.2.0](https://github.com/terrylica/cc-skills/compare/v12.1.2...v12.2.0) (2026-03-12)


### Features

* **session-debrief:** add Python preprocessor using claude-code-log for enriched session parsing ([ad1b9dd](https://github.com/terrylica/cc-skills/commit/ad1b9ddd14e84cf17afb1047d82d138be2748401))

## [12.1.2](https://github.com/terrylica/cc-skills/compare/v12.1.1...v12.1.2) (2026-03-12)


### Bug Fixes

* **session-debrief:** strip skill injection content and meta-tool calls from structured log ([2a6da4a](https://github.com/terrylica/cc-skills/commit/2a6da4a894072366bb46b2d56f29575003983f24))

## [12.1.1](https://github.com/terrylica/cc-skills/compare/v12.1.0...v12.1.1) (2026-03-12)


### Bug Fixes

* **session-debrief:** prevent MiniMax tool_call hallucination poisoning loop ([eac669d](https://github.com/terrylica/cc-skills/commit/eac669d6707b5d835fbf6b324c7ab9df58875457))

# [12.1.0](https://github.com/terrylica/cc-skills/compare/v12.0.0...v12.1.0) (2026-03-12)


### Bug Fixes

* **session-debrief:** Restore callMiniMax + 3-round MiniMax prompt iteration ([ff54eed](https://github.com/terrylica/cc-skills/commit/ff54eed06b85e43492459990f53cace44ef34ae5))


### Features

* **cli-anything:** Add CLI-Anything reference skill plugin ([1472ce7](https://github.com/terrylica/cc-skills/commit/1472ce708d4a0508ca2def56ef0b1152ba1b9a65))
* **session-debrief:** add few-shot skeleton examples and prompt-benchmark.ts ([02bfce6](https://github.com/terrylica/cc-skills/commit/02bfce6d18a57183d8ebae02721ca5a35fcc6450))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>cli-anything</strong> (1 change)</summary>

- [cli-anything](https://github.com/terrylica/cc-skills/blob/main/plugins/cli-anything/skills/cli-anything/SKILL.md) - new (+335)

</details>


## Other Documentation

### Other

- [cli-anything Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/cli-anything/CLAUDE.md) - new (+37)

# [12.0.0](https://github.com/terrylica/cc-skills/compare/v11.95.0...v12.0.0) (2026-03-12)


### Bug Fixes

* Remove cli-anything from marketplace.json (plugin directory not yet ready) ([005a5c0](https://github.com/terrylica/cc-skills/commit/005a5c062775d122958f859e29ae897de5c90b5f))


### Features

* **devops-tools:** Rename session-blind-spots skill to session-debrief ([182f74b](https://github.com/terrylica/cc-skills/commit/182f74b38d6a9a336810753250643c52cb767bbb))


### BREAKING CHANGES

* **devops-tools:** Legacy UUID mode removed entirely; only --goal/--since mode supported.





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (2 changes)</summary>

- [session blind spots](https://github.com/terrylica/cc-skills/blob/v11.95.0/plugins/devops-tools/skills/session-blind-spots/SKILL.md) - deleted
- [session-debrief](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-debrief/SKILL.md) - new (+187)

</details>

# [11.95.0](https://github.com/terrylica/cc-skills/compare/v11.94.0...v11.95.0) (2026-03-11)


### Features

* **code-hardcode-audit:** Add 3 complementary secret detection tools (bandit, trufflehog, whispers) ([f94cc74](https://github.com/terrylica/cc-skills/commit/f94cc74b951c2d5a587ae96e38f49660109f9b2b))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [code-hardcode-audit](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/code-hardcode-audit/SKILL.md) - updated (+26/-9)

</details>

# [11.94.0](https://github.com/terrylica/cc-skills/compare/v11.93.0...v11.94.0) (2026-03-11)


### Features

* **code-hardcode-audit:** Add ast-grep & env-coverage tools, preflight checks, semgrep rules ([f81fec5](https://github.com/terrylica/cc-skills/commit/f81fec55db99d951f1b1898938243a4ca26c25ab))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [code-hardcode-audit](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/code-hardcode-audit/SKILL.md) - updated (+41/-26)

</details>

<details>
<summary><strong>link-tools</strong> (1 change)</summary>

- [link-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/skills/link-validation/SKILL.md) - updated (+2/-3)

</details>

<details>
<summary><strong>statusline-tools</strong> (1 change)</summary>

- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/setup/SKILL.md) - updated (+8/-12)

</details>


### Plugin READMEs

- [link-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/README.md) - updated (+3/-18)
- [statusline-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/README.md) - updated (+17/-111)

### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+1/-1)

</details>


## Repository Documentation

### Root Documentation

- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+5/-7)

### General Documentation

- [Hooks Development Guide](https://github.com/terrylica/cc-skills/blob/main/docs/HOOKS.md) - updated (-1)
- [Toolchain & Automation Landscape](https://github.com/terrylica/cc-skills/blob/main/docs/tool-inventory.md) - updated (+38/-38)

## Other Documentation

### Other

- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (+1/-1)
- [link-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/CLAUDE.md) - updated (-6)
- [statusline-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/CLAUDE.md) - updated (+4/-14)

# [11.93.0](https://github.com/terrylica/cc-skills/compare/v11.92.0...v11.93.0) (2026-03-10)


### Bug Fixes

* **dotfiles-tools:** replace backwards scope check with source-dir scoping ([38dccb1](https://github.com/terrylica/cc-skills/commit/38dccb135aa10f7802e0d57563a6df8d71fc7f26))


### Features

* **dotfiles-tools:** add interactive chezmoi-sync skill, remove stop hook ([f4e85a7](https://github.com/terrylica/cc-skills/commit/f4e85a721700cb32f4f190072572d2e211bcde64))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>dotfiles-tools</strong> (1 change)</summary>

- [chezmoi-sync](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/skills/chezmoi-sync/SKILL.md) - new (+75)

</details>


### Plugin READMEs

- [dotfiles-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/README.md) - updated (+12/-57)

## Other Documentation

### Other

- [dotfiles-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/CLAUDE.md) - updated (+6/-6)

# [11.92.0](https://github.com/terrylica/cc-skills/compare/v11.91.0...v11.92.0) (2026-03-09)


### Bug Fixes

* **dotfiles-tools:** fix scope check fallthrough when cwd missing or is $HOME ([a9b699f](https://github.com/terrylica/cc-skills/commit/a9b699f0f5b710ec84856069912cc7ef7414fb8d))
* **tts:** Telegram alert on failure, never fall back to say ([0911f6c](https://github.com/terrylica/cc-skills/commit/0911f6cef204eddeed1e53d7842e90086198b3cd))


### Features

* **kokoro-tts:** add audio device hot-switching pattern ([4bdc72e](https://github.com/terrylica/cc-skills/commit/4bdc72ebd04e7c0c41a5035154628aa2e2795015))
* **mise:** update run-full-release skill with v13.2.0 production learnings ([0a4669d](https://github.com/terrylica/cc-skills/commit/0a4669de3b3bb360d99f0b11458624da0cf08445))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>kokoro-tts</strong> (1 change)</summary>

- [realtime-audio-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/realtime-audio-architecture/SKILL.md) - updated (+88/-10)

</details>

<details>
<summary><strong>mise</strong> (1 change)</summary>

- [run-full-release](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/run-full-release/SKILL.md) - updated (+57/-162)

</details>


### Skill References

<details>
<summary><strong>kokoro-tts/realtime-audio-architecture</strong> (2 files)</summary>

- [Audio Device Routing and Hot-Switching](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/realtime-audio-architecture/references/device-routing.md) - new (+117)
- [Write-Based sounddevice.OutputStream](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/realtime-audio-architecture/references/write-based-stream.md) - updated (+8/-4)

</details>

<details>
<summary><strong>mise/run-full-release</strong> (2 files)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/run-full-release/references/evolution-log.md) - updated (+28)
- [Task Implementation Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/run-full-release/references/task-implementations.md) - new (+172)

</details>


## Other Documentation

### Other

- [kokoro-tts Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/CLAUDE.md) - updated (+1)

# [11.91.0](https://github.com/terrylica/cc-skills/compare/v11.90.3...v11.91.0) (2026-03-09)


### Features

* **kokoro-tts:** add realtime-audio-architecture skill ([1f1adf0](https://github.com/terrylica/cc-skills/commit/1f1adf041612514ae12360bc9a38330ff819f5a7))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>kokoro-tts</strong> (1 change)</summary>

- [realtime-audio-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/realtime-audio-architecture/SKILL.md) - new (+229)

</details>


### Skill References

<details>
<summary><strong>kokoro-tts/realtime-audio-architecture</strong> (3 files)</summary>

- [launchd QoS for Audio Processes](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/realtime-audio-architecture/references/launchd-qos.md) - new (+72)
- [Pipeline Synthesis for Gapless TTS](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/realtime-audio-architecture/references/pipeline-synthesis.md) - new (+97)
- [Write-Based sounddevice.OutputStream](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/realtime-audio-architecture/references/write-based-stream.md) - new (+98)

</details>


## Other Documentation

### Other

- [Design Specifications Guide](https://github.com/terrylica/cc-skills/blob/main/docs/design/CLAUDE.md) - new (+73)
- [kokoro-tts Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/CLAUDE.md) - updated (+18/-5)
- [PRD.md - Nested CLAUDE.md Link Farm Migration](https://github.com/terrylica/cc-skills/blob/main/PRD.md) - updated (+64/-101)

## [11.90.3](https://github.com/terrylica/cc-skills/compare/v11.90.2...v11.90.3) (2026-03-09)


### Bug Fixes

* **media-tools:** use standard Sibling pattern instead of Marketplace ([ea36dd6](https://github.com/terrylica/cc-skills/commit/ea36dd6777f67f26fb28e150be051ee0bf1cc7cd))
* **tts:** Kokoro-only policy with infinite re-sweep prevention ([94e1c19](https://github.com/terrylica/cc-skills/commit/94e1c19b6f2154193b9345cfe5f730ceb11fbe4c)), closes [hi#load](https://github.com/hi/issues/load)





---

## Documentation Changes

## Repository Documentation

### General Documentation

- [Cross-Link Validation Report](https://github.com/terrylica/cc-skills/blob/main/docs/cross-link-validation-report.md) - new (+109)

## Other Documentation

### Other

- [Task for crew-worker](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/artifacts/1d8a4502_crew-worker_0_input.md) - deleted
- [1d8a4502_crew-worker_0_output](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/artifacts/1d8a4502_crew-worker_0_output.md) - deleted
- [Task for crew-worker](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/artifacts/1d8a4502_crew-worker_1_input.md) - deleted
- [1d8a4502_crew-worker_1_output](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/artifacts/1d8a4502_crew-worker_1_output.md) - deleted
- [Task for crew-worker](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/artifacts/1d8a4502_crew-worker_2_input.md) - deleted
- [1d8a4502_crew-worker_2_output](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/artifacts/1d8a4502_crew-worker_2_output.md) - deleted
- [Task for crew-worker](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/artifacts/1d8a4502_crew-worker_3_input.md) - deleted
- [Task for crew-worker](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/artifacts/1d8a4502_crew-worker_4_input.md) - deleted
- [Task for crew-planner](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/artifacts/bfb3ee55_crew-planner_0_input.md) - deleted
- [bfb3ee55_crew-planner_0_output](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/artifacts/bfb3ee55_crew-planner_0_output.md) - deleted
- [plan](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/plan.md) - deleted
- [Planning Outline](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/planning-outline.md) - deleted
- [Planning Progress](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/planning-progress.md) - deleted
- [Task 1: Documentation Standards Audit](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/tasks/task-1.md) - deleted
- [task-1.progress](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/tasks/task-1.progress.md) - deleted
- [Task 2: Cross-Platform Format Analysis](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/tasks/task-2.md) - deleted
- [task-2.progress](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/tasks/task-2.progress.md) - deleted
- [Task 3: Toolchain & Automation Landscape](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/tasks/task-3.md) - deleted
- [task-3.progress](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/tasks/task-3.progress.md) - deleted
- [Task 4: Version Consistency Strategy](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/tasks/task-4.md) - deleted
- [task-4.progress](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/tasks/task-4.progress.md) - deleted
- [Task 5: Search & Discovery Architecture](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/tasks/task-5.md) - deleted
- [task-5.progress](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/tasks/task-5.progress.md) - deleted
- [Task 6: Content Deduplication Analysis](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/tasks/task-6.md) - deleted
- [task-6.progress](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/tasks/task-6.progress.md) - deleted
- [Task 7: Metadata & Linking Framework](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/tasks/task-7.md) - deleted
- [task-7.progress](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/tasks/task-7.progress.md) - deleted
- [Task 8: Accessibility & Findability Review](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/tasks/task-8.md) - deleted
- [task-8.progress](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/tasks/task-8.progress.md) - deleted
- [Task 9: Governance & Maintenance Model](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/tasks/task-9.md) - deleted
- [task-9.progress](https://github.com/terrylica/cc-skills/blob/v11.90.2/.pi/messenger/crew/tasks/task-9.progress.md) - deleted
- [media-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/media-tools/CLAUDE.md) - updated (+1/-1)

## [11.90.2](https://github.com/terrylica/cc-skills/compare/v11.90.1...v11.90.2) (2026-03-09)


### Bug Fixes

* **tts-telegram-sync:** Improve TTS pipeline robustness and performance ([963453e](https://github.com/terrylica/cc-skills/commit/963453e3bd6389611b6ef4ce307d0876fb7ada48))

## [11.90.1](https://github.com/terrylica/cc-skills/compare/v11.90.0...v11.90.1) (2026-03-08)


### Bug Fixes

* **gitnexus-tools:** Correct --repo flag documentation (optional not absent) ([ab3bd19](https://github.com/terrylica/cc-skills/commit/ab3bd19d971bfa6b79a45a8d33169dbce3ccfb6d))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gitnexus-tools</strong> (4 changes)</summary>

- [dead-code](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/dead-code/SKILL.md) - updated (+2/-8)
- [explore](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/explore/SKILL.md) - updated (+2/-8)
- [impact](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/impact/SKILL.md) - updated (+2/-8)
- [reindex](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/reindex/SKILL.md) - updated (+2/-8)

</details>


## Other Documentation

### Other

- [gitnexus-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/CLAUDE.md) - updated (+17/-11)

# [11.90.0](https://github.com/terrylica/cc-skills/compare/v11.89.0...v11.90.0) (2026-03-08)


### Bug Fixes

* **gitnexus-tools:** Add pre-flight check and remove phantom --repo flag ([b25fc7f](https://github.com/terrylica/cc-skills/commit/b25fc7fb0f3ca3546633f8977d8be571d8c0802d))


### Features

* **pueue:** add companion CLI tools section (noti, ntfy, mprocs, task-spooler) ([4b2da6d](https://github.com/terrylica/cc-skills/commit/4b2da6d44ff54509ebd16d4bbdd8d47743693dbc))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [pueue-job-orchestration](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/SKILL.md) - updated (+96/-1)

</details>

<details>
<summary><strong>gitnexus-tools</strong> (4 changes)</summary>

- [dead-code](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/dead-code/SKILL.md) - updated (+17/-11)
- [explore](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/explore/SKILL.md) - updated (+20/-15)
- [impact](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/impact/SKILL.md) - updated (+20/-15)
- [reindex](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/reindex/SKILL.md) - updated (+15/-9)

</details>


## Other Documentation

### Other

- [gitnexus-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/CLAUDE.md) - updated (+13/-12)

# [11.89.0](https://github.com/terrylica/cc-skills/compare/v11.88.0...v11.89.0) (2026-03-08)


### Bug Fixes

* **dotfiles-tools:** silence chezmoi guard for out-of-project drift ([b07e0fb](https://github.com/terrylica/cc-skills/commit/b07e0fbe76a927bb28db555345f6565ce3fee80c))
* **tts-telegram-sync:** Fix parseDecision multi-line truncation and iteration/runtime limits ([ef4bc04](https://github.com/terrylica/cc-skills/commit/ef4bc04c9f141bf812d54e6ac2c11747039c8597))


### Features

* **devops-tools:** Add mandatory Agent execution model to session-blind-spots ([7811f13](https://github.com/terrylica/cc-skills/commit/7811f133baa14f2baa5865e1d05d6a71ed7a3545))
* **dotfiles-tools:** add 4 workflows — forget, templates, safe update, doctor ([9c5eb9a](https://github.com/terrylica/cc-skills/commit/9c5eb9a003fe88dbc16a8a93e62e2b5cc7648a47))
* **gemini-deep-research:** migrate browser automation plugin from openclaw-zero-token ([6af5a1d](https://github.com/terrylica/cc-skills/commit/6af5a1d1a9dcde7d02da1a17a499dc8b7858b3e7))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [session-blind-spots](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-blind-spots/SKILL.md) - updated (+23/-1)

</details>

<details>
<summary><strong>dotfiles-tools</strong> (1 change)</summary>

- [chezmoi-workflows](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/skills/chezmoi-workflows/SKILL.md) - updated (+113/-8)

</details>

<details>
<summary><strong>gemini-deep-research</strong> (1 change)</summary>

- [gemini-deep-research](https://github.com/terrylica/cc-skills/blob/main/plugins/gemini-deep-research/skills/research/SKILL.md) - new (+176)

</details>


## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+8/-7)

## Other Documentation

### Other

- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (+28/-27)
- [gemini-deep-research Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gemini-deep-research/CLAUDE.md) - new (+74)

# [11.88.0](https://github.com/terrylica/cc-skills/compare/v11.87.1...v11.88.0) (2026-03-08)


### Features

* **tts-telegram-sync:** Restructure SWEEP_PROMPT into 5-step pipeline ([4ecfcce](https://github.com/terrylica/cc-skills/commit/4ecfcce8f26712fd1498f09a21c487b38f7e1762))

## [11.87.1](https://github.com/terrylica/cc-skills/compare/v11.87.0...v11.87.1) (2026-03-08)


### Bug Fixes

* **tts-telegram-sync:** Add yield-to-user detection and instruction sanitization to auto-continue ([4486c74](https://github.com/terrylica/cc-skills/commit/4486c740b0ee95e51828c577a320c5acd2efe21d))

# [11.87.0](https://github.com/terrylica/cc-skills/compare/v11.86.5...v11.87.0) (2026-03-08)


### Features

* **validation:** Detect shadow hooks in settings.json that duplicate cc-skills hooks ([b00723a](https://github.com/terrylica/cc-skills/commit/b00723a9a55abafbca42a87a5862ab9a49309660))

## [11.86.5](https://github.com/terrylica/cc-skills/compare/v11.86.4...v11.86.5) (2026-03-08)


### Bug Fixes

* **tts-telegram-sync:** Reset sweep_done on manual intervention in auto-continue hook ([9739cf1](https://github.com/terrylica/cc-skills/commit/9739cf1515c1a4f04914fcdfc1894e9a7d822f3b))

## [11.86.4](https://github.com/terrylica/cc-skills/compare/v11.86.3...v11.86.4) (2026-03-08)


### Bug Fixes

* **devops-tools:** Add concurrency control and retry logic to MiniMax calls ([20f0de6](https://github.com/terrylica/cc-skills/commit/20f0de64e749f36f8c0161bfeeffe35f6f48fb72))

## [11.86.3](https://github.com/terrylica/cc-skills/compare/v11.86.2...v11.86.3) (2026-03-08)


### Bug Fixes

* **devops-tools:** Add explicit instruction to never reduce --shots default ([80444f8](https://github.com/terrylica/cc-skills/commit/80444f8054c16499e88181f2d685b7e7607acd53))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [session-blind-spots](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-blind-spots/SKILL.md) - updated (+6/-9)

</details>

## [11.86.2](https://github.com/terrylica/cc-skills/compare/v11.86.1...v11.86.2) (2026-03-08)


### Bug Fixes

* **devops-tools:** Update SKILL.md examples to reflect 50-shot default ([8089b1b](https://github.com/terrylica/cc-skills/commit/8089b1b17656b636ca4e5568878fbb140b5ded14))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [session-blind-spots](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-blind-spots/SKILL.md) - updated (+4/-4)

</details>

## [11.86.1](https://github.com/terrylica/cc-skills/compare/v11.86.0...v11.86.1) (2026-03-08)


### Bug Fixes

* **devops-tools:** Harden session-blind-spots JSONL parsing for maximum lookback ([ce372b4](https://github.com/terrylica/cc-skills/commit/ce372b471bcf37b7f9bf1ae1d6e672ae5aa940b9))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [session-blind-spots](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-blind-spots/SKILL.md) - updated (+32/-15)

</details>

# [11.86.0](https://github.com/terrylica/cc-skills/compare/v11.85.0...v11.86.0) (2026-03-08)


### Features

* **devops-tools:** Expand session-blind-spots to 50 orthogonal perspectives ([b90cf51](https://github.com/terrylica/cc-skills/commit/b90cf5125567cd68c75df81f697cc91b8ac4e01e))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [session-blind-spots](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-blind-spots/SKILL.md) - updated (+56/-26)

</details>

# [11.85.0](https://github.com/terrylica/cc-skills/compare/v11.84.1...v11.85.0) (2026-03-08)


### Features

* **devops-tools:** Add session-blind-spots skill - MiniMax-powered consensus analysis ([69f5ccd](https://github.com/terrylica/cc-skills/commit/69f5ccdf61e8e49a5b8c12baeeb7416d7afe6fe8))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [session-blind-spots](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-blind-spots/SKILL.md) - new (+170)

</details>

## [11.84.1](https://github.com/terrylica/cc-skills/compare/v11.84.0...v11.84.1) (2026-03-08)


### Bug Fixes

* **tts-telegram-sync,gmail-commander:** update all log paths to centralized launchd-logs ([55741d6](https://github.com/terrylica/cc-skills/commit/55741d6ac4ff7893d1061f63862ef08aa1122a65))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gmail-commander</strong> (1 change)</summary>

- [bot-process-control](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/bot-process-control/SKILL.md) - updated (+9/-9)

</details>

<details>
<summary><strong>tts-telegram-sync</strong> (3 changes)</summary>

- [bot-process-control](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/bot-process-control/SKILL.md) - updated (+10/-10)
- [clean-component-removal](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/clean-component-removal/SKILL.md) - updated (+7/-6)
- [diagnostic-issue-resolver](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/diagnostic-issue-resolver/SKILL.md) - updated (+4/-3)

</details>


### Skill References

<details>
<summary><strong>tts-telegram-sync/bot-process-control</strong> (1 file)</summary>

- [Operational Commands](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/bot-process-control/references/operational-commands.md) - updated (+6/-6)

</details>

<details>
<summary><strong>tts-telegram-sync/diagnostic-issue-resolver</strong> (1 file)</summary>

- [Common Issues -- Expanded Diagnostic Procedures](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/diagnostic-issue-resolver/references/common-issues.md) - updated (+2/-2)

</details>

<details>
<summary><strong>tts-telegram-sync/settings-and-tuning</strong> (1 file)</summary>

- [Configuration Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/settings-and-tuning/references/config-reference.md) - updated (+1/-1)

</details>


## Other Documentation

### Other

- [Gmail Commander Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/CLAUDE.md) - updated (+10/-10)
- [tts-telegram-sync Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/CLAUDE.md) - updated (+12/-11)

# [11.84.0](https://github.com/terrylica/cc-skills/compare/v11.83.1...v11.84.0) (2026-03-08)


### Features

* **tts-telegram-sync:** centralize TTS server queue and update MiniMax label ([fd1a23a](https://github.com/terrylica/cc-skills/commit/fd1a23a90b2c6cc5fc5d754467080f5a2a53dbce))

## [11.83.1](https://github.com/terrylica/cc-skills/compare/v11.83.0...v11.83.1) (2026-03-07)


### Bug Fixes

* **gitnexus-tools:** Remove all hooks — invoke via skills only ([847eab9](https://github.com/terrylica/cc-skills/commit/847eab9012085796783bea0c97cb709dc85cd35e))

# [11.83.0](https://github.com/terrylica/cc-skills/compare/v11.82.0...v11.83.0) (2026-03-07)


### Bug Fixes

* **dotfiles-tools:** Scope chezmoi-stop-guard to session CWD ([12ce9a3](https://github.com/terrylica/cc-skills/commit/12ce9a3fb8bb0e94b1fe4663c369201ed3867bba))


### Features

* **tts-telegram-sync:** register auto-continue stop hook in hooks.json ([e6e6fd9](https://github.com/terrylica/cc-skills/commit/e6e6fd933aaf4dee6a6d4bd9a8dafe4d43209a92))

# [11.82.0](https://github.com/terrylica/cc-skills/compare/v11.81.0...v11.82.0) (2026-03-07)


### Features

* **dotfiles-tools:** Add plan mode bypass to chezmoi hooks ([2f7b14c](https://github.com/terrylica/cc-skills/commit/2f7b14cd5f2ab3fef596debaadca9677358c1d31))
* **gh-tools:** add issue-branch-PR lifecycle to issues-workflow skill ([8afec55](https://github.com/terrylica/cc-skills/commit/8afec55bd37d3b5165379f31b8313222dde6767e)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools) [owner/repo#N](https://github.com/owner/repo/issues/N)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [issues-workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issues-workflow/SKILL.md) - updated (+34/-1)

</details>


### Skill References

<details>
<summary><strong>gh-tools/issues-workflow</strong> (1 file)</summary>

- [Issue-Branch-PR Lifecycle Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issues-workflow/references/issue-branch-lifecycle.md) - new (+132)

</details>

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+90/-70)

</details>


## Other Documentation

### Other

- [gh-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/CLAUDE.md) - updated (+7/-7)

# [11.81.0](https://github.com/terrylica/cc-skills/compare/v11.80.0...v11.81.0) (2026-03-06)


### Features

* Refactor 13 skill descriptions to natural language format ([88516f7](https://github.com/terrylica/cc-skills/commit/88516f7f53dc3abc371a83eea0ede45ae4d7e5b9)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools)
* **skill-architecture:** Align with Anthropic skill-creator via 9-agent deep dive ([8b5da96](https://github.com/terrylica/cc-skills/commit/8b5da965ed565c70e9ca4073bed0f8bd1720ed8c))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (3 changes)</summary>

- [doppler-workflows](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/doppler-workflows/SKILL.md) - updated (+1/-1)
- [pueue-job-orchestration](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/SKILL.md) - updated (+1/-1)
- [session-recovery](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-recovery/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>doc-tools</strong> (1 change)</summary>

- [documentation-standards](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/documentation-standards/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>gh-tools</strong> (2 changes)</summary>

- [issue-create](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issue-create/SKILL.md) - updated (+1/-1)
- [issues-workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issues-workflow/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>itp</strong> (4 changes)</summary>

- [go](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/go/SKILL.md) - updated (+1/-1)
- [implement-plan-preflight](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/implement-plan-preflight/SKILL.md) - updated (+1/-1)
- [mise-configuration](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-configuration/SKILL.md) - updated (+1/-1)
- [mise-tasks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>plugin-dev</strong> (1 change)</summary>

- [skill-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/SKILL.md) - updated (+52/-2)

</details>

<details>
<summary><strong>quality-tools</strong> (1 change)</summary>

- [pre-ship-review](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/pre-ship-review/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>rust-tools</strong> (2 changes)</summary>

- [rust-dependency-audit](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-dependency-audit/SKILL.md) - updated (+1/-1)
- [rust-sota-arsenal](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/SKILL.md) - updated (+1/-1)

</details>


### Skill References

<details>
<summary><strong>asciinema-tools/asciinema-streaming-backup</strong> (1 file)</summary>

- [Setup Scripts](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/references/setup-scripts.md) - updated (+7)

</details>

<details>
<summary><strong>doc-tools/ascii-diagram-validator</strong> (2 files)</summary>

- [ASCII Alignment Checker - Integration Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/ascii-diagram-validator/references/INTEGRATION_GUIDE.md) - updated (+40)
- [ASCII Alignment Checker - Script Design Report](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/ascii-diagram-validator/references/SCRIPT_DESIGN_REPORT.md) - updated (+41)

</details>

<details>
<summary><strong>doc-tools/pandoc-pdf-generation</strong> (1 file)</summary>

- [LaTeX Parameters Reference for Pandoc](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/pandoc-pdf-generation/references/latex-parameters.md) - updated (+94/-2)

</details>

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+59)

</details>

<details>
<summary><strong>itp/mise-configuration</strong> (1 file)</summary>

- [mise [env] Code Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-configuration/references/patterns.md) - updated (+38)

</details>

<details>
<summary><strong>itp/mise-tasks</strong> (2 files)</summary>

- [Meta-Prompt: Autonomous Polyglot Monorepo Bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/references/bootstrap-monorepo.md) - updated (+47)
- [mise Tasks Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/references/patterns.md) - updated (+23)

</details>

<details>
<summary><strong>itp/semantic-release</strong> (2 files)</summary>

- [Python Projects Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/python.md) - updated (+32)
- [Troubleshooting](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/troubleshooting.md) - updated (+41)

</details>

<details>
<summary><strong>plugin-dev/skill-architecture</strong> (3 files)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/evolution-log.md) - updated (+27)
- [Script Design for Agentic Consumption](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/script-design.md) - new (+224)
- [Skill Writing Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/writing-guide.md) - new (+143)

</details>

<details>
<summary><strong>quant-research/adaptive-wfo-epoch</strong> (2 files)</summary>

- [Anti-Patterns: Adaptive Walk-Forward Epoch Selection](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/anti-patterns.md) - updated (+12)
- [Decision Tree: Adaptive Walk-Forward Epoch Selection](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/epoch-selection-decision-tree.md) - updated (+19)

</details>

<details>
<summary><strong>quant-research/rangebar-eval-metrics</strong> (1 file)</summary>

- [State-of-the-Art Methods (2025-2026)](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/references/sota-2025-2026.md) - updated (+26)

</details>

# [11.80.0](https://github.com/terrylica/cc-skills/compare/v11.79.2...v11.80.0) (2026-03-06)


### Features

* **rust-tools:** Complete 4-phase release pipeline with cargo-geiger, cargo-vet, cargo-hack integration ([efdf234](https://github.com/terrylica/cc-skills/commit/efdf2343b6cec270bd8b74b46de3243f7793c917)), closes [41-#51](https://github.com/41-/issues/51)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>rust-tools</strong> (2 changes)</summary>

- [rust-dependency-audit](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-dependency-audit/SKILL.md) - updated (+34)
- [rust-sota-arsenal](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/SKILL.md) - updated (+49)

</details>


### Skill References

<details>
<summary><strong>rust-tools/rust-dependency-audit</strong> (1 file)</summary>

- [cargo-geiger](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-dependency-audit/references/cargo-geiger-guide.md) - new (+179)

</details>

<details>
<summary><strong>rust-tools/rust-sota-arsenal</strong> (1 file)</summary>

- [cargo-hack Extended Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/references/cargo-hack-extended.md) - new (+218)

</details>


## Other Documentation

### Other

- [rust-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/CLAUDE.md) - updated (+27/-6)

## [11.79.2](https://github.com/terrylica/cc-skills/compare/v11.79.1...v11.79.2) (2026-03-06)


### Bug Fixes

* **itp-hooks:** Cap biome max-diagnostics to 20 to prevent timeout ([08268c6](https://github.com/terrylica/cc-skills/commit/08268c6d2d5219dd5f5b483ceff5a99cb05ab11b))

## [11.79.1](https://github.com/terrylica/cc-skills/compare/v11.79.0...v11.79.1) (2026-03-06)


### Bug Fixes

* **itp-hooks:** Fix tsgo basename collision, biome noise, and extension gaps ([4816da6](https://github.com/terrylica/cc-skills/commit/4816da6296fd331ddce7794abd719bc302832a52))

# [11.79.0](https://github.com/terrylica/cc-skills/compare/v11.78.0...v11.79.0) (2026-03-06)


### Features

* **itp-hooks:** Add tsgo, oxlint, and biome PostToolUse hooks for JS/TS files ([e2803e4](https://github.com/terrylica/cc-skills/commit/e2803e42f43a7c7436c06f19a28b43c19fa16d96)), closes [hi#performance](https://github.com/hi/issues/performance)





---

## Documentation Changes

## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+13/-10)

# [11.78.0](https://github.com/terrylica/cc-skills/compare/v11.77.8...v11.78.0) (2026-03-06)


### Features

* **itp-hooks:** Add ty type checker hook for Python files ([6335453](https://github.com/terrylica/cc-skills/commit/6335453c70c64f51c612b99da74c8c6151c3fee6))





---

## Documentation Changes

## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+1)

## [11.77.8](https://github.com/terrylica/cc-skills/compare/v11.77.7...v11.77.8) (2026-03-06)


### Bug Fixes

* **gitnexus-tools:** Add npx fallback for gitnexus CLI shim resolution ([6199591](https://github.com/terrylica/cc-skills/commit/61995911044c7749ecd9e520303aa15229e6d23b))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gitnexus-tools</strong> (4 changes)</summary>

- [dead-code](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/dead-code/SKILL.md) - updated (+11/-8)
- [explore](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/explore/SKILL.md) - updated (+13/-12)
- [impact](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/impact/SKILL.md) - updated (+14/-11)
- [reindex](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/reindex/SKILL.md) - updated (+10/-7)

</details>


## Other Documentation

### Other

- [gitnexus-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/CLAUDE.md) - updated (+11/-10)

## [11.77.7](https://github.com/terrylica/cc-skills/compare/v11.77.6...v11.77.7) (2026-03-06)

## [11.77.6](https://github.com/terrylica/cc-skills/compare/v11.77.5...v11.77.6) (2026-03-06)


### Bug Fixes

* **gitnexus-tools:** Remove Read from CLI reminder hook matcher ([5a63d30](https://github.com/terrylica/cc-skills/commit/5a63d305079ab7d333fbc3a7a9ad3858abe848a2))





---

## Documentation Changes

## Other Documentation

### Other

- [gitnexus-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/CLAUDE.md) - updated (+5/-5)

## [11.77.5](https://github.com/terrylica/cc-skills/compare/v11.77.4...v11.77.5) (2026-03-06)


### Bug Fixes

* **gitnexus-tools:** Auto-reindex when stale instead of suggesting manual reindex ([75f7f92](https://github.com/terrylica/cc-skills/commit/75f7f92dc3033138cb69b6d763e3424703bb6f4a))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gitnexus-tools</strong> (3 changes)</summary>

- [dead-code](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/dead-code/SKILL.md) - updated (+8/-2)
- [explore](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/explore/SKILL.md) - updated (+8/-2)
- [impact](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/impact/SKILL.md) - updated (+8/-2)

</details>

## [11.77.4](https://github.com/terrylica/cc-skills/compare/v11.77.3...v11.77.4) (2026-03-06)


### Bug Fixes

* **gitnexus-tools:** Add --repo flag to all skills and hooks for multi-repo support ([310b9bb](https://github.com/terrylica/cc-skills/commit/310b9bbe4974861b15ba8fdc3ce31483d257d6c0))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gitnexus-tools</strong> (4 changes)</summary>

- [dead-code](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/dead-code/SKILL.md) - updated (+13/-7)
- [explore](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/explore/SKILL.md) - updated (+19/-10)
- [impact](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/impact/SKILL.md) - updated (+17/-10)
- [reindex](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/reindex/SKILL.md) - updated (+12/-6)

</details>


## Repository Documentation

### General Documentation

- [Cargo TTY Suspension Prevention Hook](https://github.com/terrylica/cc-skills/blob/main/docs/cargo-tty-suspension-prevention.md) - updated (+58)
- [Lessons Learned](https://github.com/terrylica/cc-skills/blob/main/docs/LESSONS.md) - updated (+4)

## Other Documentation

### Other

- [gitnexus-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/CLAUDE.md) - updated (+15/-9)

## [11.77.3](https://github.com/terrylica/cc-skills/compare/v11.77.2...v11.77.3) (2026-03-05)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gitnexus-tools</strong> (4 changes)</summary>

- [dead-code](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/dead-code/SKILL.md) - updated (+6/-6)
- [explore](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/explore/SKILL.md) - updated (+9/-9)
- [impact](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/impact/SKILL.md) - updated (+9/-9)
- [reindex](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/reindex/SKILL.md) - updated (+5/-5)

</details>


## Other Documentation

### Other

- [gitnexus-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/CLAUDE.md) - updated (+11/-11)

## [11.77.2](https://github.com/terrylica/cc-skills/compare/v11.77.1...v11.77.2) (2026-03-05)


### Bug Fixes

* **itp-hooks:** Prevent pueue false positives and revert MCP stdin wrapping ([f920218](https://github.com/terrylica/cc-skills/commit/f9202184c7296eb242206dade09f4f317b678e42))

## [11.77.1](https://github.com/terrylica/cc-skills/compare/v11.77.0...v11.77.1) (2026-03-05)


### Bug Fixes

* **plugin-dev:** Escape dynamic context injection examples in skill-architecture ([c7db45d](https://github.com/terrylica/cc-skills/commit/c7db45dd6672640f9bf446fe28d5928d2e0d5eca))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>plugin-dev</strong> (1 change)</summary>

- [skill-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/SKILL.md) - updated (+7/-5)

</details>

# [11.77.0](https://github.com/terrylica/cc-skills/compare/v11.76.6...v11.77.0) (2026-03-04)


### Bug Fixes

* **mise:** Enable model invocation for run-full-release skill ([5e52cad](https://github.com/terrylica/cc-skills/commit/5e52cad3c875b64a6b9cedc72aeee5e5afea6565))


### Features

* **statusline-tools:** Reorganize status line layout with ❯ prefix and time consolidation ([33a87ce](https://github.com/terrylica/cc-skills/commit/33a87cea33a9eccd097b4ccbf91fa9d920ea3619))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>mise</strong> (1 change)</summary>

- [run-full-release](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/run-full-release/SKILL.md) - updated (-1)

</details>

## [11.76.6](https://github.com/terrylica/cc-skills/compare/v11.76.5...v11.76.6) (2026-03-04)


### Bug Fixes

* **itp-hooks:** Extend stdin inlet guard to protect MCP shell_execute calls ([8b01149](https://github.com/terrylica/cc-skills/commit/8b0114974cf8feff030a1534913e7b9b933fb1aa))

## [11.76.5](https://github.com/terrylica/cc-skills/compare/v11.76.4...v11.76.5) (2026-03-04)


### Bug Fixes

* **release:verify:** Handle enabledPlugins as object not array ([5a3e14c](https://github.com/terrylica/cc-skills/commit/5a3e14c3537fb33809220fa8d7292b5b5362f6ed))

## [11.76.4](https://github.com/terrylica/cc-skills/compare/v11.76.3...v11.76.4) (2026-03-04)


### Bug Fixes

* **release:** Prevent 'plugin failed to install' via cross-validation ([822b755](https://github.com/terrylica/cc-skills/commit/822b7550493919cf707744724e4efb5d92494bf3))

## [11.76.3](https://github.com/terrylica/cc-skills/compare/v11.76.2...v11.76.3) (2026-03-04)


### Bug Fixes

* **itp-hooks:** Prevent UV enforcement false positive on free-form text commands ([c8742ac](https://github.com/terrylica/cc-skills/commit/c8742acdfaead7aaf2a1722843ecfc809f1d4fbc))
* **itp-hooks:** Prevent UV reminder false positive on free-form text commands ([7025e2a](https://github.com/terrylica/cc-skills/commit/7025e2a49c616cc25fb44962e9f92ad4b9f520ac))

## [11.76.2](https://github.com/terrylica/cc-skills/compare/v11.76.1...v11.76.2) (2026-03-04)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (2 changes)</summary>

- [distributed-job-safety](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/SKILL.md) - updated (+20)
- [pueue-job-orchestration](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/SKILL.md) - updated (+39/-10)

</details>

## [11.76.1](https://github.com/terrylica/cc-skills/compare/v11.76.0...v11.76.1) (2026-03-04)


### Bug Fixes

* **plugin-dev:** Fix skill validator resilience and missing ansis dependency ([e1e0eb9](https://github.com/terrylica/cc-skills/commit/e1e0eb97c6cca03c676323772e8fe59777474bcf))

# [11.76.0](https://github.com/terrylica/cc-skills/compare/v11.75.1...v11.76.0) (2026-03-04)


### Bug Fixes

* **itp-hooks:** Prevent false positive pueue reminders on pueue management scripts ([b7cf962](https://github.com/terrylica/cc-skills/commit/b7cf96215677ade4d5073882117f397d9f1c5300))
* **itp-hooks:** Prevent wrapping of pueue management scripts ([6599611](https://github.com/terrylica/cc-skills/commit/6599611d053c08c09794932a2138f9c9a8b710d3)), closes [rangebar-py#77](https://github.com/rangebar-py/issues/77)


### Features

* **gh-tools:** add Discovery Provenance convention for issue creation ([f72c668](https://github.com/terrylica/cc-skills/commit/f72c6685f9b81cbeeacfae4fa73d13c31fca3937)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools)
* **mise:** add postflight phase to canonical release workflow (4→5 phases) ([6d9393e](https://github.com/terrylica/cc-skills/commit/6d9393ed89add2dc3a83d3725a31d4c3dd4ffc63))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>mise</strong> (1 change)</summary>

- [run-full-release](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/run-full-release/SKILL.md) - updated (+80/-16)

</details>


## Repository Documentation

### General Documentation

- [Release Workflow Guide](https://github.com/terrylica/cc-skills/blob/main/docs/RELEASE.md) - updated (+11/-9)

## Other Documentation

### Other

- [gh-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/CLAUDE.md) - updated (+46)

## [11.75.1](https://github.com/terrylica/cc-skills/compare/v11.75.0...v11.75.1) (2026-03-03)


### Bug Fixes

* **docs:** Update plugin counts and navigation to reflect 23 plugins ([d07bad0](https://github.com/terrylica/cc-skills/commit/d07bad073a677015df86808a80cba5f8fa263f85))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>mise</strong> (1 change)</summary>

- [run-full-release](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/run-full-release/SKILL.md) - updated (+22/-12)

</details>

# [11.75.0](https://github.com/terrylica/cc-skills/compare/v11.74.1...v11.75.0) (2026-03-03)


### Features

* **media-tools:** Add YouTube audio download and BookPlayer transfer plugin ([bb08831](https://github.com/terrylica/cc-skills/commit/bb0883107dab4e92f69d4d7b53ca72c0850e4366))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>media-tools</strong> (1 change)</summary>

- [youtube-to-bookplayer](https://github.com/terrylica/cc-skills/blob/main/plugins/media-tools/skills/youtube-to-bookplayer/SKILL.md) - new (+282)

</details>


### Skill References

<details>
<summary><strong>media-tools/youtube-to-bookplayer</strong> (3 files)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/media-tools/skills/youtube-to-bookplayer/references/evolution-log.md) - new (+21)
- [Tool Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/media-tools/skills/youtube-to-bookplayer/references/tool-reference.md) - new (+127)
- [Troubleshooting](https://github.com/terrylica/cc-skills/blob/main/plugins/media-tools/skills/youtube-to-bookplayer/references/troubleshooting.md) - new (+44)

</details>


## Other Documentation

### Other

- [media-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/media-tools/CLAUDE.md) - new (+41)

## [11.74.1](https://github.com/terrylica/cc-skills/compare/v11.74.0...v11.74.1) (2026-03-02)





---

## Documentation Changes

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+7/-7)
- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+1/-1)

### General Documentation

- [Session Resume Context](https://github.com/terrylica/cc-skills/blob/main/docs/RESUME.md) - updated (+2/-2)

## Other Documentation

### Other

- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (+3/-1)
- [kokoro-tts Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/CLAUDE.md) - updated (+1/-1)

# [11.74.0](https://github.com/terrylica/cc-skills/compare/v11.73.0...v11.74.0) (2026-03-02)


### Features

* **docs:** Add content deduplication analysis ([b80fa02](https://github.com/terrylica/cc-skills/commit/b80fa026afe79a5c4fc062be63c39ea09a47d837))
* **docs:** add governance model with ownership assignments ([932cb15](https://github.com/terrylica/cc-skills/commit/932cb15ae599496ed10c0207c3c35bf8510af632))
* **docs:** add governance-model.md ([ee758a3](https://github.com/terrylica/cc-skills/commit/ee758a33937c820a40881708b14318b3663341ec))
* **docs:** add metadata and linking framework ([d182889](https://github.com/terrylica/cc-skills/commit/d182889ce5dd52181921df54fabccd9253257e0e))





---

## Documentation Changes

## Repository Documentation

### General Documentation

- [Accessibility & Findability Review](https://github.com/terrylica/cc-skills/blob/main/docs/accessibility-findability-review.md) - new (+120)
- [Content Deduplication Analysis](https://github.com/terrylica/cc-skills/blob/main/docs/deduplication-analysis.md) - new (+239)
- [Search & Discovery Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/discovery-architecture.md) - new (+278)
- [Format Inventory: Cross-Platform Format Analysis](https://github.com/terrylica/cc-skills/blob/main/docs/format-inventory.md) - new (+225)
- [Governance & Maintenance Model](https://github.com/terrylica/cc-skills/blob/main/docs/governance-maintenance-model.md) - new (+329)
- [Governance & Maintenance Model](https://github.com/terrylica/cc-skills/blob/main/docs/governance-model.md) - new (+322)
- [Metadata & Linking Framework](https://github.com/terrylica/cc-skills/blob/main/docs/metadata-linking-framework.md) - new (+520)
- [Documentation Standards Compliance Matrix](https://github.com/terrylica/cc-skills/blob/main/docs/standards-compliance-matrix.md) - new (+252)
- [Toolchain & Automation Landscape](https://github.com/terrylica/cc-skills/blob/main/docs/tool-inventory.md) - new (+146)
- [Version Consistency Strategy](https://github.com/terrylica/cc-skills/blob/main/docs/version-consistency-strategy.md) - new (+179)

## Other Documentation

### Other

- [Task for crew-worker](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/artifacts/1d8a4502_crew-worker_0_input.md) - new (+138)
- [1d8a4502_crew-worker_0_output](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/artifacts/1d8a4502_crew-worker_0_output.md) - new (+28)
- [Task for crew-worker](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/artifacts/1d8a4502_crew-worker_1_input.md) - new (+138)
- [1d8a4502_crew-worker_1_output](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/artifacts/1d8a4502_crew-worker_1_output.md) - new (+37)
- [Task for crew-worker](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/artifacts/1d8a4502_crew-worker_2_input.md) - new (+149)
- [1d8a4502_crew-worker_2_output](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/artifacts/1d8a4502_crew-worker_2_output.md) - new (+22)
- [Task for crew-worker](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/artifacts/1d8a4502_crew-worker_3_input.md) - new (+148)
- [Task for crew-worker](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/artifacts/1d8a4502_crew-worker_4_input.md) - new (+148)
- [Task for crew-planner](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/artifacts/bfb3ee55_crew-planner_0_input.md) - new (+143)
- [bfb3ee55_crew-planner_0_output](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/artifacts/bfb3ee55_crew-planner_0_output.md) - new (+256)
- [plan](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/plan.md) - new (+256)
- [Planning Outline](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/planning-outline.md) - new (+252)
- [Planning Progress](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/planning-progress.md) - new (+267)
- [Task 1: Documentation Standards Audit](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/tasks/task-1.md) - new (+10)
- [task-1.progress](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/tasks/task-1.progress.md) - new (+3)
- [Task 2: Cross-Platform Format Analysis](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/tasks/task-2.md) - new (+11)
- [task-2.progress](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/tasks/task-2.progress.md) - new (+2)
- [Task 3: Toolchain & Automation Landscape](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/tasks/task-3.md) - new (+11)
- [task-3.progress](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/tasks/task-3.progress.md) - new (+1)
- [Task 4: Version Consistency Strategy](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/tasks/task-4.md) - new (+10)
- [task-4.progress](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/tasks/task-4.progress.md) - new (+3)
- [Task 5: Search & Discovery Architecture](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/tasks/task-5.md) - new (+11)
- [task-5.progress](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/tasks/task-5.progress.md) - new (+2)
- [Task 6: Content Deduplication Analysis](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/tasks/task-6.md) - new (+11)
- [task-6.progress](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/tasks/task-6.progress.md) - new (+1)
- [Task 7: Metadata & Linking Framework](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/tasks/task-7.md) - new (+5)
- [task-7.progress](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/tasks/task-7.progress.md) - new (+3)
- [Task 8: Accessibility & Findability Review](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/tasks/task-8.md) - new (+5)
- [task-8.progress](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/tasks/task-8.progress.md) - new (+1)
- [Task 9: Governance & Maintenance Model](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/tasks/task-9.md) - new (+5)
- [task-9.progress](https://github.com/terrylica/cc-skills/blob/main/.pi/messenger/crew/tasks/task-9.progress.md) - new (+2)
- [PRD: Align All Docs](https://github.com/terrylica/cc-skills/blob/main/PRD.md) - new (+120)

# [11.73.0](https://github.com/terrylica/cc-skills/compare/v11.72.0...v11.73.0) (2026-03-02)


### Features

* **devops-tools:** consolidate firecrawl skills into unified research-patterns skill ([cf105f8](https://github.com/terrylica/cc-skills/commit/cf105f8e0eec798af38a0e99602e8231c7635639))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [firecrawl-research-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/SKILL.md) - updated (+27/-4)

</details>


### Plugin READMEs

- [devops-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/README.md) - updated (+25/-25)

### Skill References

<details>
<summary><strong>devops-tools/firecrawl-research-patterns</strong> (7 files)</summary>

- [API Endpoint Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/api-endpoint-reference.md) - updated (+6/-6)
- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/evolution-log.md) - updated (+19)
- [Recursive Research Protocol](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/recursive-research-protocol.md) - updated (+1/-1)
- [Firecrawl Best Practices (Empirically Verified)](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/self-hosted-best-practices.md) - renamed from `plugins/devops-tools/skills/firecrawl-self-hosted/references/best-practices.md`
- [Firecrawl Bootstrap: Fresh Installation](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/self-hosted-bootstrap-guide.md) - renamed from `plugins/devops-tools/skills/firecrawl-self-hosted/references/bootstrap-guide.md`
- [Firecrawl Self-Hosted Operations](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/self-hosted-operations.md) - renamed from `plugins/devops-tools/skills/firecrawl-self-hosted/SKILL.md`
- [Firecrawl Troubleshooting](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/self-hosted-troubleshooting.md) - renamed from `plugins/devops-tools/skills/firecrawl-self-hosted/references/troubleshooting.md`

</details>

<details>
<summary><strong>devops-tools/firecrawl-self-hosted</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/v11.72.0/plugins/devops-tools/skills/firecrawl-self-hosted/references/evolution-log.md) - deleted

</details>


## Repository Documentation

### Root Documentation

- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+1/-1)

## Other Documentation

### Other

- [devops-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/CLAUDE.md) - updated (+20/-21)

# [11.72.0](https://github.com/terrylica/cc-skills/compare/v11.71.0...v11.72.0) (2026-03-02)


### Features

* **gh-tools:** document Playwright automation for GitHub Issue image uploads ([fcc7d6e](https://github.com/terrylica/cc-skills/commit/fcc7d6ed4e028d41168db4f08f1d8d32f8a38e86)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [issue-create](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issue-create/SKILL.md) - updated (+28/-7)

</details>


### Skill References

<details>
<summary><strong>gh-tools/issues-workflow</strong> (1 file)</summary>

- [GFM Anti-Patterns in Issue Comments](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issues-workflow/references/gfm-antipatterns.md) - updated (+2)

</details>

# [11.71.0](https://github.com/terrylica/cc-skills/compare/v11.70.0...v11.71.0) (2026-03-02)


### Features

* **rust-tools:** add Firecrawl scrape as WebFetch fallback ([e72e9d5](https://github.com/terrylica/cc-skills/commit/e72e9d52eb0ecc8092db5483493a6c836e78acae))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>rust-tools</strong> (2 changes)</summary>

- [rust-dependency-audit](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-dependency-audit/SKILL.md) - updated (+11)
- [rust-sota-arsenal](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/SKILL.md) - updated (+11)

</details>

# [11.70.0](https://github.com/terrylica/cc-skills/compare/v11.69.4...v11.70.0) (2026-03-02)


### Features

* **rust-tools:** add web-verify-first guidance to both skills ([5905d38](https://github.com/terrylica/cc-skills/commit/5905d38d24b49a2ce00e969745a171ccf83b21e0))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>rust-tools</strong> (2 changes)</summary>

- [rust-dependency-audit](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-dependency-audit/SKILL.md) - updated (+25/-1)
- [rust-sota-arsenal](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/SKILL.md) - updated (+27/-1)

</details>


### Skill References

<details>
<summary><strong>rust-tools/rust-sota-arsenal</strong> (1 file)</summary>

- [PyO3 Upgrade Guide: 0.22+](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/references/pyo3-upgrade-guide.md) - updated (+6)

</details>

## [11.69.4](https://github.com/terrylica/cc-skills/compare/v11.69.3...v11.69.4) (2026-03-02)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>rust-tools</strong> (2 changes)</summary>

- [rust-dependency-audit](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-dependency-audit/SKILL.md) - updated (+1/-1)
- [rust-sota-arsenal](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/SKILL.md) - updated (+34/-34)

</details>


### Skill References

<details>
<summary><strong>rust-tools/rust-dependency-audit</strong> (3 files)</summary>

- [cargo-audit](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-dependency-audit/references/cargo-audit-guide.md) - updated (+2/-2)
- [cargo-deny](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-dependency-audit/references/cargo-deny-guide.md) - updated (+2/-2)
- [Dependency Freshness: cargo-outdated and Alternatives](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-dependency-audit/references/cargo-outdated-guide.md) - updated (+5/-5)

</details>

<details>
<summary><strong>rust-tools/rust-sota-arsenal</strong> (5 files)</summary>

- [cargo-semver-checks](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/references/cargo-semver-checks.md) - updated (+4/-4)
- [cargo-wizard](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/references/cargo-wizard.md) - updated (+1/-1)
- [Benchmarking: divan and Criterion](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/references/divan-and-criterion.md) - updated (+12/-12)
- [macerator: Type-Generic SIMD](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/references/macerator-simd.md) - updated (+11/-11)
- [PyO3 Upgrade Guide: 0.22+](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/references/pyo3-upgrade-guide.md) - updated (+8/-9)

</details>


## Other Documentation

### Other

- [rust-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/CLAUDE.md) - updated (+7/-7)

## [11.69.3](https://github.com/terrylica/cc-skills/compare/v11.69.2...v11.69.3) (2026-03-02)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [issue-create](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issue-create/SKILL.md) - updated (+67/-11)

</details>

## [11.69.2](https://github.com/terrylica/cc-skills/compare/v11.69.1...v11.69.2) (2026-03-02)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [issue-create](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issue-create/SKILL.md) - updated (+47)

</details>


### Skill References

<details>
<summary><strong>gh-tools/issues-workflow</strong> (1 file)</summary>

- [GFM Anti-Patterns in Issue Comments](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issues-workflow/references/gfm-antipatterns.md) - updated (+63/-8)

</details>

## [11.69.1](https://github.com/terrylica/cc-skills/compare/v11.69.0...v11.69.1) (2026-03-02)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gmail-commander</strong> (1 change)</summary>

- [gmail-access](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/gmail-access/SKILL.md) - updated (+183/-34)

</details>

# [11.69.0](https://github.com/terrylica/cc-skills/compare/v11.68.1...v11.69.0) (2026-03-02)


### Features

* **rust-tools:** add SOTA Rust tooling plugin - 21 docs, 2 skills, once-per-session hook ([69843c8](https://github.com/terrylica/cc-skills/commit/69843c80df5fff8b3d460cf31f67a9ef78bb726a)), closes [#21](https://github.com/terrylica/cc-skills/issues/21)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>rust-tools</strong> (2 changes)</summary>

- [rust-dependency-audit](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-dependency-audit/SKILL.md) - new (+230)
- [rust-sota-arsenal](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/SKILL.md) - new (+287)

</details>


### Skill References

<details>
<summary><strong>rust-tools/rust-dependency-audit</strong> (5 files)</summary>

- [cargo-audit](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-dependency-audit/references/cargo-audit-guide.md) - new (+142)
- [cargo-deny](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-dependency-audit/references/cargo-deny-guide.md) - new (+223)
- [Dependency Freshness: cargo-outdated and Alternatives](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-dependency-audit/references/cargo-outdated-guide.md) - new (+169)
- [cargo-vet](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-dependency-audit/references/cargo-vet-guide.md) - new (+200)
- [Evolution Log: rust-dependency-audit](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-dependency-audit/references/evolution-log.md) - new (+9)

</details>

<details>
<summary><strong>rust-tools/rust-sota-arsenal</strong> (12 files)</summary>

- [ast-grep for Rust](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/references/ast-grep-rust.md) - new (+183)
- [cargo-hack](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/references/cargo-hack.md) - new (+145)
- [cargo-mutants](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/references/cargo-mutants.md) - new (+172)
- [cargo-nextest](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/references/cargo-nextest.md) - new (+196)
- [cargo-pgo](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/references/cargo-pgo.md) - new (+157)
- [cargo-semver-checks](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/references/cargo-semver-checks.md) - new (+124)
- [cargo-wizard](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/references/cargo-wizard.md) - new (+138)
- [Benchmarking: divan and Criterion](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/references/divan-and-criterion.md) - new (+247)
- [Evolution Log: rust-sota-arsenal](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/references/evolution-log.md) - new (+9)
- [macerator: Type-Generic SIMD](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/references/macerator-simd.md) - new (+202)
- [PyO3 Upgrade Guide: 0.22 → 0.28](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/references/pyo3-upgrade-guide.md) - new (+193)
- [samply: Interactive Rust Profiling](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/skills/rust-sota-arsenal/references/samply-profiling.md) - new (+193)

</details>


## Other Documentation

### Other

- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (+2/-1)
- [rust-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/rust-tools/CLAUDE.md) - new (+97)

## [11.68.1](https://github.com/terrylica/cc-skills/compare/v11.68.0...v11.68.1) (2026-03-02)


### Bug Fixes

* **gmail-commander:** cache app credentials to avoid 1Password call at runtime ([aab5a23](https://github.com/terrylica/cc-skills/commit/aab5a23ba60379c52a5e62b3bbcc67180299db2c))

# [11.68.0](https://github.com/terrylica/cc-skills/compare/v11.67.0...v11.68.0) (2026-03-02)


### Features

* **gmail-commander:** add inline image extraction and download capability to gmail-cli ([27a03b6](https://github.com/terrylica/cc-skills/commit/27a03b614445653bbf8ea41ff17b1e7de295e89e))

# [11.67.0](https://github.com/terrylica/cc-skills/compare/v11.66.1...v11.67.0) (2026-03-01)


### Features

* **itp-hooks:** add PreToolUse UV enforcement guard hook ([f9747f8](https://github.com/terrylica/cc-skills/commit/f9747f82330eecaeea6b805d8553858774f28a01))





---

## Documentation Changes

## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+1)

## [11.66.1](https://github.com/terrylica/cc-skills/compare/v11.66.0...v11.66.1) (2026-02-28)


### Bug Fixes

* **tts:** speak "∴ Thinking…" instead of stripping it ([dbbedec](https://github.com/terrylica/cc-skills/commit/dbbedeca2f97cc31975fff919dee7f9da0fb3324))

# [11.66.0](https://github.com/terrylica/cc-skills/compare/v11.65.2...v11.66.0) (2026-02-28)


### Features

* **plugins:** migrate to MLX-Audio backend, create universal kokoro-tts plugin ([62fa1ff](https://github.com/terrylica/cc-skills/commit/62fa1fff97da26b64a9cf945adb51c8991e43524))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>kokoro-tts</strong> (7 changes)</summary>

- [diagnose](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/diagnose/SKILL.md) - new (+68)
- [health](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/health/SKILL.md) - new (+44)
- [install](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/install/SKILL.md) - new (+67)
- [remove](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/remove/SKILL.md) - new (+59)
- [server](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/server/SKILL.md) - new (+66)
- [synthesize](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/synthesize/SKILL.md) - new (+65)
- [upgrade](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/upgrade/SKILL.md) - new (+66)

</details>

<details>
<summary><strong>tts-telegram-sync</strong> (7 changes)</summary>

- [component-version-upgrade](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/component-version-upgrade/SKILL.md) - updated (+2/-2)
- [diagnostic-issue-resolver](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/diagnostic-issue-resolver/SKILL.md) - updated (+13/-13)
- [full-stack-bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/full-stack-bootstrap/SKILL.md) - updated (+13/-13)
- [health](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/health/SKILL.md) - updated (+12/-12)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/setup/SKILL.md) - updated (+2/-2)
- [system-health-check](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/system-health-check/SKILL.md) - updated (+9/-9)
- [voice-quality-audition](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/voice-quality-audition/SKILL.md) - updated (+2/-2)

</details>


### Plugin READMEs

- [Kokoro TTS](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/README.md) - new (+69)
- [TTS Telegram Sync](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/README.md) - updated (+9/-9)

### Skill References

<details>
<summary><strong>kokoro-tts/diagnose</strong> (1 file)</summary>

- [Common Issues — Expanded Diagnostic Procedures](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/diagnose/references/common-issues.md) - new (+104)

</details>

<details>
<summary><strong>kokoro-tts/health</strong> (1 file)</summary>

- [Health Checks Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/health/references/health-checks.md) - new (+114)

</details>

<details>
<summary><strong>kokoro-tts/server</strong> (2 files)</summary>

- [Kokoro TTS Server API Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/server/references/server-api.md) - new (+92)
- [Service Management Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/server/references/service-management.md) - new (+77)

</details>

<details>
<summary><strong>kokoro-tts/synthesize</strong> (1 file)</summary>

- [Kokoro Voice Catalog](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/skills/synthesize/references/voice-catalog.md) - new (+48)

</details>

<details>
<summary><strong>tts-telegram-sync/component-version-upgrade</strong> (1 file)</summary>

- [Upgrade Procedures](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/component-version-upgrade/references/upgrade-procedures.md) - updated (+8/-7)

</details>

<details>
<summary><strong>tts-telegram-sync/diagnostic-issue-resolver</strong> (1 file)</summary>

- [Common Issues -- Expanded Diagnostic Procedures](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/diagnostic-issue-resolver/references/common-issues.md) - updated (+16/-13)

</details>

<details>
<summary><strong>tts-telegram-sync/full-stack-bootstrap</strong> (2 files)</summary>

- [Kokoro TTS Engine Bootstrap Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/full-stack-bootstrap/references/kokoro-bootstrap.md) - updated (+33/-45)
- [Upstream: MLX-Audio Kokoro](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/full-stack-bootstrap/references/upstream-fork.md) - updated (+31/-28)

</details>

<details>
<summary><strong>tts-telegram-sync/system-health-check</strong> (1 file)</summary>

- [Health Checks Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/system-health-check/references/health-checks.md) - updated (+13/-17)

</details>


## Other Documentation

### Other

- [kokoro-tts Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/kokoro-tts/CLAUDE.md) - new (+57)
- [tts-telegram-sync Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/CLAUDE.md) - updated (+3/-3)

## [11.65.2](https://github.com/terrylica/cc-skills/compare/v11.65.1...v11.65.2) (2026-02-28)


### Bug Fixes

* **gh-tools:** remove gh-issue-body-file-guard — premise disproved ([88bfc21](https://github.com/terrylica/cc-skills/commit/88bfc21b3e72db124e781475dc93eab4492a1837)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools) [#issue-body-file-guard](https://github.com/terrylica/cc-skills/issues/issue-body-file-guard)





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| superseded | [gh issue create --body-file Requirement](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-11-gh-issue-body-file-guard.md) | updated (+27/-35) |

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (3 changes)</summary>

- [issue-create](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issue-create/SKILL.md) - updated (-4)
- [issues-workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issues-workflow/SKILL.md) - updated (+9/-9)
- [research-archival](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/research-archival/SKILL.md) - updated (+4/-4)

</details>


### Plugin READMEs

- [gh-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/README.md) - updated (+14/-38)

### Skill References

<details>
<summary><strong>gh-tools/issues-workflow</strong> (1 file)</summary>

- [GFM Anti-Patterns in Issue Comments](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issues-workflow/references/gfm-antipatterns.md) - updated (+10/-12)

</details>

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+7/-7)

</details>


## Repository Documentation

### General Documentation

- [Hooks Development Guide](https://github.com/terrylica/cc-skills/blob/main/docs/HOOKS.md) - updated (+2/-2)

## Other Documentation

### Other

- [gh-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/CLAUDE.md) - updated (+4/-14)

## [11.65.1](https://github.com/terrylica/cc-skills/compare/v11.65.0...v11.65.1) (2026-02-28)

# [11.65.0](https://github.com/terrylica/cc-skills/compare/v11.64.0...v11.65.0) (2026-02-28)


### Features

* **itp-hooks:** add Zod schema registry for input validation ([f1dfa87](https://github.com/terrylica/cc-skills/commit/f1dfa8741a447d1bb297606699486025070c7157)), closes [#13439](https://github.com/terrylica/cc-skills/issues/13439)

# [11.64.0](https://github.com/terrylica/cc-skills/compare/v11.63.1...v11.64.0) (2026-02-28)


### Features

* **itp-hooks:** universal SSoT/DI principles hook with ast-grep detection ([82254fb](https://github.com/terrylica/cc-skills/commit/82254fb51b36a4c23118ae41e95c35c37703ab7e)), closes [terrylica/cc-skills#28](https://github.com/terrylica/cc-skills/issues/28)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (2 changes)</summary>

- [code-hardcode-audit](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/code-hardcode-audit/SKILL.md) - updated (+12/-8)
- [impl-standards](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/impl-standards/SKILL.md) - updated (+3/-1)

</details>


### Skill References

<details>
<summary><strong>itp/impl-standards</strong> (1 file)</summary>

- [SSoT / Dependency Injection Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/impl-standards/references/ssot-dependency-injection.md) - new (+195)

</details>


## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+40/-8)

## [11.63.1](https://github.com/terrylica/cc-skills/compare/v11.63.0...v11.63.1) (2026-02-28)


### Bug Fixes

* **itp-hooks:** fix AskUserQuestion corruption from stdin-inlet-guard ([e4cdc8a](https://github.com/terrylica/cc-skills/commit/e4cdc8a451392322eff18a3bb86886dd9515d50b)), closes [#13439](https://github.com/terrylica/cc-skills/issues/13439) [#10400](https://github.com/terrylica/cc-skills/issues/10400)

# [11.63.0](https://github.com/terrylica/cc-skills/compare/v11.62.5...v11.63.0) (2026-02-28)


### Features

* **statusline:** separate Cast UUID to own line with path prefix ([18e28d6](https://github.com/terrylica/cc-skills/commit/18e28d6bd969954f4c147efb8013b5c194be124f))

## [11.62.5](https://github.com/terrylica/cc-skills/compare/v11.62.4...v11.62.5) (2026-02-28)


### Bug Fixes

* **gitnexus-tools:** remove non-existent --repo flag from all CLI examples ([bd9a788](https://github.com/terrylica/cc-skills/commit/bd9a788370dfcb6292da56df7216a84e0fb8161f))
* **tts:** unify lock protocol — tts_read_clipboard uses shared kokoro-tts.lock ([15deb40](https://github.com/terrylica/cc-skills/commit/15deb4071df875fe61b0acca6e02f1abc492fdf5))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gitnexus-tools</strong> (4 changes)</summary>

- [dead-code](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/dead-code/SKILL.md) - updated (+10/-16)
- [explore](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/explore/SKILL.md) - updated (+14/-21)
- [impact](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/impact/SKILL.md) - updated (+15/-22)
- [reindex](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/reindex/SKILL.md) - updated (+16/-22)

</details>


## Other Documentation

### Other

- [gitnexus-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/CLAUDE.md) - updated (+12/-12)

## [11.62.4](https://github.com/terrylica/cc-skills/compare/v11.62.3...v11.62.4) (2026-02-28)


### Bug Fixes

* **gitnexus-tools:** add CLI ONLY warning to skill description frontmatter ([9f6c7c3](https://github.com/terrylica/cc-skills/commit/9f6c7c30db4644dd0804209e66ab7e03beac9e72))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gitnexus-tools</strong> (4 changes)</summary>

- [dead-code](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/dead-code/SKILL.md) - updated (+1/-1)
- [explore](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/explore/SKILL.md) - updated (+1/-1)
- [impact](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/impact/SKILL.md) - updated (+1/-1)
- [reindex](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/reindex/SKILL.md) - updated (+1/-1)

</details>

## [11.62.3](https://github.com/terrylica/cc-skills/compare/v11.62.2...v11.62.3) (2026-02-28)


### Bug Fixes

* **gitnexus-tools:** resolve cwd from process.cwd() when file_path is outside repo ([696b18a](https://github.com/terrylica/cc-skills/commit/696b18abc36cd306ce0f8b76b1328470053c89a4))

## [11.62.2](https://github.com/terrylica/cc-skills/compare/v11.62.1...v11.62.2) (2026-02-28)


### Bug Fixes

* **gitnexus-tools:** strengthen MCP prohibition and document --repo flag ([2cd0905](https://github.com/terrylica/cc-skills/commit/2cd0905edd1c8e6a841b58b55d2c112ad8dcd2ef))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gitnexus-tools</strong> (4 changes)</summary>

- [dead-code](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/dead-code/SKILL.md) - updated (+19/-9)
- [explore](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/explore/SKILL.md) - updated (+24/-13)
- [impact](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/impact/SKILL.md) - updated (+25/-14)
- [reindex](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/reindex/SKILL.md) - updated (+18/-8)

</details>


## Other Documentation

### Other

- [gitnexus-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/CLAUDE.md) - updated (+13/-8)

## [11.62.1](https://github.com/terrylica/cc-skills/compare/v11.62.0...v11.62.1) (2026-02-28)


### Bug Fixes

* **gitnexus-tools:** replace broken PreToolUse MCP hook with PostToolUse CLI reminder ([74f5a89](https://github.com/terrylica/cc-skills/commit/74f5a89ec124c9868b10d5ed7befc272c562c5be))





---

## Documentation Changes

## Other Documentation

### Other

- [gitnexus-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/CLAUDE.md) - updated (+7/-7)

# [11.62.0](https://github.com/terrylica/cc-skills/compare/v11.61.2...v11.62.0) (2026-02-28)


### Features

* **gitnexus-tools:** add PreToolUse hook to redirect MCP calls to CLI ([d098751](https://github.com/terrylica/cc-skills/commit/d098751ae2c8ccbf28beee7e55b75247e6507ed0))





---

## Documentation Changes

## Other Documentation

### Other

- [gitnexus-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/CLAUDE.md) - updated (+9/-4)

## [11.61.2](https://github.com/terrylica/cc-skills/compare/v11.61.1...v11.61.2) (2026-02-28)


### Bug Fixes

* **statusline,pueue:** prevent /tmp file proliferation and SSH double-wrapping ([4465bb9](https://github.com/terrylica/cc-skills/commit/4465bb9684f9c0df88835cba4060ad782f18d7d9))

## [11.61.1](https://github.com/terrylica/cc-skills/compare/v11.61.0...v11.61.1) (2026-02-28)


### Bug Fixes

* **itp-hooks:** exclude /tmp/ from version guard to allow gh issue body files ([d007561](https://github.com/terrylica/cc-skills/commit/d007561e56a1b8f45436a85323265d2af8ff67c1))

# [11.61.0](https://github.com/terrylica/cc-skills/compare/v11.60.0...v11.61.0) (2026-02-28)


### Features

* **gitnexus-tools:** GitNexus knowledge graph skills and staleness hooks ([7d58c1f](https://github.com/terrylica/cc-skills/commit/7d58c1ff4126f556c24059b8526a9197c525c584))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gitnexus-tools</strong> (4 changes)</summary>

- [dead-code](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/dead-code/SKILL.md) - new (+107)
- [explore](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/explore/SKILL.md) - new (+83)
- [impact](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/impact/SKILL.md) - new (+91)
- [reindex](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/skills/reindex/SKILL.md) - new (+72)

</details>


## Other Documentation

### Other

- [gitnexus-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gitnexus-tools/CLAUDE.md) - new (+71)

# [11.60.0](https://github.com/terrylica/cc-skills/compare/v11.59.3...v11.60.0) (2026-02-27)


### Bug Fixes

* add missing allowed-tools to setup and health skills ([cdf0422](https://github.com/terrylica/cc-skills/commit/cdf042286804d7ff46e8b04bd02bda05f54961b7))
* **itp-hooks:** stop UV reminder from triggering on uv pip/venv commands ([9d2d715](https://github.com/terrylica/cc-skills/commit/9d2d7156422fc0e210de93a62d41b2b54c93aa46))


### Features

* add evolution-log.md to all 152 skills for self-improvement tracking ([23228c3](https://github.com/terrylica/cc-skills/commit/23228c3485d9cab54b591b41c53ea05ef47b5c59))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>calcom-commander</strong> (2 changes)</summary>

- [health](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/health/SKILL.md) - updated (+1)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/setup/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>gmail-commander</strong> (2 changes)</summary>

- [health](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/health/SKILL.md) - updated (+1)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/setup/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>mise</strong> (1 change)</summary>

- [run-full-release](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/run-full-release/SKILL.md) - updated (+57/-49)

</details>

<details>
<summary><strong>tts-telegram-sync</strong> (1 change)</summary>

- [bot-process-control](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/bot-process-control/SKILL.md) - updated (+20/-11)

</details>


### Skill References

<details>
<summary><strong>asciinema-tools/analyze</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/analyze/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/asciinema-analyzer</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-analyzer/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/asciinema-cast-format</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-cast-format/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/asciinema-converter</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-converter/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/asciinema-player</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-player/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/asciinema-recorder</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-recorder/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/asciinema-streaming-backup</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/backup</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/backup/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/bootstrap</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/bootstrap/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/convert</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/convert/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/daemon-logs</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-logs/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/daemon-setup</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-setup/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/daemon-start</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-start/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/daemon-status</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-status/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/daemon-stop</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-stop/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/finalize</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/finalize/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/format</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/format/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/full-workflow</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/full-workflow/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/hooks</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/hooks/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/play</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/play/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/post-session</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/post-session/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/record</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/record/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/setup</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/setup/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>asciinema-tools/summarize</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/summarize/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>calcom-commander/booking-config</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/booking-config/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>calcom-commander/booking-notify</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/booking-notify/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>calcom-commander/calcom-access</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/calcom-access/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>calcom-commander/health</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/health/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>calcom-commander/infra-deploy</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/infra-deploy/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>calcom-commander/setup</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/setup/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>devops-tools/clickhouse-cloud-management</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/clickhouse-cloud-management/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>devops-tools/clickhouse-pydantic-config</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/clickhouse-pydantic-config/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>devops-tools/distributed-job-safety</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>devops-tools/doppler-secret-validation</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/doppler-secret-validation/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>devops-tools/doppler-workflows</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/doppler-workflows/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>devops-tools/dual-channel-watchexec</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/dual-channel-watchexec/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>devops-tools/dual-channel-watchexec-notifications</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/dual-channel-watchexec-notifications/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>devops-tools/firecrawl-research-patterns</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>devops-tools/firecrawl-self-hosted</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-self-hosted/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>devops-tools/ml-data-pipeline-architecture</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/ml-data-pipeline-architecture/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>devops-tools/ml-failfast-validation</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/ml-failfast-validation/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>devops-tools/mlflow-python</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/mlflow-python/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>devops-tools/pueue-job-orchestration</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>devops-tools/python-logging-best-practices</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/python-logging-best-practices/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>devops-tools/session-chronicle</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>devops-tools/session-recovery</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-recovery/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>devops-tools/worktree-manager</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/worktree-manager/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>doc-tools/ascii-diagram-validator</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/ascii-diagram-validator/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>doc-tools/documentation-standards</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/documentation-standards/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>doc-tools/glossary-management</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/glossary-management/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>doc-tools/latex-build</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-build/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>doc-tools/latex-setup</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-setup/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>doc-tools/latex-tables</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-tables/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>doc-tools/pandoc-pdf-generation</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/pandoc-pdf-generation/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>doc-tools/plotext-financial-chart</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/plotext-financial-chart/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>doc-tools/terminal-print</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/terminal-print/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>dotfiles-tools/chezmoi-workflows</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/skills/chezmoi-workflows/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>dotfiles-tools/hooks</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/skills/hooks/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>gh-tools/hooks</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/hooks/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>gh-tools/issue-create</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issue-create/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>gh-tools/issues-workflow</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issues-workflow/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>gh-tools/pr-gfm-validator</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/pr-gfm-validator/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>git-town-workflow/contribute</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/skills/contribute/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>git-town-workflow/fork</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/skills/fork/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>git-town-workflow/hooks</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/skills/hooks/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>git-town-workflow/setup</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/skills/setup/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>gmail-commander/bot-process-control</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/bot-process-control/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>gmail-commander/email-triage</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/email-triage/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>gmail-commander/health</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/health/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>gmail-commander/interactive-bot</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/interactive-bot/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>gmail-commander/setup</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/setup/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>itp-hooks/setup</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/setup/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>itp/adr-code-traceability</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/adr-code-traceability/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>itp/adr-graph-easy-architect</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/adr-graph-easy-architect/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>itp/bootstrap-monorepo</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/bootstrap-monorepo/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>itp/code-hardcode-audit</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/code-hardcode-audit/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>itp/go</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/go/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>itp/graph-easy</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/graph-easy/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>itp/hooks</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/hooks/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>itp/impl-standards</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/impl-standards/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>itp/implement-plan-preflight</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/implement-plan-preflight/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>itp/mise-configuration</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-configuration/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>itp/mise-tasks</strong> (2 files)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/references/evolution-log.md) - new (+26)
- [Release Workflow Patterns for mise Tasks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/references/release-workflow-patterns.md) - updated (+68)

</details>

<details>
<summary><strong>itp/pypi-doppler</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/pypi-doppler/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>itp/release</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/release/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>itp/setup</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/setup/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>link-tools/link-validation</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/skills/link-validation/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>link-tools/link-validator</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/skills/link-validator/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>mise/list-repo-tasks</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/list-repo-tasks/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>mise/run-full-release</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/run-full-release/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>mise/show-env-status</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/show-env-status/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>mise/sred-commit</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/sred-commit/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>mql5/article-extractor</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/article-extractor/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>mql5/log-reader</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/log-reader/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>mql5/mql5-indicator-patterns</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/mql5-indicator-patterns/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>mql5/python-workspace</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/python-workspace/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>plugin-dev/create</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/create/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>plugin-dev/plugin-validator</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/plugin-validator/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>productivity-tools/calendar-event-manager</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/calendar-event-manager/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>productivity-tools/gdrive-access</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/gdrive-access/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>productivity-tools/hooks</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/hooks/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>productivity-tools/iterm2-layout</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/iterm2-layout/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>productivity-tools/notion-sdk</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/notion-sdk/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>productivity-tools/slash-command-factory</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/slash-command-factory/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>quality-tools/alpha-forge-preship</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/alpha-forge-preship/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>quality-tools/clickhouse-architect</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/clickhouse-architect/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>quality-tools/code-clone-assistant</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/code-clone-assistant/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>quality-tools/dead-code-detector</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/dead-code-detector/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>quality-tools/multi-agent-e2e-validation</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/multi-agent-e2e-validation/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>quality-tools/multi-agent-performance-profiling</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/multi-agent-performance-profiling/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>quality-tools/schema-e2e-validation</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/schema-e2e-validation/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>quant-research/adaptive-wfo-epoch</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>quant-research/backtesting-py-oracle</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/backtesting-py-oracle/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>quant-research/evolutionary-metric-ranking</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/evolutionary-metric-ranking/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>quant-research/rangebar-eval-metrics</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>ru/audit-now</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/audit-now/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>ru/config</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/config/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>ru/encourage</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/encourage/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>ru/forbid</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/forbid/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>ru/hooks</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/hooks/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>ru/start</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/start/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>ru/status</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/status/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>ru/stop</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/stop/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>ru/wizard</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/wizard/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>statusline-tools/hooks</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/hooks/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>statusline-tools/ignore</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/ignore/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>statusline-tools/session-info</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/session-info/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>statusline-tools/setup</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/setup/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>tts-telegram-sync/bot-process-control</strong> (2 files)</summary>

- [Operational Commands](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/bot-process-control/references/operational-commands.md) - updated (+36/-34)
- [Process Tree](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/bot-process-control/references/process-tree.md) - updated (+19/-4)

</details>

<details>
<summary><strong>tts-telegram-sync/health</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/health/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>tts-telegram-sync/hooks</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/hooks/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>tts-telegram-sync/setup</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/setup/references/evolution-log.md) - new (+26)

</details>


## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+22)
- [tts-telegram-sync Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/CLAUDE.md) - updated (+6)

## [11.59.3](https://github.com/terrylica/cc-skills/compare/v11.59.2...v11.59.3) (2026-02-26)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>asciinema-tools</strong> (8 changes)</summary>

- [asciinema-converter](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-converter/SKILL.md) - updated (+25/-435)
- [asciinema-streaming-backup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/SKILL.md) - updated (+50/-894)
- [bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/bootstrap/SKILL.md) - updated (+1)
- [daemon-setup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-setup/SKILL.md) - updated (+28/-473)
- [daemon-start](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-start/SKILL.md) - updated (+1)
- [daemon-stop](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-stop/SKILL.md) - updated (+1)
- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/hooks/SKILL.md) - updated (+1)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/setup/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>calcom-commander</strong> (2 changes)</summary>

- [infra-deploy](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/infra-deploy/SKILL.md) - updated (+1)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/setup/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>devops-tools</strong> (7 changes)</summary>

- [claude-code-proxy-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/claude-code-proxy-patterns/SKILL.md) - updated (+12/-300)
- [cloudflare-workers-publish](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/cloudflare-workers-publish/SKILL.md) - updated (+2/-4)
- [distributed-job-safety](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/SKILL.md) - updated (+39/-400)
- [dual-channel-watchexec](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/dual-channel-watchexec/SKILL.md) - updated (+1/-1)
- [firecrawl-self-hosted](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-self-hosted/SKILL.md) - updated (+4/-380)
- [pueue-job-orchestration](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/SKILL.md) - updated (+16/-855)
- [session-chronicle](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/SKILL.md) - updated (+37/-502)

</details>

<details>
<summary><strong>doc-tools</strong> (1 change)</summary>

- [latex-setup](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-setup/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>dotfiles-tools</strong> (1 change)</summary>

- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/skills/hooks/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/hooks/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>git-town-workflow</strong> (2 changes)</summary>

- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/skills/hooks/SKILL.md) - updated (+1)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/skills/setup/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>gmail-commander</strong> (1 change)</summary>

- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/setup/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>itp</strong> (11 changes)</summary>

- [adr-graph-easy-architect](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/adr-graph-easy-architect/SKILL.md) - updated (+78/-483)
- [bootstrap-monorepo](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/bootstrap-monorepo/SKILL.md) - updated (+1)
- [go](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/go/SKILL.md) - updated (+34/-490)
- [graph-easy](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/graph-easy/SKILL.md) - updated (+73/-501)
- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/hooks/SKILL.md) - updated (+1)
- [mise-configuration](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-configuration/SKILL.md) - updated (+65/-416)
- [mise-tasks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/SKILL.md) - updated (+31/-530)
- [pypi-doppler](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/pypi-doppler/SKILL.md) - updated (+25/-389)
- [release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/release/SKILL.md) - updated (+1)
- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/SKILL.md) - updated (+1)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/setup/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>itp-hooks</strong> (1 change)</summary>

- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/setup/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>mise</strong> (2 changes)</summary>

- [run-full-release](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/run-full-release/SKILL.md) - updated (+1)
- [sred-commit](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/sred-commit/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>plugin-dev</strong> (2 changes)</summary>

- [create](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/create/SKILL.md) - updated (+27/-384)
- [skill-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/SKILL.md) - updated (+44/-304)

</details>

<details>
<summary><strong>productivity-tools</strong> (2 changes)</summary>

- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/hooks/SKILL.md) - updated (+1)
- [slash-command-factory](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/slash-command-factory/SKILL.md) - updated (+92/-1084)

</details>

<details>
<summary><strong>quant-research</strong> (1 change)</summary>

- [adaptive-wfo-epoch](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/SKILL.md) - updated (+38/-1298)

</details>

<details>
<summary><strong>ru</strong> (3 changes)</summary>

- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/hooks/SKILL.md) - updated (+1)
- [start](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/start/SKILL.md) - updated (+1)
- [stop](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/stop/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>statusline-tools</strong> (2 changes)</summary>

- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/hooks/SKILL.md) - updated (+1)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/setup/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>tts-telegram-sync</strong> (5 changes)</summary>

- [clean-component-removal](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/clean-component-removal/SKILL.md) - updated (+1)
- [component-version-upgrade](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/component-version-upgrade/SKILL.md) - updated (+1)
- [full-stack-bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/full-stack-bootstrap/SKILL.md) - updated (+1)
- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/hooks/SKILL.md) - updated (+1)
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/setup/SKILL.md) - updated (+1)

</details>


### Skill References

<details>
<summary><strong>asciinema-tools/asciinema-converter</strong> (4 files)</summary>

- [Batch Mode Workflow (Phases 7-10)](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-converter/references/batch-workflow.md) - new (+147)
- [Post-Change Checklist](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-converter/references/post-change-checklist.md) - new (+20)
- [TodoWrite Task Templates](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-converter/references/task-templates.md) - new (+28)
- [Workflow Phases (Single File Mode)](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-converter/references/workflow-phases.md) - new (+240)

</details>

<details>
<summary><strong>asciinema-tools/asciinema-streaming-backup</strong> (7 files)</summary>

- [Account & Repository Detection](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/references/account-detection.md) - new (+181)
- [Autonomous Validation Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/references/autonomous-validation.md) - updated (+2)
- [Configuration Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/references/configuration-reference.md) - new (+250)
- [GitHub Actions Workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/references/github-workflow.md) - updated (+2)
- [Idle Chunker Script (DEPRECATED)](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/references/idle-chunker.md) - updated (+2)
- [Setup Scripts](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/references/setup-scripts.md) - updated (+2)
- [Troubleshooting Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/references/troubleshooting.md) - new (+75)

</details>

<details>
<summary><strong>asciinema-tools/daemon-setup</strong> (4 files)</summary>

- [launchd Installation Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-setup/references/launchd-installation.md) - new (+142)
- [GitHub PAT Setup Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-setup/references/pat-setup-guide.md) - new (+135)
- [Pushover Setup Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-setup/references/pushover-setup-guide.md) - new (+124)
- [Verification and Troubleshooting](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-setup/references/verification-and-troubleshooting.md) - new (+100)

</details>

<details>
<summary><strong>devops-tools/claude-code-proxy-patterns</strong> (3 files)</summary>

- [Launchd Service Configuration](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/claude-code-proxy-patterns/references/launchd-configuration.md) - new (+136)
- [OAuth Token Auto-Refresh](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/claude-code-proxy-patterns/references/oauth-auto-refresh.md) - new (+59)
- [TodoWrite Task Templates](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/claude-code-proxy-patterns/references/task-templates.md) - new (+43)

</details>

<details>
<summary><strong>devops-tools/distributed-job-safety</strong> (3 files)</summary>

- [Anti-Patterns (Learned from Production)](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/references/anti-patterns.md) - new (+317)
- [Autoscaler](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/references/autoscaler.md) - new (+54)
- [The Mise + Pueue + systemd-run Stack](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/references/stack-architecture.md) - new (+40)

</details>

<details>
<summary><strong>devops-tools/firecrawl-self-hosted</strong> (3 files)</summary>

- [Firecrawl Best Practices (Empirically Verified)](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-self-hosted/references/best-practices.md) - new (+70)
- [Firecrawl Bootstrap: Fresh Installation](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-self-hosted/references/bootstrap-guide.md) - new (+212)
- [Firecrawl Troubleshooting](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-self-hosted/references/troubleshooting.md) - new (+103)

</details>

<details>
<summary><strong>devops-tools/pueue-job-orchestration</strong> (8 files)</summary>

- [Callback Hooks & Scheduling](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/references/callbacks-and-scheduling.md) - new (+86)
- [Claude Code + Pueue Integration Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/references/claude-code-integration.md) - updated (+2)
- [ClickHouse Parallelism Tuning (pueue + ClickHouse)](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/references/clickhouse-tuning.md) - new (+66)
- [Environment Variables & Secrets for Pueue Jobs](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/references/environment-secrets.md) - new (+81)
- [Installation Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/references/installation-guide.md) - new (+95)
- [Production Lessons (Issue #88)](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/references/production-lessons.md) - new (+269)
- [Pueue Configuration Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/references/pueue-config-reference.md) - updated (+2)
- [State File Management & Bulk Submission](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/references/state-management.md) - new (+255)

</details>

<details>
<summary><strong>devops-tools/session-chronicle</strong> (4 files)</summary>

- [Session Archaeology Scripts](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/references/archaeology-scripts.md) - new (+166)
- [Output Generation](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/references/output-generation.md) - new (+111)
- [Preflight Scripts](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/references/preflight-scripts.md) - new (+131)
- [Registry Schema Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/references/registry-schema.md) - new (+119)

</details>

<details>
<summary><strong>itp/adr-graph-easy-architect</strong> (4 files)</summary>

- [Embedding Diagrams in ADRs](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/adr-graph-easy-architect/references/adr-embedding.md) - new (+93)
- [Graph-Easy DSL Syntax Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/adr-graph-easy-architect/references/dsl-syntax.md) - new (+206)
- [Monospace-Safe Symbols Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/adr-graph-easy-architect/references/monospace-symbols.md) - new (+46)
- [Preflight Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/adr-graph-easy-architect/references/preflight-setup.md) - new (+112)

</details>

<details>
<summary><strong>itp/go</strong> (7 files)</summary>

- [Arguments Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/go/references/arguments-reference.md) - new (+65)
- [Phase 1 Protocols](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/go/references/phase1-protocols.md) - new (+93)
- [Phase 2 Scripts](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/go/references/phase2-scripts.md) - new (+53)
- [Phase 3 Gate Logic](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/go/references/phase3-gate-logic.md) - new (+104)
- [Preflight Checkpoint (MANDATORY)](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/go/references/preflight-checkpoint.md) - new (+37)
- [TodoWrite Merge Strategy](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/go/references/todo-merge-strategy.md) - new (+97)
- [Workflow Preview](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/go/references/workflow-preview.md) - new (+35)

</details>

<details>
<summary><strong>itp/graph-easy</strong> (5 files)</summary>

- [Common Diagram Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/graph-easy/references/diagram-patterns.md) - new (+69)
- [DSL Syntax Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/graph-easy/references/dsl-syntax.md) - new (+174)
- [Embedding Diagrams in Markdown](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/graph-easy/references/embedding-guide.md) - new (+88)
- [Monospace-Safe Symbols Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/graph-easy/references/monospace-symbols.md) - new (+39)
- [Preflight Check](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/graph-easy/references/preflight-check.md) - new (+112)

</details>

<details>
<summary><strong>itp/mise-configuration</strong> (4 files)</summary>

- [mise Configuration Anti-Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-configuration/references/anti-patterns.md) - new (+37)
- [Hub-Spoke Architecture for mise Configuration](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-configuration/references/hub-spoke-architecture.md) - new (+117)
- [Monorepo Workspace Pattern](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-configuration/references/monorepo-workspace.md) - new (+35)
- [Task Orchestration Integration](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-configuration/references/task-orchestration.md) - new (+38)

</details>

<details>
<summary><strong>itp/mise-tasks</strong> (2 files)</summary>

- [Environment Integration](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/references/env-integration.md) - new (+44)
- [Task Levels Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/references/task-levels.md) - new (+438)

</details>

<details>
<summary><strong>itp/pypi-doppler</strong> (5 files)</summary>

- [CI Detection Enforcement](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/pypi-doppler/references/ci-detection.md) - new (+40)
- [Credential Management](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/pypi-doppler/references/credential-management.md) - new (+50)
- [mise Task Integration](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/pypi-doppler/references/mise-task-integration.md) - new (+33)
- [TestPyPI Testing](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/pypi-doppler/references/testpypi-testing.md) - new (+39)
- [Troubleshooting](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/pypi-doppler/references/troubleshooting.md) - new (+130)

</details>

<details>
<summary><strong>plugin-dev/create</strong> (6 files)</summary>

- [Phase 0: Discovery & Validation (Detailed)](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/create/references/phase0-discovery.md) - new (+111)
- [Phase 1: Scaffold Plugin (Detailed)](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/create/references/phase1-scaffold.md) - new (+82)
- [Phase 2: Component Creation (Detailed)](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/create/references/phase2-components.md) - new (+61)
- [Phase 3: Registration & Validation (Detailed)](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/create/references/phase3-validation.md) - new (+95)
- [Phase 4: Commit & Release (Detailed)](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/create/references/phase4-release.md) - new (+85)
- [Troubleshooting](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/create/references/troubleshooting.md) - new (+10)

</details>

<details>
<summary><strong>plugin-dev/skill-architecture</strong> (4 files)</summary>

- [Skill Creation Process (Detailed Tutorial)](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/creation-tutorial.md) - new (+88)
- [Task Templates](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/task-templates.md) - new (+130)
- [Troubleshooting](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/troubleshooting.md) - new (+54)
- [YAML Frontmatter Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/yaml-frontmatter.md) - new (+75)

</details>

<details>
<summary><strong>productivity-tools/slash-command-factory</strong> (8 files)</summary>

- [Bash Permission Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/slash-command-factory/references/bash-permissions.md) - new (+84)
- [Official Command Structure Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/slash-command-factory/references/command-patterns.md) - new (+145)
- [Generation Process](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/slash-command-factory/references/generation-process.md) - new (+140)
- [Comprehensive Naming Convention](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/slash-command-factory/references/naming-convention.md) - new (+59)
- [Preset Command Details](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/slash-command-factory/references/preset-commands.md) - new (+259)
- [Question Flow (Custom Path)](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/slash-command-factory/references/question-flow.md) - new (+164)
- [Usage Examples](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/slash-command-factory/references/usage-examples.md) - new (+116)
- [Validation & Success Criteria](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/slash-command-factory/references/validation-reference.md) - new (+129)

</details>

<details>
<summary><strong>quant-research/adaptive-wfo-epoch</strong> (9 files)</summary>

- [Principled Configuration Framework](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/configuration-framework.md) - new (+211)
- [Efficient Frontier Algorithm](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/efficient-frontier.md) - new (+112)
- [Epoch Smoothing Methods](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/epoch-smoothing-methods.md) - new (+108)
- [Guardrails (Principled Guidelines)](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/guardrails.md) - new (+175)
- [Look-Ahead Bias Prevention](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/look-ahead-bias-v3.md) - new (+143)
- [OOS Metrics Implementation](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/oos-metrics-implementation.md) - new (+164)
- [OOS Application Phase](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/oos-workflow.md) - new (+321)
- [Troubleshooting](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/troubleshooting.md) - new (+14)
- [WFE Aggregation Methods](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/wfe-aggregation.md) - new (+79)

</details>


## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+34/-45)

### General Documentation

- [Documentation Guide](https://github.com/terrylica/cc-skills/blob/main/docs/CLAUDE.md) - updated (+1)
- [Lessons Learned](https://github.com/terrylica/cc-skills/blob/main/docs/LESSONS.md) - new (+23)

## Other Documentation

### Other

- [asciinema-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/CLAUDE.md) - new (+51)
- [Cal.com Commander Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/CLAUDE.md) - updated (+3/-1)
- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (+23/-23)
- [doc-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/CLAUDE.md) - new (+25)
- [dotfiles-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/CLAUDE.md) - new (+25)
- [git-town-workflow Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/CLAUDE.md) - new (+29)
- [Gmail Commander Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/CLAUDE.md) - updated (+3/-1)
- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+2)
- [itp Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/CLAUDE.md) - new (+67)
- [link-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/CLAUDE.md) - new (+24)
- [mise Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/CLAUDE.md) - updated (+2)
- [mql5 Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/CLAUDE.md) - new (+20)
- [plugin-dev Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/CLAUDE.md) - new (+33)
- [productivity-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/CLAUDE.md) - new (+28)
- [quality-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/CLAUDE.md) - new (+25)
- [quant-research Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/CLAUDE.md) - new (+21)
- [ru Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/CLAUDE.md) - new (+49)
- [statusline-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/CLAUDE.md) - new (+36)
- [tts-telegram-sync Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/CLAUDE.md) - updated (+2)

## [11.59.2](https://github.com/terrylica/cc-skills/compare/v11.59.1...v11.59.2) (2026-02-26)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>plugin-dev</strong> (1 change)</summary>

- [skill-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/SKILL.md) - updated (+113/-56)

</details>


### Skill References

<details>
<summary><strong>plugin-dev/skill-architecture</strong> (8 files)</summary>

- [Agent Skill Name](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/advanced-topics.md) - updated (+21/-10)
- [Command Skill Duality](https://github.com/terrylica/cc-skills/blob/v11.59.1/plugins/plugin-dev/skills/skill-architecture/references/command-skill-duality.md) - deleted
- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/evolution-log.md) - updated (+42)
- [Invocation Control](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/invocation-control.md) - new (+94)
- [Progressive Disclosure](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/progressive-disclosure.md) - updated (+12/-12)
- [Structural Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/structural-patterns.md) - updated (+1/-5)
- [Marketplace Sync Tracking](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/SYNC-TRACKING.md) - updated (+18/-7)
- [My Skill](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/validation-reference.md) - updated (+21/-5)

</details>

## [11.59.1](https://github.com/terrylica/cc-skills/compare/v11.59.0...v11.59.1) (2026-02-26)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [worktree-manager](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/worktree-manager/SKILL.md) - renamed from `plugins/alpha-forge-worktree/skills/worktree-manager/SKILL.md`

</details>

<details>
<summary><strong>productivity-tools</strong> (4 changes)</summary>

- [gdrive-access](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/gdrive-access/SKILL.md) - renamed from `plugins/gdrive-tools/skills/gdrive-access/SKILL.md`
- [imessage-query](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/imessage-query/SKILL.md) - renamed from `plugins/imessage-tools/skills/imessage-query/SKILL.md`
- [iterm2-layout](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/iterm2-layout/SKILL.md) - renamed from `plugins/iterm2-layout-config/skills/iterm2-layout/SKILL.md`
- [notion-sdk](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/notion-sdk/SKILL.md) - renamed from `plugins/notion-api/skills/notion-sdk/SKILL.md`

</details>

<details>
<summary><strong>quality-tools</strong> (1 change)</summary>

- [alpha-forge-preship](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/alpha-forge-preship/SKILL.md) - renamed from `plugins/alpha-forge-preship/SKILL.md`

</details>


### Plugin READMEs

- [alpha-forge-worktree](https://github.com/terrylica/cc-skills/blob/v11.59.0/plugins/alpha-forge-worktree/README.md) - deleted
- [gdrive-tools](https://github.com/terrylica/cc-skills/blob/v11.59.0/plugins/gdrive-tools/README.md) - deleted
- [imessage-tools](https://github.com/terrylica/cc-skills/blob/v11.59.0/plugins/imessage-tools/README.md) - deleted
- [iterm2-layout-config](https://github.com/terrylica/cc-skills/blob/v11.59.0/plugins/iterm2-layout-config/README.md) - deleted
- [notion-api](https://github.com/terrylica/cc-skills/blob/v11.59.0/plugins/notion-api/README.md) - deleted

### Skill References

<details>
<summary><strong>devops-tools/worktree-manager</strong> (1 file)</summary>

- [Alpha-Forge Worktree Naming Conventions](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/worktree-manager/references/naming-conventions.md) - renamed from `plugins/alpha-forge-worktree/skills/worktree-manager/references/naming-conventions.md`

</details>

<details>
<summary><strong>productivity-tools/gdrive-access</strong> (2 files)</summary>

- [Google Drive API OAuth Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/gdrive-access/references/gdrive-api-setup.md) - renamed from `plugins/gdrive-tools/skills/gdrive-access/references/gdrive-api-setup.md`
- [OAuth Client Setup Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/gdrive-access/references/oauth-clients.md) - renamed from `plugins/gdrive-tools/skills/gdrive-access/references/oauth-clients.md`

</details>

<details>
<summary><strong>productivity-tools/imessage-query</strong> (5 files)</summary>

- [Cross-Repository Analysis: iMessage Decoder Implementations](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/imessage-query/references/cross-repo-analysis.md) - renamed from `plugins/imessage-tools/skills/imessage-query/references/cross-repo-analysis.md`
- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/imessage-query/references/evolution-log.md) - renamed from `plugins/imessage-tools/skills/imessage-query/references/evolution-log.md`
- [Known Pitfalls](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/imessage-query/references/known-pitfalls.md) - renamed from `plugins/imessage-tools/skills/imessage-query/references/known-pitfalls.md`
- [Reusable SQL Query Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/imessage-query/references/query-patterns.md) - renamed from `plugins/imessage-tools/skills/imessage-query/references/query-patterns.md`
- [iMessage Database Schema Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/imessage-query/references/schema-reference.md) - renamed from `plugins/imessage-tools/skills/imessage-query/references/schema-reference.md`

</details>

<details>
<summary><strong>productivity-tools/notion-sdk</strong> (4 files)</summary>

- [Notion Block Types Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/notion-sdk/references/block-types.md) - renamed from `plugins/notion-api/skills/notion-sdk/references/block-types.md`
- [Pagination Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/notion-sdk/references/pagination.md) - renamed from `plugins/notion-api/skills/notion-sdk/references/pagination.md`
- [Notion Property Types Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/notion-sdk/references/property-types.md) - renamed from `plugins/notion-api/skills/notion-sdk/references/property-types.md`
- [Rich Text Formatting Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/notion-sdk/references/rich-text.md) - renamed from `plugins/notion-api/skills/notion-sdk/references/rich-text.md`

</details>

<details>
<summary><strong>quality-tools/alpha-forge-preship</strong> (1 file)</summary>

- [Alpha Forge Pre-Ship Audit Framework - Complete Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/alpha-forge-preship/references/reference.md) - renamed from `plugins/alpha-forge-preship/reference.md`

</details>


## Other Documentation

### Other

- [5_LAYER_DEFENSE_SYNTHESIS_2026-02-23](https://github.com/terrylica/cc-skills/blob/v11.59.0/plugins/alpha-forge-preship/5_LAYER_DEFENSE_SYNTHESIS_2026-02-23.md) - deleted
- [IMPLEMENTATION_SUMMARY](https://github.com/terrylica/cc-skills/blob/v11.59.0/plugins/alpha-forge-preship/IMPLEMENTATION_SUMMARY.md) - deleted
- [OFFICIAL_PHASE1_HANDOFF_2026-02-23](https://github.com/terrylica/cc-skills/blob/v11.59.0/plugins/alpha-forge-preship/OFFICIAL_PHASE1_HANDOFF_2026-02-23.md) - deleted
- [PHASE_1_STATUS](https://github.com/terrylica/cc-skills/blob/v11.59.0/plugins/alpha-forge-preship/PHASE_1_STATUS.md) - deleted
- [PHASE_2_IMPLEMENTATION_SUMMARY](https://github.com/terrylica/cc-skills/blob/v11.59.0/plugins/alpha-forge-preship/PHASE_2_IMPLEMENTATION_SUMMARY.md) - deleted
- [PHASE1_IMPLEMENTATION_SUMMARY](https://github.com/terrylica/cc-skills/blob/v11.59.0/plugins/alpha-forge-preship/PHASE1_IMPLEMENTATION_SUMMARY.md) - deleted
- [PHASE1_PRODUCTION_READY_2026-02-23](https://github.com/terrylica/cc-skills/blob/v11.59.0/plugins/alpha-forge-preship/PHASE1_PRODUCTION_READY_2026-02-23.md) - deleted
- [PROJECT_ARCHIVE_2026-02-23](https://github.com/terrylica/cc-skills/blob/v11.59.0/plugins/alpha-forge-preship/PROJECT_ARCHIVE_2026-02-23.md) - deleted
- [PROJECT_COMPLETE_FINAL_2026-02-23](https://github.com/terrylica/cc-skills/blob/v11.59.0/plugins/alpha-forge-preship/PROJECT_COMPLETE_FINAL_2026-02-23.md) - deleted
- [VERIFICATION](https://github.com/terrylica/cc-skills/blob/v11.59.0/plugins/alpha-forge-preship/VERIFICATION.md) - deleted
- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (+24/-29)
- [Alpha Forge Pre-Ship Quality Gates - Phase 1](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/alpha-forge-preship/README.md) - renamed from `plugins/alpha-forge-preship/README.md`

# [11.59.0](https://github.com/terrylica/cc-skills/compare/v11.58.2...v11.59.0) (2026-02-26)


### Bug Fixes

* replace remaining preshop→preship typos in plugin docs ([fa3a983](https://github.com/terrylica/cc-skills/commit/fa3a98337e6d7d62c3ec5ddfcd9cbe958d4e832d))


### Features

* add firecrawl-research-patterns skill to devops-tools ([fb8e0ad](https://github.com/terrylica/cc-skills/commit/fb8e0ad358502df62567fa1bcc068b168245a4ca))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [firecrawl-research-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/SKILL.md) - new (+311)

</details>


### Skill References

<details>
<summary><strong>devops-tools/firecrawl-research-patterns</strong> (4 files)</summary>

- [Academic Paper Routing](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/academic-paper-routing.md) - new (+202)
- [API Endpoint Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/api-endpoint-reference.md) - new (+258)
- [Corpus Persistence Format](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/corpus-persistence-format.md) - new (+249)
- [Recursive Research Protocol](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-research-patterns/references/recursive-research-protocol.md) - new (+244)

</details>


## Other Documentation

### Other

- [Phase 1 Quality Gates - Implementation Status](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preship/PHASE_1_STATUS.md) - updated (+1/-1)
- [Phase 2 Quality Gates - Implementation Summary](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preship/PHASE_2_IMPLEMENTATION_SUMMARY.md) - updated (+2/-2)
- [Phase 1 Quality Gates: Production Ready - Final Verification](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preship/PHASE1_PRODUCTION_READY_2026-02-23.md) - updated (+1/-1)
- [TGI-1 Project Archive - Final Closure](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preship/PROJECT_ARCHIVE_2026-02-23.md) - updated (+1/-1)
- [Alpha Forge Pre-Ship Audit Framework - Complete Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preship/reference.md) - updated (+1/-1)
- [devops-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/CLAUDE.md) - updated (+20/-19)

## [11.58.2](https://github.com/terrylica/cc-skills/compare/v11.58.1...v11.58.2) (2026-02-26)


### Bug Fixes

* rename alpha-forge-preshop to alpha-forge-preship (typo) ([379eba1](https://github.com/terrylica/cc-skills/commit/379eba16190c712671942c1be3c6a349e31e5fd9))





---

## Documentation Changes

## Plugin Documentation

### Plugin Skills

- [Alpha Forge Pre-Ship Quality Gates - Phase 1](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preship/SKILL.md) - renamed from `plugins/alpha-forge-preshop/SKILL.md`

### Plugin READMEs

- [Alpha Forge Pre-Ship Quality Gates - Phase 1](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preship/README.md) - renamed from `plugins/alpha-forge-preshop/README.md`

## Other Documentation

### Other

- [5-Layer Defense-in-Depth Synthesis: Complete Architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preship/5_LAYER_DEFENSE_SYNTHESIS_2026-02-23.md) - renamed from `plugins/alpha-forge-preshop/5_LAYER_DEFENSE_SYNTHESIS_2026-02-23.md`
- [Phase 1 Quality Gates Implementation - COMPLETE ✅](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preship/IMPLEMENTATION_SUMMARY.md) - renamed from `plugins/alpha-forge-preshop/IMPLEMENTATION_SUMMARY.md`
- [Official Phase 1 Implementation Handoff](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preship/OFFICIAL_PHASE1_HANDOFF_2026-02-23.md) - renamed from `plugins/alpha-forge-preshop/OFFICIAL_PHASE1_HANDOFF_2026-02-23.md`
- [Phase 1 Quality Gates - Implementation Status](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preship/PHASE_1_STATUS.md) - renamed from `plugins/alpha-forge-preshop/PHASE_1_STATUS.md`
- [Phase 2 Quality Gates - Implementation Summary](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preship/PHASE_2_IMPLEMENTATION_SUMMARY.md) - renamed from `plugins/alpha-forge-preshop/PHASE_2_IMPLEMENTATION_SUMMARY.md`
- [Phase 1 Quality Gates Implementation Summary](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preship/PHASE1_IMPLEMENTATION_SUMMARY.md) - renamed from `plugins/alpha-forge-preshop/PHASE1_IMPLEMENTATION_SUMMARY.md`
- [Phase 1 Quality Gates: Production Ready - Final Verification](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preship/PHASE1_PRODUCTION_READY_2026-02-23.md) - renamed from `plugins/alpha-forge-preshop/PHASE1_PRODUCTION_READY_2026-02-23.md`
- [TGI-1 Project Archive - Final Closure](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preship/PROJECT_ARCHIVE_2026-02-23.md) - renamed from `plugins/alpha-forge-preshop/PROJECT_ARCHIVE_2026-02-23.md`
- [TGI-1 Project: OFFICIALLY COMPLETE - FINAL CLOSURE](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preship/PROJECT_COMPLETE_FINAL_2026-02-23.md) - renamed from `plugins/alpha-forge-preshop/PROJECT_COMPLETE_FINAL_2026-02-23.md`
- [Alpha Forge Pre-Ship Audit Framework - Complete Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preship/reference.md) - renamed from `plugins/alpha-forge-preshop/reference.md`
- [Phase 1 Quality Gates - Verification Report](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preship/VERIFICATION.md) - renamed from `plugins/alpha-forge-preshop/VERIFICATION.md`

## [11.58.1](https://github.com/terrylica/cc-skills/compare/v11.58.0...v11.58.1) (2026-02-25)


### Bug Fixes

* allow public-safe gh operations (issue create/comment) on public repos without push access ([39b154c](https://github.com/terrylica/cc-skills/commit/39b154c8c741649eab208a9c459c6d985ef08a0f))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [claude-code-proxy-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/claude-code-proxy-patterns/SKILL.md) - updated (+126/-50)

</details>


### Skill References

<details>
<summary><strong>devops-tools/claude-code-proxy-patterns</strong> (2 files)</summary>

- [Claude Code Proxy Anti-Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/claude-code-proxy-patterns/references/anti-patterns.md) - updated (+63/-17)
- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/claude-code-proxy-patterns/references/evolution-log.md) - updated (+26)

</details>


## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+18/-17)

# [11.58.0](https://github.com/terrylica/cc-skills/compare/v11.57.1...v11.58.0) (2026-02-24)


### Bug Fixes

* **g12:** return dict format for manifest sync validation issues ([756bc07](https://github.com/terrylica/cc-skills/commit/756bc07bda052d9569699d6de841675583701381))


### Features

* **alpha-forge-preshop:** implement Phase 1 quality gates G4, G5, G8, G12 ([ce15689](https://github.com/terrylica/cc-skills/commit/ce15689b01a2cfee5662651e162cd53970d713e6))
* **gates:** implement Phase 2 quality gates (G6, G7, G10, G1-G3) ([a348d22](https://github.com/terrylica/cc-skills/commit/a348d222b51d2e0559879cc1121c1ec1beb82c55))
* Phase 1 quality gates implementation for Alpha Forge ([46d8be4](https://github.com/terrylica/cc-skills/commit/46d8be45a848f879712f8a0486b402e95d3a1cfa)), closes [#154](https://github.com/terrylica/cc-skills/issues/154)
* **preshop:** implement Phase 1 quality gates (G4, G5, G8, G12) ([68b1a74](https://github.com/terrylica/cc-skills/commit/68b1a741c025e8491e6483f2c9e4acfff0d73e34)), closes [#154](https://github.com/terrylica/cc-skills/issues/154) [#154](https://github.com/terrylica/cc-skills/issues/154)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [claude-code-proxy-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/claude-code-proxy-patterns/SKILL.md) - updated (+223/-52)

</details>


### Plugin Skills

- [Alpha Forge Pre-Ship Quality Gates - Phase 1](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preshop/SKILL.md) - new (+67)

### Plugin READMEs

- [Alpha Forge Pre-Ship Quality Gates - Phase 1](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preshop/README.md) - new (+100)

### Skill References

<details>
<summary><strong>devops-tools/claude-code-proxy-patterns</strong> (3 files)</summary>

- [Claude Code Proxy Anti-Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/claude-code-proxy-patterns/references/anti-patterns.md) - updated (+4/-4)
- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/claude-code-proxy-patterns/references/evolution-log.md) - updated (+20)
- [Provider Compatibility Matrix](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/claude-code-proxy-patterns/references/provider-compatibility.md) - updated (+46/-8)

</details>


## Other Documentation

### Other

- [5-Layer Defense-in-Depth Synthesis: Complete Architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preshop/5_LAYER_DEFENSE_SYNTHESIS_2026-02-23.md) - new (+343)
- [Phase 1 Quality Gates Implementation - COMPLETE ✅](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preshop/IMPLEMENTATION_SUMMARY.md) - new (+176)
- [Official Phase 1 Implementation Handoff](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preshop/OFFICIAL_PHASE1_HANDOFF_2026-02-23.md) - new (+323)
- [Phase 1 Quality Gates - Implementation Status](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preshop/PHASE_1_STATUS.md) - new (+165)
- [Phase 2 Quality Gates - Implementation Summary](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preshop/PHASE_2_IMPLEMENTATION_SUMMARY.md) - new (+409)
- [Phase 1 Quality Gates Implementation Summary](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preshop/PHASE1_IMPLEMENTATION_SUMMARY.md) - new (+175)
- [Phase 1 Quality Gates: Production Ready - Final Verification](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preshop/PHASE1_PRODUCTION_READY_2026-02-23.md) - new (+357)
- [TGI-1 Project Archive - Final Closure](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preshop/PROJECT_ARCHIVE_2026-02-23.md) - new (+386)
- [TGI-1 Project: OFFICIALLY COMPLETE - FINAL CLOSURE](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preshop/PROJECT_COMPLETE_FINAL_2026-02-23.md) - new (+416)
- [Alpha Forge Pre-Ship Audit Framework - Complete Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preshop/reference.md) - new (+516)
- [Phase 1 Quality Gates - Verification Report](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-preshop/VERIFICATION.md) - new (+120)

## [11.57.1](https://github.com/terrylica/cc-skills/compare/v11.57.0...v11.57.1) (2026-02-23)


### Bug Fixes

* **itp-hooks:** expand cargo-tty-guard to protect foreground cargo commands ([cf188f6](https://github.com/terrylica/cc-skills/commit/cf188f6a0afe534c920acc216529b7cf5214bc1a)), closes [#11898](https://github.com/terrylica/cc-skills/issues/11898) [#12507](https://github.com/terrylica/cc-skills/issues/12507) [#13598](https://github.com/terrylica/cc-skills/issues/13598)





---

## Documentation Changes

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+2)

# [11.57.0](https://github.com/terrylica/cc-skills/compare/v11.56.1...v11.57.0) (2026-02-23)


### Features

* **itp-hooks:** universal subprocess TTY guard - expanded scope to all tools ([3d157e1](https://github.com/terrylica/cc-skills/commit/3d157e103cdc3dfd0c4a75ed8173a77f89252ac7)), closes [#11898](https://github.com/terrylica/cc-skills/issues/11898) [#12507](https://github.com/terrylica/cc-skills/issues/12507) [#13598](https://github.com/terrylica/cc-skills/issues/13598)

## [11.56.1](https://github.com/terrylica/cc-skills/compare/v11.56.0...v11.56.1) (2026-02-23)


### Bug Fixes

* **itp-hooks:** improve cargo-tty-guard hook reliability and UX ([2514257](https://github.com/terrylica/cc-skills/commit/2514257f735e29abf960f2de1a154598fa482009))





---

## Documentation Changes

## Repository Documentation

### General Documentation

- [Cargo TTY Suspension Prevention Hook](https://github.com/terrylica/cc-skills/blob/main/docs/cargo-tty-suspension-prevention.md) - updated (+51)

# [11.56.0](https://github.com/terrylica/cc-skills/compare/v11.55.0...v11.56.0) (2026-02-23)


### Features

* **itp-hooks:** cargo TTY suspension prevention hook with PUEUE isolation ([65008a9](https://github.com/terrylica/cc-skills/commit/65008a909b4362df4d7a392c33766f6f3f304d29))





---

## Documentation Changes

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+19/-15)

### General Documentation

- [Cargo TTY Suspension Prevention Hook](https://github.com/terrylica/cc-skills/blob/main/docs/cargo-tty-suspension-prevention.md) - new (+319)
- [Documentation Guide](https://github.com/terrylica/cc-skills/blob/main/docs/CLAUDE.md) - updated (+9/-8)

## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+55/-16)

# [11.55.0](https://github.com/terrylica/cc-skills/compare/v11.54.2...v11.55.0) (2026-02-23)


### Bug Fixes

* **ru:** narrow deletion_patterns to prevent false-positive blocking ([69c502e](https://github.com/terrylica/cc-skills/commit/69c502ea3ba7c5bca87613d06131b5f8e7c32c29))


### Features

* **devops-tools:** add claude-code-proxy-patterns skill ([9b1c75b](https://github.com/terrylica/cc-skills/commit/9b1c75ba4569cfd958e63053ba1ffaafdd3337bc))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [claude-code-proxy-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/claude-code-proxy-patterns/SKILL.md) - new (+358)

</details>


### Skill References

<details>
<summary><strong>devops-tools/claude-code-proxy-patterns</strong> (4 files)</summary>

- [Claude Code Proxy Anti-Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/claude-code-proxy-patterns/references/anti-patterns.md) - new (+242)
- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/claude-code-proxy-patterns/references/evolution-log.md) - new (+10)
- [Claude Code OAuth Internals](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/claude-code-proxy-patterns/references/oauth-internals.md) - new (+244)
- [Provider Compatibility Matrix](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/claude-code-proxy-patterns/references/provider-compatibility.md) - new (+104)

</details>

## [11.54.2](https://github.com/terrylica/cc-skills/compare/v11.54.1...v11.54.2) (2026-02-23)


### Bug Fixes

* **gmail-commander:** filter stop hook to gmail project dir, prevent cross-session noise ([f81d9c3](https://github.com/terrylica/cc-skills/commit/f81d9c34367aea31762c8e68d71c099a8d7a60dd))
* **tts-telegram-sync:** use transcript_path from stdin, fail-open, mkdirSync ([a9f2fb1](https://github.com/terrylica/cc-skills/commit/a9f2fb17706453aaa9a92cbfd264953b81292f46))





---

## Documentation Changes

## Other Documentation

### Other

- [devops-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/CLAUDE.md) - new (+86)
- [gh-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/CLAUDE.md) - updated (+53)
- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+32)

## [11.54.1](https://github.com/terrylica/cc-skills/compare/v11.54.0...v11.54.1) (2026-02-20)

# [11.54.0](https://github.com/terrylica/cc-skills/compare/v11.53.3...v11.54.0) (2026-02-20)


### Features

* **skills:** conform to official skills/ architecture, eliminate commands/ layer ([fdc4837](https://github.com/terrylica/cc-skills/commit/fdc48376e2d77e4ff7fb20273fdff902e139ee9a)), closes [#17361](https://github.com/terrylica/cc-skills/issues/17361) [#18517](https://github.com/terrylica/cc-skills/issues/18517) [#14061](https://github.com/terrylica/cc-skills/issues/14061)
* **tts:** add optional pySBD sentence-split pass to preprocess pipeline ([f5aad02](https://github.com/terrylica/cc-skills/commit/f5aad02e4c70a127d42743acfd2f3551f7746a91))
* **tts:** intelligent hard-wrap reflow preprocessing for clipboard TTS ([d4a3750](https://github.com/terrylica/cc-skills/commit/d4a3750d16c4569dc289fa0c20795ef9209011dc))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>asciinema-tools</strong> (18 changes)</summary>

- [analyze](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/analyze/SKILL.md) - renamed from `plugins/asciinema-tools/commands/analyze.md`
- [backup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/backup/SKILL.md) - renamed from `plugins/asciinema-tools/commands/backup.md`
- [bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/bootstrap/SKILL.md) - renamed from `plugins/asciinema-tools/commands/bootstrap.md`
- [convert](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/convert/SKILL.md) - renamed from `plugins/asciinema-tools/commands/convert.md`
- [daemon-logs](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-logs/SKILL.md) - renamed from `plugins/asciinema-tools/commands/daemon-logs.md`
- [daemon-setup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-setup/SKILL.md) - renamed from `plugins/asciinema-tools/commands/daemon-setup.md`
- [daemon-start](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-start/SKILL.md) - renamed from `plugins/asciinema-tools/commands/daemon-start.md`
- [daemon-status](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-status/SKILL.md) - renamed from `plugins/asciinema-tools/commands/daemon-status.md`
- [daemon-stop](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/daemon-stop/SKILL.md) - renamed from `plugins/asciinema-tools/commands/daemon-stop.md`
- [finalize](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/finalize/SKILL.md) - renamed from `plugins/asciinema-tools/commands/finalize.md`
- [format](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/format/SKILL.md) - renamed from `plugins/asciinema-tools/commands/format.md`
- [full-workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/full-workflow/SKILL.md) - renamed from `plugins/asciinema-tools/commands/full-workflow.md`
- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/hooks/SKILL.md) - renamed from `plugins/asciinema-tools/commands/hooks.md`
- [play](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/play/SKILL.md) - renamed from `plugins/asciinema-tools/commands/play.md`
- [post-session](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/post-session/SKILL.md) - renamed from `plugins/asciinema-tools/commands/post-session.md`
- [record](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/record/SKILL.md) - renamed from `plugins/asciinema-tools/commands/record.md`
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/setup/SKILL.md) - renamed from `plugins/asciinema-tools/commands/setup.md`
- [summarize](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/summarize/SKILL.md) - renamed from `plugins/asciinema-tools/commands/summarize.md`

</details>

<details>
<summary><strong>calcom-commander</strong> (2 changes)</summary>

- [health](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/health/SKILL.md) - renamed from `plugins/calcom-commander/commands/health.md`
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/setup/SKILL.md) - renamed from `plugins/calcom-commander/commands/setup.md`

</details>

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [dual-channel-watchexec-notifications](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/dual-channel-watchexec-notifications/SKILL.md) - renamed from `plugins/devops-tools/commands/dual-channel-watchexec-notifications.md`

</details>

<details>
<summary><strong>dotfiles-tools</strong> (1 change)</summary>

- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/skills/hooks/SKILL.md) - renamed from `plugins/dotfiles-tools/commands/hooks.md`

</details>

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/hooks/SKILL.md) - renamed from `plugins/gh-tools/commands/hooks.md`

</details>

<details>
<summary><strong>git-town-workflow</strong> (4 changes)</summary>

- [contribute](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/skills/contribute/SKILL.md) - renamed from `plugins/git-town-workflow/commands/contribute.md`
- [fork](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/skills/fork/SKILL.md) - renamed from `plugins/git-town-workflow/commands/fork.md`
- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/skills/hooks/SKILL.md) - renamed from `plugins/git-town-workflow/commands/hooks.md`
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/skills/setup/SKILL.md) - renamed from `plugins/git-town-workflow/commands/setup.md`

</details>

<details>
<summary><strong>gmail-commander</strong> (2 changes)</summary>

- [health](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/health/SKILL.md) - renamed from `plugins/gmail-commander/commands/health.md`
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/setup/SKILL.md) - renamed from `plugins/gmail-commander/commands/setup.md`

</details>

<details>
<summary><strong>itp</strong> (4 changes)</summary>

- [go](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/go/SKILL.md) - renamed from `plugins/itp/commands/go.md`
- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/hooks/SKILL.md) - renamed from `plugins/itp/commands/hooks.md`
- [release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/release/SKILL.md) - renamed from `plugins/itp/commands/release.md`
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/setup/SKILL.md) - renamed from `plugins/itp/commands/setup.md`

</details>

<details>
<summary><strong>itp-hooks</strong> (1 change)</summary>

- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/setup/SKILL.md) - renamed from `plugins/itp-hooks/commands/setup.md`

</details>

<details>
<summary><strong>mise</strong> (4 changes)</summary>

- [list-repo-tasks](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/list-repo-tasks/SKILL.md) - renamed from `plugins/mise/commands/list-repo-tasks.md`
- [run-full-release](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/run-full-release/SKILL.md) - renamed from `plugins/mise/commands/run-full-release.md`
- [show-env-status](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/show-env-status/SKILL.md) - renamed from `plugins/mise/commands/show-env-status.md`
- [sred-commit](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/skills/sred-commit/SKILL.md) - renamed from `plugins/mise/commands/sred-commit.md`

</details>

<details>
<summary><strong>plugin-dev</strong> (2 changes)</summary>

- [create](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/create/SKILL.md) - renamed from `plugins/plugin-dev/commands/create.md`
- [skill-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/SKILL.md) - updated (+44/-10)

</details>

<details>
<summary><strong>productivity-tools</strong> (1 change)</summary>

- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/hooks/SKILL.md) - renamed from `plugins/productivity-tools/commands/hooks.md`

</details>

<details>
<summary><strong>ru</strong> (9 changes)</summary>

- [audit-now](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/audit-now/SKILL.md) - renamed from `plugins/ru/commands/audit-now.md`
- [config](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/config/SKILL.md) - renamed from `plugins/ru/commands/config.md`
- [encourage](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/encourage/SKILL.md) - renamed from `plugins/ru/commands/encourage.md`
- [forbid](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/forbid/SKILL.md) - renamed from `plugins/ru/commands/forbid.md`
- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/hooks/SKILL.md) - renamed from `plugins/ru/commands/hooks.md`
- [start](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/start/SKILL.md) - renamed from `plugins/ru/commands/start.md`
- [status](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/status/SKILL.md) - renamed from `plugins/ru/commands/status.md`
- [stop](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/stop/SKILL.md) - renamed from `plugins/ru/commands/stop.md`
- [wizard](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/skills/wizard/SKILL.md) - renamed from `plugins/ru/commands/wizard.md`

</details>

<details>
<summary><strong>statusline-tools</strong> (3 changes)</summary>

- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/hooks/SKILL.md) - renamed from `plugins/statusline-tools/commands/hooks.md`
- [ignore](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/ignore/SKILL.md) - renamed from `plugins/statusline-tools/commands/ignore.md`
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/setup/SKILL.md) - renamed from `plugins/statusline-tools/commands/setup.md`

</details>

<details>
<summary><strong>tts-telegram-sync</strong> (3 changes)</summary>

- [health](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/health/SKILL.md) - renamed from `plugins/tts-telegram-sync/commands/health.md`
- [hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/hooks/SKILL.md) - renamed from `plugins/tts-telegram-sync/commands/hooks.md`
- [setup](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/setup/SKILL.md) - renamed from `plugins/tts-telegram-sync/commands/setup.md`

</details>


### Commands

<details>
<summary><strong>alpha-forge-worktree</strong> (1 command)</summary>

- [worktree-manager](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/alpha-forge-worktree/commands/worktree-manager.md) - deleted

</details>

<details>
<summary><strong>asciinema-tools</strong> (6 commands)</summary>

- [asciinema-analyzer](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/asciinema-tools/commands/asciinema-analyzer.md) - deleted
- [asciinema-cast-format](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/asciinema-tools/commands/asciinema-cast-format.md) - deleted
- [asciinema-converter](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/asciinema-tools/commands/asciinema-converter.md) - deleted
- [asciinema-player](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/asciinema-tools/commands/asciinema-player.md) - deleted
- [asciinema-recorder](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/asciinema-tools/commands/asciinema-recorder.md) - deleted
- [asciinema-streaming-backup](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/asciinema-tools/commands/asciinema-streaming-backup.md) - deleted

</details>

<details>
<summary><strong>calcom-commander</strong> (4 commands)</summary>

- [booking-config](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/calcom-commander/commands/booking-config.md) - deleted
- [booking-notify](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/calcom-commander/commands/booking-notify.md) - deleted
- [calcom-access](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/calcom-commander/commands/calcom-access.md) - deleted
- [infra-deploy](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/calcom-commander/commands/infra-deploy.md) - deleted

</details>

<details>
<summary><strong>devops-tools</strong> (17 commands)</summary>

- [clickhouse-cloud-management](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/devops-tools/commands/clickhouse-cloud-management.md) - deleted
- [clickhouse-pydantic-config](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/devops-tools/commands/clickhouse-pydantic-config.md) - deleted
- [cloudflare-workers-publish](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/devops-tools/commands/cloudflare-workers-publish.md) - deleted
- [disk-hygiene](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/devops-tools/commands/disk-hygiene.md) - deleted
- [distributed-job-safety](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/devops-tools/commands/distributed-job-safety.md) - deleted
- [doppler-secret-validation](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/devops-tools/commands/doppler-secret-validation.md) - deleted
- [doppler-workflows](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/devops-tools/commands/doppler-workflows.md) - deleted
- [dual-channel-watchexec](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/devops-tools/commands/dual-channel-watchexec.md) - deleted
- [firecrawl-self-hosted](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/devops-tools/commands/firecrawl-self-hosted.md) - deleted
- [ml-data-pipeline-architecture](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/devops-tools/commands/ml-data-pipeline-architecture.md) - deleted
- [ml-failfast-validation](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/devops-tools/commands/ml-failfast-validation.md) - deleted
- [mlflow-python](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/devops-tools/commands/mlflow-python.md) - deleted
- [project-directory-migration](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/devops-tools/commands/project-directory-migration.md) - deleted
- [pueue-job-orchestration](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/devops-tools/commands/pueue-job-orchestration.md) - deleted
- [python-logging-best-practices](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/devops-tools/commands/python-logging-best-practices.md) - deleted
- [session-chronicle](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/devops-tools/commands/session-chronicle.md) - deleted
- [session-recovery](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/devops-tools/commands/session-recovery.md) - deleted

</details>

<details>
<summary><strong>doc-tools</strong> (9 commands)</summary>

- [ascii-diagram-validator](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/doc-tools/commands/ascii-diagram-validator.md) - deleted
- [documentation-standards](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/doc-tools/commands/documentation-standards.md) - deleted
- [glossary-management](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/doc-tools/commands/glossary-management.md) - deleted
- [latex-build](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/doc-tools/commands/latex-build.md) - deleted
- [latex-setup](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/doc-tools/commands/latex-setup.md) - deleted
- [latex-tables](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/doc-tools/commands/latex-tables.md) - deleted
- [pandoc-pdf-generation](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/doc-tools/commands/pandoc-pdf-generation.md) - deleted
- [plotext-financial-chart](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/doc-tools/commands/plotext-financial-chart.md) - deleted
- [terminal-print](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/doc-tools/commands/terminal-print.md) - deleted

</details>

<details>
<summary><strong>dotfiles-tools</strong> (1 command)</summary>

- [chezmoi-workflows](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/dotfiles-tools/commands/chezmoi-workflows.md) - deleted

</details>

<details>
<summary><strong>gdrive-tools</strong> (1 command)</summary>

- [gdrive-access](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/gdrive-tools/commands/gdrive-access.md) - deleted

</details>

<details>
<summary><strong>gh-tools</strong> (5 commands)</summary>

- [fork-intelligence](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/gh-tools/commands/fork-intelligence.md) - deleted
- [issue-create](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/gh-tools/commands/issue-create.md) - deleted
- [issues-workflow](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/gh-tools/commands/issues-workflow.md) - deleted
- [pr-gfm-validator](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/gh-tools/commands/pr-gfm-validator.md) - deleted
- [research-archival](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/gh-tools/commands/research-archival.md) - deleted

</details>

<details>
<summary><strong>gmail-commander</strong> (4 commands)</summary>

- [bot-process-control](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/gmail-commander/commands/bot-process-control.md) - deleted
- [email-triage](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/gmail-commander/commands/email-triage.md) - deleted
- [gmail-access](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/gmail-commander/commands/gmail-access.md) - deleted
- [interactive-bot](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/gmail-commander/commands/interactive-bot.md) - deleted

</details>

<details>
<summary><strong>imessage-tools</strong> (1 command)</summary>

- [imessage-query](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/imessage-tools/commands/imessage-query.md) - deleted

</details>

<details>
<summary><strong>iterm2-layout-config</strong> (1 command)</summary>

- [iterm2-layout](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/iterm2-layout-config/commands/iterm2-layout.md) - deleted

</details>

<details>
<summary><strong>itp</strong> (11 commands)</summary>

- [adr-code-traceability](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/itp/commands/adr-code-traceability.md) - deleted
- [adr-graph-easy-architect](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/itp/commands/adr-graph-easy-architect.md) - deleted
- [bootstrap-monorepo](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/itp/commands/bootstrap-monorepo.md) - deleted
- [code-hardcode-audit](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/itp/commands/code-hardcode-audit.md) - deleted
- [graph-easy](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/itp/commands/graph-easy.md) - deleted
- [impl-standards](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/itp/commands/impl-standards.md) - deleted
- [implement-plan-preflight](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/itp/commands/implement-plan-preflight.md) - deleted
- [mise-configuration](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/itp/commands/mise-configuration.md) - deleted
- [mise-tasks](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/itp/commands/mise-tasks.md) - deleted
- [pypi-doppler](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/itp/commands/pypi-doppler.md) - deleted
- [semantic-release](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/itp/commands/semantic-release.md) - deleted

</details>

<details>
<summary><strong>itp-hooks</strong> (1 command)</summary>

- [hooks-development](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/itp-hooks/commands/hooks-development.md) - deleted

</details>

<details>
<summary><strong>link-tools</strong> (1 command)</summary>

- [link-validator](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/link-tools/commands/link-validator.md) - deleted

</details>

<details>
<summary><strong>mql5</strong> (4 commands)</summary>

- [article-extractor](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/mql5/commands/article-extractor.md) - deleted
- [log-reader](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/mql5/commands/log-reader.md) - deleted
- [mql5-indicator-patterns](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/mql5/commands/mql5-indicator-patterns.md) - deleted
- [python-workspace](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/mql5/commands/python-workspace.md) - deleted

</details>

<details>
<summary><strong>notion-api</strong> (1 command)</summary>

- [notion-sdk](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/notion-api/commands/notion-sdk.md) - deleted

</details>

<details>
<summary><strong>plugin-dev</strong> (2 commands)</summary>

- [plugin-validator](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/plugin-dev/commands/plugin-validator.md) - deleted
- [skill-architecture](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/plugin-dev/commands/skill-architecture.md) - deleted

</details>

<details>
<summary><strong>productivity-tools</strong> (2 commands)</summary>

- [calendar-event-manager](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/productivity-tools/commands/calendar-event-manager.md) - deleted
- [slash-command-factory](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/productivity-tools/commands/slash-command-factory.md) - deleted

</details>

<details>
<summary><strong>quality-tools</strong> (8 commands)</summary>

- [clickhouse-architect](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/quality-tools/commands/clickhouse-architect.md) - deleted
- [code-clone-assistant](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/quality-tools/commands/code-clone-assistant.md) - deleted
- [dead-code-detector](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/quality-tools/commands/dead-code-detector.md) - deleted
- [multi-agent-e2e-validation](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/quality-tools/commands/multi-agent-e2e-validation.md) - deleted
- [multi-agent-performance-profiling](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/quality-tools/commands/multi-agent-performance-profiling.md) - deleted
- [pre-ship-review](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/quality-tools/commands/pre-ship-review.md) - deleted
- [schema-e2e-validation](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/quality-tools/commands/schema-e2e-validation.md) - deleted
- [symmetric-dogfooding](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/quality-tools/commands/symmetric-dogfooding.md) - deleted

</details>

<details>
<summary><strong>quant-research</strong> (4 commands)</summary>

- [adaptive-wfo-epoch](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/quant-research/commands/adaptive-wfo-epoch.md) - deleted
- [backtesting-py-oracle](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/quant-research/commands/backtesting-py-oracle.md) - deleted
- [evolutionary-metric-ranking](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/quant-research/commands/evolutionary-metric-ranking.md) - deleted
- [rangebar-eval-metrics](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/quant-research/commands/rangebar-eval-metrics.md) - deleted

</details>

<details>
<summary><strong>statusline-tools</strong> (1 command)</summary>

- [session-info](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/statusline-tools/commands/session-info.md) - deleted

</details>

<details>
<summary><strong>tts-telegram-sync</strong> (8 commands)</summary>

- [bot-process-control](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/tts-telegram-sync/commands/bot-process-control.md) - deleted
- [clean-component-removal](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/tts-telegram-sync/commands/clean-component-removal.md) - deleted
- [component-version-upgrade](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/tts-telegram-sync/commands/component-version-upgrade.md) - deleted
- [diagnostic-issue-resolver](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/tts-telegram-sync/commands/diagnostic-issue-resolver.md) - deleted
- [full-stack-bootstrap](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/tts-telegram-sync/commands/full-stack-bootstrap.md) - deleted
- [settings-and-tuning](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/tts-telegram-sync/commands/settings-and-tuning.md) - deleted
- [system-health-check](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/tts-telegram-sync/commands/system-health-check.md) - deleted
- [voice-quality-audition](https://github.com/terrylica/cc-skills/blob/v11.53.3/plugins/tts-telegram-sync/commands/voice-quality-audition.md) - deleted

</details>


## Other Documentation

### Other

- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (-1)

## [11.53.3](https://github.com/terrylica/cc-skills/compare/v11.53.2...v11.53.3) (2026-02-20)


### Bug Fixes

* **commands:** expose 89 skills as user-invocable commands + enforce invariant ([981906f](https://github.com/terrylica/cc-skills/commit/981906f774931e17d07c927315c17b5160820d5a))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>alpha-forge-worktree</strong> (1 command)</summary>

- [Alpha-Forge Worktree Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-worktree/commands/worktree-manager.md) - new (+454)

</details>

<details>
<summary><strong>asciinema-tools</strong> (6 commands)</summary>

- [asciinema-analyzer](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/asciinema-analyzer.md) - new (+403)
- [asciinema-cast-format](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/asciinema-cast-format.md) - new (+240)
- [asciinema-converter](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/asciinema-converter.md) - new (+552)
- [asciinema-player](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/asciinema-player.md) - new (+364)
- [asciinema-recorder](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/asciinema-recorder.md) - new (+330)
- [asciinema-streaming-backup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/asciinema-streaming-backup.md) - new (+1076)

</details>

<details>
<summary><strong>calcom-commander</strong> (4 commands)</summary>

- [Booking Configuration](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/commands/booking-config.md) - new (+166)
- [Booking Notifications (Dual-Channel)](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/commands/booking-notify.md) - new (+131)
- [Cal.com Access](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/commands/calcom-access.md) - new (+176)
- [Infrastructure Deployment](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/commands/infra-deploy.md) - new (+262)

</details>

<details>
<summary><strong>devops-tools</strong> (18 commands)</summary>

- [ClickHouse Cloud Management](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/commands/clickhouse-cloud-management.md) - new (+180)
- [ClickHouse Pydantic Config](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/commands/clickhouse-pydantic-config.md) - new (+217)
- [Cloudflare Workers Publish](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/commands/cloudflare-workers-publish.md) - new (+293)
- [Disk Hygiene](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/commands/disk-hygiene.md) - new (+289)
- [Distributed Job Safety](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/commands/distributed-job-safety.md) - new (+673)
- [Doppler Secret Validation](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/commands/doppler-secret-validation.md) - new (+205)
- [Doppler Credential Workflows](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/commands/doppler-workflows.md) - new (+135)
- [Dual-Channel Watchexec Notifications](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/commands/dual-channel-watchexec-notifications.md) - new (+154)
- [Dual-Channel Watchexec Notifications](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/commands/dual-channel-watchexec.md) - new (+154)
- [Firecrawl Self-Hosted Operations](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/commands/firecrawl-self-hosted.md) - new (+561)
- [ML Data Pipeline Architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/commands/ml-data-pipeline-architecture.md) - new (+328)
- [ML Fail-Fast Validation](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/commands/ml-failfast-validation.md) - new (+481)
- [MLflow Python Skill](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/commands/mlflow-python.md) - new (+176)
- [Project Directory Migration](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/commands/project-directory-migration.md) - new (+169)
- [Pueue Job Orchestration](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/commands/pueue-job-orchestration.md) - new (+1103)
- [Python Logging Best Practices](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/commands/python-logging-best-practices.md) - new (+208)
- [Session Chronicle](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/commands/session-chronicle.md) - new (+818)
- [Claude Code Session Recovery Skill](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/commands/session-recovery.md) - new (+87)

</details>

<details>
<summary><strong>doc-tools</strong> (9 commands)</summary>

- [ASCII Diagram Validator](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/commands/ascii-diagram-validator.md) - new (+172)
- [Documentation Standards](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/commands/documentation-standards.md) - new (+206)
- [Glossary Management](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/commands/glossary-management.md) - new (+269)
- [LaTeX Build Automation](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/commands/latex-build.md) - new (+127)
- [LaTeX Environment Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/commands/latex-setup.md) - new (+101)
- [LaTeX Tables with tabularray](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/commands/latex-tables.md) - new (+131)
- [Pandoc PDF Generation](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/commands/pandoc-pdf-generation.md) - new (+256)
- [Plotext Financial Chart Skill](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/commands/plotext-financial-chart.md) - new (+152)
- [Terminal Print](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/commands/terminal-print.md) - new (+127)

</details>

<details>
<summary><strong>dotfiles-tools</strong> (1 command)</summary>

- [Chezmoi Workflows](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/commands/chezmoi-workflows.md) - new (+203)

</details>

<details>
<summary><strong>gdrive-tools</strong> (1 command)</summary>

- [Google Drive Access](https://github.com/terrylica/cc-skills/blob/main/plugins/gdrive-tools/commands/gdrive-access.md) - new (+247)

</details>

<details>
<summary><strong>gmail-commander</strong> (4 commands)</summary>

- [Bot Process Control](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/commands/bot-process-control.md) - new (+255)
- [Email Triage (Scheduled Digest)](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/commands/email-triage.md) - new (+67)
- [Gmail Access](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/commands/gmail-access.md) - new (+368)
- [Interactive Bot](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/commands/interactive-bot.md) - new (+72)

</details>

<details>
<summary><strong>imessage-tools</strong> (1 command)</summary>

- [iMessage Database Query](https://github.com/terrylica/cc-skills/blob/main/plugins/imessage-tools/commands/imessage-query.md) - new (+311)

</details>

<details>
<summary><strong>iterm2-layout-config</strong> (1 command)</summary>

- [iTerm2 Layout Configuration](https://github.com/terrylica/cc-skills/blob/main/plugins/iterm2-layout-config/commands/iterm2-layout.md) - new (+206)

</details>

<details>
<summary><strong>itp</strong> (11 commands)</summary>

- [ADR Code Traceability](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/adr-code-traceability.md) - new (+104)
- [ADR Graph-Easy Architect](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/adr-graph-easy-architect.md) - new (+702)
- [Bootstrap Polyglot Monorepo](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/bootstrap-monorepo.md) - new (+58)
- [Code Hardcode Audit](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/code-hardcode-audit.md) - new (+128)
- [Graph-Easy Diagram Skill](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/graph-easy.md) - new (+691)
- [Implementation Standards](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/impl-standards.md) - new (+159)
- [Implement Plan Preflight](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/implement-plan-preflight.md) - new (+175)
- [mise Configuration as Single Source of Truth](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/mise-configuration.md) - new (+577)
- [mise Tasks Orchestration](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/mise-tasks.md) - new (+700)
- [PyPI Publishing with Doppler (Local-Only)](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/pypi-doppler.md) - new (+603)
- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/semantic-release.md) - new (+374)

</details>

<details>
<summary><strong>itp-hooks</strong> (1 command)</summary>

- [Hooks Development](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/commands/hooks-development.md) - new (+139)

</details>

<details>
<summary><strong>link-tools</strong> (1 command)</summary>

- [Link Validator](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/commands/link-validator.md) - new (+126)

</details>

<details>
<summary><strong>mql5</strong> (4 commands)</summary>

- [MQL5 Article Extractor](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/commands/article-extractor.md) - new (+98)
- [MT5 Log Reader](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/commands/log-reader.md) - new (+205)
- [MQL5 Visual Indicator Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/commands/mql5-indicator-patterns.md) - new (+104)
- [MQL5-Python Translation Workspace Skill](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/commands/python-workspace.md) - new (+95)

</details>

<details>
<summary><strong>notion-api</strong> (1 command)</summary>

- [Notion SDK Skill](https://github.com/terrylica/cc-skills/blob/main/plugins/notion-api/commands/notion-sdk.md) - new (+324)

</details>

<details>
<summary><strong>plugin-dev</strong> (2 commands)</summary>

- [Plugin Validator](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/commands/plugin-validator.md) - new (+156)
- [Skill Architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/commands/skill-architecture.md) - new (+441)

</details>

<details>
<summary><strong>productivity-tools</strong> (2 commands)</summary>

- [Calendar Event Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/commands/calendar-event-manager.md) - new (+170)
- [Slash Command Factory](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/commands/slash-command-factory.md) - new (+1186)

</details>

<details>
<summary><strong>quality-tools</strong> (8 commands)</summary>

- [ClickHouse Architect](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/commands/clickhouse-architect.md) - new (+345)
- [Code Clone Assistant](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/commands/code-clone-assistant.md) - new (+155)
- [Dead Code Detector](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/commands/dead-code-detector.md) - new (+339)
- [Multi-Agent E2E Validation](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/commands/multi-agent-e2e-validation.md) - new (+396)
- [Multi-Agent Performance Profiling](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/commands/multi-agent-performance-profiling.md) - new (+406)
- [Pre-Ship Review](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/commands/pre-ship-review.md) - new (+257)
- [Schema E2E Validation](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/commands/schema-e2e-validation.md) - new (+236)
- [Symmetric Dogfooding](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/commands/symmetric-dogfooding.md) - new (+274)

</details>

<details>
<summary><strong>quant-research</strong> (4 commands)</summary>

- [Adaptive Walk-Forward Epoch Selection (AWFES)](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/commands/adaptive-wfo-epoch.md) - new (+1522)
- [backtesting.py Oracle Validation for Range Bar Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/commands/backtesting-py-oracle.md) - new (+197)
- [Evolutionary Metric Ranking](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/commands/evolutionary-metric-ranking.md) - new (+491)
- [Range Bar Evaluation Metrics](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/commands/rangebar-eval-metrics.md) - new (+236)

</details>

<details>
<summary><strong>statusline-tools</strong> (1 command)</summary>

- [Session Info Skill](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/commands/session-info.md) - new (+83)

</details>

<details>
<summary><strong>tts-telegram-sync</strong> (8 commands)</summary>

- [Bot Process Control](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/commands/bot-process-control.md) - new (+121)
- [Clean Component Removal](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/commands/clean-component-removal.md) - new (+156)
- [Component Version Upgrade](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/commands/component-version-upgrade.md) - new (+126)
- [Diagnostic Issue Resolver](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/commands/diagnostic-issue-resolver.md) - new (+153)
- [Full Stack Bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/commands/full-stack-bootstrap.md) - new (+199)
- [Settings and Tuning](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/commands/settings-and-tuning.md) - new (+128)
- [System Health Check](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/commands/system-health-check.md) - new (+196)
- [Voice Quality Audition](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/commands/voice-quality-audition.md) - new (+167)

</details>

## [11.53.2](https://github.com/terrylica/cc-skills/compare/v11.53.1...v11.53.2) (2026-02-20)


### Bug Fixes

* **gh-tools:** expose 5 skills as user-invocable slash commands ([001e9a6](https://github.com/terrylica/cc-skills/commit/001e9a6eb1fb191edef07100f14a2fa9d9930e9c)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools) [#tools](https://github.com/terrylica/cc-skills/issues/tools)





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>gh-tools</strong> (5 commands)</summary>

- [Fork Intelligence](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/commands/fork-intelligence.md) - new (+322)
- [Issue Create Skill](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/commands/issue-create.md) - new (+198)
- [GitHub Issues-First Workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/commands/issues-workflow.md) - new (+453)
- [PR GFM Link Validator](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/commands/pr-gfm-validator.md) - new (+277)
- [Research Archival](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/commands/research-archival.md) - new (+335)

</details>

## [11.53.1](https://github.com/terrylica/cc-skills/compare/v11.53.0...v11.53.1) (2026-02-20)





---

## Documentation Changes

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+27/-25)

### General Documentation

- [Documentation Guide](https://github.com/terrylica/cc-skills/blob/main/docs/CLAUDE.md) - updated (+10)

## Other Documentation

### Other

- [Gmail Commander Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/CLAUDE.md) - updated (+55/-2)
- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+35)

# [11.53.0](https://github.com/terrylica/cc-skills/compare/v11.52.0...v11.53.0) (2026-02-20)


### Features

* **gmail-commander:** add /abort command + hourly OAuth token refresher ([a84d1d4](https://github.com/terrylica/cc-skills/commit/a84d1d4dfacce76d660953b468ce410a97432561))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gmail-commander</strong> (1 change)</summary>

- [bot-process-control](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/bot-process-control/SKILL.md) - updated (+104/-3)

</details>

# [11.52.0](https://github.com/terrylica/cc-skills/compare/v11.51.2...v11.52.0) (2026-02-20)


### Bug Fixes

* **docs:** second documentation alignment pass from 9-agent audit ([991a6d4](https://github.com/terrylica/cc-skills/commit/991a6d43ada9e3e53cde4f8beeb8cf393fb8d297))


### Features

* **mise:** /mise:run-full-release handles PyPI + crates.io end-to-end ([783c991](https://github.com/terrylica/cc-skills/commit/783c991d201f19737193504f92aa4ed13b9f7cf5))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| accepted | [Ralph Dual Time Tracking (Runtime + Wall-Clock)](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-22-ralph-dual-time-tracking.md) | updated (+5) |
| accepted | [Ralph Stop Visibility Observability](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-22-ralph-stop-visibility-observability.md) | updated (+5) |
| accepted | [Skill Bash Compatibility Enforcement](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-22-skill-bash-compatibility-enforcement.md) | updated (+5) |
| accepted | [asciinema-tools Plugin Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-24-asciinema-tools-plugin.md) | updated (+5) |
| accepted | [asciinema-tools Daemon Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-26-asciinema-daemon-architecture.md) | updated (+13/-8) |
| accepted | [Ralph Constraint Scanning](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-29-ralph-constraint-scanning.md) | updated (+6/-1) |
| accepted | [gh-tools WebFetch Enforcement Hook](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-03-gh-tools-webfetch-enforcement.md) | updated (+23/-15) |
| accepted | [gh issue create --body-file Requirement](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-11-gh-issue-body-file-guard.md) | updated (+6) |
| accepted | [mise gh CLI Incompatibility with Claude Code](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-12-mise-gh-cli-incompatibility.md) | updated (+5) |
| accepted | [mise.toml Hygiene Guard Hook](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-02-05-mise-hygiene-guard.md) | updated (+5) |

## Plugin Documentation

### Skills

<details>
<summary><strong>alpha-forge-worktree</strong> (1 change)</summary>

- [worktree-manager](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-worktree/skills/worktree-manager/SKILL.md) - updated (+2/-1)

</details>

<details>
<summary><strong>devops-tools</strong> (3 changes)</summary>

- [firecrawl-self-hosted](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-self-hosted/SKILL.md) - updated (+1)
- [ml-data-pipeline-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/ml-data-pipeline-architecture/SKILL.md) - updated (+1)
- [ml-failfast-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/ml-failfast-validation/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>doc-tools</strong> (5 changes)</summary>

- [ascii-diagram-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/ascii-diagram-validator/SKILL.md) - updated (+1)
- [documentation-standards](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/documentation-standards/SKILL.md) - updated (+1)
- [glossary-management](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/glossary-management/SKILL.md) - updated (+1)
- [pandoc-pdf-generation](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/pandoc-pdf-generation/SKILL.md) - updated (+1)
- [terminal-print](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/terminal-print/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [pr-gfm-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/pr-gfm-validator/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>gmail-commander</strong> (1 change)</summary>

- [bot-process-control](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/bot-process-control/SKILL.md) - updated (+8/-8)

</details>

<details>
<summary><strong>iterm2-layout-config</strong> (1 change)</summary>

- [iterm2-layout](https://github.com/terrylica/cc-skills/blob/main/plugins/iterm2-layout-config/skills/iterm2-layout/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>itp</strong> (7 changes)</summary>

- [adr-code-traceability](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/adr-code-traceability/SKILL.md) - updated (+1)
- [adr-graph-easy-architect](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/adr-graph-easy-architect/SKILL.md) - updated (+1)
- [graph-easy](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/graph-easy/SKILL.md) - updated (+1)
- [impl-standards](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/impl-standards/SKILL.md) - updated (+1)
- [implement-plan-preflight](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/implement-plan-preflight/SKILL.md) - updated (+1)
- [mise-configuration](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-configuration/SKILL.md) - updated (+1/-1)
- [pypi-doppler](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/pypi-doppler/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>itp-hooks</strong> (1 change)</summary>

- [hooks-development](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>link-tools</strong> (2 changes)</summary>

- [link-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/skills/link-validation/SKILL.md) - updated (+1)
- [link-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/skills/link-validator/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>mql5</strong> (1 change)</summary>

- [python-workspace](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/python-workspace/SKILL.md) - updated (+2/-1)

</details>

<details>
<summary><strong>productivity-tools</strong> (1 change)</summary>

- [calendar-event-manager](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/calendar-event-manager/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>quality-tools</strong> (5 changes)</summary>

- [multi-agent-e2e-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/multi-agent-e2e-validation/SKILL.md) - updated (+1)
- [multi-agent-performance-profiling](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/multi-agent-performance-profiling/SKILL.md) - updated (+1)
- [pre-ship-review](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/pre-ship-review/SKILL.md) - updated (+1)
- [schema-e2e-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/schema-e2e-validation/SKILL.md) - updated (+9/-9)
- [symmetric-dogfooding](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/symmetric-dogfooding/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>quant-research</strong> (1 change)</summary>

- [backtesting-py-oracle](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/backtesting-py-oracle/SKILL.md) - updated (+1)

</details>

<details>
<summary><strong>statusline-tools</strong> (1 change)</summary>

- [session-info](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/session-info/SKILL.md) - updated (+2/-1)

</details>


### Plugin READMEs

- [mise](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/README.md) - new (+85)

### Skill References

<details>
<summary><strong>asciinema-tools/asciinema-converter</strong> (1 file)</summary>

- [Integration Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-converter/references/integration-guide.md) - updated (+2/-2)

</details>

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+1/-1)

</details>

<details>
<summary><strong>plugin-dev/skill-architecture</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/evolution-log.md) - updated (+1/-1)

</details>

<details>
<summary><strong>statusline-tools/session-info</strong> (1 file)</summary>

- [Session Registry Format](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/session-info/references/registry-format.md) - updated (+2/-2)

</details>

<details>
<summary><strong>tts-telegram-sync/bot-process-control</strong> (1 file)</summary>

- [Operational Commands](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/bot-process-control/references/operational-commands.md) - updated (+1/-1)

</details>


### Commands

<details>
<summary><strong>asciinema-tools</strong> (1 command)</summary>

- [/asciinema-tools:daemon-setup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-setup.md) - updated (+2/-2)

</details>

<details>
<summary><strong>calcom-commander</strong> (2 commands)</summary>

- [Cal.com Commander Health Check](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/commands/health.md) - updated (+1/-1)
- [Cal.com Commander Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/commands/setup.md) - updated (+5/-5)

</details>

<details>
<summary><strong>dotfiles-tools</strong> (1 command)</summary>

- [Dotfiles Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/commands/hooks.md) - updated (+1/-1)

</details>

<details>
<summary><strong>gh-tools</strong> (1 command)</summary>

- [gh-tools Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/commands/hooks.md) - updated (+1/-1)

</details>

<details>
<summary><strong>gmail-commander</strong> (2 commands)</summary>

- [Gmail Commander Health Check](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/commands/health.md) - updated (+1/-1)
- [Gmail Commander Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/commands/setup.md) - updated (+5/-5)

</details>

<details>
<summary><strong>itp</strong> (3 commands)</summary>

- [⛔ ITP Workflow — STOP AND READ](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/go.md) - updated (+1/-1)
- [ITP Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/hooks.md) - updated (+1/-1)
- [ITP Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/setup.md) - updated (+1/-1)

</details>

<details>
<summary><strong>itp-hooks</strong> (1 command)</summary>

- [ITP Hooks Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/commands/setup.md) - updated (+1/-1)

</details>

<details>
<summary><strong>mise</strong> (1 command)</summary>

- [/mise:run-full-release](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/commands/run-full-release.md) - updated (+263/-25)

</details>

<details>
<summary><strong>plugin-dev</strong> (1 command)</summary>

- [⛔ Create Plugin — STOP AND READ](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/commands/create.md) - updated (+1/-1)

</details>

<details>
<summary><strong>productivity-tools</strong> (1 command)</summary>

- [productivity-tools Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/commands/hooks.md) - updated (+1/-1)

</details>

<details>
<summary><strong>ru</strong> (9 commands)</summary>

- [RU: Audit Now](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/audit-now.md) - updated (+1/-1)
- [RU: Config](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/config.md) - updated (+1/-1)
- [RU: Encourage](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/encourage.md) - updated (+1/-1)
- [RU: Forbid](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/forbid.md) - updated (+1/-1)
- [RU: Hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/hooks.md) - updated (+1/-1)
- [RU: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/start.md) - updated (+1/-1)
- [RU: Status](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/status.md) - updated (+1/-1)
- [RU: Stop](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/stop.md) - updated (+1/-1)
- [RU: Wizard](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/wizard.md) - updated (+1/-1)

</details>

<details>
<summary><strong>statusline-tools</strong> (3 commands)</summary>

- [Status Line Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/commands/hooks.md) - updated (+1/-1)
- [Global Ignore Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/commands/ignore.md) - updated (+1/-1)
- [Status Line Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/commands/setup.md) - updated (+1/-1)

</details>

<details>
<summary><strong>tts-telegram-sync</strong> (3 commands)</summary>

- [TTS Telegram Sync Health Check](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/commands/health.md) - updated (+1/-1)
- [TTS Telegram Sync Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/commands/hooks.md) - updated (+1/-1)
- [TTS Telegram Sync Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/commands/setup.md) - updated (+1/-1)

</details>


## Other Documentation

### Other

- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (+29/-12)
- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+2/-2)

## [11.51.2](https://github.com/terrylica/cc-skills/compare/v11.51.1...v11.51.2) (2026-02-19)


### Bug Fixes

* **itp-hooks:** scope Vale terminology checks to changed lines only ([a6598b1](https://github.com/terrylica/cc-skills/commit/a6598b1f4ac16cc216de77d1c7d99b282f8736bd))

## [11.51.1](https://github.com/terrylica/cc-skills/compare/v11.51.0...v11.51.1) (2026-02-19)





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>mise</strong> (1 command)</summary>

- [/mise:run-full-release](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/commands/run-full-release.md) - updated (+22/-12)

</details>

# [11.51.0](https://github.com/terrylica/cc-skills/compare/v11.50.0...v11.51.0) (2026-02-19)


### Features

* **commands:** add model: haiku to 29 procedural slash commands ([ae34ec9](https://github.com/terrylica/cc-skills/commit/ae34ec95afa8897c5b494fd0828738781f8bead1))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>asciinema-tools</strong> (7 commands)</summary>

- [/asciinema-tools:daemon-logs](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-logs.md) - updated (+1)
- [/asciinema-tools:daemon-start](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-start.md) - updated (+1)
- [/asciinema-tools:daemon-status](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-status.md) - updated (+1)
- [/asciinema-tools:daemon-stop](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-stop.md) - updated (+1)
- [/asciinema-tools:format](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/format.md) - updated (+1)
- [/asciinema-tools:play](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/play.md) - updated (+1)
- [/asciinema-tools:setup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/setup.md) - updated (+1)

</details>

<details>
<summary><strong>calcom-commander</strong> (1 command)</summary>

- [Cal.com Commander Health Check](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/commands/health.md) - updated (+1)

</details>

<details>
<summary><strong>dotfiles-tools</strong> (1 command)</summary>

- [Dotfiles Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/commands/hooks.md) - updated (+1)

</details>

<details>
<summary><strong>gh-tools</strong> (1 command)</summary>

- [gh-tools Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/commands/hooks.md) - updated (+1)

</details>

<details>
<summary><strong>git-town-workflow</strong> (1 command)</summary>

- [Git-Town Enforcement Hooks — Installation](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/commands/hooks.md) - updated (+1)

</details>

<details>
<summary><strong>gmail-commander</strong> (1 command)</summary>

- [Gmail Commander Health Check](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/commands/health.md) - updated (+1)

</details>

<details>
<summary><strong>itp</strong> (1 command)</summary>

- [ITP Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/hooks.md) - updated (+1)

</details>

<details>
<summary><strong>itp-hooks</strong> (1 command)</summary>

- [ITP Hooks Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/commands/setup.md) - updated (+1)

</details>

<details>
<summary><strong>mise</strong> (3 commands)</summary>

- [/mise:list-repo-tasks](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/commands/list-repo-tasks.md) - updated (+1)
- [/mise:run-full-release](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/commands/run-full-release.md) - updated (+6/-2)
- [/mise:show-env-status](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/commands/show-env-status.md) - updated (+1)

</details>

<details>
<summary><strong>productivity-tools</strong> (1 command)</summary>

- [productivity-tools Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/commands/hooks.md) - updated (+1)

</details>

<details>
<summary><strong>ru</strong> (7 commands)</summary>

- [RU: Audit Now](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/audit-now.md) - updated (+1)
- [RU: Config](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/config.md) - updated (+1)
- [RU: Encourage](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/encourage.md) - updated (+1)
- [RU: Forbid](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/forbid.md) - updated (+1)
- [RU: Hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/hooks.md) - updated (+1)
- [RU: Status](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/status.md) - updated (+1)
- [RU: Stop](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/stop.md) - updated (+1)

</details>

<details>
<summary><strong>statusline-tools</strong> (3 commands)</summary>

- [Status Line Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/commands/hooks.md) - updated (+1)
- [Global Ignore Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/commands/ignore.md) - updated (+1)
- [Status Line Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/commands/setup.md) - updated (+1)

</details>

<details>
<summary><strong>tts-telegram-sync</strong> (2 commands)</summary>

- [TTS Telegram Sync Health Check](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/commands/health.md) - updated (+1)
- [TTS Telegram Sync Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/commands/hooks.md) - updated (+1)

</details>

# [11.50.0](https://github.com/terrylica/cc-skills/compare/v11.49.0...v11.50.0) (2026-02-19)


### Bug Fixes

* **hooks:** add jq error handling and +x permission for bash hooks ([5ad7ded](https://github.com/terrylica/cc-skills/commit/5ad7ded6168d3045e10b2c0d25b13b6acc141007))


### Features

* **mise:** add model: haiku to run-full-release slash command ([9aa2d1e](https://github.com/terrylica/cc-skills/commit/9aa2d1ee4b65a3fec36d377e33e1ce955e4089b9))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>mise</strong> (1 command)</summary>

- [/mise:run-full-release](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/commands/run-full-release.md) - updated (+1)

</details>

# [11.49.0](https://github.com/terrylica/cc-skills/compare/v11.48.0...v11.49.0) (2026-02-19)


### Bug Fixes

* **docs:** comprehensive documentation alignment from 9-agent audit ([775a6fd](https://github.com/terrylica/cc-skills/commit/775a6fd3d02d5132e19d2998586e565ccb0b07cd)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools) [#tools](https://github.com/terrylica/cc-skills/issues/tools)
* **itp-hooks:** scope code-correctness-guard to changed lines for Edit tool ([e8de281](https://github.com/terrylica/cc-skills/commit/e8de28189600f61b3697bb62fb28b02b772bd5c7))


### Features

* **statusline-tools:** rename Session UUID label to ~/.claude/projects JSONL ID ([42f42f8](https://github.com/terrylica/cc-skills/commit/42f42f8a3771666435aaa89563b8a2e461116aa0))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| accepted | [Ralph Eternal Loop Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-20-ralph-rssi-eternal-loop.md) | updated (+1/-1) |
| unknown | [Ralph Dual Time Tracking (Runtime + Wall-Clock)](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-22-ralph-dual-time-tracking.md) | updated (+1/-1) |
| unknown | [Ralph Stop Visibility Observability](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-22-ralph-stop-visibility-observability.md) | updated (+1/-1) |
| unknown | [Ralph Constraint Scanning](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-29-ralph-constraint-scanning.md) | updated (+1/-1) |
| accepted | [Ralph Guidance Freshness Detection](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-02-ralph-guidance-freshness-detection.md) | updated (+8/-8) |

### Design Specs

- [Design Spec: Ralph Eternal Loop Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-20-ralph-rssi-eternal-loop/spec.md) - coupled
- [Diagnosis: /ralph:encourage → Stop Hook Data Flow](https://github.com/terrylica/cc-skills/blob/main/docs/design/2026-01-02-ralph-guidance-freshness-detection/spec.md) - coupled

## Plugin Documentation

### Skills

<details>
<summary><strong>statusline-tools</strong> (1 change)</summary>

- [session-info](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/session-info/SKILL.md) - updated (+1/-1)

</details>


### Plugin READMEs

- [devops-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/README.md) - updated (+3/-1)
- [gh-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/README.md) - updated (+8/-6)
- [quality-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/README.md) - updated (+3/-1)
- [statusline-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/README.md) - updated (+2/-2)

### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+4/-4)

</details>


### Commands

<details>
<summary><strong>asciinema-tools</strong> (18 commands)</summary>

- [/asciinema-tools:analyze](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/analyze.md) - updated (+1)
- [/asciinema-tools:backup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/backup.md) - updated (+1)
- [/asciinema-tools:bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/bootstrap.md) - updated (+1)
- [/asciinema-tools:convert](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/convert.md) - updated (+1)
- [/asciinema-tools:daemon-logs](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-logs.md) - updated (+1)
- [/asciinema-tools:daemon-setup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-setup.md) - updated (+1)
- [/asciinema-tools:daemon-start](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-start.md) - updated (+1)
- [/asciinema-tools:daemon-status](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-status.md) - updated (+1)
- [/asciinema-tools:daemon-stop](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-stop.md) - updated (+1)
- [/asciinema-tools:finalize](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/finalize.md) - updated (+1)
- [/asciinema-tools:format](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/format.md) - updated (+1)
- [/asciinema-tools:full-workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/full-workflow.md) - updated (+1)
- [/asciinema-tools:hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/hooks.md) - updated (+1)
- [/asciinema-tools:play](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/play.md) - updated (+1)
- [/asciinema-tools:post-session](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/post-session.md) - updated (+1)
- [/asciinema-tools:record](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/record.md) - updated (+1)
- [/asciinema-tools:setup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/setup.md) - updated (+1)
- [/asciinema-tools:summarize](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/summarize.md) - updated (+1)

</details>

<details>
<summary><strong>dotfiles-tools</strong> (1 command)</summary>

- [Dotfiles Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/commands/hooks.md) - updated (+1)

</details>

<details>
<summary><strong>gh-tools</strong> (1 command)</summary>

- [gh-tools Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/commands/hooks.md) - updated (+1)

</details>

<details>
<summary><strong>git-town-workflow</strong> (4 commands)</summary>

- [Git-Town Contribution Workflow — STOP AND READ](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/commands/contribute.md) - updated (+1)
- [Git-Town Fork Workflow — STOP AND READ](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/commands/fork.md) - updated (+1)
- [Git-Town Enforcement Hooks — Installation](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/commands/hooks.md) - updated (+1)
- [Git-Town Setup — One-Time Configuration](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/commands/setup.md) - updated (+1)

</details>

<details>
<summary><strong>itp</strong> (3 commands)</summary>

- [⛔ ITP Workflow — STOP AND READ](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/go.md) - updated (+1)
- [ITP Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/hooks.md) - updated (+1)
- [ITP Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/setup.md) - updated (+1)

</details>

<details>
<summary><strong>itp-hooks</strong> (1 command)</summary>

- [ITP Hooks Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/commands/setup.md) - updated (+1)

</details>

<details>
<summary><strong>plugin-dev</strong> (1 command)</summary>

- [⛔ Create Plugin — STOP AND READ](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/commands/create.md) - updated (+1)

</details>

<details>
<summary><strong>productivity-tools</strong> (1 command)</summary>

- [productivity-tools Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/commands/hooks.md) - updated (+1)

</details>

<details>
<summary><strong>ru</strong> (9 commands)</summary>

- [RU: Audit Now](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/audit-now.md) - updated (+1)
- [RU: Config](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/config.md) - updated (+1)
- [RU: Encourage](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/encourage.md) - updated (+1)
- [RU: Forbid](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/forbid.md) - updated (+1)
- [RU: Hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/hooks.md) - updated (+1)
- [RU: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/start.md) - updated (+1)
- [RU: Status](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/status.md) - updated (+1)
- [RU: Stop](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/stop.md) - updated (+1)
- [RU: Wizard](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/wizard.md) - updated (+1)

</details>

<details>
<summary><strong>statusline-tools</strong> (3 commands)</summary>

- [Status Line Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/commands/hooks.md) - updated (+1)
- [Global Ignore Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/commands/ignore.md) - updated (+1)
- [Status Line Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/commands/setup.md) - updated (+1)

</details>

<details>
<summary><strong>tts-telegram-sync</strong> (3 commands)</summary>

- [TTS Telegram Sync Health Check](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/commands/health.md) - updated (+1)
- [TTS Telegram Sync Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/commands/hooks.md) - updated (+1)
- [TTS Telegram Sync Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/commands/setup.md) - updated (+1)

</details>


## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+3/-3)

### General Documentation

- [Hooks Development Guide](https://github.com/terrylica/cc-skills/blob/main/docs/HOOKS.md) - updated (+12/-8)
- [Plugin Authoring Guide](https://github.com/terrylica/cc-skills/blob/main/docs/plugin-authoring.md) - updated (+2/-2)

## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+16/-7)

# [11.48.0](https://github.com/terrylica/cc-skills/compare/v11.47.0...v11.48.0) (2026-02-18)


### Features

* **devops-tools:** add cloudflare-workers-publish skill for static HTML deployment ([70b849f](https://github.com/terrylica/cc-skills/commit/70b849fd8859927613d4f14ba748039a2b5307a7))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [cloudflare-workers-publish](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/cloudflare-workers-publish/SKILL.md) - new (+293)

</details>


### Plugin READMEs

- [devops-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/README.md) - updated (+16/-2)

### Skill References

<details>
<summary><strong>devops-tools/cloudflare-workers-publish</strong> (4 files)</summary>

- [Cloudflare Workers Publish Anti-Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/cloudflare-workers-publish/references/anti-patterns.md) - new (+286)
- [cloudflare-workers-publish Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/cloudflare-workers-publish/references/evolution-log.md) - new (+28)
- [1Password Credential Setup for Cloudflare Workers](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/cloudflare-workers-publish/references/onep-credential-setup.md) - new (+136)
- [Wrangler Setup Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/cloudflare-workers-publish/references/wrangler-setup.md) - new (+87)

</details>

# [11.47.0](https://github.com/terrylica/cc-skills/compare/v11.46.0...v11.47.0) (2026-02-18)


### Features

* **gh-tools:** add fork-intelligence skill for discovering valuable fork divergence ([5cc73a5](https://github.com/terrylica/cc-skills/commit/5cc73a5a087d1768df2db4f77f13ea32bb64cd83)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [fork-intelligence](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/fork-intelligence/SKILL.md) - new (+322)

</details>


### Skill References

<details>
<summary><strong>gh-tools/fork-intelligence</strong> (4 files)</summary>

- [Domain-Specific Fork Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/fork-intelligence/references/domain-patterns.md) - new (+143)
- [Empirical Data — Stars Anti-Correlation](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/fork-intelligence/references/empirical-data.md) - new (+77)
- [Evolution Log — fork-intelligence](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/fork-intelligence/references/evolution-log.md) - new (+10)
- [Signal Priority Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/fork-intelligence/references/signal-priority.md) - new (+124)

</details>


## Other Documentation

### Other

- [gh-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/CLAUDE.md) - updated (+1)

# [11.46.0](https://github.com/terrylica/cc-skills/compare/v11.45.0...v11.46.0) (2026-02-18)


### Bug Fixes

* **pueue:** exclude git commands from pueue wrapping and reminders ([3c55df7](https://github.com/terrylica/cc-skills/commit/3c55df7bcf03d45256ddc3e6aa4af2c68a04f7c2))


### Features

* **mise:** migrate sred-commit-guard from hook to /mise:sred-commit command ([1829bf2](https://github.com/terrylica/cc-skills/commit/1829bf2f435419aaa3569cf2997699e6fad24148))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>mise</strong> (1 command)</summary>

- [/mise:sred-commit](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/commands/sred-commit.md) - new (+100)

</details>


## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+2/-1)
- [mise Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/CLAUDE.md) - updated (+6/-5)

# [11.45.0](https://github.com/terrylica/cc-skills/compare/v11.44.1...v11.45.0) (2026-02-17)


### Features

* **distributed-job-safety:** add INV-9 artifact category isolation + AP-17 ([9412097](https://github.com/terrylica/cc-skills/commit/94120978cd38c6fa0367e76ae81e504ad7c3aff8))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [distributed-job-safety](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/SKILL.md) - updated (+61/-2)

</details>


### Skill References

<details>
<summary><strong>devops-tools/distributed-job-safety</strong> (1 file)</summary>

- [Concurrency Invariants](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/references/concurrency-invariants.md) - updated (+48)

</details>

## [11.44.1](https://github.com/terrylica/cc-skills/compare/v11.44.0...v11.44.1) (2026-02-17)





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

- [Troubleshooting](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/troubleshooting.md) - updated (+25/-2)

</details>

# [11.44.0](https://github.com/terrylica/cc-skills/compare/v11.43.5...v11.44.0) (2026-02-16)


### Bug Fixes

* **hooks:** replace console.error with trackHookError across 29 hook files ([79fe6dd](https://github.com/terrylica/cc-skills/commit/79fe6dd4cb728a233c6569141d971227facef87b))


### Features

* **itp-hooks:** add hook-error-tracker library with threshold-based escalation ([eb6f83a](https://github.com/terrylica/cc-skills/commit/eb6f83ad3a1a59d07260ef82e50dcc9a31d42620))





---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+49/-8)

</details>

## [11.43.5](https://github.com/terrylica/cc-skills/compare/v11.43.4...v11.43.5) (2026-02-16)


### Bug Fixes

* **mise:** auto-resolve dirty working directory before release ([3705a1f](https://github.com/terrylica/cc-skills/commit/3705a1fc144e08afae884fef84b4c0816ad4c493))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>mise</strong> (1 command)</summary>

- [/mise:run-full-release](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/commands/run-full-release.md) - updated (+18/-3)

</details>

## [11.43.4](https://github.com/terrylica/cc-skills/compare/v11.43.3...v11.43.4) (2026-02-16)


### Bug Fixes

* **tts-telegram-sync:** resolve symlinks in SCRIPT_DIR for reliable path detection ([069f53b](https://github.com/terrylica/cc-skills/commit/069f53bfb69cfa8b8ecdbdf0c0ae8c5c46846e4f))

## [11.43.3](https://github.com/terrylica/cc-skills/compare/v11.43.2...v11.43.3) (2026-02-16)


### Bug Fixes

* **itp-hooks:** exclude Pydantic default_factory from fake-data guard ([fec9442](https://github.com/terrylica/cc-skills/commit/fec94427eb77f848bc55e5250583cc8934f315b3))

## [11.43.2](https://github.com/terrylica/cc-skills/compare/v11.43.1...v11.43.2) (2026-02-16)


### Bug Fixes

* **itp-hooks:** narrow ruff hook to silent failure patterns only ([d6fb9fa](https://github.com/terrylica/cc-skills/commit/d6fb9fae7d659c65389c11e263a2d12febef4b25))

## [11.43.1](https://github.com/terrylica/cc-skills/compare/v11.43.0...v11.43.1) (2026-02-16)





---

## Documentation Changes

## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+11)

# [11.43.0](https://github.com/terrylica/cc-skills/compare/v11.42.0...v11.43.0) (2026-02-15)


### Features

* **itp-hooks:** add native binary guard for macOS launchd automation ([72edf29](https://github.com/terrylica/cc-skills/commit/72edf292c07bde841e5f21c95a4cf3db93387a6d))





---

## Documentation Changes

## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+53)

# [11.42.0](https://github.com/terrylica/cc-skills/compare/v11.41.1...v11.42.0) (2026-02-15)


### Features

* **mise:** add mise plugin with command distribution infrastructure ([b89bf0e](https://github.com/terrylica/cc-skills/commit/b89bf0e420f33a28cb59f58cba05cd8424f63729))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>mise</strong> (3 commands)</summary>

- [/mise:list-repo-tasks](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/commands/list-repo-tasks.md) - new (+98)
- [/mise:run-full-release](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/commands/run-full-release.md) - new (+108)
- [/mise:show-env-status](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/commands/show-env-status.md) - new (+82)

</details>


## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+11/-9)

## Other Documentation

### Other

- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (+1)
- [mise Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/mise/CLAUDE.md) - new (+53)

## [11.41.1](https://github.com/terrylica/cc-skills/compare/v11.41.0...v11.41.1) (2026-02-15)


### Bug Fixes

* **itp-hooks:** convert fake-data-guard from ask to deny mode ([5d5faac](https://github.com/terrylica/cc-skills/commit/5d5faacc3a621d9a4b1a9b56c59ba505efadef94))





---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+65/-10)

</details>


## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+1/-1)

# [11.41.0](https://github.com/terrylica/cc-skills/compare/v11.40.0...v11.41.0) (2026-02-15)


### Features

* **calcom-commander:** add Pushover dual-channel notifications + webhook relay ([dbf17ea](https://github.com/terrylica/cc-skills/commit/dbf17ea321e1cc86b9053ff7c7d7e6c5ed7f5eef))
* **gmail-commander:** add draft lifecycle management (list, delete, update) ([48294c0](https://github.com/terrylica/cc-skills/commit/48294c087f316cd5a2b65d38b9f8c147a0dd72bc))
* **imessage-tools:** v4 native pitfall protections + full metadata extraction ([a7eb486](https://github.com/terrylica/cc-skills/commit/a7eb486930d6230061cc90bbdc2d3c0d2a419212))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>calcom-commander</strong> (3 changes)</summary>

- [booking-config](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/booking-config/SKILL.md) - updated (+28)
- [booking-notify](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/booking-notify/SKILL.md) - updated (+66/-10)
- [infra-deploy](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/infra-deploy/SKILL.md) - updated (+66)

</details>

<details>
<summary><strong>imessage-tools</strong> (1 change)</summary>

- [imessage-query](https://github.com/terrylica/cc-skills/blob/main/plugins/imessage-tools/skills/imessage-query/SKILL.md) - updated (+30/-2)

</details>


### Skill References

<details>
<summary><strong>calcom-commander/booking-notify</strong> (3 files)</summary>

- [Notification Templates](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/booking-notify/references/notification-templates.md) - updated (+69/-1)
- [Pushover Setup Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/booking-notify/references/pushover-setup.md) - new (+87)
- [Webhook Relay Deployment](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/booking-notify/references/webhook-relay.md) - new (+120)

</details>

<details>
<summary><strong>imessage-tools/imessage-query</strong> (2 files)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/imessage-tools/skills/imessage-query/references/evolution-log.md) - updated (+57)
- [Known Pitfalls](https://github.com/terrylica/cc-skills/blob/main/plugins/imessage-tools/skills/imessage-query/references/known-pitfalls.md) - updated (+41/-15)

</details>


## Other Documentation

### Other

- [Cal.com Commander Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/CLAUDE.md) - updated (+24/-6)

# [11.40.0](https://github.com/terrylica/cc-skills/compare/v11.39.0...v11.40.0) (2026-02-15)


### Features

* **code-clone-assistant:** add accepted exceptions for intentional duplication ([eba0757](https://github.com/terrylica/cc-skills/commit/eba07570159c1e414002a295b7ad38bc4ddc67e8))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>quality-tools</strong> (1 change)</summary>

- [code-clone-assistant](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/code-clone-assistant/SKILL.md) - updated (+58)

</details>


### Skill References

<details>
<summary><strong>quality-tools/code-clone-assistant</strong> (1 file)</summary>

- [Create working directory](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/code-clone-assistant/references/complete-workflow.md) - updated (+27/-18)

</details>

# [11.39.0](https://github.com/terrylica/cc-skills/compare/v11.38.0...v11.39.0) (2026-02-15)


### Features

* **imessage-tools:** v3 3-tier decoder with pytypedstream + cross-repo analysis ([e6e783c](https://github.com/terrylica/cc-skills/commit/e6e783c73bae5098a0fb883bca444e4f342dcdda))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>imessage-tools</strong> (1 change)</summary>

- [imessage-query](https://github.com/terrylica/cc-skills/blob/main/plugins/imessage-tools/skills/imessage-query/SKILL.md) - updated (+11/-3)

</details>


### Skill References

<details>
<summary><strong>imessage-tools/imessage-query</strong> (3 files)</summary>

- [Cross-Repository Analysis: iMessage Decoder Implementations](https://github.com/terrylica/cc-skills/blob/main/plugins/imessage-tools/skills/imessage-query/references/cross-repo-analysis.md) - new (+252)
- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/imessage-tools/skills/imessage-query/references/evolution-log.md) - updated (+34)
- [Known Pitfalls](https://github.com/terrylica/cc-skills/blob/main/plugins/imessage-tools/skills/imessage-query/references/known-pitfalls.md) - updated (+31/-22)

</details>

# [11.38.0](https://github.com/terrylica/cc-skills/compare/v11.37.2...v11.38.0) (2026-02-15)


### Features

* **gmail-commander:** structured email read view + keyboard button fix ([edf839f](https://github.com/terrylica/cc-skills/commit/edf839f16b02dd127d3143faf057117b18c97223))
* **imessage-tools:** add search context flag and NDJSON export ([2606231](https://github.com/terrylica/cc-skills/commit/2606231fd388c2b55f0eff6c1f06fe1b49eba0a9))
* **itp-hooks:** add OP token injector lib + update hook table formatting ([3ac264a](https://github.com/terrylica/cc-skills/commit/3ac264a805abe437423beb4dc5c2248a95093811))
* **quant-research:** add evolutionary metric ranking skill ([6758340](https://github.com/terrylica/cc-skills/commit/6758340360e21ad0d1018476e56f58fe5932c454))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>imessage-tools</strong> (1 change)</summary>

- [imessage-query](https://github.com/terrylica/cc-skills/blob/main/plugins/imessage-tools/skills/imessage-query/SKILL.md) - updated (+57)

</details>

<details>
<summary><strong>quant-research</strong> (1 change)</summary>

- [evolutionary-metric-ranking](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/evolutionary-metric-ranking/SKILL.md) - new (+491)

</details>


### Plugin READMEs

- [quant-research](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/README.md) - updated (+25/-7)

### Skill References

<details>
<summary><strong>imessage-tools/imessage-query</strong> (2 files)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/imessage-tools/skills/imessage-query/references/evolution-log.md) - updated (+30)
- [Known Pitfalls](https://github.com/terrylica/cc-skills/blob/main/plugins/imessage-tools/skills/imessage-query/references/known-pitfalls.md) - updated (+39/-27)

</details>

<details>
<summary><strong>quant-research/evolutionary-metric-ranking</strong> (3 files)</summary>

- [Case Study - Range Bar Pattern Ranking (Issue `#17`)](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/evolutionary-metric-ranking/references/case-study-rangebar-ranking.md) - new (+223)
- [Metric Design Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/evolutionary-metric-ranking/references/metric-design-guide.md) - new (+123)
- [Objective Function Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/evolutionary-metric-ranking/references/objective-functions.md) - new (+223)

</details>


## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+14/-14)

## [11.37.2](https://github.com/terrylica/cc-skills/compare/v11.37.1...v11.37.2) (2026-02-15)


### Bug Fixes

* **itp-hooks:** reduce false positives in storm guard and pueue wrap ([3b59543](https://github.com/terrylica/cc-skills/commit/3b595431e7f962aaec957636b0c1a25330fc1a3c))

## [11.37.1](https://github.com/terrylica/cc-skills/compare/v11.37.0...v11.37.1) (2026-02-14)





---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>gmail-commander/gmail-access</strong> (1 file)</summary>

- [mise Configuration Templates](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/gmail-access/references/mise-templates.md) - updated (+4/-4)

</details>


## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+1/-1)
- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+1/-1)

### General Documentation

- [Session Resume Context](https://github.com/terrylica/cc-skills/blob/main/docs/RESUME.md) - updated (+1/-1)

## Other Documentation

### Other

- [Troubleshooting cc-skills Marketplace Installation](https://github.com/terrylica/cc-skills/blob/main/docs/troubleshooting/marketplace-installation.md) - updated (+1/-1)
- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (+9/-9)

# [11.37.0](https://github.com/terrylica/cc-skills/compare/v11.36.1...v11.37.0) (2026-02-14)


### Bug Fixes

* **gmail-commander:** refactor commands and digest, fix state file path ([88814ab](https://github.com/terrylica/cc-skills/commit/88814ab9331a7faad35d35a714bc92aac3c59cec))


### Features

* **calcom-commander:** add Cal.com + Telegram bot plugin ([9e1acec](https://github.com/terrylica/cc-skills/commit/9e1acecf030def5c10fa8717d9c0edfc3cb158a0))
* **devops-tools:** add pueue+dotenv patterns and mise/checkpoint gotchas ([8b5fab7](https://github.com/terrylica/cc-skills/commit/8b5fab7ab2f4f9e2e86ad48dfd62c76e40592470))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>calcom-commander</strong> (4 changes)</summary>

- [booking-config](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/booking-config/SKILL.md) - new (+138)
- [booking-notify](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/booking-notify/SKILL.md) - new (+75)
- [calcom-access](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/calcom-access/SKILL.md) - new (+176)
- [infra-deploy](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/infra-deploy/SKILL.md) - new (+196)

</details>

<details>
<summary><strong>devops-tools</strong> (2 changes)</summary>

- [distributed-job-safety](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/SKILL.md) - updated (+52/-1)
- [pueue-job-orchestration](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/SKILL.md) - updated (+52)

</details>

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [mise-configuration](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-configuration/SKILL.md) - updated (+33/-6)

</details>


### Plugin READMEs

- [Cal.com Commander](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/README.md) - new (+51)

### Skill References

<details>
<summary><strong>calcom-commander/booking-notify</strong> (2 files)</summary>

- [Notification Templates](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/booking-notify/references/notification-templates.md) - new (+52)
- [Sync Configuration](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/booking-notify/references/sync-config.md) - new (+51)

</details>

<details>
<summary><strong>calcom-commander/calcom-access</strong> (2 files)</summary>

- [Cal.com API Setup Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/calcom-access/references/calcom-api-setup.md) - new (+55)
- [mise Configuration for Cal.com Commander](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/skills/calcom-access/references/mise-setup.md) - new (+65)

</details>

<details>
<summary><strong>devops-tools/distributed-job-safety</strong> (1 file)</summary>

- [Environment Gotchas](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/references/environment-gotchas.md) - updated (+109/-16)

</details>


### Commands

<details>
<summary><strong>calcom-commander</strong> (2 commands)</summary>

- [Cal.com Commander Health Check](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/commands/health.md) - new (+96)
- [Cal.com Commander Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/commands/setup.md) - new (+191)

</details>


## Other Documentation

### Other

- [Cal.com Commander Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/calcom-commander/CLAUDE.md) - new (+35)

## [11.36.1](https://github.com/terrylica/cc-skills/compare/v11.36.0...v11.36.1) (2026-02-14)


### Bug Fixes

* **hooks:** use canonical object format in gmail-commander hooks.json ([2ff36bb](https://github.com/terrylica/cc-skills/commit/2ff36bbf8fcf12c363161d7fa4e21fb3f623979f))





---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (2 files)</summary>

- [Hook Templates](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/hook-templates.md) - updated (+53)
- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+74/-18)

</details>

# [11.36.0](https://github.com/terrylica/cc-skills/compare/v11.35.2...v11.36.0) (2026-02-14)


### Features

* **gmail-commander:** interactive Telegram bot with Agent SDK, absorb gmail-tools ([65b2d12](https://github.com/terrylica/cc-skills/commit/65b2d12e89c0f3504b5f8ee732e7b890e592931d))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gmail-commander</strong> (4 changes)</summary>

- [bot-process-control](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/bot-process-control/SKILL.md) - new (+154)
- [email-triage](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/email-triage/SKILL.md) - new (+67)
- [gmail-access](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/gmail-access/SKILL.md) - renamed from `plugins/gmail-tools/skills/gmail-access/SKILL.md`
- [interactive-bot](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/interactive-bot/SKILL.md) - new (+72)

</details>


### Plugin READMEs

- [Gmail Commander](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/README.md) - new (+51)
- [gmail-tools](https://github.com/terrylica/cc-skills/blob/v11.35.2/plugins/gmail-tools/README.md) - deleted

### Skill References

<details>
<summary><strong>gmail-commander/gmail-access</strong> (4 files)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/gmail-access/references/evolution-log.md) - renamed from `plugins/gmail-tools/skills/gmail-access/references/evolution-log.md`
- [Gmail API OAuth Setup Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/gmail-access/references/gmail-api-setup.md) - renamed from `plugins/gmail-tools/skills/gmail-access/references/gmail-api-setup.md`
- [mise Setup Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/gmail-access/references/mise-setup.md) - renamed from `plugins/gmail-tools/skills/gmail-access/references/mise-setup.md`
- [mise Configuration Templates](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/skills/gmail-access/references/mise-templates.md) - renamed from `plugins/gmail-tools/skills/gmail-access/references/mise-templates.md`

</details>


### Commands

<details>
<summary><strong>gmail-commander</strong> (2 commands)</summary>

- [Gmail Commander Health Check](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/commands/health.md) - new (+84)
- [Gmail Commander Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/commands/setup.md) - new (+152)

</details>

<details>
<summary><strong>gmail-tools</strong> (1 command)</summary>

- [setup](https://github.com/terrylica/cc-skills/blob/v11.35.2/plugins/gmail-tools/commands/setup.md) - deleted

</details>


## Other Documentation

### Other

- [Gmail Commander Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-commander/CLAUDE.md) - new (+35)

## [11.35.2](https://github.com/terrylica/cc-skills/compare/v11.35.1...v11.35.2) (2026-02-13)





---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+19/-17)

</details>

<details>
<summary><strong>plugin-dev/skill-architecture</strong> (2 files)</summary>

- [Agent Skill Name](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/advanced-topics.md) - updated (+14/-2)
- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/evolution-log.md) - updated (+20)

</details>

## [11.35.1](https://github.com/terrylica/cc-skills/compare/v11.35.0...v11.35.1) (2026-02-13)


### Bug Fixes

* **tts-telegram-sync:** resolve $CLAUDE_PLUGIN_ROOT in stop hook path ([4ec307d](https://github.com/terrylica/cc-skills/commit/4ec307de5659c8118b3f51b794757d85d4eb7f98))

# [11.35.0](https://github.com/terrylica/cc-skills/compare/v11.34.1...v11.35.0) (2026-02-13)


### Features

* **plugin-dev:** add advanced patterns to skill-architecture from tts-telegram-sync ([62384d3](https://github.com/terrylica/cc-skills/commit/62384d38e8515b759dee640f924fbf2ea385d588))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>plugin-dev</strong> (1 change)</summary>

- [skill-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/SKILL.md) - updated (+23/-2)

</details>


### Skill References

<details>
<summary><strong>plugin-dev/skill-architecture</strong> (8 files)</summary>

- [Agent Skill Name](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/advanced-topics.md) - updated (+97)
- [Command-Skill Duality](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/command-skill-duality.md) - new (+132)
- [Creation Workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/creation-workflow.md) - updated (+11/-6)
- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/evolution-log.md) - updated (+21)
- [Interactive Patterns (AskUserQuestion)](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/interactive-patterns.md) - new (+265)
- [Phased Execution Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/phased-execution.md) - new (+223)
- [Scripts Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/scripts-reference.md) - updated (+52/-4)
- [Structural Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/structural-patterns.md) - updated (+65/-6)

</details>

## [11.34.1](https://github.com/terrylica/cc-skills/compare/v11.34.0...v11.34.1) (2026-02-13)


### Bug Fixes

* **devops-tools:** remove stale telegram-bot-management references ([518cb26](https://github.com/terrylica/cc-skills/commit/518cb269dda83d0a7cd652c75e6856f8027b4ec4))





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [devops-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/README.md) - updated (+2/-11)

## Repository Documentation

### Root Documentation

- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+2/-2)

# [11.34.0](https://github.com/terrylica/cc-skills/compare/v11.33.0...v11.34.0) (2026-02-13)


### Bug Fixes

* **tts-telegram-sync:** correct CLAUDE.md to match actual implementation ([4ef4dca](https://github.com/terrylica/cc-skills/commit/4ef4dcaf056a0dc42e1a1ae98905bd4048d9083a))


### Features

* **tts-telegram-sync:** add plugin with full lifecycle management ([7de6290](https://github.com/terrylica/cc-skills/commit/7de62900efc2accf0faccba2e8a4ccabbd565ce8)), closes [#24](https://github.com/terrylica/cc-skills/issues/24)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [telegram bot management](https://github.com/terrylica/cc-skills/blob/v11.33.0/plugins/devops-tools/skills/telegram-bot-management/SKILL.md) - deleted

</details>

<details>
<summary><strong>tts-telegram-sync</strong> (8 changes)</summary>

- [bot-process-control](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/bot-process-control/SKILL.md) - new (+121)
- [clean-component-removal](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/clean-component-removal/SKILL.md) - new (+156)
- [component-version-upgrade](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/component-version-upgrade/SKILL.md) - new (+126)
- [diagnostic-issue-resolver](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/diagnostic-issue-resolver/SKILL.md) - new (+153)
- [full-stack-bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/full-stack-bootstrap/SKILL.md) - new (+199)
- [settings-and-tuning](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/settings-and-tuning/SKILL.md) - new (+128)
- [system-health-check](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/system-health-check/SKILL.md) - new (+196)
- [voice-quality-audition](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/voice-quality-audition/SKILL.md) - new (+167)

</details>


### Plugin READMEs

- [TTS Telegram Sync](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/README.md) - new (+82)

### Skill References

<details>
<summary><strong>devops-tools/telegram-bot-management</strong> (2 files)</summary>

- [Operational Commands](https://github.com/terrylica/cc-skills/blob/v11.33.0/plugins/devops-tools/skills/telegram-bot-management/references/operational-commands.md) - deleted
- [Troubleshooting](https://github.com/terrylica/cc-skills/blob/v11.33.0/plugins/devops-tools/skills/telegram-bot-management/references/troubleshooting.md) - deleted

</details>

<details>
<summary><strong>tts-telegram-sync/bot-process-control</strong> (3 files)</summary>

- [bot-process-control Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/bot-process-control/references/evolution-log.md) - new (+5)
- [Operational Commands](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/bot-process-control/references/operational-commands.md) - new (+146)
- [Process Tree](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/bot-process-control/references/process-tree.md) - new (+73)

</details>

<details>
<summary><strong>tts-telegram-sync/clean-component-removal</strong> (1 file)</summary>

- [clean-component-removal Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/clean-component-removal/references/evolution-log.md) - new (+5)

</details>

<details>
<summary><strong>tts-telegram-sync/component-version-upgrade</strong> (2 files)</summary>

- [component-version-upgrade Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/component-version-upgrade/references/evolution-log.md) - new (+5)
- [Upgrade Procedures](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/component-version-upgrade/references/upgrade-procedures.md) - new (+158)

</details>

<details>
<summary><strong>tts-telegram-sync/diagnostic-issue-resolver</strong> (3 files)</summary>

- [Common Issues -- Expanded Diagnostic Procedures](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/diagnostic-issue-resolver/references/common-issues.md) - new (+186)
- [diagnostic-issue-resolver Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/diagnostic-issue-resolver/references/evolution-log.md) - new (+5)
- [Lock Debugging -- Two-Layer Lock Mechanism](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/diagnostic-issue-resolver/references/lock-debugging.md) - new (+209)

</details>

<details>
<summary><strong>tts-telegram-sync/full-stack-bootstrap</strong> (4 files)</summary>

- [BotFather Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/full-stack-bootstrap/references/botfather-guide.md) - new (+139)
- [full-stack-bootstrap Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/full-stack-bootstrap/references/evolution-log.md) - new (+5)
- [Kokoro TTS Engine Bootstrap Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/full-stack-bootstrap/references/kokoro-bootstrap.md) - new (+114)
- [Upstream Fork: hexgrad/kokoro](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/full-stack-bootstrap/references/upstream-fork.md) - new (+66)

</details>

<details>
<summary><strong>tts-telegram-sync/settings-and-tuning</strong> (3 files)</summary>

- [Configuration Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/settings-and-tuning/references/config-reference.md) - new (+147)
- [settings-and-tuning Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/settings-and-tuning/references/evolution-log.md) - new (+5)
- [mise.toml Architecture Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/settings-and-tuning/references/mise-toml-reference.md) - new (+128)

</details>

<details>
<summary><strong>tts-telegram-sync/system-health-check</strong> (2 files)</summary>

- [system-health-check Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/system-health-check/references/evolution-log.md) - new (+5)
- [Health Checks Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/system-health-check/references/health-checks.md) - new (+266)

</details>

<details>
<summary><strong>tts-telegram-sync/voice-quality-audition</strong> (2 files)</summary>

- [voice-quality-audition Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/voice-quality-audition/references/evolution-log.md) - new (+5)
- [Voice Catalog](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/skills/voice-quality-audition/references/voice-catalog.md) - new (+139)

</details>


### Commands

<details>
<summary><strong>tts-telegram-sync</strong> (3 commands)</summary>

- [TTS Telegram Sync Health Check](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/commands/health.md) - new (+52)
- [TTS Telegram Sync Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/commands/hooks.md) - new (+81)
- [TTS Telegram Sync Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/commands/setup.md) - new (+99)

</details>


## Other Documentation

### Other

- [tts-telegram-sync Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/tts-telegram-sync/CLAUDE.md) - new (+48)

# [11.33.0](https://github.com/terrylica/cc-skills/compare/v11.32.0...v11.33.0) (2026-02-13)


### Features

* **gh-tools:** add Firecrawl health check + auto-revival to research-archival skill ([de5e7ce](https://github.com/terrylica/cc-skills/commit/de5e7ce8c28c388b22532cb92db4da6d68afeef5)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [research-archival](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/research-archival/SKILL.md) - updated (+74/-12)

</details>


### Skill References

<details>
<summary><strong>gh-tools/research-archival</strong> (3 files)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/research-archival/references/evolution-log.md) - updated (+11)
- [Frontmatter Schema](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/research-archival/references/frontmatter-schema.md) - updated (+1/-1)
- [URL Routing](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/research-archival/references/url-routing.md) - updated (+49/-10)

</details>

# [11.32.0](https://github.com/terrylica/cc-skills/compare/v11.31.0...v11.32.0) (2026-02-13)


### Features

* **quant-research:** add backtesting-py-oracle skill for SQL oracle validation ([1a23bb1](https://github.com/terrylica/cc-skills/commit/1a23bb16d037a429df1012a0d6419eaf524a81f9))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>quant-research</strong> (1 change)</summary>

- [backtesting-py-oracle](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/backtesting-py-oracle/SKILL.md) - new (+196)

</details>


### Plugin READMEs

- [quant-research](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/README.md) - updated (+13/-1)

# [11.31.0](https://github.com/terrylica/cc-skills/compare/v11.30.0...v11.31.0) (2026-02-13)


### Bug Fixes

* **itp-hooks:** remove over-broad pueue wrap patterns and fix task ID extraction ([#23](https://github.com/terrylica/cc-skills/issues/23)) ([12bedf7](https://github.com/terrylica/cc-skills/commit/12bedf7023c43926b0c72fc4dd98fb6b4970c1b3))


### Features

* **productivity-tools:** add calendar event manager with tiered sound alarms ([f2fc18b](https://github.com/terrylica/cc-skills/commit/f2fc18bad43fc3816f8725ed8f982a0cf1435d1a))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>productivity-tools</strong> (1 change)</summary>

- [calendar-event-manager](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/calendar-event-manager/SKILL.md) - new (+169)

</details>


### Plugin READMEs

- [productivity-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/README.md) - updated (+38/-6)

### Skill References

<details>
<summary><strong>productivity-tools/calendar-event-manager</strong> (1 file)</summary>

- [macOS System Sounds Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/calendar-event-manager/references/sound-reference.md) - new (+77)

</details>


### Commands

<details>
<summary><strong>productivity-tools</strong> (1 command)</summary>

- [productivity-tools Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/commands/hooks.md) - new (+102)

</details>

# [11.30.0](https://github.com/terrylica/cc-skills/compare/v11.29.1...v11.30.0) (2026-02-12)


### Features

* **gmail-tools:** add sender alignment with auto-detection for multi-alias accounts ([93b60f2](https://github.com/terrylica/cc-skills/commit/93b60f280c89bbd9de5ea445285f56ec5cc605cb))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gmail-tools</strong> (1 change)</summary>

- [gmail-access](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-tools/skills/gmail-access/SKILL.md) - updated (+72/-4)

</details>

## [11.29.1](https://github.com/terrylica/cc-skills/compare/v11.29.0...v11.29.1) (2026-02-12)


### Bug Fixes

* **itp-hooks:** flip pueue wrap guard from blocklist to allowlist ([08d9931](https://github.com/terrylica/cc-skills/commit/08d993132520bc206603dd9ef9c98ed004152cc5))

# [11.29.0](https://github.com/terrylica/cc-skills/compare/v11.28.0...v11.29.0) (2026-02-12)


### Features

* **itp-hooks:** convert PreToolUse hooks from ask to deny + fix version guard false positives ([7765434](https://github.com/terrylica/cc-skills/commit/77654344d802b11e38086f201f0d2dc3e08ba8ae))

# [11.28.0](https://github.com/terrylica/cc-skills/compare/v11.27.0...v11.28.0) (2026-02-12)


### Features

* **devops-tools,itp-hooks:** pueue universal CLI telemetry layer + auto-wrap hook ([ea2df82](https://github.com/terrylica/cc-skills/commit/ea2df82c69fdbfb5497e93ababb54d1a458a4da6))
* **itp-hooks:** add posttooluse-readme-pypi-links hook ([1656783](https://github.com/terrylica/cc-skills/commit/165678315da5147afe0c39af95e2ffcb1b387180))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (2 changes)</summary>

- [distributed-job-safety](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/SKILL.md) - updated (+8/-3)
- [pueue-job-orchestration](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/SKILL.md) - updated (+267/-13)

</details>


### Skill References

<details>
<summary><strong>devops-tools/pueue-job-orchestration</strong> (2 files)</summary>

- [Claude Code + Pueue Integration Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/references/claude-code-integration.md) - new (+158)
- [Pueue Configuration Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/references/pueue-config-reference.md) - new (+115)

</details>


## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+14/-13)

# [11.27.0](https://github.com/terrylica/cc-skills/compare/v11.26.0...v11.27.0) (2026-02-12)


### Features

* **itp-hooks:** add file-size bloat guard hook ([33e38b2](https://github.com/terrylica/cc-skills/commit/33e38b24835cd6a898b5b657edffb48aa8ab3b6b))





---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+185/-89)

</details>

<details>
<summary><strong>quality-tools/clickhouse-architect</strong> (1 file)</summary>

- [Anti-Patterns and Fixes](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/clickhouse-architect/references/anti-patterns-and-fixes.md) - updated (+2)

</details>


## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+46)

# [11.26.0](https://github.com/terrylica/cc-skills/compare/v11.25.1...v11.26.0) (2026-02-12)


### Features

* **itp-hooks:** add __init__ structure guard for Python packages ([026dc27](https://github.com/terrylica/cc-skills/commit/026dc273c63d1053a08fed89c81d4fb22155b9d7))

## [11.25.1](https://github.com/terrylica/cc-skills/compare/v11.25.0...v11.25.1) (2026-02-12)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (2 changes)</summary>

- [distributed-job-safety](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/SKILL.md) - updated (+66/-4)
- [pueue-job-orchestration](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/SKILL.md) - updated (+94/-7)

</details>


### Skill References

<details>
<summary><strong>devops-tools/distributed-job-safety</strong> (2 files)</summary>

- [Concurrency Invariants](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/references/concurrency-invariants.md) - updated (+4)
- [Environment Gotchas](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/references/environment-gotchas.md) - updated (+48)

</details>

# [11.25.0](https://github.com/terrylica/cc-skills/compare/v11.24.0...v11.25.0) (2026-02-11)


### Features

* **devops-tools:** add ClickHouse parallelism tuning and state management best practices ([f4a2b66](https://github.com/terrylica/cc-skills/commit/f4a2b66d352d6082d0cf021922e04290d0b3d968))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (2 changes)</summary>

- [distributed-job-safety](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/SKILL.md) - updated (+34/-18)
- [pueue-job-orchestration](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/SKILL.md) - updated (+83/-12)

</details>


### Skill References

<details>
<summary><strong>devops-tools/distributed-job-safety</strong> (1 file)</summary>

- [Environment Gotchas](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/references/environment-gotchas.md) - updated (+23)

</details>

<details>
<summary><strong>quality-tools/clickhouse-architect</strong> (1 file)</summary>

- [Anti-Patterns and Fixes](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/clickhouse-architect/references/anti-patterns-and-fixes.md) - updated (+2)

</details>

# [11.24.0](https://github.com/terrylica/cc-skills/compare/v11.23.0...v11.24.0) (2026-02-11)


### Features

* **devops-tools:** add pipeline monitoring, per-year parallelization, and new anti-patterns ([fa8b283](https://github.com/terrylica/cc-skills/commit/fa8b28379febca44de2f596e2737bfb0e46ec691))
* **devops-tools:** add state file management and bulk submission patterns ([433d675](https://github.com/terrylica/cc-skills/commit/433d675bee69b5f678cc945841a28a71ccb75bf9)), closes [hi#throughput](https://github.com/hi/issues/throughput)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (2 changes)</summary>

- [distributed-job-safety](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/SKILL.md) - updated (+107/-1)
- [pueue-job-orchestration](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/SKILL.md) - updated (+275)

</details>


### Skill References

<details>
<summary><strong>devops-tools/distributed-job-safety</strong> (1 file)</summary>

- [Concurrency Invariants](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/references/concurrency-invariants.md) - updated (+32)

</details>

# [11.23.0](https://github.com/terrylica/cc-skills/compare/v11.22.0...v11.23.0) (2026-02-10)


### Features

* **skills:** add battle-tested pueue + mise patterns from Issue [#88](https://github.com/terrylica/cc-skills/issues/88) deployment ([37a9b1d](https://github.com/terrylica/cc-skills/commit/37a9b1dc5ac01991e78f14c0f06f2984cc392dab))
* **skills:** add distributed-job-safety universal concurrency patterns ([d067711](https://github.com/terrylica/cc-skills/commit/d0677115c048e6be0f4e3bf588d22ca8c39f079c))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (2 changes)</summary>

- [distributed-job-safety](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/SKILL.md) - new (+374)
- [pueue-job-orchestration](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/SKILL.md) - updated (+137)

</details>


### Plugin READMEs

- [devops-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/README.md) - updated (+12/-1)

### Skill References

<details>
<summary><strong>devops-tools/distributed-job-safety</strong> (3 files)</summary>

- [Concurrency Invariants](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/references/concurrency-invariants.md) - new (+242)
- [Deployment Checklist](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/references/deployment-checklist.md) - new (+207)
- [Environment Gotchas](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/distributed-job-safety/references/environment-gotchas.md) - new (+249)

</details>

<details>
<summary><strong>itp/mise-tasks</strong> (1 file)</summary>

- [mise Tasks Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/references/patterns.md) - updated (+95)

</details>

# [11.22.0](https://github.com/terrylica/cc-skills/compare/v11.21.1...v11.22.0) (2026-02-10)


### Features

* **mise:** enrich all task descriptions for AI coding agent context priming ([9730d9b](https://github.com/terrylica/cc-skills/commit/9730d9b3774527ed811857fa8b0a70ab5f791f7e))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [mise-tasks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/SKILL.md) - updated (+30/-10)

</details>

## [11.21.1](https://github.com/terrylica/cc-skills/compare/v11.21.0...v11.21.1) (2026-02-10)


### Bug Fixes

* **research-archival:** route ChatGPT share URLs to Jina Reader ([24109c5](https://github.com/terrylica/cc-skills/commit/24109c5a1b57340985611de9dd582e6b62bbd28c))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [research-archival](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/research-archival/SKILL.md) - updated (+5/-1)

</details>


### Skill References

<details>
<summary><strong>gh-tools/research-archival</strong> (2 files)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/research-archival/references/evolution-log.md) - updated (+7)
- [URL Routing](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/research-archival/references/url-routing.md) - updated (+10/-6)

</details>

# [11.21.0](https://github.com/terrylica/cc-skills/compare/v11.20.1...v11.21.0) (2026-02-10)


### Features

* **gh-tools:** add repo identity guard hook and research-archival skill ([b565c6a](https://github.com/terrylica/cc-skills/commit/b565c6a45fa3c172f30132845d38fe6f7ae480aa)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools) [#6](https://github.com/terrylica/cc-skills/issues/6)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [research-archival](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/research-archival/SKILL.md) - new (+269)

</details>


### Skill References

<details>
<summary><strong>gh-tools/research-archival</strong> (3 files)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/research-archival/references/evolution-log.md) - new (+11)
- [Frontmatter Schema](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/research-archival/references/frontmatter-schema.md) - new (+60)
- [URL Routing](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/research-archival/references/url-routing.md) - new (+71)

</details>


## Other Documentation

### Other

- [gh-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/CLAUDE.md) - updated (+47/-7)

## [11.20.1](https://github.com/terrylica/cc-skills/compare/v11.20.0...v11.20.1) (2026-02-10)





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>itp</strong> (1 command)</summary>

- [/itp:release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/release.md) - updated (+88/-106)

</details>

# [11.20.0](https://github.com/terrylica/cc-skills/compare/v11.19.0...v11.20.0) (2026-02-09)


### Features

* **itp-hooks:** add CWD deletion guard hook ([0b4fd5f](https://github.com/terrylica/cc-skills/commit/0b4fd5f9aa0feeb7acc07bb8a60cc13febb18548))





---

## Documentation Changes

## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+43)

# [11.19.0](https://github.com/terrylica/cc-skills/compare/v11.18.0...v11.19.0) (2026-02-09)


### Bug Fixes

* **mise-tasks,telegram-bot:** prefer runtime-native watch over external watchers ([bc0348a](https://github.com/terrylica/cc-skills/commit/bc0348aad49a7124544cf54689325268cc5519b1))


### Features

* **devops-tools:** add project-directory-migration skill ([9229b86](https://github.com/terrylica/cc-skills/commit/9229b8687bc0ca9dfd0edec56fd941b062285013))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [project-directory-migration](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/project-directory-migration/SKILL.md) - new (+169)

</details>

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [mise-tasks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/SKILL.md) - updated (+13/-1)

</details>


### Plugin READMEs

- [devops-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/README.md) - updated (+11/-1)

### Skill References

<details>
<summary><strong>devops-tools/project-directory-migration</strong> (3 files)</summary>

- [project-directory-migration Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/project-directory-migration/references/evolution-log.md) - new (+28)
- [Claude Code Session Storage Anatomy](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/project-directory-migration/references/session-storage-anatomy.md) - new (+86)
- [Troubleshooting Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/project-directory-migration/references/troubleshooting.md) - new (+92)

</details>

<details>
<summary><strong>devops-tools/telegram-bot-management</strong> (1 file)</summary>

- [Or use alias](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/telegram-bot-management/references/operational-commands.md) - updated (+18/-1)

</details>

<details>
<summary><strong>itp/mise-tasks</strong> (1 file)</summary>

- [mise Tasks Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/references/patterns.md) - updated (+38/-2)

</details>

# [11.18.0](https://github.com/terrylica/cc-skills/compare/v11.17.0...v11.18.0) (2026-02-09)


### Features

* **quality-tools:** add pre-ship-review skill ([6662dbd](https://github.com/terrylica/cc-skills/commit/6662dbd89366640550e201160601e12e4703d0cc))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>quality-tools</strong> (1 change)</summary>

- [pre-ship-review](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/pre-ship-review/SKILL.md) - new (+256)

</details>


### Plugin READMEs

- [quality-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/README.md) - updated (+18/-9)

### Skill References

<details>
<summary><strong>quality-tools/pre-ship-review</strong> (5 files)</summary>

- [Anti-Pattern Catalog](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/pre-ship-review/references/anti-pattern-catalog.md) - new (+240)
- [Automated Checks Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/pre-ship-review/references/automated-checks.md) - new (+288)
- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/pre-ship-review/references/evolution-log.md) - new (+16)
- [Judgment Checks Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/pre-ship-review/references/judgment-checks.md) - new (+205)
- [Tool Install Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/pre-ship-review/references/tool-install-guide.md) - new (+214)

</details>

# [11.17.0](https://github.com/terrylica/cc-skills/compare/v11.16.2...v11.17.0) (2026-02-08)


### Bug Fixes

* **gh-tools:** add GFM rendering anti-patterns reference to issues-workflow ([15dc28b](https://github.com/terrylica/cc-skills/commit/15dc28b0c03f750d0008714720a9ef668d8f1a24)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools) [#N](https://github.com/terrylica/cc-skills/issues/N)


### Features

* **devops-tools:** add disk-hygiene skill for macOS disk cleanup ([2155eac](https://github.com/terrylica/cc-skills/commit/2155eacdd2cbf811d9d8d624e9417900f95d0d4e))
* **imessage-tools:** add iMessage database querying plugin ([9e8079a](https://github.com/terrylica/cc-skills/commit/9e8079a611e93809ad20241ef66e3b5fa591eca5))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [disk-hygiene](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/disk-hygiene/SKILL.md) - new (+289)

</details>

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [issues-workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issues-workflow/SKILL.md) - updated (+19/-7)

</details>

<details>
<summary><strong>imessage-tools</strong> (1 change)</summary>

- [imessage-query](https://github.com/terrylica/cc-skills/blob/main/plugins/imessage-tools/skills/imessage-query/SKILL.md) - new (+218)

</details>


### Plugin READMEs

- [devops-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/README.md) - updated (+11/-1)
- [imessage-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/imessage-tools/README.md) - new (+25)

### Skill References

<details>
<summary><strong>devops-tools/disk-hygiene</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/disk-hygiene/references/evolution-log.md) - new (+12)

</details>

<details>
<summary><strong>gh-tools/issues-workflow</strong> (1 file)</summary>

- [GFM Anti-Patterns in Issue Comments](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issues-workflow/references/gfm-antipatterns.md) - new (+209)

</details>

<details>
<summary><strong>imessage-tools/imessage-query</strong> (4 files)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/imessage-tools/skills/imessage-query/references/evolution-log.md) - new (+29)
- [Known Pitfalls](https://github.com/terrylica/cc-skills/blob/main/plugins/imessage-tools/skills/imessage-query/references/known-pitfalls.md) - new (+152)
- [Reusable SQL Query Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/imessage-tools/skills/imessage-query/references/query-patterns.md) - new (+184)
- [iMessage Database Schema Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/imessage-tools/skills/imessage-query/references/schema-reference.md) - new (+138)

</details>

## [11.16.2](https://github.com/terrylica/cc-skills/compare/v11.16.1...v11.16.2) (2026-02-06)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>quality-tools</strong> (1 change)</summary>

- [dead-code-detector](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/dead-code-detector/SKILL.md) - updated (+46/-44)

</details>

## [11.16.1](https://github.com/terrylica/cc-skills/compare/v11.16.0...v11.16.1) (2026-02-06)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>quality-tools</strong> (1 change)</summary>

- [dead-code-detector](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/dead-code-detector/SKILL.md) - updated (+144)

</details>

# [11.16.0](https://github.com/terrylica/cc-skills/compare/v11.15.0...v11.16.0) (2026-02-06)


### Features

* **quality-tools:** add dead-code-detector skill for polyglot codebases ([6c0e7c5](https://github.com/terrylica/cc-skills/commit/6c0e7c5806b22884d00559b3be65679c7e72acbb))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>quality-tools</strong> (1 change)</summary>

- [dead-code-detector](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/dead-code-detector/SKILL.md) - new (+193)

</details>


### Skill References

<details>
<summary><strong>quality-tools/dead-code-detector</strong> (3 files)</summary>

- [Python Dead Code Detection with vulture](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/dead-code-detector/references/python-workflow.md) - new (+158)
- [Rust Dead Code Detection with cargo clippy](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/dead-code-detector/references/rust-workflow.md) - new (+197)
- [TypeScript Dead Code Detection with knip](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/dead-code-detector/references/typescript-workflow.md) - new (+184)

</details>

# [11.15.0](https://github.com/terrylica/cc-skills/compare/v11.14.0...v11.15.0) (2026-02-06)


### Features

* **gh-tools:** add gh-issue-title-reminder hook for 256-char title optimization ([9cd7ceb](https://github.com/terrylica/cc-skills/commit/9cd7ceb03a6900bfd2685a5413c2b81fab4f705c)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools) [#issue-title-reminder](https://github.com/terrylica/cc-skills/issues/issue-title-reminder) [#tools](https://github.com/terrylica/cc-skills/issues/tools) [#TOOLS](https://github.com/terrylica/cc-skills/issues/TOOLS)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (2 changes)</summary>

- [issue-create](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issue-create/SKILL.md) - updated (+2/-2)
- [issues-workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issues-workflow/SKILL.md) - updated (+21)

</details>


### Plugin READMEs

- [gh-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/README.md) - updated (+33/-5)

### Skill References

<details>
<summary><strong>gh-tools/issue-create</strong> (1 file)</summary>

- [AI Prompts Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issue-create/references/ai-prompts.md) - updated (+6/-4)

</details>


## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+17/-13)

## Other Documentation

### Other

- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (+9/-9)
- [gh-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/CLAUDE.md) - new (+125)

# [11.14.0](https://github.com/terrylica/cc-skills/compare/v11.13.0...v11.14.0) (2026-02-05)


### Features

* **devops-tools:** add pueue-job-orchestration skill ([2f03bd8](https://github.com/terrylica/cc-skills/commit/2f03bd895ce1ebd5cc83a90d42ed454249217730))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [pueue-job-orchestration](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/pueue-job-orchestration/SKILL.md) - new (+227)

</details>

# [11.13.0](https://github.com/terrylica/cc-skills/compare/v11.12.0...v11.13.0) (2026-02-05)


### Features

* **itp-hooks:** add Pueue reminder for long-running tasks ([292060b](https://github.com/terrylica/cc-skills/commit/292060b887e2f2500c858039f1185bd986a74ec4))





---

## Documentation Changes

## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+53/-1)

# [11.12.0](https://github.com/terrylica/cc-skills/compare/v11.11.1...v11.12.0) (2026-02-05)


### Features

* **itp-hooks:** add read-only command detection to reduce hook noise ([2a916be](https://github.com/terrylica/cc-skills/commit/2a916bedf7e23733d62a20fe52d4f0c2784c954c))





---

## Documentation Changes

## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+31)

## [11.11.1](https://github.com/terrylica/cc-skills/compare/v11.11.0...v11.11.1) (2026-02-05)





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| unknown | [mise.toml Hygiene Guard Hook](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-02-05-mise-hygiene-guard.md) | new (+80) |

# [11.11.0](https://github.com/terrylica/cc-skills/compare/v11.10.1...v11.11.0) (2026-02-05)


### Bug Fixes

* **itp-hooks:** remove unused parameter and improve error handling ([74daf07](https://github.com/terrylica/cc-skills/commit/74daf07003a86e319c664602b1cb1607f838058d))


### Features

* **itp-hooks:** add plan mode detection for PreToolUse hooks ([dff381c](https://github.com/terrylica/cc-skills/commit/dff381ca75ddc19ec7392982113bca3fc26f1a42))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| accepted | [Plan Mode Detection in PreToolUse Hooks](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-02-05-plan-mode-detection-hooks.md) | new (+159) |

## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+35)

## [11.10.1](https://github.com/terrylica/cc-skills/compare/v11.10.0...v11.10.1) (2026-02-05)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gmail-tools</strong> (1 change)</summary>

- [gmail-access](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-tools/skills/gmail-access/SKILL.md) - updated (+36)

</details>


### Skill References

<details>
<summary><strong>gmail-tools/gmail-access</strong> (1 file)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-tools/skills/gmail-access/references/evolution-log.md) - new (+26)

</details>

<details>
<summary><strong>itp/mise-tasks</strong> (1 file)</summary>

- [Release Workflow Patterns for mise Tasks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/references/release-workflow-patterns.md) - updated (+75)

</details>

# [11.10.0](https://github.com/terrylica/cc-skills/compare/v11.9.1...v11.10.0) (2026-02-04)


### Features

* **gdrive-tools:** add Google Drive API plugin with documentation updates ([7513c3a](https://github.com/terrylica/cc-skills/commit/7513c3a11c2b0b707a1daed152d68ef07322db9f))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gdrive-tools</strong> (1 change)</summary>

- [gdrive-access](https://github.com/terrylica/cc-skills/blob/main/plugins/gdrive-tools/skills/gdrive-access/SKILL.md) - new (+247)

</details>


### Plugin READMEs

- [Google Drive Tools](https://github.com/terrylica/cc-skills/blob/main/plugins/gdrive-tools/README.md) - new (+102)

### Skill References

<details>
<summary><strong>gdrive-tools/gdrive-access</strong> (2 files)</summary>

- [Google Drive API OAuth Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/gdrive-tools/skills/gdrive-access/references/gdrive-api-setup.md) - new (+139)
- [OAuth Client Setup Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/gdrive-tools/skills/gdrive-access/references/oauth-clients.md) - new (+68)

</details>


## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+42/-23)

### General Documentation

- [Documentation Guide](https://github.com/terrylica/cc-skills/blob/main/docs/CLAUDE.md) - updated (+1)
- [Session Resume Context](https://github.com/terrylica/cc-skills/blob/main/docs/RESUME.md) - updated (+21/-1)

## Other Documentation

### Other

- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (+10/-8)

## [11.9.1](https://github.com/terrylica/cc-skills/compare/v11.9.0...v11.9.1) (2026-02-03)





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [RU](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/README.md) - updated (+15/-19)

## Repository Documentation

### Root Documentation

- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+2/-4)

# [11.9.0](https://github.com/terrylica/cc-skills/compare/v11.8.4...v11.9.0) (2026-02-03)


### Features

* **gmail-tools:** Add draft creation capability ([aa49215](https://github.com/terrylica/cc-skills/commit/aa49215f7021cf19456baa995bdf9f2db4b09e13))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gmail-tools</strong> (1 change)</summary>

- [gmail-access](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-tools/skills/gmail-access/SKILL.md) - updated (+41/-1)

</details>


### Plugin READMEs

- [Gmail Tools](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-tools/README.md) - updated (+9/-3)

## [11.8.4](https://github.com/terrylica/cc-skills/compare/v11.8.3...v11.8.4) (2026-02-03)





---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>itp/semantic-release</strong> (2 files)</summary>

- [Rust Projects with release-plz](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/rust.md) - updated (+41/-11)
- [Version Alignment Standards](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/version-alignment.md) - updated (+38)

</details>

## [11.8.3](https://github.com/terrylica/cc-skills/compare/v11.8.2...v11.8.3) (2026-02-03)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [issues-workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issues-workflow/SKILL.md) - updated (+1/-1)

</details>


### Plugin READMEs

- [ITP Hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/README.md) - updated (+13/-36)

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+2/-2)
- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+4/-5)

### General Documentation

- [Hooks Development Guide](https://github.com/terrylica/cc-skills/blob/main/docs/HOOKS.md) - updated (+8/-8)
- [Session Resume Context](https://github.com/terrylica/cc-skills/blob/main/docs/RESUME.md) - updated (+1/-1)

## Other Documentation

### Other

- [Troubleshooting cc-skills Marketplace Installation](https://github.com/terrylica/cc-skills/blob/main/docs/troubleshooting/marketplace-installation.md) - updated (+2/-2)
- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (+1/-1)

## [11.8.2](https://github.com/terrylica/cc-skills/compare/v11.8.1...v11.8.2) (2026-02-03)


### Bug Fixes

* **gmail-tools:** add mandatory preflight with AskUserQuestion flows ([f9ee5d7](https://github.com/terrylica/cc-skills/commit/f9ee5d72dd3442ed5c91a8e7acd0dbe055fa2272))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gmail-tools</strong> (1 change)</summary>

- [gmail-access](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-tools/skills/gmail-access/SKILL.md) - updated (+142/-141)

</details>

## [11.8.1](https://github.com/terrylica/cc-skills/compare/v11.8.0...v11.8.1) (2026-02-03)


### Bug Fixes

* **gmail-tools:** add CLI location and first-run setup instructions ([ef31ff4](https://github.com/terrylica/cc-skills/commit/ef31ff4112ef4be83c57ee77cd5ea3bf5880fa4b))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gmail-tools</strong> (1 change)</summary>

- [gmail-access](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-tools/skills/gmail-access/SKILL.md) - updated (+25)

</details>

# [11.8.0](https://github.com/terrylica/cc-skills/compare/v11.7.6...v11.8.0) (2026-02-03)


### Features

* **gmail-tools:** add Gmail access plugin with 1Password OAuth ([29a2513](https://github.com/terrylica/cc-skills/commit/29a251366b76fb69298d3dd49815430c52d43d06))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gmail-tools</strong> (1 change)</summary>

- [gmail-access](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-tools/skills/gmail-access/SKILL.md) - new (+198)

</details>


### Plugin READMEs

- [Gmail Tools](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-tools/README.md) - new (+101)

### Skill References

<details>
<summary><strong>gmail-tools/gmail-access</strong> (3 files)</summary>

- [Gmail API OAuth Setup Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-tools/skills/gmail-access/references/gmail-api-setup.md) - new (+114)
- [mise Setup Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-tools/skills/gmail-access/references/mise-setup.md) - new (+113)
- [mise Configuration Templates](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-tools/skills/gmail-access/references/mise-templates.md) - new (+96)

</details>


### Commands

<details>
<summary><strong>gmail-tools</strong> (1 command)</summary>

- [Gmail Tools Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/gmail-tools/commands/setup.md) - new (+68)

</details>

## [11.7.6](https://github.com/terrylica/cc-skills/compare/v11.7.5...v11.7.6) (2026-02-02)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [issues-workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issues-workflow/SKILL.md) - renamed from `plugins/gh-tools/skills/project-workflow/SKILL.md`

</details>


### Plugin READMEs

- [gh-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/README.md) - updated (+2/-2)

### Skill References

<details>
<summary><strong>gh-tools/issues-workflow</strong> (3 files)</summary>

- [Auto-Link Configuration Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issues-workflow/references/auto-link-config.md) - renamed from `plugins/gh-tools/skills/project-workflow/references/auto-link-config.md`
- [GitHub Projects v2 Field Types Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issues-workflow/references/field-types.md) - renamed from `plugins/gh-tools/skills/project-workflow/references/field-types.md`
- [GraphQL Queries Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issues-workflow/references/graphql-queries.md) - renamed from `plugins/gh-tools/skills/project-workflow/references/graphql-queries.md`

</details>

## [11.7.5](https://github.com/terrylica/cc-skills/compare/v11.7.4...v11.7.5) (2026-02-02)


### Bug Fixes

* **itp-hooks:** remove obsolete Polars preference tests ([a4cd8c2](https://github.com/terrylica/cc-skills/commit/a4cd8c23d15ad5a029b38236262ba9657603346d))





---

## Documentation Changes

## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+17/-31)

## [11.7.4](https://github.com/terrylica/cc-skills/compare/v11.7.3...v11.7.4) (2026-02-02)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [project-workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/project-workflow/SKILL.md) - updated (+28/-8)

</details>

## [11.7.3](https://github.com/terrylica/cc-skills/compare/v11.7.2...v11.7.3) (2026-02-02)


### Documentation

* **gh-tools:** make Issues-first default, Projects v2 visualization-only ([e9f5f75](https://github.com/terrylica/cc-skills/commit/e9f5f75b06d97350599db956aa0c6526106c9f1b)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools) [#TOOLS](https://github.com/terrylica/cc-skills/issues/TOOLS)


### BREAKING CHANGES

* **gh-tools:** Reposition workflow from "Issues + Projects" to "Issues-first"

- Issues are now the default for all content, hierarchy, and tracking
- Sub-issues replace Projects for hierarchy (100 per parent, 8 levels)
- Labels replace Project fields for status/priority tracking
- Projects v2 reduced to optional cross-repo visualization layer
- Add complete GitHub Issues feature reference (30+ filters, milestones)
- Add tasklist retirement notice (April 30, 2025)
- Clarify when to use Projects v2 vs skip entirely

SRED-Type: support-work





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [project-workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/project-workflow/SKILL.md) - updated (+257/-286)

</details>

## [11.7.2](https://github.com/terrylica/cc-skills/compare/v11.7.1...v11.7.2) (2026-02-02)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [project-workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/project-workflow/SKILL.md) - updated (+70/-8)

</details>


### Skill References

<details>
<summary><strong>gh-tools/project-workflow</strong> (1 file)</summary>

- [GraphQL Queries Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/project-workflow/references/graphql-queries.md) - updated (+110/-5)

</details>

## [11.7.1](https://github.com/terrylica/cc-skills/compare/v11.7.0...v11.7.1) (2026-02-02)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [project-workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/project-workflow/SKILL.md) - updated (+54/-1)

</details>

# [11.7.0](https://github.com/terrylica/cc-skills/compare/v11.6.3...v11.7.0) (2026-02-02)


### Bug Fixes

* **ru:** apply whitespace trimming to all LiquidJS for loops ([033effe](https://github.com/terrylica/cc-skills/commit/033effef03dd70e62badb0c27669aa1c31111602))


### Features

* **gh-tools:** add project-workflow skill for GitHub Projects v2 integration ([42021f6](https://github.com/terrylica/cc-skills/commit/42021f6bf6b283815c120757190011df033a8a2c)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools) [#20](https://github.com/terrylica/cc-skills/issues/20) [#TOOLS](https://github.com/terrylica/cc-skills/issues/TOOLS)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [project-workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/project-workflow/SKILL.md) - new (+314)

</details>


### Plugin READMEs

- [gh-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/README.md) - updated (+4/-1)

### Skill References

<details>
<summary><strong>gh-tools/project-workflow</strong> (3 files)</summary>

- [Auto-Link Configuration Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/project-workflow/references/auto-link-config.md) - new (+269)
- [GitHub Projects v2 Field Types Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/project-workflow/references/field-types.md) - new (+175)
- [GraphQL Queries Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/project-workflow/references/graphql-queries.md) - new (+353)

</details>


## Other Documentation

### Other

- [ralph-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/hooks/templates/ralph-unified.md) - updated (+4/-4)

## [11.6.3](https://github.com/terrylica/cc-skills/compare/v11.6.2...v11.6.3) (2026-02-01)


### Bug Fixes

* **itp-hooks:** remove obsolete Polars preference tests ([da86063](https://github.com/terrylica/cc-skills/commit/da8606317d58a928034a36cd4f66f28a448fa87a))
* **ru:** remove extra blank lines in LiquidJS for loop output ([6736148](https://github.com/terrylica/cc-skills/commit/67361489c936896edf59bfad9ef818d7389f181a))





---

## Documentation Changes

## Other Documentation

### Other

- [ralph-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/hooks/templates/ralph-unified.md) - updated (+4/-4)

## [11.6.2](https://github.com/terrylica/cc-skills/compare/v11.6.1...v11.6.2) (2026-02-01)

## [11.6.1](https://github.com/terrylica/cc-skills/compare/v11.6.0...v11.6.1) (2026-02-01)





---

## Documentation Changes

## Other Documentation

### Other

- [ralph-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/hooks/templates/ralph-unified.md) - updated (+16/-18)

# [11.6.0](https://github.com/terrylica/cc-skills/compare/v11.5.1...v11.6.0) (2026-02-01)


### Features

* **ru:** add Polars/Arrow preference to template ([74ff93b](https://github.com/terrylica/cc-skills/commit/74ff93b18e954a4a29a97bde074a944daea59243))





---

## Documentation Changes

## Other Documentation

### Other

- [ralph-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/hooks/templates/ralph-unified.md) - updated (+6)

## [11.5.1](https://github.com/terrylica/cc-skills/compare/v11.5.0...v11.5.1) (2026-02-01)





---

## Documentation Changes

## Other Documentation

### Other

- [ralph-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/hooks/templates/ralph-unified.md) - updated (+7/-59)

# [11.5.0](https://github.com/terrylica/cc-skills/compare/v11.4.0...v11.5.0) (2026-02-01)


### Features

* **ru:** add GPU acceleration policy to autonomous loop template ([1414a82](https://github.com/terrylica/cc-skills/commit/1414a8240e6b57be04bad7408473e3f2b05b28e5))





---

## Documentation Changes

## Other Documentation

### Other

- [Copy forked tool to GPU workstation](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/hooks/templates/ralph-unified.md) - updated (+65)

# [11.4.0](https://github.com/terrylica/cc-skills/compare/v11.3.2...v11.4.0) (2026-02-01)


### Features

* **ru:** redesign wizard flow to agnostic classification approach ([2dfb58e](https://github.com/terrylica/cc-skills/commit/2dfb58e322d4fae85304b9a932b50c9a74728e75))





---

## Documentation Changes

## Plugin Documentation

### Commands

<details>
<summary><strong>ru</strong> (2 commands)</summary>

- [RU: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/start.md) - updated (+88/-20)
- [RU: Wizard](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/wizard.md) - updated (+154/-69)

</details>


## Other Documentation

### Other

- [ralph-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/hooks/templates/ralph-unified.md) - updated (+4/-3)

## [11.3.2](https://github.com/terrylica/cc-skills/compare/v11.3.1...v11.3.2) (2026-02-01)





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [RU](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/README.md) - updated (+60)

## [11.3.1](https://github.com/terrylica/cc-skills/compare/v11.3.0...v11.3.1) (2026-01-31)


### Bug Fixes

* **ru:** remove extra blank lines from template whitespace ([6e08e12](https://github.com/terrylica/cc-skills/commit/6e08e120426a8af181dbf2142f7db64d970d99b0))





---

## Documentation Changes

## Other Documentation

### Other

- [ralph-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/hooks/templates/ralph-unified.md) - updated (+5/-12)

# [11.3.0](https://github.com/terrylica/cc-skills/compare/v11.2.0...v11.3.0) (2026-01-31)


### Features

* **ru:** add TESTING PHILOSOPHY section to template ([03da4fb](https://github.com/terrylica/cc-skills/commit/03da4fb7169cbe1e0626226a17d346ec3097264d))





---

## Documentation Changes

## Other Documentation

### Other

- [ralph-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/hooks/templates/ralph-unified.md) - updated (+37)

# [11.2.0](https://github.com/terrylica/cc-skills/compare/v11.1.1...v11.2.0) (2026-01-31)


### Features

* **ru:** show config path at top and bottom of template ([d117fb2](https://github.com/terrylica/cc-skills/commit/d117fb27ad6befb827d06f1673d69935395de84e))





---

## Documentation Changes

## Other Documentation

### Other

- [ralph-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/hooks/templates/ralph-unified.md) - updated (+6)

## [11.1.1](https://github.com/terrylica/cc-skills/compare/v11.1.0...v11.1.1) (2026-01-31)


### Bug Fixes

* **ru:** use uv run for Python subprocess in TypeScript hook ([6bd378f](https://github.com/terrylica/cc-skills/commit/6bd378fc5af221710ef388ac85f6d7236f09a98f))

# [11.1.0](https://github.com/terrylica/cc-skills/compare/v11.0.4...v11.1.0) (2026-01-31)


### Features

* **ru:** migrate loop-until-done to TypeScript/Bun (Phase 1) ([e6c4d76](https://github.com/terrylica/cc-skills/commit/e6c4d7629cc0584b737d14f0881f4622511e99b2))

## [11.0.4](https://github.com/terrylica/cc-skills/compare/v11.0.3...v11.0.4) (2026-01-31)


### Bug Fixes

* **ru:** preserve guidance when timestamp is null (Issue [#18](https://github.com/terrylica/cc-skills/issues/18)) ([a598b76](https://github.com/terrylica/cc-skills/commit/a598b76674264b2c5827f236fde90c0939ca05b5))

## [11.0.3](https://github.com/terrylica/cc-skills/compare/v11.0.2...v11.0.3) (2026-01-31)





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| superseded | [Polars Preference Hook (Efficiency Preferences Framework)](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-22-polars-preference-hook.md) | updated (+4/-1) |

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+3/-5)

## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+12/-53)

## [11.0.2](https://github.com/terrylica/cc-skills/compare/v11.0.1...v11.0.2) (2026-01-31)


### Bug Fixes

* **ru:** add Context Refresh step to IMPLEMENTATION phase workflow ([f9be72b](https://github.com/terrylica/cc-skills/commit/f9be72bfb32ba9c8705556d64f6b8a9b314a9ef6))





---

## Documentation Changes

## Other Documentation

### Other

- [ralph-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/hooks/templates/ralph-unified.md) - updated (+10/-7)

## [11.0.1](https://github.com/terrylica/cc-skills/compare/v11.0.0...v11.0.1) (2026-01-31)

# [11.0.0](https://github.com/terrylica/cc-skills/compare/v10.3.0...v11.0.0) (2026-01-31)


### Features

* **ru:** remove deprecated ralph plugin in favor of ru (Ralph Universe) ([42cf919](https://github.com/terrylica/cc-skills/commit/42cf91972d888df19197bb7f3ba90a19a256c47e))


### BREAKING CHANGES

* **ru:** The `ralph` plugin has been removed. Use `ru` instead.

Migration guide:
- /ralph:start → /ru:start
- /ralph:stop → /ru:stop
- /ralph:status → /ru:status
- /ralph:config → /ru:config
- /ralph:encourage → /ru:encourage
- /ralph:forbid → /ru:forbid
- /ralph:audit-now → /ru:audit-now
- /ralph:hooks → /ru:hooks

New in ru:
- /ru:wizard - Interactive guidance setup (replaces session-guidance skill)

Removed (Alpha-Forge specific, not migrated):
- constraint-discovery skill (5-agent parallel constraint scan)
- session-guidance skill (NDJSON constraint integration)
- MENTAL-MODEL.md, GETTING-STARTED.md (Alpha-Forge specific docs)
- EXPLORE-AGENT-* documentation (13 files)

The ru plugin contains all hooks and core functionality from ralph,
now modernized for Claude Code 2.1+ with native Task system support.

SRED-Type: experimental-development
SRED-Claim: RU





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>ralph</strong> (2 changes)</summary>

- [constraint discovery](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/skills/constraint-discovery/SKILL.md) - deleted
- [session guidance](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/skills/session-guidance/SKILL.md) - deleted

</details>


### Plugin READMEs

- [ralph](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/README.md) - deleted

### Commands

<details>
<summary><strong>ralph</strong> (8 commands)</summary>

- [audit-now](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/commands/audit-now.md) - deleted
- [config](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/commands/config.md) - deleted
- [encourage](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/commands/encourage.md) - deleted
- [forbid](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/commands/forbid.md) - deleted
- [hooks](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/commands/hooks.md) - deleted
- [start](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/commands/start.md) - deleted
- [status](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/commands/status.md) - deleted
- [stop](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/commands/stop.md) - deleted

</details>


## Other Documentation

### Other

- [adapters](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/docs/adapters.md) - deleted
- [ALPHA-FORGE-VALIDATION-PROMPT](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/docs/ALPHA-FORGE-VALIDATION-PROMPT.md) - deleted
- [EXPLORE-AGENT-ARCHITECTURE](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/docs/EXPLORE-AGENT-ARCHITECTURE.md) - deleted
- [EXPLORE-AGENT-DESIGN-COMPLETE](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/docs/EXPLORE-AGENT-DESIGN-COMPLETE.md) - deleted
- [EXPLORE-AGENT-IMPLEMENTATION](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/docs/EXPLORE-AGENT-IMPLEMENTATION.md) - deleted
- [EXPLORE-AGENT-INDEX](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/docs/EXPLORE-AGENT-INDEX.md) - deleted
- [EXPLORE-AGENT-INTEGRATION-DESIGN](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/docs/EXPLORE-AGENT-INTEGRATION-DESIGN.md) - deleted
- [EXPLORE-AGENT-PROMPTS](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/docs/EXPLORE-AGENT-PROMPTS.md) - deleted
- [EXPLORE-AGENT-SUMMARY](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/docs/EXPLORE-AGENT-SUMMARY.md) - deleted
- [EXPLORE-EXAMPLES](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/docs/EXPLORE-EXAMPLES.md) - deleted
- [EXPLORE-GUIDE](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/docs/EXPLORE-GUIDE.md) - deleted
- [EXPLORE-INDEX](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/docs/EXPLORE-INDEX.md) - deleted
- [EXPLORE-REFERENCE](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/docs/EXPLORE-REFERENCE.md) - deleted
- [GETTING-STARTED](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/GETTING-STARTED.md) - deleted
- [ralph-unified](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/hooks/templates/ralph-unified.md) - deleted
- [poc-task](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/hooks/tests/poc-task.md) - deleted
- [MENTAL-MODEL](https://github.com/terrylica/cc-skills/blob/v10.3.0/plugins/ralph/MENTAL-MODEL.md) - deleted

# [10.3.0](https://github.com/terrylica/cc-skills/compare/v10.2.2...v10.3.0) (2026-01-31)


### Bug Fixes

* add recovery tips to error messages in hooks ([18e82e8](https://github.com/terrylica/cc-skills/commit/18e82e8fc8f415a35759228ebe73cb82f89176ad))
* **alpha-forge-worktree:** improve error messages with recovery instructions ([9f6e51e](https://github.com/terrylica/cc-skills/commit/9f6e51e7c70d54ec82a23967d24449a3486cf497))
* **asciinema-tools:** correct broken asciinema-summarizer link ([c6bcf90](https://github.com/terrylica/cc-skills/commit/c6bcf9001002eda9859c3b01b767505769285788))
* correct broken links across multiple plugins ([71deb47](https://github.com/terrylica/cc-skills/commit/71deb47e59396a15bd0ded79b4f2a4a02ab2fed9)), closes [#model-collapse-detection](https://github.com/terrylica/cc-skills/issues/model-collapse-detection)
* **devops-tools:** remove broken launchagent-log-rotation references ([830e2c8](https://github.com/terrylica/cc-skills/commit/830e2c81665d18b9cce60e42d8cbc3eecc3f7d41))
* **devops-tools:** remove broken zerotier-network link in firecrawl skill ([914c844](https://github.com/terrylica/cc-skills/commit/914c844e1d9bc35a23775eb3728311bd82490722))
* **doc-tools:** improve error handling in build-pdf.sh ([20a90d9](https://github.com/terrylica/cc-skills/commit/20a90d938fd9207a7f4f87721c88551444478b7b))
* **docs:** correct external link and hook documentation ([6c75dd0](https://github.com/terrylica/cc-skills/commit/6c75dd0983ae3d9b0f9bb4cf51a6f9f2aaabf85b))
* **docs:** correct hook badge count and installation command format ([8b02660](https://github.com/terrylica/cc-skills/commit/8b02660ebe34cacc1ccbac15711673a271b97e81))
* **docs:** remove broken external references ([85d5344](https://github.com/terrylica/cc-skills/commit/85d534406caf79630254aaf3d02b6424b1875504))
* **docs:** remove remaining private repo URL references ([59a3e03](https://github.com/terrylica/cc-skills/commit/59a3e031654b7d03f3a1a338be2321e164c4f35f))
* **hooks:** improve error messages with recovery tips ([14971ed](https://github.com/terrylica/cc-skills/commit/14971ed786f99f984b3255479f7897a590ce320b))
* **itp-hooks:** add error context to catch blocks in TypeScript hooks ([7d0b63f](https://github.com/terrylica/cc-skills/commit/7d0b63fcc7871238634490992d38905d66121ca0))
* **itp-hooks:** add file readability check before analysis ([d9e4279](https://github.com/terrylica/cc-skills/commit/d9e42791ee9e29d7853ac632576070bc95c9f50f))
* **itp-hooks:** improve error messages with actionable guidance ([5b958da](https://github.com/terrylica/cc-skills/commit/5b958dac6f82f8e1c441f363b587a171588e97a2))
* **itp:** correct broken anchor link in README ([706a5df](https://github.com/terrylica/cc-skills/commit/706a5dfa6608bc8b6c878f2d9ccc43dcf9a779b7)), closes [#0-most-common-plugin-not-found-after-successful-add](https://github.com/terrylica/cc-skills/issues/0-most-common-plugin-not-found-after-successful-add) [#1-plugin-not-found-after-successful-marketplace-add](https://github.com/terrylica/cc-skills/issues/1-plugin-not-found-after-successful-marketplace-add)
* **itp:** correct broken anchor links in mise-configuration SKILL.md ([469e1d0](https://github.com/terrylica/cc-skills/commit/469e1d0995ade5dfe28144af03e3e99cc9343600)), closes [authentication.md#controlmaster-cache-issues](https://github.com/authentication.md/issues/controlmaster-cache-issues) [troubleshooting.md#ssh-controlmaster-cache](https://github.com/troubleshooting.md/issues/ssh-controlmaster-cache) [#hub-spoke](https://github.com/terrylica/cc-skills/issues/hub-spoke)
* **itp:** correct broken anchor links in semantic-release references ([7a115b2](https://github.com/terrylica/cc-skills/commit/7a115b234a2bc70db6bf9a2e42ff2810964de406)), closes [authentication.md#controlmaster-cache-issues](https://github.com/authentication.md/issues/controlmaster-cache-issues) [troubleshooting.md#ssh-controlmaster-cache](https://github.com/troubleshooting.md/issues/ssh-controlmaster-cache) [#controlmaster-cache-issues](https://github.com/terrylica/cc-skills/issues/controlmaster-cache-issues) [./troubleshooting.md#ssh-controlmaster-cache](https://github.com/./troubleshooting.md/issues/ssh-controlmaster-cache) [#macos-gatekeeper-blocks-node-files](https://github.com/terrylica/cc-skills/issues/macos-gatekeeper-blocks-node-files)
* **itp:** update skills badge count to 11 ([04b77f9](https://github.com/terrylica/cc-skills/commit/04b77f917c85f91379eb91870b742acb93d143df))
* **scripts:** add error handling for mkdir and cp operations ([0183d3d](https://github.com/terrylica/cc-skills/commit/0183d3ddf7d9ba009059564bd4a4b8471470a124))
* **statusline-tools:** escape bracket notation to prevent false hyperlink ([7808153](https://github.com/terrylica/cc-skills/commit/78081539d52ece7c5593b9b7e051277ff4ece382))


### Features

* **ru:** modernize ralph-unified template for Claude Code 2.1+ ([2989aa4](https://github.com/terrylica/cc-skills/commit/2989aa45d21582e8acde51432be9583ba9e144c0))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| accepted | [mise [env] Token Loading: read_file vs exec](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-15-mise-env-token-loading-patterns.md) | updated (+1/-1) |
| accepted | [SR&ED Dynamic Project Discovery via Claude Agent SDK](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-18-sred-dynamic-discovery.md) | coupled |

### Design Specs

- [SR&ED Project Discovery: Forked Haiku Session via Claude Agent SDK](https://github.com/terrylica/cc-skills/blob/main/docs/design/2026-01-18-sred-dynamic-discovery/spec.md) - updated (+7/-7)

## Plugin Documentation

### Skills

<details>
<summary><strong>alpha-forge-worktree</strong> (1 change)</summary>

- [worktree-manager](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-worktree/skills/worktree-manager/SKILL.md) - updated (+21/-8)

</details>

<details>
<summary><strong>asciinema-tools</strong> (6 changes)</summary>

- [asciinema-analyzer](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-analyzer/SKILL.md) - updated (+25)
- [asciinema-cast-format](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-cast-format/SKILL.md) - updated (+26/-1)
- [asciinema-converter](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-converter/SKILL.md) - updated (+26/-1)
- [asciinema-player](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-player/SKILL.md) - updated (+10/-1)
- [asciinema-recorder](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-recorder/SKILL.md) - updated (+10/-2)
- [asciinema-streaming-backup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/SKILL.md) - updated (+9)

</details>

<details>
<summary><strong>devops-tools</strong> (12 changes)</summary>

- [clickhouse-pydantic-config](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/clickhouse-pydantic-config/SKILL.md) - updated (+25)
- [doppler-secret-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/doppler-secret-validation/SKILL.md) - updated (+15)
- [doppler-workflows](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/doppler-workflows/SKILL.md) - updated (+19/-2)
- [dual-channel-watchexec-notifications](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/dual-channel-watchexec/SKILL.md) - updated (+25)
- [firecrawl-self-hosted](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-self-hosted/SKILL.md) - updated (+15/-1)
- [ml-data-pipeline-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/ml-data-pipeline-architecture/SKILL.md) - updated (+32/-2)
- [ml-failfast-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/ml-failfast-validation/SKILL.md) - updated (+31/-1)
- [mlflow-python](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/mlflow-python/SKILL.md) - updated (+15)
- [python-logging-best-practices](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/python-logging-best-practices/SKILL.md) - updated (+23/-1)
- [session-chronicle](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/SKILL.md) - updated (+15)
- [session-recovery](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-recovery/SKILL.md) - updated (+19/-2)
- [telegram-bot-management](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/telegram-bot-management/SKILL.md) - updated (+15)

</details>

<details>
<summary><strong>doc-tools</strong> (7 changes)</summary>

- [ascii-diagram-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/ascii-diagram-validator/SKILL.md) - updated (+15)
- [documentation-standards](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/documentation-standards/SKILL.md) - updated (+15)
- [latex-build](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-build/SKILL.md) - updated (+19/-2)
- [latex-setup](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-setup/SKILL.md) - updated (+19/-2)
- [latex-tables](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-tables/SKILL.md) - updated (+19/-2)
- [pandoc-pdf-generation](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/pandoc-pdf-generation/SKILL.md) - updated (+15)
- [terminal-print](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/terminal-print/SKILL.md) - updated (+9)

</details>

<details>
<summary><strong>dotfiles-tools</strong> (1 change)</summary>

- [chezmoi-workflows](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/skills/chezmoi-workflows/SKILL.md) - updated (+23)

</details>

<details>
<summary><strong>gh-tools</strong> (2 changes)</summary>

- [issue-create](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issue-create/SKILL.md) - updated (+3/-1)
- [pr-gfm-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/pr-gfm-validator/SKILL.md) - updated (+15)

</details>

<details>
<summary><strong>iterm2-layout-config</strong> (1 change)</summary>

- [iterm2-layout](https://github.com/terrylica/cc-skills/blob/main/plugins/iterm2-layout-config/skills/iterm2-layout/SKILL.md) - updated (+6/-9)

</details>

<details>
<summary><strong>itp</strong> (9 changes)</summary>

- [adr-code-traceability](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/adr-code-traceability/SKILL.md) - updated (+12)
- [bootstrap-monorepo](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/bootstrap-monorepo/SKILL.md) - updated (+18/-1)
- [code-hardcode-audit](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/code-hardcode-audit/SKILL.md) - updated (+15)
- [impl-standards](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/impl-standards/SKILL.md) - updated (+12)
- [implement-plan-preflight](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/implement-plan-preflight/SKILL.md) - updated (+13)
- [mise-configuration](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-configuration/SKILL.md) - updated (+25/-3)
- [mise-tasks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/SKILL.md) - updated (+13)
- [pypi-doppler](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/pypi-doppler/SKILL.md) - updated (+9)
- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/SKILL.md) - updated (+16)

</details>

<details>
<summary><strong>itp-hooks</strong> (1 change)</summary>

- [hooks-development](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/SKILL.md) - updated (+15)

</details>

<details>
<summary><strong>link-tools</strong> (2 changes)</summary>

- [link-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/skills/link-validation/SKILL.md) - updated (+22)
- [link-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/skills/link-validator/SKILL.md) - updated (+15)

</details>

<details>
<summary><strong>mql5</strong> (4 changes)</summary>

- [article-extractor](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/article-extractor/SKILL.md) - updated (+24)
- [log-reader](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/log-reader/SKILL.md) - updated (+16/-1)
- [mql5-indicator-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/mql5-indicator-patterns/SKILL.md) - updated (+24)
- [python-workspace](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/python-workspace/SKILL.md) - updated (+15)

</details>

<details>
<summary><strong>notion-api</strong> (1 change)</summary>

- [notion-sdk](https://github.com/terrylica/cc-skills/blob/main/plugins/notion-api/skills/notion-sdk/SKILL.md) - updated (+27/-2)

</details>

<details>
<summary><strong>plugin-dev</strong> (2 changes)</summary>

- [plugin-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/plugin-validator/SKILL.md) - updated (+24)
- [skill-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/SKILL.md) - updated (+24)

</details>

<details>
<summary><strong>productivity-tools</strong> (1 change)</summary>

- [slash-command-factory](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/slash-command-factory/SKILL.md) - updated (+25)

</details>

<details>
<summary><strong>quality-tools</strong> (6 changes)</summary>

- [clickhouse-architect](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/clickhouse-architect/SKILL.md) - updated (+25)
- [code-clone-assistant](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/code-clone-assistant/SKILL.md) - updated (+22/-2)
- [multi-agent-e2e-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/multi-agent-e2e-validation/SKILL.md) - updated (+18/-1)
- [multi-agent-performance-profiling](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/multi-agent-performance-profiling/SKILL.md) - updated (+18/-1)
- [schema-e2e-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/schema-e2e-validation/SKILL.md) - updated (+3/-1)
- [symmetric-dogfooding](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/symmetric-dogfooding/SKILL.md) - updated (+22/-7)

</details>

<details>
<summary><strong>quant-research</strong> (2 changes)</summary>

- [adaptive-wfo-epoch](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/SKILL.md) - updated (+25)
- [rangebar-eval-metrics](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/SKILL.md) - updated (+25)

</details>

<details>
<summary><strong>ralph</strong> (2 changes)</summary>

- [constraint-discovery](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/skills/constraint-discovery/SKILL.md) - updated (+18/-1)
- [session-guidance](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/skills/session-guidance/SKILL.md) - updated (+18/-1)

</details>

<details>
<summary><strong>statusline-tools</strong> (1 change)</summary>

- [session-info](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/session-info/SKILL.md) - updated (+18/-1)

</details>


### Plugin READMEs

- [Alpha-Forge Worktree Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-worktree/README.md) - updated (+28)
- [asciinema-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/README.md) - updated (+30/-1)
- [devops-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/README.md) - updated (+14)
- [doc-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/README.md) - updated (+24/-5)
- [dotfiles-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/README.md) - updated (+18/-3)
- [gh-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/README.md) - updated (+57/-6)
- [Git-Town Workflow Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/README.md) - updated (+40/-14)
- [iterm2-layout-config](https://github.com/terrylica/cc-skills/blob/main/plugins/iterm2-layout-config/README.md) - updated (+22)
- [ITP Hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/README.md) - updated (+14)
- [ITP Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/README.md) - updated (+2/-2)
- [link-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/README.md) - updated (+52/-4)
- [mql5](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/README.md) - updated (+25/-4)
- [Notion API Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/notion-api/README.md) - updated (+17/-1)
- [plugin-dev](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/README.md) - updated (+44/-5)
- [productivity-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/README.md) - updated (+23)
- [quality-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/README.md) - updated (+78/-19)
- [quant-research](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/README.md) - updated (+53/-10)
- [Ralph Plugin for Claude Code](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/README.md) - updated (+17/-3)
- [RU](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/README.md) - updated (+70)
- [statusline-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/README.md) - updated (+48)

### Skill References

<details>
<summary><strong>asciinema-tools/asciinema-converter</strong> (1 file)</summary>

- [Integration Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-converter/references/integration-guide.md) - updated (+2/-2)

</details>

<details>
<summary><strong>devops-tools/python-logging-best-practices</strong> (1 file)</summary>

- [Python Logging Architecture Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/python-logging-best-practices/references/logging-architecture.md) - updated (+2/-2)

</details>

<details>
<summary><strong>itp/mise-configuration</strong> (1 file)</summary>

- [GitHub Token Multi-Account Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-configuration/references/github-tokens.md) - updated (+10/-6)

</details>

<details>
<summary><strong>itp/semantic-release</strong> (2 files)</summary>

- [Authentication for semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/authentication.md) - updated (+2/-1)
- [Local Release Workflow (Canonical)](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/local-release-workflow.md) - updated (+13/-11)

</details>

<details>
<summary><strong>mql5/article-extractor</strong> (1 file)</summary>

- [Data Sources](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/article-extractor/references/data-sources.md) - updated (+2/-2)

</details>

<details>
<summary><strong>quant-research/adaptive-wfo-epoch</strong> (2 files)</summary>

- [Range Bar Metrics: Time-Weighted Sharpe Ratio](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/range-bar-metrics.md) - updated (-4)
- [xLSTM Implementation Patterns for Financial Time Series](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/xlstm-implementation.md) - updated (-1)

</details>

<details>
<summary><strong>quant-research/rangebar-eval-metrics</strong> (2 files)</summary>

- [Anti-Patterns in Range Bar Metrics](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/references/anti-patterns.md) - updated (+1/-1)
- [Structured Logging Contract for AWFES Experiments](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/references/structured-logging.md) - updated (+1/-1)

</details>

<details>
<summary><strong>statusline-tools/session-info</strong> (1 file)</summary>

- [Session Registry Format](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/session-info/references/registry-format.md) - updated (+1/-1)

</details>


### Commands

<details>
<summary><strong>asciinema-tools</strong> (18 commands)</summary>

- [/asciinema-tools:analyze](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/analyze.md) - updated (+21)
- [/asciinema-tools:backup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/backup.md) - updated (+26)
- [/asciinema-tools:bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/bootstrap.md) - updated (+12)
- [/asciinema-tools:convert](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/convert.md) - updated (+10)
- [/asciinema-tools:daemon-logs](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-logs.md) - updated (+22)
- [/asciinema-tools:daemon-setup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-setup.md) - updated (+11)
- [/asciinema-tools:daemon-start](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-start.md) - updated (+9)
- [/asciinema-tools:daemon-status](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-status.md) - updated (+10)
- [/asciinema-tools:daemon-stop](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/daemon-stop.md) - updated (+9)
- [/asciinema-tools:finalize](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/finalize.md) - updated (+11)
- [/asciinema-tools:format](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/format.md) - updated (+21)
- [/asciinema-tools:full-workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/full-workflow.md) - updated (+10)
- [/asciinema-tools:hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/hooks.md) - updated (+25)
- [/asciinema-tools:play](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/play.md) - updated (+21)
- [/asciinema-tools:post-session](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/post-session.md) - updated (+24/-8)
- [/asciinema-tools:record](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/record.md) - updated (+21)
- [/asciinema-tools:setup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/setup.md) - updated (+23)
- [/asciinema-tools:summarize](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/summarize.md) - updated (+32/-10)

</details>

<details>
<summary><strong>dotfiles-tools</strong> (1 command)</summary>

- [Dotfiles Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/commands/hooks.md) - updated (+29)

</details>

<details>
<summary><strong>gh-tools</strong> (1 command)</summary>

- [gh-tools Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/commands/hooks.md) - updated (+29/-6)

</details>

<details>
<summary><strong>git-town-workflow</strong> (4 commands)</summary>

- [Git-Town Contribution Workflow — STOP AND READ](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/commands/contribute.md) - updated (+28/-6)
- [Git-Town Fork Workflow — STOP AND READ](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/commands/fork.md) - updated (+47/-26)
- [Git-Town Enforcement Hooks — Installation](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/commands/hooks.md) - updated (+28/-18)
- [Git-Town Setup — One-Time Configuration](https://github.com/terrylica/cc-skills/blob/main/plugins/git-town-workflow/commands/setup.md) - updated (+12)

</details>

<details>
<summary><strong>itp</strong> (4 commands)</summary>

- [⛔ ITP Workflow — STOP AND READ](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/go.md) - updated (+12)
- [ITP Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/hooks.md) - updated (+30)
- [/itp:release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/release.md) - updated (+31/-17)
- [ITP Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/setup.md) - updated (+1)

</details>

<details>
<summary><strong>itp-hooks</strong> (1 command)</summary>

- [ITP Hooks Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/commands/setup.md) - updated (+11)

</details>

<details>
<summary><strong>plugin-dev</strong> (1 command)</summary>

- [⛔ Create Plugin — STOP AND READ](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/commands/create.md) - updated (+11)

</details>

<details>
<summary><strong>ralph</strong> (5 commands)</summary>

- [Ralph Loop: Audit Now](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/audit-now.md) - updated (+9)
- [Ralph Loop: Config](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/config.md) - updated (+10)
- [Ralph Loop: Forbid](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/forbid.md) - updated (+13/-2)
- [Ralph Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/hooks.md) - updated (+24)
- [Ralph Loop: Status](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/commands/status.md) - updated (+20)

</details>

<details>
<summary><strong>ru</strong> (9 commands)</summary>

- [RU: Audit Now](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/audit-now.md) - updated (+10)
- [RU: Config](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/config.md) - updated (+10)
- [RU: Encourage](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/encourage.md) - updated (+10)
- [RU: Forbid](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/forbid.md) - updated (+10)
- [RU: Hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/hooks.md) - updated (+21)
- [RU: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/start.md) - updated (+22)
- [RU: Status](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/status.md) - updated (+19)
- [RU: Stop](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/stop.md) - updated (+10)
- [RU: Wizard](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/wizard.md) - updated (+10)

</details>

<details>
<summary><strong>statusline-tools</strong> (3 commands)</summary>

- [Status Line Hooks Manager](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/commands/hooks.md) - updated (+23)
- [Global Ignore Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/commands/ignore.md) - updated (+9)
- [Status Line Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/commands/setup.md) - updated (+10)

</details>


## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+5/-5)
- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+15/-10)

### General Documentation

- [Hooks Development Guide](https://github.com/terrylica/cc-skills/blob/main/docs/HOOKS.md) - updated (+1/-1)
- [Release Workflow Guide](https://github.com/terrylica/cc-skills/blob/main/docs/RELEASE.md) - updated (+35/-35)

## Other Documentation

### Other

- [Troubleshooting cc-skills Marketplace Installation](https://github.com/terrylica/cc-skills/blob/main/docs/troubleshooting/marketplace-installation.md) - updated (+2/-2)
- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+1)
- [Getting Started with Ralph (First-Time Users)](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/GETTING-STARTED.md) - updated (+1/-1)
- [ralph-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/hooks/templates/ralph-unified.md) - updated (+117/-21)

## [10.2.2](https://github.com/terrylica/cc-skills/compare/v10.2.1...v10.2.2) (2026-01-31)





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [doc-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/README.md) - updated (+2)
- [productivity-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/README.md) - updated (+47/-5)
- [quality-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/README.md) - updated (+4)
- [quant-research](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/README.md) - updated (+22/-3)

## [10.2.1](https://github.com/terrylica/cc-skills/compare/v10.2.0...v10.2.1) (2026-01-31)





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [RU](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/README.md) - updated (+2/-2)

### Commands

<details>
<summary><strong>ru</strong> (2 commands)</summary>

- [RU: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/start.md) - updated (+1/-1)
- [RU: Wizard](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/wizard.md) - renamed from `plugins/ru/commands/configure.md`

</details>

# [10.2.0](https://github.com/terrylica/cc-skills/compare/v10.1.2...v10.2.0) (2026-01-31)


### Features

* **ru:** add interactive AskUserQuestion guidance setup ([df61ce1](https://github.com/terrylica/cc-skills/commit/df61ce11889747771bed99cd8525dcee26486264))





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [RU](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/README.md) - updated (+32/-49)

### Commands

<details>
<summary><strong>ru</strong> (2 commands)</summary>

- [RU: Configure](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/configure.md) - new (+155)
- [RU: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/start.md) - updated (+150/-41)

</details>

## [10.1.2](https://github.com/terrylica/cc-skills/compare/v10.1.1...v10.1.2) (2026-01-30)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>doc-tools</strong> (1 change)</summary>

- [plotext-financial-chart](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/plotext-financial-chart/SKILL.md) - updated (+10/-3)

</details>


### Skill References

<details>
<summary><strong>doc-tools/plotext-financial-chart</strong> (1 file)</summary>

- [Plotext Financial Chart — API and Patterns Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/plotext-financial-chart/references/api-and-patterns.md) - updated (+33/-4)

</details>

## [10.1.1](https://github.com/terrylica/cc-skills/compare/v10.1.0...v10.1.1) (2026-01-30)





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [RU (Ralph Universal)](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/README.md) - updated (+1/-12)

### Commands

<details>
<summary><strong>ru</strong> (6 commands)</summary>

- [RU: Encourage](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/encourage.md) - updated (+1/-1)
- [RU: Forbid](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/forbid.md) - updated (+1/-1)
- [RU: Hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/hooks.md) - updated (+6/-6)
- [RU: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/start.md) - updated (+4/-4)
- [RU: Status](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/status.md) - updated (+1/-1)
- [RU: Stop](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/stop.md) - updated (+3/-3)

</details>

# [10.1.0](https://github.com/terrylica/cc-skills/compare/v10.0.1...v10.1.0) (2026-01-30)


### Features

* **release:** auto-enable new plugins in settings.json ([8c1851d](https://github.com/terrylica/cc-skills/commit/8c1851da50c504acf81e66a52b053815d6e82b0c))

## [10.0.1](https://github.com/terrylica/cc-skills/compare/v10.0.0...v10.0.1) (2026-01-30)


### Bug Fixes

* **itp-hooks:** prevent fork bomb pattern false positives on shell functions ([1cc3623](https://github.com/terrylica/cc-skills/commit/1cc36239c2e137e080e3f9f2874f22d9f70d65d0)), closes [#17](https://github.com/terrylica/cc-skills/issues/17)

# [10.0.0](https://github.com/terrylica/cc-skills/compare/v9.55.0...v10.0.0) (2026-01-30)


### Features

* **ru:** rename ralph-universal to ru for shorter invocation ([62707ad](https://github.com/terrylica/cc-skills/commit/62707add075b697ce496410270c853aed985b98e))


### BREAKING CHANGES

* **ru:** Plugin renamed from ralph-universal to ru.
All commands now use /ru:* prefix instead of /ralph-universal:*.

Changes:
- Renamed plugin directory from ralph-universal to ru
- Fixed config_schema.py to use ru-state.json (was ralph-state.json)
- Updated all config files to use ru-config.json
- Added missing commands: config.md, audit-now.md
- Updated marketplace.json registration

Migration: Replace /ralph-universal:* with /ru:* in all commands.

SRED-Type: experimental-development
SRED-Claim: RU





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [ralph-universal](https://github.com/terrylica/cc-skills/blob/v9.55.0/plugins/ralph-universal/README.md) - deleted
- [RU (Ralph Universal)](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/README.md) - new (+104)

### Commands

<details>
<summary><strong>ru</strong> (8 commands)</summary>

- [RU: Audit Now](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/audit-now.md) - new (+63)
- [RU: Config](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/config.md) - new (+79)
- [Ralph Universal: Encourage](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/encourage.md) - renamed from `plugins/ralph-universal/commands/encourage.md`
- [Ralph Universal: Forbid](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/forbid.md) - renamed from `plugins/ralph-universal/commands/forbid.md`
- [Ralph Universal: Hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/hooks.md) - renamed from `plugins/ralph-universal/commands/hooks.md`
- [Ralph Universal: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/start.md) - renamed from `plugins/ralph-universal/commands/start.md`
- [Ralph Universal: Status](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/status.md) - renamed from `plugins/ralph-universal/commands/status.md`
- [Ralph Universal: Stop](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/commands/stop.md) - renamed from `plugins/ralph-universal/commands/stop.md`

</details>


## Other Documentation

### Other

- [ralph-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ru/hooks/templates/ralph-unified.md) - renamed from `plugins/ralph-universal/hooks/templates/ralph-unified.md`

# [9.55.0](https://github.com/terrylica/cc-skills/compare/v9.54.0...v9.55.0) (2026-01-30)


### Features

* **ralph-universal:** add forbid/encourage commands for guidance ([27a546c](https://github.com/terrylica/cc-skills/commit/27a546c3ac75b534cdbb9925c818d79080e23c98))





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [Ralph Universal](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph-universal/README.md) - updated (+45/-19)

### Commands

<details>
<summary><strong>ralph-universal</strong> (2 commands)</summary>

- [Ralph Universal: Encourage](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph-universal/commands/encourage.md) - new (+102)
- [Ralph Universal: Forbid](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph-universal/commands/forbid.md) - new (+101)

</details>

# [9.54.0](https://github.com/terrylica/cc-skills/compare/v9.53.0...v9.54.0) (2026-01-30)


### Features

* **ralph-universal:** deep cleanup - remove all Alpha-Forge exclusivity ([67bbfab](https://github.com/terrylica/cc-skills/commit/67bbfab7ab05d48b3e73ca7acf8178f7e22fbf98)), closes [#12](https://github.com/terrylica/cc-skills/issues/12) [#13](https://github.com/terrylica/cc-skills/issues/13) [#14](https://github.com/terrylica/cc-skills/issues/14) [#15](https://github.com/terrylica/cc-skills/issues/15)





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [Ralph Universal](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph-universal/README.md) - updated (+12/-5)

## Other Documentation

### Other

- [ralph-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph-universal/hooks/templates/ralph-unified.md) - updated (+17/-152)

# [9.53.0](https://github.com/terrylica/cc-skills/compare/v9.52.0...v9.53.0) (2026-01-30)


### Features

* **ralph-universal:** add universal Ralph fork for any project type ([c7db6d8](https://github.com/terrylica/cc-skills/commit/c7db6d868d7c2e4275e3ae0eb6b23a1fdfeb00ee)), closes [#12](https://github.com/terrylica/cc-skills/issues/12)





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [Ralph Universal](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph-universal/README.md) - new (+68)

### Commands

<details>
<summary><strong>ralph-universal</strong> (4 commands)</summary>

- [Ralph Universal: Hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph-universal/commands/hooks.md) - new (+98)
- [Ralph Universal: Start](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph-universal/commands/start.md) - new (+141)
- [Ralph Universal: Status](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph-universal/commands/status.md) - new (+46)
- [Ralph Universal: Stop](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph-universal/commands/stop.md) - new (+44)

</details>


## Other Documentation

### Other

- [ralph-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph-universal/hooks/templates/ralph-unified.md) - new (+296)

# [9.52.0](https://github.com/terrylica/cc-skills/compare/v9.51.0...v9.52.0) (2026-01-30)


### Features

* **ralph:** improve UX for non-Alpha-Forge projects ([3e627ad](https://github.com/terrylica/cc-skills/commit/3e627ada1095e93497bdf48528d6de83c8d67f2e)), closes [#12-15](https://github.com/terrylica/cc-skills/issues/12-15) [#16](https://github.com/terrylica/cc-skills/issues/16)





---

## Documentation Changes

## Other Documentation

### Other

- [Ralph Adapters](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/docs/adapters.md) - new (+97)

# [9.51.0](https://github.com/terrylica/cc-skills/compare/v9.50.2...v9.51.0) (2026-01-30)


### Features

* **doc-tools:** add plotext-financial-chart skill for ASCII line charts ([3b9c1cb](https://github.com/terrylica/cc-skills/commit/3b9c1cbdbac25a91ba1b480339051f5442c8c409))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>doc-tools</strong> (1 change)</summary>

- [plotext-financial-chart](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/plotext-financial-chart/SKILL.md) - new (+145)

</details>

<details>
<summary><strong>quality-tools</strong> (1 change)</summary>

- [clickhouse-architect](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/clickhouse-architect/SKILL.md) - updated (+1)

</details>


### Plugin READMEs

- [doc-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/README.md) - updated (+2)

### Skill References

<details>
<summary><strong>doc-tools/plotext-financial-chart</strong> (2 files)</summary>

- [Plotext Financial Chart — API and Patterns Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/plotext-financial-chart/references/api-and-patterns.md) - new (+205)
- [Tool Selection Rationale](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/plotext-financial-chart/references/tool-selection.md) - new (+118)

</details>

<details>
<summary><strong>quality-tools/clickhouse-architect</strong> (1 file)</summary>

- [Cache Schema Evolution](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/clickhouse-architect/references/cache-schema-evolution.md) - new (+483)

</details>

## [9.50.2](https://github.com/terrylica/cc-skills/compare/v9.50.1...v9.50.2) (2026-01-30)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (2 changes)</summary>

- [mise-tasks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/SKILL.md) - updated (+5)
- [pypi-doppler](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/pypi-doppler/SKILL.md) - updated (+38)

</details>


### Skill References

<details>
<summary><strong>itp/mise-tasks</strong> (1 file)</summary>

- [Release Workflow Patterns for mise Tasks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/references/release-workflow-patterns.md) - new (+239)

</details>

<details>
<summary><strong>itp/semantic-release</strong> (1 file)</summary>

- [Python Projects Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/python.md) - updated (+27/-10)

</details>

## [9.50.1](https://github.com/terrylica/cc-skills/compare/v9.50.0...v9.50.1) (2026-01-27)


### Bug Fixes

* **itp-hooks:** make Vale hook cwd-agnostic with proper ANSI handling ([35e0325](https://github.com/terrylica/cc-skills/commit/35e032599de344b06d4023c08e2c90d0b96af314))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>doc-tools</strong> (1 change)</summary>

- [glossary-management](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/glossary-management/SKILL.md) - updated (+23/-3)

</details>


## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+9)

# [9.50.0](https://github.com/terrylica/cc-skills/compare/v9.49.0...v9.50.0) (2026-01-27)


### Features

* **quality-tools:** add symmetric-dogfooding skill for cross-repo validation ([323acc8](https://github.com/terrylica/cc-skills/commit/323acc847bb622b0a7802f8ca21f620d4f8822e7))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>plugin-dev</strong> (1 change)</summary>

- [skill-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/SKILL.md) - updated (+4/-4)

</details>

<details>
<summary><strong>quality-tools</strong> (1 change)</summary>

- [symmetric-dogfooding](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/symmetric-dogfooding/SKILL.md) - new (+258)

</details>


### Skill References

<details>
<summary><strong>plugin-dev/skill-architecture</strong> (1 file)</summary>

- [Creation Workflow](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/creation-workflow.md) - updated (+4/-4)

</details>

<details>
<summary><strong>quality-tools/symmetric-dogfooding</strong> (2 files)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/symmetric-dogfooding/references/evolution-log.md) - new (+13)
- [Example: trading-fitness and rangebar-py](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/symmetric-dogfooding/references/example-setup.md) - new (+82)

</details>

# [9.49.0](https://github.com/terrylica/cc-skills/compare/v9.48.2...v9.49.0) (2026-01-27)


### Features

* **itp-hooks:** enhance code traceability to include GitHub Issues ([4d0c730](https://github.com/terrylica/cc-skills/commit/4d0c730101c870088548f4176a79ce5258e316ca))

## [9.48.2](https://github.com/terrylica/cc-skills/compare/v9.48.1...v9.48.2) (2026-01-26)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>alpha-forge-worktree</strong> (1 change)</summary>

- [worktree-manager](https://github.com/terrylica/cc-skills/blob/main/plugins/alpha-forge-worktree/skills/worktree-manager/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>asciinema-tools</strong> (1 change)</summary>

- [asciinema-cast-format](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-cast-format/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>devops-tools</strong> (6 changes)</summary>

- [doppler-workflows](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/doppler-workflows/SKILL.md) - updated (+1/-1)
- [dual-channel-watchexec-notifications](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/dual-channel-watchexec/SKILL.md) - updated (+1/-1)
- [python-logging-best-practices](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/python-logging-best-practices/SKILL.md) - updated (+1/-1)
- [session-chronicle](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-chronicle/SKILL.md) - updated (+53/-23)
- [session-recovery](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/session-recovery/SKILL.md) - updated (+1/-1)
- [telegram-bot-management](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/telegram-bot-management/SKILL.md) - updated (+5/-2)

</details>

<details>
<summary><strong>doc-tools</strong> (5 changes)</summary>

- [ascii-diagram-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/ascii-diagram-validator/SKILL.md) - updated (+1/-1)
- [glossary-management](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/glossary-management/SKILL.md) - updated (+1/-1)
- [latex-build](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-build/SKILL.md) - updated (+11/-5)
- [latex-setup](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-setup/SKILL.md) - updated (+12/-6)
- [latex-tables](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/latex-tables/SKILL.md) - updated (+9/-5)

</details>

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [issue-create](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issue-create/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>iterm2-layout-config</strong> (1 change)</summary>

- [iterm2-layout](https://github.com/terrylica/cc-skills/blob/main/plugins/iterm2-layout-config/skills/iterm2-layout/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>link-tools</strong> (1 change)</summary>

- [link-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/link-tools/skills/link-validator/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>mql5</strong> (4 changes)</summary>

- [article-extractor](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/article-extractor/SKILL.md) - updated (+1/-1)
- [log-reader](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/log-reader/SKILL.md) - updated (+1/-1)
- [mql5-indicator-patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/mql5-indicator-patterns/SKILL.md) - updated (+1/-1)
- [python-workspace](https://github.com/terrylica/cc-skills/blob/main/plugins/mql5/skills/python-workspace/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>notion-api</strong> (1 change)</summary>

- [notion-sdk](https://github.com/terrylica/cc-skills/blob/main/plugins/notion-api/skills/notion-sdk/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>plugin-dev</strong> (1 change)</summary>

- [plugin-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/plugin-validator/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>quality-tools</strong> (2 changes)</summary>

- [code-clone-assistant](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/code-clone-assistant/SKILL.md) - updated (+13/-13)
- [schema-e2e-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/schema-e2e-validation/SKILL.md) - updated (+1/-5)

</details>

<details>
<summary><strong>ralph</strong> (2 changes)</summary>

- [constraint-discovery](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/skills/constraint-discovery/SKILL.md) - updated (+2/-1)
- [session-guidance](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/skills/session-guidance/SKILL.md) - updated (+21/-5)

</details>

## [9.48.1](https://github.com/terrylica/cc-skills/compare/v9.48.0...v9.48.1) (2026-01-26)





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>asciinema-tools</strong> (5 changes)</summary>

- [asciinema-analyzer](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-analyzer/SKILL.md) - updated (+1/-1)
- [asciinema-converter](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-converter/SKILL.md) - updated (+1/-1)
- [asciinema-player](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-player/SKILL.md) - updated (+1/-1)
- [asciinema-recorder](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-recorder/SKILL.md) - updated (+1/-1)
- [asciinema-streaming-backup](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>devops-tools</strong> (4 changes)</summary>

- [clickhouse-cloud-management](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/clickhouse-cloud-management/SKILL.md) - updated (+1/-1)
- [clickhouse-pydantic-config](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/clickhouse-pydantic-config/SKILL.md) - updated (+1/-6)
- [doppler-secret-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/doppler-secret-validation/SKILL.md) - updated (+1/-1)
- [mlflow-python](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/mlflow-python/SKILL.md) - updated (+1/-5)

</details>

<details>
<summary><strong>doc-tools</strong> (3 changes)</summary>

- [documentation-standards](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/documentation-standards/SKILL.md) - updated (+1/-1)
- [pandoc-pdf-generation](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/pandoc-pdf-generation/SKILL.md) - updated (+1/-1)
- [terminal-print](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/terminal-print/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>dotfiles-tools</strong> (1 change)</summary>

- [chezmoi-workflows](https://github.com/terrylica/cc-skills/blob/main/plugins/dotfiles-tools/skills/chezmoi-workflows/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [pr-gfm-validator](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/pr-gfm-validator/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>itp</strong> (7 changes)</summary>

- [adr-code-traceability](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/adr-code-traceability/SKILL.md) - updated (+1/-1)
- [adr-graph-easy-architect](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/adr-graph-easy-architect/SKILL.md) - updated (+10/-10)
- [code-hardcode-audit](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/code-hardcode-audit/SKILL.md) - updated (+1/-1)
- [graph-easy](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/graph-easy/SKILL.md) - updated (+1/-1)
- [impl-standards](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/impl-standards/SKILL.md) - updated (+1/-1)
- [implement-plan-preflight](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/implement-plan-preflight/SKILL.md) - updated (+1/-1)
- [pypi-doppler](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/pypi-doppler/SKILL.md) - updated (+23/-14)

</details>

<details>
<summary><strong>itp-hooks</strong> (1 change)</summary>

- [hooks-development](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>plugin-dev</strong> (1 change)</summary>

- [skill-architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>productivity-tools</strong> (1 change)</summary>

- [slash-command-factory](https://github.com/terrylica/cc-skills/blob/main/plugins/productivity-tools/skills/slash-command-factory/SKILL.md) - updated (+1/-1)

</details>

<details>
<summary><strong>quality-tools</strong> (3 changes)</summary>

- [clickhouse-architect](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/clickhouse-architect/SKILL.md) - updated (+1/-9)
- [multi-agent-e2e-validation](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/multi-agent-e2e-validation/SKILL.md) - updated (+1/-1)
- [multi-agent-performance-profiling](https://github.com/terrylica/cc-skills/blob/main/plugins/quality-tools/skills/multi-agent-performance-profiling/SKILL.md) - updated (+47/-1)

</details>

<details>
<summary><strong>quant-research</strong> (2 changes)</summary>

- [adaptive-wfo-epoch](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/SKILL.md) - updated (+1/-6)
- [rangebar-eval-metrics](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/SKILL.md) - updated (+1/-6)

</details>

# [9.48.0](https://github.com/terrylica/cc-skills/compare/v9.47.1...v9.48.0) (2026-01-26)


### Features

* **mise-configuration:** add hub-spoke architecture pattern ([4ab4446](https://github.com/terrylica/cc-skills/commit/4ab4446a4a9ebae1f0d545d5a1e6d258bc5d334b))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [mise-configuration](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-configuration/SKILL.md) - updated (+123/-1)

</details>

## [9.47.1](https://github.com/terrylica/cc-skills/compare/v9.47.0...v9.47.1) (2026-01-25)





---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+189/-150)

</details>


## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+2)

### General Documentation

- [Session Resume Context](https://github.com/terrylica/cc-skills/blob/main/docs/RESUME.md) - updated (+29/-1)

## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+42/-8)

# [9.47.0](https://github.com/terrylica/cc-skills/compare/v9.46.0...v9.47.0) (2026-01-23)


### Features

* **itp-hooks:** add GPU optimization guard with parameter-free batch tuning ([4e96550](https://github.com/terrylica/cc-skills/commit/4e9655046256d62d37716156ca72a1009f7723e2))





---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [ITP Hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/README.md) - updated (+25/-5)

## Repository Documentation

### General Documentation

- [Hooks Development Guide](https://github.com/terrylica/cc-skills/blob/main/docs/HOOKS.md) - updated (+8/-8)

# [9.46.0](https://github.com/terrylica/cc-skills/compare/v9.45.0...v9.46.0) (2026-01-22)


### Features

* **itp-hooks:** add Polars preference enforcement with PreToolUse dialog ([4c6973a](https://github.com/terrylica/cc-skills/commit/4c6973af415955151b896917be99978d4d628d4f))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| implemented | [Polars Preference Hook (Efficiency Preferences Framework)](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-22-polars-preference-hook.md) | new (+174) |

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (2 changes)</summary>

- [ML Data Pipeline Architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/ml-data-pipeline-architecture/SKILL.md) - updated (+6)
- [mlflow-python](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/mlflow-python/SKILL.md) - updated (+2)

</details>

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [impl-standards](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/impl-standards/SKILL.md) - updated (+30/-5)

</details>


### Plugin READMEs

- [ITP Hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/README.md) - updated (+30/-1)

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+2)

### General Documentation

- [Hooks Development Guide](https://github.com/terrylica/cc-skills/blob/main/docs/HOOKS.md) - updated (+9/-8)

## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+59/-17)

# [9.45.0](https://github.com/terrylica/cc-skills/compare/v9.44.1...v9.45.0) (2026-01-22)


### Bug Fixes

* **validation:** eliminate all plugin validator warnings ([f1afc80](https://github.com/terrylica/cc-skills/commit/f1afc80b6a105078547778c23375b95d32cdcec3))


### Features

* **itp-hooks:** add pyproject.toml root-only policy and path escape guards ([a39d5d6](https://github.com/terrylica/cc-skills/commit/a39d5d6fde21c336e9a19f7a7829b07d90bbe30a))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| implemented | [pyproject.toml Root-Only Policy](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-22-pyproject-toml-root-only-policy.md) | new (+126) |

## Plugin Documentation

### Skill References

<details>
<summary><strong>quant-research/rangebar-eval-metrics</strong> (1 file)</summary>

- [Sharpe Ratio Formulas for Range Bars](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/references/sharpe-formulas.md) - updated (+28)

</details>


## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+17/-3)

## [9.44.1](https://github.com/terrylica/cc-skills/compare/v9.44.0...v9.44.1) (2026-01-22)


### Bug Fixes

* **doc-tools:** improve glossary-management skill documentation ([9c6570c](https://github.com/terrylica/cc-skills/commit/9c6570c73c6ff3df45582e30985abd4615b8186a))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>doc-tools</strong> (1 change)</summary>

- [glossary-management](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/glossary-management/SKILL.md) - updated (+45/-3)

</details>


## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+4/-2)

# [9.44.0](https://github.com/terrylica/cc-skills/compare/v9.43.0...v9.44.0) (2026-01-22)


### Features

* **doc-tools:** add glossary-management skill for terminology SSoT ([5929199](https://github.com/terrylica/cc-skills/commit/59291999ef5f059b098046889c67b3f333605f5e))





---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>doc-tools</strong> (1 change)</summary>

- [glossary-management](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/glossary-management/SKILL.md) - new (+206)

</details>

# [9.43.0](https://github.com/terrylica/cc-skills/compare/v9.42.0...v9.43.0) (2026-01-22)


### Features

* **itp-hooks:** add hoisted dev deps enforcement for uv workspaces ([fe42d8d](https://github.com/terrylica/cc-skills/commit/fe42d8d795661d9ca4f0084eaed4dbfc2d2d8274))





---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status | ADR | Change |
|--------|-----|--------|
| implemented | [UV Reminder Hook for Pip Usage](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-10-uv-reminder-hook.md) | updated (+20/-3) |

### Design Specs

- [UV Reminder Hook](https://github.com/terrylica/cc-skills/blob/main/docs/design/2026-01-10-uv-reminder-hook/spec.md) - new (+158)

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [mise-configuration](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-configuration/SKILL.md) - updated (+36)

</details>


### Skill References

<details>
<summary><strong>itp/mise-tasks</strong> (1 file)</summary>

- [Meta-Prompt: Autonomous Polyglot Monorepo Bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/references/bootstrap-monorepo.md) - updated (+44/-9)

</details>

<details>
<summary><strong>quant-research/rangebar-eval-metrics</strong> (1 file)</summary>

- [Sharpe Ratio Formulas for Range Bars](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/references/sharpe-formulas.md) - updated (+81/-3)

</details>


## Repository Documentation

### Root Documentation

- [[9.42.0](https://github.com/terrylica/cc-skills/compare/v9.41.0...v9.42.0) (2026-01-22)](https://github.com/terrylica/cc-skills/blob/main/CHANGELOG.md) - updated (+504/-1591)
- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+4/-1)

### General Documentation

- [Documentation Guide](https://github.com/terrylica/cc-skills/blob/main/docs/CLAUDE.md) - updated (+2)
- [Hooks Development Guide](https://github.com/terrylica/cc-skills/blob/main/docs/HOOKS.md) - updated (+59/-9)
- [Session Resume Context](https://github.com/terrylica/cc-skills/blob/main/docs/RESUME.md) - new (+59)

## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+28/-14)

# [9.42.0](https://github.com/terrylica/cc-skills/compare/v9.41.0...v9.42.0) (2026-01-22)

### Features

- **itp-hooks:** add TypeScript posttooluse-reminder with venv detection ([fe38fd5](https://github.com/terrylica/cc-skills/commit/fe38fd5640c0a7c244934d0801c82d0a6a8e767a))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status      | ADR                                                                                                                        | Change           |
| ----------- | -------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| implemented | [UV Reminder Hook for Pip Usage](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-10-uv-reminder-hook.md) | updated (+25/-9) |

### Design Specs

| Spec                                                                                                                 | Change  |
| -------------------------------------------------------------------------------------------------------------------- | ------- |
| [UV Reminder Hook](https://github.com/terrylica/cc-skills/blob/main/docs/design/2026-01-10-uv-reminder-hook/spec.md) | created |

### Migration Notes

**Bash to TypeScript**: `posttooluse-reminder.sh` → `posttooluse-reminder.ts`

- Runtime: bash + jq → Bun
- Tests: Manual → 33 automated unit tests
- New patterns: venv activation detection (`source .venv/bin/activate`)
- Exception handling: documentation context, grep searches

# [9.41.0](https://github.com/terrylica/cc-skills/compare/v9.40.3...v9.41.0) (2026-01-22)

### Features

- **itp-hooks:** add Vale terminology enforcement hooks for CLAUDE.md ([bf2e577](https://github.com/terrylica/cc-skills/commit/bf2e577d5062c16e32927988d38d69f43341bee3))

---

## Documentation Changes

## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - updated (+53/-4)

## [9.40.3](https://github.com/terrylica/cc-skills/compare/v9.40.2...v9.40.3) (2026-01-22)

---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+34/-29)

</details>

## [9.40.2](https://github.com/terrylica/cc-skills/compare/v9.40.1...v9.40.2) (2026-01-22)

### Bug Fixes

- **itp-hooks:** use additionalContext for Stop hook Claude visibility ([dc90bc3](https://github.com/terrylica/cc-skills/commit/dc90bc3f2c44120ba0b93679c44281b7f5824f58))

## [9.40.1](https://github.com/terrylica/cc-skills/compare/v9.40.0...v9.40.1) (2026-01-22)

### Bug Fixes

- **itp-hooks:** narrow exclude_paths to not block examples/research ([89098d8](https://github.com/terrylica/cc-skills/commit/89098d88d933995fca33d7ba7c059fac7c583bd3))

# [9.40.0](https://github.com/terrylica/cc-skills/compare/v9.39.1...v9.40.0) (2026-01-22)

### Features

- **itp-hooks:** add multi-layer time-weighted Sharpe guard ([7961ba2](https://github.com/terrylica/cc-skills/commit/7961ba282dd66c47786719951a2b378704fe1463))

## [9.39.1](https://github.com/terrylica/cc-skills/compare/v9.39.0...v9.39.1) (2026-01-21)

---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [devops-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/README.md) - updated (+48/-11)

## Repository Documentation

### Root Documentation

- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+3/-3)

# [9.39.0](https://github.com/terrylica/cc-skills/compare/v9.38.2...v9.39.0) (2026-01-21)

### Features

- **devops-tools:** add firecrawl-self-hosted and ML skills ([79921d0](https://github.com/terrylica/cc-skills/commit/79921d0d02814aca10d6990d670ecc819a8e3c70))

---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>asciinema-tools</strong> (1 change)</summary>

- [asciinema-converter](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-converter/SKILL.md) - updated (+204/-1)

</details>

<details>
<summary><strong>devops-tools</strong> (3 changes)</summary>

- [Firecrawl Self-Hosted Operations](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/firecrawl-self-hosted/SKILL.md) - new (+546)
- [ML Data Pipeline Architecture](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/ml-data-pipeline-architecture/SKILL.md) - new (+291)
- [ML Fail-Fast Validation](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/ml-failfast-validation/SKILL.md) - new (+450)

</details>

### Skill References

<details>
<summary><strong>asciinema-tools/asciinema-converter</strong> (3 files)</summary>

- [Anti-Patterns in asciinema Conversion](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-converter/references/anti-patterns.md) - new (+271)
- [Batch Processing Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-converter/references/batch-processing.md) - new (+291)
- [Integration Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-converter/references/integration-guide.md) - new (+262)

</details>

### Commands

<details>
<summary><strong>asciinema-tools</strong> (1 command)</summary>

- [/asciinema-tools:convert](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/convert.md) - updated (+53/-9)

</details>

## [9.38.2](https://github.com/terrylica/cc-skills/compare/v9.38.1...v9.38.2) (2026-01-21)

### Bug Fixes

- **adaptive-wfo-epoch:** standardize sharpe_tw naming across all reference docs ([8f9bc78](https://github.com/terrylica/cc-skills/commit/8f9bc78a1ed26f76ef84d03cbfa574312c662425))
- **itp-hooks:** add PEP 723 library module storm guard ([31aca05](https://github.com/terrylica/cc-skills/commit/31aca05dace6e55509abad1b9cbf6d4ce8364c40))

---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/SKILL.md) - updated (+2)

</details>

<details>
<summary><strong>quant-research</strong> (2 changes)</summary>

- [adaptive-wfo-epoch](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/SKILL.md) - updated (+119/-34)
- [rangebar-eval-metrics](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/SKILL.md) - updated (+1)

</details>

### Skill References

<details>
<summary><strong>itp/mise-tasks</strong> (1 file)</summary>

- [Meta-Prompt: Autonomous Polyglot Monorepo Bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/references/bootstrap-monorepo.md) - updated (+3)

</details>

<details>
<summary><strong>itp/semantic-release</strong> (2 files)</summary>

- [Python Projects Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/python.md) - updated (+6)
- [Troubleshooting](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/troubleshooting.md) - updated (+102)

</details>

<details>
<summary><strong>quant-research/adaptive-wfo-epoch</strong> (7 files)</summary>

- [Anti-Patterns: Adaptive Walk-Forward Epoch Selection](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/anti-patterns.md) - updated (+6/-3)
- [Feature Sets for BiLSTM Training](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/feature-sets.md) - new (+211)
- [Look-Ahead Bias Prevention Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/look-ahead-bias.md) - updated (+73/-15)
- [OOS Application Phase Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/oos-application.md) - updated (+34/-18)
- [OOS Metrics Specification Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/oos-metrics.md) - updated (+61/-45)
- [Range Bar Metrics: Time-Weighted Sharpe Ratio](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/range-bar-metrics.md) - new (+295)
- [xLSTM Implementation Patterns for Financial Time Series](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/xlstm-implementation.md) - new (+261)

</details>

<details>
<summary><strong>quant-research/rangebar-eval-metrics</strong> (1 file)</summary>

- [Structured Logging Contract for AWFES Experiments](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/references/structured-logging.md) - new (+299)

</details>

## [9.38.1](https://github.com/terrylica/cc-skills/compare/v9.38.0...v9.38.1) (2026-01-20)

### Bug Fixes

- **adaptive-wfo-epoch:** second audit remediation - code errors and documentation ([d20ad3e](https://github.com/terrylica/cc-skills/commit/d20ad3e053f0f87948044ca9d0826fe9adad7328))

---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>quant-research</strong> (1 change)</summary>

- [adaptive-wfo-epoch](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/SKILL.md) - updated (+469/-91)

</details>

### Skill References

<details>
<summary><strong>quant-research/adaptive-wfo-epoch</strong> (5 files)</summary>

- [Anti-Patterns: Adaptive Walk-Forward Epoch Selection](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/anti-patterns.md) - updated (+174/-28)
- [Epoch Smoothing Methods Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/epoch-smoothing.md) - updated (+71/-23)
- [Look-Ahead Bias Prevention Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/look-ahead-bias.md) - updated (+17/-2)
- [Mathematical Formulation: Adaptive Walk-Forward Epoch Selection](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/mathematical-formulation.md) - updated (+24/-4)
- [OOS Application Phase Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/oos-application.md) - updated (+36/-15)

</details>

# [9.38.0](https://github.com/terrylica/cc-skills/compare/v9.37.0...v9.38.0) (2026-01-19)

### Features

- **quant-research:** comprehensive audit remediation with SOTA references ([6a671ca](https://github.com/terrylica/cc-skills/commit/6a671ca42821e819070ffd3c110f17d4ee0799c5))

---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>quant-research</strong> (2 changes)</summary>

- [adaptive-wfo-epoch](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/SKILL.md) - updated (+640/-6)
- [rangebar-eval-metrics](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/SKILL.md) - updated (+25/-5)

</details>

### Skill References

<details>
<summary><strong>quant-research/adaptive-wfo-epoch</strong> (4 files)</summary>

- [Epoch Smoothing Methods Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/epoch-smoothing.md) - new (+427)
- [Look-Ahead Bias Prevention Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/look-ahead-bias.md) - new (+325)
- [OOS Application Phase Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/oos-application.md) - new (+356)
- [OOS Metrics Specification Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/oos-metrics.md) - new (+468)

</details>

<details>
<summary><strong>quant-research/rangebar-eval-metrics</strong> (4 files)</summary>

- [Anti-Patterns in Range Bar Metrics](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/references/anti-patterns.md) - new (+274)
- [Metrics JSON Schema](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/references/metrics-schema.md) - new (+343)
- [State-of-the-Art Methods (2025-2026)](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/references/sota-2025-2026.md) - new (+631)
- [Worked Examples](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/references/worked-examples.md) - new (+484)

</details>

# [9.37.0](https://github.com/terrylica/cc-skills/compare/v9.36.1...v9.37.0) (2026-01-19)

### Features

- **quant-research:** add adaptive-wfo-epoch skill and enhance metrics ([bb58f7a](https://github.com/terrylica/cc-skills/commit/bb58f7a47e088cf681a4912fb224ae589a11401a))

---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>quant-research</strong> (2 changes)</summary>

- [adaptive-wfo-epoch](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/SKILL.md) - new (+405)
- [rangebar-eval-metrics](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/SKILL.md) - updated (+40)

</details>

### Skill References

<details>
<summary><strong>quant-research/adaptive-wfo-epoch</strong> (4 files)</summary>

- [Academic Foundations: Adaptive Walk-Forward Epoch Selection](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/academic-foundations.md) - new (+264)
- [Anti-Patterns: Adaptive Walk-Forward Epoch Selection](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/anti-patterns.md) - new (+374)
- [Decision Tree: Adaptive Walk-Forward Epoch Selection](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/epoch-selection-decision-tree.md) - new (+569)
- [Mathematical Formulation: Adaptive Walk-Forward Epoch Selection](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/adaptive-wfo-epoch/references/mathematical-formulation.md) - new (+351)

</details>

<details>
<summary><strong>quant-research/rangebar-eval-metrics</strong> (2 files)</summary>

- [ML Prediction Quality Metrics](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/references/ml-prediction-quality.md) - updated (+73/-7)
- [Risk Metrics for Range Bars](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/references/risk-metrics.md) - updated (+34/-3)

</details>

## [9.36.1](https://github.com/terrylica/cc-skills/compare/v9.36.0...v9.36.1) (2026-01-19)

### Bug Fixes

- **quant-research:** add session-specific annualization guidance ([8da18df](https://github.com/terrylica/cc-skills/commit/8da18df5fc244277a0ba349eb529b56ebf684a5f))

---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>quant-research</strong> (1 change)</summary>

- [rangebar-eval-metrics](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/SKILL.md) - updated (+11)

</details>

### Skill References

<details>
<summary><strong>quant-research/rangebar-eval-metrics</strong> (1 file)</summary>

- [Crypto Market Considerations](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/references/crypto-markets.md) - updated (+127/-24)

</details>

# [9.36.0](https://github.com/terrylica/cc-skills/compare/v9.35.3...v9.36.0) (2026-01-19)

### Features

- **quant-research:** add quantitative research metrics plugin ([8c93d22](https://github.com/terrylica/cc-skills/commit/8c93d2287e80bda24caef24fcaa9044d4b79d49b))

---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>quant-research</strong> (1 change)</summary>

- [rangebar-eval-metrics](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/SKILL.md) - new (+144)

</details>

### Plugin READMEs

- [quant-research](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/README.md) - new (+28)

### Skill References

<details>
<summary><strong>quant-research/rangebar-eval-metrics</strong> (5 files)</summary>

- [Crypto Market Considerations](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/references/crypto-markets.md) - new (+233)
- [ML Prediction Quality Metrics](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/references/ml-prediction-quality.md) - new (+250)
- [Risk Metrics for Range Bars](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/references/risk-metrics.md) - new (+226)
- [Sharpe Ratio Formulas for Range Bars](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/references/sharpe-formulas.md) - new (+247)
- [Temporal Aggregation for Range Bars](https://github.com/terrylica/cc-skills/blob/main/plugins/quant-research/skills/rangebar-eval-metrics/references/temporal-aggregation.md) - new (+140)

</details>

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+1/-1)

## [9.35.3](https://github.com/terrylica/cc-skills/compare/v9.35.2...v9.35.3) (2026-01-19)

### Bug Fixes

- **sred-commit-guard:** handle heredoc and file-based commit messages ([6c9202f](https://github.com/terrylica/cc-skills/commit/6c9202f026312af7612c5a92a96dfc55ad8d7506))

---

## Documentation Changes

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+1/-1)

## [9.35.2](https://github.com/terrylica/cc-skills/compare/v9.35.1...v9.35.2) (2026-01-19)

---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [bootstrap-monorepo](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/bootstrap-monorepo/SKILL.md) - updated (+2/-1)

</details>

### Skill References

<details>
<summary><strong>itp/mise-tasks</strong> (1 file)</summary>

- [Meta-Prompt: Autonomous Polyglot Monorepo Bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/references/bootstrap-monorepo.md) - updated (+274)

</details>

## [9.35.1](https://github.com/terrylica/cc-skills/compare/v9.35.0...v9.35.1) (2026-01-19)

# [9.35.0](https://github.com/terrylica/cc-skills/compare/v9.34.0...v9.35.0) (2026-01-18)

### Features

- **itp-hooks:** dynamic SR&ED project discovery via Claude Agent SDK ([#10](https://github.com/terrylica/cc-skills/issues/10)) ([1f7c170](https://github.com/terrylica/cc-skills/commit/1f7c170316ecb09cc3ec098f06c215a0db545666))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status   | ADR                                                                                                                                                    | Change     |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- |
| accepted | [SR&ED Dynamic Project Discovery via Claude Agent SDK](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-18-sred-dynamic-discovery.md) | new (+358) |

### Design Specs

- [SR&ED Project Discovery: Forked Haiku Session via Claude Agent SDK](https://github.com/terrylica/cc-skills/blob/main/docs/design/2026-01-18-sred-dynamic-discovery/spec.md) - new (+605)

# [9.34.0](https://github.com/terrylica/cc-skills/compare/v9.33.2...v9.34.0) (2026-01-18)

### Features

- **itp-hooks:** make SRED-Claim mandatory with registry validation ([51f719b](https://github.com/terrylica/cc-skills/commit/51f719b253f47a2661f7163079fd33ea4b633d89))

## [9.33.2](https://github.com/terrylica/cc-skills/compare/v9.33.1...v9.33.2) (2026-01-18)

---

## Documentation Changes

## Repository Documentation

### General Documentation

- [Hooks Development Guide](https://github.com/terrylica/cc-skills/blob/main/docs/HOOKS.md) - updated (+23/-8)

## Other Documentation

### Other

- [itp-hooks Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/CLAUDE.md) - new (+93)

## [9.33.1](https://github.com/terrylica/cc-skills/compare/v9.33.0...v9.33.1) (2026-01-18)

# [9.33.0](https://github.com/terrylica/cc-skills/compare/v9.32.0...v9.33.0) (2026-01-18)

### Features

- **itp-hooks:** add TypeScript/Bun hook template and SR&ED commit guard ([36389c7](https://github.com/terrylica/cc-skills/commit/36389c7b7814091590d6b2d7f8805a9871146c38))

---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+191/-2)

</details>

# [9.32.0](https://github.com/terrylica/cc-skills/compare/v9.31.0...v9.32.0) (2026-01-18)

### Features

- **itp:** add SR&ED commit conventions and GitHub repository setup ([06260f6](https://github.com/terrylica/cc-skills/commit/06260f6ecfcbae57295741fe6ce568cf4623942f))

---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>itp/mise-tasks</strong> (1 file)</summary>

- [Meta-Prompt: Autonomous Polyglot Monorepo Bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/references/bootstrap-monorepo.md) - updated (+831/-11)

</details>

# [9.31.0](https://github.com/terrylica/cc-skills/compare/v9.30.1...v9.31.0) (2026-01-16)

### Features

- **semantic-release:** align with polyglot monorepo best practices ([96d6365](https://github.com/terrylica/cc-skills/commit/96d6365c2ed514e3ee6a77d7978b1d86db669300))

---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/SKILL.md) - updated (+38/-34)

</details>

### Skill References

<details>
<summary><strong>itp/semantic-release</strong> (5 files)</summary>

- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/evolution-log.md) - updated (+33)
- [List affected packages](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/monorepo-support.md) - updated (+210/-1)
- [Python Projects Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/python.md) - updated (+18/-15)
- [Rust Projects with release-plz](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/rust.md) - updated (+4)
- [Troubleshooting](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/troubleshooting.md) - updated (+8/-7)

</details>

## [9.30.1](https://github.com/terrylica/cc-skills/compare/v9.30.0...v9.30.1) (2026-01-16)

### Bug Fixes

- **gh-tools:** shorten issue-create skill description to under 200 chars ([ba31e2f](https://github.com/terrylica/cc-skills/commit/ba31e2f6faf2f0029af1233de7382009ec0fdec3)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools)

---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [issue-create](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issue-create/SKILL.md) - updated (+1/-1)

</details>

# [9.30.0](https://github.com/terrylica/cc-skills/compare/v9.29.0...v9.30.0) (2026-01-16)

### Features

- **statusline-tools:** add session-info skill with registry tracking ([e7f6731](https://github.com/terrylica/cc-skills/commit/e7f673118b436b38da0fa6e96f3ab9fb4a5037ea))

---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>statusline-tools</strong> (1 change)</summary>

- [session-info](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/session-info/SKILL.md) - new (+65)

</details>

### Skill References

<details>
<summary><strong>statusline-tools/session-info</strong> (1 file)</summary>

- [Session Registry Format](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/skills/session-info/references/registry-format.md) - new (+75)

</details>

# [9.29.0](https://github.com/terrylica/cc-skills/compare/v9.28.0...v9.29.0) (2026-01-16)

### Features

- **gh-tools:** add issue-create skill with AI-powered labeling ([1b607ab](https://github.com/terrylica/cc-skills/commit/1b607ab53aed5b1f00233c5edc0d0f931ff84b5b)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools) [#models](https://github.com/terrylica/cc-skills/issues/models) [#models](https://github.com/terrylica/cc-skills/issues/models) [#issue-body-file-guard](https://github.com/terrylica/cc-skills/issues/issue-body-file-guard) [#models](https://github.com/terrylica/cc-skills/issues/models)

---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>gh-tools</strong> (1 change)</summary>

- [issue-create](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issue-create/SKILL.md) - new (+196)

</details>

### Plugin READMEs

- [gh-tools Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/README.md) - updated (+6/-5)

### Skill References

<details>
<summary><strong>gh-tools/issue-create</strong> (3 files)</summary>

- [AI Prompts Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issue-create/references/ai-prompts.md) - new (+124)
- [Content Types Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issue-create/references/content-types.md) - new (+130)
- [Label Strategy Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/gh-tools/skills/issue-create/references/label-strategy.md) - new (+115)

</details>

# [9.28.0](https://github.com/terrylica/cc-skills/compare/v9.27.0...v9.28.0) (2026-01-16)

### Features

- **mise-tasks:** add Pants + mise polyglot monorepo patterns (Level 11) ([fdf3cc0](https://github.com/terrylica/cc-skills/commit/fdf3cc093da50042c27467bde4bc4af33a2ae894))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status   | ADR                                                                                                                                                    | Change     |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- |
| accepted | [mise [env] Token Loading: read_file vs exec](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-15-mise-env-token-loading-patterns.md) | new (+129) |

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (2 changes)</summary>

- [bootstrap-monorepo](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/bootstrap-monorepo/SKILL.md) - new (+40)
- [mise-tasks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/SKILL.md) - updated (+103)

</details>

### Skill References

<details>
<summary><strong>itp/mise-tasks</strong> (2 files)</summary>

- [Meta-Prompt: Autonomous Polyglot Monorepo Bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/references/bootstrap-monorepo.md) - new (+451)
- [Polyglot Monorepo Affected Detection](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/mise-tasks/references/polyglot-affected.md) - new (+265)

</details>

# [9.27.0](https://github.com/terrylica/cc-skills/compare/v9.26.2...v9.27.0) (2026-01-15)

### Features

- **devops-tools:** add python-logging-best-practices skill ([1243419](https://github.com/terrylica/cc-skills/commit/1243419f5ed35233d36ed4585db3667b86c114c9))

---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>devops-tools</strong> (1 change)</summary>

- [python-logging-best-practices](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/python-logging-best-practices/SKILL.md) - new (+186)

</details>

### Skill References

<details>
<summary><strong>devops-tools/python-logging-best-practices</strong> (4 files)</summary>

- [Python Logging Architecture Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/python-logging-best-practices/references/logging-architecture.md) - new (+136)
- [Loguru Configuration Patterns](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/python-logging-best-practices/references/loguru-patterns.md) - new (+126)
- [Migration Guide: print() to Structured Logging](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/python-logging-best-practices/references/migration-guide.md) - new (+205)
- [platformdirs - Cross-Platform Directory Handling](https://github.com/terrylica/cc-skills/blob/main/plugins/devops-tools/skills/python-logging-best-practices/references/platformdirs-xdg.md) - new (+88)

</details>

<details>
<summary><strong>itp/semantic-release</strong> (1 file)</summary>

- [Version Alignment Standards](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/version-alignment.md) - updated (+74)

</details>

<details>
<summary><strong>plugin-dev/skill-architecture</strong> (1 file)</summary>

- [Path Patterns Reference](https://github.com/terrylica/cc-skills/blob/main/plugins/plugin-dev/skills/skill-architecture/references/path-patterns.md) - updated (+59/-5)

</details>

## Repository Documentation

### General Documentation

- [Plugin Lifecycle and Configuration](https://github.com/terrylica/cc-skills/blob/main/docs/PLUGIN-LIFECYCLE.md) - new (+287)

## Other Documentation

### Other

- [version-guard-claude-md-issue](https://github.com/terrylica/cc-skills/blob/main/docs/issues/version-guard-claude-md-issue.md) - new (+63)
- [Troubleshooting cc-skills Marketplace Installation](https://github.com/terrylica/cc-skills/blob/main/docs/troubleshooting/marketplace-installation.md) - updated (+89)

## [9.26.2](https://github.com/terrylica/cc-skills/compare/v9.26.1...v9.26.2) (2026-01-14)

### Bug Fixes

- **itp-hooks:** correct nested code block formatting in BUILD INSTRUCTIONS section ([de158d1](https://github.com/terrylica/cc-skills/commit/de158d187141623954f6d276da54a92ad8ce67bb))

---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+9/-13)

</details>

## [9.26.1](https://github.com/terrylica/cc-skills/compare/v9.26.0...v9.26.1) (2026-01-14)

### Bug Fixes

- **itp-hooks:** align troubleshooting table columns in lifecycle reference ([b9c4799](https://github.com/terrylica/cc-skills/commit/b9c4799ce595c94dd1016c019063632e19c830bc))

---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+34/-28)

</details>

# [9.26.0](https://github.com/terrylica/cc-skills/compare/v9.25.0...v9.26.0) (2026-01-13)

### Bug Fixes

- **itp-hooks:** improve shell variable detection regex pattern ([8d4713c](https://github.com/terrylica/cc-skills/commit/8d4713c4163be6b21beeb655a26110803452096d))

### Features

- **itp-hooks:** rename silent-failure-detector to code-correctness-guard ([e72475c](https://github.com/terrylica/cc-skills/commit/e72475cea543f8e032e1beec8edd12db336ae08c))

---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [ITP Hooks](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/README.md) - updated (+10/-9)

# [9.25.0](https://github.com/terrylica/cc-skills/compare/v9.24.8...v9.25.0) (2026-01-13)

### Features

- **itp-hooks:** add process storm prevention guard ([754acaf](https://github.com/terrylica/cc-skills/commit/754acafe33f45f8f22ccfc98737cfe54a321d33a))

## [9.24.8](https://github.com/terrylica/cc-skills/compare/v9.24.7...v9.24.8) (2026-01-13)

### Bug Fixes

- delete git-account-validator plugin (mise [env] is permanent solution) ([584d0b6](https://github.com/terrylica/cc-skills/commit/584d0b6c3b27f8520ddbd0bd6e8953a219bf56e3))
- remove remaining gh CLI calls to prevent process storms ([ca1b890](https://github.com/terrylica/cc-skills/commit/ca1b890f8988bc4d783b316420b88295dd6658da))

---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [git-account-validator](https://github.com/terrylica/cc-skills/blob/v9.24.7/plugins/git-account-validator/README.md) - deleted

### Commands

<details>
<summary><strong>asciinema-tools</strong> (2 commands)</summary>

- [/asciinema-tools:bootstrap](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/bootstrap.md) - updated (+2/-2)
- [/asciinema-tools:finalize](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/commands/finalize.md) - updated (+9/-9)

</details>

<details>
<summary><strong>git-account-validator</strong> (1 command)</summary>

- [hooks](https://github.com/terrylica/cc-skills/blob/v9.24.7/plugins/git-account-validator/commands/hooks.md) - deleted

</details>

## Repository Documentation

### Root Documentation

- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+23/-27)

### General Documentation

- [Hooks Development Guide](https://github.com/terrylica/cc-skills/blob/main/docs/HOOKS.md) - updated (+8/-9)

## Other Documentation

### Other

- [Troubleshooting cc-skills Marketplace Installation](https://github.com/terrylica/cc-skills/blob/main/docs/troubleshooting/marketplace-installation.md) - updated (+1/-1)
- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (+7/-8)
- [Getting Started with Ralph (First-Time Users)](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/GETTING-STARTED.md) - updated (+1/-1)

## [9.24.7](https://github.com/terrylica/cc-skills/compare/v9.24.6...v9.24.7) (2026-01-13)

### Bug Fixes

- **git-town-workflow:** correct plugin.json schema ([71a4b8a](https://github.com/terrylica/cc-skills/commit/71a4b8a417910473aa202d860452eddf284ce7ff))
- remove gh api calls from release tasks to prevent process storms ([ac0dde1](https://github.com/terrylica/cc-skills/commit/ac0dde115424ac9abbadf6c8e4f246d3587826d4))
- remove trailing slashes from plugin source paths ([269d2db](https://github.com/terrylica/cc-skills/commit/269d2db589ad949535eb28a702ff63acd6d7389b))

---

## Documentation Changes

## Repository Documentation

### Root Documentation

- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+480/-236)

## Other Documentation

### Other

- [Troubleshooting cc-skills Marketplace Installation](https://github.com/terrylica/cc-skills/blob/main/docs/troubleshooting/marketplace-installation.md) - updated (+175/-370)
- [Getting Started with Ralph (First-Time Users)](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/GETTING-STARTED.md) - updated (+34/-28)

## [9.24.6](https://github.com/terrylica/cc-skills/compare/v9.24.5...v9.24.6) (2026-01-12)

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status  | ADR                                                                                                                                                 | Change    |
| ------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| unknown | [mise gh CLI Incompatibility with Claude Code](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-12-mise-gh-cli-incompatibility.md) | new (+55) |

## Plugin Documentation

### Plugin READMEs

- [ITP Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/README.md) - updated (+7/-5)

### Commands

<details>
<summary><strong>itp</strong> (1 command)</summary>

- [ITP Setup](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/commands/setup.md) - updated (+13/-11)

</details>

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+2/-2)

## [9.24.5](https://github.com/terrylica/cc-skills/compare/v9.24.4...v9.24.5) (2026-01-12)

### Bug Fixes

- **statusline:** filter lychee path resolution errors from L: count ([d8b9597](https://github.com/terrylica/cc-skills/commit/d8b95978c0b06f5927dba320e1d9b4d0d15b660e))

---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [Git Account Validator Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/git-account-validator/README.md) - updated (+1/-1)

## Repository Documentation

### General Documentation

- [Hooks Development Guide](https://github.com/terrylica/cc-skills/blob/main/docs/HOOKS.md) - updated (+1/-1)

## [9.24.4](https://github.com/terrylica/cc-skills/compare/v9.24.3...v9.24.4) (2026-01-12)

---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+2/-2)

</details>

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+39/-22)
- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+1/-1)

### General Documentation

- [Documentation Guide](https://github.com/terrylica/cc-skills/blob/main/docs/CLAUDE.md) - updated (+15/-14)

## Other Documentation

### Other

- [Troubleshooting cc-skills Marketplace Installation](https://github.com/terrylica/cc-skills/blob/main/docs/troubleshooting/marketplace-installation.md) - updated (+3/-3)
- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (+19/-13)
- [Getting Started with Ralph (First-Time Users)](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/GETTING-STARTED.md) - updated (+1/-1)

## [9.24.3](https://github.com/terrylica/cc-skills/compare/v9.24.2...v9.24.3) (2026-01-12)

---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+27/-1)

</details>

## [9.24.2](https://github.com/terrylica/cc-skills/compare/v9.24.1...v9.24.2) (2026-01-12)

### Reverts

- remove PostToolUseError hook (not a valid Claude Code hook type) ([90cf728](https://github.com/terrylica/cc-skills/commit/90cf728337c460e0a20fd8f357e003588a3667b7))

## [9.24.1](https://github.com/terrylica/cc-skills/compare/v9.24.0...v9.24.1) (2026-01-12)

### Bug Fixes

- **scripts:** add PostToolUseError support to hook sync script ([6edbcc4](https://github.com/terrylica/cc-skills/commit/6edbcc4528965fa5bd2af12ed371ef11c03d9239))

# [9.24.0](https://github.com/terrylica/cc-skills/compare/v9.23.0...v9.24.0) (2026-01-12)

### Features

- **itp-hooks:** add PostToolUseError hook for UV reminder on failed pip commands ([7e1c96a](https://github.com/terrylica/cc-skills/commit/7e1c96aae045a37824f69f2a144a2f1b4b59f196))

# [9.23.0](https://github.com/terrylica/cc-skills/compare/v9.22.12...v9.23.0) (2026-01-12)

### Features

- **itp-hooks:** enhance silent-failure-detector with new patterns and BATS tests ([fe17220](https://github.com/terrylica/cc-skills/commit/fe172203f4aed6a87104099acbf22626f3bd1449))

## [9.22.12](https://github.com/terrylica/cc-skills/compare/v9.22.11...v9.22.12) (2026-01-12)

### Bug Fixes

- disable all git-account-validator hooks (mise handles auth) ([6028dcb](https://github.com/terrylica/cc-skills/commit/6028dcb81aeb5e0742de3e7798a198286681842e))
- **git-account-validator:** fix false positives on quoted gh strings ([b66d608](https://github.com/terrylica/cc-skills/commit/b66d608fd644ebb9ce93dbb629ba9017d3630e28))
- **git-account-validator:** fix word-splitting bug in command detection ([295857c](https://github.com/terrylica/cc-skills/commit/295857cdcf4d18804dbea7a9bf5181294aa2d999))
- **link-tools:** add configurable exclusion patterns for path policy linter ([8196df9](https://github.com/terrylica/cc-skills/commit/8196df9a00f4a7d6bc8390ac66d7222304f7f311)), closes [#8](https://github.com/terrylica/cc-skills/issues/8)
- remove validate-gh-isolation hook (caused process storms) ([7d6b050](https://github.com/terrylica/cc-skills/commit/7d6b050173b51177cdb80f15cc06e7e717e10a04)), closes [validate-#isolation](https://github.com/validate-/issues/isolation)

---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [Git Account Validator Plugin](https://github.com/terrylica/cc-skills/blob/main/plugins/git-account-validator/README.md) - updated (+105/-219)

## Repository Documentation

### General Documentation

- [Hooks Development Guide](https://github.com/terrylica/cc-skills/blob/main/docs/HOOKS.md) - updated (+41/-23)

## [9.22.11](https://github.com/terrylica/cc-skills/compare/v9.22.10...v9.22.11) (2026-01-12)

### Bug Fixes

- **docs:** fix 4 broken links detected by lychee ([9deb864](https://github.com/terrylica/cc-skills/commit/9deb864bec12a0d1decefca21d8c20b4bb313ba1))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status      | ADR                                                                                                                        | Change          |
| ----------- | -------------------------------------------------------------------------------------------------------------------------- | --------------- |
| implemented | [UV Reminder Hook for Pip Usage](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-10-uv-reminder-hook.md) | updated (+1/-1) |

## Plugin Documentation

### Skill References

<details>
<summary><strong>itp/semantic-release</strong> (1 file)</summary>

- [Version Alignment Standards](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/version-alignment.md) - updated (+1/-1)

</details>

## Other Documentation

### Other

- [Ralph Explore Agent Prompts - Real Examples](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/docs/EXPLORE-EXAMPLES.md) - updated (+1/-1)
- [Ralph Explore Agents - Complete Documentation Index](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/docs/EXPLORE-INDEX.md) - updated (+10/-10)

## [9.22.10](https://github.com/terrylica/cc-skills/compare/v9.22.9...v9.22.10) (2026-01-12)

### Bug Fixes

- **gh-tools:** use correct PreToolUse output format for gh-issue-body-file-guard ([1daa63a](https://github.com/terrylica/cc-skills/commit/1daa63a64f7e76877ef500d1757f6683e8b18fd2)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools) [#issue-body-file-guard](https://github.com/terrylica/cc-skills/issues/issue-body-file-guard)

## [9.22.9](https://github.com/terrylica/cc-skills/compare/v9.22.8...v9.22.9) (2026-01-12)

### Bug Fixes

- **itp-hooks:** exclude outputs/ directory from version-guard (was only output/) ([90f3ec5](https://github.com/terrylica/cc-skills/commit/90f3ec5797aa41e2b8e2d4e002fe45f9ac355f34))

## [9.22.8](https://github.com/terrylica/cc-skills/compare/v9.22.7...v9.22.8) (2026-01-12)

### Bug Fixes

- **dotfiles-tools:** ignore mode-only changes in chezmoi-stop-guard ([2a3c90d](https://github.com/terrylica/cc-skills/commit/2a3c90d91eb893a3ee57b046dcec2e26c9d749e4))

## [9.22.7](https://github.com/terrylica/cc-skills/compare/v9.22.6...v9.22.7) (2026-01-12)

### Bug Fixes

- **link-tools:** use mise shims path for uv in Stop hook ([6c7bd7b](https://github.com/terrylica/cc-skills/commit/6c7bd7bd98a4d32d60d4a984d166f5663e089832))

## [9.22.6](https://github.com/terrylica/cc-skills/compare/v9.22.5...v9.22.6) (2026-01-12)

### Bug Fixes

- **gh-isolation:** pattern match gh CLI command not path ([1f1d208](https://github.com/terrylica/cc-skills/commit/1f1d208a53d808c98c5331b288d569f52e6ae447)), closes [#isolation](https://github.com/terrylica/cc-skills/issues/isolation)

## [9.22.5](https://github.com/terrylica/cc-skills/compare/v9.22.4...v9.22.5) (2026-01-12)

### Bug Fixes

- **hooks:** prevent Stop hook infinite loop and clarify gh-isolation scope ([f316190](https://github.com/terrylica/cc-skills/commit/f3161905e853a326e010bda0511606881b17c4b9)), closes [#isolation](https://github.com/terrylica/cc-skills/issues/isolation)

## [9.22.4](https://github.com/terrylica/cc-skills/compare/v9.22.3...v9.22.4) (2026-01-12)

### Bug Fixes

- **git-account-validator:** read hook input from stdin JSON instead of env var ([5609cef](https://github.com/terrylica/cc-skills/commit/5609cef04703b1584f6a3dd8766a46187dd20044))

---

## Documentation Changes

## Plugin Documentation

### Skill References

<details>
<summary><strong>itp-hooks/hooks-development</strong> (1 file)</summary>

- [❌ WRONG - Claude sees NOTHING](https://github.com/terrylica/cc-skills/blob/main/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) - updated (+100)

</details>

## [9.22.3](https://github.com/terrylica/cc-skills/compare/v9.22.2...v9.22.3) (2026-01-11)

### Bug Fixes

- correct CLAUDE.md alignment with codebase ([118a1ad](https://github.com/terrylica/cc-skills/commit/118a1add4c867e37f85496911dccbd1738fa7ab9))

---

## Documentation Changes

## Repository Documentation

### General Documentation

- [Hooks Development Guide](https://github.com/terrylica/cc-skills/blob/main/docs/HOOKS.md) - updated (+1/-1)

## Other Documentation

### Other

- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - updated (+1/-1)

## [9.22.2](https://github.com/terrylica/cc-skills/compare/v9.22.1...v9.22.2) (2026-01-11)

---

## Documentation Changes

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+49/-155)

### General Documentation

- [Documentation Guide](https://github.com/terrylica/cc-skills/blob/main/docs/CLAUDE.md) - new (+57)
- [Hooks Development Guide](https://github.com/terrylica/cc-skills/blob/main/docs/HOOKS.md) - new (+137)
- [Release Workflow Guide](https://github.com/terrylica/cc-skills/blob/main/docs/RELEASE.md) - new (+122)

## Other Documentation

### Other

- [Plugin Development Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/CLAUDE.md) - new (+102)

## [9.22.1](https://github.com/terrylica/cc-skills/compare/v9.22.0...v9.22.1) (2026-01-11)

### Bug Fixes

- **release:** remove unused BASH_SOURCE line that broke Lodash template ([b3a274b](https://github.com/terrylica/cc-skills/commit/b3a274b5ea4eec4b97d17d59135eddfd2f078589))

# [9.22.0](https://github.com/terrylica/cc-skills/compare/v9.21.0...v9.22.0) (2026-01-11)

### Features

- **release:** add mise-controlled 4-phase release workflow ([5e69323](https://github.com/terrylica/cc-skills/commit/5e6932355349394b9191d7f8b88c083459358321)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools)

# [9.21.0](https://github.com/terrylica/cc-skills/compare/v9.20.5...v9.21.0) (2026-01-11)

### Features

- **gh-tools:** add gh-issue-body-file-guard hook (Issue [#5](https://github.com/terrylica/cc-skills/issues/5)) ([7d440fc](https://github.com/terrylica/cc-skills/commit/7d440fc225590029deacd20f72753b31a3c4758d)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools) [#issue-body-file-guard](https://github.com/terrylica/cc-skills/issues/issue-body-file-guard)

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status  | ADR                                                                                                                                         | Change    |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| unknown | [gh issue create --body-file Requirement](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-11-gh-issue-body-file-guard.md) | new (+68) |

## [9.20.5](https://github.com/terrylica/cc-skills/compare/v9.20.4...v9.20.5) (2026-01-11)

### Bug Fixes

- **git-account-validator:** add account confirmation with detected usernames ([90b2dcf](https://github.com/terrylica/cc-skills/commit/90b2dcf00b5a2f9d2b81ede3cc69a1515db3f307))

## [9.20.4](https://github.com/terrylica/cc-skills/compare/v9.20.3...v9.20.4) (2026-01-11)

### Bug Fixes

- **git-account-validator:** explicit AskUserQuestion tool call with JSON params ([e18052a](https://github.com/terrylica/cc-skills/commit/e18052a9ae5b1a1118d9abe919c0d0efde0d746d))

## [9.20.3](https://github.com/terrylica/cc-skills/compare/v9.20.2...v9.20.3) (2026-01-11)

### Bug Fixes

- **git-account-validator:** instruct Claude to use AskUserQuestion for remediation ([d8d1cc0](https://github.com/terrylica/cc-skills/commit/d8d1cc096ad9b9bc7b5e76d198296bb89fa968c7))

## [9.20.2](https://github.com/terrylica/cc-skills/compare/v9.20.1...v9.20.2) (2026-01-11)

### Bug Fixes

- **git-account-validator:** improve deny messages with actionable guidance for Claude ([850e6c7](https://github.com/terrylica/cc-skills/commit/850e6c7dcbcd2dce972bba69201c7866f183bd92))

## [9.20.1](https://github.com/terrylica/cc-skills/compare/v9.20.0...v9.20.1) (2026-01-11)

### Bug Fixes

- **git-account-validator:** remove self-healing that bypassed account isolation ([b27cd32](https://github.com/terrylica/cc-skills/commit/b27cd32867e97d9f60c9bafd1ce9bb6cae44982e))

---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/SKILL.md) - updated (+74/-553)

</details>

### Skill References

<details>
<summary><strong>itp/semantic-release</strong> (11 files)</summary>

- [2025 Updates](https://github.com/terrylica/cc-skills/blob/v9.20.0/plugins/itp/skills/semantic-release/references/2025-updates.md) - deleted
- [Authentication for semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/authentication.md) - updated (+6/-119)
- [Evolution Log](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/evolution-log.md) - new (+71)
- [Local Release Workflow (Canonical)](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/local-release-workflow.md) - updated (+6/-189)
- [MAJOR Version Breaking Change Confirmation](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/major-confirmation.md) - new (+237)
- [Pypi Publishing With Doppler](https://github.com/terrylica/cc-skills/blob/v9.20.0/plugins/itp/skills/semantic-release/references/pypi-publishing-with-doppler.md) - deleted
- [Python Projects Guide](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/python.md) - renamed from `plugins/itp/skills/semantic-release/references/python-projects-nodejs-semantic-release.md`
- [Resources](https://github.com/terrylica/cc-skills/blob/v9.20.0/plugins/itp/skills/semantic-release/references/resources.md) - deleted
- [Rust Projects with release-plz](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/rust.md) - renamed from `plugins/itp/skills/semantic-release/references/rust-release-plz.md`
- [Troubleshooting](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/troubleshooting.md) - updated (+317/-24)
- [Workflow Patterns](https://github.com/terrylica/cc-skills/blob/v9.20.0/plugins/itp/skills/semantic-release/references/workflow-patterns.md) - deleted

</details>

# [9.20.0](https://github.com/terrylica/cc-skills/compare/v9.19.1...v9.20.0) (2026-01-10)

### Features

- **semantic-release:** add mise task detection as priority release method ([5a8b46b](https://github.com/terrylica/cc-skills/commit/5a8b46bebcae7b58354f12371c155bf372d781ae))

---

## Documentation Changes

## Plugin Documentation

### Skills

<details>
<summary><strong>itp</strong> (1 change)</summary>

- [semantic-release](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/SKILL.md) - updated (+78/-1)

</details>

### Skill References

<details>
<summary><strong>itp/semantic-release</strong> (1 file)</summary>

- [Local Release Workflow (Canonical)](https://github.com/terrylica/cc-skills/blob/main/plugins/itp/skills/semantic-release/references/local-release-workflow.md) - updated (+8/-1)

</details>

## [9.19.1](https://github.com/terrylica/cc-skills/compare/v9.19.0...v9.19.1) (2026-01-10)

### Bug Fixes

- **itp-hooks:** correct UV reminder exception for requirements.txt ([212fef7](https://github.com/terrylica/cc-skills/commit/212fef79aad67a2e16fda8617e8af4b6442c5119))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status      | ADR                                                                                                                        | Change          |
| ----------- | -------------------------------------------------------------------------------------------------------------------------- | --------------- |
| implemented | [UV Reminder Hook for Pip Usage](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-10-uv-reminder-hook.md) | updated (+3/-1) |

# [9.19.0](https://github.com/terrylica/cc-skills/compare/v9.18.2...v9.19.0) (2026-01-10)

### Features

- **itp-hooks:** add UV reminder for pip usage ([6f16580](https://github.com/terrylica/cc-skills/commit/6f1658079b7138600866b996d5411451b80233f1))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status      | ADR                                                                                                                        | Change     |
| ----------- | -------------------------------------------------------------------------------------------------------------------------- | ---------- |
| implemented | [UV Reminder Hook for Pip Usage](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-10-uv-reminder-hook.md) | new (+122) |

## [9.18.2](https://github.com/terrylica/cc-skills/compare/v9.18.1...v9.18.2) (2026-01-10)

## [9.18.1](https://github.com/terrylica/cc-skills/compare/v9.18.0...v9.18.1) (2026-01-10)

### Bug Fixes

- **git-account-validator:** use correct PreToolUse JSON output format ([1538806](https://github.com/terrylica/cc-skills/commit/15388066005e247e70c510bc7497664ae1c32f31))
- **git-account-validator:** validate active gh account matches GH_ACCOUNT ([6c2f347](https://github.com/terrylica/cc-skills/commit/6c2f347d12e9f43a7604d24c297149d60938336d)), closes [#4](https://github.com/terrylica/cc-skills/issues/4)

# [9.18.0](https://github.com/terrylica/cc-skills/compare/v9.17.1...v9.18.0) (2026-01-10)

### Features

- **statusline-tools:** add asciinema cast file reference to statusline ([d8b71a4](https://github.com/terrylica/cc-skills/commit/d8b71a422fbd336156fdc4999cfadc557a81940b))

## [9.17.1](https://github.com/terrylica/cc-skills/compare/v9.17.0...v9.17.1) (2026-01-10)

# [9.17.0](https://github.com/terrylica/cc-skills/compare/v9.16.0...v9.17.0) (2026-01-10)

### Features

- **statusline-tools:** add session UUID chain display with lineage tracing ([871372e](https://github.com/terrylica/cc-skills/commit/871372ec54e10111ed1897636e04423b286dfdb1))

# [9.16.0](https://github.com/terrylica/cc-skills/compare/v9.15.0...v9.16.0) (2026-01-10)

### Features

- **itp-hooks:** add universal version SSoT guard ([76feea6](https://github.com/terrylica/cc-skills/commit/76feea65e1eef827bece446852d281ede5ecd803))

# [9.15.0](https://github.com/terrylica/cc-skills/compare/v9.14.0...v9.15.0) (2026-01-08)

### Bug Fixes

- **semantic-release:** avoid shell history expansion in verifyConditionsCmd ([1178c9f](https://github.com/terrylica/cc-skills/commit/1178c9fff69896240ee1b43f02790eebc19e100e))
- **semantic-release:** prevent release workflow hiccups ([cc6296f](https://github.com/terrylica/cc-skills/commit/cc6296f01cb34e6416784191b639b5f8dcec599b))

### Features

- **ralph:** add activation-gated bash wrappers for hooks ([c92bbdb](https://github.com/terrylica/cc-skills/commit/c92bbdb8a179dd9d15257fa090058dfd35d4ca86))
- **semantic-release:** add mise env loading to preflight verifyConditions ([36a90f7](https://github.com/terrylica/cc-skills/commit/36a90f73969880e8bd6ef3203e720706417a99a1))

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

- **statusline-tools:** add session UUID as third line in status output ([01e3846](https://github.com/terrylica/cc-skills/commit/01e38467f5484ee7e7a6197a2601d91e162c71d2))

---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [statusline-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/README.md) - updated (+17/-1)

# [9.13.0](https://github.com/terrylica/cc-skills/compare/v9.12.1...v9.13.0) (2026-01-05)

### Features

- **semantic-release:** add gh CLI workflow scope validation to preflight ([ecee9dd](https://github.com/terrylica/cc-skills/commit/ecee9ddff34e2576197fa922c7af8446fc99b99e))

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

- **session-chronicle:** update 1Password credentials to Claude Automation vault ([87f0cd7](https://github.com/terrylica/cc-skills/commit/87f0cd7920d13f9dea7352e4a439126388a02f44))

### Features

- **itp:** add standalone /itp:release command ([88a4357](https://github.com/terrylica/cc-skills/commit/88a4357d3ac1527ba3dbf57c08ee63eb0c21653f))
- **itp:** wire /itp:release command to semantic-release skill ([f6f0797](https://github.com/terrylica/cc-skills/commit/f6f07979bec1099b421013026178504b3d597640))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status   | ADR                                                                                                                                           | Change          |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------------- | --------------- |
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

- **session-chronicle:** migrate S3 bucket and credentials to company account ([23d480a](https://github.com/terrylica/cc-skills/commit/23d480ad3ba783def375c75869bfc167c81d637c))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status   | ADR                                                                                                                                           | Change        |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ------------- |
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

- **semantic-release:** use correct -q flag for git update-index ([05c8e58](https://github.com/terrylica/cc-skills/commit/05c8e58326b269599da36e047341738c36bff853))

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

- **semantic-release:** add git cache clearing to preflight ([00ef67f](https://github.com/terrylica/cc-skills/commit/00ef67fbc07c231d1a292e66459ee6ad5925f21c))

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

- **gh-tools:** add WebFetch enforcement hook for GitHub CLI preference ([9ea4427](https://github.com/terrylica/cc-skills/commit/9ea4427904c1edabd93ac97341382387ca266830)), closes [#tools](https://github.com/terrylica/cc-skills/issues/tools)

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status   | ADR                                                                                                                                           | Change          |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------------- | --------------- |
| accepted | [Session Chronicle S3 Artifact Sharing](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-02-session-chronicle-s3-sharing.md) | updated (+5/-5) |
| unknown  | [gh-tools WebFetch Enforcement Hook](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-03-gh-tools-webfetch-enforcement.md)   | new (+137)      |

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

- **docs:** regenerate diagrams using graph-easy skill properly ([0711f1c](https://github.com/terrylica/cc-skills/commit/0711f1cf70aa83603cb096d8b89e0578d8c615b0))

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

| Status   | ADR                                                                                                                                                                  | Change  |
| -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
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

- **session-chronicle:** use Claude Automation vault for AWS credentials ([01f527f](https://github.com/terrylica/cc-skills/commit/01f527fd94886c4faad132438329414b384e91e4))

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

- **session-chronicle:** support 1Password biometric desktop app integration ([e37db06](https://github.com/terrylica/cc-skills/commit/e37db06d7d09a048d82080ade56eb04f0e02a5a5))

# [9.10.0](https://github.com/terrylica/cc-skills/compare/v9.9.3...v9.10.0) (2026-01-03)

### Bug Fixes

- **session-chronicle:** eliminate all silent failures in embedded scripts ([1e1bfd0](https://github.com/terrylica/cc-skills/commit/1e1bfd0d47d93038792a98a3857c9f99b3671905))

### Features

- **session-chronicle:** enforce complete session recording with AskUserQuestion flows ([bdaab73](https://github.com/terrylica/cc-skills/commit/bdaab73be0dad0d629226cc7d3fb350b8db84aba))

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

- **semantic-release:** simplify post-release verification, remove complex jq check ([a6e48c9](https://github.com/terrylica/cc-skills/commit/a6e48c9a03135e47f7bae8acdbe6b913b5b51dd5))

## [9.9.2](https://github.com/terrylica/cc-skills/compare/v9.9.1...v9.9.2) (2026-01-03)

### Bug Fixes

- **semantic-release:** fix jq quoting issue in installed_plugins.json check ([ef83d9c](https://github.com/terrylica/cc-skills/commit/ef83d9ce6e5cf649a57413ae82f5b174ab41deef))

## [9.9.1](https://github.com/terrylica/cc-skills/compare/v9.9.0...v9.9.1) (2026-01-03)

### Bug Fixes

- **semantic-release:** make post-release plugin verification fully automated ([d92e542](https://github.com/terrylica/cc-skills/commit/d92e542690a6aed3db026de06e6c08957329cb8b))

# [9.9.0](https://github.com/terrylica/cc-skills/compare/v9.8.1...v9.9.0) (2026-01-03)

### Features

- **semantic-release:** add post-release plugin cache verification ([2fd5893](https://github.com/terrylica/cc-skills/commit/2fd5893fb6d60b32ce8a52791866ecfe7324d4ab))

## [9.8.1](https://github.com/terrylica/cc-skills/compare/v9.8.0...v9.8.1) (2026-01-03)

### Bug Fixes

- **ralph:** make /ralph:stop execute bash script instead of summarizing ([78860de](https://github.com/terrylica/cc-skills/commit/78860dec665ddaa635f34f220fda0fe4fec06fe4))

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

- **ralph:** simplify global stop signal handling for cross-session reliability ([07212be](https://github.com/terrylica/cc-skills/commit/07212bed087599f81cc3ad054b2abfff959e9f90))

### Features

- **semantic-release:** add MAJOR version confirmation with multi-perspective analysis ([0d660f8](https://github.com/terrylica/cc-skills/commit/0d660f842acdfa10ae35a3f96f2805157f3d1915))

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

- **ralph:** add --remove flag to /ralph:encourage and /ralph:forbid ([57f1180](https://github.com/terrylica/cc-skills/commit/57f118070356f362c3316e0815dc6191e532b182))
- **session-chronicle:** add S3 artifact sharing with Brotli compression ([34f0082](https://github.com/terrylica/cc-skills/commit/34f0082fd602e186541df385b55bc2e5b5de71d7))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status   | ADR                                                                                                                                              | Change           |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------- |
| accepted | [Ralph Guidance Freshness Detection](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-02-ralph-guidance-freshness-detection.md) | updated (+27/-1) |
| accepted | [Session Chronicle S3 Artifact Sharing](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2026-01-02-session-chronicle-s3-sharing.md)    | new (+260)       |

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

- **ralph:** handle cross-session race condition in /ralph:stop ([9ad8190](https://github.com/terrylica/cc-skills/commit/9ad81905a9da2e8d58a8f0853e20254c190cc216))

## [9.6.4](https://github.com/terrylica/cc-skills/compare/v9.6.3...v9.6.4) (2026-01-02)

### Bug Fixes

- **ralph:** add guidance freshness detection with on-the-fly constraint scanning ([3a4bda7](https://github.com/terrylica/cc-skills/commit/3a4bda7f3e15f546a484b81e7421da8a3b220b4d))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status   | ADR                                                                                                                                              | Change     |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- |
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

- **ralph:** add proper YAML frontmatter and Skill tool invocation ([29a1530](https://github.com/terrylica/cc-skills/commit/29a15308f074b6f3f7f9a768acc77e88fb9a6f61))

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

- **session-chronicle:** extract FULL session chains, not fixed windows ([0599d35](https://github.com/terrylica/cc-skills/commit/0599d359e2e858adac7a17c12ba05e91bb405f54))

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

- **devops-tools:** add session-chronicle skill for session archaeology ([56fb64f](https://github.com/terrylica/cc-skills/commit/56fb64fedfd5001b08c99bf567a930412a3465d7))
- **ralph:** add unlimited @ link following to Explore agents ([7128e44](https://github.com/terrylica/cc-skills/commit/7128e4438df82e9b0411c75b3e037d868975b7d1))

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

- **ralph:** add blocking gate for agent results and deep-dive prompts ([ff354ea](https://github.com/terrylica/cc-skills/commit/ff354ea48e31ecc8c15d8c71479742191099c759))

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

- **ralph:** make Step 1.4.5 Explore agents MANDATORY with explicit Task syntax ([60303fe](https://github.com/terrylica/cc-skills/commit/60303febcee19fa83804c82c716e60a65d51721a))

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

- **ralph:** add Explore-based constraint discovery to /ralph:start ([2274f96](https://github.com/terrylica/cc-skills/commit/2274f96642ccf462d0aa6a506cbd2ce70ece9933))

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

- **ralph:** wire constraint scan results to AskUserQuestion flows ([da8e1c9](https://github.com/terrylica/cc-skills/commit/da8e1c9591d5063384ba6ad8ffff91c091b5f1a6))

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

- **ralph:** batch gitignore check using --stdin for performance ([d076dfb](https://github.com/terrylica/cc-skills/commit/d076dfb2adc4a13500bb1572cd1d06a8d3174b0f))

## [9.4.5](https://github.com/terrylica/cc-skills/compare/v9.4.4...v9.4.5) (2025-12-31)

### Bug Fixes

- **ralph:** suppress uv DEBUG output in constraint scanner ([2de7201](https://github.com/terrylica/cc-skills/commit/2de72014caabb1b33f8f7425686b2923935c3dc1))

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

- **ralph:** robust uv discovery for mise-installed environments ([a969fe6](https://github.com/terrylica/cc-skills/commit/a969fe6d624abbdd8096c6e74d85d20538faeea5))

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

| Status  | ADR                                                                                                                                          | Change           |
| ------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| unknown | [asciinema-tools Daemon Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-26-asciinema-daemon-architecture.md) | updated (+15/-4) |

## Plugin Documentation

### Skill References

<details>
<summary><strong>asciinema-tools/asciinema-streaming-backup</strong> (1 file)</summary>

- [Idle Chunker Script (DEPRECATED)](https://github.com/terrylica/cc-skills/blob/main/plugins/asciinema-tools/skills/asciinema-streaming-backup/references/idle-chunker.md) - updated (+10/-3)

</details>

## [9.4.2](https://github.com/terrylica/cc-skills/compare/v9.4.1...v9.4.2) (2025-12-31)

### Bug Fixes

- emit errors to stderr and fix shellcheck warnings ([315806a](https://github.com/terrylica/cc-skills/commit/315806a2c794d1d210dca4a11233f05ae6c0c1cd))

## [9.4.1](https://github.com/terrylica/cc-skills/compare/v9.4.0...v9.4.1) (2025-12-31)

### Bug Fixes

- **asciinema-tools:** improve daemon-setup robustness and remove leaked data ([0b2e2cf](https://github.com/terrylica/cc-skills/commit/0b2e2cf680b3e083b89bc874dc31ef10f8a0354f))
- **iterm2-layout:** generalize worktree examples in documentation ([d070f32](https://github.com/terrylica/cc-skills/commit/d070f32811525b5d0656540bed0a7cd7093336ee))

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

- **asciinema-tools:** add finalize and summarize commands for complete post-session workflow ([79b4101](https://github.com/terrylica/cc-skills/commit/79b41019ef7a06edec9bfb6ca47b5d496146ae4b))

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

- **ralph:** add UV detection with loud validation failure ([a3f18d0](https://github.com/terrylica/cc-skills/commit/a3f18d0a9331fe6ffce84b09b5de5f3c48869a8e))

## [9.3.5](https://github.com/terrylica/cc-skills/compare/v9.3.4...v9.3.5) (2025-12-30)

### Bug Fixes

- **ralph:** expand hook install descriptions ([ef134fc](https://github.com/terrylica/cc-skills/commit/ef134fc313f9eb18b8cbd13e7a0aded2229e668b))

## [9.3.4](https://github.com/terrylica/cc-skills/compare/v9.3.3...v9.3.4) (2025-12-30)

### Bug Fixes

- **ralph:** remove RSSI branding throughout codebase ([cee1bc8](https://github.com/terrylica/cc-skills/commit/cee1bc8af6b089c500a1875e3de49a9fdb02655b))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status   | ADR                                                                                                                                                | Change            |
| -------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
| accepted | [Ralph Eternal Loop Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-20-ralph-rssi-eternal-loop.md)                 | updated (+33/-33) |
| unknown  | [Ralph Stop Visibility Observability](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-22-ralph-stop-visibility-observability.md) | updated (+2/-2)   |
| unknown  | [Ralph Constraint Scanning](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-29-ralph-constraint-scanning.md)                     | updated (+1/-1)   |

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

| Status   | ADR                                                                                                                                     | Change  |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| accepted | [Ralph RSSI Eternal Loop Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-20-ralph-rssi-eternal-loop.md) | coupled |

### Design Specs

- [Design Spec: Ralph RSSI Eternal Loop Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-20-ralph-rssi-eternal-loop/spec.md) - updated (+42/-39)

## [9.3.2](https://github.com/terrylica/cc-skills/compare/v9.3.1...v9.3.2) (2025-12-30)

### Bug Fixes

- **ralph:** update test imports for RSSI → Ralph rename ([071fc02](https://github.com/terrylica/cc-skills/commit/071fc020e0dd6fdf9fd6802be5162be2d16bd190))

## [9.3.1](https://github.com/terrylica/cc-skills/compare/v9.3.0...v9.3.1) (2025-12-30)

### Bug Fixes

- **ralph:** correct version numbers in MENTAL-MODEL.md (v9.2.4 → v9.3.0) ([c366b7a](https://github.com/terrylica/cc-skills/commit/c366b7a282b3db924fdd2d93b65d7b2f5e60a482))

### Code Refactoring

- **ralph:** rename RSSI modules to Ralph naming convention ([17cab6e](https://github.com/terrylica/cc-skills/commit/17cab6e5f6b09301490cb399871eb9194ddf3400))

### BREAKING CHANGES

- **ralph:** Users with existing state files should run
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

- **ralph:** add dual-channel observability for hook operations ([52b717e](https://github.com/terrylica/cc-skills/commit/52b717e94c61ca49a31974d593173b0c4f771a0e))

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

- **ralph:** enhance MENTAL-MODEL.md with layman-friendly diagrams ([ff5d082](https://github.com/terrylica/cc-skills/commit/ff5d08233d7512a2fc078b70e4c9c4b5496cfd14))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status   | ADR                                                                                                                                                   | Change            |
| -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
| accepted | [Alpha-Forge Git Worktree Management System](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-14-alpha-forge-worktree-management.md) | updated (+57/-40) |
| accepted | [Ralph RSSI Eternal Loop Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-20-ralph-rssi-eternal-loop.md)               | updated (+3/-1)   |

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

- **ralph:** install Bash PreToolUse hook for loop file protection ([54d61f1](https://github.com/terrylica/cc-skills/commit/54d61f1d8de46bf9e55ae1a01689121e72b4aeab))

## [9.2.1](https://github.com/terrylica/cc-skills/compare/v9.2.0...v9.2.1) (2025-12-30)

### Bug Fixes

- **ralph:** address adversarial audit findings for constraint scanner ([d7c5f5f](https://github.com/terrylica/cc-skills/commit/d7c5f5fd1ddd171c66f9c0147365a1bccc50f6b5))

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

- **statusline-tools:** move UTC time to line 2 with GitHub URL ([cc5dad9](https://github.com/terrylica/cc-skills/commit/cc5dad9878c1c9488e212a2a205887ce50aa5f1a))

### Features

- **ralph:** add constraint scanner with Pydantic v2 migration ([a340ef2](https://github.com/terrylica/cc-skills/commit/a340ef2cf16e01638b282ebd52f4c49a02808125))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status  | ADR                                                                                                                            | Change     |
| ------- | ------------------------------------------------------------------------------------------------------------------------------ | ---------- |
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

- **statusline-tools:** include date in local time display ([b92541b](https://github.com/terrylica/cc-skills/commit/b92541b0bd4a83c5a09af930facadf9ad33573e7))

# [9.1.0](https://github.com/terrylica/cc-skills/compare/v9.0.5...v9.1.0) (2025-12-30)

### Features

- **statusline-tools:** add local time after UTC in status line ([b551c01](https://github.com/terrylica/cc-skills/commit/b551c01a3ba6b78cb92c1ea820134b7a380a0dd5))

## [9.0.5](https://github.com/terrylica/cc-skills/compare/v9.0.4...v9.0.5) (2025-12-30)

### Bug Fixes

- **statusline-tools:** remove redundant branch display, fix worktree cache ([e649fa0](https://github.com/terrylica/cc-skills/commit/e649fa0d6874d4046e120bcf8e9a8e5df8c9d70d))

## [9.0.4](https://github.com/terrylica/cc-skills/compare/v9.0.3...v9.0.4) (2025-12-29)

### Bug Fixes

- **link-tools:** remove orphaned lib directory with dead code ([3dc3245](https://github.com/terrylica/cc-skills/commit/3dc3245294ba849c150996094abb8278dafbe22d))

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

- **plugin-dev:** add --project-local and --skip-bash flags to validate-skill ([79f37ce](https://github.com/terrylica/cc-skills/commit/79f37ce93220ac030914eba5fb1ce960a6b68df2))

## [9.0.1](https://github.com/terrylica/cc-skills/compare/v9.0.0...v9.0.1) (2025-12-29)

### Bug Fixes

- **statusline-tools:** exclude .claude/skills/ from lint-relative-paths ([8221474](https://github.com/terrylica/cc-skills/commit/822147479922f4d71f6f43838f715491fdd3b5d3))

# [9.0.0](https://github.com/terrylica/cc-skills/compare/v8.11.4...v9.0.0) (2025-12-29)

### Features

- **plugin-dev:** migrate skill validators from Python to Bun/TypeScript ([3b2623f](https://github.com/terrylica/cc-skills/commit/3b2623f34e91974ec6044432ea06e08654c762f9))

### BREAKING CHANGES

- **plugin-dev:** Python validators removed, use TypeScript equivalents

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

| Status  | ADR                                                                                                                                                  | Change          |
| ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | --------------- |
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

- **statusline-tools:** skip skill directories in lint-relative-paths ([4b7067f](https://github.com/terrylica/cc-skills/commit/4b7067f75e3e5cc199104d361567d4d34821fd39))

## [8.11.3](https://github.com/terrylica/cc-skills/compare/v8.11.2...v8.11.3) (2025-12-29)

### Bug Fixes

- **docs:** correct broken internal links detected by lychee ([33febcc](https://github.com/terrylica/cc-skills/commit/33febcc1144ec75f7a104e2540a9de2903ac76eb))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status   | ADR                                                                                                                                                  | Change          |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | --------------- |
| accepted | [Ralph RSSI Eternal Loop Architecture](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-20-ralph-rssi-eternal-loop.md)              | updated (-1)    |
| unknown  | [Skill Bash Compatibility Enforcement](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-22-skill-bash-compatibility-enforcement.md) | updated (+1/-1) |

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

- **ralph:** use full mise shims path for uv in stop hook ([02f47be](https://github.com/terrylica/cc-skills/commit/02f47be577c6c1a875d729f45c0795183b159288))

## [8.11.1](https://github.com/terrylica/cc-skills/compare/v8.11.0...v8.11.1) (2025-12-29)

### Bug Fixes

- **statusline-tools:** use --root-dir for lychee and document dependencies ([7ff56bf](https://github.com/terrylica/cc-skills/commit/7ff56bf697fde9080122922267680716417dc4ec))

---

## Documentation Changes

## Plugin Documentation

### Plugin READMEs

- [statusline-tools](https://github.com/terrylica/cc-skills/blob/main/plugins/statusline-tools/README.md) - updated (+41/-7)

# [8.11.0](https://github.com/terrylica/cc-skills/compare/v8.10.2...v8.11.0) (2025-12-29)

### Bug Fixes

- **statusline-tools:** add --base flag to lychee for root-relative paths ([ec6e238](https://github.com/terrylica/cc-skills/commit/ec6e23819c64e8f86445f504e8cbf406cd3dab96))
- **statusline-tools:** add skills to exclude_dirs in lint-relative-paths ([80f0171](https://github.com/terrylica/cc-skills/commit/80f0171e75910a683edd0c04ccdf09231cb7bb72))
- **statusline-tools:** respect .gitignore in link validators ([c967003](https://github.com/terrylica/cc-skills/commit/c967003cf81b5d6e64fee79403081a978c674986))

### Features

- **doc-tools:** add terminal-print skill for iTerm2 output printing ([e3430f0](https://github.com/terrylica/cc-skills/commit/e3430f0528757488b65dcfbe407e9e24879c16d8))
- **dotfiles-tools:** add Stop hook for chezmoi sync enforcement ([a480025](https://github.com/terrylica/cc-skills/commit/a4800252848bf2eea5323ed4502af4a8327daf08))

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

- **docs:** add fake-data-guard to command descriptions ([3e635f8](https://github.com/terrylica/cc-skills/commit/3e635f83cc29eacbfd1bf75d8e9652f003450cad))

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

- **itp-hooks:** update stale /itp-hooks:hooks reference to /itp:hooks ([2328fde](https://github.com/terrylica/cc-skills/commit/2328fde1a210241d07fef0de6667cd17d0559b36))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status      | ADR                                                                                                                                            | Change  |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
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

- **itp-hooks:** add fake data guard PreToolUse hook ([98a8eb1](https://github.com/terrylica/cc-skills/commit/98a8eb17a3ea6bfee30108bdcd6ae5d4c0e34775))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status      | ADR                                                                                                                                            | Change     |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| implemented | [Universal Fake Data Guard PreToolUse Hook](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-27-fake-data-guard-universal.md) | new (+172) |

## Plugin Documentation

### Commands

<details>
<summary><strong>itp-hooks</strong> (1 command)</summary>

- [hooks](https://github.com/terrylica/cc-skills/blob/v8.9.6/plugins/itp-hooks/commands/hooks.md) - deleted

</details>

## [8.9.6](https://github.com/terrylica/cc-skills/compare/v8.9.5...v8.9.6) (2025-12-28)

### Bug Fixes

- **git-account-validator:** respect SSH host aliases in remote URL ([70d3a3f](https://github.com/terrylica/cc-skills/commit/70d3a3faebcb6970623f0b8e270ad2ac32cf58c1))

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

- **ralph:** create STATE_DIR and CONFIG_DIR on import to prevent FileNotFoundError ([0152e1f](https://github.com/terrylica/cc-skills/commit/0152e1ffceb8480789ee955aea236b744052f048))

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

- **ralph:** address race conditions and argument handling issues ([ffc0853](https://github.com/terrylica/cc-skills/commit/ffc0853e856c69cf117d36bb2b1881d2b325c028))

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

- **itp:** use origin remote for browser URLs instead of gh repo view ([eef3882](https://github.com/terrylica/cc-skills/commit/eef38827a4bab194dfcea2897f97c2ae64527788))

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

- **statusline-tools:** add global ignore patterns for lint-relative-paths ([45e174b](https://github.com/terrylica/cc-skills/commit/45e174bfd42b483d0b23c6665ec1911171b31071))

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

- **validate:** add hooks.json schema validation to prevent "Invalid discriminator value" regressions ([108a325](https://github.com/terrylica/cc-skills/commit/108a3250ead526f1cd6b389bea09a1673f920e5b))

## [8.7.7](https://github.com/terrylica/cc-skills/compare/v8.7.6...v8.7.7) (2025-12-27)

### Bug Fixes

- **ralph:** correct PreToolUse hook JSON structure in manage-hooks.sh ([b4d626c](https://github.com/terrylica/cc-skills/commit/b4d626cb69bbed770a3aaf714af681c9d081b49a))

## [8.7.6](https://github.com/terrylica/cc-skills/compare/v8.7.5...v8.7.6) (2025-12-27)

### Bug Fixes

- **statusline-tools:** add archives and state to lint exclude dirs ([1ba2793](https://github.com/terrylica/cc-skills/commit/1ba2793b70e4b9286d742c041dab89e1497a1dfe))

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

| Status   | ADR                                                                                                                                     | Change  |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------- | ------- |
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

- **ralph:** web research trigger only in exploration mode, not implementation ([06742fb](https://github.com/terrylica/cc-skills/commit/06742fb36483839c9c0a28238690d44be79011d1))

---

## Documentation Changes

## Other Documentation

### Other

- [rssi-unified](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/rssi-unified.md) - updated (+4/-1)

## [8.7.2](https://github.com/terrylica/cc-skills/compare/v8.7.1...v8.7.2) (2025-12-27)

### Bug Fixes

- **ralph:** unify templates so encourage/forbid guidance applies to all phases ([6ba72d6](https://github.com/terrylica/cc-skills/commit/6ba72d6a0ed054df5464a0b4a4d90c27b1556986))

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

- **validate:** integrate AJV schema validation into validateMarketplaceEntries ([158292c](https://github.com/terrylica/cc-skills/commit/158292c3f458256b407119dcdab769a4475ec082))

# [8.7.0](https://github.com/terrylica/cc-skills/compare/v8.6.0...v8.7.0) (2025-12-26)

### Features

- **validate:** modernize with tinyglobby + AJV, adopt Bun runtime ([8980686](https://github.com/terrylica/cc-skills/commit/89806863484f841ecc5a66d8c6cab8908b77783d))

---

## Documentation Changes

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated (+16/-16)

# [8.6.0](https://github.com/terrylica/cc-skills/compare/v8.5.1...v8.6.0) (2025-12-26)

### Features

- **validate:** add hook pitfall detection for common bugs ([0fd1732](https://github.com/terrylica/cc-skills/commit/0fd1732831f91f977d0820842e1ebf53a96bc2d0))

## [8.5.1](https://github.com/terrylica/cc-skills/compare/v8.5.0...v8.5.1) (2025-12-26)

### Bug Fixes

- **itp-hooks:** skip ADR reminder if file already has ADR reference ([fba3267](https://github.com/terrylica/cc-skills/commit/fba326791559271ed28539ff31675a39887fcc66))

# [8.5.0](https://github.com/terrylica/cc-skills/compare/v8.4.3...v8.5.0) (2025-12-26)

### Features

- **ralph:** show guidance in /ralph:status ([112881a](https://github.com/terrylica/cc-skills/commit/112881a763c5e4f91f2f28525b0a9f465998b5da))

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

- **ralph:** preserve guidance across /ralph:start restarts ([62aa170](https://github.com/terrylica/cc-skills/commit/62aa1707de70fcf2f08d51cd4c932c1737a8d5a6))

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

- **ralph:** consolidate exploration templates into unified file ([445db85](https://github.com/terrylica/cc-skills/commit/445db851b04490ea8c44433acebcd44e9cc69993))

### BREAKING CHANGES

- **ralph:** alpha-forge-exploration.md removed, use exploration-mode.md with adapter_name="alpha-forge"

---

## Documentation Changes

## Other Documentation

### Other

- [alpha-forge-exploration](https://github.com/terrylica/cc-skills/blob/v8.4.1/plugins/ralph/hooks/templates/alpha-forge-exploration.md) - deleted
- [exploration-mode](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/exploration-mode.md) - updated (+348/-39)
- [implementation-mode](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/implementation-mode.md) - updated (-6)

## [8.4.1](https://github.com/terrylica/cc-skills/compare/v8.4.0...v8.4.1) (2025-12-26)

### Bug Fixes

- **ralph:** add RSSI protocol and data reminder to all templates ([2076bd8](https://github.com/terrylica/cc-skills/commit/2076bd85dd8fc6ae5e7b39c1b5d3cb46f32b35be))

---

## Documentation Changes

## Other Documentation

### Other

- [alpha-forge-exploration](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/alpha-forge-exploration.md) - updated (+4)
- [exploration-mode](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/exploration-mode.md) - updated (+6/-2)
- [implementation-mode](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/hooks/templates/implementation-mode.md) - updated (+6)

# [8.4.0](https://github.com/terrylica/cc-skills/compare/v8.3.0...v8.4.0) (2025-12-26)

### Features

- **ralph:** add RSSI branding and behavioral reminder to implementation mode ([ca4c7df](https://github.com/terrylica/cc-skills/commit/ca4c7dfde2b79ce91a40639e6ac4d0538585cf6c))

# [8.3.0](https://github.com/terrylica/cc-skills/compare/v8.2.1...v8.3.0) (2025-12-26)

### Features

- **validate:** add hook pitfall detection for common bugs ([c1807e5](https://github.com/terrylica/cc-skills/commit/c1807e5896c5c3a67153a9dd38f13c8fbff4589c))

## [8.2.1](https://github.com/terrylica/cc-skills/compare/v8.2.0...v8.2.1) (2025-12-26)

### Bug Fixes

- **hooks:** fix PostToolUse blocking errors for relative paths and ruff success ([69fd2c6](https://github.com/terrylica/cc-skills/commit/69fd2c638fecb17ef70dffde67629f2be6bf909f))

# [8.2.0](https://github.com/terrylica/cc-skills/compare/v8.1.11...v8.2.0) (2025-12-26)

### Features

- **asciinema-tools:** add launchd daemon architecture for background chunking ([d5657d3](https://github.com/terrylica/cc-skills/commit/d5657d3dfd1de6c2a28d61c75e0e7d41bfa7bb6a))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status  | ADR                                                                                                                                          | Change     |
| ------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
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

- **ralph:** add git remote detection for sparse checkouts/branches ([474246c](https://github.com/terrylica/cc-skills/commit/474246ca95b8ce3f690a2fd11842229b4628c6be))

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

- **statusline-tools:** add stop_hook_active check to prevent infinite loop ([a22774b](https://github.com/terrylica/cc-skills/commit/a22774be3410f6d481866a6986b9d679a377b526))
- **statusline-tools:** use decision:block so Claude sees violations ([7ffbee3](https://github.com/terrylica/cc-skills/commit/7ffbee3ee6244719c14a849e973b02addc4db58c))

## [8.1.7](https://github.com/terrylica/cc-skills/compare/v8.1.6...v8.1.7) (2025-12-26)

### Bug Fixes

- **statusline-tools:** include actual violation details in Stop hook ([b9b61b2](https://github.com/terrylica/cc-skills/commit/b9b61b245bedf95cd1dfa13892ed746269b84568))

## [8.1.6](https://github.com/terrylica/cc-skills/compare/v8.1.5...v8.1.6) (2025-12-26)

### Bug Fixes

- **ralph:** move and update alpha-forge validation meta-prompt ([64c468b](https://github.com/terrylica/cc-skills/commit/64c468bf820d14ce35f23482f5a4f0b7ed6d8273))

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

- **validate:** correct Stop hook output format recommendation ([a8bab52](https://github.com/terrylica/cc-skills/commit/a8bab527cded5141d438228952f725741e87ea12))

## [8.1.3](https://github.com/terrylica/cc-skills/compare/v8.1.2...v8.1.3) (2025-12-26)

### Bug Fixes

- **statusline-tools:** use systemMessage for Stop hook output ([1a92495](https://github.com/terrylica/cc-skills/commit/1a924953eeac1817348a6a53965fcb4460900f2a))

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

- **hooks:** add silent failure detection and fix deprecated output patterns ([9d98b0c](https://github.com/terrylica/cc-skills/commit/9d98b0c4e75857e33df7b2c917500a8cd7219536))

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

- **ralph:** add git worktree detection to alpha-forge guard ([380ff16](https://github.com/terrylica/cc-skills/commit/380ff16f841187c260ba37d3432a6036aea1e90a))

## [8.0.2](https://github.com/terrylica/cc-skills/compare/v8.0.1...v8.0.2) (2025-12-26)

### Bug Fixes

- **ralph:** add alpha-forge only guard to all hooks ([cbb8f99](https://github.com/terrylica/cc-skills/commit/cbb8f99a18c26b8e145810d6c3716e684e4d9cfa))

## [8.0.1](https://github.com/terrylica/cc-skills/compare/v8.0.0...v8.0.1) (2025-12-26)

### Bug Fixes

- **marketplace:** remove unsupported 'requires' field causing schema errors ([1efa729](https://github.com/terrylica/cc-skills/commit/1efa729d9d6b2fd46b894c2fe0c77ba72d56b217)), closes [#9444](https://github.com/terrylica/cc-skills/issues/9444)

---

## Documentation Changes

## Repository Documentation

### Root Documentation

- [cc-skills](https://github.com/terrylica/cc-skills/blob/main/README.md) - updated (+19)

# [8.0.0](https://github.com/terrylica/cc-skills/compare/v7.19.7...v8.0.0) (2025-12-26)

### Features

- **plugins:** consolidate 7 plugins into 4 merged plugins with dependency tracking ([8d6096d](https://github.com/terrylica/cc-skills/commit/8d6096dc54695aecd5967064afb449a58ad83f5e))

### BREAKING CHANGES

- **plugins:** Plugin names changed - update your /plugin install commands

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

Reference: <https://github.com/anthropics/claude-code/issues/9444>

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
- [Document Title ← Makes this Section 1](https://github.com/terrylica/cc-skills/blob/main/plugins/doc-tools/skills/pandoc-pdf-generation/references/yaml-structure.md) - renamed from `plugins/doc-build-tools/skills/pandoc-pdf-generation/references/yaml-structure.md`

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

- **ralph:** add verbose error handling to archive-plan.sh ([b0bb0e1](https://github.com/terrylica/cc-skills/commit/b0bb0e1de97574c2edf5c52e816905915dd9f75c))

## [7.19.6](https://github.com/terrylica/cc-skills/compare/v7.19.5...v7.19.6) (2025-12-26)

### Bug Fixes

- **ralph:** eliminate all silent failures in manage-hooks.sh ([33a782a](https://github.com/terrylica/cc-skills/commit/33a782aa53486e17a3860f126d0b9d6d26bcc38d))

## [7.19.5](https://github.com/terrylica/cc-skills/compare/v7.19.4...v7.19.5) (2025-12-26)

### Bug Fixes

- **ralph:** clean up timestamp and cache files on uninstall ([e7b649f](https://github.com/terrylica/cc-skills/commit/e7b649fae2180d736abf911fbd50863efb053641))

## [7.19.4](https://github.com/terrylica/cc-skills/compare/v7.19.3...v7.19.4) (2025-12-26)

### Bug Fixes

- **ralph:** add missing pretooluse-loop-guard.py to preflight check ([9e7a52f](https://github.com/terrylica/cc-skills/commit/9e7a52f0a4e3dffa19cbd8a9de44448d3416fe10))

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

- **ralph:** correct MENTAL-MODEL.md paths and clarify Alpha-Forge convergence ([41780ac](https://github.com/terrylica/cc-skills/commit/41780ac9066d09dcf7b43541792fa6d4a3356c63))

---

## Documentation Changes

## Other Documentation

### Other

- [Ralph Mental Model for Alpha-Forge](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/MENTAL-MODEL.md) - updated (+7/-4)

## [7.19.2](https://github.com/terrylica/cc-skills/compare/v7.19.1...v7.19.2) (2025-12-26)

### Bug Fixes

- **ralph:** add documentation links to /ralph:hooks status output ([063e06f](https://github.com/terrylica/cc-skills/commit/063e06ff0f94dfd49ea95faf32e6cb7928fe6b8f))

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

- **skill:** recommend ASCII for GitHub, boxart for terminal only ([1a6389b](https://github.com/terrylica/cc-skills/commit/1a6389b794ab61789ea76485c8d4adcadda3b01c))

### Features

- **ralph:** comprehensive installation integrity with restart detection ([842fe4c](https://github.com/terrylica/cc-skills/commit/842fe4cf593183345fd35a5febb14b3faaa540c3))

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

- **semantic-release:** improve deleted file handling in release notes ([e18ca62](https://github.com/terrylica/cc-skills/commit/e18ca624da560c22b8e3b400ac9af550cdc3bdd1))

## [7.18.1](https://github.com/terrylica/cc-skills/compare/v7.18.0...v7.18.1) (2025-12-26)

### Bug Fixes

- **ralph:** remove SDK harness command and associated files ([79d25fd](https://github.com/terrylica/cc-skills/commit/79d25fde53014c76fc835c46f7d4fec2b66e6592))

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

- **doc-tools:** extend ascii-diagram-validator for graph-easy boxart ([f098092](https://github.com/terrylica/cc-skills/commit/f098092d30d0e87e746bbbfed8e6e1e27872503c))
- **ralph:** add session state continuity with infallible inheritance tracking ([b09d39d](https://github.com/terrylica/cc-skills/commit/b09d39d424627c9cc7e02102a45eba2f4c0a77ed))

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

- **ralph:** implement RSSI Beyond AGI - Intelligence Explosion mode ([efa10c4](https://github.com/terrylica/cc-skills/commit/efa10c47069852fd4e84d32e965a26c2fc797905))

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

- **ralph:** remove broken links to gitignored runtime directories ([0b4213c](https://github.com/terrylica/cc-skills/commit/0b4213c6de266188738a3739f930a64a43856812))

---

## Documentation Changes

## Other Documentation

### Other

- [Ralph Mental Model for Alpha-Forge](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/MENTAL-MODEL.md) - updated (+20/-20)

## [7.16.6](https://github.com/terrylica/cc-skills/compare/v7.16.5...v7.16.6) (2025-12-25)

### Bug Fixes

- **ralph:** add 5 graph-easy diagrams and 16 hyperlinks to MENTAL-MODEL.md ([adab79b](https://github.com/terrylica/cc-skills/commit/adab79bec2356cc686486e311d0138d5f8fb4702))

---

## Documentation Changes

## Other Documentation

### Other

- [Ralph Mental Model for Alpha-Forge](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/MENTAL-MODEL.md) - updated (+354/-57)

## [7.16.5](https://github.com/terrylica/cc-skills/compare/v7.16.4...v7.16.5) (2025-12-25)

### Bug Fixes

- **ralph:** audit fixes, constants centralization, and MENTAL-MODEL.md ([c544eb4](https://github.com/terrylica/cc-skills/commit/c544eb4866f2332ad66865a59e4be54ca1118dcb))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status   | ADR                                                                                                                                     | Change  |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------- | ------- |
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

- **ralph:** fail loudly when Jinja2 unavailable for complex templates ([d0fc686](https://github.com/terrylica/cc-skills/commit/d0fc6869de42d4c1bb7b72f84358b639710149a6))

## [7.16.3](https://github.com/terrylica/cc-skills/compare/v7.16.2...v7.16.3) (2025-12-25)

### Bug Fixes

- **ralph:** support nested dict access in fallback template renderer ([65d52b7](https://github.com/terrylica/cc-skills/commit/65d52b76e2458845d683b866095496daaccad16d))

## [7.16.2](https://github.com/terrylica/cc-skills/compare/v7.16.1...v7.16.2) (2025-12-25)

### Bug Fixes

- **ralph:** add global stop signal for version-agnostic stop ([dbcd448](https://github.com/terrylica/cc-skills/commit/dbcd448d91e2461c1a804b62e622f5628cca0a14))

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

- **ralph:** session-aware stop with holistic project directory resolution ([5f68a57](https://github.com/terrylica/cc-skills/commit/5f68a57b79a7b64a4a7b0db5202f883143b54067))

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

- **ralph:** add GPU infrastructure awareness for alpha-forge ([d203158](https://github.com/terrylica/cc-skills/commit/d20315884bcc3516143ef602ee3e8b4bf280cbab))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status  | ADR                                                                                                                                   | Change     |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
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

- **docs:** update link convention documentation for marketplace plugins ([2caf502](https://github.com/terrylica/cc-skills/commit/2caf502ab8daee3b2d7df8bc19d56767b436eab6))

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

- **validator:** correct link convention for marketplace plugins ([840f150](https://github.com/terrylica/cc-skills/commit/840f150a43dc1f8ea174ed85cbb43ec531c55a3e))

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

- **skills:** use relative paths for in-repo ADR links ([f2c5090](https://github.com/terrylica/cc-skills/commit/f2c5090b1877d872207d2bbf3004df360d585da0))

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

- **skills:** apply validate_skill.py to all production skills ([61bf292](https://github.com/terrylica/cc-skills/commit/61bf2921c58185f74bbd339f7cea64b1c3c2ef5b))

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

- **skill-architecture:** add comprehensive skill validator with interactive clarification ([5d6bdcf](https://github.com/terrylica/cc-skills/commit/5d6bdcfb284aca33b714bf9d8aca609d04d79790))

## [7.14.2](https://github.com/terrylica/cc-skills/compare/v7.14.1...v7.14.2) (2025-12-24)

### Bug Fixes

- **skills:** improve YAML frontmatter with TRIGGERS and allowed-tools ([99ba698](https://github.com/terrylica/cc-skills/commit/99ba698927415f8e46887dd34982e99f1dd95890))

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

- **semantic-release:** add bash heredoc wrappers for zsh compatibility ([1e04d40](https://github.com/terrylica/cc-skills/commit/1e04d40ae4f369c0e8501cc587d0c5259d4490e9))

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

- **notion-api:** add test suite and documentation insights from integration testing ([8934bea](https://github.com/terrylica/cc-skills/commit/8934bea30b16bc240e14ea5173667f4ccb793d18))

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

- **ralph:** add 5-part autonomous loop enhancement ([083652e](https://github.com/terrylica/cc-skills/commit/083652e5ed1edecc8d9345f1679274a541d2d39e))

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

- **asciinema-recorder:** add AskUserQuestion flows for interactive recording setup ([f0cdc8d](https://github.com/terrylica/cc-skills/commit/f0cdc8d6638cfac16eda72f0666ffa4bc6c015da))

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

- **ralph:** always prompt for preset confirmation before loop start ([86596f9](https://github.com/terrylica/cc-skills/commit/86596f9fdfee72ab42eb6f1e4e7742260667a537))

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

- **notion-api:** add Notion API plugin with notion-client SDK ([0e8dd69](https://github.com/terrylica/cc-skills/commit/0e8dd69e9c6536e363cf6e56ae5935afb49859e6))

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

- **semantic-release:** add auto-push workflow and HTTPS-first authentication ([f3d1a59](https://github.com/terrylica/cc-skills/commit/f3d1a596ebd8e73c88d175c59fdbb8f5f492f458))

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

- **ralph:** add dual time tracking (runtime + wall-clock) ([222bc18](https://github.com/terrylica/cc-skills/commit/222bc189cb1fe10f72db419d104a33dec186ea4f))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status  | ADR                                                                                                                                                 | Change |
| ------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| unknown | [Ralph Dual Time Tracking (Runtime + Wall-Clock)](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-22-ralph-dual-time-tracking.md) | new    |

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

- **ralph:** add user guidance lists for RSSI autonomous loop ([ce57dd0](https://github.com/terrylica/cc-skills/commit/ce57dd04a9d59688ef9eb7d554cab9705723787b))

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

| Status  | ADR                                                                                                                                                | Change |
| ------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| unknown | [Ralph Stop Visibility Observability](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-22-ralph-stop-visibility-observability.md) | new    |

## Plugin Documentation

### Plugin READMEs

- [Ralph Plugin for Claude Code](https://github.com/terrylica/cc-skills/blob/main/plugins/ralph/README.md) - updated

## Repository Documentation

### Root Documentation

- [CLAUDE.md](https://github.com/terrylica/cc-skills/blob/main/CLAUDE.md) - updated

# [7.7.0](https://github.com/terrylica/cc-skills/compare/v7.6.0...v7.7.0) (2025-12-23)

### Features

- **ralph:** add 5-layer stop visibility observability system ([ada180c](https://github.com/terrylica/cc-skills/commit/ada180c839be43255d9365671f48569c41f82954))

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

- **ralph:** use exploration template for CONVERGED busywork blocking ([f9d96db](https://github.com/terrylica/cc-skills/commit/f9d96db23ea7c2c7fd3439f8e503819e2f0d7e72))

### Features

- **skill-architecture:** enforce bash compatibility in skill creation ([899b406](https://github.com/terrylica/cc-skills/commit/899b40653245488bb94bc77e316e2484ef468164))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status  | ADR                                                                                                                                                  | Change |
| ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| unknown | [Skill Bash Compatibility Enforcement](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-22-skill-bash-compatibility-enforcement.md) | new    |

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

- **ralph:** prevent orphaned running state on script failure ([b21369c](https://github.com/terrylica/cc-skills/commit/b21369c2d6519243f898970f223860255769385f))

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

- **devops-tools:** add interactive configuration to asciinema-streaming-backup ([b431465](https://github.com/terrylica/cc-skills/commit/b4314650e064a1755774da780b494e8d0a599424))

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

- **asciinema-streaming-backup:** add AskUserQuestion flows and GitHub account detection ([03affac](https://github.com/terrylica/cc-skills/commit/03affacf523bb14ffd9dd9fa8f4e7f159c6f7fb5))

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

- **devops-tools:** add asciinema-streaming-backup skill ([ee5fb0f](https://github.com/terrylica/cc-skills/commit/ee5fb0f11a62051b776a3ed4099371da5c29f730))

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

- **devops-tools:** remove -c flag from asciinema-recorder ([d646014](https://github.com/terrylica/cc-skills/commit/d646014686bea050f11fffd47e7b80ff8b09c1b7))

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

- **devops-tools:** expand asciinema-recorder trigger phrases ([2a01131](https://github.com/terrylica/cc-skills/commit/2a011311e635c4abcf26eea9c00692d732e6952d))

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

- **devops-tools:** add asciinema-recorder skill for recording Claude Code sessions ([bc52a73](https://github.com/terrylica/cc-skills/commit/bc52a7366694a901a574ee778fe2f05c7316f2cb))

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

- **statusline-tools:** add UTC timestamp with date to status line ([44030fe](https://github.com/terrylica/cc-skills/commit/44030fee4b9e84666061026544fd270890573868))

# [7.0.0](https://github.com/terrylica/cc-skills/compare/v6.5.1...v7.0.0) (2025-12-22)

- feat(asciinema-player)!: rewrite for iTerm2-only playback ([c23d646](https://github.com/terrylica/cc-skills/commit/c23d64642dbcabdc0ecd95c67c79f4bd6bc2c49e))

### BREAKING CHANGES

- Browser-based player removed. Now uses iTerm2 CLI only.

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

- **dotfiles-tools:** enhance chezmoi hook to detect untracked config files ([ff71693](https://github.com/terrylica/cc-skills/commit/ff7169337f0583a803708ea98e3a5fe432235da8))

## [6.4.1](https://github.com/terrylica/cc-skills/compare/v6.4.0...v6.4.1) (2025-12-21)

### Bug Fixes

- **asciinema-player:** use semver range for auto-upgrade with minimum version ([fd42458](https://github.com/terrylica/cc-skills/commit/fd4245897bb2afddea2caa9822c81126a63acb49))

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

- **asciinema-player:** upgrade to v3.10.0 for asciicast v3 support ([44db67c](https://github.com/terrylica/cc-skills/commit/44db67c2240ba01b78accf3bd37553bb50c252d5))
- **asciinema-player:** use available port when default is occupied ([fa55afc](https://github.com/terrylica/cc-skills/commit/fa55afcb9cb717d829429cdde721514ece925bb9))

### Features

- **asciinema-player:** redesign with mandatory AskUserQuestion flows and preflight checks ([d3985a8](https://github.com/terrylica/cc-skills/commit/d3985a808fd88406c57f25eebe29301516017a8f))

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

- **statusline-tools:** correct two-line layout ([2479105](https://github.com/terrylica/cc-skills/commit/2479105f0d4ef2fc6f3f0d64070c1339b87cc59a))

# [6.3.0](https://github.com/terrylica/cc-skills/compare/v6.2.0...v6.3.0) (2025-12-21)

### Features

- **statusline-tools:** change to two-line status format ([90fb9a4](https://github.com/terrylica/cc-skills/commit/90fb9a428d69dcf3dfb69e6c5f72baf890602b8f))

# [6.2.0](https://github.com/terrylica/cc-skills/compare/v6.1.0...v6.2.0) (2025-12-21)

### Features

- **devops-tools:** add AskUserQuestion-driven workflow to asciinema-player ([316b829](https://github.com/terrylica/cc-skills/commit/316b82909fe82b43383d316b9f9b9b50e80170c6))

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

- **devops-tools:** add asciinema-player skill for terminal recordings ([5cbc4d1](https://github.com/terrylica/cc-skills/commit/5cbc4d16ea2c0b8cd65d9239e14c77ccecbf1571))

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

- **ralph:** align implementation with design philosophy ([e7d7755](https://github.com/terrylica/cc-skills/commit/e7d775528b4dc08dee47c467418bd5e0235fa53c))

### BREAKING CHANGES

- **ralph:** Ralph is now Alpha Forge exclusive

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

- **release-notes:** expand documentation linking to all markdown files ([86fb31e](https://github.com/terrylica/cc-skills/commit/86fb31e5ebeabe45b7093e3cee3f29ec02475b8e))

---

## Documentation Changes

## Architecture Decisions

### ADRs

| Status      | ADR                                                                                                                                                            | Change  |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| accepted    | [Documentation Links in Release Notes](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-06-release-notes-adr-linking.md)                      | updated |
| implemented | [Shell Command Portability for Zsh Compatibility](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-06-shell-command-portability-zsh.md)       | coupled |
| accepted    | [mise Environment Variables as Centralized Configuration](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-08-mise-env-centralized-config.md) | updated |

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

- **ralph:** align dependencies with best practices, add design philosophy ([f00f872](https://github.com/terrylica/cc-skills/commit/f00f872584fd503616db0279391af3296a440744)), closes [Hi#Impact](https://github.com/Hi/issues/Impact)

## [5.24.2](https://github.com/terrylica/cc-skills/compare/v5.24.1...v5.24.2) (2025-12-21)

## [5.24.1](https://github.com/terrylica/cc-skills/compare/v5.24.0...v5.24.1) (2025-12-21)

### Bug Fixes

- **release:** add revert type to release rules ([66a5753](https://github.com/terrylica/cc-skills/commit/66a5753a022aa46ff4180da434e8001f21dcb8a8))

### Reverts

- **ralph:** remove redundant cooldown, use existing stamina backoff ([ab95990](https://github.com/terrylica/cc-skills/commit/ab95990d9b2f0bc9f2984dd51f2d8b93934d2c6f))

# [5.24.0](https://github.com/terrylica/cc-skills/compare/v5.23.0...v5.24.0) (2025-12-21)

### Features

- **ralph:** add idle command guard to block repetitive git status ([4551a7a](https://github.com/terrylica/cc-skills/commit/4551a7a619eeb61d0b39f03ba0cc31110c95fe9c))

# [5.23.0](https://github.com/terrylica/cc-skills/compare/v5.22.0...v5.23.0) (2025-12-21)

### Features

- **ralph:** exponential backoff for idle detection (stamina-style) ([b9c5f13](https://github.com/terrylica/cc-skills/commit/b9c5f13819342bcd05610e7a0dde6b54025bfca1))

# [5.22.0](https://github.com/terrylica/cc-skills/compare/v5.21.5...v5.22.0) (2025-12-21)

### Features

- **ralph:** deterministic idle detection to prevent token waste ([128ae77](https://github.com/terrylica/cc-skills/commit/128ae776de5ddd46015f029640f801662f4e1947))

## [5.21.5](https://github.com/terrylica/cc-skills/compare/v5.21.4...v5.21.5) (2025-12-21)

### Bug Fixes

- **ralph:** forbid idle monitoring loop that wastes tokens ([a263339](https://github.com/terrylica/cc-skills/commit/a263339bfa9711aa3f3e4dff305bf29fd2930d4e))

## [5.21.4](https://github.com/terrylica/cc-skills/compare/v5.21.3...v5.21.4) (2025-12-21)

### Bug Fixes

- **ralph:** prevent premature stop when task complete but agent idling ([ff7ab6f](https://github.com/terrylica/cc-skills/commit/ff7ab6fb1cc58a93c8acb8b40eff958a3477fc3e))

## [5.21.3](https://github.com/terrylica/cc-skills/compare/v5.21.2...v5.21.3) (2025-12-21)

### Bug Fixes

- **ralph:** actionable RSSI hook with 5-step loop ([8f60322](https://github.com/terrylica/cc-skills/commit/8f60322da46da54f7bd6622cd69e849c852c896c))

## [5.21.2](https://github.com/terrylica/cc-skills/compare/v5.21.1...v5.21.2) (2025-12-21)

### Bug Fixes

- **ralph:** ultra-minimal RSSI hook output for no_focus mode ([ce1200a](https://github.com/terrylica/cc-skills/commit/ce1200aea829e990baca0127d53399e1a67a6d4d))

## [5.21.1](https://github.com/terrylica/cc-skills/compare/v5.21.0...v5.21.1) (2025-12-21)

### Bug Fixes

- **ralph:** trim stop hook output to concise status only ([6bfc8d1](https://github.com/terrylica/cc-skills/commit/6bfc8d162d50ddceb8f59d88ca672707a81a8506))

# [5.21.0](https://github.com/terrylica/cc-skills/compare/v5.20.0...v5.21.0) (2025-12-21)

### Features

- **ralph:** goal-driven dynamic search depth for alpha-forge integration ([aa714ef](https://github.com/terrylica/cc-skills/commit/aa714ef6a15b58c55bfa9952a6e327ce729d5306))

# [5.20.0](https://github.com/terrylica/cc-skills/compare/v5.19.3...v5.20.0) (2025-12-21)

### Features

- **ralph:** dynamic iterative WebSearch for SOTA discovery ([a863788](https://github.com/terrylica/cc-skills/commit/a86378884c2178e1b5f2aa6ec6b0149d39c66cd4))

## [5.19.3](https://github.com/terrylica/cc-skills/compare/v5.19.2...v5.19.3) (2025-12-21)

### Bug Fixes

- **ralph:** make RSSI template action-oriented, forbid status-only responses ([66515d1](https://github.com/terrylica/cc-skills/commit/66515d17718e829679a8b528fc191ef681757703))

## [5.19.2](https://github.com/terrylica/cc-skills/compare/v5.19.1...v5.19.2) (2025-12-21)

### Bug Fixes

- **ralph:** add no-focus mode convergence detection ([05330ff](https://github.com/terrylica/cc-skills/commit/05330ffb12feaf7e6bf8a3be137d843ac1945ec7))

## [5.19.1](https://github.com/terrylica/cc-skills/compare/v5.19.0...v5.19.1) (2025-12-21)

### Bug Fixes

- **devops-tools,quality-tools:** update gapless-crypto-data to gapless-crypto-clickhouse ([4b4510d](https://github.com/terrylica/cc-skills/commit/4b4510da3520cad3fdbc116d729ee5e37bb5ecad))

# [5.19.0](https://github.com/terrylica/cc-skills/compare/v5.18.0...v5.19.0) (2025-12-21)

### Features

- **ralph:** use gapless-crypto-clickhouse for historical data ([c516bec](https://github.com/terrylica/cc-skills/commit/c516becad68739e7542beb9b8f6164cc22c0209f))

# [5.18.0](https://github.com/terrylica/cc-skills/compare/v5.17.0...v5.18.0) (2025-12-21)

### Features

- **ralph:** add DATA INTEGRITY constraints for real historical data ([8e20ad4](https://github.com/terrylica/cc-skills/commit/8e20ad4e0d9b5d65b6cc7a646057afb650f49c6f))

# [5.17.0](https://github.com/terrylica/cc-skills/compare/v5.16.0...v5.17.0) (2025-12-21)

### Features

- **ralph:** add AUTONOMOUS MODE directive and SDK harness ([1de8eb4](https://github.com/terrylica/cc-skills/commit/1de8eb480c355c2cd61554eac9d0280e6a21fd3e))

# [5.16.0](https://github.com/terrylica/cc-skills/compare/v5.15.0...v5.16.0) (2025-12-21)

### Bug Fixes

- **ralph:** correct adapter detection path in start.md ([80d309c](https://github.com/terrylica/cc-skills/commit/80d309c4497f79b77c4b0d8c05928a323e6ee2ff))

### Features

- **ralph:** auto-invoke /research command for Alpha Forge research sessions ([09d7033](https://github.com/terrylica/cc-skills/commit/09d7033caebbc6ccad9ecf16e21e55b3cced0bf6))
- **ralph:** implement SOTA iterative patterns for Alpha Forge RSSI ([d71f150](https://github.com/terrylica/cc-skills/commit/d71f15049b088fa42a89897e71786211425e42d2))

# [5.15.0](https://github.com/terrylica/cc-skills/compare/v5.14.0...v5.15.0) (2025-12-21)

### Features

- **ralph:** auto-select focus files without prompting ([463a984](https://github.com/terrylica/cc-skills/commit/463a984c1faeecbd6afe7db4a8e553bfae0879b4))

# [5.14.0](https://github.com/terrylica/cc-skills/compare/v5.13.0...v5.14.0) (2025-12-21)

### Features

- **ralph:** fail fast when version cannot be determined ([676c23b](https://github.com/terrylica/cc-skills/commit/676c23ba9fc9d6df53a9036e832886030f060edc))

# [5.13.0](https://github.com/terrylica/cc-skills/compare/v5.12.1...v5.13.0) (2025-12-21)

### Features

- **ralph:** show local repo version from package.json ([9798c88](https://github.com/terrylica/cc-skills/commit/9798c88a5767145fa1c121a818792c6ed3bffd2a))

## [5.12.1](https://github.com/terrylica/cc-skills/compare/v5.12.0...v5.12.1) (2025-12-21)

### Bug Fixes

- **ralph:** prefer local-dev when symlink directory exists ([fbe546e](https://github.com/terrylica/cc-skills/commit/fbe546ede847d448b440f683d88eb57f42b30dc1))

# [5.12.0](https://github.com/terrylica/cc-skills/compare/v5.11.1...v5.12.0) (2025-12-21)

### Features

- **ralph:** add version banner to /ralph:start ([80cb8ed](https://github.com/terrylica/cc-skills/commit/80cb8ed547aebadaa6e8bcac6399b96a6f26a002))

## [5.11.1](https://github.com/terrylica/cc-skills/compare/v5.11.0...v5.11.1) (2025-12-21)

### Bug Fixes

- **ralph:** add Alpha Forge research sessions to start.md discovery ([8229f38](https://github.com/terrylica/cc-skills/commit/8229f38f336307211486fef19f5483591d8ae7af))

# [5.11.0](https://github.com/terrylica/cc-skills/compare/v5.10.4...v5.11.0) (2025-12-21)

### Features

- **ralph:** add Alpha Forge research session discovery ([71b30d9](https://github.com/terrylica/cc-skills/commit/71b30d9e1223a225d0b394c9bd3df78955dff9df))

## [5.10.4](https://github.com/terrylica/cc-skills/compare/v5.10.3...v5.10.4) (2025-12-21)

### Bug Fixes

- **ralph:** add simple alpha-forge detection failsafe ([70465e6](https://github.com/terrylica/cc-skills/commit/70465e600786d1d54ef011a715483048ef7dbe3f))

## [5.10.3](https://github.com/terrylica/cc-skills/compare/v5.10.2...v5.10.3) (2025-12-21)

### Bug Fixes

- **ralph:** add parent directory detection to alpha-forge adapter ([406fb0e](https://github.com/terrylica/cc-skills/commit/406fb0e3be9076f11b5f239ce95ee3f62565af1d))

## [5.10.2](https://github.com/terrylica/cc-skills/compare/v5.10.1...v5.10.2) (2025-12-21)

## [5.10.1](https://github.com/terrylica/cc-skills/compare/v5.10.0...v5.10.1) (2025-12-21)

### Bug Fixes

- **ralph:** apply busywork filter at all stages for Alpha Forge ([51de144](https://github.com/terrylica/cc-skills/commit/51de144f7ac6fadcdc63ec173c5f8d95d7a3582a))

# [5.10.0](https://github.com/terrylica/cc-skills/compare/v5.9.3...v5.10.0) (2025-12-21)

### Features

- **ralph:** add reinforcement learning with persistent artifacts for Alpha Forge ([f8ea147](https://github.com/terrylica/cc-skills/commit/f8ea14763f000c20dad2ed1ec1f0c9a8db017487))

# [5.10.0](https://github.com/terrylica/cc-skills/compare/v5.9.3...v5.10.0) (2025-12-21)

### Features

- **ralph:** add reinforcement learning with persistent artifacts for Alpha Forge ([f8ea147](https://github.com/terrylica/cc-skills/commit/f8ea14763f000c20dad2ed1ec1f0c9a8db017487))

## [5.9.3](https://github.com/terrylica/cc-skills/compare/v5.9.2...v5.9.3) (2025-12-21)

### Bug Fixes

- **ralph:** strict busywork filter for Alpha Forge eternal loop ([7d69c49](https://github.com/terrylica/cc-skills/commit/7d69c49f375c2ffd92f3d77adf594e26740c3a23))

## [5.9.2](https://github.com/terrylica/cc-skills/compare/v5.9.1...v5.9.2) (2025-12-21)

### Bug Fixes

- **ralph:** detect research completion and stop loop ([7b60d70](https://github.com/terrylica/cc-skills/commit/7b60d70cd3ea07ea3e70dfee48cc07a3932f103c))

## [5.9.1](https://github.com/terrylica/cc-skills/compare/v5.9.0...v5.9.1) (2025-12-21)

### Bug Fixes

- **ralph:** improve adapter detection and completion for ITP workflow ([c311323](https://github.com/terrylica/cc-skills/commit/c311323d4300b63e12a4da15343f73acb2bedb65))

# [5.9.0](https://github.com/terrylica/cc-skills/compare/v5.8.7...v5.9.0) (2025-12-20)

### Bug Fixes

- **ralph:** use kill switch for reliable /ralph:stop termination ([27454e6](https://github.com/terrylica/cc-skills/commit/27454e615ef55462cb9db3cf6359aa2e58c734fc))

### Features

- **ralph:** add SLO enforcement for Alpha Forge projects ([70b024e](https://github.com/terrylica/cc-skills/commit/70b024e053f7425d0016924a710bb8e012aae2ba))
- **ralph:** add unified config schema with externalized magic numbers ([50eedb0](https://github.com/terrylica/cc-skills/commit/50eedb05ad8aea04c26d2bcbd8290f410f05d0c6))
- **ralph:** enhance /ralph:config with v2.0 unified schema ([f31fb7c](https://github.com/terrylica/cc-skills/commit/f31fb7c3f3dde2e8330c4dfe14fc583e57413e95))
- **ralph:** implement state machine in start/stop commands ([716cba3](https://github.com/terrylica/cc-skills/commit/716cba36eb8e5333572927e847cab259536ccf29))

## [5.8.7](https://github.com/terrylica/cc-skills/compare/v5.8.6...v5.8.7) (2025-12-20)

### Bug Fixes

- **ralph:** allow /ralph:stop to bypass loop guard ([c758374](https://github.com/terrylica/cc-skills/commit/c758374b1df5f5539e9711a213b75c8f55841e10))

## [5.8.6](https://github.com/terrylica/cc-skills/compare/v5.8.5...v5.8.6) (2025-12-20)

### Bug Fixes

- **ralph:** add PreToolUse hook to guard loop control files ([89cb426](https://github.com/terrylica/cc-skills/commit/89cb42641772e6de7844b4d72bda4e02eb499865))

## [5.8.5](https://github.com/terrylica/cc-skills/compare/v5.8.4...v5.8.5) (2025-12-20)

### Bug Fixes

- **ralph:** add explicit constraints to prevent self-termination ([f93a38a](https://github.com/terrylica/cc-skills/commit/f93a38aacedfd44ce26af2ee46661121bca82241))

## [5.8.4](https://github.com/terrylica/cc-skills/compare/v5.8.3...v5.8.4) (2025-12-20)

### Bug Fixes

- **ralph:** handle None values in theme dict for web discovery ([5d2f2ee](https://github.com/terrylica/cc-skills/commit/5d2f2ee2ac49a9baa43f262c8034a120f1fd637e))

## [5.8.3](https://github.com/terrylica/cc-skills/compare/v5.8.2...v5.8.3) (2025-12-20)

### Bug Fixes

- **ralph:** always use RSSI exploration mode in no_focus mode ([d6357f9](https://github.com/terrylica/cc-skills/commit/d6357f935719034f136d17f04a2e4131975d2933))

## [5.8.2](https://github.com/terrylica/cc-skills/compare/v5.8.1...v5.8.2) (2025-12-20)

### Bug Fixes

- **ralph:** remove invalid line-length from ruff.toml ([3152227](https://github.com/terrylica/cc-skills/commit/3152227d58902dbcaa43d1bb1827fb56ec24fe13))

## [5.8.1](https://github.com/terrylica/cc-skills/compare/v5.8.0...v5.8.1) (2025-12-20)

# [5.8.0](https://github.com/terrylica/cc-skills/compare/v5.7.1...v5.8.0) (2025-12-20)

### Bug Fixes

- **ralph:** use absolute import in rssi_meta.py ([690f137](https://github.com/terrylica/cc-skills/commit/690f1378e0eb3d444fc9e1753c9ad3591b82ab38))

### Features

- **ralph:** implement RSSI eternal loop architecture ([2b6bc06](https://github.com/terrylica/cc-skills/commit/2b6bc068b6cc2d2a546428f68f808d2159ae675b))

## [5.7.1](https://github.com/terrylica/cc-skills/compare/v5.7.0...v5.7.1) (2025-12-20)

### Bug Fixes

- **ralph:** align adapter tests with RSSI-only stopping design ([61e8ead](https://github.com/terrylica/cc-skills/commit/61e8ead76be3d6a851bb4bd03eb8cc40a3ee37db))

# [5.7.0](https://github.com/terrylica/cc-skills/compare/v5.6.0...v5.7.0) (2025-12-20)

### Features

- **ralph:** add plan mode discovery and user confirmation flow ([f59cc83](https://github.com/terrylica/cc-skills/commit/f59cc83af3e6bfa480a1aeef030a49facdb5a5c9))

# [5.6.0](https://github.com/terrylica/cc-skills/compare/v5.5.5...v5.6.0) (2025-12-20)

### Features

- **ralph:** add research experts and fix metrics display for Alpha Forge ([4f6a425](https://github.com/terrylica/cc-skills/commit/4f6a425c6f7b318b6db906ec09885aee5f045785))

## [5.5.5](https://github.com/terrylica/cc-skills/compare/v5.5.4...v5.5.5) (2025-12-20)

### Bug Fixes

- **statusline-tools:** use HOOK_SCRIPT_RESOLVED for status display ([8b2383e](https://github.com/terrylica/cc-skills/commit/8b2383e52b2091519c9b03897b09fd5347973fd6))
- **statusline-tools:** use HOOK_SCRIPT_SETTINGS for consistent logging ([0058144](https://github.com/terrylica/cc-skills/commit/0058144f023c194934708aff7d0e33a9f199fda5))

## [5.5.4](https://github.com/terrylica/cc-skills/compare/v5.5.3...v5.5.4) (2025-12-20)

### Bug Fixes

- **statusline-tools:** use marketplace path for auto-updates ([0ae976d](https://github.com/terrylica/cc-skills/commit/0ae976d01536b0225541b5452fc7bcb5f16adb03))

## [5.5.3](https://github.com/terrylica/cc-skills/compare/v5.5.2...v5.5.3) (2025-12-20)

### Bug Fixes

- add lychee config to exclude test fixtures and generated dirs ([9a37752](https://github.com/terrylica/cc-skills/commit/9a377526ba6efa5aab684f87c456aa2ac19d4e89))

## [5.5.2](https://github.com/terrylica/cc-skills/compare/v5.5.1...v5.5.2) (2025-12-20)

### Bug Fixes

- **statusline-tools:** add separator between git status and link validation ([d9036aa](https://github.com/terrylica/cc-skills/commit/d9036aa853cb8775c865cf026c014e58f5647ef0))

## [5.5.1](https://github.com/terrylica/cc-skills/compare/v5.5.0...v5.5.1) (2025-12-20)

### Bug Fixes

- **statusline-tools:** resolve Stop hook failure from pipefail and file scanning ([e0913ef](https://github.com/terrylica/cc-skills/commit/e0913efa2ca14036a7539f44daf33e3bc9a792c2))

# [5.5.0](https://github.com/terrylica/cc-skills/compare/v5.4.0...v5.5.0) (2025-12-20)

### Features

- **statusline-tools:** add custom status line plugin with git status, link validation, and path linting ([6cbb11c](https://github.com/terrylica/cc-skills/commit/6cbb11c9edcbcf5968f2c29b0e54ff5a265177ab))

# [5.4.0](https://github.com/terrylica/cc-skills/compare/v5.3.0...v5.4.0) (2025-12-20)

### Features

- **ralph:** add multi-repository adapter architecture ([1ab4637](https://github.com/terrylica/cc-skills/commit/1ab46370872d3f440278915c427d98c7a4d7e27d))

# [5.3.0](https://github.com/terrylica/cc-skills/compare/v5.2.2...v5.3.0) (2025-12-20)

### Features

- **ralph:** modularize RSSI hooks into separation of concerns architecture ([bc4e050](https://github.com/terrylica/cc-skills/commit/bc4e050567a7de9db5e4a2823ef7d6e68b3cfe37))

## [5.2.2](https://github.com/terrylica/cc-skills/compare/v5.2.1...v5.2.2) (2025-12-20)

## [5.2.1](https://github.com/terrylica/cc-skills/compare/v5.2.0...v5.2.1) (2025-12-20)

### Bug Fixes

- **semantic-release:** simplify account verification to HTTPS-first workflow ([e0ae2a2](https://github.com/terrylica/cc-skills/commit/e0ae2a28e7cc3848f399b5632c47f2121b3b72ab))

# [5.2.0](https://github.com/terrylica/cc-skills/compare/v5.1.7...v5.2.0) (2025-12-20)

### Features

- **ralph:** add file discovery and argument parsing ([51c8dee](https://github.com/terrylica/cc-skills/commit/51c8dee9b88135cb9773ab8869b596ade9a35d1c))

## [5.1.7](https://github.com/terrylica/cc-skills/compare/v5.1.6...v5.1.7) (2025-12-19)

### Bug Fixes

- **ralph:** add shell compatibility for macOS zsh ([dbd1722](https://github.com/terrylica/cc-skills/commit/dbd1722cb8608b1a8c0d63faf6133e959526babb))

## [5.1.6](https://github.com/terrylica/cc-skills/compare/v5.1.5...v5.1.6) (2025-12-19)

## [5.1.5](https://github.com/terrylica/cc-skills/compare/v5.1.4...v5.1.5) (2025-12-19)

### Bug Fixes

- **ralph:** correct Stop hook for multi-iteration loops ([a9a0701](https://github.com/terrylica/cc-skills/commit/a9a0701bd9e3d45a51db6c5e7697b8cc2d802def))

## [5.1.4](https://github.com/terrylica/cc-skills/compare/v5.1.3...v5.1.4) (2025-12-19)

### Bug Fixes

- **ralph:** use correct Stop hook schema per Claude Code docs ([5a1e2db](https://github.com/terrylica/cc-skills/commit/5a1e2dbe095c9e7c6dcae463617a09da72c515ad))

## [5.1.3](https://github.com/terrylica/cc-skills/compare/v5.1.2...v5.1.3) (2025-12-19)

### Bug Fixes

- **git-account-validator:** change default to warn-only for network issues ([a139c06](https://github.com/terrylica/cc-skills/commit/a139c06689509588719d7222659ac601fa02da7c))

## [5.1.2](https://github.com/terrylica/cc-skills/compare/v5.1.1...v5.1.2) (2025-12-19)

### Bug Fixes

- **ralph:** use correct Stop hook JSON schema ([eb115d0](https://github.com/terrylica/cc-skills/commit/eb115d0fe925e713b5df3f345ea08a6a19035335))

## [5.1.1](https://github.com/terrylica/cc-skills/compare/v5.1.0...v5.1.1) (2025-12-19)

### Bug Fixes

- **ralph:** improve status accuracy and hook validation ([73d3acc](https://github.com/terrylica/cc-skills/commit/73d3accbb9ea09f5929f9c26dc81823a8b53d50b))

# [5.0.0](https://github.com/terrylica/cc-skills/compare/v4.8.4...v5.0.0) (2025-12-19)

### Features

- **ralph:** add autonomous loop hooks and slash commands ([a39ccc5](https://github.com/terrylica/cc-skills/commit/a39ccc57a3b9786b5fa6442306b627c1984b1c54))

### BREAKING CHANGES

- **ralph:** Plugin renamed from ralph-tools to ralph

## [4.8.4](https://github.com/terrylica/cc-skills/compare/v4.8.3...v4.8.4) (2025-12-19)

### Bug Fixes

- **docs:** add GitHub token reference docs for mise multi-account setup ([bf4eb93](https://github.com/terrylica/cc-skills/commit/bf4eb936e75cdbc9d2084b8c1f2d0b96bc9818a5))

## [4.8.3](https://github.com/terrylica/cc-skills/compare/v4.8.2...v4.8.3) (2025-12-18)

### Bug Fixes

- **docs:** add release notes visibility warning to semantic-release skill ([3a3b7fd](https://github.com/terrylica/cc-skills/commit/3a3b7fdcd82587811dac44ec376d78a8e9ff0c61))

## [4.8.2](https://github.com/terrylica/cc-skills/compare/v4.8.1...v4.8.2) (2025-12-18)

## [4.8.1](https://github.com/terrylica/cc-skills/compare/v4.8.0...v4.8.1) (2025-12-18)

### Bug Fixes

- **docs:** align documentation with actual plugin/skill counts and paths ([6a89dfc](https://github.com/terrylica/cc-skills/commit/6a89dfcf35169bf8167880b61a4ab443eb3dd168))

# [4.8.0](https://github.com/terrylica/cc-skills/compare/v4.7.2...v4.8.0) (2025-12-17)

### Features

- **itp-hooks:** add hooks-development skill for PostToolUse visibility patterns ([c1de3ac](https://github.com/terrylica/cc-skills/commit/c1de3acbd0fd2d96f22b4438d67108b8d8c2edda))

## [4.7.2](https://github.com/terrylica/cc-skills/compare/v4.7.1...v4.7.2) (2025-12-17)

## [4.7.1](https://github.com/terrylica/cc-skills/compare/v4.7.0...v4.7.1) (2025-12-17)

### Bug Fixes

- **dotfiles-tools:** use decision:block JSON for Claude visibility ([a8f20c3](https://github.com/terrylica/cc-skills/commit/a8f20c3b819a4b1f3dfbb1b0c25d1131cba29595))

# [4.7.0](https://github.com/terrylica/cc-skills/compare/v4.6.1...v4.7.0) (2025-12-17)

### Features

- **dotfiles-tools:** add /dotfiles:hooks installer command ([7e568e8](https://github.com/terrylica/cc-skills/commit/7e568e8d7318f3a032de6162cf430734cabe2295))

## [4.6.1](https://github.com/terrylica/cc-skills/compare/v4.6.0...v4.6.1) (2025-12-17)

### Bug Fixes

- **dotfiles-tools:** use INSTRUCTION prefix for deterministic skill invocation ([29de9e4](https://github.com/terrylica/cc-skills/commit/29de9e41272f243041e27bc9b6208df4f4a35528))

# [4.6.0](https://github.com/terrylica/cc-skills/compare/v4.5.0...v4.6.0) (2025-12-17)

### Features

- **dotfiles-tools:** add chezmoi sync reminder PostToolUse hook ([96f9fbd](https://github.com/terrylica/cc-skills/commit/96f9fbd70ecc8b82e22cc1b3063333992f6a45da))

# [4.5.0](https://github.com/terrylica/cc-skills/compare/v4.4.0...v4.5.0) (2025-12-16)

### Bug Fixes

- **dotfiles-tools:** improve skill description with specific triggers ([8ff7fe3](https://github.com/terrylica/cc-skills/commit/8ff7fe341591ca0bcd360332e5876ff313c141c2))
- **dotfiles-tools:** use portable chezmoi git commands ([8039eea](https://github.com/terrylica/cc-skills/commit/8039eea11df522f89e049a93931f7f5aba6b5c10))
- **dotfiles-tools:** validation fixes for universal applicability ([db192a2](https://github.com/terrylica/cc-skills/commit/db192a23ad732c6cd40efeb9272139cabc488d71))

### Features

- **dotfiles-tools:** add setup guide for universal chezmoi configuration ([9233cb9](https://github.com/terrylica/cc-skills/commit/9233cb9677424bf200e8d4214aed4c851ac8a0ab))
- **dotfiles-tools:** expand description with common tool triggers ([e815cf0](https://github.com/terrylica/cc-skills/commit/e815cf08ad7c905caf4480fd020e4acf69cda8a6))

# [4.4.0](https://github.com/terrylica/cc-skills/compare/v4.3.0...v4.4.0) (2025-12-16)

### Features

- **iterm2-layout-config:** add plugin for TOML-based configuration separation ([5aa88d0](https://github.com/terrylica/cc-skills/commit/5aa88d044a5dbf20a9048e99017ab494fee5112d))

# [4.3.0](https://github.com/terrylica/cc-skills/compare/v4.2.0...v4.3.0) (2025-12-16)

### Features

- **ralph-tools:** add 'ralph wiggum' as skill trigger ([cdd02dc](https://github.com/terrylica/cc-skills/commit/cdd02dcedc507b1405dee09c3c028135407170f2))

# [4.2.0](https://github.com/terrylica/cc-skills/compare/v4.1.1...v4.2.0) (2025-12-15)

### Features

- **alpha-forge-worktree:** add direnv integration for auto-loading secrets ([0e8214c](https://github.com/terrylica/cc-skills/commit/0e8214c0fe531a4587e1066f4f5c21156e6f751c))

## [4.1.1](https://github.com/terrylica/cc-skills/compare/v4.1.0...v4.1.1) (2025-12-15)

# [4.1.0](https://github.com/terrylica/cc-skills/compare/v4.0.0...v4.1.0) (2025-12-15)

### Bug Fixes

- add ralph-tools plugin with validation fixes ([952d1e3](https://github.com/terrylica/cc-skills/commit/952d1e345c003c0102b7c875db9c23a620369c80))

### Features

- **itp:** add ralph-orchestrator skill for autonomous AI development ([da1ba3b](https://github.com/terrylica/cc-skills/commit/da1ba3b63f1dee2190dfa5c240fbacbb334f7063))

# [4.0.0](https://github.com/terrylica/cc-skills/compare/v3.5.0...v4.0.0) (2025-12-15)

### Features

- **alpha-forge-worktree:** refactor to skills-only architecture with natural language triggers ([9d71107](https://github.com/terrylica/cc-skills/commit/9d71107a5550625c226c156c12b61d5bb9f25145))

### BREAKING CHANGES

- **alpha-forge-worktree:** The /af:wt slash command is removed. Use natural language
  triggers like "create worktree for [description]" instead.

# [3.5.0](https://github.com/terrylica/cc-skills/compare/v3.4.1...v3.5.0) (2025-12-15)

### Features

- **marketplace:** register alpha-forge-worktree plugin ([ac70daf](https://github.com/terrylica/cc-skills/commit/ac70dafaf421bf147940bbee64ac2a8d71a150cb))
- **plugin:** add alpha-forge-worktree plugin for git worktree management ([16c40bd](https://github.com/terrylica/cc-skills/commit/16c40bda8d036eb4dea45db1e42e5655677b3c7b))
- **validation:** enhance plugin validation to prevent marketplace registration oversight ([0792242](https://github.com/terrylica/cc-skills/commit/0792242964ae7da80543d964b246c886bb7b7398))

## [3.4.1](https://github.com/terrylica/cc-skills/compare/v3.4.0...v3.4.1) (2025-12-15)

# [3.4.0](https://github.com/terrylica/cc-skills/compare/v3.3.0...v3.4.0) (2025-12-15)

### Features

- **pandoc-pdf-generation:** add --hide-details flag to strip <details> blocks from PDF ([be2012e](https://github.com/terrylica/cc-skills/commit/be2012e5154852884582adfc7f42605ef51a0190))

# [3.3.0](https://github.com/terrylica/cc-skills/compare/v3.2.0...v3.3.0) (2025-12-14)

### Bug Fixes

- **git-account-validator:** pre-flush SSH ControlMaster cache before validation ([5ef6820](https://github.com/terrylica/cc-skills/commit/5ef682055f55f799e565c9a79fad4166bcb1cb5b))

### Features

- **git-account-validator:** add pre-push validation plugin for multi-account GitHub ([73984f7](https://github.com/terrylica/cc-skills/commit/73984f7e889ad73b499477e305be23c2aa9bec38))

# [3.2.0](https://github.com/terrylica/cc-skills/compare/v3.1.2...v3.2.0) (2025-12-13)

### Features

- **pandoc-pdf-generation:** add orientation options and markdown authoring guide ([f4d2d61](https://github.com/terrylica/cc-skills/commit/f4d2d610263ceac4cb165fcede37eaaa1d6dd770))

## [3.1.2](https://github.com/terrylica/cc-skills/compare/v3.1.1...v3.1.2) (2025-12-13)

### Bug Fixes

- **itp-hooks:** detect file trees to avoid false positives in diagram blocking ([b71d7cb](https://github.com/terrylica/cc-skills/commit/b71d7cb4e70719e06e72dcb7d1a6f76c85596ea8))

## [3.1.1](https://github.com/terrylica/cc-skills/compare/v3.1.0...v3.1.1) (2025-12-13)

### Bug Fixes

- **itp-hooks:** broaden plan file exemption to any /plans/ directory ([e206d03](https://github.com/terrylica/cc-skills/commit/e206d03376721cd1656919b51e9c2f7e0a448d44))

# [3.1.0](https://github.com/terrylica/cc-skills/compare/v3.0.0...v3.1.0) (2025-12-13)

### Features

- **graph-easy:** add wrapper script for mise-installed binary ([ae4fcf9](https://github.com/terrylica/cc-skills/commit/ae4fcf948f0a00e99a76eb0b9f16e48b516c46e7))

# [3.0.0](https://github.com/terrylica/cc-skills/compare/v2.30.0...v3.0.0) (2025-12-13)

### Features

- **devops-tools:** add mlflow-python skill with QuantStats integration ([12a4ba7](https://github.com/terrylica/cc-skills/commit/12a4ba7355c01270d21aa5699590e4b7b94132de))

### BREAKING CHANGES

- **devops-tools:** mlflow-query skill deleted without deprecation period

# [2.30.0](https://github.com/terrylica/cc-skills/compare/v2.29.0...v2.30.0) (2025-12-12)

### Features

- **itp:** add plugin-add command for marketplace plugin creation ([6c30ea9](https://github.com/terrylica/cc-skills/commit/6c30ea9648726de4885e5aae852f5dec2732ed4b))

# [2.29.0](https://github.com/terrylica/cc-skills/compare/v2.28.0...v2.29.0) (2025-12-12)

### Features

- **marketplace:** register link-checker plugin and add auto-discovery ([0527f4a](https://github.com/terrylica/cc-skills/commit/0527f4a87760603f72b4a6059d32bb835d6aad4d))

# [2.28.0](https://github.com/terrylica/cc-skills/compare/v2.27.1...v2.28.0) (2025-12-11)

### Features

- **link-checker:** add universal link validation plugin ([#2](https://github.com/terrylica/cc-skills/issues/2)) ([56e9800](https://github.com/terrylica/cc-skills/commit/56e980025c380781698d4daa12cbb5a8bf634d7a))

## [2.27.1](https://github.com/terrylica/cc-skills/compare/v2.27.0...v2.27.1) (2025-12-11)

# [2.27.0](https://github.com/terrylica/cc-skills/compare/v2.26.1...v2.27.0) (2025-12-11)

### Bug Fixes

- **release:** update expected plugin count after skill audit ([0c7d1ed](https://github.com/terrylica/cc-skills/commit/0c7d1eda6d4a28b1f1d9600ccbba3eb7c6205fea))

### Features

- Ruff PostToolUse linting + skill audit cleanup ([#1](https://github.com/terrylica/cc-skills/issues/1)) ([2670f98](https://github.com/terrylica/cc-skills/commit/2670f9816abb8f4ca8d511d79bc3c7533878307b))

## [2.26.1](https://github.com/terrylica/cc-skills/compare/v2.26.0...v2.26.1) (2025-12-11)

# [2.26.0](https://github.com/terrylica/cc-skills/compare/v2.25.0...v2.26.0) (2025-12-10)

### Features

- **clickhouse:** add hub-based skill delegation to architect skill ([aa3a2fe](https://github.com/terrylica/cc-skills/commit/aa3a2feb107cc6d5f1141ca884a719344f704b4b))
- **clickhouse:** add Python driver policy to all ClickHouse skills ([38cee2c](https://github.com/terrylica/cc-skills/commit/38cee2cb9110263e37f36ff35c4796e3c225aae2))

# [2.25.0](https://github.com/terrylica/cc-skills/compare/v2.24.0...v2.25.0) (2025-12-10)

### Features

- **clickhouse:** close documentation gaps in skill ecosystem ([281f491](https://github.com/terrylica/cc-skills/commit/281f49108af2e625f8e25bf07a68cd7f24bb922d))

# [2.24.0](https://github.com/terrylica/cc-skills/compare/v2.23.0...v2.24.0) (2025-12-10)

### Features

- **clickhouse-architect:** add schema documentation guidance for AI understanding ([0653234](https://github.com/terrylica/cc-skills/commit/065323469b2a67ab8b6b0ccfef46a52864c63d41))

# [2.23.0](https://github.com/terrylica/cc-skills/compare/v2.22.1...v2.23.0) (2025-12-10)

### Features

- **itp-hooks:** add workflow-aware graph-easy detection ([c9775ae](https://github.com/terrylica/cc-skills/commit/c9775aec9141e0eeebf6c0089b55d15f0205a57b))

## [2.22.1](https://github.com/terrylica/cc-skills/compare/v2.22.0...v2.22.1) (2025-12-10)

### Bug Fixes

- **itp-hooks:** exempt plan files from ASCII diagram blocking ([6c5aa9b](https://github.com/terrylica/cc-skills/commit/6c5aa9b962aa4e977deb4921cb12675b9ff246bf))

# [2.22.0](https://github.com/terrylica/cc-skills/compare/v2.21.1...v2.22.0) (2025-12-09)

### Bug Fixes

- **quality-tools:** add ALP codec development status to clickhouse-architect ([8ff3525](https://github.com/terrylica/cc-skills/commit/8ff352526b15bdc3c2603aa0e383c6a81c0a74ad)), closes [#91362](https://github.com/terrylica/cc-skills/issues/91362) [#60533](https://github.com/terrylica/cc-skills/issues/60533) [#91362](https://github.com/terrylica/cc-skills/issues/91362)

### Features

- **devops-tools:** add clickhouse-pydantic-config skill ([e171d05](https://github.com/terrylica/cc-skills/commit/e171d05fa61386a363f73fbdf3ce137c603f6ee2))

## [2.21.1](https://github.com/terrylica/cc-skills/compare/v2.21.0...v2.21.1) (2025-12-09)

### Bug Fixes

- **quality-tools:** rectify clickhouse-architect skill based on empirical validation ([33fc270](https://github.com/terrylica/cc-skills/commit/33fc2702d06c97ca66a304d762e4626f0f9f4a14)), closes [#45615](https://github.com/terrylica/cc-skills/issues/45615)

# [2.21.0](https://github.com/terrylica/cc-skills/compare/v2.20.1...v2.21.0) (2025-12-09)

### Features

- **quality-tools:** add clickhouse-architect skill for schema design ([7926523](https://github.com/terrylica/cc-skills/commit/7926523d23948cd7280ca72d3acfe4bf576c836e))

## [2.20.1](https://github.com/terrylica/cc-skills/compare/v2.20.0...v2.20.1) (2025-12-09)

# [2.20.0](https://github.com/terrylica/cc-skills/compare/v2.19.0...v2.20.0) (2025-12-09)

### Bug Fixes

- align documentation with recent releases ([246c179](https://github.com/terrylica/cc-skills/commit/246c179a967bb01b9f8a234a0ac209824f542a31))
- **itp:** clarify Python baseline >=3.11 in mise-configuration ([364fa21](https://github.com/terrylica/cc-skills/commit/364fa21f0d0f300088416602ef537eca7c2e27de))

### Features

- **devops-tools:** add clickhouse-cloud-management skill ([ce1409b](https://github.com/terrylica/cc-skills/commit/ce1409bd67ae3b7e409b42fdc0605fd47789e45e))
- **itp:** add mise-tasks skill with bidirectional cross-references ([7827bde](https://github.com/terrylica/cc-skills/commit/7827bde8777d47bfcf60868896fb5504ae70ebb6))

# [2.19.0](https://github.com/terrylica/cc-skills/compare/v2.18.0...v2.19.0) (2025-12-08)

### Features

- **itp:** polish mise-configuration skill to SOTA best practices ([9113bfa](https://github.com/terrylica/cc-skills/commit/9113bfaa00a91ee935a7502a43e336f0097f3f55))
- **itp:** wire mise-configuration skill into /itp:go workflow ([550be35](https://github.com/terrylica/cc-skills/commit/550be35a3cdfbca1609708aee9db7b0d8d616509))

# [2.18.0](https://github.com/terrylica/cc-skills/compare/v2.17.0...v2.18.0) (2025-12-08)

### Features

- **itp:** add mise [env] as centralized configuration for ITP skills ([140ed67](https://github.com/terrylica/cc-skills/commit/140ed67db176b7f6f1d179d9f14e69901b0788ba))
- **itp:** add mise-configuration skill for env var SSoT pattern ([e202ebf](https://github.com/terrylica/cc-skills/commit/e202ebf507b1d3ca0c269aa40ba6a8b34cc781bc))

# [2.17.0](https://github.com/terrylica/cc-skills/compare/v2.16.2...v2.17.0) (2025-12-08)

### Features

- **itp:** integrate gitleaks into code-hardcode-audit skill ([24dedd4](https://github.com/terrylica/cc-skills/commit/24dedd411df452567bece1626726bd8add769f1b))

## [2.16.2](https://github.com/terrylica/cc-skills/compare/v2.16.1...v2.16.2) (2025-12-08)

### Bug Fixes

- **itp:** clarify version numbers are derived, not hardcoded ([dadb3c3](https://github.com/terrylica/cc-skills/commit/dadb3c36dc790477219039ddcc30d4fe969c014c))

## [2.16.1](https://github.com/terrylica/cc-skills/compare/v2.16.0...v2.16.1) (2025-12-08)

# [2.16.0](https://github.com/terrylica/cc-skills/compare/v2.15.0...v2.16.0) (2025-12-08)

### Features

- **itp:** rename /itp:itp command to /itp:go for shortcut support ([032c240](https://github.com/terrylica/cc-skills/commit/032c240f25ad77b0ae3ac7c335bdcbf879ab8d09))

# [2.15.0](https://github.com/terrylica/cc-skills/compare/v2.14.0...v2.15.0) (2025-12-08)

### Features

- **itp:** add gitleaks secret scanner to setup command ([920fa14](https://github.com/terrylica/cc-skills/commit/920fa14c88ecc39d6afd1aa4a2fec73f9b60cbf2))

# [2.14.0](https://github.com/terrylica/cc-skills/compare/v2.13.0...v2.14.0) (2025-12-07)

### Features

- **scripts:** add idempotency fixes across 8 shell scripts ([40bc880](https://github.com/terrylica/cc-skills/commit/40bc880b33360d6eb0a219606024de2aa1e3f9ec))

# [2.13.0](https://github.com/terrylica/cc-skills/compare/v2.12.1...v2.13.0) (2025-12-07)

### Features

- **itp:** add hooks reminder to setup command ([af34e6e](https://github.com/terrylica/cc-skills/commit/af34e6e42840e1f8db9b16d16ee4fd9b6dd41480))

## [2.12.1](https://github.com/terrylica/cc-skills/compare/v2.12.0...v2.12.1) (2025-12-07)

### Bug Fixes

- **adr:** regenerate diagrams with graph-easy boxart ([b2ee96f](https://github.com/terrylica/cc-skills/commit/b2ee96f762d21e785ec9dbc980cf96b5fd8b9422))

# [2.12.0](https://github.com/terrylica/cc-skills/compare/v2.11.4...v2.12.0) (2025-12-07)

### Features

- **itp:** add /itp hooks command for settings.json hook management ([cf2a675](https://github.com/terrylica/cc-skills/commit/cf2a67546c5a223597ffb70f35c8e286fa88b0e5))

## [2.11.4](https://github.com/terrylica/cc-skills/compare/v2.11.3...v2.11.4) (2025-12-07)

### Bug Fixes

- **itp-hooks:** remove dual hooks config, rely on standalone plugin.json ([fb0c3a4](https://github.com/terrylica/cc-skills/commit/fb0c3a483beed602927af9b8d22a4f3e109ae4d4))

## [2.11.3](https://github.com/terrylica/cc-skills/compare/v2.11.2...v2.11.3) (2025-12-07)

### Bug Fixes

- **itp-hooks:** add plugin.json for standalone hook loading ([dc723cb](https://github.com/terrylica/cc-skills/commit/dc723cbc5d8ae6efec2d1cd133170938a879bbeb))

## [2.11.2](https://github.com/terrylica/cc-skills/compare/v2.11.1...v2.11.2) (2025-12-07)

### Bug Fixes

- **itp-hooks:** add symlink for hooks path resolution ([26b7456](https://github.com/terrylica/cc-skills/commit/26b74560d0b004f97fc641ce9bac0fe6b409f845))

## [2.11.1](https://github.com/terrylica/cc-skills/compare/v2.11.0...v2.11.1) (2025-12-07)

### Bug Fixes

- **itp-hooks:** correct hooks path resolution in marketplace.json ([635f580](https://github.com/terrylica/cc-skills/commit/635f58018e18f3a36b62bdf59a31a9f91cb14311))

# [2.11.0](https://github.com/terrylica/cc-skills/compare/v2.10.2...v2.11.0) (2025-12-06)

### Features

- **itp-hooks:** add as opt-in marketplace plugin ([87202c6](https://github.com/terrylica/cc-skills/commit/87202c6fd5b385d5c1167d6edc7962e85674d17c))

---

## Architecture Decisions

### ADRs

- [ADR: PreToolUse and PostToolUse Hooks for Implementation Standards](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-06-pretooluse-posttooluse-hooks.md) (implemented)

### Design Specs

- [PreToolUse and PostToolUse Hooks](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-06-pretooluse-posttooluse-hooks/spec.md)

## [2.10.2](https://github.com/terrylica/cc-skills/compare/v2.10.1...v2.10.2) (2025-12-06)

## [2.10.1](https://github.com/terrylica/cc-skills/compare/v2.10.0...v2.10.1) (2025-12-06)

### Bug Fixes

- **hooks:** use exit code 2 for hard blocks, move graph-easy to PostToolUse ([18e1922](https://github.com/terrylica/cc-skills/commit/18e1922cbbcbbc8fd1b9774d91c9d642a05e9540))

---

## Architecture Decisions

### ADRs

- [ADR: PreToolUse and PostToolUse Hooks for Implementation Standards](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-06-pretooluse-posttooluse-hooks.md) (implemented)

### Design Specs

- [PreToolUse and PostToolUse Hooks](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-06-pretooluse-posttooluse-hooks/spec.md)

# [2.10.0](https://github.com/terrylica/cc-skills/compare/v2.9.2...v2.10.0) (2025-12-06)

### Features

- **hooks:** add PreToolUse/PostToolUse enforcement for implementation standards ([8fab271](https://github.com/terrylica/cc-skills/commit/8fab27106b51421e0afe11801a264405a6b05e78))

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

- **semantic-release:** use env var for generateNotesCmd to bypass lodash templates ([f0ea53d](https://github.com/terrylica/cc-skills/commit/f0ea53d782a407239446144f1c78a6dabd9162dc))

---

## Architecture Decisions

### ADRs

- [ADR: ADR/Design Spec Links in Release Notes](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-06-release-notes-adr-linking.md) (implemented)

### Design Specs

- [ADR/Design Spec Links in Release Notes](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-06-release-notes-adr-linking/spec.md)

# [2.9.0](https://github.com/terrylica/cc-skills/compare/v2.8.0...v2.9.0) (2025-12-06)

### Bug Fixes

- **semantic-release:** use relative path for generateNotesCmd ([909975e](https://github.com/terrylica/cc-skills/commit/909975e414700a582e3ee7e0334f6e4b8a06b06b))

### Features

- **semantic-release:** add ADR/Design Spec links in release notes ([dc5771b](https://github.com/terrylica/cc-skills/commit/dc5771bbb2a0cd235093d7a03a6b5c6dc8c9e48a))

---

## Architecture Decisions

### ADRs

- [ADR: ADR/Design Spec Links in Release Notes](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-06-release-notes-adr-linking.md) (accepted)

### Design Specs

- [ADR/Design Spec Links in Release Notes](https://github.com/terrylica/cc-skills/blob/main/docs/design/2025-12-06-release-notes-adr-linking/spec.md)

# [2.8.0](https://github.com/terrylica/cc-skills/compare/v2.7.0...v2.8.0) (2025-12-06)

### Features

- **itp:** add plan-aware todo integration (merge, not overwrite) ([c679d24](https://github.com/terrylica/cc-skills/commit/c679d24f0f4ae0c00adf6875baa95eb99d8548d2))

# [2.7.0](https://github.com/terrylica/cc-skills/compare/v2.6.2...v2.7.0) (2025-12-06)

### Bug Fixes

- **mql5com:** convert absolute paths to relative in references ([9576f0e](https://github.com/terrylica/cc-skills/commit/9576f0e860083a5b08788cdb1455f550ba8f1012))

### Code Refactoring

- adopt marketplace.json-only versioning (strict: false) ([9de694c](https://github.com/terrylica/cc-skills/commit/9de694c6988abcc84595deb8aa2b177e2b49088b))

### Features

- **mql5com:** add mql5.com operations plugin with 4 skills ([0e9c34d](https://github.com/terrylica/cc-skills/commit/0e9c34d34dd665fdec576c9fa64bc77e5e438618))
- **plugins:** migrate 12 personal skills to marketplace plugins ([76c9eda](https://github.com/terrylica/cc-skills/commit/76c9edae8736952444cb0980f7d8ada5a85a19cb))

### BREAKING CHANGES

- Individual plugin.json files no longer exist.
  All plugin metadata now comes from marketplace.json only.

## [2.6.2](https://github.com/terrylica/cc-skills/compare/v2.6.1...v2.6.2) (2025-12-06)

### Bug Fixes

- **release:** add individual plugin files to git assets ([17240b9](https://github.com/terrylica/cc-skills/commit/17240b9bcec6e038746dcf1378edbe9b91778445))

## [2.6.1](https://github.com/terrylica/cc-skills/compare/v2.6.0...v2.6.1) (2025-12-06)

### Bug Fixes

- sync individual plugin versions with dynamic discovery ([13cc346](https://github.com/terrylica/cc-skills/commit/13cc346007843c572eba7ed7353a5dea02f434b4))

# [2.6.0](https://github.com/terrylica/cc-skills/compare/v2.5.2...v2.6.0) (2025-12-06)

### Features

- add 6 new plugins to marketplace ([78686fc](https://github.com/terrylica/cc-skills/commit/78686fcd297ce78b55c355facd899e93fba49218))

## [2.5.2](https://github.com/terrylica/cc-skills/compare/v2.5.1...v2.5.2) (2025-12-06)

## [2.5.1](https://github.com/terrylica/cc-skills/compare/v2.5.0...v2.5.1) (2025-12-06)

### Bug Fixes

- **release:** sync version files to 2.5.0 and simplify replace-plugin config ([cd33ae2](https://github.com/terrylica/cc-skills/commit/cd33ae2950abd732fa008a642f95640b9d3509eb))

# [2.5.0](https://github.com/terrylica/cc-skills/compare/v2.4.0...v2.5.0) (2025-12-06)

### Features

- **release:** migrate to semantic-release-replace-plugin for centralized versioning ([61547d5](https://github.com/terrylica/cc-skills/commit/61547d5b0c6ad09c58084d341e409dc14d095748))

# [2.5.0](https://github.com/terrylica/cc-skills/compare/v2.4.0...v2.5.0) (2025-12-06)

### Features

- **release:** migrate to semantic-release-replace-plugin for centralized versioning ([61547d5](https://github.com/terrylica/cc-skills/commit/61547d5b0c6ad09c58084d341e409dc14d095748))

# [2.4.0](https://github.com/terrylica/cc-skills/compare/v2.3.8...v2.4.0) (2025-12-05)

### Features

- **itp:** TodoWrite-driven interactive setup workflow ([92ffe29](https://github.com/terrylica/cc-skills/commit/92ffe29ad737686ecad9894b62c00a4e43cd1647))

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
