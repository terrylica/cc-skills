@testable import CompanionCore
import Testing

@Suite(.serialized)
@MainActor
struct SubtitleChunkerTests {
    @Test func chunksShortTextIntoSinglePage() {
        let pages = SubtitleChunker.chunkIntoPages(text: "Hello world")
        #expect(pages.count == 1)
        #expect(pages[0].words.contains("Hello"))
        #expect(pages[0].words.contains("world"))
    }

    @Test func handlesEmptyText() {
        let pages = SubtitleChunker.chunkIntoPages(text: "")
        #expect(pages.isEmpty)
    }

    @Test func splitsLongTextIntoMultiplePages() {
        // Generate text long enough to require multiple pages
        let longText = (1...100).map { "word\($0)" }.joined(separator: " ")
        let pages = SubtitleChunker.chunkIntoPages(text: longText)
        #expect(pages.count > 1)
        // All words should be present across all pages
        let allWords = pages.flatMap { $0.words }
        #expect(allWords.count == 100)
    }

    @Test func trackStartWordIndex() {
        let text = "one two three four five six seven eight nine ten"
        let pages = SubtitleChunker.chunkIntoPages(text: text)
        // First page always starts at index 0
        #expect(pages[0].startWordIndex == 0)
        // Subsequent pages start after the previous page's words
        if pages.count > 1 {
            #expect(pages[1].startWordIndex == pages[0].words.count)
        }
    }

    @Test func normalizesWhitespace() {
        // Tabs, newlines, and multiple spaces should be normalized
        let text = "hello\tworld\nfoo   bar"
        let pages = SubtitleChunker.chunkIntoPages(text: text)
        let allWords = pages.flatMap { $0.words }
        #expect(allWords == ["hello", "world", "foo", "bar"])
    }

    // MARK: - Break Priority Tests (Phase 20)

    @Test func breakPriorityClauseBoundary() {
        #expect(SubtitleChunker.breakPriority("hello,") == 3)
        #expect(SubtitleChunker.breakPriority("world;") == 3)
        #expect(SubtitleChunker.breakPriority("done:") == 3)
        #expect(SubtitleChunker.breakPriority("pause\u{2014}") == 3)  // em-dash
    }

    @Test func breakPriorityPhraseWord() {
        #expect(SubtitleChunker.breakPriority("and") == 2)
        #expect(SubtitleChunker.breakPriority("with") == 2)
        #expect(SubtitleChunker.breakPriority("from") == 2)
        #expect(SubtitleChunker.breakPriority("or") == 2)
        #expect(SubtitleChunker.breakPriority("but") == 2)
    }

    @Test func breakPriorityRegularWord() {
        #expect(SubtitleChunker.breakPriority("hello") == 1)
        #expect(SubtitleChunker.breakPriority("Swift") == 1)
        #expect(SubtitleChunker.breakPriority("testing") == 1)
    }

    // MARK: - Font Size Variant Tests (Phase 20)

    @Test func fontSizeAffectsPageCount() {
        // Generate 50-word text that requires multiple pages
        let text = (1...50).map { "word\($0)" }.joined(separator: " ")
        let smallPages = SubtitleChunker.chunkIntoPages(text: text, fontSizeName: "small")
        let largePages = SubtitleChunker.chunkIntoPages(text: text, fontSizeName: "large")
        // Smaller font fits more words per line -> fewer or equal pages
        #expect(smallPages.count <= largePages.count)
    }

    @Test func allFontSizesProduceValidPages() {
        let text = (1...30).map { "word\($0)" }.joined(separator: " ")
        for size in ["small", "medium", "large"] {
            let pages = SubtitleChunker.chunkIntoPages(text: text, fontSizeName: size)
            #expect(!pages.isEmpty, "Font size '\(size)' should produce non-empty pages")
            let allWords = pages.flatMap { $0.words }
            #expect(allWords.count == 30, "Font size '\(size)' should cover all 30 words, got \(allWords.count)")
        }
    }

    // MARK: - Page Integrity Tests (Phase 20)

    @Test func pagesCoverAllWordsContiguously() {
        let text = (1...80).map { "word\($0)" }.joined(separator: " ")
        let pages = SubtitleChunker.chunkIntoPages(text: text)
        #expect(pages.count > 1, "Should produce multiple pages")

        // Verify contiguous startWordIndex
        var expectedStart = 0
        for page in pages {
            #expect(page.startWordIndex == expectedStart,
                    "Expected startWordIndex \(expectedStart), got \(page.startWordIndex)")
            expectedStart += page.wordCount
        }

        // Verify total word count
        let totalWords = pages.reduce(0) { $0 + $1.wordCount }
        #expect(totalWords == 80)
    }

    @Test func singleLongWordProducesOnePage() {
        // A 200-character word with no spaces
        let longWord = String(repeating: "a", count: 200)
        let pages = SubtitleChunker.chunkIntoPages(text: longWord)
        #expect(pages.count == 1)
        #expect(pages[0].words.count == 1)
        #expect(pages[0].words[0] == longWord)
    }

    // MARK: - Measure Width Tests (Phase 20)

    @Test func measureWidthIncreasesWithLength() {
        let short = SubtitleChunker.measureWidth("Hi")
        let medium = SubtitleChunker.measureWidth("Hello world")
        let long = SubtitleChunker.measureWidth("Hello world this is a longer string")
        #expect(short < medium)
        #expect(medium < long)
    }

    @Test func measureWidthIncreasesWithFontSize() {
        let small = SubtitleChunker.measureWidth("Hello", fontSizeName: "small")
        let large = SubtitleChunker.measureWidth("Hello", fontSizeName: "large")
        #expect(small < large)
    }
}
