import Foundation

/// Result of language detection on a text string.
public struct LanguageResult {
    /// Language code: "en-us" for English, "cmn" for Mandarin Chinese
    let lang: String
    /// Kokoro speaker ID for this language (legacy, kept for compatibility)
    let speakerId: Int32
    /// Voice embedding name for kokoro-ios
    let voiceName: String
}

/// Detects whether text is predominantly CJK (Chinese/Japanese/Korean) based on
/// Unicode scalar ratio. Port of legacy TypeScript `detectLanguage()` from kokoro-client.ts.
public enum LanguageDetector {
    /// Detect the dominant language of the given text.
    ///
    /// Counts CJK Unicode scalars across three ranges (CJK Unified Ideographs,
    /// Extension A, Extension B) and returns Chinese voice settings when the
    /// CJK ratio exceeds `Config.cjkDetectionThreshold` (default 20%).
    ///
    /// Note: kokoro-ios is English-only. Chinese text will use the English voice
    /// with a warning logged by TTSEngine.
    ///
    /// Empty strings return English defaults (matching legacy behavior).
    static func detect(text: String) -> LanguageResult {
        let scalars = text.unicodeScalars
        let totalCount = scalars.count

        guard totalCount > 0 else {
            return LanguageResult(
                lang: "en-us",
                speakerId: Config.defaultSpeakerId,
                voiceName: Config.defaultVoiceName
            )
        }

        var cjkCount = 0
        for scalar in scalars {
            let code = scalar.value
            if (code >= 0x4E00 && code <= 0x9FFF)       // CJK Unified Ideographs
                || (code >= 0x3400 && code <= 0x4DBF)    // CJK Extension A
                || (code >= 0x20000 && code <= 0x2A6DF)  // CJK Extension B
            {
                cjkCount += 1
            }
        }

        let ratio = (Double(cjkCount) / Double(totalCount)) * 100.0

        if ratio >= Config.cjkDetectionThreshold {
            // kokoro-ios is English-only; use English voice for CJK text with warning
            return LanguageResult(
                lang: "cmn",
                speakerId: Config.chineseSpeakerId,
                voiceName: Config.defaultVoiceName  // Graceful degradation: English voice
            )
        }

        return LanguageResult(
            lang: "en-us",
            speakerId: Config.defaultSpeakerId,
            voiceName: Config.defaultVoiceName
        )
    }
}
