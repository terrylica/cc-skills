import Foundation
import Logging

/// Subtitle display settings, persisted to disk (API-03, API-07).
public struct SubtitleSettings: Codable, Sendable {
    var fontSize: String
    var position: String
    var opacity: Double
    var karaokeEnabled: Bool
    var screen: String
    var displayMode: String
    /// "paragraph" (default) shows full text on subtitle; "sentence" shows one sentence at a time
    var subtitleScope: String
    /// Bionic reading suffix opacity (0.0–1.0). Prefix is full opacity, suffix is dimmed.
    var bionicSuffixOpacity: Double

    static let `default` = SubtitleSettings(
        fontSize: "medium",
        position: "bottom",
        opacity: 0.3,
        karaokeEnabled: true,
        screen: "builtin",
        displayMode: "karaoke",
        subtitleScope: "paragraph",
        bionicSuffixOpacity: 0.7
    )

    /// Custom decoder with backward-compatible defaults for new fields.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontSize = try container.decode(String.self, forKey: .fontSize)
        position = try container.decode(String.self, forKey: .position)
        opacity = try container.decode(Double.self, forKey: .opacity)
        karaokeEnabled = try container.decode(Bool.self, forKey: .karaokeEnabled)
        screen = try container.decode(String.self, forKey: .screen)
        displayMode = try container.decodeIfPresent(String.self, forKey: .displayMode) ?? "karaoke"
        subtitleScope = try container.decodeIfPresent(String.self, forKey: .subtitleScope) ?? "paragraph"
        bionicSuffixOpacity = try container.decodeIfPresent(Double.self, forKey: .bionicSuffixOpacity) ?? 0.7
    }

    init(fontSize: String, position: String, opacity: Double, karaokeEnabled: Bool, screen: String, displayMode: String, subtitleScope: String = "paragraph", bionicSuffixOpacity: Double = 0.7) {
        self.fontSize = fontSize
        self.position = position
        self.opacity = opacity
        self.karaokeEnabled = karaokeEnabled
        self.screen = screen
        self.displayMode = displayMode
        self.subtitleScope = subtitleScope
        self.bionicSuffixOpacity = bionicSuffixOpacity
    }
}

/// TTS engine settings, persisted to disk (API-04, API-07).
public struct TTSSettings: Codable, Sendable {
    var enabled: Bool
    var voice: String
    var speed: Double
    /// Maximum characters per synthesis chunk (Paragraph Budget).
    /// Paragraphs exceeding this are recursively bisected at sentence boundaries.
    /// 0 = unlimited (no budget enforcement).
    var paragraphBudget: Int

    static let `default` = TTSSettings(
        enabled: true,
        voice: "af_heart",
        speed: 1.0,
        paragraphBudget: 500
    )

    init(enabled: Bool, voice: String, speed: Double, paragraphBudget: Int = 500) {
        self.enabled = enabled
        self.voice = voice
        self.speed = speed
        self.paragraphBudget = paragraphBudget
    }

    /// Backward-compatible decoder for settings files without paragraphBudget.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        voice = try container.decode(String.self, forKey: .voice)
        speed = try container.decode(Double.self, forKey: .speed)
        paragraphBudget = try container.decodeIfPresent(Int.self, forKey: .paragraphBudget) ?? 500
    }
}

/// Top-level settings container holding all subsystem configurations.
public struct AppSettings: Codable, Sendable {
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
public final class SettingsStore: @unchecked Sendable {

    private let logger = Logger(label: "settings-store")

    /// Lock protecting all access to `settings`.
    private let lock = NSLock()

    /// In-memory copy of current settings.
    private var settings: AppSettings

    /// Path to the JSON settings file on disk.
    let settingsFilePath: String

    init() {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/<you>"
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
