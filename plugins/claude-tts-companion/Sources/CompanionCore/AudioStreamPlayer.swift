// Gapless streaming audio player using AVAudioEngine + AVAudioPlayerNode.
//
// Replaces per-chunk AVAudioPlayer creation with a persistent audio graph
// that stays warm between chunks. scheduleBuffer() enables gapless transitions
// without hardware cold-start latency.
import AVFoundation
import CoreAudio
import Foundation
import Logging

/// Callback fired when a scheduled buffer finishes playing (for subtitle sync + back-pressure).
typealias ChunkCompletionHandler = () -> Void

/// CoreAudio HAL property listener callback (C function pointer).
/// Fires on an internal CoreAudio thread -- dispatches to main queue for thread safety.
private func defaultOutputDeviceChanged(
    _ objectID: AudioObjectID,
    _ numberAddresses: UInt32,
    _ addresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData = clientData else { return noErr }
    let player = Unmanaged<AudioStreamPlayer>.fromOpaque(clientData).takeUnretainedValue()
    DispatchQueue.main.async {
        player.triggerRebuild(source: .halListener)
    }
    return noErr
}

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

    /// Whether the CoreAudio HAL property listener is registered.
    private var halListenerRegistered: Bool = false

    /// Cached output device ID (set on engine start/rebuild, compared in health check).
    private(set) var cachedOutputDeviceID: AudioDeviceID = AudioDeviceID(kAudioDeviceUnknown)

    /// Timestamp of the last successful engine rebuild (for cooldown enforcement).
    private var lastRebuildTime: CFAbsoluteTime = 0

    /// Pending debounced rebuild work item (cancelled on each new trigger).
    private var rebuildWorkItem: DispatchWorkItem?

    /// Source that triggered an engine rebuild.
    enum RebuildSource: String {
        case halListener, configNotification, healthCheck
    }

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
        // Create the standard format: 48kHz mono float32.
        // Audio from Kokoro (24kHz) is upsampled 2x before scheduling to match
        // CoreAudio's native hardware rate, eliminating internal sample rate converter
        // artifacts at buffer boundaries.
        guard let fmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000.0,
            channels: 1,
            interleaved: false
        ) else {
            fatalError("Failed to create AVAudioFormat for 48kHz mono float32")
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

        // Register CoreAudio HAL listener for default output device changes
        setupHALListener()

        // Cache the initial output device ID
        cachedOutputDeviceID = getSystemDefaultOutputDeviceID()
        let initialDeviceName = getDeviceName(deviceID: cachedOutputDeviceID)
        logger.info("AudioStreamPlayer created (48kHz mono float32, AVAudioEngine, device: \(initialDeviceName) [\(cachedOutputDeviceID)])")
    }

    deinit {
        removeHALListener()
        rebuildWorkItem?.cancel()
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
            cachedOutputDeviceID = getSystemDefaultOutputDeviceID()
            let deviceName = getDeviceName(deviceID: cachedOutputDeviceID)
            logger.info("AVAudioEngine started on \(deviceName) [\(cachedOutputDeviceID)]")
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
    /// Pre-starts the player node with a tiny silent lead-in to eliminate first-buffer blips.
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

        // Pre-start player node with a tiny silent lead-in (~10ms).
        // This primes the CoreAudio render pipeline so the first real buffer
        // doesn't get a blip from the player node cold-starting mid-schedule.
        if let silentBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480) {
            silentBuffer.frameLength = 480  // 10ms at 48kHz
            memset(silentBuffer.floatChannelData![0], 0, 480 * MemoryLayout<Float>.size)
            playerNode.play()
            playerNode.scheduleBuffer(silentBuffer)
        }

        logger.info("AudioStreamPlayer reset for new session (player pre-started)")
    }

    // MARK: - Route Change Recovery

    /// Handle AVAudioEngine configuration change (hardware route change).
    ///
    /// When Bluetooth headphones disconnect mid-playback, macOS invalidates the
    /// engine configuration. Feeds into the unified debounced rebuild path so that
    /// rapid config changes (e.g., Bluetooth reconnect) are collapsed into a single rebuild.
    private func handleConfigurationChange() {
        logger.warning("Audio configuration changed (hardware route change)")
        triggerRebuild(source: .configNotification)
    }

    // MARK: - Device Change Detection

    /// Register CoreAudio HAL property listener for default output device changes.
    /// Uses the C function pointer variant (NOT the block variant which has a known Apple removal bug).
    private func setupHALListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            defaultOutputDeviceChanged,
            selfPtr
        )
        if status == noErr {
            halListenerRegistered = true
            logger.info("CoreAudio HAL listener registered for default output device changes")
        } else {
            logger.error("Failed to register CoreAudio HAL listener: \(status)")
        }
    }

    /// Remove CoreAudio HAL property listener.
    private func removeHALListener() {
        guard halListenerRegistered else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            defaultOutputDeviceChanged,
            selfPtr
        )
        halListenerRegistered = false
        if status != noErr {
            logger.warning("Failed to remove CoreAudio HAL listener: \(status)")
        }
    }

    /// Query the system default output device ID via CoreAudio HAL.
    func getSystemDefaultOutputDeviceID() -> AudioDeviceID {
        var deviceID = AudioDeviceID(kAudioDeviceUnknown)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil,
            &propertySize, &deviceID
        )
        return deviceID
    }

    /// Get the human-readable name for an audio device.
    func getDeviceName(deviceID: AudioDeviceID) -> String {
        var name: CFString = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, &name)
        if status != noErr {
            return "Unknown"
        }
        return name as String
    }

    /// Debounced entry point for engine rebuild. Cancels any pending rebuild and schedules
    /// a new one after the debounce window. Enforces cooldown between rebuilds.
    func triggerRebuild(source: RebuildSource) {
        logger.info("Rebuild triggered by \(source.rawValue)")

        // Cancel pending debounce
        rebuildWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Cooldown check
            let now = CFAbsoluteTimeGetCurrent()
            if now - self.lastRebuildTime < Config.audioRebuildCooldownSeconds {
                let remaining = Config.audioRebuildCooldownSeconds - (now - self.lastRebuildTime)
                self.logger.info("Rebuild skipped (cooldown active, \(String(format: "%.1f", remaining))s remaining)")
                return
            }

            self.rebuildEngine()

            // Notify coordinator after rebuild completes
            self.onRouteChange?()
        }
        rebuildWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(Int(Config.audioRebuildDebounceMs)),
            execute: work
        )
    }

    /// Full engine teardown and rebuild: stop -> detach -> reset -> re-attach -> connect -> prepare -> start.
    /// Preserves the 48kHz mono float32 format by using the stored `format` (NOT engine.outputNode.outputFormat).
    private func rebuildEngine() {
        engineLock.lock()
        defer { engineLock.unlock() }

        let startTime = CFAbsoluteTimeGetCurrent()
        let oldDeviceID = cachedOutputDeviceID
        let newDeviceID = getSystemDefaultOutputDeviceID()
        let newDeviceName = getDeviceName(deviceID: newDeviceID)

        logger.warning("Rebuilding audio engine: device \(oldDeviceID) -> \(newDeviceID) (\(newDeviceName))")

        // 1. Stop everything
        playerNode.stop()
        bufferCountLock.lock()
        scheduledBufferCount = 0
        bufferCountLock.unlock()

        if isRunning {
            engine.stop()
            isRunning = false
        }

        // 2. Teardown graph
        engine.detach(playerNode)
        engine.reset()

        // 3. Rebuild graph (preserves 48kHz mono float32 format)
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.prepare()

        // 4. Start
        do {
            try engine.start()
            isRunning = true
            cachedOutputDeviceID = getSystemDefaultOutputDeviceID()
            lastRebuildTime = CFAbsoluteTimeGetCurrent()
            let duration = lastRebuildTime - startTime
            logger.info("Audio engine rebuilt successfully on \(newDeviceName) (took \(String(format: "%.1f", duration * 1000))ms)")
        } catch {
            isRunning = false
            logger.error("Failed to rebuild audio engine: \(error)")
        }
    }

    // MARK: - Buffer Scheduling

    /// Schedule a chunk of float32 PCM samples for gapless playback.
    ///
    /// - Parameters:
    ///   - samples: Float32 PCM audio at 48kHz mono (upsampled from Kokoro's 24kHz)
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

        let duration = Double(samples.count) / 48000.0
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
