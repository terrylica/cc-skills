import AppKit

/// A single page of subtitle text, containing words and their position in the full word array.
struct SubtitlePage {
    let words: [String]
    let startWordIndex: Int
    var wordCount: Int { words.count }
}

/// Splits subtitle text into 2-line pages using pixel-width measurement.
///
/// Uses `NSAttributedString.size()` with `SubtitleStyle.regularFont` for accurate
/// text width measurement, and applies clause/phrase-priority line breaking with
/// a bottom-heavy preference (shorter first line, longer second line).
@MainActor
enum SubtitleChunker {

    // MARK: - Public API

    /// Split text into pages of up to 2 lines each, using pixel-width measurement.
    static func chunkIntoPages(text: String) -> [SubtitlePage] {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let width = availableLineWidth()
        return chunkIntoPages(words: words, availableWidth: width)
    }

    // MARK: - Width Measurement

    /// Compute the available line width in points, accounting for panel width ratio and padding.
    static func availableLineWidth() -> CGFloat {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 2056
        return screenWidth * SubtitleStyle.widthRatio - (SubtitleStyle.horizontalPadding * 2)
    }

    /// Measure the rendered width of a string using the bold subtitle font.
    ///
    /// Uses bold font (not regular) because during karaoke display, one word is
    /// always bold — this ensures lines measured during chunking never overflow
    /// when displayed with karaoke highlighting.
    static func measureWidth(_ text: String) -> CGFloat {
        let attrStr = NSAttributedString(
            string: text,
            attributes: [.font: SubtitleStyle.currentWordFont]
        )
        return ceil(attrStr.size().width)
    }

    // MARK: - Break Priority

    /// Return the break priority for a word (higher = better line break point).
    ///
    /// - 3: Clause boundary (word ends with `,`, `;`, `:`, or em-dash `\u{2014}`)
    /// - 2: Phrase boundary (conjunctions, prepositions)
    /// - 1: Any other word
    static func breakPriority(_ word: String) -> Int {
        let clauseEndings: [Character] = [",", ";", ":", "\u{2014}"]
        if let last = word.last, clauseEndings.contains(last) {
            return 3
        }

        let phraseWords: Set<String> = [
            "and", "or", "but", "for", "nor", "yet", "so",
            "in", "on", "at", "to", "of", "by", "with", "from",
        ]
        if phraseWords.contains(word.lowercased()) {
            return 2
        }

        return 1
    }

    // MARK: - Line Filling

    /// Greedily fill a line with words, respecting pixel-width constraints.
    ///
    /// When `preferShorter` is true (line 1), the algorithm backtracks to a clause or
    /// phrase break in the last 30% of words if one exists, producing a shorter first
    /// line for a bottom-heavy visual shape.
    private static func fillLine(
        words: [String],
        from startIndex: Int,
        maxWidth: CGFloat,
        preferShorter: Bool
    ) -> (words: [String], nextIndex: Int) {
        guard startIndex < words.count else {
            return ([], startIndex)
        }

        var lineWords: [String] = []
        var lastBreakIndex: Int?
        var lastBreakPriority: Int = 0
        var currentIndex = startIndex

        while currentIndex < words.count {
            lineWords.append(words[currentIndex])
            let lineText = lineWords.joined(separator: " ")
            let width = measureWidth(lineText)

            // Track high-priority break points
            let priority = breakPriority(words[currentIndex])
            if priority >= 2 {
                lastBreakIndex = lineWords.count - 1
                lastBreakPriority = priority
            }

            if width > maxWidth {
                // Single word overflows -- include it anyway
                if lineWords.count == 1 {
                    return (lineWords, currentIndex + 1)
                }

                // Check if we should backtrack to a break point
                if preferShorter,
                   let breakIdx = lastBreakIndex,
                   lastBreakPriority >= 2
                {
                    // Only backtrack if break is in the last 30% of words added
                    let wordsAdded = lineWords.count
                    let threshold = Int(Double(wordsAdded) * 0.7)
                    if breakIdx >= threshold {
                        let trimmedWords = Array(lineWords[0...breakIdx])
                        return (trimmedWords, startIndex + breakIdx + 1)
                    }
                }

                // Default: backtrack to before the overflowing word
                lineWords.removeLast()
                return (lineWords, currentIndex)
            }

            currentIndex += 1
        }

        // All remaining words fit on one line
        return (lineWords, currentIndex)
    }

    // MARK: - Page Construction

    /// Build pages of up to 2 lines each from a word array.
    private static func chunkIntoPages(words: [String], availableWidth: CGFloat) -> [SubtitlePage] {
        var pages: [SubtitlePage] = []
        var wordIndex = 0

        while wordIndex < words.count {
            let pageStart = wordIndex

            // Line 1: prefer shorter for bottom-heavy shape
            let line1 = fillLine(words: words, from: wordIndex, maxWidth: availableWidth, preferShorter: true)

            // Line 2: fill as much as possible
            let line2 = fillLine(words: words, from: line1.nextIndex, maxWidth: availableWidth, preferShorter: false)

            let pageWords = line1.words + line2.words
            if !pageWords.isEmpty {
                pages.append(SubtitlePage(words: pageWords, startWordIndex: pageStart))
            }

            wordIndex = line2.nextIndex
        }

        // Filter out empty pages (defensive)
        return pages.filter { !$0.words.isEmpty }
    }
}
