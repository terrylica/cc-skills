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

/// Wraps sherpa-onnx Kokoro TTS for speech synthesis with word-level timestamps.
///
/// - Model loads lazily on first `synthesize()` call (TTS-03)
/// - All synthesis runs on a dedicated serial DispatchQueue (TTS-02)
/// - Audio written as 24kHz mono 16-bit WAV via SherpaOnnxWriteWave (TTS-08)
/// - Playback via afplay subprocess (TTS-01)
final class TTSEngine: @unchecked Sendable {

    private let logger = Logger(label: "tts-engine")

    /// Dedicated serial queue for all TTS work -- never blocks main thread (TTS-02)
    private let queue = DispatchQueue(label: "com.terryli.tts-engine", qos: .userInitiated)

    /// Lazily-initialized sherpa-onnx TTS instance (TTS-03)
    private var ttsInstance: OpaquePointer?

    /// Lock protecting lazy init of ttsInstance
    private let lock = NSLock()

    /// Currently running afplay process (for cancellation)
    private var playbackProcess: Process?

    /// Path to the last generated WAV (cleaned up before next synthesis)
    private var lastWavPath: String?

    // MARK: - Lifecycle

    init() {
        logger.info("TTSEngine created (model will load lazily on first synthesis)")
    }

    deinit {
        playbackProcess?.terminate()
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
        speakerId: Int32 = 0,
        speed: Float = 1.0,
        completion: @escaping (Result<SynthesisResult, Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                let tts = try ensureModelLoaded()

                // Clean up previous temp file
                cleanupLastWav()

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

                // Extract durations if available
                var durations: [Float]?
                let numDurations = result.pointee.num_durations
                if numDurations > 0, let durPtr = result.pointee.durations {
                    durations = Array(UnsafeBufferPointer(start: durPtr, count: Int(numDurations)))
                }

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

                if let durs = durations {
                    logger.debug("Duration tensor: \(durs.count) values")
                }

                completion(.success(SynthesisResult(
                    wavPath: wavPath,
                    audioDuration: audioDuration,
                    durations: durations
                )))
            } catch {
                logger.error("Synthesis failed: \(error)")
                completion(.failure(error))
            }
        }
    }

    /// Play a WAV file using afplay subprocess.
    ///
    /// Runs on the serial queue so it doesn't block the main thread.
    /// The completion handler is called when playback finishes.
    func play(wavPath: String, completion: (() -> Void)? = nil) {
        queue.async { [self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            process.arguments = [wavPath]

            playbackProcess = process

            process.terminationHandler = { [weak self] _ in
                self?.playbackProcess = nil
                completion?()
            }

            do {
                try process.run()
                logger.info("Playing WAV: \(wavPath)")
                process.waitUntilExit()
            } catch {
                logger.error("afplay failed: \(error)")
                playbackProcess = nil
                completion?()
            }
        }
    }

    /// Stop any currently playing audio.
    func stopPlayback() {
        playbackProcess?.terminate()
        playbackProcess = nil
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
        let provider = strdup("cpu")

        defer {
            free(modelPath)
            free(voicesPath)
            free(tokensPath)
            free(dataDir)
            free(provider)
        }

        var config = SherpaOnnxOfflineTtsConfig()
        config.model.kokoro.model = UnsafePointer(modelPath)
        config.model.kokoro.voices = UnsafePointer(voicesPath)
        config.model.kokoro.tokens = UnsafePointer(tokensPath)
        config.model.kokoro.data_dir = UnsafePointer(dataDir)
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
