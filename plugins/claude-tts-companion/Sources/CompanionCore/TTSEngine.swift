// FILE-SIZE-OK -- actor facade with synthesis methods, model lifecycle, circuit breaker (core TTS logic)
// TTS engine: streaming synthesis, model lifecycle, circuit breaker
// Actor-isolated -- all mutable state protected by Swift actor model (no NSLock).
import AVFoundation
import Foundation
import KokoroSwift
import Logging
@preconcurrency import MLX
@preconcurrency import MLXUtilsLibrary

/// Result of a TTS synthesis operation.
public struct SynthesisResult: Sendable {
    /// Path to the generated WAV file
    let wavPath: String
    /// Duration of the generated audio in seconds
    let audioDuration: TimeInterval
    /// Raw duration tensor values per token (nil for kokoro-ios -- use MToken timestamps instead)
    let durations: [Float]?
}

/// Result of synthesis with word-level timing data for karaoke display.
public struct TTSResult: Sendable {
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
/// - Word timestamps extracted natively from MToken.start_ts/end_ts (no C++ patches)
/// - Text preprocessing fixes mispronounced words before phonemization (TTS-09)
/// - Actor isolation replaces NSLock for thread safety (CONC-01/02/03/04)
public actor TTSEngine {

    private let logger = Logger(label: "tts-engine")

    /// Dedicated serial queue for all TTS work -- never blocks main thread (TTS-02)
    private let synthesisQueue = DispatchQueue(label: "com.terryli.tts-engine", qos: .userInitiated)

    /// Lazily-initialized kokoro-ios TTS instance (TTS-03)
    private var ttsInstance: KokoroTTS?

    /// All voice embeddings loaded from voices.npz
    private var voicesDict: [String: MLXArray]?

    /// Currently active voice embedding
    private var voice: MLXArray?

    /// PlaybackManager reference for delegating play/stop/prepare operations.
    /// Received at init (D-04).
    let playbackManager: PlaybackManager

    /// sherpa-onnx engine for CJK text synthesis (CJK-01).
    /// Injected at init; handles on-demand model loading with idle unload.
    let sherpaOnnxEngine: SherpaOnnxEngine

    /// Path to the last generated WAV (cleaned up before next synthesis)
    private var lastWavPath: String?

    // MARK: - MLX Cache Management

    // NOTE: MLX Metal buffer cache management is handled INSIDE libKokoroSwift.dylib
    // (kokoro-ios v1.0.13+). Each generateAudio() call now clears its own cache, and
    // the cache limit is set to 32 MB on KokoroTTS init.
    //
    // Calling Memory.clearCache() or Memory.cacheLimit from the main binary is FORBIDDEN
    // -- it initializes a separate C++ Metal device singleton that competes for the GPU's
    // 499000 resource limit, causing immediate crashes.

    // MARK: - Lifecycle

    /// Whether TTS is disabled due to missing model files at startup.
    /// When true, all synthesis calls return immediately with an error instead
    /// of crashing on first use.
    private(set) var isDisabledDueToMissingModel: Bool = false

    // MARK: - Memory Lifecycle (MLX IOAccelerator Leak Mitigation)

    /// Total number of generateAudio() calls since process start.
    /// Used by the memory lifecycle system to trigger planned restart
    /// before IOAccelerator allocations exhaust system RAM.
    private(set) var synthesisCount: Int = 0

    /// Maximum generateAudio() calls before triggering graceful exit for memory reclaim.
    /// IOAccelerator grows ~1.7GB per call and is only reclaimable via process exit.
    /// At 10 calls, worst case is ~17GB before restart -- safely under 32GB system RAM.
    /// Static let on actor is nonisolated (accessible without await).
    static let maxSynthesisBeforeRestart = 10

    /// Whether the synthesis count has reached the restart threshold.
    /// Callers should trigger graceful exit after current playback completes.
    var shouldRestartForMemory: Bool {
        return synthesisCount >= Self.maxSynthesisBeforeRestart
    }

    /// Returns synthesis count and optional MLX memory snapshot for diagnostics.
    func memoryDiagnostics() -> (synthesisCount: Int, mlxActive: Int?, mlxCache: Int?, mlxPeak: Int?) {
        let count = synthesisCount
        if let tts = ttsInstance {
            let snap = tts.memorySnapshot()
            return (count, snap.active, snap.cache, snap.peak)
        }
        return (count, nil, nil, nil)
    }

    // MARK: - TTS Circuit Breaker (P1)

    /// Circuit breaker tracking consecutive synthesis failures.
    /// Delegates to the existing CircuitBreaker class (replaces inline NSLock-based implementation).
    private let circuitBreaker = CircuitBreaker(maxFailures: 3, cooldownSeconds: 300)

    /// Check whether TTS is temporarily disabled by the circuit breaker.
    /// If the cooldown has elapsed, automatically re-enable.
    var isTTSCircuitBreakerOpen: Bool {
        circuitBreaker.isOpen
    }

    init(playbackManager: PlaybackManager, sherpaOnnxEngine: SherpaOnnxEngine) {
        self.playbackManager = playbackManager
        self.sherpaOnnxEngine = sherpaOnnxEngine
        logger.info("TTSEngine created (kokoro-ios MLX + sherpa-onnx CJK, models load lazily)")

        // Validate model files exist at boot to fail fast with a clear error
        // instead of crashing on first synthesis (P0: startup model validation).
        let fm = FileManager.default
        if !fm.fileExists(atPath: Config.kokoroMLXModelPath) {
            logger.critical("Kokoro MLX model not found at \(Config.kokoroMLXModelPath) -- TTS disabled")
            isDisabledDueToMissingModel = true
        } else if !fm.fileExists(atPath: Config.kokoroVoicesPath) {
            logger.critical("Kokoro voices not found at \(Config.kokoroVoicesPath) -- TTS disabled")
            isDisabledDueToMissingModel = true
        } else {
            logger.info("Model files validated: \(Config.kokoroMLXModelPath), \(Config.kokoroVoicesPath)")
        }

        // NOTE: MLX Memory.clearCache() / Memory.cacheLimit calls are FORBIDDEN from
        // the main binary -- they create a separate C++ Metal device singleton that
        // competes for the GPU's 499000 resource limit. Cache management is handled
        // inside libKokoroSwift.dylib (kokoro-ios v1.0.13+).
    }

    // NOTE: No deinit needed -- ARC handles ttsInstance/voicesDict/voice cleanup.
    // WAV cleanup happens in cleanupLastWav() during normal synthesis flow.
    // Actor deinit is nonisolated and cannot access actor-isolated non-Sendable properties.

    // MARK: - Public API

    /// Synthesize text to a WAV file on the background queue.
    ///
    /// Uses withCheckedThrowingContinuation to bridge the blocking DispatchQueue
    /// work to Swift async/await (CONC-03).
    func synthesize(
        text: String,
        voiceName: String = Config.defaultVoiceName,
        speed: Float = 1.2
    ) async throws -> SynthesisResult {
        guard !isDisabledDueToMissingModel else {
            throw TTSError.modelLoadFailed(path: "TTS disabled -- model files missing at startup")
        }

        // Prepare state before entering DispatchQueue (actor-isolated)
        let tts = try ensureModelLoaded()
        let activeVoice = voiceForName(voiceName)
        let processedText = PronunciationProcessor.preprocessText(text)
        let wavPath = NSTemporaryDirectory() + "tts-\(UUID().uuidString).wav"
        lastWavPath = wavPath

        // Bridge blocking GPU work to async via DispatchQueue + continuation (CONC-03)
        let result: SynthesisResult = try await withCheckedThrowingContinuation { continuation in
            synthesisQueue.async {
                do {
                    let startTime = CFAbsoluteTimeGetCurrent()

                    let (audio, _) = try tts.generateAudio(
                        voice: activeVoice, language: .enUS, text: processedText, speed: speed
                    )

                    let audioDuration = Double(audio.count) / 24000.0

                    // Write WAV file using AVAudioFile
                    try Self.writeWav(samples: audio, to: wavPath)

                    continuation.resume(returning: SynthesisResult(
                        wavPath: wavPath,
                        audioDuration: audioDuration,
                        durations: nil
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        // Back in actor isolation: update state
        synthesisCount += 1
        logger.info("Synthesis complete: \(String(format: "%.2f", result.audioDuration))s audio, count=\(synthesisCount)")

        return result
    }

    /// Synthesize text and extract per-word timing data for karaoke highlighting.
    ///
    /// Combines `synthesize()` with native MToken timestamps into a single call that
    /// returns everything needed to drive SubtitlePanel.showUtterance().
    func synthesizeWithTimestamps(
        text: String,
        voiceName: String = Config.defaultVoiceName,
        speed: Float = 1.2
    ) async throws -> TTSResult {
        guard !isDisabledDueToMissingModel else {
            throw TTSError.modelLoadFailed(path: "TTS disabled -- model files missing at startup")
        }

        // Prepare state before entering DispatchQueue (actor-isolated)
        let tts = try ensureModelLoaded()
        let activeVoice = voiceForName(voiceName)
        let processedText = PronunciationProcessor.preprocessText(text)
        let wavPath = NSTemporaryDirectory() + "tts-\(UUID().uuidString).wav"
        lastWavPath = wavPath

        // Bridge blocking GPU work to async via DispatchQueue + continuation (CONC-03)
        let (_, tokenArray, audioDuration): ([Float], [MToken]?, TimeInterval) = try await withCheckedThrowingContinuation { continuation in
            synthesisQueue.async {
                do {
                    let startTime = CFAbsoluteTimeGetCurrent()

                    let (audio, tokenArray) = try tts.generateAudio(
                        voice: activeVoice, language: .enUS, text: processedText, speed: speed
                    )

                    let audioDuration = Double(audio.count) / 24000.0
                    try Self.writeWav(samples: audio, to: wavPath)

                    continuation.resume(returning: (audio, tokenArray, audioDuration))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        // Back in actor isolation: update state and compute timings
        synthesisCount += 1
        logger.info("Synthesis with timestamps complete: \(String(format: "%.2f", audioDuration))s audio, count=\(synthesisCount)")

        // Align MToken timestamps to subtitle words (with character-weighted fallback)
        let resolved = WordTimingAligner.resolveWordTimings(
            tokenArray: tokenArray,
            text: text,
            audioDuration: audioDuration,
            logger: logger
        )

        return TTSResult(
            wavPath: wavPath,
            text: text,
            wordTimings: resolved.durations,
            audioDuration: audioDuration,
            wordOnsets: resolved.onsets
        )
    }

    // MARK: - Streaming Sentence-Chunked Synthesis

    /// Result for a single sentence chunk in the streaming pipeline.
    struct ChunkResult: Sendable {
        let wavPath: String
        let text: String
        let wordTimings: [TimeInterval]
        let audioDuration: TimeInterval
        let chunkIndex: Int
        let totalChunks: Int
        /// Native word onset times from MToken.start_ts (nil when using character-weighted fallback)
        let wordOnsets: [TimeInterval]?
        /// Raw float32 PCM samples at 24kHz for direct AVAudioEngine scheduling.
        /// When present, SubtitleSyncDriver can skip WAV file I/O entirely.
        let samples: [Float]?
    }

    /// Number of silence samples appended to each streaming chunk WAV.
    /// At 24kHz, 2400 samples = 100ms of trailing silence.
    private static let trailingSilenceSamples = 2400  // 100ms at 24kHz

    /// Synthesize text as sentence chunks using batch-then-play pattern.
    ///
    /// Splits `text` into sentences, synthesizes ALL sentences sequentially on the
    /// background queue, then returns all chunks. This completely separates
    /// GPU synthesis from audio playback -- zero GPU work during playback.
    ///
    /// Returns an empty array if TTS is disabled, circuit breaker is open, or all chunks fail.
    func synthesizeStreaming(
        text: String,
        voiceName: String = Config.defaultVoiceName,
        speed: Float = 1.2
    ) async -> [ChunkResult] {
        guard !isDisabledDueToMissingModel else {
            logger.error("TTS disabled -- model files missing at startup, skipping streaming synthesis")
            return []
        }
        guard !isTTSCircuitBreakerOpen else {
            logger.warning("TTS circuit breaker open -- skipping streaming synthesis (\(text.count) chars)")
            return []
        }

        // Prepare state before entering DispatchQueue (actor-isolated)
        let tts: KokoroTTS
        do {
            tts = try ensureModelLoaded()
        } catch {
            logger.error("Streaming synthesis failed: \(error)")
            return []
        }
        let activeVoice = voiceForName(voiceName)
        let sentences = SentenceSplitter.splitIntoSentences(text)
        let totalChunks = sentences.count
        logger.info("Streaming TTS: \(text.count) chars split into \(totalChunks) sentences")

        // Capture actor-isolated values before entering DispatchQueue
        let cbRef = circuitBreaker
        let loggerCopy = logger

        // Bridge ALL synthesis work to the DispatchQueue via continuation
        let synthesizedChunks: [ChunkResult] = await withCheckedContinuation { continuation in
            synthesisQueue.async {
                var chunks: [ChunkResult] = []
                let pipelineStart = CFAbsoluteTimeGetCurrent()

                for (index, sentence) in sentences.enumerated() {
                    let chunkResult: ChunkResult? = autoreleasepool {
                        let wavPath = NSTemporaryDirectory() + "tts-stream-\(UUID().uuidString).wav"
                        let processedSentence = PronunciationProcessor.preprocessText(sentence)
                        loggerCopy.info("Synthesizing chunk \(index + 1)/\(totalChunks): \(sentence.count) chars")
                        let startTime = CFAbsoluteTimeGetCurrent()

                        let audio: [Float]
                        let tokenArray: [MToken]?
                        do {
                            (audio, tokenArray) = try tts.generateAudio(
                                voice: activeVoice, language: .enUS, text: processedSentence, speed: speed
                            )
                            cbRef.recordSuccess()
                        } catch {
                            loggerCopy.error("Synthesis failed for chunk \(index + 1): \(error)")
                            cbRef.recordFailure()
                            return nil
                        }

                        let audioDuration = Double(audio.count) / 24000.0

                        let paddedAudio = audio + [Float](repeating: 0.0, count: Self.trailingSilenceSamples)

                        do {
                            try Self.writeWav(samples: paddedAudio, to: wavPath)
                        } catch {
                            loggerCopy.error("WAV write failed for chunk \(index + 1): \(error)")
                            return nil
                        }

                        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                        let rtf = elapsed / audioDuration
                        loggerCopy.info("Chunk \(index + 1)/\(totalChunks) complete: \(String(format: "%.2f", audioDuration))s audio in \(String(format: "%.2f", elapsed))s (RTF: \(String(format: "%.3f", rtf)))")

                        let resolved = WordTimingAligner.resolveWordTimings(
                            tokenArray: tokenArray,
                            text: sentence,
                            audioDuration: audioDuration,
                            logger: loggerCopy
                        )

                        return ChunkResult(
                            wavPath: wavPath,
                            text: sentence,
                            wordTimings: resolved.durations,
                            audioDuration: audioDuration,
                            chunkIndex: index,
                            totalChunks: totalChunks,
                            wordOnsets: resolved.onsets,
                            samples: paddedAudio
                        )
                    }

                    guard let chunk = chunkResult else {
                        if cbRef.isOpen {
                            loggerCopy.error("TTS circuit breaker tripped mid-stream -- aborting remaining chunks")
                            break
                        }
                        continue
                    }

                    chunks.append(chunk)
                }

                let totalElapsed = CFAbsoluteTimeGetCurrent() - pipelineStart
                loggerCopy.info("Streaming TTS pipeline complete: \(totalChunks) chunks in \(String(format: "%.2f", totalElapsed))s")
                continuation.resume(returning: chunks)
            }
        }

        // Back in actor isolation: update synthesis count
        synthesisCount += synthesizedChunks.count
        logger.info("Streaming synthesis done: \(synthesizedChunks.count) chunks, total synthesisCount=\(synthesisCount)")

        return synthesizedChunks
    }

    // MARK: - CJK Synthesis (sherpa-onnx)

    /// Synthesize CJK text via sherpa-onnx engine.
    /// Returns a single ChunkResult with the full text (no sentence splitting for CJK).
    /// Returns nil if synthesis fails (CJK-04 graceful fallback).
    func synthesizeCJK(text: String, speed: Float = 1.0) async -> ChunkResult? {
        guard let result = sherpaOnnxEngine.synthesize(text: text, speed: speed) else {
            logger.warning("CJK synthesis failed -- falling back to subtitle-only")
            return nil
        }

        let wavPath = NSTemporaryDirectory() + "tts-cjk-\(UUID().uuidString).wav"
        let audioDuration = Double(result.samples.count) / Double(result.sampleRate)

        // Add trailing silence (same as English streaming path)
        let paddedSamples = result.samples + [Float](repeating: 0.0, count: Self.trailingSilenceSamples)

        do {
            try Self.writeWav(samples: paddedSamples, sampleRate: Double(result.sampleRate), to: wavPath)
        } catch {
            logger.error("CJK WAV write failed: \(error)")
            return nil
        }

        // CJK karaoke timing is out of scope -- use uniform word timing as fallback.
        // Split text into characters for subtitle display (each char = one "word").
        let words = text.map { String($0) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let perWordDuration = words.isEmpty ? audioDuration : audioDuration / Double(words.count)
        let wordTimings = Array(repeating: perWordDuration, count: words.count)

        synthesisCount += 1
        logger.info("CJK synthesis complete: \(String(format: "%.2f", audioDuration))s audio, count=\(synthesisCount)")

        return ChunkResult(
            wavPath: wavPath,
            text: text,
            wordTimings: wordTimings,
            audioDuration: audioDuration,
            chunkIndex: 0,
            totalChunks: 1,
            wordOnsets: nil,
            samples: paddedSamples
        )
    }

    /// Synthesize text, automatically routing CJK to sherpa-onnx and English to kokoro-ios MLX.
    /// Returns empty array if synthesis fails entirely.
    func synthesizeStreamingAutoRoute(text: String, speed: Float = 1.2) async -> [ChunkResult] {
        let langResult = LanguageDetector.detect(text: text)

        if langResult.lang == "cmn" {
            logger.info("CJK text detected (\(text.count) chars) -- routing to sherpa-onnx")
            if let chunk = await synthesizeCJK(text: text, speed: 1.0) {
                return [chunk]
            }
            // Fallback: subtitle-only (CJK-04)
            logger.warning("CJK synthesis failed -- returning empty for subtitle-only fallback")
            return []
        }

        // English path: use existing kokoro-ios MLX streaming (CJK-02)
        return await synthesizeStreaming(text: text, voiceName: langResult.voiceName, speed: speed)
    }

    // MARK: - Private

    /// Ensure the TTS model is loaded, performing lazy initialization if needed (TTS-03).
    /// Actor-isolated -- no lock needed.
    private func ensureModelLoaded() throws -> KokoroTTS {
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
        if name != Config.defaultVoiceName {
            logger.warning("Voice '\(name)' not found, using default '\(Config.defaultVoiceName)'")
        }
        return voice!
    }

    /// Write float32 audio samples to a WAV file using AVAudioFile.
    /// Static to be callable from non-isolated DispatchQueue context.
    private static func writeWav(samples: [Float], sampleRate: Double = 24000.0, to path: String) throws {
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
