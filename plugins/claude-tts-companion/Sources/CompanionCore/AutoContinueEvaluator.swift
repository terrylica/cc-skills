import Foundation
import Logging

/// Evaluates completed Claude Code session transcripts via MiniMax to decide the next action.
///
/// Full legacy evaluation engine ported from TypeScript auto-continue.ts.
/// Delegates to extracted modules:
/// - `AutoContinueTypes` -- ContinueDecision, AutoContinueState, EvaluationResult
/// - `AutoContinuePrompts` -- SYSTEM_PROMPT, SWEEP_PROMPT
/// - `AutoContinueParser` -- Decision parsing from MiniMax responses
/// - `AutoContinuePlanDiscovery` -- Plan file discovery, transcript building, tool breakdown
/// - `AutoContinueFormatter` -- Telegram message formatting
public final class AutoContinueEvaluator: @unchecked Sendable {

    private let logger = Logger(label: "auto-continue")
    private let client: MiniMaxClient

    // MARK: - Constants

    /// Maximum iterations per auto-continue streak (resets on manual intervention)
    static let MAX_ITERATIONS: Int = {
        if let env = ProcessInfo.processInfo.environment["AUTO_CONTINUE_MAX_ITERATIONS"],
           let val = Int(env) { return val }
        return 10
    }()

    /// Maximum runtime in minutes before auto-stop
    static let MAX_RUNTIME_MIN: Int = {
        if let env = ProcessInfo.processInfo.environment["AUTO_CONTINUE_MAX_RUNTIME_MIN"],
           let val = Int(env) { return val }
        return 180
    }()

    /// Character budget for transcript text sent to MiniMax
    static let TRANSCRIPT_BUDGET: Int = {
        if let env = ProcessInfo.processInfo.environment["AUTO_CONTINUE_TRANSCRIPT_BUDGET"],
           let val = Int(env) { return val }
        return 102400
    }()

    /// Window (ms) to detect auto-continuation vs manual intervention
    static let AUTO_CONTINUE_WINDOW_MS: Double = 5 * 60 * 1000

    /// Absolute cap on total iterations across all streaks
    static var ABSOLUTE_MAX: Int { MAX_ITERATIONS * 3 }

    /// Directory for per-session state files
    static let STATE_DIR: String = {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/terryli"
        return "\(home)/.claude/hooks/state"
    }()

    // MARK: - Prompt Aliases

    /// System prompt for MiniMax evaluation (EVAL-01).
    static var SYSTEM_PROMPT: String { AutoContinuePrompts.SYSTEM_PROMPT }

    /// 5-step sweep pipeline prompt (EVAL-03).
    static var SWEEP_PROMPT: String { AutoContinuePrompts.SWEEP_PROMPT }

    /// Create an evaluator that shares a MiniMax client with other subsystems.
    ///
    /// - Parameter client: The shared MiniMaxClient instance (same circuit breaker as SummaryEngine)
    init(client: MiniMaxClient) {
        self.client = client
    }

    // MARK: - State Management (EVAL-04)

    /// Path to the state file for a given session.
    static func stateFilePath(sessionId: String) -> String {
        return "\(STATE_DIR)/auto-continue-\(sessionId).json"
    }

    /// Load persisted state for a session, resetting on corruption.
    func loadState(sessionId: String) -> AutoContinueState {
        let path = Self.stateFilePath(sessionId: sessionId)
        let fm = FileManager.default

        guard fm.fileExists(atPath: path),
              let data = fm.contents(atPath: path) else {
            return .fresh()
        }

        do {
            var parsed = try JSONDecoder().decode(AutoContinueState.self, from: data)
            if parsed.totalIterations == 0 && parsed.iteration > 0 {
                parsed.totalIterations = parsed.iteration
            }
            return parsed
        } catch {
            logger.warning("State file corrupted for \(sessionId), resetting: \(error)")
            return .fresh()
        }
    }

    /// Persist state to disk, creating STATE_DIR if needed.
    func saveState(sessionId: String, state: AutoContinueState) {
        let fm = FileManager.default
        let dir = Self.STATE_DIR

        do {
            if !fm.fileExists(atPath: dir) {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            let path = Self.stateFilePath(sessionId: sessionId)
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            logger.error("Failed to save state for \(sessionId): \(error)")
        }
    }

    // MARK: - MiniMax Evaluation

    /// Call MiniMax to evaluate the session transcript.
    private func evaluateCompletion(
        transcript: String,
        planContent: String,
        sweepInProgress: Bool
    ) async throws -> (decision: ContinueDecision, reason: String) {
        let hasPlan = !planContent.isEmpty
            && planContent.trimmingCharacters(in: .whitespacesAndNewlines) != "NO_PLAN"

        let truncatedPlan: String? = hasPlan
            ? (planContent.count > 15000
                ? String(planContent.prefix(15000)) + "\n[plan truncated]"
                : planContent)
            : nil

        let planSection: String
        if let plan = truncatedPlan {
            planSection = "## Plan (authoritative task list)\n\"\"\"\n\(plan)\n\"\"\"\n\n"
        } else {
            planSection = "## Plan\nNO PLAN FILE. Infer deliverables from the user's messages in the transcript below. Look for numbered lists, checkboxes, \"Output:\" sections, multi-step prompts, or explicit multi-deliverable requests.\n\n"
        }

        let sweepSection: String
        if sweepInProgress {
            sweepSection = "## IMPORTANT: Sweep In Progress\nA 5-step sweep pipeline was injected earlier in this session. The sweep has multiple steps (blind spot analysis, plan audit, FOSS discovery, execute remaining work, reconcile). Unless ALL 5 steps are clearly completed in the transcript, return CONTINUE with instructions for the next incomplete step. A sweep in progress almost always means CONTINUE.\n\n"
        } else {
            sweepSection = ""
        }

        let prompt = """
            \(planSection)\(sweepSection)## Session Transcript
            \"\"\"
            \(transcript)
            \"\"\"

            Evaluate the session. What is the best next action?
            """

        let result = try await client.query(
            prompt: prompt,
            systemPrompt: Self.SYSTEM_PROMPT,
            maxTokens: 2048
        )

        return AutoContinueParser.parseDecision(result.text)
    }

    // MARK: - Main Evaluation (EVAL-01 through EVAL-06)

    /// Full evaluation pipeline matching legacy TypeScript `main()`.
    ///
    /// 1. Load state, detect auto-continuation vs manual intervention
    /// 2. Check safety limits (absolute cap, per-streak, runtime, sweep_done)
    /// 3. Parse transcript, discover plan, build transcript text
    /// 4. Handle 0-turn session with un-swept sibling plan
    /// 5. Call MiniMax evaluation
    /// 6. Apply deterministic sweep fallback
    /// 7. Update state and return result
    func evaluate(
        sessionId: String,
        transcriptPath: String,
        cwd: String
    ) async -> EvaluationResult {
        // Load state
        var state = loadState(sessionId: sessionId)

        // Detect auto-continuation vs manual intervention
        let isAutoContinuation: Bool
        if let lastBlocked = state.lastBlockedAt {
            let nowMs = Date().timeIntervalSince1970 * 1000
            isAutoContinuation = (nowMs - lastBlocked) < Self.AUTO_CONTINUE_WINDOW_MS
        } else {
            isAutoContinuation = false
        }

        if isAutoContinuation {
            logger.info("Auto-continue continuation (iteration=\(state.iteration), total=\(state.totalIterations))")
        } else {
            if state.iteration > 0 {
                logger.info("Manual intervention detected (iteration=\(state.iteration)->0), resetting streak (total=\(state.totalIterations), sweep_injected=\(state.sweepInjected), sweep_done=\(state.sweepDone))")
            }
            state.iteration = 0
            state.sweepNotified = false
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            state.startedAt = formatter.string(from: Date())
            state.lastBlockedAt = nil
            saveState(sessionId: sessionId, state: state)
        }

        let elapsedMin = (Date().timeIntervalSince1970 - AutoContinueFormatter.isoToEpoch(state.startedAt)) / 60.0

        // Safety limit checks
        if let earlyExit = checkSafetyLimits(sessionId: sessionId, state: &state, elapsedMin: elapsedMin) {
            return earlyExit
        }

        // Parse transcript and discover plan
        let entries = TranscriptParser.parse(filePath: transcriptPath)
        let turns = TranscriptParser.entriesToTurns(entries)
        let turnCount = turns.count

        let planPath = AutoContinuePlanDiscovery.discoverPlanFromTranscript(
            transcriptPath: transcriptPath,
            loadState: { self.loadState(sessionId: $0) },
            stateFilePath: { Self.stateFilePath(sessionId: $0) }
        )
        let planContent: String
        if let pp = planPath {
            if let data = FileManager.default.contents(atPath: pp),
               let text = String(data: data, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                planContent = text
            } else {
                logger.warning("Failed to read plan file: \(pp), continuing without plan")
                planContent = "NO_PLAN"
            }
        } else {
            logger.info("No plan file found \u{2014} MiniMax will infer deliverables from transcript")
            planContent = "NO_PLAN"
        }

        let (toolCalls, toolBreakdown) = AutoContinuePlanDiscovery.buildToolBreakdown(turns: turns)

        // Handle 0-turn session with un-swept sibling plan
        if turnCount == 0 {
            return handleZeroTurnSession(
                sessionId: sessionId, state: &state, planPath: planPath,
                planContent: planContent, elapsedMin: elapsedMin
            )
        }

        let transcript = AutoContinuePlanDiscovery.buildTranscriptText(turns: turns, budget: Self.TRANSCRIPT_BUDGET)

        // MiniMax evaluation
        let evalDecision: ContinueDecision
        let evalReason: String
        do {
            let sweepInProgress = state.sweepInjected && !state.sweepDone
            let result = try await evaluateCompletion(
                transcript: transcript, planContent: planContent, sweepInProgress: sweepInProgress
            )
            evalDecision = result.decision
            evalReason = result.reason
            logger.info("MiniMax decision: \(result.decision.rawValue) (iteration=\(state.iteration), turns=\(turnCount))")
        } catch {
            logger.error("MiniMax evaluation failed: \(error)")
            return EvaluationResult(
                decision: .done, reason: "MiniMax failed: \(String(describing: error).prefix(100))",
                shouldBlock: false, blockReason: nil, state: state,
                planPath: planPath, planContent: planContent, turnCount: turnCount,
                toolCalls: toolCalls, toolBreakdown: toolBreakdown, errors: 0,
                gitBranch: nil, elapsedMin: elapsedMin
            )
        }

        // Apply deterministic sweep fallback
        var effectiveDecision = evalDecision
        var effectiveReason = evalReason
        if effectiveDecision == .done
            && AutoContinuePlanDiscovery.detectSweepNeeded(planContent: planContent)
            && !state.sweepInjected {
            effectiveDecision = .sweep
            effectiveReason = "Deterministic sweep: all checkboxes done, no review section"
        }

        // Act on decision and update state
        let (shouldBlock, blockReason) = applyDecision(
            effectiveDecision, reason: effectiveReason, sessionId: sessionId, state: &state
        )

        return EvaluationResult(
            decision: effectiveDecision, reason: effectiveReason,
            shouldBlock: shouldBlock, blockReason: blockReason, state: state,
            planPath: planPath, planContent: planContent, turnCount: turnCount,
            toolCalls: toolCalls, toolBreakdown: toolBreakdown, errors: 0,
            gitBranch: nil, elapsedMin: elapsedMin
        )
    }

    // MARK: - Evaluation Helpers

    /// Check safety limits and return an early-exit result if any are hit.
    private func checkSafetyLimits(
        sessionId: String, state: inout AutoContinueState, elapsedMin: Double
    ) -> EvaluationResult? {
        if state.totalIterations >= Self.ABSOLUTE_MAX {
            logger.info("Absolute iteration cap (\(Self.ABSOLUTE_MAX)) reached for \(sessionId)")
            return EvaluationResult(
                decision: .done, reason: "Absolute iteration cap (\(Self.ABSOLUTE_MAX)) reached",
                shouldBlock: false, blockReason: nil, state: state,
                planPath: nil, planContent: nil, turnCount: 0,
                toolCalls: 0, toolBreakdown: "", errors: 0,
                gitBranch: nil, elapsedMin: elapsedMin
            )
        }

        if state.iteration >= Self.MAX_ITERATIONS {
            logger.info("Max iterations (\(Self.MAX_ITERATIONS)) reached for \(sessionId)")
            return EvaluationResult(
                decision: .done, reason: "Max iterations (\(Self.MAX_ITERATIONS)) reached",
                shouldBlock: false, blockReason: nil, state: state,
                planPath: nil, planContent: nil, turnCount: 0,
                toolCalls: 0, toolBreakdown: "", errors: 0,
                gitBranch: nil, elapsedMin: elapsedMin
            )
        }

        if state.iteration > 0 && elapsedMin >= Double(Self.MAX_RUNTIME_MIN) {
            logger.info("Max runtime (\(Self.MAX_RUNTIME_MIN)min) reached for \(sessionId)")
            return EvaluationResult(
                decision: .done, reason: "Max runtime (\(Self.MAX_RUNTIME_MIN)min) reached",
                shouldBlock: false, blockReason: nil, state: state,
                planPath: nil, planContent: nil, turnCount: 0,
                toolCalls: 0, toolBreakdown: "", errors: 0,
                gitBranch: nil, elapsedMin: elapsedMin
            )
        }

        if state.sweepDone {
            logger.info("sweep_done=true for \(sessionId.prefix(8)), allowing stop")
            if !state.sweepNotified {
                state.sweepNotified = true
                saveState(sessionId: sessionId, state: state)
            }
            return EvaluationResult(
                decision: .done, reason: "Sweep complete \u{2014} session finished",
                shouldBlock: false, blockReason: nil, state: state,
                planPath: nil, planContent: nil, turnCount: 0,
                toolCalls: 0, toolBreakdown: "", errors: 0,
                gitBranch: nil, elapsedMin: elapsedMin
            )
        }

        return nil
    }

    /// Handle a 0-turn session, potentially injecting a sweep for an un-swept sibling plan.
    private func handleZeroTurnSession(
        sessionId: String, state: inout AutoContinueState,
        planPath: String?, planContent: String, elapsedMin: Double
    ) -> EvaluationResult {
        if planPath != nil && planContent != "NO_PLAN" && !state.sweepInjected {
            logger.info("0-turn session with un-swept sibling plan \u{2014} injecting sweep")
            state.sweepInjected = true
            state.totalIterations += 1
            state.lastBlockedAt = Date().timeIntervalSince1970 * 1000
            saveState(sessionId: sessionId, state: state)
            return EvaluationResult(
                decision: .sweep,
                reason: "Sibling session implemented plan but sweep never fired \u{2014} injecting final audit",
                shouldBlock: true, blockReason: Self.SWEEP_PROMPT, state: state,
                planPath: planPath, planContent: planContent, turnCount: 0,
                toolCalls: 0, toolBreakdown: "", errors: 0,
                gitBranch: nil, elapsedMin: 0
            )
        }
        logger.info("No turns found in transcript")
        return EvaluationResult(
            decision: .done, reason: "No turns in transcript",
            shouldBlock: false, blockReason: nil, state: state,
            planPath: planPath, planContent: planContent, turnCount: 0,
            toolCalls: 0, toolBreakdown: "", errors: 0,
            gitBranch: nil, elapsedMin: elapsedMin
        )
    }

    /// Apply a decision to state and return (shouldBlock, blockReason).
    private func applyDecision(
        _ decision: ContinueDecision, reason: String,
        sessionId: String, state: inout AutoContinueState
    ) -> (shouldBlock: Bool, blockReason: String?) {
        switch decision {
        case .continue, .redirect:
            state.iteration += 1
            state.totalIterations += 1
            state.lastBlockedAt = Date().timeIntervalSince1970 * 1000
            saveState(sessionId: sessionId, state: state)
            return (true, reason.isEmpty ? "MiniMax returned CONTINUE without specific instructions — session will resume its current task" : reason)
        case .sweep:
            state.sweepInjected = true
            state.iteration += 1
            state.totalIterations += 1
            state.lastBlockedAt = Date().timeIntervalSince1970 * 1000
            saveState(sessionId: sessionId, state: state)
            return (true, Self.SWEEP_PROMPT)
        case .done:
            if state.sweepInjected {
                state.sweepDone = true
                saveState(sessionId: sessionId, state: state)
            }
            return (false, nil)
        }
    }

    // MARK: - Formatting Delegates

    /// Format a rich decision notification for Telegram (EVAL-05).
    func formatDecisionMessage(
        result: EvaluationResult, sessionId: String, cwd: String,
        maxIterations: Int, maxRuntimeMin: Double
    ) -> String {
        AutoContinueFormatter.formatDecisionMessage(
            result: result, sessionId: sessionId, cwd: cwd,
            maxIterations: maxIterations, maxRuntimeMin: maxRuntimeMin
        )
    }

    /// Format a lightweight exit notification for early stops (EVAL-05).
    func formatExitMessage(
        reason: String, sessionId: String, cwd: String,
        state: AutoContinueState?, maxIterations: Int, maxRuntimeMin: Double
    ) -> String {
        AutoContinueFormatter.formatExitMessage(
            reason: reason, sessionId: sessionId, cwd: cwd,
            state: state, maxIterations: maxIterations, maxRuntimeMin: maxRuntimeMin
        )
    }

    // MARK: - Legacy Static API Compatibility

    /// Count checked and total checkboxes in plan content.
    static func checkboxCounts(_ planContent: String) -> (checked: Int, total: Int) {
        AutoContinueFormatter.checkboxCounts(planContent)
    }

    /// Build a progress bar string (filled blocks + empty blocks).
    static func progressBar(done: Int, total: Int, width: Int = 10) -> String {
        AutoContinueFormatter.progressBar(done: done, total: total, width: width)
    }

    /// Extract the first `# Title` line from plan content.
    static func extractPlanTitle(_ planContent: String) -> String {
        AutoContinueFormatter.extractPlanTitle(planContent)
    }
}
