import Foundation
import Logging

/// Subtitle display settings, persisted to disk (API-03, API-07).
struct SubtitleSettings: Codable, Sendable {
    var fontSize: String
    var position: String
    var opacity: Double
    var karaokeEnabled: Bool
    var screen: String

    static let `default` = SubtitleSettings(
        fontSize: "medium",
        position: "bottom",
        opacity: 0.3,
        karaokeEnabled: true,
        screen: "builtin"
    )
}

/// TTS engine settings, persisted to disk (API-04, API-07).
struct TTSSettings: Codable, Sendable {
    var enabled: Bool
    var voice: String
    var speed: Double

    static let `default` = TTSSettings(
        enabled: true,
        voice: "af_heart",
        speed: 1.0
    )
}

/// Top-level settings container holding all subsystem configurations.
struct AppSettings: Codable, Sendable {
    var subtitle: SubtitleSettings
    var tts: TTSSettings

    static let `default` = AppSettings(
        subtitle: .default,
        tts: .default
    )
}

/// Thread-safe settings manager with JSON file persistence (API-07).
///
/// Settings are stored at `~/.config/claude-tts-companion/settings.json`.
/// All reads and writes are protected by NSLock, consistent with the
/// thread-safety patterns used elsewhere in this codebase (TTSEngine, CircuitBreaker).
final class SettingsStore: @unchecked Sendable {

    private let logger = Logger(label: "settings-store")

    /// Lock protecting all access to `settings`.
    private let lock = NSLock()

    /// In-memory copy of current settings.
    private var settings: AppSettings

    /// Path to the JSON settings file on disk.
    let settingsFilePath: String

    init() {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/terryli"
        let configDir = "\(home)/.config/\(Config.appName)"
        self.settingsFilePath = "\(configDir)/settings.json"

        // Ensure config directory exists
        try? FileManager.default.createDirectory(
            atPath: configDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Load from disk or use defaults
        if let loaded = SettingsStore.load(from: settingsFilePath) {
            self.settings = loaded
        } else {
            self.settings = .default
        }
    }

    /// Return a snapshot of current settings.
    func getSettings() -> AppSettings {
        lock.lock()
        defer { lock.unlock() }
        return settings
    }

    /// Mutate subtitle settings in-place, then persist to disk.
    func updateSubtitle(_ update: (inout SubtitleSettings) -> Void) {
        lock.lock()
        update(&settings.subtitle)
        let current = settings
        lock.unlock()
        save(current)
    }

    /// Mutate TTS settings in-place, then persist to disk.
    func updateTTS(_ update: (inout TTSSettings) -> Void) {
        lock.lock()
        update(&settings.tts)
        let current = settings
        lock.unlock()
        save(current)
    }

    // MARK: - Private

    /// Encode settings to JSON and write atomically to disk.
    private func save(_ settings: AppSettings) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: URL(fileURLWithPath: settingsFilePath), options: .atomic)
        } catch {
            logger.error("Failed to save settings: \(error)")
        }
    }

    /// Read and decode settings from a JSON file. Returns nil on any failure.
    private static func load(from path: String) -> AppSettings? {
        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }
}
