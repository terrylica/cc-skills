import Foundation
import Logging

/// Tails a growing JSONL (newline-delimited JSON) file using DispatchSource (WATCH-02).
///
/// Monitors a file for `.write` events via `O_EVTONLY` file descriptor. On each event,
/// reads new bytes from the last known offset, splits into complete lines, and fires
/// the callback. Partial lines (no trailing newline) are re-read on the next event.
///
/// The DispatchSource is stored as a strong instance property to prevent ARC deallocation (WATCH-03).
/// Event delivery latency is typically <50ms on macOS, within the 100ms target (WATCH-04).
public final class JSONLTailer: @unchecked Sendable {

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
