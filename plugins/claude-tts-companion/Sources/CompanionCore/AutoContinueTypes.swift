import Foundation

/// Decision output from evaluating a completed Claude Code session transcript.
///
/// The auto-continue evaluator uses MiniMax to analyze session content and determine
/// what action should follow (EVAL-01).
public enum ContinueDecision: String, Sendable {
    /// Session has more work to do -- resume with the same task
    case `continue` = "CONTINUE"
    /// Run 5-step review pipeline on completed work
    case sweep = "SWEEP"
    /// Switch to a different task mentioned in the conversation
    case redirect = "REDIRECT"
    /// Session is complete, no further action needed
    case done = "DONE"
}

/// Per-session state persisted across stop-hook invocations (EVAL-04).
///
/// State files stored at `~/.claude/hooks/state/auto-continue-{sessionId}.json`.
/// Tracks iteration counts, sweep lifecycle, and manual intervention detection.
public struct AutoContinueState: Codable {
    /// Per-streak counter (resets on manual intervention)
    var iteration: Int
    /// Lifetime counter -- never resets
    var totalIterations: Int
    /// Sweep prompt sent -- MiniMax still evaluates subsequent stops
    var sweepInjected: Bool
    /// MiniMax returned DONE after sweep was injected -- truly finished
    var sweepDone: Bool
    /// Prevents duplicate "Sweep complete" Telegram spam
    var sweepNotified: Bool
    /// ISO 8601 timestamp when this state was created
    var startedAt: String
    /// Epoch seconds when hook last blocked -- distinguishes auto-continue from manual intervention
    var lastBlockedAt: Double?

    // Use snake_case for JSON keys to match legacy TypeScript state files
    enum CodingKeys: String, CodingKey {
        case iteration
        case totalIterations = "total_iterations"
        case sweepInjected = "sweep_injected"
        case sweepDone = "sweep_done"
        case sweepNotified = "sweep_notified"
        case startedAt = "started_at"
        case lastBlockedAt = "last_blocked_at"
    }

    /// Create a fresh default state.
    static func fresh() -> AutoContinueState {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return AutoContinueState(
            iteration: 0,
            totalIterations: 0,
            sweepInjected: false,
            sweepDone: false,
            sweepNotified: false,
            startedAt: formatter.string(from: Date()),
            lastBlockedAt: nil
        )
    }
}

/// Result of the full auto-continue evaluation pipeline.
public struct EvaluationResult {
    let decision: ContinueDecision
    let reason: String
    /// true = blockStop, false = allowStop
    let shouldBlock: Bool
    /// The text to inject (reason for CONTINUE/REDIRECT, SWEEP_PROMPT for SWEEP)
    let blockReason: String?
    /// Current state after evaluation
    let state: AutoContinueState
    let planPath: String?
    let planContent: String?
    let turnCount: Int
    let toolCalls: Int
    let toolBreakdown: String
    let errors: Int
    let gitBranch: String?
    let elapsedMin: Double
}
