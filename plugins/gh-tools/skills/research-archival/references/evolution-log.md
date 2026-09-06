# Evolution Log

Reverse chronological — newest entries on top.

<!-- INVENTED-FALLBACK-OK: this log QUOTES retired code in order to record why it was retired.
     The 2026-08-20 entry names `${OWNER_TYPE:-unknown}` as the pattern the INVENTED-FALLBACK hook
     correctly rejected. It is prose about a deleted line, not a live fallback — the shipped
     identity block in SKILL.md contains no parameter-expansion defaults. Removing the quotation
     would delete the evidence for the fix. -->

## 2026-09-06 — the identity preflight asked the wrong account, in a bare shell

- **Real, reproducible, and it blocked a correct archival.** The preflight runs inside `/usr/bin/env bash << 'IDENTITY_EOF'`. That is a NEW process, so it does not inherit the interactive shell's functions — and on a machine using owner-per-path, `gh` at the prompt is a shell function that sets `GH_CONFIG_DIR` from the per-repository `gh.configdir` git config key. The heredoc called the raw binary instead and got the globally-active account.
- **Measured:** in one directory, `gh api user --jq .login` returned the repository's own account from the interactive shell and a different account from the heredoc. The preflight printed MISMATCH and refused to continue, while `gh api repos/<slug>` from the prompt showed `push=true` for that very repo.
- **Why it was hard to see:** every symptom pointed at a bad credential — a 404 on a private repo is what a wrong token looks like — so the natural response is to hunt for the right token rather than to suspect the shell.
- **Fix:** `cd` into the repository INSIDE the heredoc, and resolve `GH_CONFIG_DIR` from `git config --get gh.configdir` before the first `gh` call, unsetting `GH_TOKEN`/`GITHUB_TOKEN` so an ambient token cannot outrank it. The check no longer depends on which shell invoked it.
- Added a troubleshooting row: differing answers from `gh api user` inside vs outside the heredoc identifies this bug rather than a credential problem.

## 2026-08-21 (later) — Deleting the duplicate was right; the gate that ENFORCED it was a pattern match wearing a guarantee's clothes

- **The one-copy rule shipped with a gate that could not enforce it.** Re-embedding was refused by looking for the legacy `<!-- RAW-SCRAPE-BODY-BEGINS -->` comment. The reviewer defeated it in one move: append the entire pinned transcript after a plain `---`, omit the marker, and the gate returned success — while the test literally named `test_re_embedding_the_transcript_is_refused` stayed green, **because that test built its fixture using the marker**. The check was verified on the one input on which the bug could not appear.
- **The general lesson, and it is the transferable one: a check that pattern-matches a known instance is not a check on the property.** Measured on a sibling project the same week — 7 probes of pattern-matching checks found 6 defects; 28 probes of checks that parse first and then compare found 0. If the invariant is "no second copy", the gate must measure copies, not recognise one historical way of writing one.
- **The fix is the standard measure for near-duplicate detection**: containment over w-shingles, Broder, _"On the resemblance and containment of documents"_, SEQUENCES 1997, `doi:10.1109/SEQUEN.1997.666900`. Containment rather than resemblance because the question is directional; sets rather than Broder's multiset because "how much _distinct_ material was reproduced" is the question; exact rather than sampled because these documents are ~25 KB and sampling error buys nothing.
- **Calibrate the threshold, never choose it.** Measured ladder on the real pair: `0.0097` (the archive's legitimate one-sentence quotation) / `0.0568` one paragraph / `0.1172` a tenth / `0.2577` a quarter / `0.5115` half / `1.0000` the full paste. `0.10` sits ~10× above quoting and below every meaningful paste. **Publish the ladder beside the constant** — an uncalibrated round number reads as a guess and cannot be defended in review.
- **Scope the invariant to the repository, not to one file.** Found by attacking my own fix rather than waiting for the next round: sweeping only the archive that _pins_ the transcript reported success while a sibling `.md` held 100% of it, and twelve fragments each under the limit reconstruct it exactly. Sweep every `*.md` **and** their concatenation.
- **State the limits instead of claiming them away.** A single quoted line must still pass — the archive itself quotes at ~1%, so any threshold refusing one pasted line forbids quotation entirely. And a heavily paraphrased re-embed defeats the measure, because the documents then genuinely differ and no automatic check can rule on whether meaning survived. Same undecidability that killed the normaliser.
- **Citation verification got its own trap.** `textutil -convert txt -stdout` on a PDF returned **exactly the file's byte count** — raw bytes passed through and reported as success — against which any quotation would have "verified" into binary noise. Sanity-check extracted length against page count first. Then, when a match fails, diagnose _which kind_ of failure: ours failed twice, once from a page number the extractor interpolated mid-sentence (quotation faithful) and once because a `'` had been substituted for the source's `"` **inside** quotation marks, which is a modification of quoted text however small.
- Also generalisable, and the reason the docstring now carries an AST tripwire: **the prose that frames a fix goes stale independently of the fix.** The code was corrected and the module docstring went on describing the retired marker as the guarantee — and I asserted the opposite in a public review comment before checking. Machine-check what you can (a refusal branch cannot be added without the documented table failing a count), and be explicit that prose correspondence is not machine-checkable rather than implying it is.

## 2026-08-21 — An archive must be TWO files; embedding the transcript created an undecidable check

- **The skill told you to save one `.md`, and the obvious reading was to paste the scrape into it. That was wrong, and it took five review rounds on `Eon-Labs/alpha-forge` to find out how wrong.** Every archival built this way carries a duplicate of the transcript, and because any repository with markdown tooling reformats `.md` on save, the duplicate can never be byte-identical to the original. So each commit silently posed the question _"is this copy still saying what the original said?"_ — and that question is not answerable by text normalisation.
- **The five bypass classes, in the order they were found**, each a meaning-changing edit that the equivalence checker certified as identical: structural markers erased (a `>` quotation demoted to the author's own assertion; a heading demoted to prose); inline delimiters erased (`` `not` `` reading as the English word "not"); identifiers and URL paths retargeted through `_`, then again through `__`; table cell boundaries moved so an outcome attached to the wrong reference; and literal asterisks consumed inside backslash escapes, tilde- and backtick-fenced code blocks, indented code blocks, and raw HTML attribute values.
- **The last one is a category error, not the fifth bug.** CommonMark 0.31.2 specifies parsing in two phases — _"In the first phase, lines of input are consumed and the block structure of the document … is constructed. Text is assigned to these blocks but not parsed. … In the second phase, the raw text contents of paragraphs and headings are parsed into sequences of Markdown inline elements"_. A line-oriented normaliser has **no block phase**, so it cannot distinguish a paragraph from a fenced code block; emphasis resolution is specified as a **delimiter-stack procedure**, not a pattern; and precedence is context-dependent (_"code spans, autolinks, and raw HTML tags bind more tightly than the brackets in link text"_, _"Backslash escapes do not work in HTML attributes"_). No sixth patch converges. Quotations taken verbatim from `spec.commonmark.org/0.31.2/`, retrieved directly rather than from a summary.
- **The fix is to delete the duplicate, not to parse better.** With one copy there is no equivalence question at all: the gate becomes `sha256(committed bytes) == sha256 pinned in frontmatter`, which has no bypass class because it has no interpretation step, and stays stdlib-only so CI can run it ahead of any dependency install. Both TodoWrite templates and the File Saving section now describe two artifacts.
- **The `.txt` extension is the mechanism, not the belt-and-braces.** Markdown tooling globs `*.md`; a raw scrape kept as `.md` is rewritten and its hash invalidated with nobody touching it. `.prettierignore` and `.gitattributes -text` are worth adding, but they protect only the machines that read the configuration — the extension protects everywhere.
- **Half-declared provenance is the subtle failure, and it is worse than none.** `raw_scrape_path` without `raw_scrape_sha256` looks pinned and is unverified; the hash without the path proves nothing. Discovery must match **either** key, or a half-declaration is not half-checked but _not checked at all_ — an archive pinning a hash and naming no file was silently skipped for a full day.
- Generalisable beyond this skill: **when a check is hard to write, ask whether the artifact should exist**. Five rounds went into making a comparison correct before anyone asked why there were two things to compare.

## 2026-08-20 (later) — The identity preflight printed "Identity verified" while resolving NOTHING

- **A false PASS, which is worse than the false BLOCK fixed earlier the same day.** Run on `terrylica/opendeviationbar-patterns` — a repo the credential legitimately owns — the check printed `Identity verified` having resolved **neither** side. Two independent defects lined up so that the comparison became `"" = ""`, which is true.
- **Defect 1 — the token branch assumed `GH_TOKEN` is in the environment.** `gh` keeps the credential in the **OS keyring**, so on a correctly-configured machine `GH_TOKEN` is normally absent and `curl -H "Authorization: token "` returned empty. Asking `gh api user --jq .login` is not a fallback, it is the ordinary path; it is now the `else` branch, with the token branch kept ahead of it for CI.
- **Defect 2 — the slug regex could not parse an SSH host alias.** This machine's own owner-per-path policy produces remotes like `git@github.com-terrylica:terrylica/repo.git`, where the character following `github.com` is `-`, not `:` or `/`. `github\.com[:/]` matched nothing. An optional `[^:/]*` now consumes the alias suffix. **The policy that makes the guard necessary is the same policy that broke it.**
- **The real fix is neither regex: FAIL CLOSED.** An equality test between two possibly-empty strings reports success by default, so the block now exits non-zero when either side is unresolved, with a per-field diagnostic. _"Identity could not be RESOLVED" and "identity verified" are different states, and only one of them is safe to proceed from._ Verified against the live repo after the fix: resolves `terrylica` / `terrylica/opendeviationbar-patterns` and verifies for a reason.
- Generalisable, and the reason this entry exists rather than a quiet patch: **a guard whose failure mode is silence is indistinguishable from a guard that works.** Prefer comparisons that cannot be satisfied by absence, and assert resolution before asserting agreement.

## 2026-08-20 — Identity preflight could never pass on an ORG repo; backlink template tripped the hard-wrap guard

- **The identity check blocked every legitimate archival into a shared organisation repository.** It was `AUTH_USER != REPO_OWNER → block`, but on an org repo the owner is the **org**, so the comparison can never match however correct the credential is. Measured on `Eon-Labs/alpha-forge`: authenticated `terrylica`, owner `Eon-Labs`, `owner.type = Organization`, `permissions.push = true` — the correct identity, called a mismatch. Fixed by falling through to `owner.type == Organization && permissions.push == true` when equality fails. The equality path is kept as the fast offline case; the org path costs one API call and is only reached on mismatch.
- **Reframed what the guard is actually asking.** Its purpose is to stop writes reaching the _wrong account_; "may this identity write here" is answered by `permissions.push`, not by string equality with the owner. Equality is a sufficient condition, never a necessary one.
- Also hardened the slug parse: `REPO_SLUG` is now captured as `owner/repo` (so the org branch can call `gh api repos/$REPO_SLUG`) with `REPO_OWNER` derived from it, instead of scraping the owner alone.
- **The skill's own canonical backlink template was rejected by `GH-HARD-WRAP-GUARD`.** Four stacked `Key: value` lines are indistinguishable from hard-wrapped prose to the hook, and GitHub renders each newline as `<br>` anyway. Replaced with a markdown list, which states "separate items" structurally — the meaning intended and the form the guard accepts. Explicitly recorded that `GH-HARD-WRAP-OK` is the wrong remedy here: the complaint was correct.
- Added a general rule that **issue and PR bodies must be authored as unbroken paragraphs**, with an `awk` one-liner to check, since soft-wrapping editors hide the problem. Long lines are correct for prose; runs of ~80–100-column lines are the defect.
- The mismatch diagnostic first used `${OWNER_TYPE:-unknown}`, and the `INVENTED-FALLBACK` hook rejected it — correctly. Substituting the word "unknown" reports a value GitHub never sent. Rewritten to print each field **only when present**, plus `gh`'s own exit code and the first line of its stderr when the API call itself failed. Absent is a state, and the honest rendering of a state is nothing at all.
- New troubleshooting rows: the hard-wrap guard; the org-repo identity fall-through; and `gh pr create` reporting "you must first push the current branch" **after a successful push** when run from a linked worktree — pass `--head <branch> --base main` explicitly, and confirm with `git ls-remote --heads origin <branch>` rather than trusting the error.

## 2026-08-13 — Retire self-hosted Firecrawl; route everything JS-rendered to the public API

- The gpu-host-2 deployment was **found alive**, not dead as assumed — HTTP 200 in 21 ms, 5 containers up 5 weeks. Retired deliberately rather than declared dead: containers, images, volumes and build cache removed, reclaiming ~18 GB (61.99 → 44.04 GB). Port 3002 now refuses connections. sub2api and clickhouse-server on the same host were preserved.
- Replaced the health-check + auto-revival + WORKER-STALLED machinery with a single `POST https://api.firecrawl.dev/v2/scrape`. The public API needs no key and has no host to be down, so there is nothing to probe and nothing to restart; failures are handled per request.
- **Reversed the 2026-02-09 decision** to route `chatgpt.com/share/*` to Jina Reader. Measured on two share links: Jina returned 9,397 and 15,960 chars vs Firecrawl's 57,616 and 136,590 — 17% and 12% coverage — and truncated mid-sentence (one ended `"I would spend money on **Synol"`), while Firecrawl reached the true footer. The gap was real content: 76 vs 12 headings, 128 vs 22 table rows. The February escaped-markdown complaint no longer reproduces on v2.
- Jina requires `-H "x-timeout: 30"`; without it a JS-rendered page returns ~321 bytes of login chrome that reads like a successful scrape.
- Switched v1 → v2. Note the `search` shape differs (`v1: data: [...]` vs `v2: data: {web: [...]}`) — do not swap versions without changing the parser.

## 2026-02-13 — Add Firecrawl health check + auto-revival to scraping workflow

- Firecrawl containers can show "Up" while internal processes are dead (RAM/CPU overload: `WORKER STALLED cpuUsage=0.998 memoryUsage=0.858`)
- Added 3-step deep health check: Tailscale ping → API HTTP probe → log inspection
- Added auto-revival: `docker restart` with 20s wait and verification
- Escalation path: restart → force-recreate → manual intervention → Jina fallback
- Added "Container Up but dead" failure mode documentation with diagnosis and fix
- Added troubleshooting rows: "Firecrawl Up but dead", "WORKER STALLED", "Jina login page shell"
- Fixed frontmatter-schema.md: `chatgpt-share` scraper corrected from Firecrawl to Jina Reader (missed in 2026-02-09)
- Discovery: Gemini deep research scrape failed because Firecrawl was dead for 4+ days undetected

## 2026-02-09 — Route ChatGPT shares to Jina Reader

- Firecrawl produced escaped markdown (`\*\*bold\*\*`) and ChatGPT UI chrome for `chatgpt.com/share/*` URLs
- Jina Reader via `curl` produces clean, structured conversation output
- Updated url-routing.md and SKILL.md decision tree
- Gemini shares still route to Firecrawl (untested with Jina)

## 2026-02-09 — Initial creation

- Created from incident: wrong GitHub account posted Issue #6 to `work/example-job-board`
- Skill codifies research archival workflow with mandatory identity preflight
- Companion hook: `gh-repo-identity-guard.mjs` (PreToolUse)
- Three TodoWrite templates: Full Archival (A), Save Only (B), Issue Only (C)
- Bundled references: frontmatter-schema.md, url-routing.md
