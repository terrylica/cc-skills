import Foundation

/// Result of language detection on a text string.
struct LanguageResult {
    /// Language code: "en-us" for English, "cmn" for Mandarin Chinese
    let lang: String
    /// Kokoro speaker ID for this language
    let speakerId: Int32
}

/// Detects whether text is predominantly CJK (Chinese/Japanese/Korean) based on
/// Unicode scalar ratio. Port of legacy TypeScript `detectLanguage()` from kokoro-client.ts.
enum LanguageDetector {
    /// Detect the dominant language of the given text.
    ///
    /// Counts CJK Unicode scalars across three ranges (CJK Unified Ideographs,
    /// Extension A, Extension B) and returns Chinese voice settings when the
    /// CJK ratio exceeds `Config.cjkDetectionThreshold` (default 20%).
    ///
    /// Empty strings return English defaults (matching legacy behavior).
    static func detect(text: String) -> LanguageResult {
        let scalars = text.unicodeScalars
        let totalCount = scalars.count

        guard totalCount > 0 else {
            return LanguageResult(lang: "en-us", speakerId: Config.defaultSpeakerId)
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
            return LanguageResult(lang: "cmn", speakerId: Config.chineseSpeakerId)
        }

        return LanguageResult(lang: "en-us", speakerId: Config.defaultSpeakerId)
    }
}
