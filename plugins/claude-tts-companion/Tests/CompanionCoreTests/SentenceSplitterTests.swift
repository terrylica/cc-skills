@testable import CompanionCore
import Testing

@Suite struct SentenceSplitterTests {

    @Test func splitsOnPeriod() {
        let result = SentenceSplitter.splitIntoSentences("Hello world. Goodbye world.")
        #expect(result == ["Hello world.", "Goodbye world."])
    }

    @Test func splitsOnExclamationAndQuestion() {
        let result = SentenceSplitter.splitIntoSentences("Wow! Really? Yes.")
        #expect(result == ["Wow!", "Really?", "Yes."])
    }

    @Test func preservesSingleLetterAbbreviationsInContext() {
        // The implementation detects abbreviations as single uppercase letter before period.
        // "Mr." has "r" before period (not single uppercase), so it WILL split.
        // But "A. Smith" has "A" (single uppercase) before period, so it won't split.
        let result = SentenceSplitter.splitIntoSentences(
            "A. Smith said hello. Then left.")
        #expect(result == ["A. Smith said hello.", "Then left."])
    }

    @Test func preservesDecimals() {
        let result = SentenceSplitter.splitIntoSentences(
            "Pi is 3.14 roughly. That is all.")
        #expect(result == ["Pi is 3.14 roughly.", "That is all."])
    }

    @Test func singleLetterAbbreviations() {
        // U. and N. are single-uppercase-letter abbreviations
        let result = SentenceSplitter.splitIntoSentences(
            "Call U. N. headquarters.")
        #expect(result.count == 1)
    }

    @Test func emptyStringReturnsEmpty() {
        let result = SentenceSplitter.splitIntoSentences("")
        #expect(result.isEmpty)
    }

    @Test func whitespaceOnlyReturnsEmpty() {
        let result = SentenceSplitter.splitIntoSentences("   \n\t  ")
        #expect(result.isEmpty)
    }

    @Test func noTerminalPunctuationReturnsSentence() {
        let result = SentenceSplitter.splitIntoSentences("Hello world")
        #expect(result == ["Hello world"])
    }

    @Test func trailingFragmentMergesWithLastSentence() {
        // "World" has no terminal punctuation, so it merges with the last sentence
        let result = SentenceSplitter.splitIntoSentences("Hello. World")
        // The implementation merges trailing fragments into the last sentence
        #expect(result == ["Hello. World"])
    }

    @Test func singleSentenceWithPeriod() {
        let result = SentenceSplitter.splitIntoSentences("Just one sentence.")
        #expect(result == ["Just one sentence."])
    }

    @Test func multipleSentenceTypes() {
        let result = SentenceSplitter.splitIntoSentences(
            "Hello! How are you? Fine.")
        #expect(result == ["Hello!", "How are you?", "Fine."])
    }
}
