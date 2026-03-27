---
status: awaiting_human_verify
trigger: "Audio is choppy and sometimes completely silent during TTS playback. Subtitles also get stuck (same text for 6+ seconds without word advancement)."
created: 2026-03-27T10:45:00-0700
updated: 2026-03-27T10:45:00-0700
---

## Current Focus

hypothesis: Two root causes — (1) SubtitleChunker.measureWidth uses hardcoded SubtitleStyle.currentWordFont instead of dynamic font from SettingsStore, causing text overflow (renderedLines=3 when maxLines=2), and (2) word-to-timing mismatch because SubtitleChunker splits on whitespace but extractTimingsFromTokens filters punctuation tokens, causing fewer timings than words
test: Verify word count from chunker vs timing count from MToken extraction
expecting: Mismatch in counts explains stuck subtitles; font mismatch explains overflow
next_action: Trace the word count vs timing count mismatch in the log data

## Symptoms

expected: Smooth continuous audio with word-by-word subtitle advancement
actual: Choppy audio, sometimes silent gaps. Subtitles stuck on same page without word advancement for seconds at a time.
errors: No error logs — audio plays (AVAudioPlayer finished success: true) but renderedLines=3 appearing (overflow)
reproduction: Every streaming TTS playback
started: After the native timestamps fix (MToken onset times)

## Eliminated

## Evidence

- timestamp: 2026-03-27T10:45:00
  checked: Log output for chunk 4 (stream chunk index 4, "Two specific errors were corrected...")
  found: renderedLines=3, measuredW=2463, availW=1412 -- text overflows 2-line limit. Subtitle stuck on same text from 10:28:58 to 10:29:11 (13 seconds, same page text "Two specific errors were corrected...")
  implication: SubtitleChunker is NOT splitting this sentence into multiple pages -- all 28 words go on 1 page but render as 3 lines. The chunker measures with SubtitleStyle.currentWordFont (hardcoded) but the panel renders with dynamic font from SettingsStore.

- timestamp: 2026-03-27T10:46:00
  checked: Log output for chunk 6 ("The solution was straightforward...")
  found: renderedLines=3, measuredW=2651, availW=1412 -- same overflow pattern. Stuck from 10:29:22 to 10:29:37 (15 seconds on same page)
  implication: Confirms systematic chunker/font mismatch

- timestamp: 2026-03-27T10:47:00
  checked: SubtitleChunker.measureWidth() source code
  found: Uses hardcoded `SubtitleStyle.currentWordFont` static property, NOT the dynamic font from SettingsStore. If user has font size set to "large", chunker measures with "medium" font width, producing pages that are too wide.
  implication: Root cause #1 confirmed: font size mismatch in chunker

- timestamp: 2026-03-27T10:48:00
  checked: Word advancement pattern in logs
  found: During chunk 4 playback (12.25s audio), subtitle text never changes from "Two specific errors..." -- the karaoke highlighting IS updating (60Hz tick updates word index) but all 28 words are on a single page so no visible page transition occurs. However word karaoke SHOULD be visible as gold highlights moving word-by-word. The logs show updateAttributedText firing every ~500ms-1s, not 60Hz.
  implication: Word advancement IS happening but (a) too many words on one page means the bold word causes line reflow making it look stuck, and (b) 3-line overflow means bottom text is clipped/invisible

## Resolution

root_cause: Two root causes: (1) SubtitleChunker.measureWidth() uses hardcoded SubtitleStyle.currentWordFont instead of the dynamic font from SettingsStore, so when font size is "large" the chunker measures with smaller font, creating pages with too many words that overflow to 3+ lines. (2) This causes "stuck subtitle" appearance because all words fit on one oversized page with no page transitions, and the 3rd line is clipped by the 2-line panel height.
fix: Made SubtitleChunker.measureWidth() and chunkIntoPages() accept a fontSizeName parameter instead of using hardcoded SubtitleStyle.currentWordFont. Made SubtitlePanel.currentFontSizeName public so TelegramBot can pass the dynamic font size to the chunker. Updated both streaming and full TTS dispatch paths in TelegramBot to pass the current font size.
verification: Build succeeds. Binary deployed. Awaiting human verification of next TTS playback.
files_changed: [SubtitleChunker.swift, SubtitlePanel.swift, TelegramBot.swift]
