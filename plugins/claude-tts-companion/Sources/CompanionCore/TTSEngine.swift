// FILE-SIZE-OK -- actor with HTTP client, streaming, CJK routing, WAV utilities (cohesive unit)
// TTS engine: delegates MLX synthesis to Python Kokoro server (localhost:8779)
// Actor-isolated -- all mutable state protected by Swift actor model (no NSLock).
// The Python server handles MLX model lifecycle, memory management, and GPU work.
// This actor handles: HTTP client, WAV file management, word timing, circuit breaker.
import AVFoundation
import Foundation
import Logging

/// Result of a TTS synthesis operation.
public struct SynthesisResult: Sendable {
    /// Path to the generated WAV file
    let wavPath: String
    /// Duration of the generated audio in seconds
    let audioDuration: TimeInterval
    /// Raw duration tensor values per token (always nil for Python server delegation)
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
    /// Native word onset times (always nil when using Python server -- no MToken data available).
    let wordOnsets: [TimeInterval]?
}

/// Delegates TTS synthesis to the Python Kokoro server (localhost:8779).
///
/// - All MLX GPU work happens in the Python server process (separate launchd service)
/// - This actor sends HTTP requests and receives WAV bytes
/// - Word timestamps use character-weighted fallback (Python server doesn't return MToken data)
/// - CJK synthesis still uses sherpa-onnx directly (no change)
/// - Circuit breaker protects against Python server failures
/// - Synthesis counter tracks calls for diagnostics (no restart needed -- Python server manages its own memory)
public actor TTSEngine {

    private let logger = Logger(label: "tts-engine")

    /// URLSession configured for Python TTS server requests.
    private let urlSession: URLSession

    /// PlaybackManager reference for delegating play/stop/prepare operations.
    /// Received at init (D-04).
    let playbackManager: PlaybackManager

    /// sherpa-onnx engine for CJK text synthesis (CJK-01).
    /// Injected at init; handles on-demand model loading with idle unload.
    let sherpaOnnxEngine: SherpaOnnxEngine

    /// Path to the last generated WAV (cleaned up before next synthesis)
    private var lastWavPath: String?

    // MARK: - Lifecycle

    /// Whether TTS is disabled due to Python server being unreachable at startup.
    /// When true, synthesis may still be attempted (server could come up later),
    /// but a warning is logged.
    private(set) var pythonServerWarning: Bool = false

    // MARK: - Synthesis Counter (Diagnostics)

    /// Total number of synthesis calls since process start.
    /// Used for diagnostics; no restart threshold needed since the Python server
    /// manages its own MLX memory lifecycle independently.
    private(set) var synthesisCount: Int = 0

    /// Maximum synthesis calls before triggering graceful exit for memory reclaim.
    /// With Python server delegation, IOAccelerator leaks happen in the Python process,
    /// not this process. Threshold raised significantly -- this binary stays lean.
    /// Static let on actor is nonisolated (accessible without await).
    static let maxSynthesisBeforeRestart = 500

    /// Whether the synthesis count has reached the restart threshold.
    /// With Python server delegation, this threshold is essentially unreachable
    /// since the companion binary no longer accumulates GPU memory.
    var shouldRestartForMemory: Bool {
        return synthesisCount >= Self.maxSynthesisBeforeRestart
    }

    /// Returns synthesis count for diagnostics (no MLX memory snapshot -- handled by Python server).
    func memoryDiagnostics() -> (synthesisCount: Int, mlxActive: Int?, mlxCache: Int?, mlxPeak: Int?) {
        return (synthesisCount, nil, nil, nil)
    }

    // MARK: - TTS Circuit Breaker (P1)

    /// Circuit breaker tracking consecutive synthesis failures.
    /// Delegates to the existing CircuitBreaker class.
    private let circuitBreaker = CircuitBreaker(maxFailures: 3, cooldownSeconds: 300)

    /// Check whether TTS is temporarily disabled by the circuit breaker.
    /// If the cooldown has elapsed, automatically re-enable.
    var isTTSCircuitBreakerOpen: Bool {
        circuitBreaker.isOpen
    }

    init(playbackManager: PlaybackManager, sherpaOnnxEngine: SherpaOnnxEngine) {
        self.playbackManager = playbackManager
        self.sherpaOnnxEngine = sherpaOnnxEngine

        // Configure URLSession with appropriate timeouts for synthesis requests
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Config.pythonTTSRequestTimeout
        config.timeoutIntervalForResource = Config.pythonTTSRequestTimeout
        self.urlSession = URLSession(configuration: config)

        logger.info("TTSEngine created (Python server delegation at \(Config.pythonTTSServerURL) + sherpa-onnx CJK)")
    }

    /// Check if the Python TTS server is reachable. Called during startup.
    /// Non-blocking -- logs warning if unreachable but does not disable TTS
    /// (server may come up later).
    func checkPythonServerHealth() async {
        let healthURL = URL(string: "\(Config.pythonTTSServerURL)/health")!
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = Config.pythonTTSHealthCheckTimeout

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                logger.warning("Python TTS server health check failed -- server may not be ready")
                pythonServerWarning = true
                return
            }
            // Parse health response for logging
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String {
                logger.info("Python TTS server healthy: status=\(status)")
            } else {
                logger.info("Python TTS server reachable (health endpoint returned 200)")
            }
            pythonServerWarning = false
        } catch {
            logger.warning("Python TTS server unreachable at \(Config.pythonTTSServerURL): \(error.localizedDescription)")
            pythonServerWarning = true
        }
    }

    // MARK: - Public API

    /// Synthesize text to a WAV file by delegating to the Python Kokoro server.
    func synthesize(
        text: String,
        voiceName: String = Config.defaultVoiceName,
        speed: Float = 1.2
    ) async throws -> SynthesisResult {
        let processedText = PronunciationProcessor.preprocessText(text)
        let wavPath = NSTemporaryDirectory() + "tts-\(UUID().uuidString).wav"
        lastWavPath = wavPath

        let wavData = try await callPythonServer(text: processedText, voice: voiceName, speed: speed)

        // Write WAV bytes to temp file
        try wavData.write(to: URL(fileURLWithPath: wavPath))

        // Parse audio duration from WAV data (24kHz mono float32 = 4 bytes per sample)
        let audioDuration = Self.wavDuration(data: wavData)

        synthesisCount += 1
        logger.info("Synthesis complete: \(String(format: "%.2f", audioDuration))s audio, count=\(synthesisCount)")

        return SynthesisResult(
            wavPath: wavPath,
            audioDuration: audioDuration,
            durations: nil
        )
    }

    /// Synthesize text and extract per-word timing data for karaoke highlighting.
    ///
    /// Uses character-weighted fallback for word timings since the Python server
    /// does not return MToken timestamp data.
    func synthesizeWithTimestamps(
        text: String,
        voiceName: String = Config.defaultVoiceName,
        speed: Float = 1.2
    ) async throws -> TTSResult {
        let processedText = PronunciationProcessor.preprocessText(text)
        let wavPath = NSTemporaryDirectory() + "tts-\(UUID().uuidString).wav"
        lastWavPath = wavPath

        let wavData = try await callPythonServer(text: processedText, voice: voiceName, speed: speed)

        // Write WAV bytes to temp file
        try wavData.write(to: URL(fileURLWithPath: wavPath))

        let audioDuration = Self.wavDuration(data: wavData)

        synthesisCount += 1
        logger.info("Synthesis with timestamps complete: \(String(format: "%.2f", audioDuration))s audio, count=\(synthesisCount)")

        // Character-weighted fallback (no MToken data from Python server)
        let wordTimings = WordTimingAligner.extractWordTimings(text: text, audioDuration: audioDuration)

        return TTSResult(
            wavPath: wavPath,
            text: text,
            wordTimings: wordTimings,
            audioDuration: audioDuration,
            wordOnsets: nil
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
        /// Native word onset times (always nil for Python server delegation)
        let wordOnsets: [TimeInterval]?
        /// Raw float32 PCM samples at 24kHz for direct AVAudioEngine scheduling.
        /// Extracted from WAV response for callers that skip file I/O.
        let samples: [Float]?
    }

    /// Number of silence samples appended to each streaming chunk WAV.
    /// At 24kHz, 2400 samples = 100ms of trailing silence.
    private static let trailingSilenceSamples = 2400  // 100ms at 24kHz

    /// Synthesize text as sentence chunks using batch-then-play pattern.
    ///
    /// Splits `text` into sentences, synthesizes ALL sentences sequentially via
    /// the Python server, then returns all chunks. This completely separates
    /// synthesis from audio playback.
    ///
    /// Returns an empty array if circuit breaker is open or all chunks fail.
    func synthesizeStreaming(
        text: String,
        voiceName: String = Config.defaultVoiceName,
        speed: Float = 1.2
    ) async -> [ChunkResult] {
        guard !isTTSCircuitBreakerOpen else {
            logger.warning("TTS circuit breaker open -- skipping streaming synthesis (\(text.count) chars)")
            return []
        }

        let sentences = SentenceSplitter.splitIntoSentences(text)
        let totalChunks = sentences.count
        logger.info("Streaming TTS: \(text.count) chars split into \(totalChunks) sentences")

        var chunks: [ChunkResult] = []
        let pipelineStart = CFAbsoluteTimeGetCurrent()

        for (index, sentence) in sentences.enumerated() {
            let processedSentence = PronunciationProcessor.preprocessText(sentence)
            let wavPath = NSTemporaryDirectory() + "tts-stream-\(UUID().uuidString).wav"

            logger.info("Synthesizing chunk \(index + 1)/\(totalChunks): \(sentence.count) chars")
            let startTime = CFAbsoluteTimeGetCurrent()

            do {
                let wavData = try await callPythonServer(text: processedSentence, voice: voiceName, speed: speed)

                let audioDuration = Self.wavDuration(data: wavData)

                // Extract float32 samples from WAV and add trailing silence
                var samples = Self.extractSamplesFromWav(data: wavData)
                samples.append(contentsOf: [Float](repeating: 0.0, count: Self.trailingSilenceSamples))

                // Write padded WAV (with silence) to disk
                try Self.writeWav(samples: samples, to: wavPath)

                circuitBreaker.recordSuccess()

                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                let rtf = elapsed / audioDuration
                logger.info("Chunk \(index + 1)/\(totalChunks) complete: \(String(format: "%.2f", audioDuration))s audio in \(String(format: "%.2f", elapsed))s (RTF: \(String(format: "%.3f", rtf)))")

                // Character-weighted timing (no MToken data from Python server)
                let wordTimings = WordTimingAligner.extractWordTimings(text: sentence, audioDuration: audioDuration)

                chunks.append(ChunkResult(
                    wavPath: wavPath,
                    text: sentence,
                    wordTimings: wordTimings,
                    audioDuration: audioDuration,
                    chunkIndex: index,
                    totalChunks: totalChunks,
                    wordOnsets: nil,
                    samples: samples
                ))
            } catch {
                logger.error("Synthesis failed for chunk \(index + 1): \(error)")
                circuitBreaker.recordFailure()

                if circuitBreaker.isOpen {
                    logger.error("TTS circuit breaker tripped mid-stream -- aborting remaining chunks")
                    break
                }
                continue
            }
        }

        let totalElapsed = CFAbsoluteTimeGetCurrent() - pipelineStart
        logger.info("Streaming TTS pipeline complete: \(totalChunks) chunks in \(String(format: "%.2f", totalElapsed))s")

        // Update synthesis count
        synthesisCount += chunks.count
        logger.info("Streaming synthesis done: \(chunks.count) chunks, total synthesisCount=\(synthesisCount)")

        return chunks
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

    /// Synthesize text, automatically routing CJK to sherpa-onnx and English to Python Kokoro server.
    /// Returns empty array if synthesis fails entirely.
    func synthesizeStreamingAutoRoute(text: String, speed: Float = 1.2) async -> [ChunkResult] {
        let langResult = LanguageDetector.detect(text: text)

        if langResult.lang == "cmn" {
            logger.info("CJK text detected (\(text.count) chars) -- routing to sherpa-onnx")
            if let chunk = await synthesizeCJK(text: text, speed: 1.0) {
                return [chunk]
            }
            logger.warning("CJK synthesis failed -- returning empty for subtitle-only fallback")
            return []
        }

        // English path: delegate to Python Kokoro server
        return await synthesizeStreaming(text: text, voiceName: langResult.voiceName, speed: speed)
    }

    // MARK: - Python Server HTTP Client

    /// Call the Python Kokoro TTS server to synthesize text.
    /// Returns raw WAV bytes on success.
    private func callPythonServer(text: String, voice: String, speed: Float) async throws -> Data {
        let url = URL(string: "\(Config.pythonTTSServerURL)/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "input": text,
            "voice": voice,
            "language": "en-us",
            "speed": speed,
            "response_format": "wav"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw TTSError.pythonServerUnavailable(url: Config.pythonTTSServerURL)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.pythonServerUnavailable(url: Config.pythonTTSServerURL)
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TTSError.pythonServerError(statusCode: httpResponse.statusCode, message: message)
        }

        guard !data.isEmpty else {
            throw TTSError.synthesisReturnedNil
        }

        return data
    }

    // MARK: - WAV Utilities

    /// Parse audio duration from WAV data by reading the header.
    /// Assumes standard WAV format (RIFF header).
    private static func wavDuration(data: Data) -> TimeInterval {
        // WAV header: bytes 24-27 = sample rate (uint32 LE), bytes 40-43 = data chunk size (uint32 LE)
        // For standard PCM WAV: duration = dataSize / (sampleRate * channels * bitsPerSample/8)
        guard data.count > 44 else { return 0 }

        let sampleRate: UInt32 = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 24, as: UInt32.self)
        }
        let bitsPerSample: UInt16 = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 34, as: UInt16.self)
        }
        let numChannels: UInt16 = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 22, as: UInt16.self)
        }

        // Find data chunk size (may not be at offset 40 if there are extra chunks)
        // Simple approach: total size minus 44-byte header
        let dataSize = data.count - 44

        guard sampleRate > 0, bitsPerSample > 0, numChannels > 0 else { return 0 }
        let bytesPerSample = Int(bitsPerSample) / 8
        let totalSamples = dataSize / (bytesPerSample * Int(numChannels))
        return Double(totalSamples) / Double(sampleRate)
    }

    /// Extract PCM samples from WAV data as float32 array.
    /// The Python server (soundfile) writes int16 PCM WAV by default.
    /// Reads bitsPerSample from the WAV header to handle both int16 and float32.
    private static func extractSamplesFromWav(data: Data) -> [Float] {
        guard data.count > 44 else { return [] }

        let bitsPerSample: UInt16 = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 34, as: UInt16.self)
        }

        let pcmData = data.subdata(in: 44..<data.count)

        if bitsPerSample == 16 {
            // Int16 PCM -> Float32 conversion (normalize to -1.0...1.0)
            let sampleCount = pcmData.count / MemoryLayout<Int16>.size
            return pcmData.withUnsafeBytes { ptr in
                let int16Ptr = ptr.bindMemory(to: Int16.self)
                return (0..<sampleCount).map { Float(int16Ptr[$0]) / 32768.0 }
            }
        } else if bitsPerSample == 32 {
            // Float32 PCM (direct copy)
            let sampleCount = pcmData.count / MemoryLayout<Float>.size
            return pcmData.withUnsafeBytes { ptr in
                let floatPtr = ptr.bindMemory(to: Float.self)
                return Array(floatPtr.prefix(sampleCount))
            }
        } else {
            // Unsupported format -- return empty
            return []
        }
    }

    /// Write float32 audio samples to a WAV file using AVAudioFile.
    /// Static to be callable from non-isolated context.
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
