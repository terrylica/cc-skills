# Empirical Data — Stars Anti-Correlation

Quantitative findings from fork analysis across 10 repositories, February 2026.

## Aggregate Finding

**Stars-only filtering misses 60-100% of substantive forks in every repository tested.**

## Per-Repository Data

| Repository     | Language   | Upstream Stars | Total Forks | Substantive Forks | Stars-Only Miss Rate                            |
| -------------- | ---------- | -------------- | ----------- | ----------------- | ----------------------------------------------- |
| tensortrade    | Python     | 4,500          | 1,191       | 2                 | ~100% (1 of 2 has 0 stars)                      |
| backtesting.py | Python     | 7,939          | 1,392       | 20                | 58% (7/12 top forks = 0 stars)                  |
| kokoro         | Python/ML  | 5,692          | 650         | 37                | 57% (20/35 = 0 stars)                           |
| pymoo          | Python/Sci | 2,778          | 459         | 22                | ~95% (26-star fork = pure mirror)               |
| firecrawl      | TypeScript | 83,642         | 6,077       | 22                | 67% (10/15 top = 0 stars)                       |
| barter-rs      | Rust       | 1,947          | 312         | 12                | ~90% (1-star fork = only starred one with work) |
| pueue          | Rust       | 6,050          | 152         | 10                | 100% (ALL substantive forks = 0 stars)          |
| dukascopy-node | Node.js    | 698            | 105         | ~12               | ~80%                                            |
| ArcticDB       | C++/Python | 2,182          | 165         | 14                | 100% (starred forks are all mirrors)            |
| flowsurface    | Rust       | 1,359          | 225         | 12                | 67% (8/12 = 0 stars)                            |

## Highest-Starred Fork vs Actual Value

Across all 10 repos, the highest-starred fork was often a pure mirror:

| Repository     | Highest-Starred Fork | Stars | Actual Value                     |
| -------------- | -------------------- | ----- | -------------------------------- |
| pymoo          | msu-coinlab          | 26    | Pure mirror, 0 original commits  |
| ArcticDB       | GaochaoZhu           | 2     | Pure mirror, 0 original commits  |
| pueue          | max-sixty            | 2     | Just a README link fix           |
| backtesting.py | oliver-zehentleitner | 52    | Mostly packaging/docs, thin code |
| tensortrade    | aaron-makowski       | 35    | Zero divergence                  |

## Most Valuable Forks (All 0 Stars)

| Repository     | Fork             | What They Built                                                  | Stars |
| -------------- | ---------------- | ---------------------------------------------------------------- | ----- |
| pymoo          | AnonymeMeow      | 300 files changed, 2 new PSO algorithms                          | 0     |
| pueue          | freesrz93        | 7 new subcommands, 6 releases                                    | 0     |
| ArcticDB       | DerThorsten      | 147 commits of conda/Clang/Apple platform enablement             | 0     |
| ArcticDB       | Rohan-flutterint | 197 branches of Man Group internal features                      | 0     |
| dukascopy-node | kyo06            | Streaming API solving #1 pain point, npm-published               | 0     |
| flowsurface    | GentlemanHu      | 65 commits, MetaTrader 5 integration in 3 languages              | 0     |
| kokoro         | PerfectRec       | Full batched inference implementation                            | 0     |
| backtesting.py | sustago          | 33 commits, OpenBox optimizer + Latin Hypercube sampling         | 0     |
| firecrawl      | aezizhu          | Most technically sophisticated fork, Patchright + anti-detection | 0     |
| barter-rs      | jfuechsl         | Deribit exchange + macro framework, 48 ahead                     | 0     |

## Blind Spots Discovered

| Blind Spot                                 | Repos Affected                 | Fix Applied                                                 |
| ------------------------------------------ | ------------------------------ | ----------------------------------------------------------- |
| Non-default branches                       | ALL 10                         | Step 4 — branch enumeration for every fork with recent push |
| Merge commit inflation                     | 6/10                           | Subtract merge commits from ahead_by count                  |
| Rebased/force-pushed branches              | ArcticDB, pueue                | Cross-reference upstream PR history as backup               |
| Stars anti-correlation                     | ALL                            | Never use stars as primary filter                           |
| Mirror forks with internal branches        | ArcticDB                       | Check branch count (>10 = suspicious)                       |
| Cross-fork convergence                     | firecrawl, flowsurface, kokoro | Compare themes across top forks                             |
| Commit email domain analysis               | ArcticDB, pymoo                | Check `@company.com` emails                                 |
| Private/non-GitHub forks                   | barter-rs                      | Fundamentally invisible — accepted limitation               |
| Timestamp clustering as mirrors            | ALL                            | Forks sharing exact pushed_at = skip                        |
| Force-pushed branches breaking compare API | pueue                          | PR history is the only evidence                             |
| Maintainer dev forks                       | dukascopy-node                 | Branch names mapping 1:1 to upstream PRs                    |
| GitHub compare API 250-commit limit        | barter-rs                      | May truncate highly divergent forks                         |

## Key Insight: Non-Default Branches

The single biggest methodology improvement. Examples of work ONLY on feature branches:

- **flowsurface/aviu16**: 7,000-line GPU shader heatmap on `shader-heatmap` branch
- **backtesting.py/blue-int**: Critical CAGR math bug fix on `fix/cagr-and-annualized-return`
- **ArcticDB/DerThorsten**: 147 commits across `conda_build`, `clang`, `apple_changes`
- **barter-rs**: 6 of 12 top forks had work only on feature branches
- **pueue/FrancescElies**: Duration display feature on `cesc/duration`
- **dukascopy-node**: Top 3 most interesting forks had zero divergence on default branch
