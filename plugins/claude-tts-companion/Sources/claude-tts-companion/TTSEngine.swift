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
    /// Native word onset times from MToken.start_ts (nil when using character-weighted fallback).
    /// When present, these are the ground-truth onset times from the Kokoro duration model
    /// and should be used directly by SubtitleSyncDriver instead of cumulating wordTimings.
    let wordOnsets: [TimeInterval]?
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

    /// Whether the CoreAudio hardware has been warmed up by playing silence
    private var audioHardwareWarmed = false

    /// Timestamp of last successful audio playback start (for re-warm after idle)
    private var lastPlaybackTime: CFAbsoluteTime = 0

    /// If audio has been idle longer than this, re-warm before playing (seconds)
    private static let audioIdleThreshold: CFAbsoluteTime = 30.0

    /// Retained warm-up player to prevent ARC deallocation before playback completes.
    /// Without this, the local player variable in warmUpAudioHardware() may be
    /// deallocated before the 0.1s silent buffer finishes playing.
    private var warmUpPlayer: AVAudioPlayer?

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

    /// Number of chunks between periodic Metal cache clears during streaming synthesis.
    /// Every N chunks, Stream.gpu.synchronize() + Memory.clearCache() prevents Metal resource
    /// accumulation that leads to the 499000 resource limit crash on long sessions.
    private static let metalCacheClearInterval = 5

    /// Whether TTS is disabled due to missing model files at startup.
    /// When true, all synthesis calls return immediately with an error instead
    /// of crashing on first use.
    private(set) var isDisabledDueToMissingModel: Bool = false

    // MARK: - TTS Circuit Breaker (P1)

    /// Number of consecutive synthesis failures before disabling TTS temporarily.
    private static let circuitBreakerThreshold = 3

    /// Duration to keep TTS disabled after hitting the circuit breaker (seconds).
    private static let circuitBreakerCooldown: TimeInterval = 300  // 5 minutes

    /// Counter of consecutive synthesis failures (reset on success).
    private var consecutiveFailures: Int = 0

    /// Timestamp when TTS was disabled by the circuit breaker (nil = not tripped).
    private var circuitBreakerTrippedAt: CFAbsoluteTime?

    /// Lock protecting circuit breaker state (accessed from TTS queue and callers).
    private let circuitBreakerLock = NSLock()

    /// Check whether TTS is temporarily disabled by the circuit breaker.
    /// If the cooldown has elapsed, automatically re-enable.
    var isTTSCircuitBreakerOpen: Bool {
        circuitBreakerLock.lock()
        defer { circuitBreakerLock.unlock() }
        guard let trippedAt = circuitBreakerTrippedAt else { return false }
        if CFAbsoluteTimeGetCurrent() - trippedAt > TTSEngine.circuitBreakerCooldown {
            // Cooldown elapsed -- re-enable
            circuitBreakerTrippedAt = nil
            consecutiveFailures = 0
            logger.info("TTS circuit breaker reset after \(Int(TTSEngine.circuitBreakerCooldown))s cooldown")
            return false
        }
        return true
    }

    /// Record a synthesis success (resets failure counter).
    private func recordSynthesisSuccess() {
        circuitBreakerLock.lock()
        consecutiveFailures = 0
        circuitBreakerLock.unlock()
    }

    /// Record a synthesis failure. If threshold exceeded, trip the circuit breaker.
    private func recordSynthesisFailure() {
        circuitBreakerLock.lock()
        consecutiveFailures += 1
        let failures = consecutiveFailures
        if failures >= TTSEngine.circuitBreakerThreshold && circuitBreakerTrippedAt == nil {
            circuitBreakerTrippedAt = CFAbsoluteTimeGetCurrent()
            circuitBreakerLock.unlock()
            logger.error("TTS circuit breaker OPEN after \(failures) consecutive failures — TTS disabled for \(Int(TTSEngine.circuitBreakerCooldown))s")
        } else {
            circuitBreakerLock.unlock()
        }
    }

    init() {
        logger.info("TTSEngine created (kokoro-ios MLX, model will load lazily on first synthesis)")

        // Validate model files exist at boot to fail fast with a clear error
        // instead of crashing on first synthesis (P0: startup model validation).
        let fm = FileManager.default
        if !fm.fileExists(atPath: Config.kokoroMLXModelPath) {
            logger.critical("Kokoro MLX model not found at \(Config.kokoroMLXModelPath) — TTS disabled")
            isDisabledDueToMissingModel = true
        } else if !fm.fileExists(atPath: Config.kokoroVoicesPath) {
            logger.critical("Kokoro voices not found at \(Config.kokoroVoicesPath) — TTS disabled")
            isDisabledDueToMissingModel = true
        } else {
            logger.info("Model files validated: \(Config.kokoroMLXModelPath), \(Config.kokoroVoicesPath)")
        }

        // Set Metal GPU cache limit to 512MB to prevent unbounded buffer cache growth.
        // This is a defense-in-depth measure: even if clearCache() is called too late,
        // the hard cap prevents hitting the Metal 499000 resource limit.
        Memory.cacheLimit = 512 * 1024 * 1024
        logger.info("MLX GPU cache limit set to 512MB")

        // Pre-warm CoreAudio hardware so the first real play() doesn't stutter.
        // macOS powers down audio hardware after idle; re-init takes ~50-500ms
        // which causes choppy audio at the start of the first chunk.
        warmUpAudioHardware()
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
        guard !isDisabledDueToMissingModel else {
            completion(.failure(TTSError.modelLoadFailed(path: "TTS disabled — model files missing at startup")))
            return
        }
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
        // Re-warm CoreAudio if idle too long (hardware powers down after ~30s idle)
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastPlaybackTime > TTSEngine.audioIdleThreshold {
            logger.info("Audio idle >\(Int(TTSEngine.audioIdleThreshold))s, re-warming CoreAudio hardware")
            warmUpAudioHardware()
        }

        let url = URL(fileURLWithPath: wavPath)
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            let delegate = PlaybackDelegate(wavPath: wavPath, completion: completion, logger: logger)
            self.playbackDelegate = delegate  // prevent dealloc
            player.delegate = delegate
            if !player.prepareToPlay() {
                logger.warning("prepareToPlay() failed for WAV: \(wavPath) — attempting play() anyway")
            }
            if !player.play() {
                logger.error("play() failed for WAV: \(wavPath)")
                completion?()
                return nil
            }
            self.audioPlayer = player
            self.lastPlaybackTime = now
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
        guard !isDisabledDueToMissingModel else {
            completion(.failure(TTSError.modelLoadFailed(path: "TTS disabled — model files missing at startup")))
            return
        }
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

                // Extract native word timestamps from MToken array and align to subtitle words.
                // MTokens are linguistic tokens (NLTokenizer) which may not match whitespace-split
                // words used by SubtitleChunker. alignOnsetsToWords() resolves the mismatch.
                let nativeTimings = TTSEngine.extractTimingsFromTokens(tokenArray)
                let subtitleWords = text.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace).map(String.init)
                let timings: [TimeInterval]
                let onsets: [TimeInterval]?
                if let native = nativeTimings,
                   let aligned = TTSEngine.alignOnsetsToWords(native: native, subtitleWords: subtitleWords, audioDuration: audioDuration) {
                    timings = aligned.durations
                    onsets = aligned.onsets
                    if native.texts.count != subtitleWords.count {
                        logger.info("Aligned \(native.texts.count) MToken words to \(subtitleWords.count) subtitle words")
                    }
                } else {
                    logger.warning("No native timestamps from kokoro-ios, falling back to character-weighted")
                    timings = TTSEngine.extractWordTimings(text: text, audioDuration: audioDuration)
                    onsets = nil
                }

                let ttsResult = TTSResult(
                    wavPath: wavPath,
                    text: text,
                    wordTimings: timings,
                    audioDuration: audioDuration,
                    wordOnsets: onsets
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
        /// Native word onset times from MToken.start_ts (nil when using character-weighted fallback)
        let wordOnsets: [TimeInterval]?
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
        guard !isDisabledDueToMissingModel else {
            logger.error("TTS disabled — model files missing at startup, skipping streaming synthesis")
            onAllComplete()
            return
        }
        guard !isTTSCircuitBreakerOpen else {
            logger.warning("TTS circuit breaker open — skipping streaming synthesis (\(text.count) chars)")
            onAllComplete()
            return
        }
        queue.async { [self] in
            do {
                // Release cached Metal buffers from previous synthesis sessions.
                // Stream.gpu.synchronize() ensures all in-flight Metal commands complete first,
                // making their buffers eligible for release. Without this, back-to-back
                // streaming sessions accumulate metal resources until hitting the
                // 499000 resource limit, crashing the process with:
                //   [metal::malloc] Resource limit (499000) exceeded
                Stream.gpu.synchronize()
                Memory.clearCache()

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
                        recordSynthesisSuccess()
                    } catch {
                        logger.error("Synthesis failed for chunk \(index + 1): \(error)")
                        recordSynthesisFailure()
                        if isTTSCircuitBreakerOpen {
                            logger.error("TTS circuit breaker tripped mid-stream — aborting remaining chunks")
                            break
                        }
                        continue
                    }

                    let audioDuration = Double(audio.count) / 24000.0

                    // Append trailing silence to prevent choppy audio at sentence boundaries.
                    // TTS models produce trailing energy (formant decay) that gets truncated
                    // at the last sample. Padding with 100ms of silence lets the waveform
                    // decay naturally and masks the poll-based chunk transition gap.
                    let paddedAudio = audio + [Float](repeating: 0.0, count: TTSEngine.trailingSilenceSamples)

                    do {
                        try writeWav(samples: paddedAudio, to: wavPath)
                    } catch {
                        logger.error("WAV write failed for chunk \(index + 1): \(error)")
                        continue
                    }

                    let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                    let rtf = elapsed / audioDuration
                    logger.info("Chunk \(index + 1)/\(totalChunks) complete: \(String(format: "%.2f", audioDuration))s audio in \(String(format: "%.2f", elapsed))s (RTF: \(String(format: "%.3f", rtf)))")

                    // Extract native word timestamps and align to subtitle words.
                    // MTokens (NLTokenizer) may differ from whitespace-split subtitle words,
                    // so alignOnsetsToWords() maps MToken onsets onto the subtitle word positions.
                    let nativeResult = TTSEngine.extractTimingsFromTokens(tokenArray)
                    let subtitleWords = sentence.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace).map(String.init)
                    let timings: [TimeInterval]
                    let onsets: [TimeInterval]?
                    if let native = nativeResult,
                       let aligned = TTSEngine.alignOnsetsToWords(native: native, subtitleWords: subtitleWords, audioDuration: audioDuration) {
                        timings = aligned.durations
                        onsets = aligned.onsets
                        if native.texts.count != subtitleWords.count {
                            logger.info("Chunk \(index + 1): aligned \(native.texts.count) MToken words to \(subtitleWords.count) subtitle words")
                        }
                    } else {
                        timings = TTSEngine.extractWordTimings(text: sentence, audioDuration: audioDuration)
                        onsets = nil
                    }

                    let chunk = ChunkResult(
                        wavPath: wavPath,
                        text: sentence,
                        wordTimings: timings,
                        audioDuration: audioDuration,
                        chunkIndex: index,
                        totalChunks: totalChunks,
                        wordOnsets: onsets
                    )
                    onChunkReady(chunk)

                    // Periodic Metal cache clear to prevent resource accumulation
                    // on long sessions (>15 chunks). Without this, intermediate MLX
                    // tensors accumulate and eventually hit the Metal 499000 limit.
                    if (index + 1) % TTSEngine.metalCacheClearInterval == 0 {
                        Stream.gpu.synchronize()
                        Memory.clearCache()
                        logger.info("Periodic Metal cache clear after chunk \(index + 1)")
                    }
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

    /// Number of silence samples appended to each streaming chunk WAV.
    /// At 24kHz, 2400 samples = 100ms of trailing silence.
    /// This prevents choppy audio at sentence boundaries by giving the waveform
    /// room to decay naturally and masking the ~16ms poll-based chunk transition gap.
    private static let trailingSilenceSamples = 2400  // 100ms at 24kHz

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

    /// Create and prepare an AVAudioPlayer for a WAV file WITHOUT starting playback.
    ///
    /// Used by SubtitleSyncDriver to pre-buffer the next chunk while the current one
    /// is still playing, eliminating ~500ms-1s gaps between streaming chunks.
    /// The caller is responsible for calling play() when ready.
    ///
    /// - Returns: A tuple of (player, delegate) or nil if creation fails.
    ///   The caller MUST retain the delegate to prevent deallocation during playback.
    func preparePlayer(wavPath: String, completion: (() -> Void)? = nil) -> (player: AVAudioPlayer, delegate: PlaybackDelegate)? {
        let url = URL(fileURLWithPath: wavPath)
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            let delegate = PlaybackDelegate(wavPath: wavPath, completion: completion, logger: logger)
            player.delegate = delegate
            if !player.prepareToPlay() {
                logger.warning("prepareToPlay() failed for pre-buffered WAV: \(wavPath)")
            }
            logger.info("Pre-buffered AVAudioPlayer: \(wavPath) (duration: \(String(format: "%.2f", player.duration))s)")
            return (player: player, delegate: delegate)
        } catch {
            logger.error("preparePlayer failed: \(error)")
            return nil
        }
    }

    /// Stop any currently playing audio.
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackDelegate = nil
    }

    // MARK: - Word Timing Extraction

    /// Extracted native timing data from MToken array.
    struct NativeTimings {
        /// Per-word durations (end_ts - start_ts), used as fallback/display
        let durations: [TimeInterval]
        /// Per-word onset times (start_ts values), the ground-truth from the Kokoro duration model.
        /// These account for leading silence and inter-word gaps that duration-only extraction loses.
        let onsets: [TimeInterval]
        /// Per-word text from MTokens (linguistic tokens, may differ from whitespace-split words).
        /// Used by alignOnsetsToWords() to map MToken onsets onto subtitle word positions.
        let texts: [String]
    }

    /// Extract per-word durations AND onset times from native MToken timestamps.
    ///
    /// Returns both durations (end_ts - start_ts) and onset times (start_ts) for each word.
    /// Onset times are the ground truth from the Kokoro duration model and include leading
    /// silence and inter-word pauses. Using onsets directly in SubtitleSyncDriver avoids
    /// the ~275ms+ drift caused by cumulating durations from zero.
    ///
    /// Filters out punctuation-only tokens. Returns nil if no timestamps available.
    static func extractTimingsFromTokens(_ tokens: [MToken]?) -> NativeTimings? {
        guard let tokens = tokens, !tokens.isEmpty else { return nil }

        let punctuation: Set<String> = [".", ",", "!", "?", ";", ":", "-", "\u{2014}", "\u{2013}"]

        var durations: [TimeInterval] = []
        var onsets: [TimeInterval] = []
        var texts: [String] = []
        for token in tokens {
            guard let startTs = token.start_ts, let endTs = token.end_ts else { continue }
            // Skip punctuation-only tokens
            let text = token.text.trimmingCharacters(in: .whitespaces)
            if punctuation.contains(text) { continue }
            if text.isEmpty { continue }
            let dur = endTs - startTs
            if dur > 0 {
                onsets.append(startTs)
                durations.append(dur)
                texts.append(text)
            }
        }

        guard !durations.isEmpty else { return nil }
        return NativeTimings(durations: durations, onsets: onsets, texts: texts)
    }

    /// Align MToken-derived onset times to whitespace-split subtitle words.
    ///
    /// MTokens come from NLTokenizer (linguistic tokenization) while subtitles split by
    /// whitespace. These can differ: contractions may split differently, preprocessing
    /// may change word count ("plugin" -> "plug-in"), and hyphens/dashes may cause splits.
    ///
    /// This function walks both arrays using character-offset tracking to map each subtitle
    /// word to the MToken whose text overlaps it, producing one onset per subtitle word.
    ///
    /// Returns aligned (durations, onsets) arrays with count == subtitleWords.count,
    /// or nil if alignment fails badly (falls back to character-weighted).
    static func alignOnsetsToWords(
        native: NativeTimings,
        subtitleWords: [String],
        audioDuration: TimeInterval
    ) -> (durations: [TimeInterval], onsets: [TimeInterval])? {
        // Fast path: counts match -- assume 1:1 alignment (common case)
        if native.texts.count == subtitleWords.count {
            return (native.durations, native.onsets)
        }

        // Build character-position mapping.
        // Walk both sequences, consuming characters to find which MToken(s) cover each subtitle word.
        var alignedOnsets: [TimeInterval] = []
        var alignedDurations: [TimeInterval] = []

        // Build flat character streams (lowercase, stripped of leading/trailing punctuation)
        let tokenChars = native.texts.map { stripPunctuation($0).lowercased() }
        let subChars = subtitleWords.map { stripPunctuation($0).lowercased() }

        var ti = 0  // token index
        var tCharPos = 0  // character position within current token

        for si in 0..<subChars.count {
            let subWord = subChars[si]
            guard !subWord.isEmpty else {
                // Empty after stripping -- interpolate from neighbors
                if let lastOnset = alignedOnsets.last {
                    let lastDur = alignedDurations.last ?? 0.2
                    alignedOnsets.append(lastOnset + lastDur)
                    alignedDurations.append(0.1)
                } else {
                    alignedOnsets.append(0)
                    alignedDurations.append(0.1)
                }
                continue
            }

            // Assign onset from the token that covers the START of this subtitle word
            if ti < native.texts.count {
                alignedOnsets.append(native.onsets[ti])

                // Consume characters from tokens to cover this subtitle word
                var remaining = subWord.count
                var lastTokenUsed = ti

                while remaining > 0 && ti < native.texts.count {
                    let tokenRemaining = tokenChars[ti].count - tCharPos
                    if tokenRemaining <= remaining {
                        remaining -= tokenRemaining
                        lastTokenUsed = ti
                        ti += 1
                        tCharPos = 0
                    } else {
                        tCharPos += remaining
                        lastTokenUsed = ti
                        remaining = 0
                    }
                }

                // Duration: from onset of first token to end of last token used
                let startOnset = alignedOnsets.last!
                if lastTokenUsed < native.texts.count {
                    let endTime = native.onsets[lastTokenUsed] + native.durations[lastTokenUsed]
                    alignedDurations.append(endTime - startOnset)
                } else {
                    alignedDurations.append(native.durations.last ?? 0.2)
                }
            } else {
                // Ran out of tokens -- extrapolate from last known position
                let lastOnset = alignedOnsets.last ?? 0
                let lastDur = alignedDurations.last ?? 0.2
                alignedOnsets.append(lastOnset + lastDur)
                // Distribute remaining time evenly
                let remainingWords = subChars.count - si
                let remainingTime = max(0, audioDuration - (lastOnset + lastDur))
                alignedDurations.append(remainingTime / Double(remainingWords))
            }
        }

        guard alignedOnsets.count == subtitleWords.count else { return nil }
        return (alignedDurations, alignedOnsets)
    }

    /// Strip leading/trailing punctuation AND internal hyphens for character-count alignment.
    ///
    /// NLTokenizer splits hyphenated compounds ("mid-decay") into separate tokens ("mid", "decay"),
    /// but SubtitleChunker keeps them as one whitespace-split word. Without removing the hyphen,
    /// "mid-decay" = 9 chars vs "mid" (3) + "decay" (5) = 8 chars, causing the character
    /// consumption loop in alignOnsetsToWords() to overshoot. Removing internal hyphens gives
    /// "middecay" = 8 chars, matching the MToken sum exactly.
    private static func stripPunctuation(_ word: String) -> String {
        let punct = CharacterSet.punctuationCharacters.union(.symbols)
        var result = word
        while let first = result.unicodeScalars.first, punct.contains(first) {
            result = String(result.dropFirst())
        }
        while let last = result.unicodeScalars.last, punct.contains(last) {
            result = String(result.dropLast())
        }
        // Remove internal hyphens/dashes so "mid-decay" -> "middecay" matches
        // NLTokenizer's "mid" + "decay" = "middecay" in character counting
        result = result.replacingOccurrences(of: "-", with: "")
        result = result.replacingOccurrences(of: "\u{2013}", with: "")  // en-dash
        result = result.replacingOccurrences(of: "\u{2014}", with: "")  // em-dash
        return result
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

    /// Pre-warm CoreAudio hardware by playing a brief silent buffer.
    ///
    /// macOS powers down the audio output subsystem after idle periods. The first
    /// AVAudioPlayer.play() after idle triggers a synchronous hardware re-init that
    /// takes ~50-500ms, causing audible stutter/choppiness at the start of playback.
    ///
    /// Playing a tiny silent WAV (~0.1s at 24kHz) forces CoreAudio to initialize the
    /// output chain, so subsequent real audio plays without stutter.
    private func warmUpAudioHardware() {
        let sampleRate: Double = 24000.0
        let silentSamples = Int(sampleRate * 0.1)  // 0.1s of silence

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(silentSamples)
        ) else {
            logger.warning("Failed to create silent buffer for audio warm-up")
            return
        }

        buffer.frameLength = AVAudioFrameCount(silentSamples)
        // Buffer is already zero-filled (silence)

        let wavPath = NSTemporaryDirectory() + "tts-warmup-\(UUID().uuidString).wav"
        do {
            let url = URL(fileURLWithPath: wavPath)
            let audioFile = try AVAudioFile(
                forWriting: url,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
            try audioFile.write(from: buffer)

            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.0  // Completely silent
            player.prepareToPlay()
            player.play()

            // Retain the player to prevent ARC deallocation before playback completes
            self.warmUpPlayer = player

            // Clean up temp file and release player after a short delay
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [weak self] in
                try? FileManager.default.removeItem(atPath: wavPath)
                // Release warm-up player on main to avoid potential race
                DispatchQueue.main.async { self?.warmUpPlayer = nil }
            }

            audioHardwareWarmed = true
            logger.info("CoreAudio hardware pre-warmed with 0.1s silent buffer")
        } catch {
            logger.warning("Audio warm-up failed: \(error) -- first playback may stutter")
            try? FileManager.default.removeItem(atPath: wavPath)
        }
    }

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
final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
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
