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
}
