import AppKit
import Logging

/// A floating panel that displays scrollable caption history with timestamps.
/// Uses NSTextView for reliable word wrapping (NSTableView row heights are unreliable).
@MainActor
public final class CaptionHistoryPanel: NSPanel {

    private let logger = Logger(label: "caption-history-panel")
    private let captionHistory: CaptionHistory
    private var entries: [CaptionEntry] = []
    private var isUserScrolling = false

    private let scrollView: NSScrollView
    private let textView: NSTextView

    private let isoFormatter: ISO8601DateFormatter = { ISO8601DateFormatter() }()
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    init(captionHistory: CaptionHistory) {
        self.captionHistory = captionHistory

        // Build text view (read-only, word-wrapping, dark background)
        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = true
        tv.backgroundColor = NSColor(white: 0.1, alpha: 0.95)
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineBreakMode = .byWordWrapping
        self.textView = tv

        // Build scroll view
        let sv = NSScrollView()
        sv.documentView = tv
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.drawsBackground = true
        sv.backgroundColor = NSColor(white: 0.1, alpha: 0.95)
        self.scrollView = sv

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let panelWidth: CGFloat = 500
        let panelHeight: CGFloat = 500
        let x = screenFrame.origin.x + (screenFrame.width - panelWidth) / 2
        let y = screenFrame.origin.y + (screenFrame.height - panelHeight) / 2

        super.init(
            contentRect: NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        title = "Caption History"
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        sharingType = .readOnly
        ignoresMouseEvents = false
        isMovableByWindowBackground = true
        minSize = NSSize(width: 300, height: 200)
        appearance = NSAppearance(named: .darkAqua)
        isOpaque = false
        backgroundColor = NSColor(white: 0.1, alpha: 0.95)

        guard let content = contentView else { return }
        content.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(scrollViewDidScroll(_:)),
            name: NSScrollView.didLiveScrollNotification, object: scrollView
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Public API

    func show() {
        reloadEntries()
        scrollToBottom()
        orderFrontRegardless()
        logger.info("Caption history panel shown with \(entries.count) entries")
    }

    func hide() { orderOut(nil) }

    func refresh() {
        reloadEntries()
        if !isUserScrolling { scrollToBottom() }
    }

    // MARK: - Rendering

    private func reloadEntries() {
        entries = captionHistory.getAll()
        renderText()
    }

    private func renderText() {
        let result = NSMutableAttributedString()
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let textFont = NSFont.systemFont(ofSize: 13)
        let timeColor = NSColor.secondaryLabelColor
        let textColor = NSColor.labelColor

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.paragraphSpacing = 8

        for entry in entries {
            let time = formatTime(entry.timestamp)

            // Sync telemetry as suffix
            var syncInfo = ""
            if let wc = entry.wordCount, let oc = entry.onsetCount {
                let match = wc == oc ? "✓" : "⚠️"
                syncInfo = "  [\(match) w:\(wc) o:\(oc)"
                if let dur = entry.audioDuration {
                    syncInfo += " \(String(format: "%.1f", dur))s"
                }
                syncInfo += " \(entry.uuid.prefix(8))]"
            }

            // Time prefix
            let timeStr = NSAttributedString(string: "\(time)  ", attributes: [
                .font: timeFont,
                .foregroundColor: timeColor,
                .paragraphStyle: paragraphStyle,
            ])

            // Caption text
            let textStr = NSAttributedString(string: entry.text, attributes: [
                .font: textFont,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle,
            ])

            // Telemetry suffix
            let infoStr = NSAttributedString(string: "\(syncInfo)\n", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: paragraphStyle,
            ])

            result.append(timeStr)
            result.append(textStr)
            result.append(infoStr)
        }

        textView.textStorage?.setAttributedString(result)
    }

    private func scrollToBottom() {
        guard !entries.isEmpty else { return }
        textView.scrollToEndOfDocument(nil)
    }

    private func formatTime(_ isoString: String) -> String {
        guard let date = isoFormatter.date(from: isoString) else { return "--:--" }
        return timeFormatter.string(from: date)
    }

    @objc private func scrollViewDidScroll(_ notification: Notification) {
        guard let clipView = scrollView.contentView as? NSClipView,
              let documentView = scrollView.documentView else { return }
        let contentHeight = documentView.frame.height
        let scrollOffset = clipView.bounds.origin.y
        let visibleHeight = clipView.bounds.height
        let atBottom = scrollOffset + visibleHeight >= contentHeight - 20
        isUserScrolling = !atBottom
    }
}
