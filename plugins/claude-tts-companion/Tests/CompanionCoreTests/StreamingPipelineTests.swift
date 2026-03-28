@testable import CompanionCore
import Foundation
import Testing

/// Integration tests for the streaming TTS pipeline:
/// SentenceSplitter -> SubtitleChunker -> WordTimingAligner
///
/// Exercises the real pipeline components together with mock audio durations
/// (no actual synthesis). Verifies correct sequencing, word coverage, and timing.
@Suite(.serialized)
@MainActor
struct StreamingPipelineTests {

    /// Helper: run the full pipeline on input text with a given per-sentence mock duration.
    /// Returns (sentences, pages-per-sentence, timings-per-sentence).
    private func runPipeline(
        text: String,
        durationPerSentence: TimeInterval
    ) -> (sentences: [String], pages: [[SubtitlePage]], timings: [[TimeInterval]]) {
        let sentences = SentenceSplitter.splitIntoSentences(text)
        var allPages: [[SubtitlePage]] = []
        var allTimings: [[TimeInterval]] = []

        for sentence in sentences {
            let pages = SubtitleChunker.chunkIntoPages(text: sentence)
            let timings = WordTimingAligner.extractWordTimings(
                text: sentence, audioDuration: durationPerSentence
            )
            allPages.append(pages)
            allTimings.append(timings)
        }

        return (sentences, allPages, allTimings)
    }

    @Test func multiSentenceProducesSequencedChunks() {
        let text = "The quick brown fox jumped over the lazy dog. It was a sunny day in the park. Birds were singing loudly."
        let result = runPipeline(text: text, durationPerSentence: 2.0)

        // Should produce 3 sentences
        #expect(result.sentences.count == 3)

        // Each sentence should have at least one page
        for (i, pages) in result.pages.enumerated() {
            #expect(!pages.isEmpty, "Sentence \(i) should have pages")
        }

        // All words from each sentence should be present in its pages
        for (i, sentence) in result.sentences.enumerated() {
            let sentenceWords = sentence.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace }).map(String.init)
            let pageWords = result.pages[i].flatMap { $0.words }
            #expect(pageWords.count == sentenceWords.count,
                    "Sentence \(i): page words (\(pageWords.count)) should match sentence words (\(sentenceWords.count))")
        }

        // Timings for each sentence should sum to 2.0s
        for (i, timings) in result.timings.enumerated() {
            let sum = timings.reduce(0, +)
            #expect(abs(sum - 2.0) < 0.001,
                    "Sentence \(i) timings sum \(sum) should equal 2.0")
        }
    }

    @Test func singleSentenceProducesOneChunk() {
        let text = "Hello world this is a test"
        let result = runPipeline(text: text, durationPerSentence: 1.5)

        #expect(result.sentences.count == 1)

        // Pages should cover all 6 words
        let allWords = result.pages[0].flatMap { $0.words }
        #expect(allWords.count == 6)

        // Timings should sum to 1.5s
        let sum = result.timings[0].reduce(0, +)
        #expect(abs(sum - 1.5) < 0.001)
    }

    @Test func emptyTextProducesNoChunks() {
        let sentences = SentenceSplitter.splitIntoSentences("")
        #expect(sentences.isEmpty)
    }

    @Test func wordOrderPreservedAcrossChunks() {
        let text = "First part of text. Second part of text. Third part of text."
        let result = runPipeline(text: text, durationPerSentence: 1.0)

        // Collect all words from all pages across all sentences in order
        var allCollectedWords: [String] = []
        for pages in result.pages {
            for page in pages {
                allCollectedWords.append(contentsOf: page.words)
            }
        }

        // Reconstruct expected words from the original sentences (after splitting)
        var expectedWords: [String] = []
        for sentence in result.sentences {
            let words = sentence.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace }).map(String.init)
            expectedWords.append(contentsOf: words)
        }

        #expect(allCollectedWords == expectedWords,
                "Words should be preserved in order across all chunks")
    }

    @Test func timingsSumToAudioDuration() {
        let text = "Testing that durations are correct."
        let duration = 3.0
        let timings = WordTimingAligner.extractWordTimings(text: text, audioDuration: duration)
        let sum = timings.reduce(0, +)
        #expect(abs(sum - 3.0) < 0.001,
                "Timings sum \(sum) should equal audio duration 3.0")
    }
}
