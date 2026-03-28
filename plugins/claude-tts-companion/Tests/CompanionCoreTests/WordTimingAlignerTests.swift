@testable import CompanionCore
import MLXUtilsLibrary
import Testing

/// Helper to construct MToken test fixtures with timing data.
private func makeToken(
    _ text: String, start: Double? = nil, end: Double? = nil
) -> MToken {
    let dummyRange = "dummy".startIndex..<"dummy".endIndex
    return MToken(
        text: text, tokenRange: dummyRange, whitespace: " ",
        start_ts: start, end_ts: end
    )
}

@Suite struct WordTimingAlignerTests {

    // MARK: - extractTimingsFromTokens

    @Test func extractTimingsReturnsNilForNilInput() {
        let result = WordTimingAligner.extractTimingsFromTokens(nil)
        #expect(result == nil)
    }

    @Test func extractTimingsReturnsNilForEmptyArray() {
        let result = WordTimingAligner.extractTimingsFromTokens([])
        #expect(result == nil)
    }

    @Test func extractTimingsReturnsCorrectDurationsAndOnsets() {
        let tokens = [
            makeToken("Hello", start: 0.0, end: 0.5),
            makeToken("world", start: 0.6, end: 1.0),
        ]
        let result = WordTimingAligner.extractTimingsFromTokens(tokens)
        #expect(result != nil)
        #expect(result!.durations.count == 2)
        #expect(result!.onsets.count == 2)
        #expect(result!.texts == ["Hello", "world"])
        #expect(abs(result!.durations[0] - 0.5) < 0.001)
        #expect(abs(result!.durations[1] - 0.4) < 0.001)
        #expect(abs(result!.onsets[0] - 0.0) < 0.001)
        #expect(abs(result!.onsets[1] - 0.6) < 0.001)
    }

    @Test func extractTimingsFiltersPunctuation() {
        let tokens = [
            makeToken("Hello", start: 0.0, end: 0.5),
            makeToken(",", start: 0.5, end: 0.55),
            makeToken("world", start: 0.6, end: 1.0),
        ]
        let result = WordTimingAligner.extractTimingsFromTokens(tokens)
        #expect(result != nil)
        #expect(result!.texts == ["Hello", "world"])
        #expect(result!.durations.count == 2)
    }

    @Test func extractTimingsFiltersDashPunctuation() {
        let tokens = [
            makeToken("Hello", start: 0.0, end: 0.5),
            makeToken("-", start: 0.5, end: 0.55),
            makeToken(".", start: 0.55, end: 0.6),
            makeToken("!", start: 0.6, end: 0.65),
            makeToken("?", start: 0.65, end: 0.7),
            makeToken(";", start: 0.7, end: 0.75),
            makeToken(":", start: 0.75, end: 0.8),
            makeToken("world", start: 0.8, end: 1.2),
        ]
        let result = WordTimingAligner.extractTimingsFromTokens(tokens)
        #expect(result != nil)
        #expect(result!.texts == ["Hello", "world"])
    }

    @Test func extractTimingsSkipsTokensMissingTimestamps() {
        let tokens = [
            makeToken("Hello", start: 0.0, end: 0.5),
            makeToken("missing", start: nil, end: nil),
            makeToken("world", start: 0.6, end: 1.0),
        ]
        let result = WordTimingAligner.extractTimingsFromTokens(tokens)
        #expect(result != nil)
        #expect(result!.texts == ["Hello", "world"])
    }

    @Test func extractTimingsSkipsZeroDuration() {
        let tokens = [
            makeToken("Hello", start: 0.0, end: 0.5),
            makeToken("zero", start: 0.5, end: 0.5),  // zero duration
            makeToken("world", start: 0.6, end: 1.0),
        ]
        let result = WordTimingAligner.extractTimingsFromTokens(tokens)
        #expect(result != nil)
        #expect(result!.texts == ["Hello", "world"])
    }

    @Test func extractTimingsReturnsNilWhenAllPunctuation() {
        let tokens = [
            makeToken(".", start: 0.0, end: 0.1),
            makeToken(",", start: 0.1, end: 0.2),
        ]
        let result = WordTimingAligner.extractTimingsFromTokens(tokens)
        #expect(result == nil)
    }

    // MARK: - alignOnsetsToWords

    @Test func alignOnsetsEqualCountFastPath() {
        let native = WordTimingAligner.NativeTimings(
            durations: [0.3, 0.4, 0.5],
            onsets: [0.0, 0.4, 0.9],
            texts: ["Hello", "beautiful", "world"]
        )
        let result = WordTimingAligner.alignOnsetsToWords(
            native: native,
            subtitleWords: ["Hello", "beautiful", "world"],
            audioDuration: 1.4
        )
        #expect(result != nil)
        #expect(result!.durations == [0.3, 0.4, 0.5])
        #expect(result!.onsets == [0.0, 0.4, 0.9])
    }

    @Test func alignOnsetsHyphenatedWord() {
        // NLTokenizer splits "mid-decay" into "mid" and "decay"
        // but subtitle has single word "mid-decay"
        let native = WordTimingAligner.NativeTimings(
            durations: [0.3, 0.5],
            onsets: [0.0, 0.4],
            texts: ["mid", "decay"]
        )
        let result = WordTimingAligner.alignOnsetsToWords(
            native: native,
            subtitleWords: ["mid-decay"],
            audioDuration: 1.0
        )
        #expect(result != nil)
        #expect(result!.onsets.count == 1)
        #expect(abs(result!.onsets[0] - 0.0) < 0.001)
    }

    @Test func alignOnsetsMoreSubtitleWordsThanTokens() {
        // Extrapolation when subtitle has more words
        let native = WordTimingAligner.NativeTimings(
            durations: [0.5],
            onsets: [0.0],
            texts: ["Hello"]
        )
        let result = WordTimingAligner.alignOnsetsToWords(
            native: native,
            subtitleWords: ["Hello", "world"],
            audioDuration: 2.0
        )
        #expect(result != nil)
        #expect(result!.onsets.count == 2)
        // Second word should be extrapolated
        #expect(result!.onsets[1] > 0)
    }

    @Test func alignOnsetsMoreTokensThanSubtitleWords() {
        // Compression: more tokens than subtitle words
        let native = WordTimingAligner.NativeTimings(
            durations: [0.2, 0.3, 0.4],
            onsets: [0.0, 0.3, 0.7],
            texts: ["one", "two", "three"]
        )
        let result = WordTimingAligner.alignOnsetsToWords(
            native: native,
            subtitleWords: ["onetwo", "three"],
            audioDuration: 1.1
        )
        #expect(result != nil)
        #expect(result!.onsets.count == 2)
    }

    // MARK: - stripPunctuation

    @Test func stripPunctuationRemovesLeadingTrailing() {
        let result = WordTimingAligner.stripPunctuation("...hello!")
        #expect(result == "hello")
    }

    @Test func stripPunctuationRemovesInternalHyphens() {
        let result = WordTimingAligner.stripPunctuation("mid-decay")
        #expect(result == "middecay")
    }

    @Test func stripPunctuationRemovesDashes() {
        let result = WordTimingAligner.stripPunctuation("\u{2014}test\u{2013}")
        #expect(result == "test")
    }

    @Test func stripPunctuationPreservesLettersAndDigits() {
        let result = WordTimingAligner.stripPunctuation("hello123")
        #expect(result == "hello123")
    }

    // MARK: - extractWordTimings (character-weighted fallback)

    @Test func extractWordTimingsProportionalToCharCount() {
        // "Hello" = 5 chars, "world" = 5 chars -> equal split
        let timings = WordTimingAligner.extractWordTimings(
            text: "Hello world", audioDuration: 2.0)
        #expect(timings.count == 2)
        #expect(abs(timings[0] - 1.0) < 0.001)
        #expect(abs(timings[1] - 1.0) < 0.001)
    }

    @Test func extractWordTimingsSumEqualsDuration() {
        let timings = WordTimingAligner.extractWordTimings(
            text: "The quick brown fox jumps", audioDuration: 5.0)
        let sum = timings.reduce(0, +)
        #expect(abs(sum - 5.0) < 0.0001)
    }

    @Test func extractWordTimingsEmptyText() {
        let timings = WordTimingAligner.extractWordTimings(
            text: "", audioDuration: 2.0)
        #expect(timings.isEmpty)
    }

    @Test func extractWordTimingsSingleWord() {
        let timings = WordTimingAligner.extractWordTimings(
            text: "Hello", audioDuration: 1.5)
        #expect(timings.count == 1)
        #expect(abs(timings[0] - 1.5) < 0.001)
    }

    @Test func extractWordTimingsUnequalCharCounts() {
        // "Hi" = 2 chars, "there" = 5 chars -> 2:5 ratio
        let timings = WordTimingAligner.extractWordTimings(
            text: "Hi there", audioDuration: 7.0)
        #expect(timings.count == 2)
        #expect(abs(timings[0] - 2.0) < 0.001)  // 2/7 * 7.0
        #expect(abs(timings[1] - 5.0) < 0.001)  // 5/7 * 7.0
    }
}
