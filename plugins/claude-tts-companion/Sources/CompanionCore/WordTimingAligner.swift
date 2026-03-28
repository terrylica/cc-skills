// Word timing alignment from MToken timestamps to subtitle words
import Foundation
import Logging
import MLXUtilsLibrary

/// Pure-function container for word-level timing extraction and alignment.
///
/// All methods are static and side-effect-free. Extracted from TTSEngine (D-02)
/// to enable independent testing and reduce TTSEngine surface area.
public struct WordTimingAligner: Sendable {

    /// Extracted native timing data from MToken array.
    struct NativeTimings {
        /// Per-word durations (end_ts - start_ts), used as fallback/display
        let durations: [TimeInterval]
        /// Per-word onset times (start_ts values), the ground-truth from the Kokoro duration model.
        /// These account for leading silence and inter-word gaps that duration-only extraction loses.
        let onsets: [TimeInterval]
        /// Per-word text from MTokens (linguistic tokens, may differ from whitespace-split words).
        /// Used by alignOnsetsToWords() to map MToken onsets onto subtitle word positions.
        let texts: [String]
    }

    /// Resolved word timings and optional onset times from MToken alignment or character-weighted fallback.
    struct ResolvedTimings {
        let durations: [TimeInterval]
        let onsets: [TimeInterval]?
    }

    /// Extract per-word durations AND onset times from native MToken timestamps.
    ///
    /// Returns both durations (end_ts - start_ts) and onset times (start_ts) for each word.
    /// Onset times are the ground truth from the Kokoro duration model and include leading
    /// silence and inter-word pauses. Using onsets directly in SubtitleSyncDriver avoids
    /// the ~275ms+ drift caused by cumulating durations from zero.
    ///
    /// Filters out punctuation-only tokens. Returns nil if no timestamps available.
    static func extractTimingsFromTokens(_ tokens: [MToken]?) -> NativeTimings? {
        guard let tokens = tokens, !tokens.isEmpty else { return nil }

        let punctuation: Set<String> = [".", ",", "!", "?", ";", ":", "-", "\u{2014}", "\u{2013}"]

        var durations: [TimeInterval] = []
        var onsets: [TimeInterval] = []
        var texts: [String] = []
        for token in tokens {
            guard let startTs = token.start_ts, let endTs = token.end_ts else { continue }
            // Skip punctuation-only tokens
            let text = token.text.trimmingCharacters(in: .whitespaces)
            if punctuation.contains(text) { continue }
            if text.isEmpty { continue }
            let dur = endTs - startTs
            if dur > 0 {
                onsets.append(startTs)
                durations.append(dur)
                texts.append(text)
            }
        }

        guard !durations.isEmpty else { return nil }
        return NativeTimings(durations: durations, onsets: onsets, texts: texts)
    }

    /// Align MToken-derived onset times to whitespace-split subtitle words.
    ///
    /// MTokens come from NLTokenizer (linguistic tokenization) while subtitles split by
    /// whitespace. These can differ: contractions may split differently, preprocessing
    /// may change word count ("plugin" -> "plug-in"), and hyphens/dashes may cause splits.
    ///
    /// This function walks both arrays using character-offset tracking to map each subtitle
    /// word to the MToken whose text overlaps it, producing one onset per subtitle word.
    ///
    /// Returns aligned (durations, onsets) arrays with count == subtitleWords.count,
    /// or nil if alignment fails badly (falls back to character-weighted).
    static func alignOnsetsToWords(
        native: NativeTimings,
        subtitleWords: [String],
        audioDuration: TimeInterval
    ) -> (durations: [TimeInterval], onsets: [TimeInterval])? {
        // Fast path: counts match -- assume 1:1 alignment (common case)
        if native.texts.count == subtitleWords.count {
            return (native.durations, native.onsets)
        }

        // Build character-position mapping.
        // Walk both sequences, consuming characters to find which MToken(s) cover each subtitle word.
        var alignedOnsets: [TimeInterval] = []
        var alignedDurations: [TimeInterval] = []

        // Build flat character streams (lowercase, stripped of leading/trailing punctuation)
        let tokenChars = native.texts.map { stripPunctuation($0).lowercased() }
        let subChars = subtitleWords.map { stripPunctuation($0).lowercased() }

        var ti = 0  // token index
        var tCharPos = 0  // character position within current token

        for si in 0..<subChars.count {
            let subWord = subChars[si]
            guard !subWord.isEmpty else {
                // Empty after stripping -- interpolate from neighbors
                if let lastOnset = alignedOnsets.last {
                    let lastDur = alignedDurations.last ?? 0.2
                    alignedOnsets.append(lastOnset + lastDur)
                    alignedDurations.append(0.1)
                } else {
                    alignedOnsets.append(0)
                    alignedDurations.append(0.1)
                }
                continue
            }

            // Assign onset from the token that covers the START of this subtitle word
            if ti < native.texts.count {
                alignedOnsets.append(native.onsets[ti])

                // Consume characters from tokens to cover this subtitle word
                var remaining = subWord.count
                var lastTokenUsed = ti

                while remaining > 0 && ti < native.texts.count {
                    let tokenRemaining = tokenChars[ti].count - tCharPos
                    if tokenRemaining <= remaining {
                        remaining -= tokenRemaining
                        lastTokenUsed = ti
                        ti += 1
                        tCharPos = 0
                    } else {
                        tCharPos += remaining
                        lastTokenUsed = ti
                        remaining = 0
                    }
                }

                // Duration: from onset of first token to end of last token used
                let startOnset = alignedOnsets.last!
                if lastTokenUsed < native.texts.count {
                    let endTime = native.onsets[lastTokenUsed] + native.durations[lastTokenUsed]
                    alignedDurations.append(endTime - startOnset)
                } else {
                    alignedDurations.append(native.durations.last ?? 0.2)
                }
            } else {
                // Ran out of tokens -- extrapolate from last known position
                let lastOnset = alignedOnsets.last ?? 0
                let lastDur = alignedDurations.last ?? 0.2
                alignedOnsets.append(lastOnset + lastDur)
                // Distribute remaining time evenly
                let remainingWords = subChars.count - si
                let remainingTime = max(0, audioDuration - (lastOnset + lastDur))
                alignedDurations.append(remainingTime / Double(remainingWords))
            }
        }

        guard alignedOnsets.count == subtitleWords.count else { return nil }
        return (alignedDurations, alignedOnsets)
    }

    /// Strip leading/trailing punctuation AND internal hyphens for character-count alignment.
    ///
    /// NLTokenizer splits hyphenated compounds ("mid-decay") into separate tokens ("mid", "decay"),
    /// but SubtitleChunker keeps them as one whitespace-split word. Without removing the hyphen,
    /// "mid-decay" = 9 chars vs "mid" (3) + "decay" (5) = 8 chars, causing the character
    /// consumption loop in alignOnsetsToWords() to overshoot. Removing internal hyphens gives
    /// "middecay" = 8 chars, matching the MToken sum exactly.
    static func stripPunctuation(_ word: String) -> String {
        let punct = CharacterSet.punctuationCharacters.union(.symbols)
        var result = word
        while let first = result.unicodeScalars.first, punct.contains(first) {
            result = String(result.dropFirst())
        }
        while let last = result.unicodeScalars.last, punct.contains(last) {
            result = String(result.dropLast())
        }
        // Remove internal hyphens/dashes so "mid-decay" -> "middecay" matches
        // NLTokenizer's "mid" + "decay" = "middecay" in character counting
        result = result.replacingOccurrences(of: "-", with: "")
        result = result.replacingOccurrences(of: "\u{2013}", with: "")  // en-dash
        result = result.replacingOccurrences(of: "\u{2014}", with: "")  // em-dash
        return result
    }

    /// Extract per-word onset timings from the total audio duration (character-weighted fallback).
    ///
    /// Each word's duration is proportional to its character count relative to the
    /// total character count. The sum of all word durations exactly equals
    /// `audioDuration`, ensuring zero accumulated drift (TTS-07).
    ///
    /// Returns an array of TimeInterval where timings[i] is the DURATION of word i
    /// (matching SubtitlePanel.showUtterance's expected format).
    static func extractWordTimings(text: String, audioDuration: TimeInterval) -> [TimeInterval] {
        let words = text.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }

        // Weight by character count (longer words take proportionally longer)
        let charCounts = words.map { Double($0.count) }
        let totalChars = charCounts.reduce(0, +)
        guard totalChars > 0 else {
            return Array(repeating: audioDuration / Double(words.count), count: words.count)
        }

        // Distribute audio duration proportionally
        return charCounts.map { count in
            (count / totalChars) * audioDuration
        }
    }

    /// Align MToken-derived timing data to whitespace-split subtitle words, with character-weighted fallback.
    ///
    /// Centralizes the pattern shared by synthesizeWithTimestamps() and synthesizeStreaming():
    /// extract native timings from tokens, align to subtitle words, fall back to character-weighted
    /// if native timestamps are unavailable.
    static func resolveWordTimings(
        tokenArray: [MToken]?,
        text: String,
        audioDuration: TimeInterval,
        logger: Logger
    ) -> ResolvedTimings {
        let nativeTimings = extractTimingsFromTokens(tokenArray)
        let subtitleWords = text.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace).map(String.init)

        if let native = nativeTimings,
           let aligned = alignOnsetsToWords(native: native, subtitleWords: subtitleWords, audioDuration: audioDuration) {
            if native.texts.count != subtitleWords.count {
                logger.info("Aligned \(native.texts.count) MToken words to \(subtitleWords.count) subtitle words")
            }
            return ResolvedTimings(durations: aligned.durations, onsets: aligned.onsets)
        } else {
            logger.warning("No native timestamps from kokoro-ios, falling back to character-weighted")
            return ResolvedTimings(
                durations: extractWordTimings(text: text, audioDuration: audioDuration),
                onsets: nil
            )
        }
    }
}
