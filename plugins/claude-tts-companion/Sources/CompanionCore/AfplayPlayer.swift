// Jitter-free audio playback via afplay subprocess.
//
// Uses posix_spawn directly (not Foundation Process) to launch afplay
// in its own process group with /dev/null I/O — matching how terminal
// launches it. Wall-clock timing provides currentTime for karaoke sync.
import Darwin
import Foundation
import Logging

/// Plays concatenated TTS audio via afplay subprocess.
///
/// Accumulates Float32 PCM chunks, writes a single WAV file, and plays it
/// through afplay. Provides wall-clock currentTime for karaoke sync.
///
/// Uses posix_spawn directly instead of Foundation's Process class to
/// eliminate overhead and give afplay its own process group, matching
/// terminal launch behavior.
@MainActor
public final class AfplayPlayer {

    private let logger = Logger(label: "afplay-player")

    /// Accumulated Float32 PCM samples at 48kHz mono.
    private var pendingSamples: [Float] = []

    /// PID of the running afplay subprocess.
    private var afplayPID: pid_t = 0

    /// Wall-clock time when afplay started playing.
    private var playStartTime: Date?

    /// Path to the current WAV file being played.
    private var currentWavPath: String?

    /// Debug directory for retaining WAV files for manual inspection.
    /// Files are kept (not deleted) so you can listen independently.
    private let debugWavDir: String = {
        let dir = NSHomeDirectory() + "/.local/share/tts-debug-wav"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Completion callback when playback finishes.
    private var onComplete: (() -> Void)?

    /// Whether playback has been stopped externally (vs finishing naturally).
    private var wasStopped = false

    /// Background thread monitoring afplay exit via waitpid.
    private var waitThread: Thread?

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
        let wavPath = debugWavDir + "/tts-\(timestamp)_\(slug).wav"
        do {
            try writeWav(samples: pendingSamples, sampleRate: 48000, to: wavPath)
        } catch {
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

    /// Current playback time based on wall clock since play() was called.
    var currentTime: TimeInterval {
        guard let start = playStartTime else { return 0 }
        return Date().timeIntervalSince(start)
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

    /// Stop playback, kill the afplay process, and discard pending samples.
    ///
    /// Kills the tracked PID first, then does a defensive killall to catch any
    /// orphaned afplay processes from race conditions (e.g., new afplay spawned
    /// between task cancellation and pipeline cancel dispatch).
    func stop() {
        wasStopped = true
        if afplayPID > 0 {
            kill(afplayPID, SIGTERM)
            logger.info("afplay terminated (pid \(afplayPID))")
            afplayPID = 0
        }
        // Belt-and-suspenders: kill ANY afplay process spawned by this user.
        // Catches orphans from async dispatch races in stopAll().
        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["-TERM", "afplay"]
        killall.standardOutput = FileHandle.nullDevice
        killall.standardError = FileHandle.nullDevice
        try? killall.run()
        playStartTime = nil
        cleanup()
    }

    /// Reset for a new session: stop playback and clear pending samples.
    func reset() {
        stop()
        pendingSamples.removeAll(keepingCapacity: true)
        onComplete = nil
    }

    // MARK: - Private

    /// Clear reference to current WAV path. Files are retained in debugWavDir
    /// for manual inspection -- listen to them to determine if jitter is in
    /// generation or playback. Clean up ~/.local/share/tts-debug-wav/ manually.
    private func cleanup() {
        currentWavPath = nil
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
