import Foundation

/// Data required to render a session-end Telegram notification.
public struct SessionNotificationData {
    let sessionId: String
    let cwd: String
    let gitBranch: String?
    let startTime: Date?
    let lastActivity: Date?
    let turnCount: Int
    let lastUserPrompt: String?
    let aiNarrative: String?
    let promptSummary: String?
}

/// Pure-function utilities for Telegram HTML formatting and fence-aware message chunking.
/// Ported from the TypeScript format.ts, fences.ts, and formatter.ts in claude-telegram-sync.
public enum TelegramFormatter {

    /// Maximum message length for Telegram Bot API.
    static let telegramMaxLength = 4096

    // MARK: - HTML Escaping

    /// Escape HTML special characters for Telegram's HTML parse mode.
    static func escapeHtml(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Project Name & Duration

    /// Derive a human-readable project name from the workspace path.
    /// Uses the last path component (folder name). Strips git-town worktree suffixes.
    static func projectName(_ cwd: String) -> String {
        let trimmed = cwd.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        let parts = trimmed.split(separator: "/").map(String.init)
        let folder = parts.last ?? "unknown"
        return folder.replacingOccurrences(of: "\\.worktree-.*$", with: "", options: .regularExpression)
    }

    /// Format duration between two dates in human-readable form.
    static func formatDuration(from start: Date, to end: Date) -> String {
        let diff = Int(end.timeIntervalSince(start))
        let seconds = max(0, diff)
        let minutes = seconds / 60
        let hours = minutes / 60
        if hours > 0 {
            return "\(hours)h \(minutes % 60)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds % 60)s"
        } else {
            return "\(seconds)s"
        }
    }

    // MARK: - Meta-Tag & Skill Expansion Stripping

    /// Strip Claude Code meta tags from user prompt text (slash command wrappers, system reminders).
    static func stripMetaTags(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "<command-message>[^<]*</command-message>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "<command-name>[^<]*</command-name>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "<command-args>[^<]*</command-args>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "<local-command-caveat>[^<]*</local-command-caveat>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "<local-command-stdout>[^<]*</local-command-stdout>", with: "", options: .regularExpression)
        // Remove system reminders (multiline — use dotMatchesLineSeparators)
        if let regex = try? NSRegularExpression(pattern: "<system-reminder>[\\s\\S]*?</system-reminder>", options: [.dotMatchesLineSeparators]) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Strip skill-injected expansion content appended after the user's real prompt.
    /// Skill expansions (e.g. /ru encourage) append instructions after \n\n,
    /// typically starting with bold uppercase, markdown headers, or block formatting.
    static func stripSkillExpansion(_ text: String) -> String {
        guard let range = text.range(of: "\n\n") else { return text }
        let afterBreak = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        let pattern = "^(\\*\\*[A-Z]|#{1,4}\\s|---\\s*\\n|>\\s|-\\s\\[|TRIGGERS\\b)"
        if afterBreak.range(of: pattern, options: .regularExpression) != nil {
            return String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    // MARK: - Markdown to HTML Conversion

    /// Convert a subset of Markdown to Telegram HTML.
    /// Handles: code blocks (```), inline code (`), bold (**), italic (*), links [text](url).
    /// Code blocks are processed first to avoid inline pattern interference.
    /// File references are wrapped as the final step (matching legacy TS pipeline).
    static func markdownToTelegramHtml(_ markdown: String) -> String {
        var result = ""
        let chars = Array(markdown)
        var i = 0

        while i < chars.count {
            // Check for fenced code blocks: ```
            if i + 2 < chars.count && chars[i] == "`" && chars[i+1] == "`" && chars[i+2] == "`" {
                var j = i + 3
                while j < chars.count && chars[j] != "\n" { j += 1 }
                let infoString = String(chars[(i+3)..<j]).trimmingCharacters(in: .whitespaces)

                var closeIdx: Int? = nil
                var k = j + 1
                while k + 2 < chars.count {
                    if chars[k] == "`" && chars[k+1] == "`" && chars[k+2] == "`" {
                        closeIdx = k
                        break
                    }
                    k += 1
                }

                if let close = closeIdx {
                    let codeContent: String
                    if j < chars.count {
                        codeContent = String(chars[(j+1)..<close])
                    } else {
                        codeContent = ""
                    }
                    if infoString.isEmpty {
                        result += "<pre>" + escapeHtml(codeContent) + "</pre>"
                    } else {
                        result += "<pre><code class=\"language-\(escapeHtml(infoString))\">" + escapeHtml(codeContent) + "</code></pre>"
                    }
                    i = close + 3
                    if i < chars.count && chars[i] == "\n" { i += 1 }
                    continue
                }
            }

            // Check for inline code: `
            if chars[i] == "`" {
                var j = i + 1
                while j < chars.count && chars[j] != "`" && chars[j] != "\n" { j += 1 }
                if j < chars.count && chars[j] == "`" {
                    let code = String(chars[(i+1)..<j])
                    result += "<code>" + escapeHtml(code) + "</code>"
                    i = j + 1
                    continue
                }
            }

            // Check for bold: **text**
            if i + 1 < chars.count && chars[i] == "*" && chars[i+1] == "*" {
                var j = i + 2
                while j + 1 < chars.count {
                    if chars[j] == "*" && chars[j+1] == "*" { break }
                    j += 1
                }
                if j + 1 < chars.count && chars[j] == "*" && chars[j+1] == "*" {
                    let content = String(chars[(i+2)..<j])
                    result += "<b>" + content + "</b>"
                    i = j + 2
                    continue
                }
            }

            // Check for italic: *text* (single asterisk, not followed by another)
            if chars[i] == "*" && (i + 1 >= chars.count || chars[i+1] != "*") {
                var j = i + 1
                while j < chars.count && chars[j] != "*" && chars[j] != "\n" { j += 1 }
                if j < chars.count && chars[j] == "*" {
                    let content = String(chars[(i+1)..<j])
                    result += "<i>" + content + "</i>"
                    i = j + 1
                    continue
                }
            }

            // Check for links: [text](url)
            if chars[i] == "[" {
                var j = i + 1
                while j < chars.count && chars[j] != "]" && chars[j] != "\n" { j += 1 }
                if j < chars.count && chars[j] == "]" && j + 1 < chars.count && chars[j+1] == "(" {
                    var k = j + 2
                    while k < chars.count && chars[k] != ")" && chars[k] != "\n" { k += 1 }
                    if k < chars.count && chars[k] == ")" {
                        let linkText = String(chars[(i+1)..<j])
                        let url = String(chars[(j+2)..<k])
                        result += "<a href=\"\(escapeHtml(url))\">\(escapeHtml(linkText))</a>"
                        i = k + 1
                        continue
                    }
                }
            }

            // Default: escape and append
            let ch = chars[i]
            switch ch {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.append(ch)
            }
            i += 1
        }

        return wrapFileReferencesInHtml(result)
    }

    // MARK: - HTML Tag Stripping

    /// Strip HTML tags from text (plain text fallback for send failures).
    static func stripHtmlTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    // MARK: - Session Notification Rendering

    /// Render the full Telegram HTML notification for a session event.
    /// Port of renderMessage() from formatter.ts.
    static func renderSessionNotification(_ data: SessionNotificationData) -> String {
        let sessionIdShort = String(data.sessionId.prefix(8))
        let cwdDisplay = data.cwd.replacingOccurrences(of: "/Users/[^/]+", with: "~", options: .regularExpression)

        // Clean the last prompt
        let rawPrompt: String
        if let prompt = data.lastUserPrompt {
            rawPrompt = stripSkillExpansion(stripMetaTags(prompt))
        } else {
            rawPrompt = ""
        }

        let PROMPT_DISPLAY_MAX = 800
        let wasCondensed = data.promptSummary != nil && rawPrompt.count > PROMPT_DISPLAY_MAX
        let lastPrompt: String
        if wasCondensed, let summary = data.promptSummary {
            lastPrompt = summary
        } else if rawPrompt.count > PROMPT_DISPLAY_MAX {
            lastPrompt = String(rawPrompt.prefix(PROMPT_DISPLAY_MAX)) + "..."
        } else {
            lastPrompt = rawPrompt
        }

        // Duration
        let duration: String
        if let start = data.startTime, let end = data.lastActivity {
            duration = formatDuration(from: start, to: end)
        } else {
            duration = ""
        }

        // Build metadata line: project | path | session | branch | duration | turns
        var metaParts: [String] = []
        metaParts.append("<b>\(escapeHtml(projectName(data.cwd)))</b>")
        metaParts.append("<code>\(escapeHtml(cwdDisplay))</code>")
        metaParts.append("<code>\(escapeHtml(sessionIdShort))</code>")
        if let branch = data.gitBranch, !branch.isEmpty {
            metaParts.append("<code>\(escapeHtml(branch))</code>")
        }
        if !duration.isEmpty {
            metaParts.append(escapeHtml(duration))
        }
        if data.turnCount > 1 {
            metaParts.append("\(data.turnCount) turns")
        }
        let metaLine = metaParts.joined(separator: " | ")

        // Summary block
        let summaryBlock: String
        if let narrative = data.aiNarrative, !narrative.isEmpty {
            summaryBlock = "\n<b>Summary</b>:\n\(escapeHtml(narrative))\n"
        } else {
            summaryBlock = ""
        }

        // Assemble
        var message = metaLine
        if !lastPrompt.isEmpty {
            message += "\n\n<b>Last Prompt</b>"
            if wasCondensed { message += " <i>(condensed)</i>" }
            message += ":\n<i>\(escapeHtml(lastPrompt))</i>"
        }
        message += summaryBlock

        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
