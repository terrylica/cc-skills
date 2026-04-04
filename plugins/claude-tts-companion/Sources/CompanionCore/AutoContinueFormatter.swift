import Foundation

/// Telegram message formatting for auto-continue decisions and exit notifications (EVAL-05).
///
/// Ported from legacy TypeScript `formatDecisionMessage()` and `sendExitNotification()`.
enum AutoContinueFormatter {

    /// Decision icon mapping matching legacy TypeScript format.
    private static let decisionIcons: [ContinueDecision: String] = [
        .continue: "\u{1F504}",   // 🔄
        .sweep: "\u{1F9F9}",      // 🧹
        .redirect: "\u{21A9}\u{FE0F}",  // ↩️
        .done: "\u{2705}",        // ✅
    ]

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

    /// Format a Vancouver timezone timestamp matching legacy en-CA locale format.
    static func formatVancouverTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_CA")
        formatter.timeZone = TimeZone(identifier: "America/Vancouver")
        return formatter.string(from: Date())
    }

    /// Format a rich decision notification for Telegram (EVAL-05).
    ///
    /// Ported from legacy TypeScript `formatDecisionMessage()` (auto-continue.ts lines 448-533).
    /// Includes icon, reason, plan info with progress bar, compact session stats, and timestamp.
    static func formatDecisionMessage(
        result: EvaluationResult,
        sessionId: String,
        cwd: String,
        maxIterations: Int,
        maxRuntimeMin: Double
    ) -> String {
        let icon = decisionIcons[result.decision] ?? "\u{2705}"
        let decision = result.decision.rawValue

        let planTitle: String
        if let pc = result.planContent, pc != "NO_PLAN" {
            planTitle = TelegramFormatter.escapeHtml(extractPlanTitle(pc))
        } else {
            planTitle = "No Plan"
        }

        let shortSession = TelegramFormatter.escapeHtml(String(sessionId.prefix(8)))
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/terryli"
        let shortCwd = TelegramFormatter.escapeHtml(cwd.replacingOccurrences(of: home, with: "~"))

        let displayReason = String(result.reason.prefix(200))

        // Checkbox progress (only if plan uses checkboxes)
        let progressLine: String
        if let pc = result.planContent, pc != "NO_PLAN" {
            let (checked, total) = checkboxCounts(pc)
            if total > 0 {
                progressLine = "\(progressBar(done: checked, total: total)) <code>\(checked)/\(total) tasks</code>\n"
            } else {
                progressLine = ""
            }
        } else {
            progressLine = ""
        }

        // Timestamp in America/Vancouver timezone, en-CA locale format
        let timestamp = formatVancouverTimestamp()

        let escapedReason = TelegramFormatter.escapeHtml(displayReason)

        var lines: [String] = [
            "<b>\(icon) Auto-Continue: \(decision)</b>  <code>\(shortSession)</code>",
            "<i>\(escapedReason.isEmpty ? "MiniMax evaluated \(result.turnCount) turns across \(String(format: "%.0f", result.elapsedMin))m and determined session is complete" : escapedReason)</i>",
        ]

        if result.decision == .sweep {
            lines.append("\u{26A1} Sweep prompt injected")
        }

        // Plan section: only show when a real plan exists
        let hasPlan = planTitle != "No Plan"
        if hasPlan {
            lines.append("")
            lines.append("<b>\u{1F4CB} Plan</b>: \(planTitle)")
            if !progressLine.isEmpty {
                lines.append(progressLine.trimmingCharacters(in: .newlines))
            }
        }

        // Compact stats line: iteration | runtime | turns+tools | project
        let iterStr = "\(result.state.totalIterations)/\(maxIterations)"
        let runtimeStr = "\(String(format: "%.0f", result.elapsedMin))m"
        let toolStr = result.toolBreakdown.isEmpty ? "\(result.toolCalls)\u{2699}" : result.toolBreakdown
        let turnsToolsStr = "\(result.turnCount)T \(toolStr)\(result.errors > 0 ? " \(result.errors)\u{2717}" : "")"

        var statsLine = "\u{2022} #\(iterStr) \u{2022} \(runtimeStr) \u{2022} \(turnsToolsStr)"
        if let branch = result.gitBranch {
            statsLine += " \u{2022} <code>\(TelegramFormatter.escapeHtml(branch))</code>"
        }

        lines.append("")
        lines.append(statsLine)
        lines.append("\u{2022} <code>\(shortCwd)</code>")
        lines.append("<i>\(timestamp)</i>")

        var message = lines.joined(separator: "\n")

        // Truncation safety: strip progress bar first, then hard truncate
        if message.count > TelegramFormatter.telegramMaxLength {
            // Remove progress bar line
            if let progressPattern = try? NSRegularExpression(pattern: "\u{2588}[\u{2588}\u{2591}]*\\s*<code>\\d+/\\d+ tasks</code>\\n") {
                message = progressPattern.stringByReplacingMatches(
                    in: message,
                    range: NSRange(message.startIndex..., in: message),
                    withTemplate: ""
                )
            }

            if message.count > TelegramFormatter.telegramMaxLength {
                // Hard truncate at last newline before 4080, clean up broken HTML
                var cutPoint = 4080
                if let lastNewline = message.prefix(4080).lastIndex(of: "\n") {
                    let offset = message.distance(from: message.startIndex, to: lastNewline)
                    if offset >= 2000 {
                        cutPoint = offset
                    }
                }
                message = String(message.prefix(cutPoint))
                // Strip broken HTML entities at cut point
                if let brokenEntity = message.range(of: "&[^;]*$", options: .regularExpression) {
                    message.removeSubrange(brokenEntity)
                }
                // Strip broken HTML tags at cut point
                if let brokenTag = message.range(of: "<[^>]*$", options: .regularExpression) {
                    message.removeSubrange(brokenTag)
                }
                message += "\n\u{2026}"
            }
        }

        return message
    }

    /// Format a lightweight exit notification for early stops (EVAL-05).
    ///
    /// Ported from legacy TypeScript `sendExitNotification()` (auto-continue.ts lines 578-636).
    /// Used for limit reached, sweep complete, and error cases.
    static func formatExitMessage(
        reason: String,
        sessionId: String,
        cwd: String,
        state: AutoContinueState?,
        maxIterations: Int,
        maxRuntimeMin: Double
    ) -> String {
        let shortSession = TelegramFormatter.escapeHtml(String(sessionId.prefix(8)))
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/terryli"
        let shortCwd = TelegramFormatter.escapeHtml(cwd.replacingOccurrences(of: home, with: "~"))
        let timestamp = formatVancouverTimestamp()

        var statsStr = ""
        if let st = state {
            let elapsed = (Date().timeIntervalSince1970 - isoToEpoch(st.startedAt)) / 60.0
            statsStr = " \u{2022} #\(st.totalIterations)/\(maxIterations) \u{2022} \(String(format: "%.0f", elapsed))m"
        }

        let lines: [String] = [
            "<b>\u{23F9} Auto-Continue: STOP</b>  <code>\(shortSession)</code>",
            "<i>\(TelegramFormatter.escapeHtml(reason))</i>",
            "\u{2022} <code>\(shortCwd)</code>\(statsStr)",
            "<i>\(timestamp)</i>",
        ]

        return lines.joined(separator: "\n")
    }

    /// Convert an ISO 8601 string to epoch seconds.
    static func isoToEpoch(_ isoString: String) -> Double {
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
