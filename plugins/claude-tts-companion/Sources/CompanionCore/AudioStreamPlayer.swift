// Gapless streaming audio player using AVAudioEngine + AVAudioPlayerNode.
//
// Replaces per-chunk AVAudioPlayer creation with a persistent audio graph
// that stays warm between chunks. scheduleBuffer() enables gapless transitions
// without hardware cold-start latency.
import AVFoundation
import Foundation
import Logging

/// Callback fired when a scheduled buffer finishes playing (for subtitle sync + back-pressure).
typealias ChunkCompletionHandler = () -> Void

/// Persistent audio engine for gapless streaming TTS playback.
///
/// The engine is started once and kept running. Callers feed PCM buffers
/// via `scheduleChunk()`, which queues them on the player node for
/// seamless back-to-back playback on the real-time audio thread.
///
/// Key advantages over AVAudioPlayer:
/// 1. Hardware never goes cold between chunks (persistent audio graph)
/// 2. Real-time audio thread with proper QoS (won't be preempted by GPU work)
/// 3. scheduleBuffer() with .dataPlayedBack callback for gapless transitions
/// 4. Float32 PCM directly to AVAudioPCMBuffer (no WAV file I/O needed)
public final class AudioStreamPlayer: @unchecked Sendable {

    private let logger = Logger(label: "audio-stream-player")

    /// The audio engine that owns the hardware output.
    private let engine = AVAudioEngine()

    /// The player node that receives scheduled buffers.
    private let playerNode = AVAudioPlayerNode()

    /// Standard format for all TTS audio: 24kHz mono float32.
    private let format: AVAudioFormat

    /// Whether the engine is currently running.
    private(set) var isRunning: Bool = false

    /// Lock protecting engine start/stop operations.
    private let engineLock = NSLock()

    /// Tracks the number of buffers currently scheduled (for isEmpty checks).
    private var scheduledBufferCount: Int = 0
    private let bufferCountLock = NSLock()

    /// Observer token for AVAudioEngine configuration change notifications.
    private var configChangeObserver: NSObjectProtocol?

    /// Called when audio route changes (e.g., Bluetooth disconnect). Fires on main queue.
    /// TTSPipelineCoordinator uses this to cancel current pipeline and optionally restart.
    var onRouteChange: (() -> Void)?

    /// Whether the player node is currently playing audio.
    var isPlaying: Bool {
        playerNode.isPlaying
    }

    /// Current playback time within the currently-playing buffer.
    ///
    /// Uses `lastRenderTime` + `playerTime` to get the precise sample position.
    /// Returns 0 if no audio is playing.
    var currentTime: TimeInterval {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return 0
        }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    // MARK: - Lifecycle

    init() {
        // Create the standard format: 24kHz mono float32 (matches Kokoro output)
        guard let fmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000.0,
            channels: 1,
            interleaved: false
        ) else {
            fatalError("Failed to create AVAudioFormat for 24kHz mono float32")
        }
        self.format = fmt

        // Attach the player node to the engine graph
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        // Observe audio configuration changes (Bluetooth disconnect, USB DAC removal, etc.)
        // When hardware route changes, macOS invalidates the AVAudioEngine configuration.
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }

        logger.info("AudioStreamPlayer created (24kHz mono float32, AVAudioEngine)")
    }

    deinit {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        stop()
    }

    // MARK: - Engine Control

    /// Start the audio engine. Call once before scheduling any buffers.
    ///
    /// Safe to call multiple times (no-op if already running).
    /// Must be called from the main thread (AVAudioEngine requirement).
    func start() {
        engineLock.lock()
        defer { engineLock.unlock() }

        guard !isRunning else { return }

        do {
            try engine.start()
            isRunning = true
            logger.info("AVAudioEngine started")
        } catch {
            logger.error("Failed to start AVAudioEngine: \(error)")
        }
    }

    /// Stop the engine and player node. Cancels all scheduled buffers.
    func stop() {
        engineLock.lock()
        defer { engineLock.unlock() }

        playerNode.stop()
        if isRunning {
            engine.stop()
            isRunning = false
        }
        bufferCountLock.lock()
        scheduledBufferCount = 0
        bufferCountLock.unlock()

        logger.info("AudioStreamPlayer stopped")
    }

    /// Reset for a new streaming session: stop the player node (cancels queued
    /// buffers) then restart it so new buffers can be scheduled immediately.
    /// The engine stays running (hardware stays warm).
    func reset() {
        engineLock.lock()
        defer { engineLock.unlock() }

        playerNode.stop()
        bufferCountLock.lock()
        scheduledBufferCount = 0
        bufferCountLock.unlock()

        // Ensure engine is running (start is idempotent internally)
        if !isRunning {
            do {
                try engine.start()
                isRunning = true
            } catch {
                logger.error("Failed to restart AVAudioEngine: \(error)")
            }
        }

        logger.info("AudioStreamPlayer reset for new session")
    }

    // MARK: - Route Change Recovery

    /// Handle AVAudioEngine configuration change (hardware route change).
    ///
    /// When Bluetooth headphones disconnect mid-playback, macOS invalidates the
    /// engine configuration. This method stops the player node (cancels queued buffers),
    /// attempts to restart the engine on the new default output device, and notifies
    /// the coordinator via `onRouteChange` callback.
    private func handleConfigurationChange() {
        logger.warning("Audio configuration changed (hardware route change)")

        engineLock.lock()

        // Stop player node -- cancels all queued buffers
        playerNode.stop()
        bufferCountLock.lock()
        scheduledBufferCount = 0
        bufferCountLock.unlock()

        // Try to restart engine on new default output device
        do {
            try engine.start()
            isRunning = true
            logger.info("AVAudioEngine restarted on new audio device")
        } catch {
            isRunning = false
            logger.error("Failed to restart AVAudioEngine after route change: \(error)")
        }

        engineLock.unlock()

        // Notify coordinator to cancel current pipeline (subtitle-only fallback if needed)
        onRouteChange?()
    }

    // MARK: - Buffer Scheduling

    /// Schedule a chunk of float32 PCM samples for gapless playback.
    ///
    /// - Parameters:
    ///   - samples: Raw float32 PCM audio at 24kHz mono
    ///   - onComplete: Called when this buffer finishes playing (`.dataPlayedBack`).
    ///     Fires on an internal AVAudioEngine thread -- dispatch to main if needed.
    func scheduleChunk(samples: [Float], onComplete: ChunkCompletionHandler? = nil) {
        guard !samples.isEmpty else {
            logger.warning("scheduleChunk called with empty samples")
            onComplete?()
            return
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            logger.error("Failed to create AVAudioPCMBuffer for \(samples.count) samples")
            onComplete?()
            return
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channelData = buffer.floatChannelData![0]
        samples.withUnsafeBufferPointer { ptr in
            channelData.update(from: ptr.baseAddress!, count: samples.count)
        }

        bufferCountLock.lock()
        scheduledBufferCount += 1
        bufferCountLock.unlock()

        // Schedule the buffer with .dataPlayedBack completion type.
        // This fires when the audio data has actually been rendered to hardware,
        // not just when it was consumed from the queue.
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.bufferCountLock.lock()
            self?.scheduledBufferCount -= 1
            self?.bufferCountLock.unlock()
            onComplete?()
        }

        // Start playing if not already (first buffer in a session)
        if !playerNode.isPlaying {
            playerNode.play()
        }

        let duration = Double(samples.count) / 24000.0
        logger.info("Scheduled buffer: \(samples.count) samples (\(String(format: "%.2f", duration))s)")
    }

    /// Schedule a WAV file for playback (fallback path for non-streaming use).
    ///
    /// Reads the WAV file into a buffer and schedules it. Used by the single-shot
    /// TTS path and /tts/test endpoint.
    func scheduleFile(wavPath: String, onComplete: ChunkCompletionHandler? = nil) {
        let url = URL(fileURLWithPath: wavPath)
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let frameCount = AVAudioFrameCount(audioFile.length)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: frameCount
            ) else {
                logger.error("Failed to create buffer for WAV: \(wavPath)")
                onComplete?()
                return
            }
            try audioFile.read(into: buffer)

            bufferCountLock.lock()
            scheduledBufferCount += 1
            bufferCountLock.unlock()

            playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                self?.bufferCountLock.lock()
                self?.scheduledBufferCount -= 1
                self?.bufferCountLock.unlock()
                // Clean up WAV file after playback
                try? FileManager.default.removeItem(atPath: wavPath)
                onComplete?()
            }

            if !playerNode.isPlaying {
                playerNode.play()
            }

            let duration = Double(frameCount) / audioFile.processingFormat.sampleRate
            logger.info("Scheduled WAV file: \(wavPath) (\(String(format: "%.2f", duration))s)")
        } catch {
            logger.error("Failed to read WAV for scheduling: \(error)")
            onComplete?()
        }
    }

    /// Whether there are any buffers still queued or playing.
    var hasScheduledBuffers: Bool {
        bufferCountLock.lock()
        defer { bufferCountLock.unlock() }
        return scheduledBufferCount > 0
    }
}
