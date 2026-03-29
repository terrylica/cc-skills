// Right-click (two-finger tap) copies subtitle text + UUID wrapped in triple backticks.
// Also manages the subtle gray UUID label at the bottom-right of the subtitle panel.
import AppKit
import Logging

/// Handles UUID display and right-click copy-to-clipboard for the subtitle panel.
@MainActor
public final class SubtitleClipboard {

    private let logger = Logger(label: "subtitle-clipboard")

    /// The current text being displayed.
    var currentText: String = ""

    /// The UUID of the current TTS entry.
    var currentUUID: String = ""

    /// Subtle gray UUID label (bottom-right of subtitle panel).
    let uuidLabel: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.isEditable = false
        field.isBezeled = false
        field.drawsBackground = false
        field.textColor = NSColor(white: 0.4, alpha: 1.0)
        field.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        field.alignment = .right
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    /// Attach the UUID label to a container view (call once during panel setup).
    func attach(to container: NSView, trailingAnchor: NSLayoutXAxisAnchor, bottomAnchor: NSLayoutYAxisAnchor) {
        container.addSubview(uuidLabel)
        NSLayoutConstraint.activate([
            uuidLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            uuidLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    /// Update the UUID display and track current text for clipboard.
    func update(text: String, uuid: String) {
        currentText = text
        currentUUID = uuid
        uuidLabel.stringValue = uuid.isEmpty ? "" : uuid.prefix(8).description
    }

    /// Copy the current subtitle + UUID to clipboard as a fenced code block.
    func copyToClipboard() {
        guard !currentText.isEmpty else {
            logger.info("Nothing to copy — subtitle is empty")
            return
        }

        let block = """
        ```
        \(currentText)
        UUID: \(currentUUID)
        ```
        """

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(block, forType: .string)

        logger.info("Copied subtitle to clipboard: \(currentText.prefix(50))... UUID: \(currentUUID.prefix(8))")

        // Brief visual feedback: flash the UUID label
        let originalColor = uuidLabel.textColor
        uuidLabel.textColor = NSColor.systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.uuidLabel.textColor = originalColor
        }
    }
}
