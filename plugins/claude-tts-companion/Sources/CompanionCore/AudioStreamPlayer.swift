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

    /// Standard format for all TTS audio: 48kHz mono float32.
    private let format: AVAudioFormat

    /// Duration of the silent lead-in buffer scheduled in reset().
    /// Callers polling currentTime must subtract this to get content-relative time.
    static let leadInDuration: TimeInterval = 480.0 / 48000.0  // 10ms

    /// Whether the engine is currently running.
    private(set) var isRunning: Bool = false

    /// App Nap prevention token. Held while audio buffers are scheduled to prevent
    /// macOS from throttling this .accessory process and starving the audio render thread.
    private var appNapActivity: NSObjectProtocol?

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

    /// Periodic health check timer comparing engine device vs system default.
    private var healthCheckTimer: DispatchSourceTimer?

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

        // Pin output to actual hardware device, bypassing virtual audio devices
        // (e.g., Background Music) that add an extra IOProc hop causing jitter.
        let hwDevice = resolveHardwareOutputDevice()
        setOutputDevice(hwDevice)
        setBufferSize(hwDevice, frames: 2048)  // ~42ms at 48kHz — resilient to CPU spikes

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

        // Start periodic health check (safety net for missed device changes)
        startHealthCheck()

        // Cache the resolved hardware device ID (not the virtual default)
        cachedOutputDeviceID = hwDevice
        let initialDeviceName = getDeviceName(deviceID: cachedOutputDeviceID)
        logger.info("AudioStreamPlayer created (48kHz mono float32, AVAudioEngine, device: \(initialDeviceName) [\(cachedOutputDeviceID)])")
    }

    deinit {
        stopHealthCheck()
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
            engine.prepare()
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
        if let activity = appNapActivity {
            ProcessInfo.processInfo.endActivity(activity)
            appNapActivity = nil
        }

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
        if let activity = appNapActivity {
            ProcessInfo.processInfo.endActivity(activity)
            appNapActivity = nil
        }

        // Ensure engine is running (start is idempotent internally)
        if !isRunning {
            do {
                engine.prepare()
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

    // MARK: - Health Check (Layer 3)

    /// Start periodic health check comparing engine device vs system default.
    /// Safety net: catches stale device if HAL listener and config notification both miss a change.
    func startHealthCheck() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + Config.audioHealthCheckInterval,
            repeating: Config.audioHealthCheckInterval
        )
        timer.setEventHandler { [weak self] in
            self?.performHealthCheck()
        }
        timer.resume()
        healthCheckTimer = timer
        logger.info("Audio health check started (interval: \(Int(Config.audioHealthCheckInterval))s)")
    }

    /// Stop the periodic health check timer.
    func stopHealthCheck() {
        healthCheckTimer?.cancel()
        healthCheckTimer = nil
        logger.info("Audio health check stopped")
    }

    /// Compare engine's cached device against system default. Trigger rebuild on mismatch.
    /// Skips during active playback -- audio is clearly working if playing.
    private func performHealthCheck() {
        // Skip during active playback -- audio is working if playing
        guard !playerNode.isPlaying else { return }

        let systemDevice = resolveHardwareOutputDevice()
        let engineDevice = cachedOutputDeviceID

        if systemDevice != engineDevice && systemDevice != AudioDeviceID(kAudioDeviceUnknown) {
            let systemName = getDeviceName(deviceID: systemDevice)
            let engineName = getDeviceName(deviceID: engineDevice)
            logger.warning("Health check: device mismatch (engine=\(engineDevice) '\(engineName)', system=\(systemDevice) '\(systemName)')")
            triggerRebuild(source: .healthCheck)
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

    /// Get the transport type of an audio device.
    private func getTransportType(deviceID: AudioDeviceID) -> UInt32 {
        var transportType: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, &transportType)
        return transportType
    }

    /// Check if a device has output channels.
    private func hasOutputChannels(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propertySize)
        guard status == noErr, propertySize > 0 else { return false }
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(propertySize))
        defer { bufferList.deallocate() }
        let status2 = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, bufferList)
        guard status2 == noErr else { return false }
        let count = Int(bufferList.pointee.mNumberBuffers)
        return count > 0 && bufferList.pointee.mBuffers.mNumberChannels > 0
    }

    /// Find the preferred hardware output device, bypassing virtual audio devices
    /// (e.g., Background Music, Loopback) that add an extra IOProc hop causing jitter.
    /// Falls back to the system default if no hardware device is found.
    func resolveHardwareOutputDevice() -> AudioDeviceID {
        let systemDefault = getSystemDefaultOutputDeviceID()
        let transportType = getTransportType(deviceID: systemDefault)

        // If the default device is already hardware (built-in, USB, Bluetooth, etc.), use it directly.
        // kAudioDeviceTransportTypeVirtual = 'virt' = 0x76697274
        if transportType != kAudioDeviceTransportTypeVirtual {
            return systemDefault
        }

        // Default is virtual — enumerate all devices and find first non-virtual output device.
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize)
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        guard deviceCount > 0 else { return systemDefault }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &deviceIDs)

        // Prefer built-in output, then any non-virtual output
        var fallbackHardware: AudioDeviceID?
        for id in deviceIDs {
            let tt = getTransportType(deviceID: id)
            guard tt != kAudioDeviceTransportTypeVirtual else { continue }
            guard hasOutputChannels(deviceID: id) else { continue }
            if tt == kAudioDeviceTransportTypeBuiltIn {
                let name = getDeviceName(deviceID: id)
                logger.info("Resolved hardware device: \(name) [\(id)] (built-in, bypassing virtual default)")
                return id
            }
            if fallbackHardware == nil {
                fallbackHardware = id
            }
        }

        if let hw = fallbackHardware {
            let name = getDeviceName(deviceID: hw)
            logger.info("Resolved hardware device: \(name) [\(hw)] (non-virtual, bypassing virtual default)")
            return hw
        }

        logger.warning("No hardware output device found, using virtual default")
        return systemDefault
    }

    /// Pin the engine's output audio unit to a specific device.
    /// Bypasses the system default routing (and any virtual device in the chain).
    private func setOutputDevice(_ deviceID: AudioDeviceID) {
        guard let outputUnit = engine.outputNode.audioUnit else {
            logger.warning("Cannot set output device: outputNode has no audioUnit")
            return
        }
        var mutableID = deviceID
        let status = AudioUnitSetProperty(
            outputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status == noErr {
            let name = getDeviceName(deviceID: deviceID)
            logger.info("Pinned engine output to \(name) [\(deviceID)]")
        } else {
            logger.error("Failed to set output device \(deviceID): OSStatus \(status)")
        }
    }

    /// Set the I/O buffer size on a hardware device.
    /// Larger buffers give the real-time audio thread more headroom to survive
    /// CPU spikes (e.g., Rust compilation). Default is typically 512 frames (~10ms).
    /// 2048 frames (~42ms at 48kHz) adds negligible latency for TTS but greatly
    /// reduces sensitivity to scheduling jitter from CPU contention.
    private func setBufferSize(_ deviceID: AudioDeviceID, frames: UInt32) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = frames
        let status = AudioObjectSetPropertyData(
            deviceID, &address, 0, nil,
            UInt32(MemoryLayout<UInt32>.size), &size
        )
        if status == noErr {
            logger.info("Set I/O buffer size to \(frames) frames (\(String(format: "%.1f", Double(frames) / 48000.0 * 1000))ms at 48kHz)")
        } else {
            // Device may clamp to nearest supported size — read back actual value
            var actual: UInt32 = 0
            var propSize = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propSize, &actual)
            logger.warning("Buffer size request \(frames) -> actual \(actual) (OSStatus \(status))")
        }
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
    /// a new one after the debounce window. Enforces cooldown between rebuilds unless
    /// the system device has actually changed (Bluetooth switches trigger intermediate hops).
    func triggerRebuild(source: RebuildSource) {
        logger.info("Rebuild triggered by \(source.rawValue)")

        // Cancel pending debounce
        rebuildWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            let systemDevice = self.getSystemDefaultOutputDeviceID()
            let deviceActuallyChanged = systemDevice != self.cachedOutputDeviceID
                && systemDevice != AudioDeviceID(kAudioDeviceUnknown)

            // Cooldown check — bypass if system device differs from engine device
            // (Bluetooth switches route briefly through built-in speakers first)
            let now = CFAbsoluteTimeGetCurrent()
            if !deviceActuallyChanged && now - self.lastRebuildTime < Config.audioRebuildCooldownSeconds {
                let remaining = Config.audioRebuildCooldownSeconds - (now - self.lastRebuildTime)
                self.logger.info("Rebuild skipped (cooldown active, \(String(format: "%.1f", remaining))s remaining, device unchanged)")
                return
            }

            if !deviceActuallyChanged {
                let deviceName = self.getDeviceName(deviceID: systemDevice)
                self.logger.info("Rebuild skipped (device unchanged: \(deviceName) [\(systemDevice)])")
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

        // Re-pin to hardware device (may have changed after route change)
        let hwDevice = resolveHardwareOutputDevice()
        setOutputDevice(hwDevice)
        setBufferSize(hwDevice, frames: 2048)
        engine.prepare()

        // 4. Start
        do {
            try engine.start()
            isRunning = true
            cachedOutputDeviceID = hwDevice
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
        let wasEmpty = scheduledBufferCount == 0
        scheduledBufferCount += 1
        bufferCountLock.unlock()

        // Prevent App Nap while audio is playing. macOS throttles .accessory processes
        // that appear idle, which starves the real-time audio render thread causing jitter.
        if wasEmpty && appNapActivity == nil {
            appNapActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical],
                reason: "TTS audio playback in progress"
            )
        }

        // Schedule the buffer with .dataPlayedBack completion type.
        // This fires when the audio data has actually been rendered to hardware,
        // not just when it was consumed from the queue.
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self = self else {
                onComplete?()
                return
            }
            self.bufferCountLock.lock()
            self.scheduledBufferCount -= 1
            let nowEmpty = self.scheduledBufferCount == 0
            self.bufferCountLock.unlock()
            if nowEmpty, let activity = self.appNapActivity {
                ProcessInfo.processInfo.endActivity(activity)
                self.appNapActivity = nil
            }
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
