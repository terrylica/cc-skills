import Foundation

/// Centralized configuration constants for claude-tts-companion.
/// Paths use environment variable overrides with sensible defaults.
enum Config {
    /// Path to sherpa-onnx installation directory
    static let sherpaOnnxPath: String = {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/<you>"
        return ProcessInfo.processInfo.environment["SHERPA_ONNX_PATH"]
            ?? "\(home)/fork-tools/sherpa-onnx/build-swift-macos/install"
    }()

    /// Path to Kokoro int8 TTS model directory (v1.0 multi-lang with af_heart voice)
    static let kokoroModelPath: String = {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/<you>"
        return ProcessInfo.processInfo.environment["KOKORO_MODEL_PATH"]
            ?? "\(home)/tmp/subtitle-spikes-7aqa/03-textream/models-int8/kokoro-int8-multi-lang-v1_0"
    }()

    /// Filename of the Kokoro model
    static let kokoroModelFile = "model.int8.onnx"

    /// Default speaker ID: af_heart (speaker 3 in Kokoro v1.0)
    static let defaultSpeakerId: Int32 = 3

    /// Application name for logging and service identification
    static let appName = "claude-tts-companion"

    /// Launchd service label
    static let serviceLabel = "com.example.claude-tts-companion"
}
