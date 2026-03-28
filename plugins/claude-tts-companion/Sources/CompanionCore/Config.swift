import Foundation

/// Centralized configuration constants for claude-tts-companion.
/// Paths use environment variable overrides with sensible defaults.
public enum Config {
    /// Path to Kokoro MLX model file (bf16 safetensors).
    static let kokoroMLXModelPath: String = {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/terryli"
        return ProcessInfo.processInfo.environment["KOKORO_MLX_MODEL_PATH"]
            ?? "\(home)/.local/share/kokoro/models/mlx/kokoro-v1_0.safetensors"
    }()

    /// Path to Kokoro voice embeddings (NPZ format).
    static let kokoroVoicesPath: String = {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/terryli"
        return ProcessInfo.processInfo.environment["KOKORO_VOICES_PATH"]
            ?? "\(home)/.local/share/kokoro/models/mlx/voices.npz"
    }()

    /// Path to mlx.metallib (Metal shader library, required at runtime).
    /// Defaults to same directory as the running binary.
    static let kokoroMLXMetallibPath: String = {
        if let envPath = ProcessInfo.processInfo.environment["MLX_METALLIB_PATH"] {
            return envPath
        }
        // Default: next to binary
        if let execURL = Bundle.main.executableURL {
            return execURL.deletingLastPathComponent().appendingPathComponent("mlx.metallib").path
        }
        return "/usr/local/bin/mlx.metallib"
    }()

    /// Default voice name for English TTS (kokoro-ios voice embedding key).
    static let defaultVoiceName: String = "af_heart"

    /// Chinese voice name (kokoro-ios does not yet support Chinese; reserved for future use).
    static let chineseVoiceName: String = "zf_xiaobei"

    /// Default speaker ID (legacy sherpa-onnx, kept for API compatibility)
    static let defaultSpeakerId: Int32 = 3

    /// Chinese speaker ID (legacy sherpa-onnx, kept for API compatibility)
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

    // MARK: - sherpa-onnx Chinese TTS

    /// Path to sherpa-onnx kokoro-int8-multi-lang model directory.
    /// Contains model.int8.onnx, tokens.txt, voices.bin, dict/, espeak-ng-data/, lexicon files, FST files.
    static let sherpaOnnxModelDir: String = {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/terryli"
        return ProcessInfo.processInfo.environment["KOKORO_MODEL_PATH"]
            ?? "\(home)/.local/share/kokoro/models/kokoro-int8-multi-lang-v1_0"
    }()

    /// Idle timeout before unloading sherpa-onnx model to reclaim RSS (seconds).
    /// Per milestone decision: 30-second idle cooldown for load-on-demand.
    static let sherpaOnnxIdleTimeoutSeconds: TimeInterval = 30

    /// Number of CPU threads for sherpa-onnx inference.
    static let sherpaOnnxNumThreads: Int32 = 2
}
