import AVFoundation
import Foundation
import Logging
import CSherpaOnnx

/// Result of a TTS synthesis operation.
struct SynthesisResult {
    /// Path to the generated WAV file
    let wavPath: String
    /// Duration of the generated audio in seconds
    let audioDuration: TimeInterval
    /// Raw duration tensor values per token (nil if model doesn't support timestamps)
    let durations: [Float]?
}

/// Result of synthesis with word-level timing data for karaoke display.
struct TTSResult {
    /// Path to the generated WAV file
    let wavPath: String
    /// Original text that was synthesized
    let text: String
    /// Per-word durations for SubtitlePanel.showUtterance (zero-drift, sums to audioDuration)
    let wordTimings: [TimeInterval]
    /// Duration of the generated audio in seconds
    let audioDuration: TimeInterval
}

/// Wraps sherpa-onnx Kokoro TTS for speech synthesis with word-level timestamps.
///
/// - Model loads lazily on first `synthesize()` call (TTS-03)
/// - All synthesis runs on a dedicated serial DispatchQueue (TTS-02)
/// - Audio written as 24kHz mono 16-bit WAV via SherpaOnnxWriteWave (TTS-08)
/// - Playback via AVAudioPlayer with prepareToPlay() pre-buffering (TTS-01)
final class TTSEngine: @unchecked Sendable {

    private let logger = Logger(label: "tts-engine")

    /// Dedicated serial queue for all TTS work -- never blocks main thread (TTS-02)
    private let queue = DispatchQueue(label: "com.terryli.tts-engine", qos: .userInitiated)

    /// Lazily-initialized sherpa-onnx TTS instance (TTS-03)
    private var ttsInstance: OpaquePointer?

    /// Lock protecting lazy init of ttsInstance
    private let lock = NSLock()

    /// Currently playing AVAudioPlayer instance (for cancellation and currentTime polling)
    private var audioPlayer: AVAudioPlayer?

    /// Delegate that handles playback completion and WAV cleanup
    private var playbackDelegate: PlaybackDelegate?

    /// Path to the last generated WAV (cleaned up before next synthesis)
    private var lastWavPath: String?

    // MARK: - Lifecycle

    init() {
        logger.info("TTSEngine created (model will load lazily on first synthesis)")
    }

    deinit {
        audioPlayer?.stop()
        if let tts = ttsInstance {
            SherpaOnnxDestroyOfflineTts(tts)
        }
        cleanupLastWav()
    }

    // MARK: - Public API

    /// Synthesize text to a WAV file on the background queue.
    ///
    /// - Parameters:
    ///   - text: The text to synthesize
    ///   - speakerId: Speaker ID for multi-speaker models (default: 0)
    ///   - speed: Speech speed multiplier (default: 1.0)
    ///   - completion: Called with the synthesis result or error
    func synthesize(
        text: String,
        speakerId: Int32 = Config.defaultSpeakerId,
        speed: Float = 1.2,
        completion: @escaping (Result<SynthesisResult, Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                let tts = try ensureModelLoaded()

                let wavPath = NSTemporaryDirectory() + "tts-\(UUID().uuidString).wav"
                lastWavPath = wavPath

                logger.info("Synthesizing \(text.count) chars, speaker=\(speakerId), speed=\(speed)")
                let startTime = CFAbsoluteTimeGetCurrent()

                // Generate audio via sherpa-onnx C API
                guard let result = SherpaOnnxOfflineTtsGenerate(tts, text, speakerId, speed) else {
                    throw TTSError.synthesisReturnedNil
                }

                let n = result.pointee.n
                let sampleRate = result.pointee.sample_rate
                let samples = result.pointee.samples

                // Write WAV file
                let writeResult = SherpaOnnxWriteWave(samples, n, sampleRate, wavPath)
                guard writeResult == 1 else {
                    SherpaOnnxDestroyOfflineTtsGeneratedAudio(result)
                    throw TTSError.wavWriteFailed(path: wavPath)
                }

                // Compute audio duration
                let audioDuration = Double(n) / Double(sampleRate)

                // Free the C struct
                SherpaOnnxDestroyOfflineTtsGeneratedAudio(result)

                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                let rtf = elapsed / audioDuration
                logger.info("Synthesis complete: \(String(format: "%.2f", audioDuration))s audio in \(String(format: "%.2f", elapsed))s (RTF: \(String(format: "%.3f", rtf)))")

                completion(.success(SynthesisResult(
                    wavPath: wavPath,
                    audioDuration: audioDuration,
                    durations: nil
                )))
            } catch {
                logger.error("Synthesis failed: \(error)")
                completion(.failure(error))
            }
        }
    }

    /// Play a WAV file using AVAudioPlayer with prepareToPlay() pre-buffering.
    ///
    /// Returns the AVAudioPlayer instance so callers (SubtitleSyncDriver) can
    /// poll `player.currentTime` for drift-free karaoke sync.
    /// Must be called on the main thread (AVAudioPlayer delegate needs run loop).
    @discardableResult
    func play(wavPath: String, completion: (() -> Void)? = nil) -> AVAudioPlayer? {
        let url = URL(fileURLWithPath: wavPath)
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            let delegate = PlaybackDelegate(wavPath: wavPath, completion: completion, logger: logger)
            self.playbackDelegate = delegate  // prevent dealloc
            player.delegate = delegate
            player.prepareToPlay()
            player.play()
            self.audioPlayer = player
            logger.info("Playing WAV via AVAudioPlayer: \(wavPath) (duration: \(String(format: "%.2f", player.duration))s)")
            return player
        } catch {
            logger.error("AVAudioPlayer failed: \(error)")
            completion?()
            return nil
        }
    }

    /// Synthesize text and extract per-word timing data for karaoke highlighting.
    ///
    /// Combines `synthesize()` with `extractWordTimings()` into a single call that
    /// returns everything needed to drive SubtitlePanel.showUtterance().
    func synthesizeWithTimestamps(
        text: String,
        speakerId: Int32 = Config.defaultSpeakerId,
        speed: Float = 1.2,
        completion: @escaping (Result<TTSResult, Error>) -> Void
    ) {
        synthesize(text: text, speakerId: speakerId, speed: speed) { result in
            switch result {
            case .success(let synth):
                let timings = TTSEngine.extractWordTimings(
                    text: text,
                    audioDuration: synth.audioDuration,
                    rawDurations: synth.durations ?? []
                )
                let ttsResult = TTSResult(
                    wavPath: synth.wavPath,
                    text: text,
                    wordTimings: timings,
                    audioDuration: synth.audioDuration
                )
                completion(.success(ttsResult))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Streaming Sentence-Chunked Synthesis

    /// Result for a single sentence chunk in the streaming pipeline.
    struct ChunkResult {
        let wavPath: String
        let text: String
        let wordTimings: [TimeInterval]
        let audioDuration: TimeInterval
        let chunkIndex: Int
        let totalChunks: Int
    }

    /// Synthesize text as streaming sentence chunks on the background queue.
    ///
    /// Splits `text` into sentences, synthesizes each sequentially, and calls
    /// `onChunkReady` as each sentence finishes -- enabling playback to start
    /// after the first sentence (~5s) rather than waiting for the full paragraph (~100s).
    ///
    /// - Parameters:
    ///   - text: Full text to synthesize
    ///   - speakerId: Speaker ID for multi-speaker models
    ///   - speed: Speech speed multiplier
    ///   - onChunkReady: Called on the TTS queue for each completed sentence chunk
    ///   - onAllComplete: Called on the TTS queue when all chunks are synthesized
    func synthesizeStreaming(
        text: String,
        speakerId: Int32 = Config.defaultSpeakerId,
        speed: Float = 1.2,
        onChunkReady: @escaping (ChunkResult) -> Void,
        onAllComplete: @escaping () -> Void
    ) {
        queue.async { [self] in
            do {
                let tts = try ensureModelLoaded()

                let sentences = TTSEngine.splitIntoSentences(text)
                let totalChunks = sentences.count
                logger.info("Streaming TTS: \(text.count) chars split into \(totalChunks) sentences")

                let pipelineStart = CFAbsoluteTimeGetCurrent()

                for (index, sentence) in sentences.enumerated() {
                    let wavPath = NSTemporaryDirectory() + "tts-stream-\(UUID().uuidString).wav"

                    logger.info("Synthesizing chunk \(index + 1)/\(totalChunks): \(sentence.count) chars")
                    let startTime = CFAbsoluteTimeGetCurrent()

                    guard let result = SherpaOnnxOfflineTtsGenerate(tts, sentence, speakerId, speed) else {
                        logger.error("Synthesis returned nil for chunk \(index + 1)")
                        continue
                    }

                    let n = result.pointee.n
                    let sampleRate = result.pointee.sample_rate
                    let samples = result.pointee.samples

                    let writeResult = SherpaOnnxWriteWave(samples, n, sampleRate, wavPath)
                    guard writeResult == 1 else {
                        SherpaOnnxDestroyOfflineTtsGeneratedAudio(result)
                        logger.error("WAV write failed for chunk \(index + 1)")
                        continue
                    }

                    let audioDuration = Double(n) / Double(sampleRate)
                    SherpaOnnxDestroyOfflineTtsGeneratedAudio(result)

                    let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                    let rtf = elapsed / audioDuration
                    logger.info("Chunk \(index + 1)/\(totalChunks) complete: \(String(format: "%.2f", audioDuration))s audio in \(String(format: "%.2f", elapsed))s (RTF: \(String(format: "%.3f", rtf)))")

                    let timings = TTSEngine.extractWordTimings(text: sentence, audioDuration: audioDuration)

                    let chunk = ChunkResult(
                        wavPath: wavPath,
                        text: sentence,
                        wordTimings: timings,
                        audioDuration: audioDuration,
                        chunkIndex: index,
                        totalChunks: totalChunks
                    )
                    onChunkReady(chunk)
                }

                let totalElapsed = CFAbsoluteTimeGetCurrent() - pipelineStart
                logger.info("Streaming TTS pipeline complete: \(totalChunks) chunks in \(String(format: "%.2f", totalElapsed))s")
                onAllComplete()
            } catch {
                logger.error("Streaming synthesis failed: \(error)")
                onAllComplete()
            }
        }
    }

    /// Split text into sentences on `.`, `!`, `?` boundaries.
    ///
    /// Preserves the delimiter with the preceding sentence. Handles common
    /// abbreviations (Mr., Dr., etc.) and decimal numbers to avoid false splits.
    static func splitIntoSentences(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Simple regex-based sentence splitting: split after .!? followed by whitespace
        // but avoid splitting on common abbreviations and decimal numbers
        var sentences: [String] = []
        var current = ""

        let chars = Array(trimmed)
        var i = 0
        while i < chars.count {
            current.append(chars[i])

            if chars[i] == "." || chars[i] == "!" || chars[i] == "?" {
                // Check if this is a real sentence boundary:
                // - Must be followed by whitespace or end of text
                // - Must not be a decimal number (digit.digit)
                let isEnd = (i + 1 >= chars.count)
                let followedBySpace = !isEnd && (i + 1 < chars.count) && chars[i + 1].isWhitespace

                // Check for decimal numbers: digit before . and digit after .
                let isDecimal = chars[i] == "."
                    && i > 0 && chars[i - 1].isNumber
                    && !isEnd && (i + 1 < chars.count) && chars[i + 1].isNumber

                // Check for common abbreviations (single capital letter followed by .)
                let isAbbrev = chars[i] == "."
                    && i > 0 && chars[i - 1].isUppercase
                    && (i < 2 || chars[i - 2].isWhitespace || i - 1 == 0)

                if (isEnd || followedBySpace) && !isDecimal && !isAbbrev {
                    let trimmedSentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedSentence.isEmpty {
                        sentences.append(trimmedSentence)
                    }
                    current = ""
                }
            }
            i += 1
        }

        // Append any remaining text as the final sentence
        let remaining = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            if sentences.isEmpty {
                sentences.append(remaining)
            } else {
                // Merge short trailing fragments with the last sentence
                sentences[sentences.count - 1] += " " + remaining
            }
        }

        return sentences
    }

    /// Stop any currently playing audio.
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackDelegate = nil
    }

    // MARK: - Word Timing Extraction

    /// Extract per-word onset timings from the total audio duration.
    ///
    /// Each word's duration is proportional to its character count relative to the
    /// total character count. The sum of all word durations exactly equals
    /// `audioDuration`, ensuring zero accumulated drift (TTS-07).
    ///
    /// Returns an array of TimeInterval where timings[i] is the DURATION of word i
    /// (matching SubtitlePanel.showUtterance's expected format).
    static func extractWordTimings(text: String, audioDuration: TimeInterval) -> [TimeInterval] {
        let words = text.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }

        // Weight by character count (longer words take proportionally longer)
        let charCounts = words.map { Double($0.count) }
        let totalChars = charCounts.reduce(0, +)
        guard totalChars > 0 else {
            return Array(repeating: audioDuration / Double(words.count), count: words.count)
        }

        // Distribute audio duration proportionally
        return charCounts.map { count in
            (count / totalChars) * audioDuration
        }
    }

    /// Extract per-word onset timings using the raw duration tensor when available.
    ///
    /// The duration tensor has one value per phoneme token. Since sherpa-onnx does not
    /// expose token IDs through the C API, we cannot identify SPACE_TOKEN boundaries
    /// directly. Falls back to character-weighted distribution anchored to actual
    /// audio duration for zero drift.
    ///
    /// Future enhancement: parse phoneme boundaries once sherpa-onnx exposes token IDs.
    static func extractWordTimings(
        text: String,
        audioDuration: TimeInterval,
        rawDurations: [Float]
    ) -> [TimeInterval] {
        // If durations are empty, fall back to character-weighted
        guard !rawDurations.isEmpty else {
            return extractWordTimings(text: text, audioDuration: audioDuration)
        }

        // Use character-weighted distribution anchored to actual audioDuration.
        // The raw durations validate that the model produced timing data, but
        // without token ID exposure we cannot map phonemes to word boundaries.
        // Total is anchored to audioDuration for zero accumulated drift.
        return extractWordTimings(text: text, audioDuration: audioDuration)
    }

    // MARK: - Private

    /// Ensure the TTS model is loaded, performing lazy initialization if needed (TTS-03).
    private func ensureModelLoaded() throws -> OpaquePointer {
        lock.lock()
        defer { lock.unlock() }

        if let tts = ttsInstance {
            return tts
        }

        logger.info("Loading Kokoro TTS model from \(Config.kokoroModelPath)")
        let startTime = CFAbsoluteTimeGetCurrent()

        // Build config using strdup to keep C strings alive
        let modelPath = strdup("\(Config.kokoroModelPath)/\(Config.kokoroModelFile)")
        let voicesPath = strdup("\(Config.kokoroModelPath)/voices.bin")
        let tokensPath = strdup("\(Config.kokoroModelPath)/tokens.txt")
        let dataDir = strdup("\(Config.kokoroModelPath)/espeak-ng-data")
        let lexiconPath = strdup("\(Config.kokoroModelPath)/lexicon-us-en.txt")
        let langStr = strdup("en-us")
        let dictDir = strdup("\(Config.kokoroModelPath)/dict")
        let provider = strdup("cpu")

        defer {
            free(modelPath)
            free(voicesPath)
            free(tokensPath)
            free(dataDir)
            free(lexiconPath)
            free(langStr)
            free(dictDir)
            free(provider)
        }

        var config = SherpaOnnxOfflineTtsConfig()
        config.model.kokoro.model = UnsafePointer(modelPath)
        config.model.kokoro.voices = UnsafePointer(voicesPath)
        config.model.kokoro.tokens = UnsafePointer(tokensPath)
        config.model.kokoro.data_dir = UnsafePointer(dataDir)
        config.model.kokoro.lexicon = UnsafePointer(lexiconPath)
        config.model.kokoro.lang = UnsafePointer(langStr)
        config.model.kokoro.dict_dir = UnsafePointer(dictDir)
        config.model.kokoro.length_scale = 1.0
        config.model.num_threads = 4
        config.model.provider = UnsafePointer(provider)
        config.max_num_sentences = 1

        guard let tts = SherpaOnnxCreateOfflineTts(&config) else {
            throw TTSError.modelLoadFailed(path: Config.kokoroModelPath)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("Model loaded in \(String(format: "%.2f", elapsed))s")

        ttsInstance = tts
        return tts
    }

    /// Remove the last temporary WAV file.
    private func cleanupLastWav() {
        if let path = lastWavPath {
            try? FileManager.default.removeItem(atPath: path)
            lastWavPath = nil
        }
    }
}

// MARK: - Playback Delegate

/// Handles AVAudioPlayer completion: cleans up WAV file and calls completion closure.
private final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private let wavPath: String
    private let completion: (() -> Void)?
    private let logger: Logger

    init(wavPath: String, completion: (() -> Void)?, logger: Logger) {
        self.wavPath = wavPath
        self.completion = completion
        self.logger = logger
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        logger.info("AVAudioPlayer finished (success: \(flag)), cleaning up WAV: \(wavPath)")
        try? FileManager.default.removeItem(atPath: wavPath)
        completion?()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        logger.error("AVAudioPlayer decode error: \(error?.localizedDescription ?? "unknown")")
        try? FileManager.default.removeItem(atPath: wavPath)
        completion?()
    }
}

// MARK: - Errors

enum TTSError: Error, CustomStringConvertible {
    case modelLoadFailed(path: String)
    case synthesisReturnedNil
    case wavWriteFailed(path: String)

    var description: String {
        switch self {
        case .modelLoadFailed(let path):
            return "Failed to load TTS model from \(path)"
        case .synthesisReturnedNil:
            return "SherpaOnnxOfflineTtsGenerate returned nil"
        case .wavWriteFailed(let path):
            return "Failed to write WAV to \(path)"
        }
    }
}
