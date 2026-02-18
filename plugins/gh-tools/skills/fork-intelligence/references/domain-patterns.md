# Domain-Specific Fork Patterns

Fork behavior varies significantly by project domain. These patterns were identified across 10 repositories.

## Scientific/ML Libraries

**Repos studied**: pymoo (459 forks), kokoro (650 forks), tensortrade (1,191 forks)

**Key pattern**: Researchers fork, implement their algorithm, publish a paper, and move on — with zero social engagement. No stars, no issues, no PRs. The fork exists only as a code artifact of their research.

**Signals to prioritize**:

- New files in algorithm/model directories (not just config changes)
- Academic email domains in commit authors
- Commit messages referencing paper titles, arXiv IDs, or conference names
- Large file-count changes (pymoo/AnonymeMeow: 300 files, 2 new PSO algorithms, 0 stars)

**Traps to avoid**:

- Highest-starred fork is often a pure mirror (pymoo: 26-star msu-coinlab = zero original commits)
- Jupyter notebooks committed to forks are usually personal experiments, not reusable features
- "Framework" renames (changing project name in README) with no code changes

**Fork types by frequency**:

1. Algorithm implementations (most valuable, hardest to find)
2. Benchmark/dataset additions
3. Personal experiment notebooks (low value)
4. Course assignment submissions (no value)

## Trading/Finance

**Repos studied**: backtesting.py (1,392 forks), barter-rs (312 forks), flowsurface (225 forks), dukascopy-node (105 forks), tensortrade (1,191 forks)

**Key pattern**: Exchange connector additions dominate. The most valuable fork work is in private repositories (trading firms keep alpha-generating code private).

**Signals to prioritize**:

- New exchange adapter files (e.g., `bybit.rs`, `deribit.rs`)
- Data format additions (Parquet, streaming APIs)
- Performance optimizations (batching, Rust rewrites)
- Alternative bar types (tick-volume, range bars)

**Cross-fork convergence is especially useful**:

- barter-rs: 4 independent Bybit implementations signals a critical exchange gap
- dukascopy-node: Memory problem spawned streaming API fork
- flowsurface: 3 forks independently added technical indicators

**Traps to avoid**:

- Forks with committed API keys or credentials (security risk, not a feature)
- "Strategy" forks that just add a trading strategy notebook (personal, not reusable)
- Private forks are fundamentally invisible — accepted limitation

## Infrastructure/DevTools

**Repos studied**: pueue (152 forks), firecrawl (6,077 forks)

**Key pattern**: Self-hosting and SaaS-removal is the dominant fork motivation for SaaS tools. CLI tools get "superset" forks that add new subcommands.

**Signals to prioritize**:

- Docker/deployment config changes (high value for operators)
- SaaS dependency removal (firecrawl: devflowinc/firecrawl-simple with 630 stars)
- New CLI subcommands (pueue/freesrz93: 7 new subcommands)
- Release presence (strongest signal — only freesrz93 had releases, and it was the most substantive pueue fork)

**Fork types by frequency**:

1. Self-hosting adaptations (most common for SaaS tools)
2. Feature supersets (new subcommands, options)
3. Integration adapters (NATS, message buses, cloud storage)
4. Deployment/packaging (systemd, Docker, Helm charts)

**Traps to avoid**:

- Install scripts that look like features but are just automation wrappers
- "Awesome" or "starter" forks that rename the project but add nothing

## C++/Python Mixed Codebases

**Repos studied**: ArcticDB (165 forks)

**Key pattern**: Feature work almost exclusively lives on branches (not default branch). Enterprise internal forks expose company development roadmaps. Branch count is the strongest initial signal.

**Signals to prioritize**:

- Branch count > 10 (ArcticDB: Rohan-flutterint had 197 branches of Man Group internal work)
- `CMakeLists.txt` and build system changes (platform enablement)
- Protobuf schema changes (architectural features)
- Commit email domains (`@man.com`, `@quantstack.net` reveal institutional contributors)
- Custom release tags with company suffixes (`+man0`)

**Enterprise fork indicators**:

- Structured branch naming (`enhancement/`, `bugfix/`, `feature/`)
- Commit messages referencing internal ticket systems (e.g., "AN-912")
- Release candidate tags
- Multiple contributors with same email domain

**Traps to avoid**:

- "Mirror" forks with 100+ branches may be automated CI/CD artifacts, not manual work
- Maintainer dev forks (branch names map 1:1 to upstream PRs) — flag and exclude from independent work analysis
- Build-only forks that only change CI/CD without touching source code

## Node.js Libraries

**Repos studied**: dukascopy-node (105 forks)

**Key pattern**: Fork ecosystem is extremely flat — no fork has more than 1 star. npm publication as a separate package is the strongest signal of independent project status.

**Signals to prioritize**:

- npm publication check (dukascopy-node: kyo06 published `dukascopy-node-plus`)
- `package.json` name/version changes
- New output format support (Parquet, streaming)
- Feature branch naming conventions matching upstream (`feat/`, `fix/`)

**Traps to avoid**:

- Scoped package republications (`@user/package`) that are just mirrors
- Forks with only `package-lock.json` changes (dependency bumps, not features)

## Rust Projects

**Repos studied**: barter-rs (312 forks), pueue (152 forks), flowsurface (225 forks)

**Key pattern**: `Cargo.toml` diff is a reliable quick filter for genuine feature work. Feature branches are common. Compilation requirements mean forks that build successfully represent real effort.

**Signals to prioritize**:

- `Cargo.toml` dependency additions (new crate = new feature)
- New module files (`.rs` files in `src/`)
- Workspace member additions
- Feature flag additions in `Cargo.toml`

**Traps to avoid**:

- `Cargo.lock` changes alone (just dependency resolution updates)
- Clippy/formatting-only commits
- Legacy Python-era forks (some Rust rewrites of Python projects have incompatible old forks)
