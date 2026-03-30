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
    /// Native word onset times from Python server's Kokoro duration model.
    /// Populated for English synthesis; nil for CJK (sherpa-onnx path).
    let wordOnsets: [TimeInterval]?
}

/// Delegates TTS synthesis to the Python Kokoro server (localhost:8779).
///
/// - All MLX GPU work happens in the Python server process (separate launchd service)
/// - This actor sends HTTP requests via /v1/audio/speech-with-timestamps (JSON: WAV + word timing)
/// - Native word onsets from Kokoro duration model drive zero-drift karaoke highlighting
/// - CJK synthesis still uses sherpa-onnx directly (no change)
/// - Circuit breaker protects against Python server failures
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


    // MARK: - Lifecycle

    /// Whether TTS is disabled due to Python server being unreachable at startup.
    /// When true, synthesis may still be attempted (server could come up later),
    /// but a warning is logged.
    private(set) var pythonServerWarning: Bool = false

    // MARK: - TTS Circuit Breaker (P1)

    /// Circuit breaker tracking consecutive synthesis failures.
    /// Delegates to the existing CircuitBreaker class.
    private let circuitBreaker = CircuitBreaker(maxFailures: 3, cooldownSeconds: 30)

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
    /// Retries up to 6 times (30s total) to wait for the Kokoro server to load its model.
    /// This prevents the circuit breaker from tripping on startup race conditions.
    func checkPythonServerHealth() async {
        let maxRetries = 6
        let retryDelay: UInt64 = 5_000_000_000  // 5 seconds

        for attempt in 1...maxRetries {
            let healthURL = URL(string: "\(Config.pythonTTSServerURL)/health")!
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = Config.pythonTTSHealthCheckTimeout

            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String {
                    logger.info("Python TTS server healthy: status=\(status)")
                } else {
                    logger.info("Python TTS server reachable (health endpoint returned 200)")
                }
                pythonServerWarning = false
                return
            } catch {
                if attempt < maxRetries {
                    logger.info("Python TTS server not ready (attempt \(attempt)/\(maxRetries)), retrying in 5s...")
                    try? await Task.sleep(nanoseconds: retryDelay)
                } else {
                    logger.warning("Python TTS server unreachable after \(maxRetries) attempts at \(Config.pythonTTSServerURL)")
                    pythonServerWarning = true
                }
            }
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

        // Use timestamp endpoint -- discard word timing for this path (only need WAV + duration)
        let tsResult = try await callPythonServerWithTimestamps(text: processedText, voice: voiceName, speed: speed)

        // Write WAV bytes to temp file
        try tsResult.wavData.write(to: URL(fileURLWithPath: wavPath))

        logger.info("Synthesis complete: \(String(format: "%.2f", tsResult.audioDuration))s audio")

        return SynthesisResult(
            wavPath: wavPath,
            audioDuration: tsResult.audioDuration,
            durations: nil
        )
    }

    /// Synthesize text and extract per-word timing data for karaoke highlighting.
    ///
    /// Uses native word onsets from the Python server's /v1/audio/speech-with-timestamps
    /// endpoint. The Kokoro duration model provides zero-drift per-word timing data,
    /// replacing the character-weighted approximation that caused visible drift on
    /// multi-syllable words.
    func synthesizeWithTimestamps(
        text: String,
        voiceName: String = Config.defaultVoiceName,
        speed: Float = 1.2
    ) async throws -> TTSResult {
        let processedText = PronunciationProcessor.preprocessText(text)
        let wavPath = NSTemporaryDirectory() + "tts-\(UUID().uuidString).wav"

        let tsResult = try await callPythonServerWithTimestamps(text: processedText, voice: voiceName, speed: speed)

        // Write WAV bytes to temp file
        try tsResult.wavData.write(to: URL(fileURLWithPath: wavPath))

        logger.info("Synthesis with timestamps complete: \(String(format: "%.2f", tsResult.audioDuration))s audio, \(tsResult.wordOnsets.count) word onsets")

        // Native per-word durations from Kokoro duration model (not character-weighted)
        // Keep wordTimings populated as fallback for SubtitleSyncDriver onset count mismatches
        let wordTimings = tsResult.wordDurations

        return TTSResult(
            wavPath: wavPath,
            text: text,
            wordTimings: wordTimings,
            audioDuration: tsResult.audioDuration,
            wordOnsets: tsResult.wordOnsets
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
        /// Native word onset times from Python server's Kokoro duration model (nil for CJK path)
        let wordOnsets: [TimeInterval]?
        /// Raw float32 PCM samples at 24kHz for direct AVAudioEngine scheduling.
        /// Extracted from WAV response for callers that skip file I/O.
        let samples: [Float]?
        /// Word texts from Kokoro's MToken tokenization (nil for CJK path).
        /// Using these as display words guarantees 1:1 alignment with wordOnsets,
        /// avoiding the mismatch between Misaki/spaCy linguistic tokens and
        /// whitespace-split words from splitWordsMatchingKokoro().
        let wordTexts: [String]?
    }

    /// Synthesize text as a single paragraph via the Python server.
    ///
    /// Sends the full text in one call (preserves paragraph-level prosody context),
    /// then splits the returned audio into sentence-level chunks for subtitle display.
    /// The Python server's mlx-audio handles internal chunking at the 510-token limit.
    ///
    /// Audio is upsampled from 24kHz to 48kHz to match CoreAudio hardware rate,
    /// eliminating internal sample rate converter artifacts at buffer boundaries.
    ///
    /// Returns an empty array if circuit breaker is open or synthesis fails.
    func synthesizeStreaming(
        text: String,
        voiceName: String = Config.defaultVoiceName,
        speed: Float = 1.2,
        cancellationCheck: (() -> Bool)? = nil
    ) async -> [ChunkResult] {
        guard !isTTSCircuitBreakerOpen else {
            logger.warning("TTS circuit breaker open -- skipping synthesis (\(text.count) chars)")
            return []
        }

        // Check cancellation before starting
        if Task.isCancelled || (cancellationCheck?() == true) {
            logger.info("Synthesis cancelled before starting")
            return []
        }

        let processedText = PronunciationProcessor.preprocessText(text)
        logger.info("Synthesizing full paragraph: \(text.count) chars (single server call)")

        let pipelineStart = CFAbsoluteTimeGetCurrent()

        do {
            let tsResult = try await callPythonServerWithTimestamps(text: processedText, voice: voiceName, speed: speed)

            // Extract float32 samples from WAV (no trailing silence — gapless scheduling)
            let rawSamples = Self.extractSamplesFromWav(data: tsResult.wavData)

            // Upsample 24kHz → 48kHz (2x integer ratio) to match CoreAudio hardware rate.
            // Eliminates internal sample rate converter artifacts at buffer boundaries.
            let samples = Self.upsample2x(rawSamples)

            circuitBreaker.recordSuccess()

            let elapsed = CFAbsoluteTimeGetCurrent() - pipelineStart
            let rtf = elapsed / tsResult.audioDuration
            logger.info("Synthesis complete: \(String(format: "%.2f", tsResult.audioDuration))s audio in \(String(format: "%.2f", elapsed))s (RTF: \(String(format: "%.3f", rtf)))")

            // Check cancellation after synthesis
            if Task.isCancelled || (cancellationCheck?() == true) {
                logger.info("Synthesis cancelled after server call")
                return []
            }

            // Split into sentence-level chunks for subtitle display.
            // Use word onset times from Kokoro's duration model to find exact sentence boundaries.
            let sentences = SentenceSplitter.splitIntoSentences(text)
            let totalChunks = sentences.count
            var chunks: [ChunkResult] = []

            let wavPath = NSTemporaryDirectory() + "tts-full-\(UUID().uuidString).wav"
            try Self.writeWav(samples: samples, sampleRate: 48000.0, to: wavPath)

            // Telemetry: log all word timings from Kokoro for debugging
            let allWordOnsets = tsResult.wordOnsets
            let allWordDurations = tsResult.wordDurations
            let allWordTexts = tsResult.wordTexts
            logger.info("[TELEMETRY] Server returned \(allWordTexts.count) words, \(allWordOnsets.count) onsets, audioDuration=\(String(format: "%.3f", tsResult.audioDuration))s")
            logger.info("[TELEMETRY] Sentences: \(sentences.count) → \(sentences.map { "\"\($0.prefix(40))\"" }.joined(separator: ", "))")
            if allWordTexts.count <= 50 {
                logger.info("[TELEMETRY] Words: \(allWordTexts.joined(separator: " | "))")
                logger.info("[TELEMETRY] Onsets: \(allWordOnsets.map { String(format: "%.3f", $0) }.joined(separator: ", "))")
            }
            logger.info("[TELEMETRY] Raw samples: \(rawSamples.count) (24kHz), upsampled: \(samples.count) (48kHz)")

            // Return the full audio as a single chunk with absolute word onsets.
            // The pipeline coordinator handles subtitle display (paragraph vs sentence scope).
            let audioDuration = Double(samples.count) / 48000.0

            // Use preprocessed text (markdown-stripped) so word splitting matches Kokoro's tokenization.
            // The original text may contain em-dashes, symbols, etc. that Kokoro strips.
            chunks.append(ChunkResult(
                wavPath: wavPath,
                text: processedText,
                wordTimings: allWordDurations,
                audioDuration: audioDuration,
                chunkIndex: 0,
                totalChunks: 1,
                wordOnsets: allWordOnsets,
                samples: samples,
                wordTexts: allWordTexts
            ))

            let totalElapsed = CFAbsoluteTimeGetCurrent() - pipelineStart
            logger.info("Pipeline complete: \(totalChunks) subtitle chunks in \(String(format: "%.2f", totalElapsed))s")

            return chunks
        } catch {
            logger.error("Synthesis failed: \(error)")
            circuitBreaker.recordFailure()
            return []
        }
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

        // Upsample CJK audio to 48kHz to match AudioStreamPlayer format
        let upsampledSamples = Self.upsample2x(result.samples)

        do {
            try Self.writeWav(samples: upsampledSamples, sampleRate: 48000.0, to: wavPath)
        } catch {
            logger.error("CJK WAV write failed: \(error)")
            return nil
        }

        // CJK karaoke timing is out of scope -- use uniform word timing as fallback.
        let words = text.map { String($0) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let perWordDuration = words.isEmpty ? audioDuration : audioDuration / Double(words.count)
        let wordTimings = Array(repeating: perWordDuration, count: words.count)

        logger.info("CJK synthesis complete: \(String(format: "%.2f", audioDuration))s audio")

        return ChunkResult(
            wavPath: wavPath,
            text: text,
            wordTimings: wordTimings,
            audioDuration: audioDuration,
            chunkIndex: 0,
            totalChunks: 1,
            wordOnsets: nil,
            samples: upsampledSamples,
            wordTexts: nil
        )
    }

    /// Synthesize text, automatically routing CJK to sherpa-onnx and English to Python Kokoro server.
    /// Returns empty array if synthesis fails entirely.
    func synthesizeStreamingAutoRoute(text: String, speed: Float = 1.2, cancellationCheck: (() -> Bool)? = nil) async -> [ChunkResult] {
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
        return await synthesizeStreaming(text: text, voiceName: langResult.voiceName, speed: speed, cancellationCheck: cancellationCheck)
    }

    // MARK: - Python Server HTTP Client

    /// JSON response from Python server's /v1/audio/speech-with-timestamps endpoint.
    private struct PythonTimestampWord: Codable {
        let text: String
        let onset: Double
        let duration: Double
    }

    /// Full response from the timestamp endpoint: base64 WAV + per-word timing array.
    private struct PythonTimestampResponse: Codable {
        let audio_b64: String
        let words: [PythonTimestampWord]
        let audio_duration: Double
        let sample_rate: Int
    }

    /// Result of calling the Python server with timestamps.
    private struct TimestampResult {
        let wavData: Data
        let wordOnsets: [TimeInterval]
        let wordDurations: [TimeInterval]
        let wordTexts: [String]
        let audioDuration: TimeInterval
    }

    /// Call the Python Kokoro TTS server's timestamp endpoint for synthesis with native word timing.
    ///
    /// Uses /v1/audio/speech-with-timestamps which returns JSON containing base64-encoded WAV
    /// and per-word onset/duration data from the Kokoro duration model. This gives zero-drift
    /// karaoke timing vs the character-weighted approximation.
    private func callPythonServerWithTimestamps(text: String, voice: String, speed: Float) async throws -> TimestampResult {
        let url = URL(string: "\(Config.pythonTTSServerURL)/v1/audio/speech-with-timestamps")!
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

        // Parse JSON response with base64 audio + word timing array
        let tsResponse = try JSONDecoder().decode(PythonTimestampResponse.self, from: data)

        guard let wavData = Data(base64Encoded: tsResponse.audio_b64) else {
            throw TTSError.synthesisReturnedNil
        }

        let wordOnsets = tsResponse.words.map { TimeInterval($0.onset) }
        let wordDurations = tsResponse.words.map { TimeInterval($0.duration) }
        let wordTexts = tsResponse.words.map { $0.text }

        return TimestampResult(
            wavData: wavData,
            wordOnsets: wordOnsets,
            wordDurations: wordDurations,
            wordTexts: wordTexts,
            audioDuration: TimeInterval(tsResponse.audio_duration)
        )
    }

    /// Call the Python Kokoro TTS server to synthesize text.
    /// Returns raw WAV bytes on success.
    /// Kept as fallback -- main paths now use callPythonServerWithTimestamps().
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

    // MARK: - Audio Processing

    /// Upsample float32 audio by 2x (24kHz → 48kHz) using linear interpolation.
    /// 48kHz is CoreAudio's native hardware rate — avoids internal sample rate converter
    /// artifacts at buffer boundaries.
    private static func upsample2x(_ input: [Float]) -> [Float] {
        guard input.count > 1 else { return input }
        var output = [Float](repeating: 0, count: input.count * 2)
        for i in 0..<input.count - 1 {
            output[i * 2] = input[i]
            output[i * 2 + 1] = (input[i] + input[i + 1]) * 0.5
        }
        // Last sample
        output[(input.count - 1) * 2] = input[input.count - 1]
        output[(input.count - 1) * 2 + 1] = input[input.count - 1]
        return output
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
    private static func writeWav(samples: [Float], sampleRate: Double = 48000.0, to path: String) throws {
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
}
