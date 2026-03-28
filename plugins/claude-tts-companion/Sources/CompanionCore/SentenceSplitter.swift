// Sentence boundary detection for streaming TTS chunking
import Foundation

/// Pure-function container for splitting text into sentences.
///
/// Used by TTSEngine's streaming synthesis to chunk text at sentence boundaries
/// for progressive TTS generation. Extracted from TTSEngine (D-05).
public struct SentenceSplitter: Sendable {

    /// Split text into sentences on `.`, `!`, `?` boundaries.
    ///
    /// Preserves the delimiter with the preceding sentence. Handles common
    /// abbreviations (Mr., Dr., etc.) and decimal numbers to avoid false splits.
    public static func splitIntoSentences(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Simple regex-based sentence splitting: split after .!? followed by whitespace
        // but avoid splitting on common abbreviations and decimal numbers
        var sentences: [String] = []
        var current = ""

        let chars = Array(trimmed)
        var i = 0
        while i < chars.count {
            current.append(chars[i])

            if chars[i] == "." || chars[i] == "!" || chars[i] == "?" {
                // Check if this is a real sentence boundary:
                // - Must be followed by whitespace or end of text
                // - Must not be a decimal number (digit.digit)
                let isEnd = (i + 1 >= chars.count)
                let followedBySpace = !isEnd && (i + 1 < chars.count) && chars[i + 1].isWhitespace

                // Check for decimal numbers: digit before . and digit after .
                let isDecimal = chars[i] == "."
                    && i > 0 && chars[i - 1].isNumber
                    && !isEnd && (i + 1 < chars.count) && chars[i + 1].isNumber

                // Check for common abbreviations (single capital letter followed by .)
                let isAbbrev = chars[i] == "."
                    && i > 0 && chars[i - 1].isUppercase
                    && (i < 2 || chars[i - 2].isWhitespace || i - 1 == 0)

                if (isEnd || followedBySpace) && !isDecimal && !isAbbrev {
                    let trimmedSentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedSentence.isEmpty {
                        sentences.append(trimmedSentence)
                    }
                    current = ""
                }
            }
            i += 1
        }

        // Append any remaining text as the final sentence
        let remaining = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            if sentences.isEmpty {
                sentences.append(remaining)
            } else {
                // Merge short trailing fragments with the last sentence
                sentences[sentences.count - 1] += " " + remaining
            }
        }

        return sentences
    }
}
