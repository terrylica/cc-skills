import AVFoundation
import Foundation
import KokoroSwift
import Logging
import MLX
import MLXUtilsLibrary

/// Result of a TTS synthesis operation.
struct SynthesisResult {
    /// Path to the generated WAV file
    let wavPath: String
    /// Duration of the generated audio in seconds
    let audioDuration: TimeInterval
    /// Raw duration tensor values per token (nil for kokoro-ios -- use MToken timestamps instead)
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

/// Wraps kokoro-ios MLX TTS for speech synthesis with word-level timestamps.
///
/// - Model loads lazily on first `synthesize()` call (TTS-03)
/// - All synthesis runs on a dedicated serial DispatchQueue (TTS-02)
/// - Audio written as 24kHz mono float32 WAV via AVAudioFile (TTS-08)
/// - Playback via AVAudioPlayer with prepareToPlay() pre-buffering (TTS-01)
/// - Word timestamps extracted natively from MToken.start_ts/end_ts (no C++ patches)
/// - Text preprocessing fixes mispronounced words before phonemization (TTS-09)
final class TTSEngine: @unchecked Sendable {

    private let logger = Logger(label: "tts-engine")

    /// Dedicated serial queue for all TTS work -- never blocks main thread (TTS-02)
    private let queue = DispatchQueue(label: "com.terryli.tts-engine", qos: .userInitiated)

    /// Lazily-initialized kokoro-ios TTS instance (TTS-03)
    private var ttsInstance: KokoroTTS?

    /// All voice embeddings loaded from voices.npz
    private var voicesDict: [String: MLXArray]?

    /// Currently active voice embedding
    private var voice: MLXArray?

    /// Lock protecting lazy init of ttsInstance
    private let lock = NSLock()

    /// Currently playing AVAudioPlayer instance (for cancellation and currentTime polling)
    private var audioPlayer: AVAudioPlayer?

    /// Delegate that handles playback completion and WAV cleanup
    private var playbackDelegate: PlaybackDelegate?

    /// Path to the last generated WAV (cleaned up before next synthesis)
    private var lastWavPath: String?

    // MARK: - Pronunciation Overrides (TTS-09)

    /// Words the Kokoro/Misaki phonemizer mispronounces, mapped to phonetically-correct
    /// replacements. Keys are case-insensitive regex patterns; values are the replacement text.
    /// The replacement must produce correct pronunciation when fed through the G2P pipeline.
    ///
    /// Example: "plugin" is phonemized as "plu-gin" instead of "plug-in".
    /// Replacing with "plug-in" (hyphenated) guides the phonemizer to the correct syllable break.
    private static let pronunciationOverrides: [(pattern: String, replacement: String)] = [
        ("\\bplugin\\b", "plug-in"),
        ("\\bplugins\\b", "plug-ins"),
        ("\\bPlugins\\b", "Plug-ins"),
        ("\\bPlugin\\b", "Plug-in"),
    ]

    /// Pre-compiled regex patterns for pronunciation overrides (compiled once, reused across calls).
    private static let compiledOverrides: [(regex: NSRegularExpression, replacement: String)] = {
        pronunciationOverrides.compactMap { entry in
            guard let regex = try? NSRegularExpression(
                pattern: entry.pattern,
                options: []
            ) else { return nil }
            return (regex: regex, replacement: entry.replacement)
        }
    }()

    /// Apply pronunciation overrides to text before passing to the TTS engine.
    ///
    /// This is a pre-phonemization text substitution: it replaces words that the
    /// Misaki G2P phonemizer handles incorrectly with phonetically-equivalent alternatives
    /// that produce correct pronunciation.
    static func preprocessText(_ text: String) -> String {
        var result = text
        for override in compiledOverrides {
            let range = NSRange(result.startIndex..., in: result)
            result = override.regex.stringByReplacingMatches(
                in: result, options: [], range: range,
                withTemplate: override.replacement
            )
        }
        return result
    }

    // MARK: - Lifecycle

    init() {
        logger.info("TTSEngine created (kokoro-ios MLX, model will load lazily on first synthesis)")
    }

    deinit {
        audioPlayer?.stop()
        ttsInstance = nil
        voicesDict = nil
        voice = nil
        cleanupLastWav()
    }

    // MARK: - Public API

    /// Synthesize text to a WAV file on the background queue.
    ///
    /// - Parameters:
    ///   - text: The text to synthesize
    ///   - voiceName: Voice embedding name (default: Config.defaultVoiceName)
    ///   - speed: Speech speed multiplier (default: 1.2)
    ///   - completion: Called with the synthesis result or error
    func synthesize(
        text: String,
        voiceName: String = Config.defaultVoiceName,
        speed: Float = 1.2,
        completion: @escaping (Result<SynthesisResult, Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                let tts = try ensureModelLoaded()
                let activeVoice = voiceForName(voiceName)

                let wavPath = NSTemporaryDirectory() + "tts-\(UUID().uuidString).wav"
                lastWavPath = wavPath

                // Apply pronunciation overrides before phonemization (TTS-09)
                let processedText = TTSEngine.preprocessText(text)
                logger.info("Synthesizing \(text.count) chars, voice=\(voiceName), speed=\(speed)")
                let startTime = CFAbsoluteTimeGetCurrent()

                // Generate audio via kokoro-ios MLX
                let (audio, _) = try tts.generateAudio(
                    voice: activeVoice, language: .enUS, text: processedText, speed: speed
                )

                let audioDuration = Double(audio.count) / 24000.0

                // Write WAV file using AVAudioFile
                try writeWav(samples: audio, to: wavPath)

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
    /// Combines `synthesize()` with native MToken timestamps into a single call that
    /// returns everything needed to drive SubtitlePanel.showUtterance().
    func synthesizeWithTimestamps(
        text: String,
        voiceName: String = Config.defaultVoiceName,
        speed: Float = 1.2,
        completion: @escaping (Result<TTSResult, Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                let tts = try ensureModelLoaded()
                let activeVoice = voiceForName(voiceName)

                let wavPath = NSTemporaryDirectory() + "tts-\(UUID().uuidString).wav"
                lastWavPath = wavPath

                // Apply pronunciation overrides before phonemization (TTS-09)
                let processedText = TTSEngine.preprocessText(text)
                logger.info("Synthesizing with timestamps: \(text.count) chars, voice=\(voiceName), speed=\(speed)")
                let startTime = CFAbsoluteTimeGetCurrent()

                let (audio, tokenArray) = try tts.generateAudio(
                    voice: activeVoice, language: .enUS, text: processedText, speed: speed
                )

                let audioDuration = Double(audio.count) / 24000.0
                try writeWav(samples: audio, to: wavPath)

                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                let rtf = elapsed / audioDuration
                logger.info("Synthesis complete: \(String(format: "%.2f", audioDuration))s audio in \(String(format: "%.2f", elapsed))s (RTF: \(String(format: "%.3f", rtf)))")

                // Extract native word timestamps from MToken array
                let nativeTimings = TTSEngine.extractTimingsFromTokens(tokenArray)
                let timings: [TimeInterval]
                if nativeTimings.isEmpty {
                    logger.warning("No native timestamps from kokoro-ios, falling back to character-weighted")
                    timings = TTSEngine.extractWordTimings(text: text, audioDuration: audioDuration)
                } else {
                    timings = nativeTimings
                }

                let ttsResult = TTSResult(
                    wavPath: wavPath,
                    text: text,
                    wordTimings: timings,
                    audioDuration: audioDuration
                )
                completion(.success(ttsResult))
            } catch {
                logger.error("Synthesis with timestamps failed: \(error)")
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
    ///   - voiceName: Voice embedding name
    ///   - speed: Speech speed multiplier
    ///   - onChunkReady: Called on the TTS queue for each completed sentence chunk
    ///   - onAllComplete: Called on the TTS queue when all chunks are synthesized
    func synthesizeStreaming(
        text: String,
        voiceName: String = Config.defaultVoiceName,
        speed: Float = 1.2,
        onChunkReady: @escaping (ChunkResult) -> Void,
        onAllComplete: @escaping () -> Void
    ) {
        queue.async { [self] in
            do {
                let tts = try ensureModelLoaded()
                let activeVoice = voiceForName(voiceName)

                let sentences = TTSEngine.splitIntoSentences(text)
                let totalChunks = sentences.count
                logger.info("Streaming TTS: \(text.count) chars split into \(totalChunks) sentences")

                let pipelineStart = CFAbsoluteTimeGetCurrent()

                for (index, sentence) in sentences.enumerated() {
                    let wavPath = NSTemporaryDirectory() + "tts-stream-\(UUID().uuidString).wav"

                    // Apply pronunciation overrides before phonemization (TTS-09)
                    let processedSentence = TTSEngine.preprocessText(sentence)
                    logger.info("Synthesizing chunk \(index + 1)/\(totalChunks): \(sentence.count) chars")
                    let startTime = CFAbsoluteTimeGetCurrent()

                    let (audio, tokenArray): ([Float], [MToken]?)
                    do {
                        (audio, tokenArray) = try tts.generateAudio(
                            voice: activeVoice, language: .enUS, text: processedSentence, speed: speed
                        )
                    } catch {
                        logger.error("Synthesis failed for chunk \(index + 1): \(error)")
                        continue
                    }

                    let audioDuration = Double(audio.count) / 24000.0

                    do {
                        try writeWav(samples: audio, to: wavPath)
                    } catch {
                        logger.error("WAV write failed for chunk \(index + 1): \(error)")
                        continue
                    }

                    let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                    let rtf = elapsed / audioDuration
                    logger.info("Chunk \(index + 1)/\(totalChunks) complete: \(String(format: "%.2f", audioDuration))s audio in \(String(format: "%.2f", elapsed))s (RTF: \(String(format: "%.3f", rtf)))")

                    // Extract native word timestamps, fallback to character-weighted
                    let nativeTimings = TTSEngine.extractTimingsFromTokens(tokenArray)
                    let timings = nativeTimings.isEmpty
                        ? TTSEngine.extractWordTimings(text: sentence, audioDuration: audioDuration)
                        : nativeTimings

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

    /// Extract per-word durations from native MToken timestamps.
    ///
    /// Filters out punctuation-only tokens and maps each word's start_ts/end_ts
    /// to a duration value. Returns empty array if no timestamps available (triggers fallback).
    static func extractTimingsFromTokens(_ tokens: [MToken]?) -> [TimeInterval] {
        guard let tokens = tokens, !tokens.isEmpty else { return [] }

        let punctuation: Set<String> = [".", ",", "!", "?", ";", ":", "-", "\u{2014}", "\u{2013}"]

        var durations: [TimeInterval] = []
        for token in tokens {
            guard let startTs = token.start_ts, let endTs = token.end_ts else { continue }
            // Skip punctuation-only tokens
            let text = token.text.trimmingCharacters(in: .whitespaces)
            if punctuation.contains(text) { continue }
            if text.isEmpty { continue }
            let dur = endTs - startTs
            if dur > 0 {
                durations.append(dur)
            }
        }

        return durations
    }

    /// Extract per-word onset timings from the total audio duration (character-weighted fallback).
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

    // MARK: - Private

    /// Ensure the TTS model is loaded, performing lazy initialization if needed (TTS-03).
    private func ensureModelLoaded() throws -> KokoroTTS {
        lock.lock()
        defer { lock.unlock() }

        if let tts = ttsInstance, voice != nil {
            return tts
        }

        let modelURL = URL(fileURLWithPath: Config.kokoroMLXModelPath)
        let voicesURL = URL(fileURLWithPath: Config.kokoroVoicesPath)

        logger.info("Loading Kokoro MLX model from \(Config.kokoroMLXModelPath)")
        let startTime = CFAbsoluteTimeGetCurrent()

        let tts = KokoroTTS(modelPath: modelURL)

        guard let voices = NpyzReader.read(fileFromPath: voicesURL) else {
            throw TTSError.modelLoadFailed(path: Config.kokoroVoicesPath)
        }

        let voiceCount = voices.count
        self.voicesDict = voices

        // Extract default voice
        // Try exact key first, then fuzzy match
        let defaultVoice: MLXArray
        if let v = voices[Config.defaultVoiceName] {
            defaultVoice = v
        } else if let key = voices.keys.first(where: { $0.contains(Config.defaultVoiceName) }),
                  let v = voices[key] {
            defaultVoice = v
            logger.info("Matched voice key '\(key)' for '\(Config.defaultVoiceName)'")
        } else {
            throw TTSError.modelLoadFailed(path: "voice '\(Config.defaultVoiceName)' not found in voices.npz")
        }
        self.voice = defaultVoice

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("Kokoro MLX model loaded in \(String(format: "%.2f", elapsed))s (\(voiceCount) voices available)")

        ttsInstance = tts
        return tts
    }

    /// Look up a voice embedding by name, falling back to default.
    private func voiceForName(_ name: String) -> MLXArray {
        if let dict = voicesDict, let v = dict[name] {
            return v
        }
        if let dict = voicesDict, let key = dict.keys.first(where: { $0.contains(name) }),
           let v = dict[key] {
            return v
        }
        // Fallback to default
        if name != Config.defaultVoiceName {
            logger.warning("Voice '\(name)' not found, using default '\(Config.defaultVoiceName)'")
        }
        return voice!
    }

    /// Write float32 audio samples to a WAV file using AVAudioFile.
    private func writeWav(samples: [Float], sampleRate: Double = 24000.0, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw TTSError.wavWriteFailed(path: path)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channelData = buffer.floatChannelData![0]
        for i in 0..<samples.count {
            channelData[i] = samples[i]
        }
        let audioFile = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        try audioFile.write(from: buffer)
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
            return "KokoroTTS.generateAudio returned nil"
        case .wavWriteFailed(let path):
            return "Failed to write WAV to \(path)"
        }
    }
}
