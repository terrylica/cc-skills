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

    // MARK: - MiniMax API

    /// MiniMax API key from environment
    static let miniMaxApiKey: String? = ProcessInfo.processInfo.environment["MINIMAX_API_KEY"]
    static let miniMaxAPIKey: String? = miniMaxApiKey

    /// Max tokens for summary generation
    static let summaryMaxTokens = 4096

    /// MiniMax API base URL
    static let miniMaxBaseURL = "https://api.minimax.chat"

    /// MiniMax model identifier
    static let miniMaxModel = "MiniMax-Text-01"

    // MARK: - Telegram Bot

    /// Telegram bot token from environment
    static let telegramBotToken: String? = ProcessInfo.processInfo.environment["TELEGRAM_BOT_TOKEN"]

    /// Telegram chat ID for notifications
    static let telegramChatId: String? = ProcessInfo.processInfo.environment["TELEGRAM_CHAT_ID"]

    // MARK: - Claude CLI

    /// Path to the `claude` CLI binary
    static let claudeCLIPath: String = {
        return ProcessInfo.processInfo.environment["CLAUDE_CLI_PATH"]
            ?? "/usr/local/bin/claude"
    }()

    /// Default model for /prompt commands when no flag is specified
    static let defaultModel = "sonnet"
}
