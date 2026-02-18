# Signal Priority Reference

Empirical ranking of fork analysis signals, validated across 10 repositories.

## Rank 1: Branch-Level Divergence

**Why it's #1**: Across all 10 repos, 50%+ of the most valuable fork work lived exclusively on feature branches, invisible to default-branch-only analysis.

**Technique**: List all branches on each fork, then compare each non-default branch against upstream.

```bash
gh api "repos/FORK_OWNER/REPO/branches" --jq '.[].name'
gh api "repos/$UPSTREAM/compare/$BRANCH...FORK_OWNER:FEATURE_BRANCH" --jq '{ahead_by, status}'
```

**Evidence**:

- flowsurface/aviu16: 7,000-line GPU shader heatmap only on `shader-heatmap`
- ArcticDB/DerThorsten: 147 commits across `conda_build`, `clang`, `apple_changes`
- pueue/FrancescElies: Duration display only on `cesc/duration`
- backtesting.py/blue-int: Critical CAGR math fix only on `fix/cagr-and-annualized-return`
- barter-rs: 6 of 12 top forks had work only on feature branches
- dukascopy-node: Top 3 forks had zero divergence on default branch

## Rank 2: Upstream PR Cross-Reference

**Why it's #2**: The compare API breaks when branches are rebased or force-pushed. The only evidence of this work is in the upstream PR history.

**Technique**: List all PRs from fork authors against upstream.

```bash
gh api "repos/$UPSTREAM/pulls?state=all" --paginate \
  --jq '.[] | select(.head.repo.fork) | {number, title, state, user: .user.login}'
```

**What it catches**:

- Rebased work (pueue: ActuallyHappening's tracing-eyre refactor showed 0 ahead, but PR #604 had 421 additions)
- Merged contributions (forks show 0 ahead because work was accepted upstream)
- Declined PRs with valuable code the fork still maintains

**Evidence**:

- ArcticDB: mjpieters had 11 merged PRs but 0 ahead on all branches
- pueue: Mephistophiles had 3 PRs (dashboard, dark colors, clean-by-group)
- kokoro: 18 PRs from fork authors merged upstream

## Rank 3: Tags/Releases on Fork

**Why it's #3**: The strongest signal of independent maintenance intent. Forks with their own release cycle are effectively independent projects.

```bash
gh api "repos/FORK_OWNER/REPO/tags" --jq '.[].name' | head -10
gh api "repos/FORK_OWNER/REPO/releases" --jq '.[] | {tag_name, published_at}' | head -5
```

**Evidence**:

- pueue/freesrz93: 6 releases spanning v5.x series, 7 new subcommands — the most substantive fork <!-- SSoT-OK: fork release tag names, not this repo's versions -->
- ArcticDB/ShabbirHasan1: RC tags revealing Man Group internal release cycle
- ArcticDB/qc00: Pre-release tags for Apple Silicon builds

## Rank 4: Commit Email Domains

**Why it's #4**: Institutional contributors often work on forks without any social engagement (no stars, no issues). Email domains are the only signal.

```bash
gh api "repos/$UPSTREAM/compare/$BRANCH...FORK_OWNER:BRANCH" \
  --jq '.commits[].commit.author.email' | sort -u
```

**Evidence**:

- ArcticDB: `@man.com` (Man Group employees), `@quantstack.net` (QuantStack engineers)
- pymoo: University emails on algorithm implementation forks
- firecrawl: Company domains on self-hosting forks

## Rank 5: Timestamp Clustering

**Why it's #5**: Bulk elimination of noise. Forks sharing exact `pushed_at` with upstream or with each other are mirrors created and abandoned.

```bash
gh api "repos/$UPSTREAM/forks" --paginate \
  --jq '.[] | {full_name, pushed_at}' | \
  jq -s 'group_by(.pushed_at) | map({pushed_at: .[0].pushed_at, count: length, forks: [.[].full_name]}) | sort_by(.count) | reverse'
```

**Evidence**: Eliminates 85%+ of all forks across every repository tested.

## Rank 6: Cross-Fork Convergence

**Why it's #6**: When 3+ forks independently solve the same problem, it reveals unmet upstream demand — useful for roadmap decisions.

**Technique**: After analyzing individual forks, group by theme/feature area.

**Evidence**:

- firecrawl: 3 forks adopted Patchright for stealth browsing
- flowsurface: 3 forks added technical indicators independently
- barter-rs: 4 forks added Bybit exchange support
- kokoro: 2 independent batched inference implementations

## Rank 7: Stars (Last Resort)

**Why it's last**: Empirically anti-correlated with actual fork value in every repository tested.

**Evidence**:

| Repository     | Highest-Starred Fork            | Its Value                       |
| -------------- | ------------------------------- | ------------------------------- |
| pymoo          | msu-coinlab (26 stars)          | Pure mirror, 0 original commits |
| ArcticDB       | GaochaoZhu (2 stars)            | Pure mirror, 0 original commits |
| pueue          | max-sixty (2 stars)             | Just a README link fix          |
| backtesting.py | oliver-zehentleitner (52 stars) | Mostly packaging, thin code     |
| tensortrade    | aaron-makowski (35 stars)       | Zero divergence                 |

Meanwhile the most valuable forks consistently had 0 stars:

- pymoo/AnonymeMeow: 300 files changed, 2 new PSO algorithms
- pueue/freesrz93: 7 new subcommands, 6 releases
- ArcticDB/DerThorsten: 147 commits of platform enablement
- dukascopy-node/kyo06: Streaming API, npm-published

**When stars ARE useful**: As a tiebreaker between two forks with similar divergence, or to identify "community champion" forks that serve as social hubs (e.g., firecrawl/devflowinc-simple with 630 stars).
