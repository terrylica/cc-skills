// FILE-SIZE-OK — single-file player with batch + pipelined modes sharing 60%+ logic
// Jitter-free audio playback via afplay subprocess.
//
// Uses posix_spawn directly (not Foundation Process) to launch afplay
// in its own process group with /dev/null I/O — matching how terminal
// launches it. Wall-clock timing provides currentTime for karaoke sync.
import Darwin
import Foundation
import Logging

/// Plays TTS audio via afplay subprocess with chained paragraph playback.
///
/// Two modes of operation:
/// 1. **Batch mode** (existing): `appendChunk()` → `play()` — accumulates samples,
///    writes one WAV, plays once. Used for single-paragraph and automated TTS.
/// 2. **Pipelined mode** (new): `playOrEnqueue()` → `markQueueComplete()` — plays
///    first paragraph immediately, queues subsequent paragraphs, chains afplay
///    invocations with ~50-200ms natural gaps. Used for multi-paragraph user TTS.
///
/// Provides cumulative `currentTime` across chained paragraphs for karaoke sync.
///
/// Uses posix_spawn directly instead of Foundation's Process class to
/// eliminate overhead and give afplay its own process group, matching
/// terminal launch behavior.
@MainActor
public final class AfplayPlayer {

    private let logger = Logger(label: "afplay-player")

    /// Accumulated Float32 PCM samples at 48kHz mono (batch mode).
    private var pendingSamples: [Float] = []

    /// PID of the running afplay subprocess.
    private var afplayPID: pid_t = 0

    /// Wall-clock time when current afplay segment started playing.
    private var playStartTime: Date?

    /// Path to the current WAV file being played.
    private var currentWavPath: String?

    /// Debug directory for retaining WAV files for manual inspection.
    /// Files are kept (not deleted) so you can listen independently.
    ///
    /// Path is captured eagerly; actual writability is re-verified before
    /// every WAV write via `ensureWritableWavDirectory()` to self-heal
    /// mid-session deletion (h07).
    private let debugWavDir: String = NSHomeDirectory() + "/.local/share/tts-debug-wav"

    // MARK: - WAV Path Fallback Chain (h07)

    /// Classification of WAV-write-path failures, for structured telemetry.
    private enum WavFailureClass: String {
        case missingDir = "missing_dir"   // ENOENT on parent
        case eperm = "eperm"              // EPERM / EACCES
        case enospc = "enospc"            // ENOSPC / EDQUOT
        case erofs = "erofs"              // EROFS
        case eexist = "eexist"            // EEXIST where dir was expected (race)
        case other = "other"
    }

    /// Collapsed failure telemetry — at most one log per class per 60s.
    private struct WavWriteFailureState {
        var consecutiveFailureCount: Int = 0
        var firstFailureAt: Date? = nil
        var lastFailureClass: String? = nil
        var fallbackLevel: Int = 0          // 0=primary, 1=tmpdir, 2=mkstemp
        var nextRecoveryAttemptAt: Date? = nil
        var totalFallbackWrites: Int = 0
        var lastLoggedAt: [String: Date] = [:]   // per-class throttle
    }

    /// Sendable snapshot for /health exposure.
    public struct AfplayHealthSnapshot: Sendable, Codable {
        public let primary_dir_writable: Bool
        public let fallback_level: Int
        public let consecutive_failure_count: Int
        public let total_fallback_writes: Int
        public let last_failure_class: String?
        public let last_failure_at: String?   // ISO8601, nil if never
    }

    private var wavFailureState = WavWriteFailureState()

    public init() {
        do {
            try FileManager.default.createDirectory(
                atPath: debugWavDir, withIntermediateDirectories: true)
        } catch {
            // Non-fatal: ensureWritableWavDirectory() will retry on first write.
            logger.error("Failed to create debugWavDir at init: \(error) — will retry on first write via fallback chain")
        }
    }

    #if DEBUG
    /// Test-only accessor for log throttle state. Do not use in production code.
    internal var __testing_loggedClassCount: Int { wavFailureState.lastLoggedAt.count }
    internal var __testing_consecutiveFailureCount: Int { wavFailureState.consecutiveFailureCount }
    internal func ensureWritableWavDirectoryForTesting() -> (url: URL, level: Int, mkstempPath: String?) {
        return ensureWritableWavDirectory()
    }
    #endif

    /// Completion callback when playback finishes (batch mode).
    private var onComplete: (() -> Void)?

    /// Whether playback has been stopped externally (vs finishing naturally).
    private var wasStopped = false

    /// Background thread monitoring afplay exit via waitpid.
    private var waitThread: Thread?

    // MARK: - Pipelined Playback State

    /// Queue of paragraphs waiting to play after the current one finishes.
    private var playQueue: [(samples: [Float], label: String?)] = []

    /// Cumulative playback time from all finished paragraph segments.
    /// Added to wall-clock elapsed for correct karaoke sync across chained afplay.
    private var cumulativeTimeOffset: TimeInterval = 0

    /// Duration of the currently-playing paragraph segment (computed from sample count).
    private var currentSegmentDuration: TimeInterval = 0

    /// Whether markQueueComplete() has been called (no more paragraphs coming).
    private var queueComplete = false

    /// Whether playback finished and is waiting for next synthesis to arrive.
    /// When true, the next playOrEnqueue() call starts afplay immediately.
    private var isWaitingForNextChunk = false

    /// Callback fired when queue drains and queueComplete is true.
    private var allCompleteCallback: (() -> Void)?

    /// Duration of the segment that just finished (pending offset advancement).
    /// Advanced into cumulativeTimeOffset when the NEXT segment starts, not when
    /// the current one finishes. This prevents currentTime from jumping to the
    /// next chunk boundary during the gap between segments.
    private var finishedSegmentDuration: TimeInterval = 0

    /// Wall-clock time when the last segment finished playing (for gap measurement).
    private var lastSegmentEndTime: Date?

    /// Whether we already logged the segment-duration cap for the current segment.
    /// Prevents 60Hz log spam from the cap firing every tick.
    private var didLogCap: Bool = false

    /// Whether we're in pipelined mode (vs batch mode).
    /// Exposed for SubtitleSyncDriver to skip the !isPlaying safety-net check
    /// during inter-segment gaps (isPlaying is briefly false between chained afplay).
    private(set) var isPipelinedMode = false

    // MARK: - Public API

    /// Append a chunk of Float32 PCM samples (48kHz mono) to the pending buffer.
    func appendChunk(samples: [Float]) {
        pendingSamples.append(contentsOf: samples)
    }

    /// Write all pending samples to a WAV file and play via afplay.
    /// - Parameter label: Optional identifier embedded in the WAV filename
    ///   (e.g., first few words of subtitle text) for correlating files to captions.
    /// - Returns: false if there are no samples or playback fails to start.
    @discardableResult
    func play(label: String? = nil, onComplete: (() -> Void)? = nil) -> Bool {
        guard !pendingSamples.isEmpty else {
            logger.warning("play() called with no pending samples")
            onComplete?()
            return false
        }

        stop()
        self.onComplete = onComplete
        wasStopped = false

        // Write WAV file to debug directory (retained for manual inspection)
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let slug: String
        if let label = label, !label.isEmpty {
            let clean = label
                .prefix(40)
                .filter { $0.isLetter || $0.isNumber || $0 == " " }
                .replacingOccurrences(of: " ", with: "_")
            slug = clean.isEmpty ? String(UUID().uuidString.prefix(8)).lowercased() : clean
        } else {
            slug = String(UUID().uuidString.prefix(8)).lowercased()
        }
        let resolved = ensureWritableWavDirectory()
        let wavPath: String
        if let mkstempPath = resolved.mkstempPath {
            wavPath = mkstempPath  // level 2 — exact file path from mkstemp
        } else {
            wavPath = resolved.url.appendingPathComponent("tts-\(timestamp)_\(slug).wav").path
        }
        do {
            try writeWav(samples: pendingSamples, sampleRate: 48000, to: wavPath)
        } catch {
            recordFailure(classify(error), error: error, attemptedPath: wavPath)
            logger.error("Failed to write WAV for afplay: \(error)")
            onComplete?()
            return false
        }
        currentWavPath = wavPath

        let duration = Double(pendingSamples.count) / 48000.0
        pendingSamples.removeAll(keepingCapacity: true)

        // Launch afplay via posix_spawn in its own process group.
        //
        // QoS scheduling: the companion's launchd plist uses ProcessType=Interactive
        // (not Adaptive) so macOS assigns it user-interactive QoS (PRI≈60). Child
        // processes spawned with QOS_CLASS_USER_INTERACTIVE inherit this elevated
        // scheduling band, matching terminal-launched afplay behavior.
        //
        // Previous bug: ProcessType=Adaptive allowed macOS to downgrade the companion
        // to background QoS (PRI=4), and posix_spawnattr_set_qos_class_np was ignored
        // for children of low-QoS parents — causing audio jitter.
        var pid: pid_t = 0

        let cPath = strdup("/usr/bin/afplay")!
        let cArg = strdup(wavPath)!
        var argv: [UnsafeMutablePointer<CChar>?] = [cPath, cArg, nil]

        // File actions: redirect stdin/stdout/stderr to /dev/null
        var fileActions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)

        // Spawn attributes: own process group + USER_INTERACTIVE QoS.
        var spawnAttr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&spawnAttr)
        posix_spawnattr_setflags(&spawnAttr, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&spawnAttr, 0)
        posix_spawnattr_set_qos_class_np(&spawnAttr, QOS_CLASS_USER_INTERACTIVE)

        let spawnResult = posix_spawn(&pid, "/usr/bin/afplay", &fileActions, &spawnAttr, &argv, environ)

        // Cleanup spawn resources
        posix_spawn_file_actions_destroy(&fileActions)
        posix_spawnattr_destroy(&spawnAttr)
        free(cPath)
        free(cArg)

        guard spawnResult == 0 else {
            logger.error("posix_spawn failed: \(spawnResult) (\(String(cString: strerror(spawnResult))))")
            onComplete?()
            self.onComplete = nil
            return false
        }

        afplayPID = pid
        playStartTime = Date()
        logger.info("afplay started (posix_spawn): \(wavPath) (\(String(format: "%.2f", duration))s, pid \(pid))")

        // Monitor afplay exit on a background thread via waitpid.
        // Can't use SIGCHLD because our process may have other children.
        let capturedPID = pid
        let thread = Thread {
            var status: Int32 = 0
            waitpid(capturedPID, &status, 0)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.afplayPID == capturedPID else { return }
                if (status & 0x7f) == 0 && ((status >> 8) & 0xff) == 0 {
                    self.logger.info("afplay finished normally")
                } else if !self.wasStopped {
                    self.logger.warning("afplay exited with status \(status)")
                }
                self.afplayPID = 0
                self.cleanup()
                let callback = self.onComplete
                self.onComplete = nil
                callback?()
            }
        }
        thread.qualityOfService = QualityOfService.utility
        thread.start()
        waitThread = thread

        return true
    }

    /// Current playback time, cumulative across chained paragraph segments.
    ///
    /// Between segments (playStartTime nil): frozen at `cumulativeTimeOffset`.
    /// During playback: `cumulativeTimeOffset + elapsed`, capped to the current
    /// segment's duration so the subtitle can never overflow into the next chunk
    /// (afplay startup delay would otherwise make currentTime race ahead of audio).
    var currentTime: TimeInterval {
        guard let start = playStartTime else {
            return cumulativeTimeOffset  // frozen between segments
        }
        let elapsed = Date().timeIntervalSince(start)
        let capped: TimeInterval
        if currentSegmentDuration > 0 && elapsed > currentSegmentDuration {
            capped = currentSegmentDuration
            if !didLogCap {
                didLogCap = true
                logger.info("[TELEMETRY] Segment-duration cap activated: elapsed=\(String(format: "%.3f", elapsed))s > segmentDuration=\(String(format: "%.3f", currentSegmentDuration))s, capping at \(String(format: "%.3f", currentSegmentDuration))s")
            }
        } else {
            capped = elapsed
        }
        return cumulativeTimeOffset + capped
    }

    /// Whether afplay is currently running.
    var isPlaying: Bool {
        guard afplayPID > 0 else { return false }
        // kill(pid, 0) checks if process exists without sending a signal
        return kill(afplayPID, 0) == 0
    }

    /// Whether there are samples waiting to be played.
    var hasPendingSamples: Bool {
        !pendingSamples.isEmpty
    }

    /// Re-anchor playStartTime to now, aligning time=0 with subtitle display.
    /// Combined with the segment-duration cap on currentTime, this ensures the
    /// first tick sees currentTime ≈ 0 (not the WAV write + spawn delay).
    func resyncPlayStart() {
        playStartTime = Date()
    }

    // MARK: - Pipelined Playback API

    /// Play a paragraph immediately or queue it behind the current playback.
    ///
    /// First call: writes WAV and launches afplay immediately.
    /// Subsequent calls while playing: queues for chained playback.
    /// If called while waiting (synthesis slower than playback): plays immediately.
    func playOrEnqueue(samples: [Float], label: String?) {
        guard !samples.isEmpty else {
            logger.warning("playOrEnqueue called with empty samples")
            return
        }
        guard !queueComplete else {
            logger.warning("playOrEnqueue called after markQueueComplete — ignoring")
            return
        }

        isPipelinedMode = true

        if isWaitingForNextChunk {
            // Synthesis caught up — play immediately
            isWaitingForNextChunk = false
            logger.info("Synthesis caught up — playing queued paragraph immediately")
            startSegment(samples: samples, label: label)
        } else if afplayPID > 0 && kill(afplayPID, 0) == 0 {
            // Currently playing — queue for chained playback
            playQueue.append((samples: samples, label: label))
            let queuedDuration = Double(samples.count) / 48000.0
            logger.info("Queued paragraph for chained playback (\(String(format: "%.2f", queuedDuration))s, queue depth: \(playQueue.count))")
        } else {
            // Nothing playing — start immediately
            startSegment(samples: samples, label: label)
        }
    }

    /// Signal that no more paragraphs will be enqueued.
    /// Fires the callback when the queue fully drains (all paragraphs played).
    func markQueueComplete(onComplete: @escaping () -> Void) {
        queueComplete = true

        if isWaitingForNextChunk && playQueue.isEmpty {
            // Was waiting for synthesis that will never come — flush and complete.
            // Without this, the system deadlocks: it waits for a playOrEnqueue that
            // will never arrive, and the completion callback never fires.
            cumulativeTimeOffset += finishedSegmentDuration
            finishedSegmentDuration = 0
            isWaitingForNextChunk = false
            logger.info("Queue complete while waiting for next chunk — flushing and completing")
            onComplete()
        } else if playQueue.isEmpty && !isPlaying && !isWaitingForNextChunk {
            // Already done — fire immediately
            logger.info("Queue already drained — firing completion immediately")
            onComplete()
        } else {
            allCompleteCallback = onComplete
        }
    }

    /// Start playing a single paragraph segment via afplay.
    private func startSegment(samples: [Float], label: String?) {
        // Reset cap log flag for the new segment
        didLogCap = false

        // Log inter-segment gap duration
        if let lastEnd = lastSegmentEndTime {
            let gap = Date().timeIntervalSince(lastEnd)
            logger.info("[TELEMETRY] Inter-segment gap: \(String(format: "%.3f", gap))s")
        }

        // Advance cumulative offset for the just-finished segment NOW (not in callback).
        // This ensures currentTime jumps to the next chunk boundary exactly when
        // the new afplay launches, keeping subtitle sync aligned with actual audio.
        if finishedSegmentDuration > 0 {
            cumulativeTimeOffset += finishedSegmentDuration
            finishedSegmentDuration = 0
        }

        // Kill any running afplay first
        if afplayPID > 0 {
            kill(afplayPID, SIGKILL)
            afplayPID = 0
        }
        wasStopped = false

        // Write WAV
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let slug: String
        if let label = label, !label.isEmpty {
            let clean = label
                .prefix(40)
                .filter { $0.isLetter || $0.isNumber || $0 == " " }
                .replacingOccurrences(of: " ", with: "_")
            slug = clean.isEmpty ? String(UUID().uuidString.prefix(8)).lowercased() : clean
        } else {
            slug = String(UUID().uuidString.prefix(8)).lowercased()
        }
        let resolved = ensureWritableWavDirectory()
        let wavPath: String
        if let mkstempPath = resolved.mkstempPath {
            wavPath = mkstempPath  // level 2 — exact file path from mkstemp
        } else {
            wavPath = resolved.url.appendingPathComponent("tts-\(timestamp)_\(slug).wav").path
        }
        do {
            try writeWav(samples: samples, sampleRate: 48000, to: wavPath)
        } catch {
            recordFailure(classify(error), error: error, attemptedPath: wavPath)
            logger.error("Failed to write WAV for pipelined afplay: \(error)")
            advanceQueue()
            return
        }
        currentWavPath = wavPath

        currentSegmentDuration = Double(samples.count) / 48000.0

        // Launch afplay via posix_spawn
        var pid: pid_t = 0
        let cPath = strdup("/usr/bin/afplay")!
        let cArg = strdup(wavPath)!
        var argv: [UnsafeMutablePointer<CChar>?] = [cPath, cArg, nil]

        var fileActions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)

        var spawnAttr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&spawnAttr)
        posix_spawnattr_setflags(&spawnAttr, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&spawnAttr, 0)
        posix_spawnattr_set_qos_class_np(&spawnAttr, QOS_CLASS_USER_INTERACTIVE)

        let spawnResult = posix_spawn(&pid, "/usr/bin/afplay", &fileActions, &spawnAttr, &argv, environ)

        posix_spawn_file_actions_destroy(&fileActions)
        posix_spawnattr_destroy(&spawnAttr)
        free(cPath)
        free(cArg)

        guard spawnResult == 0 else {
            logger.error("posix_spawn failed for pipelined afplay: \(spawnResult)")
            advanceQueue()
            return
        }

        afplayPID = pid
        playStartTime = Date()
        logger.info("afplay pipelined segment: \(wavPath) (\(String(format: "%.2f", currentSegmentDuration))s, pid \(pid), offset \(String(format: "%.2f", cumulativeTimeOffset))s)")

        // Monitor exit and chain to next segment
        let capturedPID = pid
        let thread = Thread {
            var status: Int32 = 0
            waitpid(capturedPID, &status, 0)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.afplayPID == capturedPID else { return }
                self.afplayPID = 0
                self.playStartTime = nil
                self.lastSegmentEndTime = Date()
                // Do NOT advance cumulativeTimeOffset here. It stays frozen so
                // currentTime returns the END of the last segment, keeping the tick
                // on the current chunk. Offset is advanced in startSegment() when
                // the next segment's afplay actually launches.
                self.finishedSegmentDuration = self.currentSegmentDuration
                self.currentWavPath = nil

                if self.wasStopped { return }

                if (status & 0x7f) == 0 && ((status >> 8) & 0xff) == 0 {
                    self.logger.info("afplay segment finished (cumulative \(String(format: "%.2f", self.cumulativeTimeOffset + self.finishedSegmentDuration))s)")
                } else {
                    self.logger.warning("afplay segment exited with status \(status)")
                }

                self.advanceQueue()
            }
        }
        thread.qualityOfService = .utility
        thread.start()
        waitThread = thread
    }

    /// Advance to the next queued paragraph or signal completion.
    private func advanceQueue() {
        logger.info("[TELEMETRY] advanceQueue: queue depth=\(playQueue.count)")
        if let next = playQueue.first {
            playQueue.removeFirst()
            startSegment(samples: next.samples, label: next.label)
        } else if queueComplete {
            // Flush any pending offset for the final segment
            cumulativeTimeOffset += finishedSegmentDuration
            finishedSegmentDuration = 0
            isPipelinedMode = false
            logger.info("All pipelined segments played (total \(String(format: "%.2f", cumulativeTimeOffset))s)")
            let callback = allCompleteCallback
            allCompleteCallback = nil
            callback?()
        } else {
            // Synthesis slower than playback — wait for next chunk
            isWaitingForNextChunk = true
            logger.info("Waiting for next synthesis (playback outpaced synthesis at \(String(format: "%.2f", cumulativeTimeOffset))s)")
        }
    }

    /// Stop playback, kill the afplay process, drain queue, and discard pending samples.
    ///
    /// Kills the tracked PID first, then does a defensive killall to catch any
    /// orphaned afplay processes from race conditions (e.g., new afplay spawned
    /// between task cancellation and pipeline cancel dispatch).
    func stop() {
        wasStopped = true
        if afplayPID > 0 {
            // SIGKILL (not SIGTERM): afplay with USER_INTERACTIVE QoS on a
            // real-time audio thread ignores or delays SIGTERM delivery.
            // SIGKILL cannot be caught or ignored — instant process death.
            kill(afplayPID, SIGKILL)
            logger.info("afplay killed (pid \(afplayPID))")
            afplayPID = 0
        }
        // Belt-and-suspenders: kill ANY afplay process.
        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["-9", "afplay"]
        killall.standardOutput = FileHandle.nullDevice
        killall.standardError = FileHandle.nullDevice
        try? killall.run()
        playStartTime = nil
        // Drain pipelined queue
        playQueue.removeAll()
        queueComplete = false
        isWaitingForNextChunk = false
        allCompleteCallback = nil
        isPipelinedMode = false
        cleanup()
    }

    /// Reset for a new session: stop playback, clear pending samples and pipelined state.
    func reset() {
        stop()
        pendingSamples.removeAll(keepingCapacity: true)
        onComplete = nil
        cumulativeTimeOffset = 0
        currentSegmentDuration = 0
        finishedSegmentDuration = 0
        lastSegmentEndTime = nil
        didLogCap = false
    }

    // MARK: - Private

    /// Clear reference to current WAV path. Files are retained in debugWavDir
    /// for manual inspection -- listen to them to determine if jitter is in
    /// generation or playback. Clean up ~/.local/share/tts-debug-wav/ manually.
    private func cleanup() {
        currentWavPath = nil
    }

    // MARK: - WAV Path Resolution (h07)

    /// Resolve a writable directory for WAV output. Tries primary, then tmp, then
    /// last-resort mkstemp. Called before every WAV write — the createDirectory
    /// syscall is ~1-10us on an existing dir (idempotent stat).
    ///
    /// Returns the directory URL plus the fallback level used (0/1/2). For level 2
    /// (mkstemp), the "directory" is `/tmp` and the caller must use the exact file
    /// path returned by `mkstempPath` rather than composing its own.
    private func ensureWritableWavDirectory() -> (url: URL, level: Int, mkstempPath: String?) {
        // Tier 0: primary
        let primaryURL = URL(fileURLWithPath: debugWavDir, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: primaryURL, withIntermediateDirectories: true)
            // Success — check if we're recovering from a failing state
            if wavFailureState.fallbackLevel > 0 || wavFailureState.consecutiveFailureCount > 0 {
                logger.info("[TELEMETRY] afplay-player WAV write primary_recovered prior_failures=\(wavFailureState.consecutiveFailureCount) prior_level=\(wavFailureState.fallbackLevel)")
                wavFailureState.consecutiveFailureCount = 0
                wavFailureState.fallbackLevel = 0
                wavFailureState.firstFailureAt = nil
                wavFailureState.lastFailureClass = nil
                wavFailureState.nextRecoveryAttemptAt = nil
                wavFailureState.lastLoggedAt.removeAll()
            }
            return (primaryURL, 0, nil)
        } catch {
            recordFailure(classify(error), error: error, attemptedPath: debugWavDir)
        }

        // Tier 1: NSTemporaryDirectory()/claude-tts-wav
        let tmpPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("claude-tts-wav")
        let tmpURL = URL(fileURLWithPath: tmpPath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmpURL, withIntermediateDirectories: true)
            if wavFailureState.fallbackLevel < 1 {
                wavFailureState.fallbackLevel = 1
                logger.warning("[TELEMETRY] afplay-player WAV write fallback_engaged level=1 path=\(tmpPath) reason=\(wavFailureState.lastFailureClass ?? "unknown")")
            }
            wavFailureState.totalFallbackWrites += 1
            return (tmpURL, 1, nil)
        } catch {
            recordFailure(classify(error), error: error, attemptedPath: tmpPath)
        }

        // Tier 2: mkstemp in /tmp
        var template = Array("/tmp/claude-tts-wav-XXXXXX.wav".utf8CString)
        let fd = template.withUnsafeMutableBufferPointer { buf -> Int32 in
            return mkstemps(buf.baseAddress, 4)  // 4 = length of ".wav" suffix
        }
        if fd >= 0 {
            close(fd)
            let path = template.withUnsafeBufferPointer { buf -> String in
                String(cString: buf.baseAddress!)
            }
            if wavFailureState.fallbackLevel < 2 {
                wavFailureState.fallbackLevel = 2
                logger.warning("[TELEMETRY] afplay-player WAV write ultimate_fallback_engaged level=2 path=\(path)")
            }
            wavFailureState.totalFallbackWrites += 1
            return (URL(fileURLWithPath: "/tmp", isDirectory: true), 2, path)
        }
        // Truly exhausted — log and return primary (caller will fail gracefully)
        logger.error("[TELEMETRY] afplay-player WAV write all_tiers_exhausted errno=\(errno)")
        return (primaryURL, 0, nil)
    }

    private func classify(_ error: Error) -> WavFailureClass {
        let ns = error as NSError
        // NSError wrapping POSIX errors uses NSPOSIXErrorDomain with errno codes.
        if ns.domain == NSPOSIXErrorDomain {
            switch Int32(ns.code) {
            case ENOENT: return .missingDir
            case EPERM, EACCES: return .eperm
            case ENOSPC, EDQUOT: return .enospc
            case EROFS: return .erofs
            case EEXIST: return .eexist
            default: return .other
            }
        }
        // Cocoa errors from FileManager
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return .missingDir
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError: return .eperm
            case NSFileWriteOutOfSpaceError: return .enospc
            case NSFileWriteVolumeReadOnlyError: return .erofs
            case NSFileWriteFileExistsError: return .eexist
            default: return .other
            }
        }
        return .other
    }

    private func recordFailure(_ cls: WavFailureClass, error: Error, attemptedPath: String) {
        wavFailureState.consecutiveFailureCount += 1
        if wavFailureState.firstFailureAt == nil {
            wavFailureState.firstFailureAt = Date()
        }
        wavFailureState.lastFailureClass = cls.rawValue

        // Throttle: at most one log per class per 60s
        let now = Date()
        let lastLogged = wavFailureState.lastLoggedAt[cls.rawValue]
        if lastLogged == nil || now.timeIntervalSince(lastLogged!) >= 60.0 {
            let iso = ISO8601DateFormatter().string(from: wavFailureState.firstFailureAt ?? now)
            let tmpPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("claude-tts-wav")
            let activeFallback = wavFailureState.fallbackLevel == 0 ? debugWavDir
                : wavFailureState.fallbackLevel == 1 ? tmpPath : "/tmp/mkstemp"
            logger.warning("afplay-player WAV write failure CLASS=\(cls.rawValue) COUNT=\(wavFailureState.consecutiveFailureCount) SINCE=\(iso) fallback_active=\(activeFallback) successful_writes_via_fallback=\(wavFailureState.totalFallbackWrites) attempted_path=\(attemptedPath) error=\(error)")
            wavFailureState.lastLoggedAt[cls.rawValue] = now
        }
    }

    /// Sendable snapshot for /health.
    public func getAfplayHealthSnapshot() -> AfplayHealthSnapshot {
        let iso: String? = wavFailureState.firstFailureAt.map { ISO8601DateFormatter().string(from: $0) }
        let primaryWritable = (wavFailureState.fallbackLevel == 0 && wavFailureState.consecutiveFailureCount == 0)
        return AfplayHealthSnapshot(
            primary_dir_writable: primaryWritable,
            fallback_level: wavFailureState.fallbackLevel,
            consecutive_failure_count: wavFailureState.consecutiveFailureCount,
            total_fallback_writes: wavFailureState.totalFallbackWrites,
            last_failure_class: wavFailureState.lastFailureClass,
            last_failure_at: iso
        )
    }

    /// Write Float32 samples as a 16-bit PCM WAV file.
    private func writeWav(samples: [Float], sampleRate: Int, to path: String) throws {
        let numSamples = samples.count
        let dataSize = numSamples * 2  // 16-bit = 2 bytes per sample
        let fileSize = 36 + dataSize

        var data = Data(capacity: 44 + dataSize)

        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt chunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })  // chunk size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // PCM format
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // mono
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) }) // sample rate
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * 2).littleEndian) { Array($0) }) // byte rate
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })   // block align
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })  // bits per sample

        // data chunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })

        // Convert Float32 → Int16
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * 32767.0)
            data.append(contentsOf: withUnsafeBytes(of: int16.littleEndian) { Array($0) })
        }

        try data.write(to: URL(fileURLWithPath: path))
    }
}
