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

    /// Apply pronunciation overrides to text before passing to the TTS engine.
    ///
    /// This is a pre-phonemization text substitution: it replaces words that the
    /// Misaki G2P phonemizer handles incorrectly with phonetically-equivalent alternatives
    /// that produce correct pronunciation.
    public static func preprocessText(_ text: String) -> String {
        var result = text
        for override in compiledOverrides {
            let range = NSRange(result.startIndex..., in: result)
            result = override.regex.stringByReplacingMatches(
                in: result, options: [], range: range,
                withTemplate: override.replacement
            )
        }
        return result
    }
}
