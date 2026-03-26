import Foundation

/// Centralized configuration constants for claude-tts-companion.
/// Paths use environment variable overrides with sensible defaults.
enum Config {
    /// Path to sherpa-onnx installation directory
    static let sherpaOnnxPath: String = {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/terryli"
        return ProcessInfo.processInfo.environment["SHERPA_ONNX_PATH"]
            ?? "\(home)/fork-tools/sherpa-onnx/build-swift-macos/install"
    }()

    /// Path to Kokoro int8 TTS model directory
    /// Note: canonical path is ~/.local/share/kokoro/models/kokoro-int8-en-v0_19/
    /// but current location differs. Model copy is a Phase 10 concern.
    static let kokoroModelPath: String = {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/terryli"
        return ProcessInfo.processInfo.environment["KOKORO_MODEL_PATH"]
            ?? "\(home)/tmp/subtitle-spikes-7aqa/03-textream/models-int8/kokoro-int8-en-v0_19"
    }()

    /// Application name for logging and service identification
    static let appName = "claude-tts-companion"

    /// Launchd service label
    static let serviceLabel = "com.terryli.claude-tts-companion"
}
