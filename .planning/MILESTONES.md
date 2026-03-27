# Milestones

## v4.6.0 Legacy Pipeline Feature Parity (Shipped: 2026-03-27)

**Phases completed:** 7 phases, 13 plans, 21 tasks

**Key accomplishments:**

- Full legacy TypeScript formatting pipeline ported to TelegramFormatter.swift with renderSessionNotification, meta-tag stripping, file-ref wrapping, and fence-aware chunking with close/reopen
- Session notification pipeline wired end-to-end: rich HTML header via renderSessionNotification, silent Tail Brief as separate message, git branch and timestamps extracted from JSONL transcripts
- Ported 18 legacy noise patterns + regex filters into TranscriptParser with longest-response turn extraction and tool count aggregation
- Ported exact legacy TypeScript prompt text into SummaryEngine with em dashes, right arrows, correct char budgets, and new summarizePromptForDisplay method
- Full legacy auto-continue evaluation engine ported from TypeScript with verbatim SYSTEM_PROMPT/SWEEP_PROMPT, per-session state tracking, sibling JSONL plan discovery, and deterministic sweep fallback
- Rich Telegram decision notifications with icon, reason, progress bar, tool breakdown, and timing ported from legacy TypeScript formatDecisionMessage/sendExitNotification
- CJK language detection across 3 Unicode ranges with per-outlet feature gates reading 5 legacy env vars
- Feature-gated notification pipeline with CJK language detection routing English to af_heart (3) and Chinese to zf_xiaobei (45)
- Inline keyboard with Focus Tab/Follow Up/Transcript buttons on Arc Summary, callback handlers with AppleScript iTerm2 switching and FIFO-bounded state maps
- Verified itermSessionId and transcriptPath already wired from notification JSON to sendSessionNotification -- Plan 01 completed all code changes
- NotificationProcessor with session dedup (15-min TTL, transcript size tracking) and 5s rate limiting ported from legacy TypeScript
- Pixel-width SubtitleChunker splits text into 2-line pages with clause-priority line breaking; SubtitlePanel.showPages() drives sequential page-flip karaoke with generation-counter interruption safety
- Replaced showUtterance() with SubtitleChunker.chunkIntoPages() + showPages() in dispatchTTS() for paged karaoke subtitles with continuous audio playback

---
