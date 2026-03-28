@testable import CompanionCore
import Testing

@Suite struct TelegramFormatterTests {
    @Test func convertsBoldMarkdownToHtml() {
        let result = TelegramFormatter.markdownToTelegramHtml("**bold text**")
        #expect(result.contains("<b>bold text</b>"))
    }

    @Test func convertsInlineCodeToHtml() {
        let result = TelegramFormatter.markdownToTelegramHtml("`some code`")
        #expect(result.contains("<code>some code</code>"))
    }

    @Test func convertsFencedCodeBlockToPreTag() {
        let input = "```swift\nlet x = 1\n```"
        let result = TelegramFormatter.markdownToTelegramHtml(input)
        #expect(result.contains("<pre>"))
        #expect(result.contains("let x = 1"))
    }

    @Test func escapesHtmlSpecialCharacters() {
        let result = TelegramFormatter.escapeHtml("<script>&\"test\"</script>")
        #expect(result.contains("&lt;"))
        #expect(result.contains("&amp;"))
        #expect(result.contains("&gt;"))
    }

    @Test func chunksLongTextRespectingLimit() {
        let longText = String(repeating: "word ", count: 1000)
        let chunks = TelegramFormatter.chunkTelegramHtml(longText, limit: 100)
        #expect(chunks.count > 1)
        for chunk in chunks {
            #expect(chunk.count <= 100)
        }
    }

    @Test func returnsEmptyArrayForEmptyText() {
        let chunks = TelegramFormatter.chunkTelegramHtml("")
        #expect(chunks.isEmpty)
    }

    @Test func returnsSingleChunkForShortText() {
        let chunks = TelegramFormatter.chunkTelegramHtml("Short text")
        #expect(chunks.count == 1)
        #expect(chunks[0] == "Short text")
    }
}
