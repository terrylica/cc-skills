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
}
