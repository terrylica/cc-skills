import Foundation
import Logging

/// Decision output from evaluating a completed Claude Code session transcript.
///
/// The auto-continue evaluator uses MiniMax to analyze session content and determine
/// what action should follow (AUTO-01).
enum ContinueDecision: String, Sendable {
    /// Session has more work to do -- resume with the same task
    case `continue` = "CONTINUE"
    /// Run 5-step review pipeline on completed work
    case sweep = "SWEEP"
    /// Switch to a different task mentioned in the conversation
    case redirect = "REDIRECT"
    /// Session is complete, no further action needed
    case done = "DONE"
}

/// Evaluates completed Claude Code session transcripts via MiniMax to decide the next action.
///
/// Three responsibilities:
/// 1. **Evaluate** -- Ask MiniMax whether a session should CONTINUE, SWEEP, REDIRECT, or DONE (AUTO-01)
/// 2. **Discover plan files** -- Scan transcript text for `.claude/plans/*.md` references (AUTO-02)
/// 3. **Build sweep prompt** -- Generate a 5-step review pipeline prompt for SWEEP mode (AUTO-03)
///
/// Shares a `MiniMaxClient` (and its circuit breaker) with `SummaryEngine` to avoid
/// duplicate failure tracking and connection overhead.
final class AutoContinueEvaluator: @unchecked Sendable {

    private let logger = Logger(label: "auto-continue")
    private let client: MiniMaxClient

    /// Create an evaluator that shares a MiniMax client with other subsystems.
    ///
    /// - Parameter client: The shared MiniMaxClient instance (same circuit breaker as SummaryEngine)
    init(client: MiniMaxClient) {
        self.client = client
    }

    // MARK: - Evaluation (AUTO-01)

    /// Evaluate a session transcript and decide the next action.
    ///
    /// Parses the transcript, extracts the last few exchanges, sends them to MiniMax
    /// with an evaluation prompt, and parses the response into a `ContinueDecision`.
    ///
    /// On any error (API failure, parse failure, empty transcript), defaults to `.done`.
    ///
    /// - Parameter transcriptPath: Absolute path to the session's transcript.jsonl
    /// - Returns: A tuple of (decision, one-sentence reason)
    func evaluate(transcriptPath: String) async -> (decision: ContinueDecision, reason: String) {
        let entries = TranscriptParser.parse(filePath: transcriptPath)

        guard !entries.isEmpty else {
            logger.info("Empty transcript, defaulting to DONE")
            return (.done, "Empty transcript")
        }

        // Extract last 5 prompt/response pairs for evaluation context
        let context = buildEvaluationContext(entries: entries)

        let prompt = """
            Based on this Claude Code session transcript, what should happen next?

            Session context (last exchanges):
            \(context)

            Respond with EXACTLY one of these decision words, followed by a pipe | and a one-sentence reason:

            CONTINUE -- The session was working on a multi-step task and there's clearly more to do
            SWEEP -- The session completed a feature/plan and should run a review sweep
            REDIRECT -- The session should pivot to a different task mentioned in the conversation
            DONE -- The session completed its work and no further action is needed

            Example: SWEEP | The session completed plan 07-01 and should verify the implementation

            Decision:
            """

        let systemPrompt = "You evaluate Claude Code session transcripts and decide the next action. Respond with EXACTLY one decision word (CONTINUE, SWEEP, REDIRECT, DONE) followed by | and a reason."

        do {
            let result = try await client.query(
                prompt: prompt,
                systemPrompt: systemPrompt,
                maxTokens: 256
            )

            let (decision, reason) = parseDecisionResponse(result.text)
            logger.info("Auto-continue decision: \(decision.rawValue) -- \(reason)")
            return (decision, reason)

        } catch {
            logger.error("Auto-continue evaluation failed: \(error)")
            return (.done, "Evaluation error: \(error.localizedDescription)")
        }
    }

    // MARK: - Plan Discovery (AUTO-02)

    /// Discover plan file references in a transcript.
    ///
    /// Scans the raw transcript text for paths matching `.claude/plans/*.md`
    /// and `.planning/phases/*/PLAN.md` patterns. Returns deduplicated matches.
    ///
    /// - Parameter transcriptPath: Absolute path to the session's transcript.jsonl
    /// - Returns: Array of unique plan file path strings found in the transcript
    func discoverPlanFiles(transcriptPath: String) -> [String] {
        guard let data = FileManager.default.contents(atPath: transcriptPath),
              let content = String(data: data, encoding: .utf8) else {
            logger.warning("Could not read transcript for plan discovery: \(transcriptPath)")
            return []
        }

        var discovered: Set<String> = []

        // Match .claude/plans/*.md references
        if let claudePlansRegex = try? NSRegularExpression(
            pattern: "\\.claude/plans/[\\w.-]+\\.md",
            options: []
        ) {
            let range = NSRange(content.startIndex..., in: content)
            let matches = claudePlansRegex.matches(in: content, range: range)
            for match in matches {
                if let swiftRange = Range(match.range, in: content) {
                    discovered.insert(String(content[swiftRange]))
                }
            }
        }

        // Match .planning/phases/*/PLAN.md references
        if let planningRegex = try? NSRegularExpression(
            pattern: "\\.planning/phases/[\\w./-]+PLAN\\.md",
            options: []
        ) {
            let range = NSRange(content.startIndex..., in: content)
            let matches = planningRegex.matches(in: content, range: range)
            for match in matches {
                if let swiftRange = Range(match.range, in: content) {
                    discovered.insert(String(content[swiftRange]))
                }
            }
        }

        let result = Array(discovered).sorted()
        logger.info("Discovered \(result.count) plan file(s) in transcript")
        return result
    }

    // MARK: - Sweep Prompt (AUTO-03)

    /// Build a 5-step review pipeline prompt for SWEEP mode.
    ///
    /// This prompt is NOT sent to MiniMax -- it's the prompt that would be injected
    /// into a CONTINUE/SWEEP auto-resume of Claude Code.
    ///
    /// - Parameter planFiles: Plan file paths discovered from the transcript
    /// - Returns: A multi-step review prompt string
    func buildSweepPrompt(planFiles: [String]) -> String {
        let planCheckStep: String
        if planFiles.isEmpty {
            planCheckStep = "3. PLAN CHECK: No plan files discovered -- skip this step."
        } else {
            let joined = planFiles.joined(separator: ", ")
            planCheckStep = "3. PLAN CHECK: Compare implementation against plan requirements: \(joined). List any gaps."
        }

        return """
            Run this 5-step review pipeline:

            1. VERIFY: Run the build and any existing tests. Report pass/fail.
            2. DIFF AUDIT: Review all changes made in this session. Flag any TODOs, debug code, or hardcoded values.
            \(planCheckStep)
            4. INTEGRATION: Check that new code integrates correctly with existing modules (imports resolve, types match).
            5. SUMMARY: Write a brief summary of what was accomplished and any remaining work.

            Report each step's result clearly.
            """
    }

    // MARK: - Private

    /// Build evaluation context from the last few transcript entries.
    ///
    /// Extracts up to the last 5 prompt/response pairs, truncating each to 3000 chars.
    private func buildEvaluationContext(entries: [TranscriptEntry]) -> String {
        // Collect prompt/response pairs
        var pairs: [(prompt: String, response: String)] = []
        var currentPrompt: String?

        for entry in entries {
            switch entry {
            case .prompt(let text, _):
                currentPrompt = text
            case .response(let text, _):
                if let p = currentPrompt {
                    pairs.append((prompt: p, response: text))
                    currentPrompt = nil
                }
            default:
                break
            }
        }

        // Take last 5 pairs
        let recentPairs = pairs.suffix(5)
        var context = ""

        for (i, pair) in recentPairs.enumerated() {
            let truncatedPrompt = pair.prompt.count > 3000
                ? String(pair.prompt.prefix(3000)) + " [truncated]"
                : pair.prompt
            let truncatedResponse = pair.response.count > 3000
                ? String(pair.response.prefix(3000)) + " [truncated]"
                : pair.response

            context += "--- Exchange \(i + 1) ---\n"
            context += "User: \(truncatedPrompt)\n"
            context += "Assistant: \(truncatedResponse)\n\n"
        }

        return context
    }

    /// Parse a MiniMax response into a decision and reason.
    ///
    /// Expected format: `DECISION | reason text`
    /// Falls back to `.done` if the response can't be parsed.
    private func parseDecisionResponse(_ text: String) -> (ContinueDecision, String) {
        let parts = text.components(separatedBy: "|")
        let decisionWord = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let reason = parts.count >= 2
            ? parts[1...].joined(separator: "|").trimmingCharacters(in: .whitespacesAndNewlines)
            : "No reason provided"

        if let decision = ContinueDecision(rawValue: decisionWord) {
            return (decision, reason)
        }

        // Try to find a known decision word anywhere in the first part
        for candidate in ["CONTINUE", "SWEEP", "REDIRECT", "DONE"] {
            if decisionWord.contains(candidate), let decision = ContinueDecision(rawValue: candidate) {
                return (decision, reason)
            }
        }

        logger.warning("Could not parse decision from response: \(text.prefix(200))")
        return (.done, "Could not parse model response")
    }
}
