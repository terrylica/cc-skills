# mise gh CLI Incompatibility with Claude Code

**Date**: 2026-01-12
**Status**: Accepted
**Deciders**: Terry Li

## Context

Installing GitHub CLI (`gh`) via mise causes severe issues when running Claude Code in iTerm2:

- Multiple iTerm2 tabs spawn uncontrollably
- Claude Code sessions multiply unexpectedly
- System resources become exhausted

The exact root cause is unclear, but the mise shim layer appears to interact problematically with Claude Code's process management and/or iTerm2's focus reporting.

## Decision

**Do not install `gh` via mise. Use Homebrew instead.**

### Configuration

In `~/.config/mise/config.toml`:

```toml
# gh: REMOVED - causes iTerm2 tab spawning issues with Claude Code (use Homebrew)
```

### Installation

```bash
# Correct: Homebrew
brew install gh

# WRONG: mise (do not use)
# mise use -g gh@latest
```

## Consequences

### Positive

- Claude Code operates normally without spawning multiple iTerm2 tabs
- System stability maintained during Claude Code sessions

### Negative

- gh version management is handled by Homebrew (auto-upgrades via brew_autoupdate launchd)
- Slight inconsistency in tool management (most tools via mise, gh via Homebrew)

## References

- [iTerm2 Session Spawning Bug #9494](https://github.com/anthropics/claude-code/issues/9494)
- [Multiple Claude Code Instances #9658](https://github.com/anthropics/claude-code/issues/9658)
- [Process Forking Bug](https://shivankaul.com/blog/claude-code-process-exhaustion)
