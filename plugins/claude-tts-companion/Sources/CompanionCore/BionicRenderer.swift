import AppKit

/// Bionic reading renderer (BION-03).
///
/// Splits each word into a bold prefix (40% of characters, ceiling) and a
/// regular-weight suffix. This typographic pattern improves reading speed
/// by guiding the eye to fixation points.
public enum BionicRenderer {

    /// Compute the number of characters to bold for a given word.
    ///
    /// Returns `max(1, ceil(count * 0.4))` for non-empty words, 0 for empty string.
    public static func boldPrefixLength(_ word: String) -> Int {
        let count = word.count
        guard count > 0 else { return 0 }
        return max(1, Int(ceil(Double(count) * 0.4)))
    }

    /// Render an array of words as an NSAttributedString with bold prefixes.
    ///
    /// Each word's first `boldPrefixLength` characters use the bold (current-word)
    /// font, and the remaining characters use the regular font. All text is white.
    /// Words are separated by single spaces.
    @MainActor
    public static func render(words: [String], fontSizeName: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let boldFont = SubtitleStyle.dynamicCurrentWordFont(fontSizeName)
        let regularFont = SubtitleStyle.dynamicRegularFont(fontSizeName)
        let color = SubtitleStyle.futureWordColor

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        for (index, word) in words.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: " ", attributes: [
                    .font: regularFont,
                    .foregroundColor: color,
                    .paragraphStyle: paragraphStyle,
                ]))
            }

            let prefixLen = boldPrefixLength(word)
            if prefixLen > 0 {
                let splitIndex = word.index(word.startIndex, offsetBy: prefixLen)
                let boldPart = String(word[word.startIndex..<splitIndex])
                let regularPart = String(word[splitIndex...])

                result.append(NSAttributedString(string: boldPart, attributes: [
                    .font: boldFont,
                    .foregroundColor: color,
                    .paragraphStyle: paragraphStyle,
                ]))

                if !regularPart.isEmpty {
                    result.append(NSAttributedString(string: regularPart, attributes: [
                        .font: regularFont,
                        .foregroundColor: color,
                        .paragraphStyle: paragraphStyle,
                    ]))
                }
            }
        }

        return result
    }
}
