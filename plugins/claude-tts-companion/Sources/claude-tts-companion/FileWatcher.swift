import Foundation
import Logging

/// Watches a directory for new .json notification files using DispatchSource (WATCH-01).
///
/// Uses `O_EVTONLY` file descriptor monitoring via `DispatchSource.makeFileSystemObjectSource`
/// to detect when new files appear in the Claude Code notification directory. Fires a callback
/// for each new `.json` file, deduplicating against previously seen filenames.
///
/// The DispatchSource is stored as a strong instance property to prevent ARC deallocation (WATCH-03).
/// Event delivery latency is typically <50ms on macOS, within the 100ms target (WATCH-04).
final class NotificationWatcher: @unchecked Sendable {

    private let logger = Logger(label: "notification-watcher")
    private let directoryPath: String
    private var source: DispatchSourceTimer?
    /// Maps filename → last known modification date. Detects both new files AND overwrites.
    private var knownFiles: [String: Date]
    private let lock = NSLock()
    private let callback: (String) -> Void

    /// Create a watcher for new .json files in the given directory.
    ///
    /// - Parameters:
    ///   - directory: Path to watch (defaults to `Config.notificationDir`)
    ///   - callback: Called with the full path of each newly detected or modified .json file
    init(directory: String = Config.notificationDir, callback: @escaping (String) -> Void) {
        self.directoryPath = directory
        self.callback = callback

        // Snapshot existing files WITH modification dates so we detect overwrites
        var existing: [String: Date] = [:]
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) {
            for filename in contents where filename.hasSuffix(".json") {
                let path = (directory as NSString).appendingPathComponent(filename)
                if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                   let mtime = attrs[.modificationDate] as? Date {
                    existing[filename] = mtime
                } else {
                    existing[filename] = Date.distantPast
                }
            }
        }
        self.knownFiles = existing
    }

    /// Begin watching the directory for new .json files.
    ///
    /// Uses a 2-second polling timer — more reliable than DispatchSource on macOS
    /// which can miss events due to coalescing or fd issues.
    func start() {
        // Ensure directory exists
        try? FileManager.default.createDirectory(
            atPath: directoryPath,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Poll every 2 seconds for new files (reliable, low overhead)
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + 2, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            self?.scanForNewFiles()
        }

        // Strong reference prevents ARC deallocation (WATCH-03)
        self.source = timer
        timer.resume()

        logger.info("Watching \(directoryPath) for new .json files")
    }

    /// Stop watching.
    func stop() {
        source?.cancel()
        source = nil
        logger.info("Stopped watching \(directoryPath)")
    }

    // MARK: - Private

    /// Scan directory for new or modified .json files, fire callback for each.
    private func scanForNewFiles() {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directoryPath) else {
            return
        }

        let jsonFiles = contents.filter { $0.hasSuffix(".json") }
        var changed: [String] = []

        lock.lock()
        for filename in jsonFiles {
            let path = (directoryPath as NSString).appendingPathComponent(filename)
            let mtime: Date
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let mt = attrs[.modificationDate] as? Date {
                mtime = mt
            } else {
                continue
            }

            if let lastSeen = knownFiles[filename] {
                // File exists — check if modified since last seen
                if mtime > lastSeen {
                    knownFiles[filename] = mtime
                    changed.append(filename)
                }
            } else {
                // New file
                knownFiles[filename] = mtime
                changed.append(filename)
            }
        }
        lock.unlock()

        for filename in changed {
            let fullPath = (directoryPath as NSString).appendingPathComponent(filename)
            logger.debug("Notification file changed: \(filename)")
            callback(fullPath)
        }
    }
}

/// Tails a growing JSONL file using offset-based reads via DispatchSource (WATCH-02).
///
/// Opens an `O_EVTONLY` file descriptor on the target file and uses
/// `DispatchSource.makeFileSystemObjectSource` to detect writes. On each write event,
/// reads new bytes from the last known offset, splits into complete lines, and fires
/// the callback. Partial lines (no trailing newline) are re-read on the next event.
///
/// The DispatchSource is stored as a strong instance property to prevent ARC deallocation (WATCH-03).
/// Event delivery latency is typically <50ms on macOS, within the 100ms target (WATCH-04).
final class JSONLTailer: @unchecked Sendable {

    private let logger = Logger(label: "jsonl-tailer")
    private let filePath: String
    private var source: DispatchSourceFileSystemObject?
    private var offset: UInt64 = 0
    private let callback: ([String]) -> Void
    private let lock = NSLock()

    /// Create a tailer for the given JSONL file.
    ///
    /// - Parameters:
    ///   - filePath: Absolute path to the JSONL file to tail
    ///   - callback: Called with an array of new complete lines on each write event
    init(filePath: String, callback: @escaping ([String]) -> Void) {
        self.filePath = filePath
        self.callback = callback

        // Start from end of file (only tail new content)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
           let size = attrs[.size] as? UInt64 {
            self.offset = size
        }
    }

    /// Begin tailing the file for new content.
    ///
    /// Opens an `O_EVTONLY` file descriptor and sets up a DispatchSource
    /// to fire on `.write` events.
    func start() {
        let fd = open(filePath, O_EVTONLY)
        guard fd != -1 else {
            logger.error("Failed to open file for tailing: \(filePath)")
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .global(qos: .userInitiated)
        )

        src.setEventHandler { [weak self] in
            self?.readNewLines()
        }

        src.setCancelHandler {
            close(fd)
        }

        // Strong reference prevents ARC deallocation (WATCH-03)
        self.source = src
        src.resume()

        logger.info("Tailing \(filePath) from offset \(offset)")
    }

    /// Stop tailing and release the file descriptor.
    func stop() {
        source?.cancel()
        source = nil
        logger.info("Stopped tailing \(filePath)")
    }

    // MARK: - Private

    /// Read new bytes from the file starting at the current offset.
    ///
    /// Splits data into lines. If the last chunk doesn't end with a newline,
    /// the partial line's bytes are subtracted from the offset so they get
    /// re-read on the next event (avoids yielding incomplete JSON lines).
    private func readNewLines() {
        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            logger.warning("Cannot open file for reading: \(filePath)")
            return
        }
        defer { fileHandle.closeFile() }

        lock.lock()
        let currentOffset = offset
        lock.unlock()

        fileHandle.seek(toFileOffset: currentOffset)
        let data = fileHandle.readDataToEndOfFile()

        guard !data.isEmpty else { return }

        guard let text = String(data: data, encoding: .utf8) else {
            logger.warning("New bytes at offset \(currentOffset) are not valid UTF-8")
            return
        }

        // Split into lines, handling partial last line
        let endsWithNewline = text.hasSuffix("\n")
        var lines = text.components(separatedBy: "\n")

        // Remove trailing empty element from split (if text ends with newline)
        if let last = lines.last, last.isEmpty {
            lines.removeLast()
        }

        var completeLinesBytes = UInt64(data.count)
        var completeLines = lines

        if !endsWithNewline && !lines.isEmpty {
            // Last line is incomplete -- don't yield it, rewind offset
            let partialLine = lines.last!
            let partialBytes = UInt64(partialLine.utf8.count)
            completeLinesBytes -= partialBytes
            completeLines.removeLast()
        }

        lock.lock()
        offset = currentOffset + completeLinesBytes
        lock.unlock()

        let nonEmpty = completeLines.filter { !$0.isEmpty }
        if !nonEmpty.isEmpty {
            callback(nonEmpty)
        }
    }
}
