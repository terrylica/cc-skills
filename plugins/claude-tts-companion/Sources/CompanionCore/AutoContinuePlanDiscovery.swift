import Foundation
import Logging

/// Plan file discovery, transcript text building, and tool breakdown aggregation.
///
/// Extracted from AutoContinueEvaluator to isolate file-system scanning
/// and text budget logic from the evaluation pipeline.
enum AutoContinuePlanDiscovery {

    private static let logger = Logger(label: "auto-continue.plan")

    // MARK: - Plan Discovery (EVAL-02)

    /// Discover plan file by scanning transcript content and sibling JSONL files.
    ///
    /// Search order:
    /// 1. Current transcript for `.claude/plans/{name}.md` references
    /// 2. Sibling JSONL files in the same directory (most-recent-first by mtime)
    ///    - Prefer main plans (no "-agent-" in filename) over sub-plans
    ///    - If sibling's sweep_done=true, return nil (plan is finished)
    ///
    /// - Parameters:
    ///   - transcriptPath: Absolute path to the session's transcript.jsonl
    ///   - loadState: Closure to load state for a given session ID
    ///   - stateFilePath: Closure to get the state file path for a given session ID
    /// - Returns: Absolute path to the discovered plan file, or nil
    static func discoverPlanFromTranscript(
        transcriptPath: String,
        loadState: (String) -> AutoContinueState,
        stateFilePath: (String) -> String
    ) -> String? {
        let fm = FileManager.default
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/<you>"
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
                let siblingStateFile = stateFilePath(siblingSessionId)
                if fm.fileExists(atPath: siblingStateFile) {
                    let siblingState = loadState(siblingSessionId)
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
    static func buildTranscriptText(turns: [ConversationTurn], budget: Int) -> String {
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

    // MARK: - Tool Breakdown

    /// Subagent orchestration tools to exclude from tool breakdown
    private static let SUBAGENT_TOOLS: Set<String> = [
        "Agent", "Task", "TaskCreate", "TaskGet", "TaskList",
        "TaskOutput", "TaskUpdate", "TaskStop"
    ]

    /// Aggregate tool counts across all turns, excluding subagent orchestration tools.
    ///
    /// Returns (totalCalls, breakdownString) where breakdownString is "Bash61 Edit54 Read55" format.
    static func buildToolBreakdown(turns: [ConversationTurn]) -> (totalCalls: Int, breakdown: String) {
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
                        if SUBAGENT_TOOLS.contains(name) { continue }
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
    static func detectSweepNeeded(planContent: String) -> Bool {
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
}
