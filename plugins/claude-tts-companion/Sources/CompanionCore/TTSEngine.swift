// TTS engine: streaming synthesis, model lifecycle, circuit breaker, audio playback
import AVFoundation
import Foundation
import KokoroSwift
import Logging
import MLX
import MLXUtilsLibrary

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
/// - Playback via AVAudioPlayer with prepareToPlay() pre-buffering (TTS-01)
/// - Word timestamps extracted natively from MToken.start_ts/end_ts (no C++ patches)
/// - Text preprocessing fixes mispronounced words before phonemization (TTS-09)
public final class TTSEngine: @unchecked Sendable {

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

    /// Gapless streaming audio player using AVAudioEngine + AVAudioPlayerNode.
    /// Shared across streaming sessions -- reset() between sessions, never deallocated.
    let audioStreamPlayer = AudioStreamPlayer()

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
    // See .planning/debug/mlx-metal-resource-crash.md for full root cause analysis.
    // See .planning/debug/profile-mlx-metal-memory.md for profiling data.

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
    /// At 10 calls, worst case is ~17GB before restart — safely under 32GB system RAM.
    static let maxSynthesisBeforeRestart = 10

    /// Whether the synthesis count has reached the restart threshold.
    /// Callers should trigger graceful exit after current playback completes.
    var shouldRestartForMemory: Bool {
        lock.lock()
        defer { lock.unlock() }
        return synthesisCount >= Self.maxSynthesisBeforeRestart
    }

    /// Returns synthesis count and optional MLX memory snapshot for diagnostics.
    func memoryDiagnostics() -> (synthesisCount: Int, mlxActive: Int?, mlxCache: Int?, mlxPeak: Int?) {
        lock.lock()
        let count = synthesisCount
        lock.unlock()
        if let tts = ttsInstance {
            let snap = tts.memorySnapshot()
            return (count, snap.active, snap.cache, snap.peak)
        }
        return (count, nil, nil, nil)
    }

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

        // NOTE: MLX Memory.clearCache() / Memory.cacheLimit calls are FORBIDDEN from
        // the main binary -- they create a separate C++ Metal device singleton that
        // competes for the GPU's 499000 resource limit. Cache management is handled
        // inside libKokoroSwift.dylib (kokoro-ios v1.0.13+): generateAudio() clears
        // the cache after each call, and KokoroTTS init sets a 32 MB cache limit.

        // Pre-warm CoreAudio hardware so the first real play() doesn't stutter.
        // macOS powers down audio hardware after idle; re-init takes ~50-500ms
        // which causes choppy audio at the start of the first chunk.
        warmUpAudioHardware()

        // Start AVAudioEngine early so hardware stays warm for streaming playback.
        // The engine persists across sessions -- reset() between sessions, never stopped.
        audioStreamPlayer.start()
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
                let processedText = PronunciationProcessor.preprocessText(text)
                logger.info("Synthesizing \(text.count) chars, voice=\(voiceName), speed=\(speed)")
                let startTime = CFAbsoluteTimeGetCurrent()

                // Generate audio via kokoro-ios MLX
                let (audio, _) = try tts.generateAudio(
                    voice: activeVoice, language: .enUS, text: processedText, speed: speed
                )
                lock.lock()
                synthesisCount += 1
                lock.unlock()

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
                let processedText = PronunciationProcessor.preprocessText(text)
                logger.info("Synthesizing with timestamps: \(text.count) chars, voice=\(voiceName), speed=\(speed)")
                let startTime = CFAbsoluteTimeGetCurrent()

                let (audio, tokenArray) = try tts.generateAudio(
                    voice: activeVoice, language: .enUS, text: processedText, speed: speed
                )
                lock.lock()
                synthesisCount += 1
                lock.unlock()

                let audioDuration = Double(audio.count) / 24000.0
                try writeWav(samples: audio, to: wavPath)

                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                let rtf = elapsed / audioDuration
                logger.info("Synthesis complete: \(String(format: "%.2f", audioDuration))s audio in \(String(format: "%.2f", elapsed))s (RTF: \(String(format: "%.3f", rtf)))")

                // Align MToken timestamps to subtitle words (with character-weighted fallback)
                let resolved = WordTimingAligner.resolveWordTimings(
                    tokenArray: tokenArray,
                    text: text,
                    audioDuration: audioDuration,
                    logger: logger
                )

                let ttsResult = TTSResult(
                    wavPath: wavPath,
                    text: text,
                    wordTimings: resolved.durations,
                    audioDuration: audioDuration,
                    wordOnsets: resolved.onsets
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
        /// Raw float32 PCM samples at 24kHz for direct AVAudioEngine scheduling.
        /// When present, SubtitleSyncDriver can skip WAV file I/O entirely.
        let samples: [Float]?
    }

    /// Synthesize text as sentence chunks using batch-then-play pattern.
    ///
    /// Splits `text` into sentences, synthesizes ALL sentences sequentially on the
    /// background queue, then delivers them via callbacks. This completely separates
    /// GPU synthesis from audio playback — zero GPU work during playback.
    ///
    /// **Batch-then-play pattern:** MLX Metal GPU synthesis creates ~1.7GB IOAccelerator
    /// allocations per call that are never reclaimed within a session. When synthesis and
    /// playback run simultaneously on Apple Silicon unified memory, the accumulated memory
    /// pressure causes audio stutters. By synthesizing everything first, the GPU is
    /// completely idle during playback.
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
                // NOTE: Stream.gpu.synchronize() + Memory.clearCache() removed — these
                // calls initialize a separate MLX Metal device in the main binary,
                // causing immediate 499000 resource limit exhaustion.
                // KokoroSwift manages its own Metal resources internally.

                let tts = try ensureModelLoaded()
                let activeVoice = voiceForName(voiceName)

                let sentences = SentenceSplitter.splitIntoSentences(text)
                let totalChunks = sentences.count
                logger.info("Streaming TTS: \(text.count) chars split into \(totalChunks) sentences")

                let pipelineStart = CFAbsoluteTimeGetCurrent()

                for (index, sentence) in sentences.enumerated() {
                    // Wrap each chunk in autoreleasepool to drain ObjC objects (Metal
                    // command buffers, MLXArray intermediates, etc.) between synthesis
                    // calls. Without this, all 5 chunks' Metal objects accumulate in
                    // the DispatchQueue's single autorelease pool, causing GPU memory
                    // pressure that stutters the last chunk(s).
                    // NOTE: This is safe — autoreleasepool is a pure ObjC/Swift runtime
                    // mechanism, NOT an MLX API call (which would create a duplicate
                    // Metal device singleton — see mlx-metal-resource-crash.md).
                    let chunkResult: ChunkResult? = autoreleasepool {
                        let wavPath = NSTemporaryDirectory() + "tts-stream-\(UUID().uuidString).wav"

                        // Apply pronunciation overrides before phonemization (TTS-09)
                        let processedSentence = PronunciationProcessor.preprocessText(sentence)
                        logger.info("Synthesizing chunk \(index + 1)/\(totalChunks): \(sentence.count) chars")
                        let startTime = CFAbsoluteTimeGetCurrent()

                        let audio: [Float]
                        let tokenArray: [MToken]?
                        do {
                            (audio, tokenArray) = try tts.generateAudio(
                                voice: activeVoice, language: .enUS, text: processedSentence, speed: speed
                            )
                            lock.lock()
                            synthesisCount += 1
                            lock.unlock()
                            recordSynthesisSuccess()
                        } catch {
                            logger.error("Synthesis failed for chunk \(index + 1): \(error)")
                            recordSynthesisFailure()
                            return nil
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
                            return nil
                        }

                        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                        let rtf = elapsed / audioDuration
                        logger.info("Chunk \(index + 1)/\(totalChunks) complete: \(String(format: "%.2f", audioDuration))s audio in \(String(format: "%.2f", elapsed))s (RTF: \(String(format: "%.3f", rtf)))")

                        // Align MToken timestamps to subtitle words (with character-weighted fallback)
                        let resolved = WordTimingAligner.resolveWordTimings(
                            tokenArray: tokenArray,
                            text: sentence,
                            audioDuration: audioDuration,
                            logger: logger
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

                    // Handle synthesis failure or circuit breaker
                    guard let chunk = chunkResult else {
                        if isTTSCircuitBreakerOpen {
                            logger.error("TTS circuit breaker tripped mid-stream — aborting remaining chunks")
                            break
                        }
                        continue
                    }

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

    /// Number of silence samples appended to each streaming chunk WAV.
    /// At 24kHz, 2400 samples = 100ms of trailing silence.
    /// This prevents choppy audio at sentence boundaries by giving the waveform
    /// room to decay naturally and masking the ~16ms poll-based chunk transition gap.
    private static let trailingSilenceSamples = 2400  // 100ms at 24kHz

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

        // NOTE: Cache limit (32 MB) and clearCache() are set inside KokoroTTS
        // (kokoro-ios v1.0.13+). No MLX API calls from the main binary.

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
