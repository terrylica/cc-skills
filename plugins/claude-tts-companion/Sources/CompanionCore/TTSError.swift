// TTS error types
import Foundation

/// Errors that can occur during TTS synthesis and playback.
public enum TTSError: Error, CustomStringConvertible {
    case modelLoadFailed(path: String)
    case synthesisReturnedNil
    case wavWriteFailed(path: String)
    case circuitBreakerOpen
    case pythonServerUnavailable(url: String)
    case pythonServerError(statusCode: Int, message: String)

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
        case .pythonServerUnavailable(let url):
            return "Python TTS server unavailable at \(url)"
        case .pythonServerError(let statusCode, let message):
            return "Python TTS server error (\(statusCode)): \(message)"
        }
    }
}
