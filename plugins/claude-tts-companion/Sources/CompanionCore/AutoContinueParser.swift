import Foundation
import Logging

/// Parses MiniMax evaluation responses into structured decisions.
///
/// Multi-line aware: scans lines for decision keywords.
/// Handles pipe-delimited format: `DECISION|reason text`.
/// Defaults to DONE on empty or unparseable response (fail-open).
enum AutoContinueParser {

    private static let logger = Logger(label: "auto-continue.parser")

    /// Parse a MiniMax response into a decision and reason.
    static func parseDecision(_ text: String) -> (decision: ContinueDecision, reason: String) {
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

        // Fallback pass: scan for decision keywords anywhere in text (case-insensitive).
        // This handles thinking-block content where the model writes unstructured reasoning
        // like "the decision should be DONE because..." rather than the pipe-delimited format.
        // Priority order: CONTINUE > SWEEP > REDIRECT > DONE (prefer action over inaction).
        let upper = trimmed.uppercased()
        let fallbackCandidates: [(keyword: String, decision: ContinueDecision)] = [
            ("CONTINUE", .continue),
            ("SWEEP", .sweep),
            ("REDIRECT", .redirect),
            ("DONE", .done),
        ]
        for (keyword, decision) in fallbackCandidates {
            // Match keyword at word boundary to avoid false positives
            // (e.g. "continued" should not match "CONTINUE")
            let pattern = "\\b\(keyword)\\b"
            if upper.range(of: pattern, options: .regularExpression) != nil {
                logger.info("Fallback decision match: \(keyword) found in unstructured response")
                // Extract a meaningful reason snippet from surrounding context
                let reason = extractFallbackReason(from: trimmed, keyword: keyword)
                return (decision, reason)
            }
        }

        logger.warning("No decision found in response, defaulting to DONE: \(String(trimmed.prefix(100)))")
        return (.done, "no decision line found")
    }

    /// Check if a string starts with a known decision keyword.
    static func matchDecision(_ s: String) -> ContinueDecision? {
        let u = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if u.hasPrefix("CONT") { return .continue }
        if u.hasPrefix("SWEEP") { return .sweep }
        if u.hasPrefix("REDIR") { return .redirect }
        if u.hasPrefix("DONE") { return .done }
        return nil
    }

    /// Extract a meaningful reason snippet when the fallback keyword scan fires.
    ///
    /// Instead of the opaque "extracted from unstructured response (thinking block fallback)",
    /// grab the sentence or clause containing the keyword to give the user actual context.
    /// Falls back to a cleaned first line of the response if extraction fails.
    static func extractFallbackReason(from text: String, keyword: String) -> String {
        let maxReasonLen = 200

        // Try to find the sentence containing the keyword (case-insensitive)
        let pattern = "[^.!?\\n]*\\b\(keyword)\\b[^.!?\\n]*[.!?]?"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range, in: text) {
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.count > 10 && sentence.count <= maxReasonLen {
                return sentence
            }
            if sentence.count > maxReasonLen {
                return String(sentence.prefix(maxReasonLen)) + "..."
            }
        }

        // Fallback: use the first non-empty line, trimmed
        let firstLine = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        if !firstLine.isEmpty {
            let cleaned = firstLine.count > maxReasonLen
                ? String(firstLine.prefix(maxReasonLen)) + "..."
                : firstLine
            return cleaned
        }

        return "(no details available)"
    }
}
