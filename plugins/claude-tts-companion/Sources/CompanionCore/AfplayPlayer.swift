// Jitter-free audio playback via afplay subprocess.
//
// Replaces AVAudioEngine scheduling with macOS's built-in afplay command,
// which uses CoreAudio's optimized file-playback path. Wall-clock timing
// provides currentTime for karaoke subtitle sync.
import Foundation
import Logging

/// Plays concatenated TTS audio via afplay subprocess.
///
/// Accumulates Float32 PCM chunks, writes a single WAV file, and plays it
/// through afplay. Provides wall-clock currentTime for karaoke sync.
///
/// afplay uses CoreAudio's ExtAudioFile path which is more resilient to
/// CPU contention than AVAudioEngine's real-time render thread, eliminating
/// jitter during concurrent heavy workloads (e.g., Rust compilation).
@MainActor
public final class AfplayPlayer {

    private let logger = Logger(label: "afplay-player")

    /// Accumulated Float32 PCM samples at 48kHz mono.
    private var pendingSamples: [Float] = []

    /// The running afplay subprocess.
    private var process: Process?

    /// Wall-clock time when afplay started playing.
    private var playStartTime: Date?

    /// Path to the current WAV file being played.
    private var currentWavPath: String?

    /// Completion callback when playback finishes.
    private var onComplete: (() -> Void)?

    /// Whether playback has been stopped externally (vs finishing naturally).
    private var wasStopped = false

    // MARK: - Public API

    /// Append a chunk of Float32 PCM samples (48kHz mono) to the pending buffer.
    func appendChunk(samples: [Float]) {
        pendingSamples.append(contentsOf: samples)
    }

    /// Write all pending samples to a WAV file and play via afplay.
    /// Returns false if there are no samples or playback fails to start.
    @discardableResult
    func play(onComplete: (() -> Void)? = nil) -> Bool {
        guard !pendingSamples.isEmpty else {
            logger.warning("play() called with no pending samples")
            onComplete?()
            return false
        }

        stop()
        self.onComplete = onComplete
        wasStopped = false

        // Write WAV file
        let wavPath = NSTemporaryDirectory() + "tts-afplay-\(UUID().uuidString).wav"
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

        // Launch afplay
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        proc.arguments = [wavPath]
        proc.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let exitCode = process.terminationStatus
                if exitCode == 0 {
                    self.logger.info("afplay finished normally")
                } else if !self.wasStopped {
                    self.logger.warning("afplay exited with code \(exitCode)")
                }
                self.cleanup()
                let callback = self.onComplete
                self.onComplete = nil
                callback?()
            }
        }

        do {
            try proc.run()
            process = proc
            playStartTime = Date()
            logger.info("afplay started: \(wavPath) (\(String(format: "%.2f", duration))s, \(proc.processIdentifier))")
            return true
        } catch {
            logger.error("Failed to launch afplay: \(error)")
            cleanup()
            onComplete?()
            self.onComplete = nil
            return false
        }
    }

    /// Current playback time based on wall clock since play() was called.
    var currentTime: TimeInterval {
        guard let start = playStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    /// Whether afplay is currently running.
    var isPlaying: Bool {
        process?.isRunning ?? false
    }

    /// Whether there are samples waiting to be played.
    var hasPendingSamples: Bool {
        !pendingSamples.isEmpty
    }

    /// Stop playback, kill the afplay process, and discard pending samples.
    func stop() {
        wasStopped = true
        if let proc = process, proc.isRunning {
            proc.terminate()
            logger.info("afplay terminated (pid \(proc.processIdentifier))")
        }
        process = nil
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

    /// Delete the temp WAV file.
    private func cleanup() {
        if let path = currentWavPath {
            try? FileManager.default.removeItem(atPath: path)
            currentWavPath = nil
        }
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
