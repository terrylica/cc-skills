import Foundation
import Logging

/// Tracks consecutive API failures and blocks calls during a cooldown period.
///
/// Thread-safe via NSLock (matching TTSEngine pattern).
/// Opens after `maxFailures` consecutive failures, auto-resets after `cooldownSeconds`.
public final class CircuitBreaker: @unchecked Sendable {

    private let logger = Logger(label: "circuit-breaker")
    private let lock = NSLock()

    /// Number of consecutive failures before opening the circuit
    let maxFailures: Int

    /// Duration in seconds to keep the circuit open before allowing retries
    let cooldownSeconds: TimeInterval

    private var consecutiveFailures: Int = 0
    private var disabledUntil: Date = .distantPast

    init(maxFailures: Int = 3, cooldownSeconds: TimeInterval = 300) {
        self.maxFailures = maxFailures
        self.cooldownSeconds = cooldownSeconds
    }

    /// Whether the circuit breaker is open (blocking calls).
    ///
    /// Returns `true` if currently in cooldown. If cooldown has expired,
    /// resets state and returns `false` (half-open -> closed).
    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }

        guard Date() < disabledUntil else {
            // Cooldown expired or was never set -- allow calls
            if consecutiveFailures >= maxFailures {
                logger.info("Circuit breaker cooldown expired, resetting state")
                consecutiveFailures = 0
                disabledUntil = .distantPast
            }
            return false
        }
        return true
    }

    /// Record a failed API call. Opens the circuit after `maxFailures` consecutive failures.
    func recordFailure() {
        lock.lock()
        defer { lock.unlock() }

        consecutiveFailures += 1
        if consecutiveFailures >= maxFailures {
            disabledUntil = Date().addingTimeInterval(cooldownSeconds)
            logger.warning(
                "Circuit breaker OPEN after \(consecutiveFailures) consecutive failures, disabled for \(Int(cooldownSeconds))s"
            )
        } else {
            logger.info("Failure recorded (\(consecutiveFailures)/\(maxFailures))")
        }
    }

    /// Record a successful API call, resetting the failure counter.
    func recordSuccess() {
        lock.lock()
        defer { lock.unlock() }

        if consecutiveFailures > 0 {
            logger.info("Success recorded, resetting failure count from \(consecutiveFailures)")
        }
        consecutiveFailures = 0
    }

    /// Current number of consecutive failures (read-only, for status/testing).
    var failureCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return consecutiveFailures
    }
}

// MARK: - Summary Errors

/// Errors related to AI summary generation via MiniMax API.
public enum SummaryError: Error, CustomStringConvertible {
    /// Circuit breaker is open -- too many consecutive failures
    case circuitBreakerOpen
    /// MINIMAX_API_KEY environment variable not configured
    case missingAPIKey
    /// MiniMax API returned a non-200 status code
    case apiError(statusCode: Int, body: String)
    /// MiniMax API returned no text content blocks
    case emptyResponse
    /// Failed to parse the MiniMax API response JSON
    case decodingError(String)

    public var description: String {
        switch self {
        case .circuitBreakerOpen:
            return "Summary API disabled: circuit breaker open (cooldown active)"
        case .missingAPIKey:
            return "MINIMAX_API_KEY environment variable not set"
        case .apiError(let statusCode, let body):
            return "MiniMax API error \(statusCode): \(body)"
        case .emptyResponse:
            return "MiniMax API returned empty text content"
        case .decodingError(let detail):
            return "Failed to decode MiniMax response: \(detail)"
        }
    }
}
