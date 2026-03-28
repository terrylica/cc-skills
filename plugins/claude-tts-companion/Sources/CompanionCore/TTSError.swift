// TTS error types
import Foundation

/// Errors that can occur during TTS synthesis and playback.
public enum TTSError: Error, CustomStringConvertible {
    case modelLoadFailed(path: String)
    case synthesisReturnedNil
    case wavWriteFailed(path: String)
    case circuitBreakerOpen

    public var description: String {
        switch self {
        case .modelLoadFailed(let path):
            return "Failed to load TTS model from \(path)"
        case .synthesisReturnedNil:
            return "KokoroTTS.generateAudio returned nil"
        case .wavWriteFailed(let path):
            return "Failed to write WAV to \(path)"
        case .circuitBreakerOpen:
            return "TTS circuit breaker is open — synthesis temporarily disabled"
        }
    }
}
