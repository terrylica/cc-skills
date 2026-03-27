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

    /// Path to Kokoro TTS model directory (v1.0 multi-lang, full precision for quality)
    static let kokoroModelPath: String = {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/terryli"
        return ProcessInfo.processInfo.environment["KOKORO_MODEL_PATH"]
            ?? "\(home)/.local/share/kokoro/models/kokoro-multi-lang-v1_0"
    }()

    /// Filename of the Kokoro model.
    /// Auto-detects: uses model.onnx (full precision) if available, falls back to model.int8.onnx (quantized).
    static let kokoroModelFile: String = {
        let modelDir = kokoroModelPath
        let fullPrecision = "\(modelDir)/model.onnx"
        if FileManager.default.fileExists(atPath: fullPrecision) {
            return "model.onnx"
        }
        return "model.int8.onnx"
    }()

    /// Default speaker ID: af_heart (speaker 3 in Kokoro v1.0)
    static let defaultSpeakerId: Int32 = 3

    /// Chinese speaker ID: zf_xiaobei (speaker 45 in Kokoro multi-lang v1.0)
    static let chineseSpeakerId: Int32 = 45

    /// CJK character ratio threshold (percentage) for language detection.
    /// Text with CJK ratio >= this value is treated as Chinese.
    /// Matches legacy TTS_CJK_DETECTION_RATIO default of 20.
    static let cjkDetectionThreshold: Double = 20.0

    /// Application name for logging and service identification
    static let appName = "claude-tts-companion"

    /// Launchd service label
    static let serviceLabel = "com.terryli.claude-tts-companion"

    // MARK: - TTS Pipeline

    /// Whether to use streaming sentence-chunked TTS synthesis (default: true).
    /// When true, text is split into sentences and synthesized incrementally --
    /// first audio plays in ~5s instead of ~100s for long paragraphs.
    /// Set STREAMING_TTS=false to use full-paragraph synthesis (for future low-RTF models).
    static let streamingTTS: Bool = {
        return ProcessInfo.processInfo.environment["STREAMING_TTS"] != "false"
    }()

    // MARK: - HTTP Control API

    /// Port for the HTTP control API (localhost only)
    static let httpPort: UInt16 = 8780

    // MARK: - MiniMax API

    /// MiniMax API key from environment
    static let miniMaxApiKey: String? = ProcessInfo.processInfo.environment["MINIMAX_API_KEY"]
    static let miniMaxAPIKey: String? = miniMaxApiKey

    /// Max tokens for summary generation (thinking model needs headroom: ~2k thinking + ~4k text)
    static let summaryMaxTokens = 8192

    /// MiniMax API base URL (Anthropic-compatible endpoint)
    static let miniMaxBaseURL = "https://api.minimax.io/anthropic"

    /// MiniMax model identifier (SSoT: ~/.config/mise/config.toml MINIMAX_MODEL)
    static let miniMaxModel = "MiniMax-M2.7-highspeed"

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

    /// Model ID strings for /prompt flag parsing
    static let haikuModel = "haiku"
    static let sonnetModel = "sonnet"
    static let opusModel = "opus"

    /// Default working directory for /prompt commands
    static let promptDefaultCwd: String = {
        return ProcessInfo.processInfo.environment["HOME"] ?? "/Users/terryli"
    }()

    /// Maximum execution time for a single /prompt command (seconds)
    static let promptTimeoutSeconds: Int = 120

    // MARK: - File Watching

    /// Directory where Claude Code writes notification .json files
    static let notificationDir: String = {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/terryli"
        return ProcessInfo.processInfo.environment["CLAUDE_NOTIFICATION_DIR"]
            ?? "\(home)/.claude/notifications"
    }()

    /// Base directory for Claude Code project sessions (contains {hash}/sessions/{id}/transcript.jsonl)
    static let transcriptBaseDir: String = {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/terryli"
        return ProcessInfo.processInfo.environment["CLAUDE_PROJECTS_DIR"]
            ?? "\(home)/.claude/projects"
    }()

    /// Target latency for file watcher event detection (seconds)
    static let fileWatcherLatencyTarget: TimeInterval = 0.1

    // MARK: - Notification Processing

    /// Dedup TTL: skip re-notifications for the same session within this window (seconds).
    /// Matches legacy NOTIFICATION_DEDUP_TTL_MS of 900000ms (15 minutes).
    static let notificationDedupTTL: TimeInterval = 900

    /// Minimum interval between notification processing (seconds).
    /// Matches legacy NOTIFICATION_MIN_INTERVAL_MS of 5000ms.
    static let notificationMinInterval: TimeInterval = 5.0
}
