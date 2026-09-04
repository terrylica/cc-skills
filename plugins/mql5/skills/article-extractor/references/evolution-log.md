# Evolution Log

> **Convention**: Reverse chronological order (newest on top, oldest at bottom). Prepend new entries.

---

## 2026-09-03 (later): Adversarial review of the above — six real defects found and fixed

An adversarial review pass over the changes below found that several of them were wrong or incomplete. Recording what the first pass got wrong, because most of it was self-verification that could not fail.

**1. 🔴 The backfill silently skipped 27 of 748 article directories — and `--verify` could not see it.** `iter_article_dirs()` assumed a two-level layout (`<user>/article_<id>/`), but topic collections nest deeper (`python_integration/user_articles/<author>/article_<id>/`). 265 labels stayed stale. Because `--verify` walked the _same_ truncated iterator, it printed "PASS - corpus agrees with the detector" over directories it never opened. **A verify gate that shares its traversal with the thing it verifies cannot fail.** Now uses `rglob`; coverage went 721 → 748 dirs, 594 → 620 articles, 14,418 → 15,192 blocks.

**2. 🔴 `pytest tests/` made LIVE requests to mql5.com.** `tests/test_attachment_simple.py::test_attachment_extraction` is a plain sync function that downloads two ZIPs; the missing `pytest-asyncio` that neutralised the other two did NOT protect it. Running the suite violated the repo's cardinal constraint. Fixed with a `network` marker and `addopts = "-m 'not network'"` in `pyproject.toml`, so opting in is explicit. **Audit what a test suite does before running it against a rate-limited origin.**

**3. HTTP 4xx became retryable.** Playwright's `page.goto` does not raise on error status, so a dead article failed fast via `ValidationError`. `raise_for_status` turned 404/403/429 into generic exceptions the retry loop repeated 3× with backoff — i.e. answering a block signal with two more requests. Added `PermanentExtractionError`: 4xx fails immediately, 5xx stays retryable. Covered by tests.

**4. The new tests could not catch the regression they were written for.** `tests/test_extractor_parsing.py` loads the fixture with `Path.read_text()`, whose universal-newline translation strips all 962 CRs before any assertion runs — so deleting the CRLF normalisation left every test green. Added `tests/test_fetch_path.py`, which drives the real fetch path through an `httpx.MockTransport` and reads the fixture as **bytes**. Mutation-tested: removing the normalisation now fails the suite.

**5. Attachment downloader defects.** (a) Collision dedupe used a case-sensitive `set` on a case- and normalisation-insensitive volume, so `Expert.mq5` + `expert.mq5` silently clobbered one another while the manifest claimed both were saved — now folds with NFC + casefold, and splits on the last dot so `archive.tar.gz` suffixes correctly. (b) The binary-skip policy read only the remote link _text_, which is independent of the href, so `<a href=".../payload.ex5">Expert.mq5</a>` defeated it — now checks the URL too. (c) The size cap read `Content-Length` then buffered the whole body, but httpx transparently decodes gzip, so a compliant-looking header could decompress ~1000× — now accumulates chunk-wise and stops at the cap. (d) An attachment failure re-raised past `_save_results`, discarding a fully-extracted article; attachments are supplementary and now degrade gracefully.

**6. Two markdown fences were left stranded at `javascript`** after their metadata was relabelled, because the 2025-10-29 formatter re-wrapped the bodies so they no longer matched. Unmatched fences with a non-empty info-string are now re-detected from the fence body itself (empty ones stay untouched — those are prose wrappers). This surfaced a genuine detector gap: re-wrapped multi-line calls read as non-code, so `\w::\w` (C++/MQL5 scope resolution, which Python has no equivalent of) is now a strong MQL5 signal. That corrected a further 69 blocks (39 `python`, 30 `text` → `mql5`), all verified as C++ constructor initialiser lists and method definitions.

Also fixed: eight docs still asserted Playwright drives article extraction (including the module table in the very file updated below); `setup.sh` did not install `pytest`, so the "must stay green" regression controls were unrunnable after a clean setup; `content.attachments` was write-only (now reported by the CLI and tallied in batch stats); and `config.yaml` documented the credential as inert without recording the one action that mitigates it — rotating it at mql5.com.

Final state: 620 articles / 15,192 blocks, `mql5` 12,269 · `python` 2,187 · `text` 736, zero `javascript` anywhere, 36 offline tests passing, 3 network tests deselected by default.

---

## 2026-09-03: Article fetch moved off Playwright; attachments captured; corpus backfilled

Four changes shipped together after a read-only recon pass. All verified against the 594-article local corpus.

> **Superseded in part** by the review entry above — the corpus figures here (594 articles, 2,151 labels, "javascript 22 → 0") were measured with the truncated directory walk and undercount the corpus. See above for the corrected numbers.

**1. Article fetch is now plain httpx, not a browser.** Parity was proven byte-identical (title, author, user_id, word_count, all 31 code blocks with content _and_ language, images, full `main_content`). Chromium cost 0.81 s per article in launch overhead alone; a full extraction now runs in ~2 s. `lib/extractor.py` no longer imports Playwright. `_extract_with_playwright` was renamed `_extract_article_page`.

🔴 **CRLF trap — the one real regression this introduced.** mql5.com serves **CRLF**; Playwright's `page.content()` silently normalised it to LF, so the whole stored corpus has LF. `httpx.Response.text` preserves CRLF, so the first httpx extraction differed from the stored article by invisible `\r` characters in every code block. Fixed with an explicit `.replace("\r\n", "\n")`. Note the earlier parity test _missed_ this because reading the saved page with Python's text-mode `open()` applies universal-newline translation — a parity test that loads HTML in text mode cannot see a line-ending regression.

**2. Discovery KEEPS Playwright.** Do not "finish the job" by removing it there. The publications list pages via an inline `onclick="…LoadPublications…"` handler with no query-string equivalent; a plain GET returns ~10 articles and stops (confirmed live), while the corpus holds 155 articles for a single author. A future win exists — replicate the `LoadPublications` XHR — but it is unproven.

**3. Attachments are captured.** `attachments/` + `attachments_manifest.json`, mirroring the images pattern. Selector `div.attachBlock a[href^="/en/articles/download/"]` — real attachments are root-relative, every decoy is absolute on another host (3 real / 0 of 18 decoys, vs 21 for a naive `a[href*="download"]`). 96% of corpus articles have attachments. The grouped ZIP is recorded but not downloaded when individual files exist. Downloads need no auth. The markdown header gained an `**Attachments:**` line.

**4. Corpus backfilled** via the new `scripts/backfill_code_block_languages.py` (`--dry-run` / `--apply` / `--verify`). 333 articles rewritten, 2,151 labels corrected. It patches fences **in place** and never regenerates markdown from metadata — a 2025-10-29 formatting pass touched 600/606 `.md` files and metadata does not record it, so regeneration would silently revert it. Fences are matched to blocks **by content, not index** (61 articles have fewer fences than blocks). Proven safe: sampling 60 files against a pre-change backup, 27 changed and every changed line was a fence line. `--verify` now reports 0 disagreements corpus-wide.

**5. Credentials removed** from the tracked `config.yaml`. They were provably inert: `ConfigManager._dict_to_config` builds `Config(...)` from six sections and omits `authentication`, so the dataclass default wins and the loaded value is always `enabled=False` — its only consumer, the login path at `discovery.py:80`, is unreachable. The secret remains in git history (commit `acc0cc3`); rotation at mql5.com is the actual fix and is an operator action.

---

## 2026-09-03: Code-block language detection rewritten; MQL5-by-default assumption retired

**Trigger**: Extracting article 20535 ("Combining LLM, CatBoost, and Quantum Computing into a Unified Trading System", author `koshtenko`) produced 27 blocks labelled `mql5` in an article that contains **zero MQL5 code**.

**Root cause**: `lib/extractor.py::_detect_language` assumed "all code in `<pre class='code'>` on mql5.com is MQL5", tested only `def \w+(` for Python, and defaulted everything else to `mql5`. That assumption predates the Python/ML article generation. It also mislabelled MQL5 header banners as `javascript` whenever the word "function" appeared in a comment.

**Measured blast radius** (594 already-extracted articles, 14,418 code blocks):

| Label        | Before | After  |
| ------------ | ------ | ------ |
| `mql5`       | 13,969 | 11,834 |
| `python`     | 427    | 1,894  |
| `text` (new) | 0      | 690    |
| `javascript` | 22     | 0      |

1,470 Python blocks and 690 non-code blocks had been filed as MQL5.

**Fix**: signal-scored detection (strong/weak marker sets per language, structural code test, `label: value` console-output test), with `mql5` retained only as the final tiebreak. New `text` value marks blocks that are not source at all — console output, shell transcripts, LLM prompt/response logs, results tables — which mql5.com renders in the same `<pre class="code">` element as real code.

**Regression controls** (must stay green when touching this function):

- article 14261 (classic MQL5 EA): 36/36 `mql5`, unchanged
- article 16045 (MQL5 GUI/`CDialog`): 42/42 `mql5`, unchanged — guards the `class X : public Y` vs Python `class X(Y):` distinction
- articles 10664/11752/11804/17044: `#ifdef`/`#endif` blocks stay `mql5` — guards C preprocessor directives against the `#`-comment Python tiebreak
- article 20535: 22 `python` / 9 `text` / **0 `mql5`**

**Downstream note**: `language` may now be `text`. Consumers filtering `language == "mql5"` will see a smaller, more accurate set; consumers wanting "all source" should filter `language != "text"`.

**Files affected**: `lib/extractor.py` (in `terrylica/mql5-local`).

---

## 2026-09-03: mql5.com article pages are static — Playwright is not required to parse them

**Finding**: Article pages are server-side rendered. A plain `curl` with a browser User-Agent returns HTTP 200 with the complete article (verified on 20535: 7,319 words, 31 `pre.code` blocks, `.content` present) in ~1.3 s, with **no login and no bot challenge** — despite `config.yaml` carrying mql5.com credentials with `authentication.enabled: true`.

**Parity test**: feeding curl-captured HTML through the harness's own parsing methods reproduced the Playwright result **exactly** — title, author, user_id, word_count, all 31 code blocks (content _and_ language), image list, and the full `main_content` string were byte-identical.

**Cost of the browser**: 0.81 s per article of pure Chromium overhead (launch + context + page + close), measured with no page load at all, plus a full-page screenshot written and deleted per extraction, plus the ~200 MB Playwright Chromium dependency. HTML parse itself is 0.02 s.

**Not yet verified**: whether the _discovery_ path (user profile article listings) and the official-docs extractors also work without JS. Do not remove Playwright wholesale until those are tested — only the single-article parse path is proven static.

---

## 2026-02-26: Initial Evolution Log

**Status**: Skill is in use and maintained. Track improvements here.

### Purpose

This evolution log tracks updates to the skill. Each entry should note:

- What changed (content, structure, tooling)
- Why it changed (bug fix, feature request, best practice)
- Files affected

### How to Use

1. When updating SKILL.md or references, add an entry here with the date
2. Keep entries reverse-chronological (newest first)
3. Link to ADRs or GitHub issues when relevant
4. Reference specific line changes when helpful

---
