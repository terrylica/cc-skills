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

    /// Path to Kokoro int8 TTS model directory (v1.0 multi-lang with af_heart voice)
    static let kokoroModelPath: String = {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/terryli"
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
    static let serviceLabel = "com.terryli.claude-tts-companion"

    // MARK: - MiniMax AI Summary

    /// MiniMax API key for AI session summaries (nil if not configured)
    static let miniMaxAPIKey: String? = ProcessInfo.processInfo.environment["MINIMAX_API_KEY"]

    /// MiniMax API base URL (Anthropic-compatible endpoint)
    static let miniMaxBaseURL: String = {
        ProcessInfo.processInfo.environment["SUMMARY_BASE_URL"] ?? "https://api.minimax.chat"
    }()

    /// MiniMax model identifier
    static let miniMaxModel: String = {
        ProcessInfo.processInfo.environment["SUMMARY_MODEL"]
            ?? ProcessInfo.processInfo.environment["MINIMAX_MODEL"]
            ?? "MiniMax-M1-80k"
    }()

    /// Maximum tokens for summary API responses
    static let summaryMaxTokens: Int = {
        if let str = ProcessInfo.processInfo.environment["SUMMARY_MAX_TOKENS"],
           let val = Int(str) {
            return val
        }
        return 2048
    }()

    // MARK: - Telegram Bot

    /// Telegram bot token (nil if not configured -- bot will not start)
    static let telegramBotToken: String? = ProcessInfo.processInfo.environment["TELEGRAM_BOT_TOKEN"]

    /// Telegram chat ID for sending notifications (nil if not configured)
    static let telegramChatId: Int64? = {
        guard let str = ProcessInfo.processInfo.environment["TELEGRAM_CHAT_ID"],
              let val = Int64(str) else { return nil }
        return val
    }()
}
