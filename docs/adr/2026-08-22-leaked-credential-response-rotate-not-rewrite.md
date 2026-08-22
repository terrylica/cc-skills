# Rotate a leaked credential; do not rewrite public history

- **Status**: Accepted
- **Date**: 2026-08-22
- **Context**: [#89](https://github.com/terrylica/cc-skills/issues/89) — a MiniMax API key was committed in `plugins/devops-tools/skills/claude-code-proxy-patterns/references/launchd-configuration.md` and reported by an external scanner.

## Decision

When a credential reaches a public commit in this repository:

1. **Rotate it at the provider immediately.** Treat it as burned from the moment it was pushed.
2. **Remove it from the working tree** and replace it with a placeholder that cannot be mistaken for a real value.
3. **Do not rewrite git history.** No `filter-repo`, no BFG, no force-push.
4. **Record the incident** in the issue and close it once rotation is confirmed.

## Why history is not rewritten

A rewrite is destructive and does not achieve the thing it appears to achieve.

- **It does not un-leak the key.** The commit was public. Clones, forks, GitHub's own fork network, and any scanner that already indexed it retain the blob. The scanner that filed #89 is proof the value was harvested. Only rotation revokes it.
- **It breaks every consumer.** This marketplace is installed by SHA from `~/.claude/plugins/`. Force-pushing invalidates existing clones, forks, and any pinned commit, and rewrites 27+ release tags — real breakage for users, in exchange for no security gain.
- **The cost lands on the wrong people.** Users pay the disruption; the attacker, who already has the key, pays nothing.

The security property is delivered entirely by step 1. Steps 2–4 are hygiene and disclosure.

## Consequences

- `CHANGELOG.md` and history keep their references. History is a record of what happened; scrubbing it would also destroy provenance that this repo's own doctrine depends on.
- Prevention lives at the commit boundary, not in cleanup: see the gitleaks integration ([ADR 2025-12-07](./2025-12-07-gitleaks-setup-integration.md)) and the self-custody vault, which exist so a real value never reaches a file in the first place.
- Any documentation example that resembles a credential must be an obvious placeholder — truncated (`eyJhbGciOi...`), or a named stand-in. Never paste a live value "temporarily".

## Scope

Repository-local. This governs cc-skills' own incident response. It is not a claim about how any other repository should handle leaked credentials.
