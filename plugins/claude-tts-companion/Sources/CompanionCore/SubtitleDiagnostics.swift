// Diagnostic logging for subtitle panel layout and wrapping.
import AppKit
import Logging

/// Extension providing telemetry logging for SubtitlePanel.
/// Since the panel has sharingType = .none (invisible to screenshots),
/// log-based telemetry is the only way to verify multi-line rendering.
extension SubtitlePanel {

    func logDiagnostics(label: String, text: String) {
        let panelFrame = frame
        let tfFrame = textField.frame
        let prefMaxWidth = textField.preferredMaxLayoutWidth
        let maxLines = textField.maximumNumberOfLines

        let measuredWidth = SubtitleChunker.measureWidth(text, fontSizeName: currentFontSizeName)
        let availableWidth = tfFrame.width

        let renderedLines: Int
        if !text.isEmpty {
            let attrStr: NSAttributedString
            if textField.attributedStringValue.length > 0 {
                attrStr = textField.attributedStringValue
            } else {
                attrStr = NSAttributedString(
                    string: text,
                    attributes: [.font: SubtitleStyle.regularFont]
                )
            }
            let measuredAttr = NSMutableAttributedString(attributedString: attrStr)
            if measuredAttr.length > 0 {
                let ps = NSMutableParagraphStyle()
                ps.lineBreakMode = .byWordWrapping
                measuredAttr.addAttribute(
                    .paragraphStyle, value: ps,
                    range: NSRange(location: 0, length: measuredAttr.length)
                )
            }
            let textStorage = NSTextStorage(attributedString: measuredAttr)
            let layoutManager = NSLayoutManager()
            let textContainer = NSTextContainer(
                size: NSSize(width: availableWidth, height: .greatestFiniteMagnitude)
            )
            textContainer.lineFragmentPadding = 0
            layoutManager.addTextContainer(textContainer)
            textStorage.addLayoutManager(layoutManager)

            layoutManager.ensureLayout(for: textContainer)
            var lineCount = 0
            var index = 0
            let glyphRange = layoutManager.glyphRange(for: textContainer)
            while index < NSMaxRange(glyphRange) {
                var lineRange = NSRange()
                layoutManager.lineFragmentRect(forGlyphAt: index, effectiveRange: &lineRange)
                lineCount += 1
                index = NSMaxRange(lineRange)
            }
            renderedLines = lineCount
        } else {
            renderedLines = 0
        }

        logger.info("""
            [\(label)] panel=\(Int(panelFrame.width))x\(Int(panelFrame.height)) \
            tf=\(Int(tfFrame.width))x\(Int(tfFrame.height)) \
            prefMaxW=\(Int(prefMaxWidth)) maxLines=\(maxLines) \
            measuredW=\(Int(measuredWidth)) availW=\(Int(availableWidth)) \
            renderedLines=\(renderedLines) \
            wraps=\(measuredWidth > availableWidth) \
            text=\"\(text.prefix(80))\"
            """)
    }
}
