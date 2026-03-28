// AVAudioPlayer delegate for playback completion and WAV cleanup
import AVFoundation
import Foundation
import Logging

/// Handles AVAudioPlayer completion: cleans up WAV file and calls completion closure.
///
/// Uses @MainActor (replacing the previous unchecked-Sendable pattern) because AVAudioPlayerDelegate
/// callbacks fire on the main thread. Extracted from TTSEngine (D-06).
///
/// Properties are `nonisolated(unsafe)` because they are set once in init and
/// never mutated -- this is safe for the delegate callback pattern where
/// AVFoundation calls back on the main thread.
@MainActor
public final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    nonisolated(unsafe) private let wavPath: String
    nonisolated(unsafe) private let completion: (() -> Void)?
    nonisolated(unsafe) private let logger: Logger

    nonisolated init(wavPath: String, completion: (() -> Void)?, logger: Logger) {
        self.wavPath = wavPath
        self.completion = completion
        self.logger = logger
    }

    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        logger.info("AVAudioPlayer finished (success: \(flag)), cleaning up WAV: \(wavPath)")
        try? FileManager.default.removeItem(atPath: wavPath)
        completion?()
    }

    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        logger.error("AVAudioPlayer decode error: \(error?.localizedDescription ?? "unknown")")
        try? FileManager.default.removeItem(atPath: wavPath)
        completion?()
    }
}
