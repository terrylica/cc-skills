import Foundation

/// Per-outlet feature gates read from environment variables.
/// Matches legacy TypeScript env var names from notification-watcher.ts exactly.
///
/// Default behavior: all gates enabled unless explicitly set to "false".
/// This matches the legacy `!== "false"` semantics.
enum FeatureGates {
    /// Whether Telegram summarizer messages are enabled.
    /// Env: `SUMMARIZER_TG_ENABLED` (default: true)
    static var summarizerTgEnabled: Bool {
        env("SUMMARIZER_TG_ENABLED") != "false"
    }

    /// Whether TTS synthesis is enabled globally.
    /// Env: `TTS_ENABLED` (default: true)
    static var ttsEnabled: Bool {
        env("TTS_ENABLED") != "false"
    }

    /// Whether TTS is enabled for arc summary output.
    /// Requires global TTS to also be enabled (matching legacy `ttsEnabled && ...`).
    /// Env: `SUMMARY_TTS_ENABLED` (default: true)
    static var summaryTtsEnabled: Bool {
        ttsEnabled && env("SUMMARY_TTS_ENABLED") != "false"
    }

    /// Whether Telegram TBR (Tail Brief) messages are enabled.
    /// Env: `TBR_TG_ENABLED` (default: true)
    static var tbrTgEnabled: Bool {
        env("TBR_TG_ENABLED") != "false"
    }

    /// Whether TTS is enabled for TBR output.
    /// Requires global TTS to also be enabled (matching legacy `ttsEnabled && ...`).
    /// Env: `TBR_TTS_ENABLED` (default: true)
    static var tbrTtsEnabled: Bool {
        ttsEnabled && env("TBR_TTS_ENABLED") != "false"
    }

    /// True when all five outlet gates are disabled.
    /// Matches legacy early-exit check to skip processing entirely.
    static var allOutletsDisabled: Bool {
        !summarizerTgEnabled && !ttsEnabled && !summaryTtsEnabled
            && !tbrTgEnabled && !tbrTtsEnabled
    }

    // MARK: - Private

    /// Read an environment variable by key.
    private static func env(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }
}
