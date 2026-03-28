import CSherpaOnnx
import Foundation
import Logging

/// On-demand sherpa-onnx TTS engine for CJK text synthesis.
///
/// Loads the kokoro-int8-multi-lang model lazily on first synthesis request (CJK-03).
/// Unloads after 30 seconds of idle to minimize RSS impact.
/// Thread-safe via NSLock (synthesis is blocking C code on a DispatchQueue, not async).
///
/// Returns nil from synthesize() if model files are missing (CJK-04 graceful fallback).
public final class SherpaOnnxEngine: @unchecked Sendable {
    private let logger = Logger(label: "sherpa-onnx-engine")
    private let lock = NSLock()

    /// Opaque pointer to the loaded sherpa-onnx TTS instance.
    private var ttsPtr: OpaquePointer?  // const SherpaOnnxOfflineTts*

    /// Sample rate of the loaded model (typically 24000).
    private(set) var sampleRate: Int32 = 24000

    /// Timer that fires after idle timeout to unload the model.
    private var idleTimer: DispatchWorkItem?

    /// Whether model files exist on disk (checked once at init).
    let modelAvailable: Bool

    init() {
        let fm = FileManager.default
        let modelPath = Config.sherpaOnnxModelDir + "/model.int8.onnx"
        let tokensPath = Config.sherpaOnnxModelDir + "/tokens.txt"
        let voicesPath = Config.sherpaOnnxModelDir + "/voices.bin"
        modelAvailable = fm.fileExists(atPath: modelPath)
            && fm.fileExists(atPath: tokensPath)
            && fm.fileExists(atPath: voicesPath)
        if !modelAvailable {
            logger.warning("sherpa-onnx model not found at \(Config.sherpaOnnxModelDir) -- CJK TTS disabled")
        } else {
            logger.info("sherpa-onnx model validated at \(Config.sherpaOnnxModelDir) (will load on first CJK request)")
        }
    }

    deinit {
        unloadModel()
    }

    /// Synthesize CJK text to float32 PCM samples.
    ///
    /// Returns nil if model is unavailable or synthesis fails (CJK-04).
    /// Caller is responsible for writing samples to WAV if needed.
    ///
    /// - Parameters:
    ///   - text: Chinese text to synthesize
    ///   - speakerId: Speaker ID (default: Config.chineseSpeakerId = 45)
    ///   - speed: Speech speed (default: 1.0)
    /// - Returns: (samples: [Float], sampleRate: Int32) or nil on failure
    func synthesize(text: String, speakerId: Int32 = Config.chineseSpeakerId, speed: Float = 1.0) -> (samples: [Float], sampleRate: Int32)? {
        guard modelAvailable else {
            logger.warning("CJK synthesis skipped -- model not available")
            return nil
        }

        lock.lock()
        defer { lock.unlock() }

        // Load model on demand (CJK-03)
        if ttsPtr == nil {
            guard loadModel() else { return nil }
        }

        // Reset idle timer
        resetIdleTimer()

        guard let tts = ttsPtr else { return nil }

        // Call sherpa-onnx C API
        guard let audio = SherpaOnnxOfflineTtsGenerate(tts, text, speakerId, speed) else {
            logger.error("SherpaOnnxOfflineTtsGenerate returned nil for: \(text.prefix(50))")
            return nil
        }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }

        let count = Int(audio.pointee.n)
        guard count > 0 else {
            logger.error("sherpa-onnx generated 0 samples for: \(text.prefix(50))")
            return nil
        }

        // Copy samples out before destroying the audio struct
        let samples = Array(UnsafeBufferPointer(start: audio.pointee.samples, count: count))
        let rate = audio.pointee.sample_rate

        logger.info("sherpa-onnx synthesis: \(count) samples at \(rate)Hz (\(String(format: "%.2f", Double(count) / Double(rate)))s)")

        return (samples: samples, sampleRate: rate)
    }

    /// Explicitly unload the model to reclaim memory.
    func unloadModel() {
        lock.lock()
        defer { lock.unlock() }
        idleTimer?.cancel()
        idleTimer = nil
        if let tts = ttsPtr {
            SherpaOnnxDestroyOfflineTts(tts)
            ttsPtr = nil
            logger.info("sherpa-onnx model unloaded")
        }
    }

    /// Whether the model is currently loaded in memory.
    var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ttsPtr != nil
    }

    // MARK: - Private

    /// Load the sherpa-onnx model. Must be called with lock held.
    private func loadModel() -> Bool {
        let modelDir = Config.sherpaOnnxModelDir
        let startTime = CFAbsoluteTimeGetCurrent()

        // Build config using the kokoro model type
        var config = SherpaOnnxOfflineTtsConfig()

        // Zero-initialize all fields (C structs may have garbage)
        memset(&config, 0, MemoryLayout<SherpaOnnxOfflineTtsConfig>.size)

        let modelPath = modelDir + "/model.int8.onnx"
        let tokensPath = modelDir + "/tokens.txt"
        let voicesPath = modelDir + "/voices.bin"
        let dataDirPath = modelDir + "/espeak-ng-data"
        let dictDirPath = modelDir + "/dict"
        let lexiconPaths = [
            modelDir + "/lexicon-us-en.txt",
            modelDir + "/lexicon-zh.txt",
        ].joined(separator: ",")
        let ruleFsts = [
            modelDir + "/date-zh.fst",
            modelDir + "/number-zh.fst",
            modelDir + "/phone-zh.fst",
        ].joined(separator: ",")

        // Use withCString chains to keep strings alive during C call
        let tts: OpaquePointer? = modelPath.withCString { modelCStr in
            tokensPath.withCString { tokensCStr in
                voicesPath.withCString { voicesCStr in
                    dataDirPath.withCString { dataDirCStr in
                        dictDirPath.withCString { dictDirCStr in
                            lexiconPaths.withCString { lexiconCStr in
                                ruleFsts.withCString { ruleFstsCStr in
                                    config.model.kokoro.model = modelCStr
                                    config.model.kokoro.tokens = tokensCStr
                                    config.model.kokoro.voices = voicesCStr
                                    config.model.kokoro.data_dir = dataDirCStr
                                    config.model.kokoro.dict_dir = dictDirCStr
                                    config.model.kokoro.lexicon = lexiconCStr
                                    config.model.kokoro.length_scale = 1.0
                                    config.model.num_threads = Config.sherpaOnnxNumThreads
                                    config.model.debug = 0
                                    config.rule_fsts = ruleFstsCStr
                                    config.max_num_sentences = 1
                                    return SherpaOnnxCreateOfflineTts(&config)
                                }
                            }
                        }
                    }
                }
            }
        }

        guard let tts = tts else {
            logger.error("SherpaOnnxCreateOfflineTts returned nil -- model load failed")
            return false
        }

        ttsPtr = tts
        sampleRate = SherpaOnnxOfflineTtsSampleRate(tts)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("sherpa-onnx model loaded in \(String(format: "%.2f", elapsed))s (sample rate: \(sampleRate)Hz)")
        return true
    }

    /// Reset the idle unload timer. Must be called with lock held.
    private func resetIdleTimer() {
        idleTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.unloadModel()
        }
        idleTimer = work
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + Config.sherpaOnnxIdleTimeoutSeconds,
            execute: work
        )
    }
}
