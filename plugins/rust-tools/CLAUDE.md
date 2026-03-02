# rust-tools Plugin

> SOTA Rust tooling awareness: refactoring, profiling, benchmarking, testing, SIMD, dependency audit.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [itp-hooks CLAUDE.md](../itp-hooks/CLAUDE.md) | [quality-tools CLAUDE.md](../quality-tools/CLAUDE.md)

## Overview

This plugin fills an LLM knowledge gap: many SOTA Rust tools (cargo-wizard, macerator, cargo-mutants, samply) are niche enough that Claude lacks deep training data on them. The plugin bundles reference documentation and provides a passive once-per-session reminder in any Rust project (detected via `Cargo.toml`).

**Why reference docs**: Skills with bundled references inject tool-specific knowledge into the context window on demand — no internet search required, no hallucinated APIs.

## Skills

| Skill                   | Slash Command                       | Purpose                                                    |
| ----------------------- | ----------------------------------- | ---------------------------------------------------------- |
| `rust-sota-arsenal`     | `/rust-tools:rust-sota-arsenal`     | Refactoring, profiling, benchmarking, testing, SIMD        |
| `rust-dependency-audit` | `/rust-tools:rust-dependency-audit` | Dependency freshness, vulnerability, license, supply chain |

## Hooks

| Hook                             | Event       | Matcher                             | Purpose                                               |
| -------------------------------- | ----------- | ----------------------------------- | ----------------------------------------------------- |
| `posttooluse-rust-sota-reminder` | PostToolUse | Read\|Glob\|Grep\|Bash\|Edit\|Write | Once-per-session SOTA tools reminder in Rust projects |

### Rust SOTA Reminder

On the first tool use in a repo with `Cargo.toml` at the git root, reminds Claude of available SOTA tools and skills. Gates once per session per repo via `/tmp/.claude-rust-sota-reminder/`. Fail-open everywhere.

## Tool Categories

### Refactoring

| Tool                  | Purpose                                                | Install                             |
| --------------------- | ------------------------------------------------------ | ----------------------------------- |
| `ast-grep`            | AST-aware code search and rewrite                      | `cargo install ast-grep`            |
| `cargo-semver-checks` | API compatibility linting (hundreds of built-in lints) | `cargo install cargo-semver-checks` |

### Performance

| Tool           | Purpose                                    | Install                      |
| -------------- | ------------------------------------------ | ---------------------------- |
| `samply`       | Interactive profiler (Firefox Profiler UI) | `cargo install samply`       |
| `cargo-pgo`    | Profile-Guided Optimization workflow       | `cargo install cargo-pgo`    |
| `cargo-wizard` | Auto-configure Cargo profiles              | `cargo install cargo-wizard` |

### Benchmarking

| Tool        | Purpose                         | Install                         |
| ----------- | ------------------------------- | ------------------------------- |
| `divan`     | `#[divan::bench]` attribute API | Add `divan` to dev-dependencies |
| `Criterion` | Statistics-driven benchmarks    | Add `criterion` to dev-deps     |

### Testing

| Tool            | Purpose                                 | Install                       |
| --------------- | --------------------------------------- | ----------------------------- |
| `cargo-nextest` | 3x faster test runner, process-per-test | `cargo install cargo-nextest` |
| `cargo-mutants` | Mutation testing                        | `cargo install cargo-mutants` |
| `cargo-hack`    | Feature flag powerset testing           | `cargo install cargo-hack`    |

### SIMD

| Tool        | Purpose                             | Install                         |
| ----------- | ----------------------------------- | ------------------------------- |
| `macerator` | Type-generic SIMD + multiversioning | Add `macerator` to dependencies |

### Dependencies

| Tool             | Purpose                         | Install                        |
| ---------------- | ------------------------------- | ------------------------------ |
| `cargo-audit`    | RUSTSEC vulnerability scanning  | `cargo install cargo-audit`    |
| `cargo-deny`     | License + advisory + ban checks | `cargo install cargo-deny`     |
| `cargo-vet`      | Mozilla supply chain audit      | `cargo install cargo-vet`      |
| `cargo-outdated` | Dependency freshness            | `cargo install cargo-outdated` |

### Python Bindings

| Tool | Purpose         | Reference               |
| ---- | --------------- | ----------------------- |
| PyO3 | 0.22+ migration | `pyo3-upgrade-guide.md` |

## Behavioral Triggers

Add these to project `CLAUDE.md` files to guide when skills are invoked:

- **Before refactoring**: Consider `ast-grep` for AST-aware search/replace
- **Before publishing a crate**: Run `cargo semver-checks check-release`
- **When benchmarking**: Use `/rust-tools:rust-sota-arsenal` for divan/Criterion guidance
- **Before release**: Run `/rust-tools:rust-dependency-audit` for full audit
- **When optimizing hot loops**: Check macerator for portable SIMD

## References

- [hooks.json](./hooks/hooks.json) — Hook configuration
- [rust-sota-arsenal](./skills/rust-sota-arsenal/SKILL.md) — Main SOTA skill
- [rust-dependency-audit](./skills/rust-dependency-audit/SKILL.md) — Dependency audit skill
