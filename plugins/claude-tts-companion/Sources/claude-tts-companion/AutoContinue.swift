import Foundation
import Logging

/// Decision output from evaluating a completed Claude Code session transcript.
///
/// The auto-continue evaluator uses MiniMax to analyze session content and determine
/// what action should follow (EVAL-01).
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

/// Per-session state persisted across stop-hook invocations (EVAL-04).
///
/// State files stored at `~/.claude/hooks/state/auto-continue-{sessionId}.json`.
/// Tracks iteration counts, sweep lifecycle, and manual intervention detection.
struct AutoContinueState: Codable {
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
struct EvaluationResult {
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

/// Evaluates completed Claude Code session transcripts via MiniMax to decide the next action.
///
/// Full legacy evaluation engine ported from TypeScript auto-continue.ts.
/// Includes per-session state tracking, sibling JSONL plan discovery,
/// transcript budget building, deterministic sweep fallback, and multi-line decision parsing.
final class AutoContinueEvaluator: @unchecked Sendable {

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

    // MARK: - Prompts (EVAL-01, EVAL-03)

    /// System prompt for MiniMax evaluation -- verbatim from legacy TypeScript (EVAL-01).
    static let SYSTEM_PROMPT = """
        You are an autonomous session evaluator. You receive a session transcript and optionally a plan file. Your job: determine the single best next action.

        RESPOND WITH EXACTLY ONE LINE in the format:
        DECISION|<your crafted instruction or summary>

        Where DECISION is one of:

        CONTINUE \u{2014} Work remains. Your instruction text becomes the user's next message to Claude, so make it specific and actionable. Reference exact deliverables, files, or steps that are unfinished.

        SWEEP \u{2014} Primary work appears done but needs a final multi-agent review pass. Use when the main deliverables are complete but the session hasn't verified quality, updated documentation/memory, or cross-checked against the original request.

        REDIRECT \u{2014} Claude drifted from the original request. Your instruction should re-anchor Claude to what the user actually asked for. Reference the original request and explain what went off track.

        DONE \u{2014} All requested work is complete, or Claude is yielding to the user. Return DONE when the task is finished or when Claude is clearly waiting for user direction.

        PRIORITY ORDER (highest to lowest):
          CONTINUE > REDIRECT > SWEEP > DONE

        Your job is to maximize Claude's output. The deterministic safety boundaries (max iterations, max runtime) handle the "stop eventually" concern \u{2014} your job is to find reasons to keep working, not reasons to stop.

        MANDATORY DONE SIGNALS (override all other rules \u{2014} return DONE immediately):
        - Claude asks the user what to do next ("What would you like to work on?", "Is there anything else?", "Want me to continue into Phase X?", "Shall I proceed?")
        - Claude presents options and waits for user choice
        - Claude says the task is complete and offers to help with something new
        - The last assistant message is a question directed at the user requesting input or a decision
        These patterns mean Claude has YIELDED CONTROL to the user. Continuing would bypass the user's agency. ALWAYS return DONE for these patterns, even if you think more work could be done \u{2014} the user will decide.

        INSTRUCTION TEXT RULES:
        - Your instruction text becomes the user's next message to Claude verbatim
        - It MUST be a direct, imperative instruction (e.g., "Update the memory file with the gap-fill results")
        - NEVER output raw commands, file paths, code snippets, or shell commands as the instruction
        - NEVER extract or echo content from the transcript as your instruction
        - BAD: "tail -20 /tmp/orchestrator.log" \u{2014} this is a command, not an instruction
        - GOOD: "Check the orchestrator logs on bigblack to verify it's running correctly"

        EVALUATION RULES:
        1. Read the ENTIRE transcript to understand what was requested and what was delivered.
        2. If a plan file is provided, use it as the authority for what needs to be done.
        3. If no plan file exists (marked "NO_PLAN"), infer deliverables from the user's messages in the transcript. Look for numbered lists, checkboxes, "Output:" sections, multi-step prompts, or explicit requests.
        4. For multi-deliverable prompts (e.g., "Output: updated plan, updated memory, completed deliverables"), check EACH deliverable individually. If any is missing \u{2192} CONTINUE.
        5. ACTIVELY LOOK for reasons to continue. Check for: incomplete deliverables, code that lacks tests, missing documentation updates, memory files that should be updated, GitHub issues that could be commented on or closed, error handling gaps, edge cases, opportunities to improve code quality.
        6. Even if the primary task appears done, look for adjacent value: Did Claude update project memory? Did Claude commit the changes? Are there GitHub issues to update? Could the solution be more robust?
        7. SWEEP when coding work is done but quality verification, documentation, or cross-checking hasn't happened yet.
        8. REDIRECT when the last few turns show Claude working on something unrelated to the original request.
        9. DONE when Claude is asking the user a question, presenting choices, or explicitly yielding control. Do NOT continue past a yield point.
        10. Your instruction text is critical \u{2014} Claude will receive it verbatim as a user message. Write it as a direct, imperative instruction \u{2014} never a raw command or code snippet.
        """

    /// 5-step sweep pipeline prompt -- verbatim from legacy TypeScript (EVAL-03).
    static let SWEEP_PROMPT = """
        Execute this 5-step sweep pipeline. Each step feeds context into the next \u{2014} run them in order.

        ## Step 1: Blind Spot Analysis (diagnostic foundation)
        Run /devops-tools:session-blind-spots to get a 50-perspective MiniMax consensus analysis of this session. This surfaces what we missed, overlooked, or got wrong \u{2014} security gaps, untested changes, stale docs, silent failures, architectural issues. Save the ranked findings \u{2014} every subsequent step should cross-reference them.

        ## Step 2: Plan Audit + Gap Identification (uses Step 1)
        Review the plan file against what was actually delivered in this session. Cross-reference the blind spot findings from Step 1 to distinguish real gaps from noise. Read our project memory files and relevant GitHub Issues. For each plan item, classify as: \u{2705} done, \u{26A0}\u{FE0F} partially done (specify what's missing), or \u{274C} not started. Also identify implicit deliverables the user likely expected but didn't explicitly list (e.g., commits, memory updates, issue hygiene).

        ## Step 3: FOSS Discovery (uses Step 2 gaps)
        For each gap or hand-rolled solution identified in Step 2, search ~/fork-tools and the internet for SOTA well-maintained FOSS that could replace or improve it. Fork (not clone) promising projects to ~/fork-tools and deep-dive them. Adopt lightweight ideations from heavy FOSS rather than importing wholesale. Be expansive \u{2014} I don't mind scope creeps, but keep changes aligned with the plan's goals.

        ## Step 4: Execute Remaining Work (uses Steps 2 + 3)
        Fix gaps identified in Step 2 using FOSS insights from Step 3 where applicable. Complete partially-done deliverables. For gaps that can't be resolved now, document them clearly. Be thorough \u{2014} finish what's necessary.

        ## Step 5: Reconcile + Summarize (uses all above)
        - Update the plan file to reflect current state
        - Update project memory with session learnings
        - GitHub Issues: close completed issues with evidence, update in-progress issues, file new issues for deferred gaps from Step 2
        - Output: a concise list of what you changed and why, blind spot findings that were actionable, and any deferred items with their new issue numbers
        """

    /// Subagent orchestration tools to exclude from tool breakdown
    private static let SUBAGENT_TOOLS: Set<String> = [
        "Agent", "Task", "TaskCreate", "TaskGet", "TaskList",
        "TaskOutput", "TaskUpdate", "TaskStop"
    ]

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
            // Handle migration: totalIterations defaults to iteration if missing
            // (JSONDecoder handles this via Codable defaults, but guard legacy files)
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

    // MARK: - Plan Discovery (EVAL-02)

    /// Discover plan file by scanning transcript content and sibling JSONL files.
    ///
    /// Search order:
    /// 1. Current transcript for `.claude/plans/{name}.md` references
    /// 2. Sibling JSONL files in the same directory (most-recent-first by mtime)
    ///    - Prefer main plans (no "-agent-" in filename) over sub-plans
    ///    - If sibling's sweep_done=true, return nil (plan is finished)
    ///
    /// - Parameter transcriptPath: Absolute path to the session's transcript.jsonl
    /// - Returns: Absolute path to the discovered plan file, or nil
    func discoverPlanFromTranscript(transcriptPath: String) -> String? {
        let fm = FileManager.default
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/terryli"
        let planRegexPattern = "\\.claude/plans/([a-zA-Z0-9_.-]+\\.md)"

        guard let planRegex = try? NSRegularExpression(pattern: planRegexPattern) else {
            return nil
        }

        // 1. Search current transcript
        if let data = fm.contents(atPath: transcriptPath),
           let raw = String(data: data, encoding: .utf8) {
            let range = NSRange(raw.startIndex..., in: raw)
            let matches = planRegex.matches(in: raw, range: range)
            for match in matches {
                if let captureRange = Range(match.range(at: 1), in: raw) {
                    let filename = String(raw[captureRange])
                    let planPath = "\(home)/.claude/plans/\(filename)"
                    if fm.fileExists(atPath: planPath) {
                        return planPath
                    }
                }
            }
        }

        // 2. Fallback: sibling JSONL files in same directory
        let dir = (transcriptPath as NSString).deletingLastPathComponent
        let currentFile = (transcriptPath as NSString).lastPathComponent

        do {
            let siblings = try fm.contentsOfDirectory(atPath: dir)
            let jsonlFiles = siblings
                .filter { $0.hasSuffix(".jsonl") && $0 != currentFile }
                .compactMap { name -> (name: String, mtime: Date)? in
                    let fullPath = "\(dir)/\(name)"
                    guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                          let mtime = attrs[.modificationDate] as? Date else { return nil }
                    return (name: name, mtime: mtime)
                }
                .sorted { $0.mtime > $1.mtime }

            for sibling in jsonlFiles {
                let siblingPath = "\(dir)/\(sibling.name)"
                guard let data = fm.contents(atPath: siblingPath),
                      let raw = String(data: data, encoding: .utf8) else { continue }

                let range = NSRange(raw.startIndex..., in: raw)
                let matches = planRegex.matches(in: raw, range: range)
                var candidates: [String] = []

                for match in matches {
                    if let captureRange = Range(match.range(at: 1), in: raw) {
                        let filename = String(raw[captureRange])
                        let planPath = "\(home)/.claude/plans/\(filename)"
                        if fm.fileExists(atPath: planPath) {
                            candidates.append(planPath)
                        }
                    }
                }

                guard !candidates.isEmpty else { continue }

                // Prefer main plans (no -agent- suffix) over agent sub-plans
                let planPath = candidates.first { !(($0 as NSString).lastPathComponent).contains("-agent-") }
                    ?? candidates[0]

                // Check if this sibling's plan is finished (sweep_done)
                let siblingSessionId = (sibling.name as NSString).deletingPathExtension
                let siblingStateFile = Self.stateFilePath(sessionId: siblingSessionId)
                if fm.fileExists(atPath: siblingStateFile) {
                    let siblingState = loadState(sessionId: siblingSessionId)
                    if siblingState.sweepDone {
                        logger.info("Last plan found in sibling \(sibling.name.prefix(8)) but sweep_done -- plan finished")
                        return nil  // definitive: last plan is done, no active plan
                    }
                }

                logger.info("Last plan discovered in sibling \(sibling.name.prefix(8)): \((planPath as NSString).lastPathComponent)")
                return planPath
            }
        } catch {
            // fall through
        }

        return nil
    }

    // MARK: - Transcript Building

    /// Build budget-limited transcript text from conversation turns.
    ///
    /// Ported from legacy TypeScript `buildTranscriptText()`.
    func buildTranscriptText(turns: [ConversationTurn], budget: Int) -> String {
        let maxPromptChars = 2000
        let maxResponseChars = 4000
        let maxToolResultChars = 1500

        let turnTexts = turns.enumerated().map { (i, t) in
            let p = t.prompt.count > maxPromptChars
                ? String(t.prompt.prefix(maxPromptChars)) + " [truncated]"
                : t.prompt
            let r = t.response.count > maxResponseChars
                ? String(t.response.prefix(maxResponseChars)) + " [truncated]"
                : (t.response.isEmpty ? "[no text response]" : t.response)
            let tools = t.toolSummary != nil ? "\nTools used: \(t.toolSummary!)" : ""
            let results: String
            if let tr = t.toolResults, !tr.isEmpty {
                let truncatedResults = tr.count > maxToolResultChars
                    ? String(tr.prefix(maxToolResultChars)) + " [truncated]"
                    : tr
                results = "\nKey tool outputs:\n\(truncatedResults)"
            } else {
                results = ""
            }
            return "=== Turn \(i + 1) ===\nUser request:\n\(p)\n\nOutcome:\n\(r)\(tools)\(results)"
        }

        var transcript = ""
        for t in turnTexts {
            if transcript.count + t.count > budget {
                transcript += "\n\n[remaining turns omitted for length]"
                break
            }
            transcript += (transcript.isEmpty ? "" : "\n\n") + t
        }
        return transcript
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

        return parseDecision(result.text)
    }

    // MARK: - Decision Parsing

    /// Parse a MiniMax response into a decision and reason.
    ///
    /// Multi-line aware: scans lines for decision keywords.
    /// Handles pipe-delimited format: `DECISION|reason text`.
    /// Defaults to DONE on empty or unparseable response (fail-open).
    func parseDecision(_ text: String) -> (decision: ContinueDecision, reason: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            logger.warning("Empty model response, defaulting to DONE (fail-open)")
            return (.done, "empty model response")
        }

        let lines = trimmed.components(separatedBy: "\n")
        for i in 0..<lines.count {
            let line = lines[i]
            let firstLineReason = line.contains("|")
                ? line.components(separatedBy: "|").dropFirst().joined(separator: "|").trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            let remainingLines = lines[(i + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

            // Direct match: line starts with decision keyword
            if let direct = matchDecision(line) {
                let fullReason = [firstLineReason, remainingLines]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                return (direct, fullReason)
            }

            // Indirect match: check each pipe-delimited field
            if line.contains("|") {
                let fields = line.components(separatedBy: "|")
                for (fieldIdx, field) in fields.enumerated() {
                    if let found = matchDecision(field) {
                        // Get rest of line after this field
                        let rest = fields[(fieldIdx + 1)...].joined(separator: "|").trimmingCharacters(in: .whitespacesAndNewlines)
                        let lineReason = rest.isEmpty ? firstLineReason : rest
                        let fullReason = [lineReason, remainingLines]
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n")
                        return (found, fullReason)
                    }
                }
            }
        }

        logger.warning("No decision found in response, defaulting to DONE: \(String(trimmed.prefix(100)))")
        return (.done, "no decision line found")
    }

    /// Check if a string starts with a known decision keyword.
    private func matchDecision(_ s: String) -> ContinueDecision? {
        let u = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if u.hasPrefix("CONT") { return .continue }
        if u.hasPrefix("SWEEP") { return .sweep }
        if u.hasPrefix("REDIR") { return .redirect }
        if u.hasPrefix("DONE") { return .done }
        return nil
    }

    // MARK: - Deterministic Sweep Detection (EVAL-06)

    /// Detect if a plan needs a sweep based on checkbox state.
    ///
    /// Returns true when:
    /// - All checkboxes are checked and no review section exists
    /// - Plan has no checkboxes at all (non-checkbox plans always sweep on first DONE)
    ///
    /// Returns false when:
    /// - No plan or "NO_PLAN"
    /// - Plan still has unchecked items
    func detectSweepNeeded(planContent: String) -> Bool {
        if planContent.isEmpty || planContent == "NO_PLAN" { return false }

        let hasUnchecked = planContent.range(of: "\\[ \\]", options: .regularExpression) != nil
        let hasChecked = planContent.range(of: "\\[x\\]", options: [.regularExpression, .caseInsensitive]) != nil

        // Checkbox-based plans: sweep if all checked, none unchecked
        if hasChecked && !hasUnchecked {
            let hasSweepSection = planContent.range(
                of: "##\\s*(final review|sweep|review|post-implementation)",
                options: [.regularExpression, .caseInsensitive]
            ) != nil
            return !hasSweepSection
        }

        // Non-checkbox plans: always sweep on first DONE
        if !hasChecked && !hasUnchecked {
            return true
        }

        return false  // Has unchecked items -- MiniMax should have said CONTINUE
    }

    // MARK: - Tool Breakdown

    /// Aggregate tool counts across all turns, excluding subagent orchestration tools.
    ///
    /// Returns (totalCalls, breakdownString) where breakdownString is "Bash61 Edit54 Read55" format.
    func buildToolBreakdown(turns: [ConversationTurn]) -> (totalCalls: Int, breakdown: String) {
        var toolAgg: [String: Int] = [:]

        for turn in turns {
            guard let summary = turn.toolSummary else { continue }
            for part in summary.components(separatedBy: ", ") {
                // Match "ToolName x3" or "ToolName" format
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if let regex = try? NSRegularExpression(pattern: "^(\\w+)(?:\\s+x(\\d+))?$"),
                   let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
                    if let nameRange = Range(match.range(at: 1), in: trimmed) {
                        let name = String(trimmed[nameRange])
                        if Self.SUBAGENT_TOOLS.contains(name) { continue }
                        let count: Int
                        if match.range(at: 2).location != NSNotFound,
                           let countRange = Range(match.range(at: 2), in: trimmed) {
                            count = Int(trimmed[countRange]) ?? 1
                        } else {
                            count = 1
                        }
                        toolAgg[name, default: 0] += count
                    }
                }
            }
        }

        let totalCalls = toolAgg.values.reduce(0, +)
        let breakdown = toolAgg
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { "\($0.key)\($0.value)" }
            .joined(separator: " ")

        return (totalCalls, breakdown)
    }

    // MARK: - Checkbox Progress Helpers

    /// Count checked and total checkboxes in plan content.
    static func checkboxCounts(_ planContent: String) -> (checked: Int, total: Int) {
        let checkedPattern = try? NSRegularExpression(pattern: "\\[x\\]", options: .caseInsensitive)
        let uncheckedPattern = try? NSRegularExpression(pattern: "\\[ \\]")
        let range = NSRange(planContent.startIndex..., in: planContent)

        let checked = checkedPattern?.numberOfMatches(in: planContent, range: range) ?? 0
        let unchecked = uncheckedPattern?.numberOfMatches(in: planContent, range: range) ?? 0
        return (checked: checked, total: checked + unchecked)
    }

    /// Build a progress bar string (filled blocks + empty blocks).
    static func progressBar(done: Int, total: Int, width: Int = 10) -> String {
        guard total > 0 else { return "" }
        let filled = Int((Double(done) / Double(total) * Double(width)).rounded())
        return String(repeating: "\u{2588}", count: filled)
            + String(repeating: "\u{2591}", count: width - filled)
    }

    /// Extract the first `# Title` line from plan content.
    static func extractPlanTitle(_ planContent: String) -> String {
        if let regex = try? NSRegularExpression(pattern: "^#\\s+(.+)$", options: .anchorsMatchLines),
           let match = regex.firstMatch(in: planContent, range: NSRange(planContent.startIndex..., in: planContent)),
           let titleRange = Range(match.range(at: 1), in: planContent) {
            var title = String(planContent[titleRange])
            // Strip "Plan: " prefix if present
            if let prefixRange = title.range(of: "^Plan:\\s*", options: [.regularExpression, .caseInsensitive]) {
                title.removeSubrange(prefixRange)
            }
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "Untitled Plan"
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
            // Manual intervention -- reset auto-iteration streak
            if state.iteration > 0 {
                logger.info("Manual intervention detected (iteration=\(state.iteration)->0), resetting streak (total=\(state.totalIterations), sweep_injected=\(state.sweepInjected), sweep_done=\(state.sweepDone))")
            }
            state.iteration = 0
            // sweep_injected/sweep_done are NOT reset -- sweep is a per-session-lifetime event
            state.sweepNotified = false
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            state.startedAt = formatter.string(from: Date())
            state.lastBlockedAt = nil
            saveState(sessionId: sessionId, state: state)
        }

        let elapsedMin = (Date().timeIntervalSince1970 - isoToEpoch(state.startedAt)) / 60.0

        // Absolute cap on total iterations across all streaks
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

        // Per-streak limit
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

        // Max runtime (only after at least 1 iteration)
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

        // Sweep done -- allow stop
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

        // Parse transcript and discover plan
        let entries = TranscriptParser.parse(filePath: transcriptPath)
        let turns = TranscriptParser.entriesToTurns(entries)
        let turnCount = turns.count

        let planPath = discoverPlanFromTranscript(transcriptPath: transcriptPath)
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

        // Build tool breakdown
        let (toolCalls, toolBreakdown) = buildToolBreakdown(turns: turns)

        // Handle 0-turn session with un-swept sibling plan
        if turnCount == 0 {
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

        let transcript = buildTranscriptText(turns: turns, budget: Self.TRANSCRIPT_BUDGET)

        // MiniMax evaluation
        let evalDecision: ContinueDecision
        let evalReason: String
        do {
            let sweepInProgress = state.sweepInjected && !state.sweepDone
            let result = try await evaluateCompletion(
                transcript: transcript,
                planContent: planContent,
                sweepInProgress: sweepInProgress
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
        if effectiveDecision == .done && detectSweepNeeded(planContent: planContent) && !state.sweepInjected {
            effectiveDecision = .sweep
            effectiveReason = "Deterministic sweep: all checkboxes done, no review section"
        }

        // Act on decision and update state
        let shouldBlock: Bool
        let blockReason: String?

        switch effectiveDecision {
        case .continue, .redirect:
            state.iteration += 1
            state.totalIterations += 1
            state.lastBlockedAt = Date().timeIntervalSince1970 * 1000
            saveState(sessionId: sessionId, state: state)
            shouldBlock = true
            blockReason = effectiveReason.isEmpty ? "Continue as planned" : effectiveReason
        case .sweep:
            state.sweepInjected = true
            state.iteration += 1
            state.totalIterations += 1
            state.lastBlockedAt = Date().timeIntervalSince1970 * 1000
            saveState(sessionId: sessionId, state: state)
            shouldBlock = true
            blockReason = Self.SWEEP_PROMPT
        case .done:
            if state.sweepInjected {
                state.sweepDone = true
                saveState(sessionId: sessionId, state: state)
            }
            shouldBlock = false
            blockReason = nil
        }

        return EvaluationResult(
            decision: effectiveDecision,
            reason: effectiveReason,
            shouldBlock: shouldBlock,
            blockReason: blockReason,
            state: state,
            planPath: planPath,
            planContent: planContent,
            turnCount: turnCount,
            toolCalls: toolCalls,
            toolBreakdown: toolBreakdown,
            errors: 0,
            gitBranch: nil,
            elapsedMin: elapsedMin
        )
    }

    // MARK: - Helpers

    /// Convert an ISO 8601 string to epoch seconds.
    private func isoToEpoch(_ isoString: String) -> Double {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) {
            return date.timeIntervalSince1970
        }
        // Try without fractional seconds
        let basic = ISO8601DateFormatter()
        if let date = basic.date(from: isoString) {
            return date.timeIntervalSince1970
        }
        return Date().timeIntervalSince1970
    }
}
