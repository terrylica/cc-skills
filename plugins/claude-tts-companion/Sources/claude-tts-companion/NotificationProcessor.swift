import Foundation
import Logging

/// Gates notification processing with dedup (session ID + transcript size) and rate limiting.
///
/// Ported from legacy TypeScript notification-watcher.ts dedup/rate-limit logic.
/// - REL-01: Dedup skips re-notifications when transcript file has not grown since last notification
/// - REL-02: Rate limiting enforces 5-second minimum between notification processing
final class NotificationProcessor: @unchecked Sendable {

    // MARK: - Types

    private struct DedupEntry {
        let processedAt: Date
        let transcriptSize: UInt64
    }

    // MARK: - Properties

    private let logger = Logger(label: "notification-processor")
    private let lock = NSLock()

    /// Session-level dedup: keyed by sessionId, tracks last processed time + transcript size
    private var processedSessions: [String: DedupEntry] = [:]

    /// Rate limiting state
    private var lastProcessTime: Date = .distantPast
    private var isProcessing: Bool = false
    private var pendingFilePath: String?

    // MARK: - Dedup (REL-01)

    /// Check if a notification should be skipped (transcript unchanged within TTL).
    ///
    /// - Parameters:
    ///   - sessionId: The Claude session identifier
    ///   - transcriptPath: Path to the session transcript file
    /// - Returns: `true` if the notification is a duplicate and should be skipped
    func shouldSkipDedup(sessionId: String, transcriptPath: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = processedSessions[sessionId] else {
            return false
        }

        // TTL expired -- allow re-notification
        if Date().timeIntervalSince(entry.processedAt) > Config.notificationDedupTTL {
            return false
        }

        // Get current transcript file size
        let currentSize = fileSize(atPath: transcriptPath)

        if currentSize <= entry.transcriptSize {
            logger.info("Dedup: skipping \(sessionId.prefix(8))... (transcript unchanged at \(currentSize) bytes)")
            return true
        }

        logger.info("Dedup: re-notifying \(sessionId.prefix(8))... (transcript grew \(entry.transcriptSize) -> \(currentSize) bytes)")
        return false
    }

    /// Record a successfully processed session for future dedup checks.
    ///
    /// - Parameters:
    ///   - sessionId: The Claude session identifier
    ///   - transcriptPath: Path to the session transcript file
    func recordProcessed(sessionId: String, transcriptPath: String) {
        let size = fileSize(atPath: transcriptPath)
        lock.lock()
        processedSessions[sessionId] = DedupEntry(processedAt: Date(), transcriptSize: size)
        lock.unlock()
        logger.debug("Recorded session \(sessionId.prefix(8))... (\(size) bytes)")
    }

    /// Remove expired entries to prevent unbounded growth.
    /// Prunes entries older than TTL * 2 (30 minutes).
    func pruneExpiredEntries() {
        let cutoff = Date().addingTimeInterval(-(Config.notificationDedupTTL * 2))
        lock.lock()
        let before = processedSessions.count
        processedSessions = processedSessions.filter { $0.value.processedAt > cutoff }
        let after = processedSessions.count
        lock.unlock()
        if before > after {
            logger.debug("Pruned \(before - after) expired dedup entries (\(after) remaining)")
        }
    }

    // MARK: - Rate Limiting (REL-02)

    /// Gate notification processing with mutex + rate limiting.
    ///
    /// If already processing, stores the file path as pending.
    /// If within the rate limit window, schedules a retry.
    /// Otherwise, invokes the handler immediately.
    ///
    /// - Parameters:
    ///   - filePath: Path to the notification file
    ///   - handler: Closure that performs the actual notification processing
    func processIfReady(filePath: String, handler: @escaping (String) -> Void) {
        lock.lock()

        // Mutex gate: only one notification at a time
        if isProcessing {
            logger.info("Rate limit: blocked by mutex, queuing \(basename(filePath))")
            pendingFilePath = filePath
            lock.unlock()
            return
        }

        // Rate limit: enforce minimum interval between processing
        let elapsed = Date().timeIntervalSince(lastProcessTime)
        if elapsed < Config.notificationMinInterval {
            let retryIn = Config.notificationMinInterval - elapsed + 0.5
            logger.info("Rate limit: \(String(format: "%.1f", elapsed))s < \(Config.notificationMinInterval)s, retrying in \(String(format: "%.1f", retryIn))s")
            pendingFilePath = filePath
            lock.unlock()

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + retryIn) { [weak self] in
                guard let self = self else { return }
                self.lock.lock()
                let pending = self.pendingFilePath
                self.pendingFilePath = nil
                self.lock.unlock()
                if let path = pending {
                    self.processIfReady(filePath: path, handler: handler)
                }
            }
            return
        }

        // Ready to process
        isProcessing = true
        lastProcessTime = Date()
        lock.unlock()

        // Execute handler on background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            handler(filePath)

            guard let self = self else { return }
            self.lock.lock()
            self.isProcessing = false
            let pending = self.pendingFilePath
            self.pendingFilePath = nil
            self.lock.unlock()

            // Prune expired entries after each processing cycle
            self.pruneExpiredEntries()

            // Process pending notification if one arrived during processing
            if let pendingPath = pending {
                self.processIfReady(filePath: pendingPath, handler: handler)
            }
        }
    }

    // MARK: - Private Helpers

    /// Get file size in bytes, returns 0 if file doesn't exist.
    private func fileSize(atPath path: String) -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64 else {
            return 0
        }
        return size
    }

    /// Extract filename from path for logging.
    private func basename(_ path: String) -> String {
        return (path as NSString).lastPathComponent
    }
}
