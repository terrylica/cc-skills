// Character-weighted word timing extraction for subtitle synchronization
import Foundation

/// Pure-function container for word-level timing extraction.
///
/// Provides character-weighted duration distribution for subtitle karaoke highlighting.
/// All methods are static and side-effect-free. Extracted from TTSEngine (D-02)
/// to enable independent testing and reduce TTSEngine surface area.
///
/// When native word onset data is available from the Python MLX server, it is passed
/// directly to SubtitleSyncDriver. This module serves as the fallback when native
/// timing data is unavailable.
public struct WordTimingAligner: Sendable {

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
}
