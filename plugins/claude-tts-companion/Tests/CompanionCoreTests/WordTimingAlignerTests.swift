@testable import CompanionCore
import Testing

@Suite struct WordTimingAlignerTests {

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
