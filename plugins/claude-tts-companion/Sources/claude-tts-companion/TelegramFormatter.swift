import Foundation

/// Data required to render a session-end Telegram notification.
struct SessionNotificationData {
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
enum TelegramFormatter {

    /// Maximum message length for Telegram Bot API.
    static let telegramMaxLength = 4096

    // MARK: - HTML Escaping

    /// Escape HTML special characters for Telegram's HTML parse mode.
    static func escapeHtml(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Fence Span Parsing

    /// A span of text enclosed in a fenced code block (``` or ~~~).
    struct FenceSpan {
        let start: Int      // character offset of opening fence line
        let end: Int        // character offset past the closing fence line (or end of text)
        let openLine: String
        let marker: String  // the fence characters (e.g. "```" or "~~~")
        let indent: String  // leading whitespace of the opening fence
    }

    /// Parse all fenced code block spans in the given text.
    /// Walks line-by-line matching CommonMark fence patterns: up to 3 spaces indent, then 3+ backticks or tildes.
    static func parseFenceSpans(_ text: String) -> [FenceSpan] {
        let chars = Array(text)
        var spans: [FenceSpan] = []
        var lineStart = 0
        var openFence: (start: Int, line: String, marker: String, indent: String, markerLen: Int)?

        func processLine(_ lineChars: ArraySlice<Character>) {
            let line = String(lineChars)

            // Try to match fence pattern: /^( {0,3})(`{3,}|~{3,})(.*)$/
            var idx = lineChars.startIndex
            var indentCount = 0
            while idx < lineChars.endIndex && lineChars[idx] == " " && indentCount < 3 {
                idx = lineChars.index(after: idx)
                indentCount += 1
            }
            let indent = String(repeating: " ", count: indentCount)

            guard idx < lineChars.endIndex else {
                lineStart += lineChars.count + 1 // +1 for newline
                return
            }

            let fenceChar = lineChars[idx]
            guard fenceChar == "`" || fenceChar == "~" else {
                lineStart += lineChars.count + 1
                return
            }

            var markerLen = 0
            let markerStart = idx
            while idx < lineChars.endIndex && lineChars[idx] == fenceChar {
                idx = lineChars.index(after: idx)
                markerLen += 1
            }

            guard markerLen >= 3 else {
                lineStart += lineChars.count + 1
                return
            }

            let marker = String(lineChars[markerStart..<lineChars.index(markerStart, offsetBy: markerLen)])

            if let open = openFence {
                // Check if this is a closing fence: same character, at least as many, no info string
                let restAfterMarker = String(lineChars[idx...]).trimmingCharacters(in: .whitespaces)
                if fenceChar == open.marker.first! && markerLen >= open.markerLen && restAfterMarker.isEmpty {
                    let endOffset = lineStart + lineChars.count + 1
                    spans.append(FenceSpan(
                        start: open.start,
                        end: min(endOffset, chars.count),
                        openLine: open.line,
                        marker: open.marker,
                        indent: open.indent
                    ))
                    openFence = nil
                }
            } else {
                // Opening fence -- backtick fences must not have backticks in the info string
                if fenceChar == "`" {
                    let rest = String(lineChars[idx...])
                    if rest.contains("`") {
                        lineStart += lineChars.count + 1
                        return
                    }
                }
                openFence = (start: lineStart, line: line, marker: marker, indent: indent, markerLen: markerLen)
            }

            lineStart += lineChars.count + 1
        }

        // Split into lines and process
        var currentLineStart = chars.startIndex
        lineStart = 0
        for i in chars.indices {
            if chars[i] == "\n" {
                processLine(chars[currentLineStart..<i])
                currentLineStart = chars.index(after: i)
            }
        }
        // Process last line (no trailing newline)
        if currentLineStart <= chars.endIndex {
            let finalLine = chars[currentLineStart..<chars.endIndex]
            if !finalLine.isEmpty {
                processLine(finalLine)
            }
        }

        // If there's an unclosed fence, emit a span to end of text
        if let open = openFence {
            spans.append(FenceSpan(
                start: open.start,
                end: chars.count,
                openLine: open.line,
                marker: open.marker,
                indent: open.indent
            ))
        }

        return spans
    }

    /// Find the fence span containing the given character index, if any.
    /// Uses strict greater-than on start to match legacy TS behavior.
    static func findFenceSpanAt(_ spans: [FenceSpan], index: Int) -> FenceSpan? {
        spans.first { index > $0.start && index < $0.end }
    }

    /// Check whether a break at the given character index is safe (not inside a fenced code block).
    static func isSafeFenceBreak(_ spans: [FenceSpan], index: Int) -> Bool {
        findFenceSpanAt(spans, index: index) == nil
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

    // MARK: - File Reference Wrapping

    /// File extensions that share TLDs and commonly appear in code/documentation.
    private static let fileExtensionsWithTLD: Set<String> = [
        "md", "go", "py", "pl", "sh", "am", "at", "be", "cc"
    ]

    private static var fileExtensionsPattern: String {
        fileExtensionsWithTLD.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
    }

    /// Check if a link was auto-generated from a bare filename (e.g. README.md -> http://README.md).
    private static func isAutoLinkedFileRef(href: String, label: String) -> Bool {
        let stripped = href.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
        guard stripped == label else { return false }
        guard let dotIndex = label.lastIndex(of: "."), dotIndex > label.startIndex else { return false }
        let ext = String(label[label.index(after: dotIndex)...]).lowercased()
        guard fileExtensionsWithTLD.contains(ext) else { return false }
        // Reject if any path segment before the filename contains a dot (looks like a real domain)
        let segments = label.split(separator: "/").map(String.init)
        if segments.count > 1 {
            for i in 0..<(segments.count - 1) {
                if segments[i].contains(".") { return false }
            }
        }
        return true
    }

    /// Wrap a standalone file reference in <code> tags, skipping URL-prefixed paths.
    private static func wrapStandaloneFileRef(match: String, prefix: String, filename: String) -> String {
        if filename.hasPrefix("//") { return match }
        if prefix.range(of: "https?://$", options: .regularExpression) != nil { return match }
        return "\(prefix)<code>\(escapeHtml(filename))</code>"
    }

    /// Wrap file references in a text segment, only when outside code/pre/anchor tags.
    private static func wrapSegmentFileRefs(_ text: String, codeDepth: Int, preDepth: Int, anchorDepth: Int) -> String {
        guard !text.isEmpty, codeDepth == 0, preDepth == 0, anchorDepth == 0 else { return text }

        let extPat = fileExtensionsPattern

        // Wrap standalone file refs: word.ext patterns
        let fileRefPattern = "(^|[^a-zA-Z0-9_\\-/])([a-zA-Z0-9_.\\-/]+\\.(?:\(extPat)))(?=$|[^a-zA-Z0-9_\\-/])"
        var result = text
        if let regex = try? NSRegularExpression(pattern: fileRefPattern, options: [.caseInsensitive]) {
            let mutableResult = NSMutableString(string: result)
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            // Process matches in reverse to preserve offsets
            for m in matches.reversed() {
                let fullRange = m.range
                let prefixRange = m.range(at: 1)
                let filenameRange = m.range(at: 2)
                guard let fullSwiftRange = Range(fullRange, in: result),
                      let prefixSwiftRange = Range(prefixRange, in: result),
                      let filenameSwiftRange = Range(filenameRange, in: result) else { continue }
                let fullMatch = String(result[fullSwiftRange])
                let prefix = String(result[prefixSwiftRange])
                let filename = String(result[filenameSwiftRange])
                let replacement = wrapStandaloneFileRef(match: fullMatch, prefix: prefix, filename: filename)
                mutableResult.replaceCharacters(in: fullRange, with: replacement)
            }
            result = mutableResult as String
        }

        // Wrap orphaned TLD patterns: single-char.ext
        let orphanPattern = "([^a-zA-Z0-9]|^)([A-Za-z]\\.(?:\(extPat)))(?=[^a-zA-Z0-9/]|$)"
        if let regex = try? NSRegularExpression(pattern: orphanPattern, options: []) {
            let mutableResult = NSMutableString(string: result)
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for m in matches.reversed() {
                let prefixRange = m.range(at: 1)
                let tldRange = m.range(at: 2)
                guard let prefixSwiftRange = Range(prefixRange, in: result),
                      let tldSwiftRange = Range(tldRange, in: result) else { continue }
                let prefix = String(result[prefixSwiftRange])
                let tld = String(result[tldSwiftRange])
                // Skip if prefix is ">" (inside tag)
                if prefix == ">" { continue }
                let replacement = "\(prefix)<code>\(escapeHtml(tld))</code>"
                let fullRange = NSRange(
                    location: prefixRange.location,
                    length: tldRange.location + tldRange.length - prefixRange.location
                )
                mutableResult.replaceCharacters(in: fullRange, with: replacement)
            }
            result = mutableResult as String
        }

        return result
    }

    /// Wraps bare file references (filename.ext where ext shares a TLD) in <code> tags.
    /// Runs after markdown->HTML conversion. Skips inside <code>, <pre>, and <a> tags.
    static func wrapFileReferencesInHtml(_ html: String) -> String {
        // De-linkify auto-generated anchors where href matches label
        let autoLinkPattern = "<a\\s+href=\"https?://([^\"]+)\"[^>]*>\\1</a>"
        var deLinkified = html
        if let regex = try? NSRegularExpression(pattern: autoLinkPattern, options: [.caseInsensitive]) {
            let mutableStr = NSMutableString(string: html)
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for m in matches.reversed() {
                let labelRange = m.range(at: 1)
                guard let labelSwiftRange = Range(labelRange, in: html) else { continue }
                let label = String(html[labelSwiftRange])
                if isAutoLinkedFileRef(href: "http://\(label)", label: label) {
                    mutableStr.replaceCharacters(in: m.range, with: "<code>\(escapeHtml(label))</code>")
                }
            }
            deLinkified = mutableStr as String
        }

        // Walk token-by-token tracking nesting depth, only wrap in unprotected segments
        let htmlTagPattern = "(</?)([ a-zA-Z][a-zA-Z0-9-]*)\\b[^>]*?>"
        guard let tagRegex = try? NSRegularExpression(pattern: htmlTagPattern, options: [.caseInsensitive]) else {
            return deLinkified
        }

        var codeDepth = 0
        var preDepth = 0
        var anchorDepth = 0
        var result = ""
        var lastIndex = deLinkified.startIndex

        let nsString = deLinkified as NSString
        let matches = tagRegex.matches(in: deLinkified, range: NSRange(location: 0, length: nsString.length))

        for m in matches {
            let tagStart = deLinkified.index(deLinkified.startIndex, offsetBy: m.range.location)
            let tagEnd = deLinkified.index(deLinkified.startIndex, offsetBy: m.range.location + m.range.length)

            // Process text before this tag
            if lastIndex < tagStart {
                let segment = String(deLinkified[lastIndex..<tagStart])
                result += wrapSegmentFileRefs(segment, codeDepth: codeDepth, preDepth: preDepth, anchorDepth: anchorDepth)
            }

            // Determine tag type
            guard let prefixRange = Range(m.range(at: 1), in: deLinkified),
                  let nameRange = Range(m.range(at: 2), in: deLinkified) else {
                result += String(deLinkified[tagStart..<tagEnd])
                lastIndex = tagEnd
                continue
            }
            let isClosing = String(deLinkified[prefixRange]) == "</"
            let tagName = String(deLinkified[nameRange]).lowercased()

            if tagName == "code" {
                codeDepth = isClosing ? max(0, codeDepth - 1) : codeDepth + 1
            } else if tagName == "pre" {
                preDepth = isClosing ? max(0, preDepth - 1) : preDepth + 1
            } else if tagName == "a" {
                anchorDepth = isClosing ? max(0, anchorDepth - 1) : anchorDepth + 1
            }

            result += String(deLinkified[tagStart..<tagEnd])
            lastIndex = tagEnd
        }

        // Process remaining text after last tag
        if lastIndex < deLinkified.endIndex {
            let segment = String(deLinkified[lastIndex...])
            result += wrapSegmentFileRefs(segment, codeDepth: codeDepth, preDepth: preDepth, anchorDepth: anchorDepth)
        }

        return result
    }

    // MARK: - Fence-Aware Chunking

    /// Split text into chunks that fit within Telegram's message limit, respecting fenced code blocks.
    /// When forced to split inside a fence, closes and re-opens the fence across chunks.
    static func chunkTelegramHtml(_ text: String, limit: Int = telegramMaxLength) -> [String] {
        guard !text.isEmpty else { return [] }
        guard text.count > limit else { return [text] }

        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let spans = parseFenceSpans(normalized)

        // Phase 1: Split on paragraph boundaries (blank lines) outside fences
        let paragraphPattern = "\n[\\t ]*\n+"
        var parts: [String] = []
        var lastIdx = normalized.startIndex

        if let regex = try? NSRegularExpression(pattern: paragraphPattern, options: []) {
            let nsStr = normalized as NSString
            let matches = regex.matches(in: normalized, range: NSRange(location: 0, length: nsStr.length))
            for m in matches {
                let matchStart = m.range.location
                if !isSafeFenceBreak(spans, index: matchStart) { continue }
                let partEnd = normalized.index(normalized.startIndex, offsetBy: matchStart)
                parts.append(String(normalized[lastIdx..<partEnd]))
                lastIdx = normalized.index(normalized.startIndex, offsetBy: matchStart + m.range.length)
            }
        }
        parts.append(String(normalized[lastIdx...]))

        // Phase 2: Pack paragraphs into chunks, split oversized ones with fence awareness
        var chunks: [String] = []
        var current = ""

        for part in parts {
            let paragraph = part.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            guard !paragraph.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            if !current.isEmpty && (current + "\n\n" + paragraph).count <= limit {
                current += "\n\n" + paragraph
                continue
            }

            if !current.isEmpty {
                chunks.append(current)
                current = ""
            }

            if paragraph.count <= limit {
                current = paragraph
                continue
            }

            // Oversized paragraph: fence-aware splitting
            chunks.append(contentsOf: chunkMarkdownText(paragraph, limit: limit))
        }

        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    /// Fence-aware text chunking with fence close/reopen.
    /// Prefers newline > whitespace > hard break.
    private static func chunkMarkdownText(_ text: String, limit: Int) -> [String] {
        guard !text.isEmpty else { return [] }
        guard text.count > limit else { return [text] }

        var chunks: [String] = []
        var remaining = text

        while remaining.count > limit {
            let spans = parseFenceSpans(remaining)
            let windowEnd = remaining.index(remaining.startIndex, offsetBy: min(limit, remaining.count))
            let window = String(remaining[..<windowEnd])

            // Find safe break point (outside fences, prefer newline > whitespace)
            let softBreak = pickSafeBreakIndex(window, spans: spans)
            var breakIdx = softBreak > 0 ? softBreak : limit

            // Check if we're breaking inside a fence
            var fenceToSplit: FenceSpan? = nil
            if !isSafeFenceBreak(spans, index: breakIdx) {
                if let fence = findFenceSpanAt(spans, index: breakIdx) {
                    let closeLine = "\(fence.indent)\(fence.marker)"
                    let maxIdx = limit - (closeLine.count + 1)

                    if maxIdx <= 0 {
                        // Close-line too long, fall back to hard break
                        breakIdx = limit
                    } else {
                        // Find a newline inside the fence to break at
                        let minProgress = min(remaining.count, fence.start + fence.openLine.count + 2)
                        var lastNl = remaining[..<remaining.index(remaining.startIndex, offsetBy: min(max(0, limit - closeLine.count - 1) + 1, remaining.count))].lastIndex(of: "\n")
                        var pickedNewline = false

                        while let nl = lastNl {
                            let candidate = remaining.distance(from: remaining.startIndex, to: remaining.index(after: nl))
                            if candidate < minProgress { break }
                            let atFence = findFenceSpanAt(spans, index: candidate)
                            if let atFence = atFence, atFence.start == fence.start {
                                breakIdx = max(1, candidate)
                                pickedNewline = true
                                break
                            }
                            // Search for previous newline
                            let searchEnd = nl
                            if searchEnd > remaining.startIndex {
                                lastNl = remaining[..<searchEnd].lastIndex(of: "\n")
                            } else {
                                lastNl = nil
                            }
                        }

                        if !pickedNewline {
                            if minProgress > limit - closeLine.count {
                                breakIdx = limit
                            } else {
                                breakIdx = max(minProgress, maxIdx)
                                fenceToSplit = findFenceSpanAt(spans, index: breakIdx)
                                if let f = fenceToSplit, f.start != fence.start {
                                    fenceToSplit = nil
                                }
                            }
                        } else {
                            let atBreak = findFenceSpanAt(spans, index: breakIdx)
                            fenceToSplit = (atBreak != nil && atBreak!.start == fence.start) ? atBreak : nil
                        }
                    }
                }
            }

            let breakPoint = remaining.index(remaining.startIndex, offsetBy: min(breakIdx, remaining.count))
            var rawChunk = String(remaining[..<breakPoint])
            guard !rawChunk.isEmpty else { break }

            let brokeOnSep = breakIdx < remaining.count && remaining[breakPoint].isWhitespace
            let nextStartOffset = min(remaining.count, breakIdx + (brokeOnSep ? 1 : 0))
            let nextStartIndex = remaining.index(remaining.startIndex, offsetBy: nextStartOffset)
            var next = String(remaining[nextStartIndex...])

            if let fence = fenceToSplit {
                // Close the fence in this chunk, re-open in next
                let closeLine = "\(fence.indent)\(fence.marker)"
                if rawChunk.hasSuffix("\n") {
                    rawChunk = "\(rawChunk)\(closeLine)"
                } else {
                    rawChunk = "\(rawChunk)\n\(closeLine)"
                }
                next = "\(fence.openLine)\n\(next)"
            } else {
                // Strip leading newlines from continuation
                var i = next.startIndex
                while i < next.endIndex && next[i] == "\n" {
                    i = next.index(after: i)
                }
                if i > next.startIndex {
                    next = String(next[i...])
                }
            }

            chunks.append(rawChunk)
            remaining = next
        }

        if !remaining.isEmpty {
            chunks.append(remaining)
        }

        return chunks
    }

    /// Split text into paragraphs on double-newline boundaries that are outside fenced code blocks.
    private static func splitIntoParagraphs(_ text: String, spans: [FenceSpan]) -> [String] {
        let chars = Array(text)
        var paragraphs: [String] = []
        var paragraphStart = 0

        var i = 0
        while i < chars.count {
            if chars[i] == "\n" && i + 1 < chars.count {
                var j = i + 1
                if j < chars.count && chars[j] == "\t" { j += 1 }
                if j < chars.count && chars[j] == "\n" {
                    if isSafeFenceBreak(spans, index: i) {
                        while j < chars.count && (chars[j] == "\n" || chars[j] == "\t" || chars[j] == " ") {
                            j += 1
                        }
                        let para = String(chars[paragraphStart..<i]).trimmingCharacters(in: .newlines)
                        if !para.isEmpty {
                            paragraphs.append(para)
                        }
                        paragraphStart = j
                        i = j
                        continue
                    }
                }
            }
            i += 1
        }

        if paragraphStart < chars.count {
            let para = String(chars[paragraphStart...]).trimmingCharacters(in: .newlines)
            if !para.isEmpty {
                paragraphs.append(para)
            }
        }

        return paragraphs
    }

    /// Split an oversized paragraph into chunks, respecting fence boundaries.
    private static func splitOversizedParagraph(_ text: String, limit: Int, spans: [FenceSpan]) -> [String] {
        return chunkMarkdownText(text, limit: limit)
    }

    /// Pick the best break index within a window, preferring newline > whitespace, outside fenced blocks.
    static func pickSafeBreakIndex(_ window: String, spans: [FenceSpan]) -> Int {
        let chars = Array(window)
        var lastNewline = -1
        var lastWhitespace = -1

        for i in 0..<chars.count {
            guard isSafeFenceBreak(spans, index: i) else { continue }
            if chars[i] == "\n" {
                lastNewline = i
            } else if chars[i] == " " || chars[i] == "\t" {
                lastWhitespace = i
            }
        }

        if lastNewline > 0 { return lastNewline }
        if lastWhitespace > 0 { return lastWhitespace }
        return -1
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
