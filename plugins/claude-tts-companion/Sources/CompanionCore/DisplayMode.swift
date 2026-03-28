/// Display mode for subtitle rendering (BION-02).
///
/// Controls how subtitle text is visually presented:
/// - `.karaoke`: Gold word-by-word highlighting synced with TTS playback
/// - `.bionic`: Bold prefix on each word for faster scanning (40% rule)
/// - `.plain`: White text with no highlighting or bold prefix
public enum DisplayMode: String, Codable, Sendable {
    case karaoke
    case bionic
    case plain

    /// Parse a string into a DisplayMode, defaulting to `.karaoke` for unknown values.
    static func from(string: String) -> DisplayMode {
        DisplayMode(rawValue: string) ?? .karaoke
    }
}
