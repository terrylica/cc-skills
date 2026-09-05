<!-- Delete a section only if it genuinely does not apply, and replace it with one line saying why. A blank section reads as "not done", not as "not applicable". -->

## What changed, and why

<!-- One paragraph. Lead with the defect or the goal, not with the diff — the diff is already below. -->

## Evidence

<!-- REQUIRED whenever this PR asserts something about the world outside this repository: a tool's behaviour, a spec, an upstream bug, a benchmark number, a "this is the recommended approach" claim, or the reason a plausible alternative was rejected. -->

<!-- Every such claim needs a verbatim quote AND the URL it came from, fetched and checked this session. A bare link is not evidence — it asks the reviewer to go and find the supporting sentence, which is exactly the work the citation was supposed to do for them. -->

<!-- A claim about THIS codebase is evidenced with `file:line` and the real output of the command that proves it, never with a URL. -->

<!-- Known failure mode, measured: a citation can be a real quote from a real source and still be wrong, because it supports a claim of a different SCOPE or the opposite DIRECTION. Check that the quote supports the specific claim you attached it to. -->

| Claim | Verbatim quote | Source |
| ----- | -------------- | ------ |
|       |                |        |

## Verification

<!-- The command you actually ran, and its real output. Quality gates run LOCALLY in this repo — GitHub Actions is reserved for semantic-release, CodeQL, Dependabot and deployment, so a green PR page proves nothing about tests. -->

```console
moon run repo:check
```

## Issues

<!-- Each issue needs its OWN keyword: `Closes #1, #2, #3` closes only #1. Use `Closes`, `Fixes` or `Resolves` in this body (not the title). Cross-repo form is `Closes owner/repo#N`. Use `Refs #N` for an issue this PR informs but does not resolve. -->

Closes #

## Labels

- [ ] An `area:*` label is set, so this PR is findable by subject later
- [ ] A `priority:*` label is set if this is tracked work
- [ ] Any issue this PR closes carries the same `area:*` label
