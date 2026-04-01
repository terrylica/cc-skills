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
    /// font, and the remaining characters use the regular font.
    ///
    /// - `highlightIndex`: when >= 0, the word at that index gets gold coloring
    ///   (current spoken word). Past words use `currentWordColor` (already spoken),
    ///   future words use `futureWordColor` (grey). When -1, all words are white
    ///   (static bionic display without karaoke tracking).
    /// - `paragraphBreaksAfter`: word indices after which to insert a newline.
    @MainActor
    public static func render(
        words: [String],
        fontSizeName: String,
        highlightIndex: Int = -1,
        paragraphBreaksAfter: Set<Int> = []
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let boldFont = SubtitleStyle.dynamicCurrentWordFont(fontSizeName)
        let regularFont = SubtitleStyle.dynamicRegularFont(fontSizeName)
        let goldColor = SubtitleStyle.currentWordColor
        let spokenColor = SubtitleStyle.futureWordColor  // white for already-spoken
        let futureColor = SubtitleStyle.futureWordColor

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        for (index, word) in words.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: " ", attributes: [
                    .font: regularFont,
                    .foregroundColor: futureColor,
                    .paragraphStyle: paragraphStyle,
                ]))
            }

            // Determine color based on position relative to highlight
            let color: NSColor
            if highlightIndex < 0 {
                color = futureColor  // static mode, all white
            } else if index == highlightIndex {
                color = goldColor    // current word: gold
            } else if index < highlightIndex {
                color = spokenColor  // already spoken: white
            } else {
                color = futureColor  // future: grey
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

            // Paragraph break
            if paragraphBreaksAfter.contains(index) {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: regularFont,
                    .paragraphStyle: paragraphStyle,
                ]))
            }
        }

        return result
    }
}
