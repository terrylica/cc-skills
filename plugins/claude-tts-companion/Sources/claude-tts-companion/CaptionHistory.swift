import AppKit
import Foundation
import Logging

/// A timestamped caption entry in the history ring buffer.
struct CaptionEntry: Codable, Sendable {
    /// The subtitle text that was displayed
    let text: String
    /// When the caption was shown (ISO 8601)
    let timestamp: String
    /// Monotonic index for ordering
    let index: Int
}

/// Thread-safe ring buffer that stores recent subtitle captions for scrollback and clipboard copy.
///
/// Stores up to `capacity` entries in a fixed-size ring buffer. New entries overwrite the oldest
/// when full. All access is guarded by NSLock for thread safety (consistent with TTSEngine,
/// CircuitBreaker, SettingsStore patterns).
///
/// Used by:
/// - SubtitlePanel (via `record`) to log every displayed caption
/// - HTTPControlServer (via `getAll` / `copyToClipboard`) for API access
final class CaptionHistory: @unchecked Sendable {

    private let logger = Logger(label: "caption-history")
    private let lock = NSLock()

    /// Ring buffer storage
    private var buffer: [CaptionEntry?]
    /// Next write position in the ring buffer
    private var head: Int = 0
    /// Total number of entries ever recorded (monotonic counter for index)
    private var totalCount: Int = 0
    /// Maximum number of entries to retain
    let capacity: Int

    /// Create a caption history with the given capacity.
    ///
    /// - Parameter capacity: Maximum number of captions to retain (default 100)
    init(capacity: Int = 100) {
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }

    /// Record a new caption in the history.
    ///
    /// - Parameter text: The subtitle text to record
    func record(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let formatter = ISO8601DateFormatter()
        let entry = CaptionEntry(
            text: trimmed,
            timestamp: formatter.string(from: Date()),
            index: totalCount
        )

        lock.lock()
        buffer[head] = entry
        head = (head + 1) % capacity
        totalCount += 1
        lock.unlock()

        logger.debug("Recorded caption #\(entry.index): \(trimmed.prefix(50))...")
    }

    /// Get all stored captions in chronological order.
    ///
    /// - Parameter limit: Maximum number of entries to return (nil = all)
    /// - Returns: Array of caption entries, oldest first
    func getAll(limit: Int? = nil) -> [CaptionEntry] {
        lock.lock()
        let entries = buffer.compactMap { $0 }.sorted { $0.index < $1.index }
        lock.unlock()

        if let limit = limit, limit < entries.count {
            return Array(entries.suffix(limit))
        }
        return entries
    }

    /// Get the total number of captions ever recorded (including overwritten ones).
    var count: Int {
        lock.lock()
        let c = totalCount
        lock.unlock()
        return c
    }

    /// Copy all caption text to the macOS clipboard, separated by newlines.
    ///
    /// - Parameter limit: Maximum number of recent captions to copy (nil = all)
    /// - Returns: The number of captions copied
    @MainActor
    func copyToClipboard(limit: Int? = nil) -> Int {
        let entries = getAll(limit: limit)
        guard !entries.isEmpty else { return 0 }

        let text = entries.map(\.text).joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        logger.info("Copied \(entries.count) captions to clipboard (\(text.count) chars)")
        return entries.count
    }

    /// Clear all caption history.
    func clear() {
        lock.lock()
        buffer = Array(repeating: nil, count: capacity)
        head = 0
        lock.unlock()
        logger.info("Caption history cleared")
    }
}
