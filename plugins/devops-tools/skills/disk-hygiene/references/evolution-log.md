# Evolution Log

Reverse chronological - newest on top.

## 2026-08-03b — The dependent-service guard checked only the repo ROOT, and a venv can be present but incomplete

**Trigger**: The guard added earlier the same day reported `~/eon/tasc` healthy
(`.venv=ok`, `node_modules=—`) while `com.tasc.serve` had been crash-looping
**11,593 times over ~32 hours**. Both readings were technically true and together
useless.

**Two distinct defects:**

1. **Root-only manifest walk.** The check walks up from the launchd program to the
   FIRST `package.json`/`pyproject.toml` and stops. `tasc` has `pyproject.toml` at
   the root, so it reported `.venv=ok` and treated node deps as not-applicable —
   but the service needs **`ts/node_modules`**, one directory down, which was
   missing (`Cannot find module 'ajv/dist/2020'`, 11,637 log occurrences). Fix:
   enumerate every manifest in the repo (maxdepth 3, excluding `node_modules/` and
   `.venv/`) and check each one's sibling directory.
2. **Present ≠ complete.** After restoring `ts/node_modules` the service still
   failed with `ModuleNotFoundError: No module named 'numpy'`. The `.venv` existed
   and imported `pymupdf` fine, because `uv sync` installs only the DEFAULT
   dependency group; `tasc` declares its embedding deps under
   `[dependency-groups] embed`. Resolved with `uv sync --group embed`. A directory
   existing is not evidence the dependencies are installed.

**Also corrected in this pass**: the crash loop was NOT caused by the disk
cleanup — it began ~2026-08-02 14:00 local, roughly 32 h before. Checking that
before assuming culpability mattered, because the previous entry's incident made
"the cleanup broke it" the tempting default.

**Adversarial verification earned its keep.** Before deleting a 4.48 GB
`TASC 1982-2022` archive from Downloads, a second agent independently re-derived
the redundancy claim: 4,662 PDFs in both locations, **matching MD5 checksums**
sampled across 1982–2022, the repo copy gitignored by design and documented in
its README, and extraction proven one-way (PDF → JSONL is lossy). Verdict
CONFIRMED SAFE, deleted. The same pass **REFUTED** two other "obviously stale"
installers — a MiniMax dmg whose version matched what was installed, and a
`Claude.dmg` whose app had been modified after the download — both kept.

**Measurement note worth carrying**: a `du -sh ~/.Trash` reading of 14G in Phase 1
could not be reproduced later (0B, 0 items, confirmed by `du`, `find`, `ls` and
`stat` agreeing). Cause unestablished. Recorded as unresolved rather than
explained away.

## 2026-08-03 — The biggest win was an app's own quarantined wreckage, and a sparse file lied by 16x

**Trigger**: A full audit two days after the 2026-07-31 pass, which had left the
volume at 61 % / 356 GB free. It was back to **82 % / 167 GB free** — 189 GB
consumed in 48 hours. Phases 1, 2 and 2.5 all came back small (in-repo artifacts
were only 12 GB, down from 109 GB), so the existing phases could not explain it.

**What actually found it**: a plain top-level `du` of `$HOME`, which no phase
prescribed. `~/.mempalace` was **190 GB** — larger than every cache, every repo
and every `Library` subdirectory combined.

**Two new failure modes, both now documented in Phase 3:**

1. **Sparse files make `ls -l` lie.** The offending file reported **2,831 GB
   apparent** against **174 GB allocated** — an impossible number on a 926 GB
   disk. Anything sizing candidates with `ls -l` or `find -size` would have been
   wildly misled; `du` was correct throughout.
2. **Applications quarantine their own wreckage under self-describing names.**
   The 175 GB lived in one directory literally named
   `<uuid>.corrupt-20260802-160712.drift-20260802-160712`. MemPalace had detected
   corruption from a 3-day crash loop, set the collection aside, and rebuilt a
   healthy 882 MB replacement. The disk symptom and a separate 3-day service
   outage were the same root cause. Added a marker-grep (`*corrupt*`, `.drift-*`,
   `.pre-rebuild-*`, `.bak-*`, `.quarantine*`) plus a three-part safety proof
   (no live fd, unreferenced in the app's manifest, healthy replacement exists).

**Also added — the dependent-service check, promoted from a note to a required
step.** The 2026-07-31 pass deleted `catgpt-gateway/node_modules`; its watchdog
then failed 95 times and its restart attempts drove a Chrome launch that raised a
macOS TCC prompt the user reported as a mystery. Phase 2.5 now builds the
exclusion list from `~/Library/LaunchAgents/*.plist` BEFORE deleting, prints each
skip so the guard is visible, and re-asserts the manifest→directory pairing
afterwards. On this run it correctly protected `tasc`, `opendeviationbar-patterns`
and `iterm2-scripts-moon`.

**Evidence**: total reclaimed **219 GB** (730 → 510 GB used, 82 % → 57 % full):
185.75 GB MemPalace (174.53 corrupt quarantine + 11.22 two pre-rebuild backups),
20.05 GB caches (uv 10.40 at `~/.cache/uv`, huggingface 3.91, go-build 3.54,
Homebrew 2.2), 10.53 GB in-repo artifacts. Post-cleanup verification found no new
launchd failures; `com.tasc.serve` exit 1 was pre-existing with 11,593 runs and an
intact `.venv`.

**Sizing datum worth reusing**: a healthy MemPalace index is **~0.5× its source
corpus** (4.05 GB index / 8.43 GB of `~/.claude/projects` JSONL = 0.48×), growing
~0.15 GB/day against ~0.30 GB/day of corpus. Any multiple of that ratio is
pathological, not "a big index".

## 2026-07-31 — Phase 1 read the WRONG VOLUME and under-reported disk use by 70x

**Trigger**: A full audit opened with the skill's own `df -h /`, which reported
**10Gi used, 185Gi avail** — a machine that appeared almost empty. The truth was
**707GB used, 80% full**. On APFS (Catalina onward) `/` is the sealed READ-ONLY
system volume with a fixed ~10GB footprint; all user and application data lives
on `/System/Volumes/Data`. Every number in Phase 1's headline was meaningless,
and an agent trusting it would reasonably conclude there was nothing to clean and
stop before reaching Phase 2.5 — where 109.6 GB of `target/` was waiting.

**Fix**: `df -h /System/Volumes/Data` in Phase 1 and in Template A, with an
inline comment stating why `/` is wrong and citing the measured 10Gi-vs-707GB
discrepancy so the next reader does not "simplify" it back.

**Also corrected**: the uv cache row listed only `~/Library/Caches/uv/`; on this
machine uv kept **21 GB** at `~/.cache/uv/` and the Phase 2 size probe printed
`N/A` while the real cache was the single largest one present. Row now lists both
locations. (`uv cache clean` finds it either way — only the _measurement_ was blind.)

**Evidence**: 2026-07-31 audit, terryli's MBP. Total reclaimed **175.8 GB**
(185GB → 356GB free, 80% → 61% full): 113.9 GB build artifacts, 34.7 GB caches,
27.2 GB retired forks. Largest single item: `fork-tools/flowsurface/target` at
**66 GB, untouched since 2026-03-14**.

**Confirmed still accurate**: the 2026-05-09 heredoc/pueue-hook workaround (used
pre-emptively, worked); the Cargo.toml-sibling guard (correctly skipped
`fork-tools/opengrep/src/target`, a name match with no crate); and the
rustup-pin warning — 1.93/1.94.x/1.95 were pinned by `rust-toolchain.toml` /
`.prototools` files and would have auto-reinstalled, leaving only 1.96.0/1.96.1
safely removable.

## 2026-06-29 — In-repo build artifacts were invisible; added Phase 2.5

**Trigger**: A deep multi-round audit on terryli's MBP had already reclaimed ~140 GB from caches/apps/VMs, yet the largest single category was still untouched because the skill never looked _inside_ repos: 62 GB of Rust `target/` (one repo's `target/` alone was 35 GB) plus 20 GB of Python `.venv` across ~50 repos. The Phase 1/2 scans only walk `~/Library` and the dev-cache dirs, so compiler/dependency output in the code tree was structurally invisible.

**Root cause**: Conceptual gap — the skill modeled "disk hog" as caches (in `~/Library`/`~/.cache`) or loose forgotten files, but not regenerable build output that lives in-repo. On a developer machine this is frequently the #1 consumer.

**Fix**:

- Added **Phase 2.5 - Project Build Artifacts (in-repo, regenerable)** covering Rust `target/`, Python `.venv`, `node_modules`, and zig caches: size table, a ROOTS-based discovery sweep, and safe deletion. Key safety detail baked in: only delete a `target/` that has a sibling `Cargo.toml` (so an unrelated folder named "target" is never nuked), and `pgrep` for a running build first.
- Added a step 3 to Template A (Full Disk Audit) so the artifact scan is part of every audit.
- Added two top rows to Quick Wins (Rust `target/` 10-60 GB+, `.venv` 5-20 GB) — risk "None" but flagged as a cold-rebuild/re-sync cost.

**Evidence**: `rm -rf` of the guarded `target/` set + `.venv` set freed ~76 GB net in one pass (275 GB → 351 GB free), the biggest movement of the entire session.

## 2026-05-15 — Three new high-impact cache vectors discovered

**Trigger**: Second disk audit on terryli's MBP found 21GB in `~/Library/Caches/go-build` plus multi-toolchain accumulation in rustup (8.8GB, 6 versions) and mise installs (7GB) — none of which were in the skill's cache reference table. Skill incorrectly listed `cargo cache -a` as the rustup cleanup; the actual command is `rustup toolchain uninstall <name>`. Mise toolchain pruning wasn't documented at all.

**Root cause**: The skill's cache table predates heavy Go and multi-version-Rust usage. It also confuses `cargo` registry caching with `rustup` toolchain installs (they're distinct concerns at different paths).

**Fix**: Added 3 rows to the Cache Size Reference table:

- `go-build` at `~/Library/Caches/go-build/` — typical 5-25GB on active dev machines; clean with `go clean -cache` (or `rm -rf` as fallback if `go` not on PATH)
- `rustup toolchains` at `~/.rustup/toolchains/` — typical 1-2GB per installed version; list with `rustup toolchain list`, remove with `rustup toolchain uninstall <name>` (NOT `rustup toolchain remove` — that's wrong syntax)
- `mise installs` at `~/.local/share/mise/installs/<tool>/<version>/` — typical 200MB-2GB per version; list with `mise ls`, remove with `mise uninstall <tool>@<version>`

**Evidence**: 2026-05-15 audit. Round 2 reclaim breakdown: go-build 21GB, std cache regrowth 8GB (Homebrew 3.8G + uv 2.5G + sccache 1.6G + npm/pre-commit 0.4G), rustup 1.94 + 1.94.1 = 2.7GB, mise python/3.11 + node/20 = 0.6GB. Total 32GB physical reclaim in one pass.

**Two operational learnings worth surfacing**:

1. **`mise uninstall <tool>@<version>` is the correct command**, NOT `mise toolchain uninstall` or any other variant. Verified on mise 2024+.
2. **Always cross-check stale-toolchain candidates against project `.mise.toml` pins before removal.** Example: removing `node@22.21.1` would have triggered an auto-reinstall on next mise invocation from `~/.claude/` because `~/.claude/.mise.toml` pins `node = "22"`. Skipped that removal mid-cleanup based on this check.

**Bonus finding**: `~/.local/share/tts-debug-wav` accumulated to 11GB in 7 days from Kokoro TTS debug captures (~1.4GB/day generation rate). The pruner was working — retention was just generous. Worth surfacing as a separate non-cache "debug-output growth" vector in future audits.

**Action taken**: Updated Cache Size Reference table (3 new rows + corrected rustup row), updated Quick Wins Summary to include go-build, added the project-pin cross-check note to Troubleshooting.

## 2026-05-09 — pueue hook conflict with heredocs containing spaced paths

**Trigger**: Drilldown bash blocks for `~/Library/Application Support/...` failed with `parse error near TASK_ID=$(pueue add ...` and `(eval):X: unmatched '` after the pueue interception hook tried to wrap them.

**Root cause**: When a `Bash` tool call is intercepted by a pueue submission hook, the hook re-parses the command string. Heredocs that contain `${var}/Path With Spaces/*` or backslash-escaped spaces inside variable expansions break the hook's quoting layer, even though the bash itself is well-formed.

**Fix**: For multi-line drilldowns, write the script to `/tmp/<name>.sh` with the `Write` tool, then invoke as `bash /tmp/<name>.sh`. This bypasses the inline heredoc → hook re-quote path entirely. Single-line `du -sh "$VAR"/path/*` style commands still work fine.

**Evidence**: 2026-05-09 disk audit on terryli's MBP — Chrome / Claude / MacWhisper drilldowns failed twice via heredoc, succeeded immediately when scripted via `/tmp/disk-hygiene-scan.sh`. Reclaim totals were unaffected; 40GB freed across both passes (caches 19GB + selected items 20GB physical).

**Action taken**: Added "pueue hook + heredoc with spaced paths" row to Troubleshooting table in SKILL.md, plus a "Hook-safe multi-line scripts" note in Phase 2.

## 2026-02-08 - Initial creation

- Created skill from real disk audit session
- Benchmarked dust (20.4s), gdu (28.8s), dua-cli (37.1s), ncdu (96.6s) on ~632GB home dir
- Documented cache cleanup workflow: uv (10.8GB), brew (9.4GB), pip (837MB), npm (1.1GB) = ~22GB reclaimed
- Added forgotten file detection patterns (ISOs, video exports, old recordings)
- Added Downloads triage workflow with AskUserQuestion multi-select pattern
- Covers 10 cache types: uv, brew, pip, npm, cargo, rustup, Docker, Playwright, sccache, huggingface
