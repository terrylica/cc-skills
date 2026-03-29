import Foundation

// MARK: - File Reference Wrapping

extension TelegramFormatter {

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
}
