// PlaybackManager: @MainActor class owning all audio playback lifecycle.
//
// Extracted from TTSEngine (D-01, D-09) to separate playback concerns
// from synthesis. Owns AVAudioPlayer lifecycle, pre-buffering, warm-up,
// and the AudioStreamPlayer for gapless streaming playback.
import AVFoundation
import Foundation
import Logging

/// Manages all audio playback: AVAudioPlayer for single-shot, AudioStreamPlayer for streaming.
///
/// @MainActor because AVAudioPlayer delegate callbacks fire on the main thread,
/// and SubtitleSyncDriver (also @MainActor) needs synchronous access to audioStreamPlayer.
///
/// Created by CompanionApp, passed to TTSEngine and SubtitleSyncDriver.
@MainActor
public final class PlaybackManager {

    private let logger = Logger(label: "playback-manager")

    /// Whether the CoreAudio hardware has been warmed up by playing silence
    private var audioHardwareWarmed = false

    /// Timestamp of last successful audio playback start (for re-warm after idle)
    private var lastPlaybackTime: CFAbsoluteTime = 0

    /// If audio has been idle longer than this, re-warm before playing (seconds)
    private static let audioIdleThreshold: CFAbsoluteTime = 30.0

    /// Retained warm-up player to prevent ARC deallocation before playback completes.
    private var warmUpPlayer: AVAudioPlayer?

    /// Currently playing AVAudioPlayer instance (for cancellation and currentTime polling)
    private var audioPlayer: AVAudioPlayer?

    /// Delegate that handles playback completion and WAV cleanup
    private var playbackDelegate: PlaybackDelegate?

    /// Gapless streaming audio player using AVAudioEngine + AVAudioPlayerNode.
    /// Shared across streaming sessions -- reset() between sessions, never deallocated.
    public let audioStreamPlayer = AudioStreamPlayer()

    // MARK: - Lifecycle

    init() {
        // Pre-warm CoreAudio hardware so the first real play() doesn't stutter.
        warmUpAudioHardware()

        // Start AVAudioEngine early so hardware stays warm for streaming playback.
        audioStreamPlayer.start()

        logger.info("PlaybackManager created (audio hardware pre-warmed, AudioStreamPlayer started)")
    }

    // MARK: - Public API

    /// Play a WAV file using AVAudioPlayer with prepareToPlay() pre-buffering.
    ///
    /// Returns the AVAudioPlayer instance so callers (SubtitleSyncDriver) can
    /// poll `player.currentTime` for drift-free karaoke sync.
    @discardableResult
    func play(wavPath: String, completion: (() -> Void)? = nil) -> AVAudioPlayer? {
        // Re-warm CoreAudio if idle too long (hardware powers down after ~30s idle)
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastPlaybackTime > PlaybackManager.audioIdleThreshold {
            logger.info("Audio idle >\(Int(PlaybackManager.audioIdleThreshold))s, re-warming CoreAudio hardware")
            warmUpAudioHardware()
        }

        let url = URL(fileURLWithPath: wavPath)
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            let delegate = PlaybackDelegate(wavPath: wavPath, completion: completion, logger: logger)
            self.playbackDelegate = delegate  // prevent dealloc
            player.delegate = delegate
            if !player.prepareToPlay() {
                logger.warning("prepareToPlay() failed for WAV: \(wavPath) -- attempting play() anyway")
            }
            if !player.play() {
                logger.error("play() failed for WAV: \(wavPath)")
                completion?()
                return nil
            }
            self.audioPlayer = player
            self.lastPlaybackTime = now
            logger.info("Playing WAV via AVAudioPlayer: \(wavPath) (duration: \(String(format: "%.2f", player.duration))s)")
            return player
        } catch {
            logger.error("AVAudioPlayer failed: \(error)")
            completion?()
            return nil
        }
    }

    /// Create and prepare an AVAudioPlayer for a WAV file WITHOUT starting playback.
    ///
    /// Used by SubtitleSyncDriver to pre-buffer the next chunk while the current one
    /// is still playing, eliminating ~500ms-1s gaps between streaming chunks.
    /// The caller is responsible for calling play() when ready.
    ///
    /// - Returns: A tuple of (player, delegate) or nil if creation fails.
    ///   The caller MUST retain the delegate to prevent deallocation during playback.
    func preparePlayer(wavPath: String, completion: (() -> Void)? = nil) -> (player: AVAudioPlayer, delegate: PlaybackDelegate)? {
        let url = URL(fileURLWithPath: wavPath)
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            let delegate = PlaybackDelegate(wavPath: wavPath, completion: completion, logger: logger)
            player.delegate = delegate
            if !player.prepareToPlay() {
                logger.warning("prepareToPlay() failed for pre-buffered WAV: \(wavPath)")
            }
            logger.info("Pre-buffered AVAudioPlayer: \(wavPath) (duration: \(String(format: "%.2f", player.duration))s)")
            return (player: player, delegate: delegate)
        } catch {
            logger.error("preparePlayer failed: \(error)")
            return nil
        }
    }

    /// Stop any currently playing audio.
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackDelegate = nil
    }

    // MARK: - Private

    /// Pre-warm CoreAudio hardware by playing a brief silent buffer.
    ///
    /// macOS powers down the audio output subsystem after idle periods. The first
    /// AVAudioPlayer.play() after idle triggers a synchronous hardware re-init that
    /// takes ~50-500ms, causing audible stutter/choppiness at the start of playback.
    ///
    /// Playing a tiny silent WAV (~0.1s at 24kHz) forces CoreAudio to initialize the
    /// output chain, so subsequent real audio plays without stutter.
    private func warmUpAudioHardware() {
        let sampleRate: Double = 24000.0
        let silentSamples = Int(sampleRate * 0.1)  // 0.1s of silence

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(silentSamples)
        ) else {
            logger.warning("Failed to create silent buffer for audio warm-up")
            return
        }

        buffer.frameLength = AVAudioFrameCount(silentSamples)
        // Buffer is already zero-filled (silence)

        let wavPath = NSTemporaryDirectory() + "tts-warmup-\(UUID().uuidString).wav"
        do {
            let url = URL(fileURLWithPath: wavPath)
            let audioFile = try AVAudioFile(
                forWriting: url,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
            try audioFile.write(from: buffer)

            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.0  // Completely silent
            player.prepareToPlay()
            player.play()

            // Retain the player to prevent ARC deallocation before playback completes
            self.warmUpPlayer = player

            // Clean up temp file and release player after a short delay
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [weak self] in
                try? FileManager.default.removeItem(atPath: wavPath)
                DispatchQueue.main.async { self?.warmUpPlayer = nil }
            }

            audioHardwareWarmed = true
            logger.info("CoreAudio hardware pre-warmed with 0.1s silent buffer")
        } catch {
            logger.warning("Audio warm-up failed: \(error) -- first playback may stutter")
            try? FileManager.default.removeItem(atPath: wavPath)
        }
    }
}
