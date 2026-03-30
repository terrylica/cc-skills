// Pronunciation override preprocessing for TTS phonemization
import Foundation

/// Pure-function container for text preprocessing before TTS phonemization.
///
/// Replaces words the Kokoro/Misaki G2P phonemizer mispronounces with
/// phonetically-correct alternatives. Extracted from TTSEngine (D-03).
public struct PronunciationProcessor: Sendable {

    /// Words the Kokoro/Misaki phonemizer mispronounces, mapped to phonetically-correct
    /// replacements. Keys are case-insensitive regex patterns; values are the replacement text.
    /// The replacement must produce correct pronunciation when fed through the G2P pipeline.
    ///
    /// Example: "plugin" is phonemized as "plu-gin" instead of "plug-in".
    /// Replacing with "plug-in" (hyphenated) guides the phonemizer to the correct syllable break.
    static let pronunciationOverrides: [(pattern: String, replacement: String)] = [
        ("\\bplugin\\b", "plug-in"),
        ("\\bplugins\\b", "plug-ins"),
        ("\\bPlugins\\b", "Plug-ins"),
        ("\\bPlugin\\b", "Plug-in"),
    ]

    /// Pre-compiled regex patterns for pronunciation overrides (compiled once, reused across calls).
    static let compiledOverrides: [(regex: NSRegularExpression, replacement: String)] = {
        pronunciationOverrides.compactMap { entry in
            guard let regex = try? NSRegularExpression(
                pattern: entry.pattern,
                options: []
            ) else { return nil }
            return (regex: regex, replacement: entry.replacement)
        }
    }()

    // MARK: - Markdown Stripping

    /// Patterns to strip markdown formatting before TTS synthesis.
    /// Kokoro's phonemizer mishandles asterisks, producing garbled output.
    private static let markdownPatterns: [(regex: NSRegularExpression, replacement: String)] = {
        let patterns: [(String, String)] = [
            (#"\*\*(.+?)\*\*"#, "$1"),     // **bold** → bold
            (#"\*(.+?)\*"#, "$1"),          // *italic* → italic
            (#"__(.+?)__"#, "$1"),          // __underline__ → underline
            (#"`(.+?)`"#, "$1"),            // `code` → code
            (#"^\s*#{1,6}\s+"#, ""),        // ## Heading → Heading
            (#"\[([^\]]+)\]\([^\)]+\)"#, "$1"),  // [text](url) → text
            (#"^[\s]*[-*+]\s+"#, ""),       // - list item → list item
            (#"^[\s]*\d+\.\s+"#, ""),       // 1. numbered → numbered
        ]
        return patterns.compactMap { (pattern, replacement) in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return nil }
            return (regex: regex, replacement: replacement)
        }
    }()

    /// Strip markdown formatting that Kokoro's phonemizer mishandles.
    private static func stripMarkdown(_ text: String) -> String {
        var result = text
        for pattern in markdownPatterns {
            let range = NSRange(result.startIndex..., in: result)
            result = pattern.regex.stringByReplacingMatches(
                in: result, options: [], range: range,
                withTemplate: pattern.replacement
            )
        }
        return result
    }

    /// Apply markdown stripping and pronunciation overrides before passing to TTS.
    public static func preprocessText(_ text: String) -> String {
        var result = stripMarkdown(text)
        for override in compiledOverrides {
            let range = NSRange(result.startIndex..., in: result)
            result = override.regex.stringByReplacingMatches(
                in: result, options: [], range: range,
                withTemplate: override.replacement
            )
        }
        return result
    }

    /// Split text into words matching Kokoro's tokenization.
    ///
    /// Kokoro's word timestamp output strips pure-punctuation and symbol tokens
    /// (em-dash, ellipsis, standalone brackets, emoji, etc.) while keeping
    /// punctuation attached to words (e.g. "hello," stays as one token).
    /// This splitter mirrors that behavior so word count matches onset count.
    public static func splitWordsMatchingKokoro(_ text: String) -> [String] {
        text.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { word in
                // Keep the word if it contains at least one letter or digit
                word.contains(where: { $0.isLetter || $0.isNumber })
            }
    }

    /// Re-attach punctuation from the original text to Kokoro's linguistic tokens.
    ///
    /// Kokoro's Misaki/spaCy tokenizer produces word tokens stripped of trailing
    /// punctuation (e.g., "running" instead of "running.", "over" instead of "over,").
    /// These tokens are needed for 1:1 onset alignment, but displayed subtitles should
    /// show the original punctuation.
    ///
    /// Algorithm: split original text on whitespace (preserving punctuation), then
    /// greedily match each Kokoro token to the next original word that contains it.
    /// The original word (with punctuation) becomes the display word.
    ///
    /// Returns display words with punctuation, guaranteed same count as kokoroTokens.
    /// Falls back to kokoroTokens if matching fails.
    public static func reattachPunctuation(originalText: String, kokoroTokens: [String]) -> [String] {
        // Split original text same way as splitWordsMatchingKokoro
        let originalWords = splitWordsMatchingKokoro(originalText)

        // If counts match, the original words already have punctuation — use them directly
        if originalWords.count == kokoroTokens.count {
            return originalWords
        }

        // Counts don't match (rare edge case where Kokoro merges/splits differently).
        // Try greedy matching: for each Kokoro token, find the next original word containing it.
        var displayWords: [String] = []
        var origIdx = 0

        for token in kokoroTokens {
            let tokenLower = token.lowercased()
            var matched = false

            // Search forward in original words for a match
            var searchIdx = origIdx
            while searchIdx < originalWords.count {
                let origLower = originalWords[searchIdx].lowercased()
                // Check if original word contains the token (handles trailing punctuation)
                // e.g., origLower="running." contains tokenLower="running"
                if origLower.hasPrefix(tokenLower) || origLower == tokenLower ||
                   origLower.contains(tokenLower) {
                    displayWords.append(originalWords[searchIdx])
                    origIdx = searchIdx + 1
                    matched = true
                    break
                }
                searchIdx += 1
            }

            if !matched {
                // No match found — use the token as-is (no punctuation, but keeps count correct)
                displayWords.append(token)
            }
        }

        return displayWords
    }

    // MARK: - Sentence Bisector (Adaptive Paragraph Segmentation)

    /// Recursively bisect a paragraph at sentence midpoints until every segment
    /// falls under the paragraph budget (max character count per synthesis chunk).
    ///
    /// Algorithm: split into sentences, divide at the midpoint, recurse on each
    /// half if still over budget. Returns segments in reading order.
    /// If a single sentence exceeds the budget, it is returned as-is (atomic unit).
    public static func bisectParagraph(_ text: String, budget: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > budget else { return [trimmed] }

        let sentences = splitSentences(trimmed)
        guard sentences.count > 1 else {
            // Single sentence exceeds budget — atomic, cannot split further
            return [trimmed]
        }

        let mid = sentences.count / 2
        let firstHalf = sentences[..<mid].joined(separator: " ")
        let secondHalf = sentences[mid...].joined(separator: " ")

        // Recurse on each half
        return bisectParagraph(firstHalf, budget: budget)
             + bisectParagraph(secondHalf, budget: budget)
    }

    /// Split text into sentences using Unicode-aware sentence boundary detection.
    /// Falls back to regex splitting on common sentence-ending punctuation.
    private static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, _ in
            if let s = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                sentences.append(s)
            }
        }
        // Fallback: if enumerateSubstrings produces a single chunk, try regex
        if sentences.count <= 1 {
            let pattern = #"[^.!?]+[.!?]+"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, options: [], range: range)
                let regexSentences = matches.compactMap { match -> String? in
                    guard let r = Range(match.range, in: text) else { return nil }
                    let s = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return s.isEmpty ? nil : s
                }
                if regexSentences.count > 1 { return regexSentences }
            }
        }
        return sentences.isEmpty ? [text] : sentences
    }

    /// Apply paragraph budget enforcement to a list of paragraphs (from `\n\n` splitting).
    /// Each paragraph that exceeds the budget is recursively bisected at sentence boundaries.
    public static func enforceParargraphBudget(_ paragraphs: [String], budget: Int) -> [String] {
        paragraphs.flatMap { bisectParagraph($0, budget: budget) }
    }

    /// Compute which display word indices are followed by a paragraph break in the original text.
    ///
    /// Splits by `\n\n`, counts words per paragraph, then maps break indices from source-word
    /// space to display-word space. When counts match (common case), indices are used directly.
    /// When Kokoro tokenizes differently (rare), proportional mapping keeps breaks within 1 word.
    public static func paragraphBreakIndices(_ text: String, displayWords: [String]? = nil) -> Set<Int> {
        guard text.contains("\n\n") else { return [] }

        let paragraphs = text.components(separatedBy: "\n\n")
        guard paragraphs.count > 1 else { return [] }

        // Count words per paragraph using the same filter as splitWordsMatchingKokoro
        var sourceBreakIndices: [Int] = []
        var cumulative = 0
        for (i, paragraph) in paragraphs.enumerated() {
            let count = paragraph.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
                .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
                .count
            cumulative += count
            if i < paragraphs.count - 1 && count > 0 {
                sourceBreakIndices.append(cumulative - 1)
            }
        }
        guard !sourceBreakIndices.isEmpty else { return [] }

        let sourceWordCount = cumulative
        let displayCount = displayWords?.count ?? sourceWordCount

        // Common case: counts match → source indices map 1:1 to display indices
        if displayCount == sourceWordCount {
            return Set(sourceBreakIndices.filter { $0 < displayCount - 1 })
        }

        // Rare case: Kokoro tokenized differently → proportional mapping
        let ratio = Double(displayCount) / Double(sourceWordCount)
        var breaks: Set<Int> = []
        for srcIdx in sourceBreakIndices {
            let mapped = min(Int(round(Double(srcIdx) * ratio)), displayCount - 2)
            if mapped >= 0 { breaks.insert(mapped) }
        }
        return breaks
    }
}
